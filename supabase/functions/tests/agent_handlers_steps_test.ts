// EPIC-14: agent-transcribe dictation, agent-turn on every step (draft,
// rooms, estimates, identity wiped, per-step model, undone turns).
import { assert, assertEquals } from "jsr:@std/assert@1";
import { agentModelFor, agentModels, DEFAULT_MODELS } from "../_shared/agent/config.ts";
import {
  ADDRESS_REMOVED,
  handleTranscribe,
  handleTurn,
  IDENTITY_REMOVED,
  lastRetained,
  roomsSummaryText,
  sanitizeDraft,
  sanitizeEstimates,
  sanitizeRooms,
} from "../_shared/agent/handlers.ts";
import { audioRequest, deps, FakeDb, type Handler, jsonRequest, PROPERTY } from "./agent_fakes.ts";

const NB = " ";

/** An OpenRouter fake: STT for audio, else [content] as the agent answer;
 * the chat requests are recorded in [requests]. */
function openrouter(
  content: unknown,
  requests: Record<string, unknown>[] = [],
  stt = "",
): Handler {
  return (url, init) => {
    if (url.includes("audio") || url.includes("transcri")) {
      return Response.json({ text: stt, usage: { seconds: 2, cost: 0.0001 } });
    }
    const body = JSON.parse(String(init?.body ?? "{}"));
    if (body.input_audio || JSON.stringify(body).includes("input_audio")) {
      return Response.json({ text: stt, usage: { seconds: 2, cost: 0.0001 } });
    }
    requests.push(body);
    return Response.json({
      choices: [{
        message: { content: typeof content === "string" ? content : JSON.stringify(content) },
      }],
      usage: { prompt_tokens: 100, completion_tokens: 20, cost: 0.001 },
    });
  };
}

/** The user message of a chat request, with plain spaces. */
function userPrompt(request: Record<string, unknown>): string {
  const messages = request.messages as { role: string; content: unknown }[];
  return (messages[1].content as string).replace(/\u00a0/g, " ");
}

Deno.test("dictation: the address is transcribed, never kept nor answered", async () => {
  const db = new FakeDb();
  const response = await handleTranscribe(
    audioRequest(`property_id=${PROPERTY}&step=location&mode=dictation`),
    deps(db, () => Response.json({ text: "12 rue des Lilas Lyon", usage: { seconds: 2 } })),
  );
  assertEquals(response.status, 200);
  const body = await response.json();
  assertEquals(body.transcript, "12 rue des Lilas Lyon");
  assertEquals(db.turns[0].transcript, ADDRESS_REMOVED);
  assertEquals(db.turns[0].error, "dictation");
  assertEquals(db.sessions[0].step, "location");
  // Its turn can never reach the language model.
  const turn = await handleTurn(
    jsonRequest({ property_id: PROPERTY, step: "location", turn_id: body.turn_id }),
    deps(db, openrouter({})),
  );
  assertEquals(turn.status, 409);
});

Deno.test("owners: co-owners confirmed, names wiped from the journal", async () => {
  const db = new FakeDb();
  const requests: Record<string, unknown>[] = [];
  const response = await handleTurn(
    jsonRequest({
      property_id: PROPERTY,
      step: "owners",
      transcript: "nous sommes deux avec mon frère Marc Durand",
      interactive: true,
      co_owners_count: 1,
    }),
    deps(
      db,
      openrouter({
        reply_fr: "C’est noté.",
        answers: [{
          field: "ownership_type",
          value: "multiple",
          confidence: 0.9,
          quote: "nous sommes deux",
          correction: false,
        }],
        entity_ops: [{
          entity: "co_owner",
          op: "create",
          target: "new",
          target_quote: "",
          correction: false,
          fields: [
            { field: "first_name", value: "Marc", confidence: 0.9, quote: "Marc" },
            { field: "last_name", value: "Durand", confidence: 0.9, quote: "Durand" },
          ],
        }],
        out_of_step: [],
        next_field: "none",
        done: false,
      }, requests),
    ),
  );
  assertEquals(response.status, 200);
  const body = await response.json();
  assertEquals(body.patch, { ownership_type: "multiple" });
  assertEquals(body.confirmations[0].label_fr, `Marc Durand${NB}?`);
  assertEquals(body.confirmations[0].entity_ops[0].values, {
    first_name: "Marc",
    last_name: "Durand",
  });
  assertEquals(db.turns[0].transcript, IDENTITY_REMOVED);
  const journal = JSON.stringify(db.turns[0].extracted);
  assert(!journal.includes("Marc") && !journal.includes("Durand"), journal);
  assert(userPrompt(requests[0]).includes("Co-propriétaires déjà notés : 1"));
  // The owners' schema has the co-owner entity.
  const schema =
    (requests[0].response_format as { json_schema: { schema: { required: string[] } } })
      .json_schema.schema;
  assert(schema.required.includes("entity_ops"));

  // A failed agent call forgets the names too.
  const failed = new FakeDb();
  await handleTurn(
    jsonRequest({ property_id: PROPERTY, step: "owners", transcript: "avec Marc Durand" }),
    deps(failed, () => new Response("x", { status: 500 })),
  );
  assertEquals(failed.turns[0].transcript, IDENTITY_REMOVED);
});

