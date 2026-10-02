import { assertEquals } from "jsr:@std/assert@1";
import { compute, type Deps, handle, type SnapshotRow } from "../estimate-property/handler.ts";
import type { Dossier, PropertyRow } from "../estimate-property/subject.ts";
import { toSubject } from "../estimate-property/subject.ts";
import { chaponostSales } from "./helpers.ts";
import { curveFromSales } from "../_shared/estimation/trend.ts";

const ID = "bffa2b67-636b-4899-ac67-9edc7576a867";

function property(overrides: Partial<PropertyRow> = {}): PropertyRow {
  return {
    id: ID,
    owner_id: "owner-1",
    status: "submitted",
    property_type: "maison",
    lat: 45.7104,
    lng: 4.7469,
    address_citycode: "69043",
    address_city: "Chaponost",
    living_area_m2: "115.00",
    rooms_count: 5,
    construction_year: 1990,
    heat_pump_year: null,
    roof_year: null,
    outdoor_equipment: null,
    pool_type: null,
    noise_level: null,
    overlooking: null,
    ...overrides,
  };
}

function dossier(overrides: Partial<PropertyRow> = {}): Dossier {
  return {
    property: property(overrides),
    parcelAreas: [300, null, 240],
    lifestyle: [{ kind: "asset", label: "Parc" }, { kind: "watch_point", label: "Route" }],
    documents: [
      { kind: "titre_propriete", status: "received" },
      { kind: "piece_identite", status: "analyzed" },
    ],
  };
}

const houses = chaponostSales().filter((s) => s.type === "maison");

function fakeDeps(overrides: Partial<Deps> = {}) {
  const updates: [string, SnapshotRow][] = [];
  const saved: SnapshotRow[] = [];
  const logs: string[] = [];
  const stale: string[] = [];
  const counted: [string, string][] = [];
  const work: Promise<void>[] = [];
  const deps: Deps = {
    loadDossier: () => Promise.resolve(dossier()),
    findFinal: () => Promise.resolve(null),
    findRunning: () => Promise.resolve(null),
    countRecentAttempts: (ownerId, since) => {
      counted.push([ownerId, since]);
      return Promise.resolve(0);
    },
    markStale: (id) => {
      stale.push(id);
      return Promise.resolve();
    },
    startSnapshot: () => Promise.resolve("snap-1"),
    updateSnapshot: (id, row) => {
      updates.push([id, row]);
      return Promise.resolve();
    },
    savePropertyEstimate: (_id, values) => {
      saved.push(values);
      return Promise.resolve();
    },
    loadOutbuildingMarket: () =>
      Promise.resolve({
        communeSales: [],
        nearbySales: [],
        dataUntil: null,
        sourceVersion: "geo-dvf 2026-05-18",
      }),
    loadMarket: () =>
      Promise.resolve({
        communeSales: houses,
        nearbySales: [],
        curve: curveFromSales(houses, "2025-12-19"),
        dataUntil: "2025-12-19",
        sourceVersion: "geo-dvf 2026-05-18",
      }),
    explain: () => Promise.resolve({ text: "Texte", source: "ai" }),
    background: (promise) => work.push(promise),
    now: () => new Date("2026-10-01T10:00:00Z"),
    log: (message) => logs.push(message),
    ...overrides,
  };
  return { deps, updates, saved, logs, work, stale, counted };
}

const post = (body: unknown, method = "POST") =>
  new Request("http://localhost/estimate-property", {
    method,
    body: method === "POST" ? JSON.stringify(body) : undefined,
  });

Deno.test("rejects other methods and invalid ids", async () => {
  const { deps } = fakeDeps();
  assertEquals((await handle(new Request("http://x", { method: "OPTIONS" }), deps)).status, 200);
  assertEquals((await handle(post(null, "GET"), deps)).status, 405);
  assertEquals((await handle(post({ property_id: "x" }), deps)).status, 400);
  assertEquals(
    (await handle(new Request("http://x", { method: "POST", body: "{" }), deps)).status,
    400,
  );
});

Deno.test("404 when the dossier is not the caller's, 409 when not sent", async () => {
  assertEquals(
    (await handle(
      post({ property_id: ID }),
      fakeDeps({ loadDossier: () => Promise.resolve(null) }).deps,
    ))
      .status,
    404,
  );
  const draft = fakeDeps({ loadDossier: () => Promise.resolve(dossier({ status: "draft" })) });
  assertEquals((await handle(post({ property_id: ID }), draft.deps)).status, 409);
});

