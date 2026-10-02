// EPIC-16: agent-turn records what is said for another step as pending
// answers, sends the pending ones to the prompt, masks contacts, keeps the
// evidence; the catalog of the migration matches the registry.
import { assert, assertEquals } from "jsr:@std/assert@1";
import { handleTranscribe, handleTurn, lastRetained } from "../_shared/agent/handlers.ts";
import { crossStepCatalog } from "../_shared/agent/prompt.ts";
import { stepSchema } from "../_shared/agent/steps/index.ts";
import { audioRequest, deps, FakeDb, type Handler, jsonRequest, PROPERTY } from "./agent_fakes.ts";

function agent(content: unknown, requests: Record<string, unknown>[] = [], stt = ""): Handler {
  return (url, init) => {
    const body = JSON.parse(String(init?.body ?? "{}"));
    if (JSON.stringify(body).includes("input_audio") || url.includes("transcri")) {
      return Response.json({ text: stt, usage: { seconds: 2, cost: 0.0001 } });
    }
    requests.push(body);
    return Response.json({
      choices: [{ message: { content: JSON.stringify(content) } }],
      usage: { prompt_tokens: 100, completion_tokens: 20, cost: 0.001 },
    });
  };
}

const ANSWER = {
  reply_fr: "C’est noté, appelez le 06 12 34 56 78. Avez-vous fait estimer le bien ?",
  answers: [{
    field: "purchase_year",
    value: "2012",
    confidence: 0.9,
    quote: "en 2012",
    correction: false,
  }],
  entity_ops: [],
  notes: [{ text: "Vendu meublé", quote: "vendu meublé" }],
  cross_step: {
    answers: [
      { field: "construction_year", value: "1998", confidence: 0.9, quote: "elle date de 1998" },
      { field: "heating_systems", value: "gaz", confidence: 0.6, quote: "chauffage au gaz" },
    ],
    entities: [],
    lifestyle_items: [],
    notes: [{ step: "technical", text: "Grenier aménageable", quote: "grenier aménageable" }],
  },
  out_of_step: [],
  next_field: "previously_estimated",
  done: false,
};

const TRANSCRIPT =
  "achetée en 2012, elle date de 1998, chauffage au gaz, grenier aménageable, vendu meublé, mon numéro 06 12 34 56 78";

Deno.test("agent-turn: values for other steps become pending answers", async () => {
  const db = new FakeDb();
  db.pending.push({
    id: "p0",
    property_id: PROPERTY,
    status: "pending",
    target_step: "technical",
    kind: "field",
    field: "construction_year",
    value: 1990,
    label_fr: "Construction 1990",
  }, {
    id: "q0",
    property_id: PROPERTY,
    status: "pending",
    target_step: "context",
    kind: "field",
    field: "sale_reason",
    value: "mutation",
    label_fr: "Raison mutation",
  });
  const requests: Record<string, unknown>[] = [];
  const response = await handleTurn(
    jsonRequest({ property_id: PROPERTY, step: "context", transcript: TRANSCRIPT }),
    deps(db, agent(ANSWER, requests)),
  );
  assertEquals(response.status, 200);
  const body = await response.json();
  assertEquals(body.patch, { purchase_year: 2012 });
  assertEquals(body.notes, [{ text: "Vendu meublé" }]);
  assertEquals(
    body.cross_step.map((c: Record<string, unknown>) => [c.id, c.target_step, c.field, c.value]),
    [
      ["p3", "technical", "heating_systems", ["gaz"]],
      ["p4", "technical", "construction_year", 1998],
      ["p5", "technical", null, "Grenier aménageable"],
    ],
  );
  assertEquals(body.cross_step[0].confidence, 0.6);
  assertEquals(body.superseded_ids, ["p0"]);
  // Contacts are masked before the model, in the journal and the reply.
  assertEquals(db.turns[0].transcript.includes("06 12"), false);
  assert(db.turns[0].transcript.includes("[numéro masqué]"));
  assert(body.reply_fr.includes("[numéro masqué]"));
  // deno-lint-ignore no-explicit-any
  const extracted = db.turns[0].extracted as any;
  assertEquals(extracted.evidence.map((e: { k: string }) => e.k), [
    "purchase_year",
    "note:0",
    "x:0",
    "x:1",
    "x:2",
  ]);
  assertEquals(extracted.cross_step.length, 3);
  assertEquals(db.pending.find((p) => p.id === "p4")?.turn_id, db.turns[0].id);
  assertEquals(db.pending.find((p) => p.id === "p4")?.source_step, "context");
  // The prompt: the step's pre-filled values, the others', and the
  // catalog as a second cacheable system block.
  const messages = requests[0].messages as { role: string; content: unknown }[];
  const user = messages[1].content as string;
  assert(user.includes("Valeurs pré-remplies à confirmer"), user);
  assert(user.includes("sale_reason = mutation"), user);
  assert(user.includes("Déjà noté pour d’autres étapes"), user);
  assert(!user.includes("06 12"), user);
  const system = messages[0].content as { text: string; cache_control?: unknown }[];
  assertEquals(system.length, 2);
  assert(system[1].text.startsWith("Catalogue des autres étapes"));
  assert(system[1].cache_control);
  // A correction at the next turn sees what was retained for other steps.
  assert(lastRetained(db.turns[0]).some((line) => line.startsWith("cross_step technical")));
});

