// EPIC-11 · Purge of the deactivated accounts (owner decision 2026-10-03:
// an account is deactivated at once, then deleted for good 30 days later
// unless its user reactivates it).
//
// Called once a day by pg_cron (public.run_account_purge, through pg_net)
// with the shared secret `x-purge-secret` (Supabase secret
// PURGE_ACCOUNTS_SECRET = Vault secret purge_accounts_secret), or by the
// staff (runbook docs/runbooks/suppression-de-compte.md). For each due
// account: journal row (account_purge_begin, re-checks the account is still
// deactivated and due), files of every bucket under <user id>/ (the Storage
// API: SQL cannot delete objects), then the auth user — whose deletion
// cascades to the profile, properties, lots, notifications, agent and
// vision journals — and the end of the journal row. Idempotent: a purge
// that stopped half-way resumes on the next run.

/** A file of a Storage bucket. */
export type StoredFile = { bucket: string; name: string };

/** Data access of the purge (service role). */
export interface PurgeDb {
  /** Users whose deletion date has passed, oldest first. */
  dueAccounts(limit: number): Promise<string[]>;

  /** Starts (or resumes) a purge; false when no longer due. */
  begin(userId: string): Promise<boolean>;

  /** Every file of [userId], in every bucket. */
  files(userId: string): Promise<StoredFile[]>;

  /** Deletes [names] of [bucket]. */
  removeFiles(bucket: string, names: string[]): Promise<void>;

  /** Deletes the auth user (done when it no longer exists). */
  deleteUser(userId: string): Promise<void>;

  /** Ends the journal row of the purge. */
  finish(userId: string, filesCount: number): Promise<void>;
}

/** Outcome of a run (counts only: no identifier is returned). */
export type PurgeReport = { purged: number; skipped: number; failed: number };

/** Most accounts purged per run. */
export const MAX_ACCOUNTS_PER_RUN = 20;

/** Most files removed per Storage call. */
export const FILES_PER_CALL = 100;

/** Purges the accounts that are due, one after the other. */
export async function purgeDueAccounts(
  db: PurgeDb,
  log: (message: string) => void = console.error,
): Promise<PurgeReport> {
  const report: PurgeReport = { purged: 0, skipped: 0, failed: 0 };
  for (const userId of await db.dueAccounts(MAX_ACCOUNTS_PER_RUN)) {
    try {
      if (await purgeAccount(db, userId)) {
        report.purged++;
      } else {
        report.skipped++;
      }
    } catch (error) {
      report.failed++;
      log(`purge-accounts: ${userId}: ${error instanceof Error ? error.message : error}`);
    }
  }
  return report;
}

/** Purges [userId]: false when it is no longer due (reactivated). */
export async function purgeAccount(db: PurgeDb, userId: string): Promise<boolean> {
  if (!await db.begin(userId)) return false;
  const files = await db.files(userId);
  const byBucket = new Map<string, string[]>();
  for (const file of files) {
    // Defensive: never outside the user's folder.
    if (!file.name.startsWith(`${userId}/`)) continue;
    byBucket.set(file.bucket, [...byBucket.get(file.bucket) ?? [], file.name]);
  }
  let removed = 0;
  for (const [bucket, names] of byBucket) {
    for (let start = 0; start < names.length; start += FILES_PER_CALL) {
      const chunk = names.slice(start, start + FILES_PER_CALL);
      await db.removeFiles(bucket, chunk);
      removed += chunk.length;
    }
  }
  await db.deleteUser(userId);
  await db.finish(userId, removed);
  return true;
}

/** Constant-time comparison of two strings. */
export function sameSecret(a: string, b: string): boolean {
  const left = new TextEncoder().encode(a);
  const right = new TextEncoder().encode(b);
  let difference = left.length ^ right.length;
  for (let i = 0; i < Math.max(left.length, right.length); i++) {
    difference |= (left[i] ?? 0) ^ (right[i] ?? 0);
  }
  return difference === 0;
}

function json(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

/** HTTP entry point: POST with the `x-purge-secret` header. */
export async function handlePurgeAccounts(
  request: Request,
  deps: { secret: string | undefined; db: () => PurgeDb; log?: (message: string) => void },
): Promise<Response> {
  if (request.method !== "POST") return json(405, { error: "method_not_allowed" });
  if (!deps.secret) return json(500, { error: "not_configured" });
  const given = request.headers.get("x-purge-secret") ?? "";
  if (!sameSecret(given, deps.secret)) return json(401, { error: "unauthorized" });
  try {
    return json(200, await purgeDueAccounts(deps.db(), deps.log));
  } catch (error) {
    (deps.log ?? console.error)(
      `purge-accounts: ${error instanceof Error ? error.message : error}`,
    );
    return json(500, { error: "server_error" });
  }
}