Deno.test("returns the existing final result without recomputing", async () => {
  const { deps, work } = fakeDeps({
    findFinal: () => Promise.resolve({ status: "ok", estimate_median_eur: 1 }),
  });
  const response = await handle(post({ property_id: ID }), deps);
  assertEquals(response.status, 200);
  assertEquals(await response.json(), { status: "ok", estimate_median_eur: 1 });
  assertEquals(work.length, 0);
});

Deno.test("202 while another computation runs; a stale one is closed", async () => {
  const recent = fakeDeps({
    findRunning: () => Promise.resolve({ id: "r", created_at: "2026-10-01T09:59:00Z" }),
  });
  assertEquals((await handle(post({ property_id: ID }), recent.deps)).status, 202);
  assertEquals(recent.work.length, 0);

  const stale = fakeDeps({
    findRunning: () => Promise.resolve({ id: "r", created_at: "2026-10-01T09:50:00Z" }),
  });
  assertEquals((await handle(post({ property_id: ID }), stale.deps)).status, 202);
  assertEquals(stale.stale, ["r"]);
  assertEquals(stale.work.length, 1);

  const raced = fakeDeps({ startSnapshot: () => Promise.resolve(null) });
  assertEquals((await handle(post({ property_id: ID }), raced.deps)).status, 202);
  assertEquals(raced.work.length, 0);
});

Deno.test("409 without a title deed and an identity document", async () => {
  const missing = fakeDeps({
    loadDossier: () =>
      Promise.resolve({
        ...dossier(),
        documents: [
          { kind: "titre_propriete", status: "received" },
          { kind: "piece_identite", status: "rejected" },
        ],
      }),
  });
  const response = await handle(post({ property_id: ID }), missing.deps);
  assertEquals(response.status, 409);
  assertEquals(await response.json(), { error: "missing_documents" });
  assertEquals(missing.work.length, 0);
});

Deno.test("429 after 3 attempts in 24 h for the same user", async () => {
  const capped = fakeDeps({ countRecentAttempts: () => Promise.resolve(3) });
  const response = await handle(post({ property_id: ID }), capped.deps);
  assertEquals(response.status, 429);
  assertEquals(await response.json(), { error: "too_many_attempts" });
  assertEquals(capped.work.length, 0);
  const { deps, counted } = fakeDeps();
  await handle(post({ property_id: ID }), deps);
  assertEquals(counted, [["owner-1", "2026-09-30T10:00:00.000Z"]]);
});

Deno.test("computes in the background and stores the result once", async () => {
  const { deps, updates, saved, work } = fakeDeps();
  const response = await handle(post({ property_id: ID }), deps);
  assertEquals(response.status, 202);
  assertEquals(await response.json(), { status: "running" });
  await Promise.all(work);
  const [id, row] = updates[0];
  assertEquals(id, "snap-1");
  assertEquals(row.status, "ok");
  assertEquals(row.estimate_median_eur, 476000);
  assertEquals(row.explanation_fr, "Texte");
  assertEquals(row.explanation_source, "ai");
  assertEquals(row.error, null);
  assertEquals(row.semester_medians[0].semester, "2021-S1");
  assertEquals(saved, [{
    ai_estimate_low_eur: 419000,
    ai_estimate_median_eur: 476000,
    ai_estimate_high_eur: 540000,
    ai_estimate_confidence: row.confidence,
    ai_estimate_computed_at: "2026-10-01T10:00:00.000Z",
  }]);
});

Deno.test("records the reason of a missing estimate", async () => {
  const unsupported = fakeDeps();
  await compute(unsupported.deps, "s", ID, dossier({ property_type: "terrain" }));
  assertEquals(unsupported.updates[0][1].status, "insufficient");
  assertEquals(unsupported.updates[0][1].reason, "unsupported_type");

  const noSales = fakeDeps({
    loadMarket: () =>
      Promise.resolve({
        communeSales: [],
        nearbySales: [],
        curve: null,
        dataUntil: null,
        sourceVersion: "geo-dvf",
      }),
  });
  await compute(noSales.deps, "s", ID, dossier());
  assertEquals(noSales.updates[0][1].reason, "too_few_sales");
  assertEquals(noSales.saved, []);
});

Deno.test("an AI fallback reason and a failed copy are only logged", async () => {
  const { deps, updates, logs } = fakeDeps({
    explain: () => Promise.resolve({ text: "T", source: "template", fallbackReason: "http_500" }),
    savePropertyEstimate: () => Promise.reject(new Error("denied")),
  });
  await compute(deps, "s", ID, dossier());
  assertEquals(updates[0][1].error, "explanation: http_500");
  assertEquals(logs.length, 1);
});

