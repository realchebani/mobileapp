// EPIC-12: bo-files (handler with an in-memory db).
import { assertEquals } from "jsr:@std/assert@1";
import {
  type BoFilesDb,
  DOWNLOAD_SECONDS,
  type FileItem,
  type FileLocation,
  handleBoFiles,
  parseOrigins,
  RpcError,
  statusOf,
  type UploadTarget,
} from "../_shared/backoffice/handler.ts";

const PROPERTY = "11111111-1111-4111-8111-111111111111";
const DOC = "22222222-2222-4222-8222-222222222222";
const ID_DOC = "33333333-3333-4333-8333-333333333333";
const ORIGIN = "https://expert.realesty.fr";

class FakeDb implements BoFilesDb {
  checked: FileItem[][] = [];
  signed: string[] = [];
  error: RpcError | Error | null = null;

  checkFiles(_propertyId: string, items: FileItem[]): Promise<FileLocation[]> {
    this.checked.push(items);
    if (this.error) return Promise.reject(this.error);
    if (items.some((i) => i.id === ID_DOC)) {
      return Promise.reject(new RpcError("42501", "identity_document_forbidden"));
    }
    return Promise.resolve(items.map((i) => ({
      ...i,
      bucket: "property-documents",
      path: `owner/${PROPERTY}/${i.id}.pdf`,
      file_name: `${i.id}.pdf`,
      mime_type: "application/pdf",
    })));
  }

  prepareUpload(propertyId: string): Promise<UploadTarget> {
    if (this.error) return Promise.reject(this.error);
    return Promise.resolve({
      bucket: "valuation-reports",
      path: `owner/${propertyId}/avis-de-valeur-20261003-120000.pdf`,
      valuation_id: DOC,
    });
  }

  signDownload(bucket: string, path: string, seconds: number): Promise<string> {
    this.signed.push(`${bucket}:${path}:${seconds}`);
    return Promise.resolve(`https://signed/${path}`);
  }

  signUpload(_bucket: string, path: string): Promise<{ signedUrl: string; token: string }> {
    return Promise.resolve({ signedUrl: `https://upload/${path}`, token: "tok" });
  }
}

function post(body: unknown, origin = ORIGIN): Request {
  return new Request("http://localhost/bo-files", {
    method: "POST",
    headers: { Origin: origin, "content-type": "application/json" },
    body: typeof body === "string" ? body : JSON.stringify(body),
  });
}

function deps(db: BoFilesDb | null = new FakeDb()) {
  return { db, allowedOrigins: [ORIGIN] };
}

Deno.test("preflight answers the allowed origin only", async () => {
  const ok = await handleBoFiles(
    new Request("http://localhost", { method: "OPTIONS", headers: { Origin: ORIGIN } }),
    deps(null),
  );
  assertEquals(ok.status, 204);
  assertEquals(ok.headers.get("access-control-allow-origin"), ORIGIN);
  const other = await handleBoFiles(
    new Request("http://localhost", { method: "OPTIONS", headers: { Origin: "https://evil" } }),
    deps(null),
  );
  assertEquals(other.headers.get("access-control-allow-origin"), null);
});

Deno.test("refuses other methods, no JWT and bad bodies", async () => {
  assertEquals((await handleBoFiles(new Request("http://localhost"), deps())).status, 405);
  assertEquals((await handleBoFiles(post({}), deps(null))).status, 401);
  assertEquals((await handleBoFiles(post("{"), deps())).status, 400);
  assertEquals((await handleBoFiles(post("null"), deps())).status, 400);
  assertEquals((await handleBoFiles(post("x".repeat(20_001)), deps())).status, 413);
  assertEquals((await handleBoFiles(post({ property_id: "nope" }), deps())).status, 400);
  assertEquals(
    (await handleBoFiles(post({ action: "other", property_id: PROPERTY }), deps())).status,
    400,
  );
  for (
    const items of [
      [],
      [{ type: "secret", id: DOC }],
      [{ type: "document", id: "x" }],
      [null],
      Array.from({ length: 61 }, () => ({ type: "photo", id: DOC })),
      "x",
    ]
  ) {
    const response = await handleBoFiles(
      post({ action: "sign_download", property_id: PROPERTY, items }),
      deps(),
    );
    assertEquals(response.status, 400, JSON.stringify(items));
  }
});

