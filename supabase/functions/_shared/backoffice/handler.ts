// EPIC-12 · bo-files: signed URLs for the back-office (no Storage policy
// for the team). Every request is checked by the SQL function bo_check_files
// / bo_prepare_report_upload called with the CALLER's JWT (role, MFA,
// dossier access, identity documents refused to partners, journal); only
// then does the service role sign.
//
// POST { action: "sign_download", property_id, items: [{ type, id }] }
//   → { files: [{ type, id, url, file_name, mime_type }], expires_in }
// POST { action: "sign_upload", property_id }
//   → { bucket, path, token, signed_url, valuation_id }

export const DOWNLOAD_SECONDS = 300;
export const MAX_ITEMS = 60;

export type FileType = "document" | "photo" | "report";

export interface FileItem {
  type: FileType;
  id: string;
}

export interface FileLocation extends FileItem {
  bucket: string;
  path: string;
  file_name: string;
  mime_type: string | null;
}

export interface UploadTarget {
  bucket: string;
  path: string;
  valuation_id: string;
}

/** An error raised by a bo_* SQL function (code = SQLSTATE). */
export class RpcError extends Error {
  constructor(readonly code: string, message: string) {
    super(message);
  }
}

export interface BoFilesDb {
  checkFiles(propertyId: string, items: FileItem[]): Promise<FileLocation[]>;
  prepareUpload(propertyId: string): Promise<UploadTarget>;
  signDownload(bucket: string, path: string, seconds: number): Promise<string>;
  signUpload(bucket: string, path: string): Promise<{ signedUrl: string; token: string }>;
}

export interface BoFilesDeps {
  db: BoFilesDb | null;
  /** Origins allowed to call from a browser (exact match). */
  allowedOrigins: string[];
}

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const TYPES: ReadonlySet<string> = new Set(["document", "photo", "report"]);

/** Origins from a comma-separated setting; localhost dev ports by default. */
export function parseOrigins(value: string | undefined): string[] {
  const list = (value ?? "").split(",").map((o) => o.trim()).filter((o) => o.length > 0);
  return list.length > 0 ? list : ["http://localhost:3000"];
}

function corsHeaders(request: Request, allowed: string[]): Record<string, string> {
  const origin = request.headers.get("Origin");
  if (!origin || !allowed.includes(origin)) return {};
  return {
    "access-control-allow-origin": origin,
    "access-control-allow-methods": "POST, OPTIONS",
    "access-control-allow-headers": "authorization, apikey, content-type, x-client-info",
    "access-control-max-age": "600",
    "vary": "Origin",
  };
}

/** HTTP status of a bo_* SQL error. */
export function statusOf(error: RpcError): number {
  // PTxyz: the HTTP status chosen by the SQL function.
  const explicit = /^PT([45]\d\d)$/.exec(error.code);
  if (explicit) return Number(explicit[1]);
  switch (error.code) {
    case "42501":
      return 403;
    case "P0002":
      return 404;
    case "22023":
      return 400;
    case "55000":
      return 409;
    default:
      return 500;
  }
}

function parseItems(value: unknown): FileItem[] | null {
  if (!Array.isArray(value) || value.length < 1 || value.length > MAX_ITEMS) return null;
  const items: FileItem[] = [];
  for (const raw of value) {
    const item = raw as Record<string, unknown> | null;
    if (
      !item || typeof item.type !== "string" || !TYPES.has(item.type) ||
      typeof item.id !== "string" || !UUID.test(item.id)
    ) return null;
    items.push({ type: item.type as FileType, id: item.id });
  }
  return items;
}

export async function handleBoFiles(request: Request, deps: BoFilesDeps): Promise<Response> {
  const cors = corsHeaders(request, deps.allowedOrigins);
  const json = (body: unknown, status = 200) =>
    new Response(JSON.stringify(body), {
      status,
      headers: { ...cors, "content-type": "application/json; charset=utf-8" },
    });

  if (request.method === "OPTIONS") return new Response(null, { status: 204, headers: cors });
  if (request.method !== "POST") return json({ error: "method_not_allowed" }, 405);
  if (!deps.db) return json({ error: "unauthorized" }, 401);

  let body: Record<string, unknown>;
  try {
    const text = await request.text();
    if (text.length > 20_000) return json({ error: "too_long" }, 413);
    body = JSON.parse(text) as Record<string, unknown>;
    if (!body || typeof body !== "object") throw new Error("not an object");
  } catch {
    return json({ error: "bad_request" }, 400);
  }
  const propertyId = body.property_id;
  if (typeof propertyId !== "string" || !UUID.test(propertyId)) {
    return json({ error: "bad_request" }, 400);
  }

  try {
    if (body.action === "sign_download") {
      const items = parseItems(body.items);
      if (!items) return json({ error: "bad_request" }, 400);
      const locations = await deps.db.checkFiles(propertyId, items);
      const files = await Promise.all(locations.map(async (file) => ({
        type: file.type,
        id: file.id,
        file_name: file.file_name,
        mime_type: file.mime_type,
        url: await deps.db!.signDownload(file.bucket, file.path, DOWNLOAD_SECONDS),
      })));
      return json({ files, expires_in: DOWNLOAD_SECONDS });
    }
    if (body.action === "sign_upload") {
      const target = await deps.db.prepareUpload(propertyId);
      const signed = await deps.db.signUpload(target.bucket, target.path);
      return json({
        bucket: target.bucket,
        path: target.path,
        token: signed.token,
        signed_url: signed.signedUrl,
        valuation_id: target.valuation_id,
      });
    }
    return json({ error: "bad_request" }, 400);
  } catch (error) {
    if (error instanceof RpcError) {
      const status = statusOf(error);
      return json({ error: status === 500 ? "internal" : error.message }, status);
    }
    console.error("bo-files", error instanceof Error ? error.message : error);
    return json({ error: "internal" }, 500);
  }
}
