// EPIC-08: render-mandate (template, PDF, handler with an in-memory db).
import { assert, assertEquals, assertMatch, assertStringIncludes } from "jsr:@std/assert@1";
import { PDFDocument, StandardFonts } from "npm:pdf-lib@1.17.1";
import type { MandateDb, MandateRow } from "../_shared/mandate/db.ts";
import { handleRenderMandate, mandatePdfPath } from "../_shared/mandate/handler.ts";
import { renderMandatePdf, sha256Hex, winAnsi, wrap } from "../_shared/mandate/pdf.ts";
import {
  euros,
  fees,
  frenchDateTime,
  frenchNumber,
  MANDATE_TERMS_VERSION,
  type MandateFacts,
  mandateSections,
} from "../_shared/mandate/template.ts";

const MANDATE = "11111111-1111-4111-8111-111111111111";
const SALE = "22222222-2222-4222-8222-222222222222";
const OWNER = "33333333-3333-4333-8333-333333333333";
// 1×1 transparent PNG.
const PNG = Uint8Array.from(
  atob(
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==",
  ),
  (c) => c.charCodeAt(0),
);

function facts(overrides: Partial<MandateFacts> = {}): MandateFacts {
  return {
    mandateId: MANDATE,
    formula: "essentiel",
    kind: "exclusif_sans_engagement",
    termsVersion: MANDATE_TERMS_VERSION,
    presentationPriceEur: 525000,
    feeRate: 1,
    durationMonths: null,
    owners: ["Sophie Durand"],
    properties: [{ type: "maison", address: "12 rue de la Colombe, Chaponost", areaM2: 115 }],
    isLot: false,
    signerName: "Sophie Durand",
    signedAt: new Date("2026-10-03T08:30:00Z"),
    userAgent: "iOS 26",
    appVersion: "1.0.0",
    ...overrides,
  };
}

function text(sections: ReturnType<typeof mandateSections>): string {
  return sections.map((s) => `${s.title}\n${s.lines.join("\n")}`).join("\n");
}

Deno.test("template: single property, L'Essentiel, articles 1 to 15", () => {
  const all = text(mandateSections(facts({
    properties: [{
      type: "maison",
      address: "12 rue de la Colombe, Chaponost",
      areaM2: 115,
      roomsCount: 5,
      parcels: [{ section: "AB", numero: "12", areaM2: 540 }, {
        section: null,
        numero: null,
        areaM2: null,
      }],
    }],
  })));
  for (let article = 1; article <= 15; article++) {
    assertStringIncludes(all, `Article ${article}.`);
  }
  assertStringIncludes(all, "Article 3. Bien objet du MANDAT");
  assertStringIncludes(
    all,
    "Maison de 115\u00a0m², 5\u00a0pièce(s), 12 rue de la Colombe, Chaponost",
  );
  assertStringIncludes(all, "Cadastre : section AB, n° 12, 540\u00a0m²");
  assertStringIncludes(all, "Cadastre : section ?, n° ?");
  assertStringIncludes(all, "Prix de présentation : 525\u00a0000,00\u00a0€");
  assertStringIncludes(all, "5\u00a0250,00\u00a0€ TTC, soit 4\u00a0375,00\u00a0€ HT");
  assertStringIncludes(all, "période minimale de 30 jours");
  assertStringIncludes(all, "RCS Lyon 988 966 099");
  assertStringIncludes(all, "T CPI 6901 2025 000 000 091");
  assertStringIncludes(all, "FR49988966099");
  assertStringIncludes(all, "le 03/10/2026 à 10h30");
  assertStringIncludes(all, "signature de test dessinée");
  assertStringIncludes(all, "application 1.0.0");
  assert(!all.includes("Formule Le Premium : frais"));
  assert(!all.includes("signeront hors de l’application"));
  assertEquals(fees(facts({ presentationPriceEur: null })), null);
});

Deno.test("template: lot, Premium, typed, co-owners, unknown values", () => {
  const all = text(mandateSections(facts({
    formula: "premium",
    feeRate: 2.5,
    presentationPriceEur: null,
    minimumDays: 45,
    owners: ["Sophie Durand", "Marc Durand"],
    properties: [
      { type: "maison", address: null, areaM2: null },
      { type: null, address: "Chaponost", areaM2: 18 },
      { type: "inconnu", address: null, areaM2: null },
    ],
    isLot: true,
    userAgent: null,
    appVersion: null,
    signatureMethod: "typed",
    typedSignature: "Sophie Durand",
  })));
  assertStringIncludes(all, "Biens objet du MANDAT (vente en lot)");
  assertStringIncludes(all, "• Maison\n");
  assertStringIncludes(all, "• Bien de 18\u00a0m², Chaponost");
  assertStringIncludes(all, "à définir avec le MANDANT");
  assertStringIncludes(all, "Montant calculé sur le prix de vente définitif.");
  assertStringIncludes(all, "2,5\u00a0%");
  assertStringIncludes(all, "Formule Le Premium : frais de dossier de 299\u00a0€");
  assertStringIncludes(all, "période minimale de 45 jours");
  assertStringIncludes(all, "par nom tapé");
  assertStringIncludes(all, "Nom tapé : « Sophie Durand »");
  assertStringIncludes(all, "Appareil : non renseigné.");
  assertStringIncludes(all, "Le MANDANT : Sophie Durand, Marc Durand,");
  assertStringIncludes(all, "signeront hors de l’application");
  const noOwner = text(mandateSections(facts({ owners: [] })));
  assertStringIncludes(noOwner, "Le MANDANT : Sophie Durand,");
});

