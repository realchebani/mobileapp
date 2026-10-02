// Edge Function `estimate-property` (EPIC-05): non-certified estimate of a
// sent dossier from the DVF sales of its sector. See handler.ts.
//
// Secrets: OPENROUTER_API_KEY (never logged), OPENROUTER_MODEL_ESTIMATE
// (optional, defaults to DEFAULT_ESTIMATE_MODEL). SUPABASE_URL,
// SUPABASE_ANON_KEY and SUPABASE_SERVICE_ROLE_KEY are provided by Supabase.
import { createClient } from "jsr:@supabase/supabase-js@2";
import { explainEstimate } from "../_shared/estimation/explain.ts";
import { type Deps, handle } from "./handler.ts";
import { loadMarket } from "./market.ts";
import { DvfStore } from "./store.ts";
import { type Dossier, PROPERTY_COLUMNS, type PropertyRow } from "./subject.ts";

declare const EdgeRuntime: { waitUntil(promise: Promise<unknown>): void } | undefined;

const url = Deno.env.get("SUPABASE_URL")!;
const anonKey = Deno.env.get("SUPABASE_ANON_KEY") ??
  Deno.env.get("SUPABASE_PUBLISHABLE_KEY")!;
const service = createClient(url, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
  auth: { persistSession: false },
});

function depsFor(request: Request): Deps {
  const user = createClient(url, anonKey, {
    auth: { persistSession: false },
    global: { headers: { Authorization: request.headers.get("Authorization") ?? "" } },
  });
  const now = () => new Date();
  const store = new DvfStore(service, fetch, now);
  const fail = (what: string, error: { message: string } | null) => {
    if (error) throw new Error(`${what}: ${error.message}`);
  };
  return {
    async loadDossier(propertyId) {
      const { data, error } = await user.from("properties").select(PROPERTY_COLUMNS)
        .eq("id", propertyId).maybeSingle();
      fail("properties", error);
      if (!data) return null;
      const [parcels, lifestyle, documents] = await Promise.all([
        user.from("property_parcels").select("area_m2").eq("property_id", propertyId),
        user.from("lifestyle_items").select("kind, label").eq("property_id", propertyId)
          .order("sort_order"),
        user.from("property_documents").select("kind, status").eq("property_id", propertyId),
      ]);
      fail("property_parcels", parcels.error);
      fail("lifestyle_items", lifestyle.error);
      fail("property_documents", documents.error);
      return {
        property: data as unknown as PropertyRow,
        parcelAreas: (parcels.data ?? []).map((row) => row.area_m2 as number | null),
        lifestyle: (lifestyle.data ?? []) as Dossier["lifestyle"],
        documents: (documents.data ?? []) as Dossier["documents"],
      };
    },
    async findFinal(propertyId) {
      const { data, error } = await service.from("market_snapshots").select("*")
        .eq("property_id", propertyId).in("status", ["ok", "insufficient"]).maybeSingle();
      fail("market_snapshots", error);
      return data;
    },
    async findRunning(propertyId) {
      const { data, error } = await service.from("market_snapshots").select("id, created_at")
        .eq("property_id", propertyId).eq("status", "running").maybeSingle();
      fail("market_snapshots", error);
      return data;
    },
    async countRecentAttempts(ownerId, since) {
      const { count, error } = await service.from("market_snapshots")
        .select("id, properties!inner(owner_id)", { count: "exact", head: true })
        .eq("properties.owner_id", ownerId).gte("created_at", since);
      fail("market_snapshots", error);
      return count ?? 0;
    },
    async markStale(id) {
      const { error } = await service.from("market_snapshots")
        .update({ status: "error", error: "stale" }).eq("id", id).eq("status", "running");
      fail("market_snapshots", error);
    },
    async startSnapshot(_propertyId, row) {
      const { data, error } = await service.from("market_snapshots").insert(row)
        .select("id").single();
      if (error?.code === "23505") return null;
      fail("market_snapshots", error);
      return data!.id as string;
    },
    async updateSnapshot(id, row) {
      const { error } = await service.from("market_snapshots").update(row).eq("id", id);
      fail("market_snapshots", error);
    },
    async savePropertyEstimate(propertyId, values) {
      const { error } = await service.from("properties").update(values).eq("id", propertyId);
      fail("properties", error);
    },
    loadMarket: (subject) => loadMarket(subject, store, fetch, now()),
    explain: (subject, result) =>
      explainEstimate(subject, result, {
        apiKey: Deno.env.get("OPENROUTER_API_KEY"),
        model: Deno.env.get("OPENROUTER_MODEL_ESTIMATE"),
      }),
    background(work) {
      if (typeof EdgeRuntime !== "undefined") EdgeRuntime.waitUntil(work);
    },
    now,
    log: (message) => console.error(message),
  };
}

Deno.serve((request) => handle(request, depsFor(request)));