Deno.test("agent-turn: answers beyond the ceiling are refused as full", async () => {
  const db = new FakeDb();
  db.pendingMax = 1;
  const response = await handleTurn(
    jsonRequest({ property_id: PROPERTY, step: "context", transcript: TRANSCRIPT }),
    deps(db, agent(ANSWER)),
  );
  const body = await response.json();
  assertEquals(body.cross_step.length, 1);
  const rejected = (db.turns[0].extracted as { rejected: { reason: string }[] }).rejected;
  assertEquals(rejected.filter((r) => r.reason === "full").length, 2);
});

Deno.test("agent-transcribe masks contacts before keeping the transcript", async () => {
  const db = new FakeDb();
  const response = await handleTranscribe(
    audioRequest(`property_id=${PROPERTY}&step=context&format=m4a`),
    deps(db, agent({}, [], "écrivez à jean.dupont@gmail.com")),
  );
  const body = await response.json();
  assertEquals(body.transcript, "écrivez à [e-mail masqué]");
  assertEquals(db.turns[0].transcript, "écrivez à [e-mail masqué]");
});

Deno.test("catalog: static per step and type, never the excluded fields", () => {
  const house = crossStepCatalog("context", { property_type: "maison" })!;
  assert(house.includes("construction_year"));
  assert(!house.includes("secret_note —"));
  assert(!house.includes("purchase_year"));
  assertEquals(crossStepCatalog("context", { property_type: "maison", roof_year: 1 }), house);
  const garage = crossStepCatalog("location", { property_type: "stationnement" })!;
  assert(garage.includes("parking_level"));
  assert(!garage.includes("lifestyle_items"));
});

Deno.test("dossier_field_catalog (migration) matches the registry", () => {
  const dir = new URL("../../migrations/", import.meta.url);
  const file = [...Deno.readDirSync(dir)].map((e) => e.name)
    .find((name) => name.endsWith("_voix_prioritaire.sql"))!;
  const sql = Deno.readTextFileSync(new URL(file, dir));
  const seed = sql.slice(sql.indexOf("insert into public.dossier_field_catalog"));
  const rows = [
    ...seed.matchAll(
      /\('(\w+)', '(\w+)', '(\w+)', '((?:[^']|'')*)', (\d+), (null|'(.*?)'::jsonb)\)/g,
    ),
  ].map((m) => ({
    step: m[1],
    entity: m[2],
    field: m[3],
    codes: m[7] ? JSON.parse(m[7].replace(/''/g, "'")) : null,
  }));
  const catalog = new Map(rows.map((r) => [`${r.entity}.${r.field}`, r]));
  const expect = (key: string, step: string, codes: Record<string, string> | null) => {
    const row = catalog.get(key);
    assert(row, key);
    assertEquals(row.step, step, key);
    assertEquals(row.codes, codes, key);
  };
  for (const step of ["location", "context", "technical", "lifestyle"] as const) {
    for (const field of stepSchema(step).fields) {
      const kind = field.kind;
      expect(
        `property.${field.column}`,
        step,
        kind.type === "enum" || kind.type === "list" ? kind.codes : null,
      );
    }
  }
  for (const field of stepSchema("context").entities[0].fields) {
    expect(`previous_estimate.${field.column}`, "context", null);
  }
  for (const field of stepSchema("rooms").entities[0].fields) {
    const kind = field.kind;
    expect(`room.${field.column}`, "rooms", kind.type === "enum" ? kind.codes : null);
  }
  for (const step of ["location", "context", "technical", "rooms", "lifestyle"]) {
    expect(`note.${step}`, step, null);
  }
  assertEquals(rows.length, catalog.size);
});