Deno.test("signs downloads for 5 minutes after the caller check", async () => {
  const db = new FakeDb();
  const response = await handleBoFiles(
    post({
      action: "sign_download",
      property_id: PROPERTY,
      items: [{ type: "document", id: DOC }],
    }),
    deps(db),
  );
  assertEquals(response.status, 200);
  assertEquals(response.headers.get("access-control-allow-origin"), ORIGIN);
  const body = await response.json();
  assertEquals(body.expires_in, DOWNLOAD_SECONDS);
  assertEquals(DOWNLOAD_SECONDS, 300);
  assertEquals(body.files, [{
    type: "document",
    id: DOC,
    file_name: `${DOC}.pdf`,
    mime_type: "application/pdf",
    url: `https://signed/owner/${PROPERTY}/${DOC}.pdf`,
  }]);
  assertEquals(db.checked, [[{ type: "document", id: DOC }]]);
  assertEquals(db.signed, [`property-documents:owner/${PROPERTY}/${DOC}.pdf:300`]);
});

Deno.test("an identity document refused to a partner signs nothing", async () => {
  const db = new FakeDb();
  const response = await handleBoFiles(
    post({
      action: "sign_download",
      property_id: PROPERTY,
      items: [{ type: "document", id: DOC }, { type: "document", id: ID_DOC }],
    }),
    deps(db),
  );
  assertEquals(response.status, 403);
  assertEquals(await response.json(), { error: "identity_document_forbidden" });
  assertEquals(db.signed, []);
});

Deno.test("signs an upload of the report to the server-chosen path", async () => {
  const response = await handleBoFiles(
    post({ action: "sign_upload", property_id: PROPERTY }),
    deps(),
  );
  assertEquals(response.status, 200);
  assertEquals(await response.json(), {
    bucket: "valuation-reports",
    path: `owner/${PROPERTY}/avis-de-valeur-20261003-120000.pdf`,
    token: "tok",
    signed_url: `https://upload/owner/${PROPERTY}/avis-de-valeur-20261003-120000.pdf`,
    valuation_id: DOC,
  });
});

Deno.test("maps SQL errors to HTTP statuses and hides internal ones", async () => {
  const cases: [RpcError | Error, number, string][] = [
    [new RpcError("42501", "mfa_required"), 403, "mfa_required"],
    [new RpcError("P0002", "dossier_not_found"), 404, "dossier_not_found"],
    [new RpcError("22023", "invalid_items"), 400, "invalid_items"],
    [new RpcError("55000", "not_certified"), 409, "not_certified"],
    [new RpcError("PT404", "file_not_found"), 404, "file_not_found"],
    [new RpcError("PT409", "not_certified"), 409, "not_certified"],
    [new RpcError("XX000", "boom"), 500, "internal"],
    [new Error("network"), 500, "internal"],
  ];
  for (const [error, status, code] of cases) {
    const db = new FakeDb();
    db.error = error;
    const response = await handleBoFiles(
      post({ action: "sign_upload", property_id: PROPERTY }),
      deps(db),
    );
    assertEquals(response.status, status);
    assertEquals(await response.json(), { error: code });
  }
  assertEquals(statusOf(new RpcError("", "x")), 500);
});

Deno.test("origins come from a comma-separated setting", () => {
  assertEquals(parseOrigins(undefined), ["http://localhost:3000"]);
  assertEquals(parseOrigins(" "), ["http://localhost:3000"]);
  assertEquals(parseOrigins("https://a, https://b"), ["https://a", "https://b"]);
});
