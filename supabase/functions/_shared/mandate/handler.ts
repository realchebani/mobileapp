// EPIC-08 · render-mandate: POST { mandate_id } with the caller's JWT →
// renders the PDF "SPÉCIMEN" of the caller's test mandate into the private
// bucket sale-documents (<owner>/<sale>/mandat-<id>.pdf) and returns
// { path, sha256 }. Idempotent: a mandate that already has its PDF gets
// its stored path back.

import type { MandateDb } from "./db.ts";
import { renderMandatePdf, sha256Hex } from "./pdf.ts";

export interface RenderMandateDeps {
  db: MandateDb | null;
}

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json; charset=utf-8" },
  });
}

function failure(code: string, status: number): Response {
  return json({ error: code }, status);
}

/** Path of the PDF of [mandateId] in sale-documents. */
export function mandatePdfPath(ownerId: string, saleId: string, mandateId: string): string {
  return `${ownerId}/${saleId}/mandat-${mandateId}.pdf`;
}

export async function handleRenderMandate(
  request: Request,
  deps: RenderMandateDeps,
): Promise<Response> {
  if (request.method !== "POST") return failure("method_not_allowed", 405);
  if (!deps.db) return failure("unauthorized", 401);
  let id: unknown;
  try {
    const text = await request.text();
    if (text.length > 1000) return failure("too_long", 413);
    id = (JSON.parse(text) as Record<string, unknown> | null)?.mandate_id;
  } catch {
    return failure("bad_request", 400);
  }
  if (typeof id !== "string" || !UUID.test(id)) return failure("bad_request", 400);
  try {
    const mandate = await deps.db.mandate(id);
    if (!mandate) return failure("not_found", 404);
    if (mandate.document_path && mandate.document_sha256) {
      return json({ path: mandate.document_path, sha256: mandate.document_sha256 });
    }
    const [facts, signature] = await Promise.all([
      deps.db.facts(mandate),
      deps.db.signature(mandate),
    ]);
    const pdf = await renderMandatePdf(facts, signature);
    const stored = await deps.db.store(
      mandate,
      mandatePdfPath(mandate.owner_id, mandate.sale_id, mandate.id),
      pdf,
      await sha256Hex(pdf),
    );
    return json(stored);
  } catch (error) {
    console.error("render-mandate", error instanceof Error ? error.message : error);
    return failure("internal", 500);
  }
}
