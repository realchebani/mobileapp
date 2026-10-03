// EPIC-11: purge of the deactivated accounts, with an in-memory PurgeDb.
import { assert, assertEquals } from "jsr:@std/assert@1";
import {
  FILES_PER_CALL,
  handlePurgeAccounts,
  MAX_ACCOUNTS_PER_RUN,
  purgeAccount,
  type PurgeDb,
  purgeDueAccounts,
  sameSecret,
  type StoredFile,
} from "../_shared/account/purge.ts";

const U1 = "11111111-1111-4111-8111-111111111111";
const U2 = "22222222-2222-4222-8222-222222222222";

class FakePurgeDb implements PurgeDb {
  due: string[] = [U1];
  notDue = new Set<string>();
  stored: StoredFile[] = [];
  users = new Set<string>([U1, U2]);
  calls: string[] = [];
  finished = new Map<string, number>();
  failOn: string | null = null;

  dueAccounts(limit: number): Promise<string[]> {
    this.calls.push(`due ${limit}`);
    return Promise.resolve(this.due.slice(0, limit));
  }

  begin(userId: string): Promise<boolean> {
    this.calls.push(`begin ${userId}`);
    if (this.failOn === "begin") return Promise.reject(new Error("boom"));
    return Promise.resolve(!this.notDue.has(userId));
  }

  files(userId: string): Promise<StoredFile[]> {
    this.calls.push(`files ${userId}`);
    return Promise.resolve(this.stored.filter((f) => f.name.startsWith(userId)));
  }

  removeFiles(bucket: string, names: string[]): Promise<void> {
    this.calls.push(`remove ${bucket} ${names.length}`);
    if (this.failOn === "remove") return Promise.reject(new Error("storage down"));
    this.stored = this.stored.filter((f) => !(f.bucket === bucket && names.includes(f.name)));
    return Promise.resolve();
  }

  deleteUser(userId: string): Promise<void> {
    this.calls.push(`delete ${userId}`);
    this.users.delete(userId);
    return Promise.resolve();
  }

  finish(userId: string, filesCount: number): Promise<void> {
    this.calls.push(`finish ${userId} ${filesCount}`);
    this.finished.set(userId, filesCount);
    return Promise.resolve();
  }
}

Deno.test("purgeAccount removes the files in chunks, then the user", async () => {
  const db = new FakePurgeDb();
  db.stored = [
    ...Array.from({ length: FILES_PER_CALL + 1 }, (_, i) => ({
      bucket: "property-documents",
      name: `${U1}/p/${i}.pdf`,
    })),
    { bucket: "valuation-reports", name: `${U1}/p/report.pdf` },
    { bucket: "property-documents", name: `${U2}/p/other.pdf` },
  ];
  assert(await purgeAccount(db, U1));
  assertEquals(db.calls, [
    `begin ${U1}`,
    `files ${U1}`,
    `remove property-documents ${FILES_PER_CALL}`,
    "remove property-documents 1",
    "remove valuation-reports 1",
    `delete ${U1}`,
    `finish ${U1} ${FILES_PER_CALL + 2}`,
  ]);
  assertEquals(db.stored, [{ bucket: "property-documents", name: `${U2}/p/other.pdf` }]);
  assert(!db.users.has(U1));
});

Deno.test("purgeAccount never removes a file outside the user's folder", async () => {
  const db = new FakePurgeDb();
  db.files = () => Promise.resolve([{ bucket: "b", name: `${U2}/x` }]);
  assert(await purgeAccount(db, U1));
  assertEquals(db.calls.filter((c) => c.startsWith("remove")), []);
  assertEquals(db.finished.get(U1), 0);
});

Deno.test("purgeAccount skips an account reactivated meanwhile", async () => {
  const db = new FakePurgeDb();
  db.notDue.add(U1);
  assertEquals(await purgeAccount(db, U1), false);
  assertEquals(db.calls, [`begin ${U1}`]);
  assert(db.users.has(U1));
});

