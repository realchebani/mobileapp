// MandateDb on Supabase: the mandate, its sale, properties, owners and the
// signature (row and PNG) are read with the CALLER's JWT, so RLS and the
// Storage policies decide what they may see; only the PDF upload
// (sale-documents has no client write policy) and mandates.document_path
// are written with the service role, for a mandate the caller could read.

import { createClient, type SupabaseClient } from "npm:@supabase/supabase-js@2";
import type { MandateDb, MandateRow } from "./db.ts";
import type { Formula, MandateFacts, MandateProperty } from "./template.ts";

const noSession = { persistSession: false, autoRefreshToken: false };

function fail(error: { message: string } | null): void {
  if (error) throw new Error(`db: ${error.message}`);
}

/** The data access of a signed-in caller, or null without a valid JWT. */
export async function callerMandateDb(request: Request): Promise<MandateDb | null> {
  const authorization = request.headers.get("Authorization");
  if (!authorization?.startsWith("Bearer ")) return null;
  const url = Deno.env.get("SUPABASE_URL")!;
  const caller = createClient(url, Deno.env.get("SUPABASE_ANON_KEY")!, {
    global: { headers: { Authorization: authorization } },
    auth: noSession,
  });
  const { data, error } = await caller.auth.getUser(authorization.slice(7));
  if (error || !data.user) return null;
  const service = createClient(url, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
    auth: noSession,
  });
  return new SupabaseMandateDb(caller, service);
}

interface PropertyRow {
  id: string;
  property_type: string | null;
  address_label: string | null;
  living_area_m2: number | null;
  usable_area_m2: number | null;
  rooms_count: number | null;
}

const PROPERTY_COLUMNS = "id,property_type,address_label,living_area_m2,usable_area_m2,rooms_count";

export class SupabaseMandateDb implements MandateDb {
  constructor(
    private readonly caller: SupabaseClient,
    private readonly service: SupabaseClient,
  ) {}

  async mandate(id: string): Promise<MandateRow | null> {
    const { data, error } = await this.caller.from("mandates")
      .select("id,sale_id,document_path,document_sha256,sale:sales(owner_id)")
      .eq("id", id).maybeSingle();
    fail(error);
    if (!data) return null;
    const row = data as unknown as Omit<MandateRow, "owner_id"> & {
      sale: { owner_id: string } | null;
    };
    if (!row.sale) return null;
    return {
      id: row.id,
      sale_id: row.sale_id,
      owner_id: row.sale.owner_id,
      document_path: row.document_path,
      document_sha256: row.document_sha256,
    };
  }

  private async signatureRow(mandateId: string) {
    const { data, error } = await this.caller.from("mandate_signatures")
      .select("signer_name,signed_at,user_agent,app_version,signature_path,method,typed_signature")
      .eq("mandate_id", mandateId).in("method", ["drawn_test", "typed_test"])
      .order("signed_at").limit(1).maybeSingle();
    fail(error);
    return data as {
      signer_name: string;
      signed_at: string;
      user_agent: string | null;
      app_version: string | null;
      signature_path: string | null;
      method: string;
      typed_signature: string | null;
    } | null;
  }