Deno.test("rooms: table, draft, last turn and a per-step model", async () => {
  const db = new FakeDb();
  const requests: Record<string, unknown>[] = [];
  const models = { ...DEFAULT_MODELS, agentByStep: { rooms: "anthropic/claude-haiku-4.5" } };
  const answer = {
    reply_fr: "Noté.",
    answers: [],
    entity_ops: [{
      entity: "room",
      op: "update",
      target: "R1",
      target_quote: "le séjour",
      correction: true,
      fields: [{ field: "area_m2", value: "40", confidence: 0.9, quote: "plutôt 40" }],
      copy_from: "",
      copy_fields: [],
      copy_quote: "",
    }],
    out_of_step: [],
    next_field: "room",
    done: false,
  };
  const request = (transcript: string) =>
    jsonRequest({
      property_id: PROPERTY,
      step: "rooms",
      transcript,
      interactive: true,
      last_room_ref: "R1",
      rooms: [
        {
          ref: "R1",
          name: "Séjour",
          level: "rdc",
          area_m2: 38,
          floor_covering: "parquet_chene",
          glazing: "double",
          is_annex: false,
        },
        { ref: "bad", name: "x", area_m2: 3 },
        { ref: "R2", name: "<Cuisine>", area_m2: 12, level: "nowhere" },
      ],
    });
  const first = await handleTurn(
    request("le séjour fait 38 m²"),
    deps(db, openrouter({ ...answer, entity_ops: [] }, requests), [], models),
  );
  assertEquals(first.status, 200);
  const response = await handleTurn(
    request("non le séjour fait plutôt 40"),
    deps(db, openrouter(answer, requests), [], models),
  );
  const body = await response.json();
  assertEquals(body.entity_ops.length, 1);
  assertEquals(body.entity_ops[0].target, "R1");
  assertEquals(body.entity_ops[0].values, { area_m2: 40 });
  assertEquals(body.corrections, ["room:R1"]);
  assertEquals(requests[1].model, "anthropic/claude-haiku-4.5");
  assertEquals(requests[1].max_tokens, 2500);
  const prompt = userPrompt(requests[1]);
  assert(prompt.includes("R1 · Séjour · RDC · 38 m² · Parquet chêne · Double vitrage"), prompt);
  assert(prompt.includes("R2 · ‹Cuisine›"), prompt);
  assert(!prompt.includes("bad"));
});

Deno.test("context: draft values and estimate cards", async () => {
  const db = new FakeDb();
  const requests: Record<string, unknown>[] = [];
  const response = await handleTurn(
    jsonRequest({
      property_id: PROPERTY,
      step: "context",
      transcript: "achetée en 2012",
      interactive: true,
      draft: {
        purchase_year: 2010,
        property_type: "appartement",
        construction_year: 1990,
        sale_reason: ["x"],
      },
      estimates: [{
        ref: "E1",
        price_eur: 300000,
        estimated_month: "2024-03-01",
        agency_name: "<A>",
      }],
    }),
    deps(
      db,
      openrouter({
        reply_fr: "Merci.",
        answers: [{
          field: "purchase_year",
          value: "2012",
          confidence: 0.9,
          quote: "achetée en 2012",
          correction: false,
        }],
        entity_ops: [],
        out_of_step: [],
        next_field: "none",
        done: false,
      }, requests),
    ),
  );
  const body = await response.json();
  assertEquals(body.patch, { purchase_year: 2012 });
  assertEquals(body.facts[0].changed_fr, `Modifié${NB}: 2010 → 2012`);
  const prompt = userPrompt(requests[0]);
  assert(prompt.includes("Type de bien : appartement"), prompt);
  assert(prompt.includes("E1 · 300 000 € · 03/2024 · ‹A›"), prompt);
});

Deno.test("undone turns are marked, alone or with a turn", async () => {
  const db = new FakeDb();
  await handleTurn(
    jsonRequest({ property_id: PROPERTY, step: "technical", transcript: "construite en 1998" }),
    deps(
      db,
      openrouter({ reply_fr: "Ok", answers: [], out_of_step: [], next_field: "none", done: false }),
    ),
  );
  const id = db.turns[0].id;
  const response = await handleTurn(
    jsonRequest({ property_id: PROPERTY, step: "technical", undone_turn_ids: [id, "nope"] }),
    deps(db, openrouter({})),
  );
  assertEquals(await response.json(), { undone: 1 });
  assertEquals(db.turns[0].undone, true);
  const empty = await handleTurn(
    jsonRequest({ property_id: PROPERTY, step: "technical" }),
    deps(db, openrouter({})),
  );
  assertEquals(empty.status, 400);
});