Deno.test("purgeAccount keeps the user when a file cannot be removed", async () => {
  const db = new FakePurgeDb();
  db.stored = [{ bucket: "b", name: `${U1}/f` }];
  db.failOn = "remove";
  let error: unknown;
  try {
    await purgeAccount(db, U1);
  } catch (e) {
    error = e;
  }
  assert(error instanceof Error);
  assert(db.users.has(U1));
  assertEquals(db.finished.size, 0);
});

Deno.test("purgeDueAccounts reports counts and goes on after a failure", async () => {
  const db = new FakePurgeDb();
  db.due = [U1, U2, "33333333-3333-4333-8333-333333333333"];
  db.notDue.add(U2);
  const begin = db.begin.bind(db);
  db.begin = (userId) => userId.startsWith("3") ? Promise.reject(new Error("boom")) : begin(userId);
  const logs: string[] = [];
  const report = await purgeDueAccounts(db, (m) => logs.push(m));
  assertEquals(report, { purged: 1, skipped: 1, failed: 1 });
  assertEquals(db.calls[0], `due ${MAX_ACCOUNTS_PER_RUN}`);
  assertEquals(logs.length, 1);
  assert(logs[0].includes("boom"));
});

Deno.test("purgeDueAccounts logs a non-Error failure", async () => {
  const db = new FakePurgeDb();
  db.begin = () => Promise.reject("plain");
  const logs: string[] = [];
  assertEquals(await purgeDueAccounts(db, (m) => logs.push(m)), {
    purged: 0,
    skipped: 0,
    failed: 1,
  });
  assert(logs[0].endsWith("plain"));
});

Deno.test("sameSecret compares whole strings", () => {
  assert(sameSecret("abc", "abc"));
  assert(!sameSecret("abc", "abd"));
  assert(!sameSecret("abc", "abcd"));
  assert(!sameSecret("", "a"));
});

function post(secret?: string, method = "POST"): Request {
  return new Request("https://x/functions/v1/purge-accounts", {
    method,
    headers: secret === undefined ? {} : { "x-purge-secret": secret },
  });
}

Deno.test("handlePurgeAccounts checks the method, the configuration and the secret", async () => {
  const db = () => new FakePurgeDb();
  assertEquals((await handlePurgeAccounts(post("s", "GET"), { secret: "s", db })).status, 405);
  assertEquals((await handlePurgeAccounts(post("s"), { secret: undefined, db })).status, 500);
  assertEquals((await handlePurgeAccounts(post(), { secret: "s", db })).status, 401);
  assertEquals((await handlePurgeAccounts(post("t"), { secret: "s", db })).status, 401);
});

Deno.test("handlePurgeAccounts purges and answers the counts", async () => {
  const fake = new FakePurgeDb();
  const response = await handlePurgeAccounts(post("s"), { secret: "s", db: () => fake });
  assertEquals(response.status, 200);
  assertEquals(await response.json(), { purged: 1, skipped: 0, failed: 0 });
});

Deno.test("handlePurgeAccounts answers 500 when the due accounts cannot be read", async () => {
  const fake = new FakePurgeDb();
  fake.dueAccounts = () => Promise.reject(new Error("db down"));
  const logs: string[] = [];
  const response = await handlePurgeAccounts(post("s"), {
    secret: "s",
    db: () => fake,
    log: (m) => logs.push(m),
  });
  assertEquals(response.status, 500);
  assertEquals(await response.json(), { error: "server_error" });
  assert(logs[0].includes("db down"));
  fake.dueAccounts = () => Promise.reject("plain");
  const second = await handlePurgeAccounts(post("s"), {
    secret: "s",
    db: () => fake,
    log: (m) => logs.push(m),
  });
  assertEquals(second.status, 500);
  assert(logs[1].endsWith("plain"));
});
