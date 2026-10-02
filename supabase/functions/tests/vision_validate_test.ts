// EPIC-15: validation of the vision AI outputs, configuration and parity
// of the options with the app's V5c form.
import { assert, assertEquals, assertThrows } from "jsr:@std/assert@1";
import { DEFAULT_VISION_MODEL, visionModels } from "../_shared/vision/config.ts";
import { startOfDay } from "../_shared/vision/db.ts";
import { visionMessages } from "../_shared/vision/prompt.ts";
import {
  FLOOR_COVERINGS,
  GLAZINGS,
  LEVELS,
  PLAN_SCHEMA,
  ROOM_KINDS,
  ROOM_PHOTO_SCHEMA,
} from "../_shared/vision/schema.ts";
import {
  InvalidOutput,
  validatePlanReading,
  validateRoomAnalysis,
} from "../_shared/vision/validate.ts";

const NOW = new Date("2026-10-02T10:00:00Z");

Deno.test("options match the app (vision_options.json)", () => {
  const fixture = JSON.parse(
    Deno.readTextFileSync(new URL("./fixtures/vision_options.json", import.meta.url)),
  );
  assertEquals([...ROOM_KINDS], fixture.room_kinds);
  assertEquals([...FLOOR_COVERINGS], fixture.floor_coverings);
  assertEquals([...GLAZINGS], fixture.glazings);
  assertEquals([...LEVELS], fixture.levels);
});

Deno.test("schemas require every field and allow unknown", () => {
  const room = ROOM_PHOTO_SCHEMA.schema;
  assertEquals(room.required.length, Object.keys(room.properties).length);
  assert(room.properties.room_kind.enum.includes("unknown"));
  const plan = PLAN_SCHEMA.schema;
  assertEquals(plan.required.length, Object.keys(plan.properties).length);
});

Deno.test("models come from the secrets, cheapest by default", () => {
  const env = (values: Record<string, string>) => ({ get: (name: string) => values[name] });
  assertEquals(visionModels(env({})), {
    room: DEFAULT_VISION_MODEL,
    plan: DEFAULT_VISION_MODEL,
  });
  assertEquals(visionModels(env({ OPENROUTER_MODEL_VISION: " a/b " })), {
    room: "a/b",
    plan: "a/b",
  });
  assertEquals(
    visionModels(env({ OPENROUTER_MODEL_VISION: "a/b", OPENROUTER_MODEL_PLAN: "c/d" })),
    { room: "a/b", plan: "c/d" },
  );
  assertEquals(visionModels(env({ OPENROUTER_MODEL_VISION: "  " })).room, DEFAULT_VISION_MODEL);
});

Deno.test("messages carry the instructions and the image", () => {
  const messages = visionMessages("rules", "data:image/jpeg;base64,AAA");
  assertEquals(messages[0], { role: "system", content: "rules" });
  assertEquals(messages[1].content[1], {
    type: "image_url",
    image_url: { url: "data:image/jpeg;base64,AAA" },
  });
});

Deno.test("startOfDay is midnight UTC", () => {
  assertEquals(
    startOfDay(new Date("2026-10-02T23:59:00Z")).toISOString(),
    "2026-10-02T00:00:00.000Z",
  );
});

Deno.test("room analysis keeps whitelisted values only", () => {
  const analysis = validateRoomAnalysis(
    JSON.stringify({
      room_kind: "kitchen",
      floor_covering: "carrelage",
      glazing: "unknown",
      condition_notes: [
        "Traces d’humidité au plafond",
        "  Traces d’humidité  au plafond ",
        "Pièce de 12 m²",
        "Hauteur 2,50 m",
        "Pièce de douze mètres carrés",
        "Grande surface vitrée",
        "Environ trois m² de carrelage abîmé",
        "x",
        "Cuisine équipée",
        "Peinture écaillée",
        "Joints noircis",
        "Une note de trop",
        42,
      ],
      personal_items: ["Photos de famille", "Courrier", "Code 1234"],
      people_visible: true,
      quality_issues: ["dark", "nope", "blurry"],
    }),
    "m/x",
    NOW,
  );
  assertEquals(analysis, {
    version: 1,
    room_kind: "kitchen",
    floor_covering: "carrelage",
    glazing: null,
    condition_notes: [
      "Traces d’humidité au plafond",
      "Cuisine équipée",
      "Peinture écaillée",
      "Joints noircis",
    ],
    personal_items: ["Photos de famille", "Courrier"],
    people_visible: true,
    quality_issues: ["dark", "blurry"],
    model: "m/x",
    analyzed_at: NOW.toISOString(),
  });
});