Deno.test("sanitizers and last retained values", () => {
  assertEquals(sanitizeDraft("technical", "x"), {});
  assertEquals(sanitizeDraft("technical", { big: "x".repeat(5000) }), {});
  assertEquals(
    sanitizeDraft("technical", {
      construction_year: 1998,
      heating_systems: ["gaz", 3],
      orientation: "sud",
      purchase_year: 2000,
      living_area_m2: Infinity,
      levels: { x: 1 },
    }),
    { construction_year: 1998, heating_systems: ["gaz"], orientation: "sud" },
  );
  assertEquals(sanitizeRooms("x"), []);
  assertEquals(sanitizeRooms([null, { ref: "R1", name: "A", area_m2: 0 }]), []);
  assertEquals(
    sanitizeRooms([
      { ref: "R1", name: " A ", area_m2: 4, glazing: "triple", ceiling_height_m: 2.5 },
      { ref: "R1", name: "B", area_m2: 4 },
    ]),
    [{
      ref: "R1",
      name: "A",
      level: null,
      area_m2: 4,
      floor_covering: null,
      glazing: "triple",
      ceiling_height_m: 2.5,
      is_annex: false,
    }],
  );
  assertEquals(sanitizeEstimates("x"), []);
  assertEquals(
    sanitizeEstimates([3, { ref: "E1", price_eur: "x", estimated_month: "03/2024" }, {
      ref: "E1",
    }]),
    [{ ref: "E1", price_eur: null, estimated_month: null, agency_name: null }],
  );
  assertEquals(lastRetained(undefined), []);
  assertEquals(
    lastRetained({
      id: "t",
      session_id: "s",
      transcript: "",
      reply_fr: null,
      tts_ms: null,
      cost_usd: null,
      extracted: {
        patch: { construction_year: 1998, heating_systems: ["gaz", "bois"] },
        entity_ops: [{ entity: "room", op: "create", target: "new", label_fr: "Séjour" }, 3],
      },
    }),
    ["construction_year = 1998", "heating_systems = gaz, bois", "room create new : Séjour"],
  );
});

Deno.test("per-step agent models from the secrets", () => {
  const env = new Map([
    ["OPENROUTER_MODEL_AGENT", "a/common"],
    ["OPENROUTER_MODEL_AGENT_ROOMS", " anthropic/claude-haiku-4.5 "],
    ["OPENROUTER_MODEL_AGENT_OWNERS", " "],
  ]);
  const models = agentModels({ get: (k) => env.get(k) });
  assertEquals(models.agentByStep, { rooms: "anthropic/claude-haiku-4.5" });
  assertEquals(agentModelFor(models, "rooms"), "anthropic/claude-haiku-4.5");
  assertEquals(agentModelFor(models, "owners"), "a/common");
  assertEquals(agentModelFor(DEFAULT_MODELS, "rooms"), DEFAULT_MODELS.agent);
});

Deno.test("rooms: the spoken summary needs no model", async () => {
  const db = new FakeDb();
  const requests: Record<string, unknown>[] = [];
  const response = await handleTurn(
    jsonRequest({
      property_id: PROPERTY,
      step: "rooms",
      summary: true,
      rooms: [
        { ref: "R1", name: "Séjour", area_m2: 38.5 },
        { ref: "R2", name: "Cellier", area_m2: 4, is_annex: true },
      ],
    }),
    deps(db, openrouter({}, requests)),
  );
  const body = await response.json();
  assertEquals(
    body.reply_fr.replace(/\u00a0/g, " "),
    "J’ai noté 2 pièces pour 38,5 m² habitables, plus 4 m² d’annexes. Est-ce correct ?",
  );
  assertEquals(requests.length, 0);
  assertEquals(db.turns[0].reply_fr, body.reply_fr);
  assertEquals(db.turns[0].error, null);
  assertEquals(roomsSummaryText([]).startsWith("Je n’ai noté aucune pièce"), true);
  assertEquals(
    roomsSummaryText([{
      ref: "R1",
      name: "Séjour",
      level: null,
      area_m2: 20,
      floor_covering: null,
      glazing: null,
      ceiling_height_m: null,
      is_annex: false,
    }]).replace(/\u00a0/g, " "),
    "J’ai noté 1 pièce pour 20 m² habitables. Est-ce correct ?",
  );
  db.usage = { turns: 120, audioSeconds: 0 };
  const quota = await handleTurn(
    jsonRequest({ property_id: PROPERTY, step: "rooms", summary: true, rooms: [] }),
    deps(db, openrouter({})),
  );
  assertEquals(quota.status, 429);
});