Deno.test("a failure marks the snapshot as error", async () => {
  const { deps, updates } = fakeDeps({
    loadMarket: () => Promise.reject(new Error("geo-dvf down")),
  });
  await compute(deps, "s", ID, dossier());
  assertEquals(updates[0], ["s", { status: "error", error: "geo-dvf down" }]);
  const broken = fakeDeps({
    loadMarket: () => Promise.reject("boom"),
    updateSnapshot: () => Promise.reject(new Error("db down")),
  });
  await compute(broken.deps, "s", ID, dossier());
  assertEquals(broken.logs.length, 2);
});

Deno.test("toSubject validates the dossier", () => {
  assertEquals(toSubject(dossier({ property_type: null })), "unsupported_type");
  assertEquals(toSubject(dossier({ lat: null })), "missing_location");
  assertEquals(toSubject(dossier({ address_citycode: "75" })), "missing_location");
  assertEquals(toSubject(dossier({ living_area_m2: null })), "missing_area");
  assertEquals(toSubject(dossier({ living_area_m2: 5000 })), "missing_area");
  assertEquals(toSubject(dossier({ address_citycode: "67482" })), "no_dvf_coverage");
  const subject = toSubject(dossier({ outdoor_equipment: ["garage"] }));
  if (typeof subject === "string" || subject.type === "dependance") throw new Error("dwelling");
  assertEquals(subject.livingAreaM2, 115);
  assertEquals(subject.landM2, 540);
  assertEquals(subject.assets, ["Parc"]);
  assertEquals(subject.watchPoints, ["Route"]);
  assertEquals(subject.outdoorEquipment, ["garage"]);
  const noLand = toSubject({ ...dossier(), parcelAreas: [] });
  if (typeof noLand === "string" || noLand.type === "dependance") throw new Error("dwelling");
  assertEquals(noLand.landM2, null);
  assertEquals(noLand.outdoorEquipment, []);
});

Deno.test("estimates a garage from single outbuilding sales (EPIC-13)", async () => {
  const garages = [15000, 18000, 20000, 22000, 25000].map((priceEur, i) => ({
    idMutation: `g${i}`,
    insee: "69043",
    year: 2025,
    soldOn: "2025-06-01",
    priceEur,
    street: null,
    lat: 45.7104,
    lng: 4.7469,
  }));
  const { deps, updates, saved } = fakeDeps({
    loadMarket: () => Promise.reject(new Error("not for a garage")),
    loadOutbuildingMarket: () =>
      Promise.resolve({
        communeSales: garages,
        nearbySales: [],
        dataUntil: "2025-12-19",
        sourceVersion: "geo-dvf 2026-05-18",
      }),
  });
  await compute(deps, "s", ID, dossier({ property_type: "stationnement", living_area_m2: null }));
  const row = updates[0][1];
  assertEquals(row.status, "ok");
  assertEquals(row.method_version, "dvf-dependance-v1");
  assertEquals(row.property_type, "dependance");
  assertEquals(row.living_area_m2, null);
  assertEquals(row.estimate_median_eur, 20000);
  assertEquals(row.explanation_source, "template");
  assertEquals(row.source_version, "geo-dvf 2026-05-18");
  assertEquals(saved[0].ai_estimate_median_eur, 20000);

  const none = fakeDeps();
  await compute(none.deps, "s", ID, dossier({ property_type: "dependance" }));
  assertEquals(none.updates[0][1].reason, "too_few_sales");
  assertEquals(none.updates[0][1].explanation_fr, null);

  const few = fakeDeps({
    loadOutbuildingMarket: () =>
      Promise.resolve({
        communeSales: garages.slice(0, 2),
        nearbySales: [],
        dataUntil: "2025-12-19",
        sourceVersion: "geo-dvf",
      }),
  });
  await compute(few.deps, "s", ID, dossier({ property_type: "dependance" }));
  assertEquals(few.updates[0][1].reason, "too_few_sales");
});

Deno.test("toSubject maps garages and outbuildings, not the other types", () => {
  const garage = toSubject(dossier({ property_type: "stationnement", living_area_m2: null }));
  assertEquals(garage, {
    type: "dependance",
    kind: "stationnement",
    lat: 45.7104,
    lng: 4.7469,
    insee: "69043",
    city: "Chaponost",
  });
  assertEquals(
    toSubject(dossier({ property_type: "dependance", address_citycode: "67482" })),
    "no_dvf_coverage",
  );
  assertEquals(toSubject(dossier({ property_type: "dependance", lat: null })), "missing_location");
  for (const type of ["terrain", "local_commercial", "immeuble", "autre"]) {
    assertEquals(toSubject(dossier({ property_type: type })), "unsupported_type");
  }
});