  async facts(mandate: MandateRow): Promise<MandateFacts> {
    const { data: m, error } = await this.caller.from("mandates")
      .select(
        "formula,kind,terms_version,presentation_price_eur,fee_rate,duration_months,minimum_days," +
          "signed_at," +
          "sale:sales(property_id,lot_id)",
      )
      .eq("id", mandate.id).single();
    fail(error);
    const row = m as unknown as {
      formula: Formula;
      kind: MandateFacts["kind"];
      terms_version: string;
      presentation_price_eur: number | null;
      fee_rate: number | string;
      duration_months: number | null;
      minimum_days: number | null;
      signed_at: string;
      sale: { property_id: string | null; lot_id: string | null };
    };
    let properties: PropertyRow[];
    let mainId: string | null;
    if (row.sale.property_id) {
      const { data, error } = await this.caller.from("properties")
        .select(PROPERTY_COLUMNS).eq("id", row.sale.property_id);
      fail(error);
      properties = (data ?? []) as PropertyRow[];
      mainId = row.sale.property_id;
    } else {
      const [{ data, error }, { data: lot, error: lotError }] = await Promise.all([
        this.caller.from("properties").select(PROPERTY_COLUMNS)
          .eq("lot_id", row.sale.lot_id!).order("created_at"),
        this.caller.from("property_lots").select("main_property_id")
          .eq("id", row.sale.lot_id!).maybeSingle(),
      ]);
      fail(error);
      fail(lotError);
      properties = (data ?? []) as PropertyRow[];
      mainId = (lot as { main_property_id: string | null } | null)?.main_property_id ??
        properties[0]?.id ?? null;
    }
    const { data: owners, error: ownersError } = await this.caller.from("property_owners")
      .select("first_name,last_name").eq("property_id", mainId ?? "").order("position");
    fail(ownersError);
    const signature = await this.signatureRow(mandate.id);
    const { data: parcels, error: parcelsError } = await this.caller.from("property_parcels")
      .select("property_id,section,numero,area_m2")
      .in("property_id", properties.map((p) => p.id));
    fail(parcelsError);
    const parcelRows = (parcels ?? []) as {
      property_id: string;
      section: string | null;
      numero: string | null;
      area_m2: number | null;
    }[];
    return {
      mandateId: mandate.id,
      formula: row.formula,
      kind: row.kind,
      termsVersion: row.terms_version,
      presentationPriceEur: row.presentation_price_eur,
      feeRate: Number(row.fee_rate),
      durationMonths: row.duration_months,
      minimumDays: row.minimum_days,
      owners: ((owners ?? []) as { first_name: string; last_name: string }[])
        .map((o) => `${o.first_name} ${o.last_name}`.trim()),
      properties: properties.map((p): MandateProperty => ({
        type: p.property_type,
        address: p.address_label,
        areaM2: p.living_area_m2 ?? p.usable_area_m2,
        roomsCount: p.rooms_count,
        parcels: parcelRows.filter((parcel) => parcel.property_id === p.id).map((parcel) => ({
          section: parcel.section,
          numero: parcel.numero,
          areaM2: parcel.area_m2,
        })),
      })),
      isLot: !row.sale.property_id,
      signerName: signature?.signer_name ?? "",
      signedAt: new Date(signature?.signed_at ?? row.signed_at),
      userAgent: signature?.user_agent ?? null,
      appVersion: signature?.app_version ?? null,
      signatureMethod: signature?.method === "typed_test" ? "typed" : "drawn",
      typedSignature: signature?.typed_signature ?? null,
    };
  }

  async signature(mandate: MandateRow): Promise<Uint8Array | null> {
    const row = await this.signatureRow(mandate.id);
    if (!row?.signature_path) return null;
    const { data, error } = await this.caller.storage.from("mandate-signatures")
      .download(row.signature_path);
    if (error || !data) return null;
    return new Uint8Array(await data.arrayBuffer());
  }

  async store(
    mandate: MandateRow,
    path: string,
    pdf: Uint8Array,
    sha256: string,
  ): Promise<{ path: string; sha256: string }> {
    const { error: uploadError } = await this.service.storage.from("sale-documents")
      .upload(path, pdf, { contentType: "application/pdf", upsert: true });
    fail(uploadError);
    const { data, error } = await this.service.from("mandates")
      .update({ document_path: path, document_sha256: sha256 })
      .eq("id", mandate.id).is("document_path", null)
      .select("document_path,document_sha256");
    fail(error);
    if (data && data.length) return { path, sha256 };
    // Rendered by a concurrent request: its PDF wins.
    const { data: stored, error: readError } = await this.service.from("mandates")
      .select("document_path,document_sha256").eq("id", mandate.id).single();
    fail(readError);
    const current = stored as { document_path: string; document_sha256: string };
    return { path: current.document_path, sha256: current.document_sha256 };
  }
}