Deno.test("formats", () => {
  assertEquals(euros(1234.5), "1\u00a0234,50\u00a0€");
  assertEquals(frenchNumber(1234567), "1 234 567");
  assertEquals(frenchDateTime(new Date("2026-01-05T23:05:00Z")), "06/01/2026 à 00h05");
  assertEquals(winAnsi("a b c\nd\te’€✓"), "a b c d e’€?");
});

Deno.test("wrap cuts long lines at word boundaries", async () => {
  const doc = await PDFDocument.create();
  const font = await doc.embedFont(StandardFonts.Helvetica);
  const lines = wrap("un deux trois quatre cinq six sept huit neuf dix", font, 12, 60);
  assert(lines.length > 2);
  assertEquals(lines.join(" "), "un deux trois quatre cinq six sept huit neuf dix");
  assertEquals(wrap("", font, 12, 60), []);
});

Deno.test("PDF: SPÉCIMEN metadata, signature, several pages, deterministic", async () => {
  const many = facts({
    properties: Array.from({ length: 60 }, (_, i) => ({
      type: "stationnement",
      address: `Place ${i}`,
      areaM2: 12,
    })),
    isLot: true,
  });
  const bytes = await renderMandatePdf(many, PNG);
  const doc = await PDFDocument.load(bytes);
  assert(doc.getPageCount() >= 2);
  assertStringIncludes(doc.getTitle() ?? "", "SPÉCIMEN");
  assertStringIncludes(doc.getSubject() ?? "", "sans valeur juridique");
  assertStringIncludes(doc.getKeywords() ?? "", MANDATE_TERMS_VERSION);
  assertEquals(await sha256Hex(bytes), await sha256Hex(await renderMandatePdf(many, PNG)));
  const typed = await renderMandatePdf(
    facts({ signatureMethod: "typed", typedSignature: "Sophie Durand" }),
    null,
  );
  assertEquals((await PDFDocument.load(typed)).getPageCount() >= 1, true);
  const plain = await renderMandatePdf(facts(), null);
  assert((await PDFDocument.load(plain)).getPageCount() >= 2);
  assertMatch(await sha256Hex(plain), /^[0-9a-f]{64}$/);
});

class FakeMandateDb implements MandateDb {
  row: MandateRow | null = {
    id: MANDATE,
    sale_id: SALE,
    owner_id: OWNER,
    document_path: null,
    document_sha256: null,
  };
  stored: { path: string; pdf: Uint8Array; sha256: string } | null = null;
  fail = false;

  mandate(id: string): Promise<MandateRow | null> {
    if (this.fail) return Promise.reject(new Error("boom"));
    return Promise.resolve(this.row?.id === id ? this.row : null);
  }
  facts(): Promise<MandateFacts> {
    return Promise.resolve(facts());
  }
  signature(): Promise<Uint8Array | null> {
    return Promise.resolve(PNG);
  }
  store(_: MandateRow, path: string, pdf: Uint8Array, sha256: string) {
    this.stored = { path, pdf, sha256 };
    return Promise.resolve({ path, sha256 });
  }
}

function post(body: unknown, method = "POST"): Request {
  return new Request("http://localhost/render-mandate", {
    method,
    body: method === "POST" ? (typeof body === "string" ? body : JSON.stringify(body)) : undefined,
  });
}

Deno.test("handler: refusals", async () => {
  const db = new FakeMandateDb();
  assertEquals((await handleRenderMandate(post({}, "GET"), { db })).status, 405);
  assertEquals(
    (await handleRenderMandate(post({ mandate_id: MANDATE }), { db: null })).status,
    401,
  );
  assertEquals((await handleRenderMandate(post("{"), { db })).status, 400);
  assertEquals((await handleRenderMandate(post("null"), { db })).status, 400);
  assertEquals((await handleRenderMandate(post({ mandate_id: "x" }), { db })).status, 400);
  assertEquals(
    (await handleRenderMandate(post({ mandate_id: "a".repeat(2000) }), { db })).status,
    413,
  );
  assertEquals(
    (await handleRenderMandate(
      post({ mandate_id: "44444444-4444-4444-8444-444444444444" }),
      { db },
    )).status,
    404,
  );
  db.fail = true;
  const failed = await handleRenderMandate(post({ mandate_id: MANDATE }), { db });
  assertEquals(failed.status, 500);
  assertEquals(await failed.json(), { error: "internal" });
});

Deno.test("handler: renders and stores, then returns the stored PDF", async () => {
  const db = new FakeMandateDb();
  const response = await handleRenderMandate(post({ mandate_id: MANDATE }), { db });
  assertEquals(response.status, 200);
  const body = await response.json();
  assertEquals(body.path, `${OWNER}/${SALE}/mandat-${MANDATE}.pdf`);
  assertEquals(body.path, mandatePdfPath(OWNER, SALE, MANDATE));
  assertEquals(body.sha256, await sha256Hex(db.stored!.pdf));
  db.row = { ...db.row!, document_path: "stored.pdf", document_sha256: "f".repeat(64) };
  db.stored = null;
  const again = await handleRenderMandate(post({ mandate_id: MANDATE }), { db });
  assertEquals(await again.json(), { path: "stored.pdf", sha256: "f".repeat(64) });
  assertEquals(db.stored, null);
});