Deno.test("room analysis drops unknown enums and odd lists", () => {
  const analysis = validateRoomAnalysis(
    JSON.stringify({
      room_kind: "castle",
      floor_covering: 3,
      glazing: "double",
      condition_notes: "not a list",
      personal_items: null,
      people_visible: false,
      quality_issues: "dark",
    }),
    "m",
    NOW,
  );
  assertEquals(analysis.room_kind, null);
  assertEquals(analysis.floor_covering, null);
  assertEquals(analysis.glazing, "double");
  assertEquals(analysis.condition_notes, []);
  assertEquals(analysis.personal_items, []);
  assertEquals(analysis.quality_issues, []);
});

Deno.test("an unusable answer is rejected", () => {
  assertThrows(() => validateRoomAnalysis("nope", "m", NOW), InvalidOutput);
  assertThrows(() => validateRoomAnalysis("[1]", "m", NOW), InvalidOutput);
  assertThrows(() => validateRoomAnalysis("null", "m", NOW), InvalidOutput);
  assertThrows(() => validateRoomAnalysis("{}", "m", NOW), InvalidOutput);
  assertThrows(() => validatePlanReading('{"is_floor_plan":true}', "m", NOW), InvalidOutput);
  assertThrows(() => validatePlanReading('{"rooms":[]}', "m", NOW), InvalidOutput);
});

Deno.test("plan reading keeps printed rooms and plausible areas", () => {
  const reading = validatePlanReading(
    JSON.stringify({
      is_floor_plan: true,
      rooms: [
        { name: " Séjour ", area_m2: 25.456, level: "rdc", kind: "livingRoom" },
        { name: "Chambre 2", area_m2: null, level: "unknown", kind: "bedroom" },
        { name: "Placard", area_m2: 0.2, level: "etage_9", kind: "closet" },
        { name: "", area_m2: 10, level: null, kind: null },
        { name: "<>{}", area_m2: 10, level: null, kind: null },
        { name: "Salle d’eau <script>", area_m2: 4, level: null, kind: null },
        { name: "x".repeat(61), area_m2: 1, level: null, kind: null },
        "garbage",
        null,
        { name: "Garage", area_m2: 2000, level: "rdc", kind: "garage" },
      ],
      printed_total_m2: 26,
    }),
    "m/p",
    NOW,
  );
  assertEquals(reading, {
    version: 1,
    is_floor_plan: true,
    rooms: [
      { name: "Séjour", area_m2: 25.46, level: "rdc", kind: "livingRoom" },
      { name: "Chambre 2", area_m2: null, level: null, kind: "bedroom" },
      { name: "Placard", area_m2: null, level: null, kind: null },
      { name: "Salle d’eau script", area_m2: 4, level: null, kind: null },
      { name: "x".repeat(40), area_m2: 1, level: null, kind: null },
      { name: "Garage", area_m2: null, level: "rdc", kind: "garage" },
    ],
    printed_total_m2: 26,
    rooms_total_m2: 30.46,
    total_matches: false,
    model: "m/p",
    read_at: NOW.toISOString(),
  });
});

Deno.test("plan reading compares the sum with the printed total", () => {
  const read = (total: unknown) =>
    validatePlanReading(
      JSON.stringify({
        is_floor_plan: true,
        rooms: [{ name: "A", area_m2: 50, level: null, kind: null }],
        printed_total_m2: total,
      }),
      "m",
      NOW,
    );
  assertEquals(read(60).total_matches, false);
  assertEquals(read(null).total_matches, null);
  assertEquals(read(0).printed_total_m2, null);
});

Deno.test("plan reading caps the rooms and ignores a non-plan", () => {
  const many = Array.from({ length: 50 }, (_, i) => ({
    name: `Pièce ${i}`,
    area_m2: 1,
    level: null,
    kind: null,
  }));
  const capped = validatePlanReading(
    JSON.stringify({ is_floor_plan: true, rooms: many, printed_total_m2: null }),
    "m",
    NOW,
  );
  assertEquals(capped.rooms.length, 40);
  const notPlan = validatePlanReading(
    JSON.stringify({ is_floor_plan: false, rooms: many, printed_total_m2: 100 }),
    "m",
    NOW,
  );
  assertEquals(notPlan.rooms, []);
  assertEquals(notPlan.printed_total_m2, null);
  assertEquals(notPlan.rooms_total_m2, 0);
});
