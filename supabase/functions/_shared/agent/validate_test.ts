import { assert, assertEquals } from "jsr:@std/assert@1";
import {
  factLabel,
  type ModelOutput,
  normalize,
  parseModelOutput,
  quoteFound,
  validateTurn,
} from "./validate.ts";
import {
  fieldByColumn,
  isAsked,
  missingFields,
  outputSchema,
  promptFields,
} from "./schema.ts";

const transcript =
  "Alors la maison date de 1998, elle est construite en parpaing, avec une " +
  "toiture en tuiles qu’on a refaite en 2016.";

function output(partial: Partial<ModelOutput>): ModelOutput {
  return {
    reply_fr: "Merci.",
    answers: [],
    lifestyle_items: [],
    next_field: "none",
    done: false,
    ...partial,
  };
}

const house = { property_type: "maison" };

Deno.test("normalize and quoteFound", () => {
  assertEquals(normalize("Tout-à-l’égout !"), "tout a l egout");
  assert(quoteFound("refaite en 2016", transcript));
  assert(quoteFound("Construite en PARPAING", transcript));
  assert(!quoteFound("en béton", transcript));
  assert(!quoteFound("", transcript));
  assert(!quoteFound("par", transcript)); // whole words only
});

Deno.test("accepts valid answers with facts", () => {
  const result = validateTurn(
    output({
      answers: [
        {
          field: "construction_year",
          value: "1998",
          confidence: 0.95,
          quote: "date de 1998",
        },
        {
          field: "wall_material",
          value: "parpaing",
          confidence: 0.9,
          quote: "en parpaing",
        },
        {
          field: "roof_type",
          value: "tuiles",
          confidence: 0.9,
          quote: "toiture en tuiles",
        },
        {
          field: "roof_year",
          value: "2016",
          confidence: 0.85,
          quote: "refaite en 2016",
        },
      ],
    }),
    { step: "technical", values: house, transcript, currentYear: 2026 },
  );
  assertEquals(result.patch, {
    construction_year: 1998,
    wall_material: "parpaing",
    roof_type: "tuiles",
    roof_year: 2016,
  });
  assertEquals(result.facts.map((f) => f.label_fr), [
    "Construction 1998",
    "Parpaing",
    "Toiture tuiles",
    "Année toiture 2016",
  ]);
  assertEquals(result.rejected, []);
  assertEquals(result.pending, []);
});

Deno.test("rejects invented, unknown, invalid and low-confidence answers", () => {
  const result = validateTurn(
    output({
      answers: [
        {
          field: "construction_year",
          value: "2050",
          confidence: 0.9,
          quote: "date de 1998",
        },
        {
          field: "living_area_m2",
          value: "120",
          confidence: 0.9,
          quote: "cent vingt",
        },
        {
          field: "owner_name",
          value: "Dupont",
          confidence: 1,
          quote: "maison",
        },
        {
          field: "wall_material",
          value: "granit",
          confidence: 0.9,
          quote: "en parpaing",
        },
        {
          field: "roof_type",
          value: "tuiles",
          confidence: 0.5,
          quote: "tuiles",
        },
        { field: "roof_year", value: "16", confidence: 0.9, quote: "2016" },
      ],
    }),
    { step: "technical", values: house, transcript, currentYear: 2026 },
  );
  assertEquals(result.patch, {});
  assertEquals(
    result.rejected.map((r) => r.reason),
    [
      "out_of_range",
      "quote_not_found",
      "unknown_field",
      "invalid_value",
      "low_confidence",
      "invalid_value",
    ],
  );
  assertEquals(result.pending.map((p) => p.label_fr), [
    "Construction ?",
    "Murs ?",
    "Toiture ?",
    "Année toiture ?",
  ]);
});

Deno.test("cross-field rules and conditional fields", () => {
  const text =
    "pompe à chaleur air eau, piscine de 8 sur 4, séjour de 300 m², " +
    "toiture refaite en 1950, 2 pièces et 3 chambres";
  const result = validateTurn(
    output({
      answers: [
        {
          field: "heat_pump_type",
          value: "air_eau",
          confidence: 0.9,
          quote: "air eau",
        },
        {
          field: "heating_systems",
          value: "pac",
          confidence: 0.9,
          quote: "pompe à chaleur",
        },
        {
          field: "pool_length_m",
          value: "8",
          confidence: 0.9,
          quote: "8 sur 4",
        },
        {
          field: "living_room_area_m2",
          value: "300",
          confidence: 0.9,
          quote: "séjour de 300 m²",
        },
        {
          field: "roof_year",
          value: "1950",
          confidence: 0.9,
          quote: "refaite en 1950",
        },
        {
          field: "rooms_count",
          value: "2",
          confidence: 0.9,
          quote: "2 pièces",
        },
        {
          field: "bedrooms_count",
          value: "3",
          confidence: 0.9,
          quote: "3 chambres",
        },
      ],
    }),
    {
      step: "technical",
      values: {
        property_type: "maison",
        construction_year: 1975,
        living_area_m2: 100,
        heating_systems: ["bois"],
      },
      transcript: text,
      currentYear: 2026,
    },
  );
  assertEquals(result.patch, {
    heating_systems: ["pac", "bois"],
    heat_pump_type: "air_eau",
    rooms_count: 2,
  });
  assertEquals(
    result.rejected.map((r) => [r.field, r.reason]),
    [
      ["pool_length_m", "not_asked"],
      ["living_room_area_m2", "inconsistent"],
      ["roof_year", "inconsistent"],
      ["bedrooms_count", "inconsistent"],
    ],
  );
});

Deno.test("apartment fields and decimals", () => {
  const text = "un appartement de 62,5 m² sur deux niveaux, mitoyen";
  const result = validateTurn(
    output({
      answers: [
        {
          field: "living_area_m2",
          value: "62,5",
          confidence: 0.9,
          quote: "62,5 m²",
        },
        {
          field: "levels",
          value: "r1",
          confidence: 0.9,
          quote: "deux niveaux",
        },
        {
          field: "living_room_area_m2",
          value: "abc",
          confidence: 0.9,
          quote: "appartement",
        },
        {
          field: "rooms_count",
          value: "99",
          confidence: 0.9,
          quote: "appartement",
        },
      ],
    }),
    {
      step: "technical",
      values: { property_type: "appartement" },
      transcript: text,
      currentYear: 2026,
    },
  );
  assertEquals(result.patch, { living_area_m2: 62.5 });
  assertEquals(result.facts[0].label_fr, "Surface habitable 62,5 m²");
  assertEquals(result.rejected.map((r) => r.reason), [
    "not_asked",
    "invalid_value",
    "out_of_range",
  ]);
});

Deno.test("lifestyle items, noise, overlooking and secret note", () => {
  const text = "Le quartier est très calme, l’école est à cinq minutes, la " +
    "boulangerie a fermé, aucun vis-à-vis, on veut vendre avant la rentrée";
  const result = validateTurn(
    output({
      answers: [
        {
          field: "noise_level",
          value: "2",
          confidence: 0.8,
          quote: "très calme",
        },
        {
          field: "overlooking",
          value: "aucun",
          confidence: 0.9,
          quote: "aucun vis-à-vis",
        },
        {
          field: "secret_note",
          value: "Vendre avant la rentrée",
          confidence: 0.8,
          quote: "vendre avant la rentrée",
        },
      ],
      lifestyle_items: [
        {
          kind: "asset",
          label: "École à cinq minutes",
          quote: "l’école est à cinq minutes",
        },
        {
          kind: "watch_point",
          label: "Boulangerie fermée",
          quote: "la boulangerie a fermé",
        },
        { kind: "asset", label: "Quartier calme", quote: "très calme" },
        { kind: "asset", label: "Ok", quote: "très calme" },
        { kind: "asset", label: "Piscine municipale", quote: "piscine" },
        { kind: "other", label: "Autre chose", quote: "très calme" },
        {
          kind: "asset",
          label: "École  à cinq minutes",
          quote: "l’école est à cinq minutes",
        },
      ],
    }),
    {
      step: "lifestyle",
      values: house,
      transcript: text,
      currentYear: 2026,
      lifestyleLabels: { asset: ["Quartier calme"], watch_point: [] },
    },
  );
  assertEquals(result.patch, { noise_level: 2, overlooking: "aucun" });
  assertEquals(result.suggestions, { secret_note: "Vendre avant la rentrée" });
  assertEquals(result.facts.map((f) => f.label_fr), [
    "Bruit 2/10",
    "Vis-à-vis aucun",
  ]);
  assertEquals(result.lifestyle_items, [
    { kind: "asset", label: "École à cinq minutes" },
    { kind: "watch_point", label: "Boulangerie fermée" },
  ]);
  assertEquals(result.rejected.map((r) => r.reason), [
    "duplicate",
    "out_of_range",
    "quote_not_found",
    "invalid_value",
    "duplicate",
  ]);
});

Deno.test("lifestyle lists are capped at 10 per kind", () => {
  const result = validateTurn(
    output({
      lifestyle_items: [{ kind: "asset", label: "Vue mer", quote: "vue mer" }],
    }),
    {
      step: "lifestyle",
      values: house,
      transcript: "vue mer",
      currentYear: 2026,
      lifestyleLabels: {
        asset: Array.from({ length: 10 }, (_, i) => `Atout ${i}`),
        watch_point: [],
      },
    },
  );
  assertEquals(result.lifestyle_items, []);
  assertEquals(result.rejected[0].reason, "full");
});

Deno.test("parseModelOutput tolerates noise and bad entries", () => {
  const parsed = parseModelOutput(
    'Voici : {"reply_fr":" Merci ","answers":[{"field":"rooms_count","value":4},' +
      '{"value":1},{"field":"x"}],"lifestyle_items":[{"kind":"asset","label":"Vue"},3],' +
      '"next_field":"levels","done":true}',
  );
  assertEquals(parsed.reply_fr, "Merci");
  assertEquals(parsed.answers, [
    { field: "rooms_count", value: "4", confidence: 0, quote: "" },
    { field: "x", value: "", confidence: 0, quote: "" },
  ]);
  assertEquals(parsed.lifestyle_items, [{
    kind: "asset",
    label: "Vue",
    quote: "",
  }]);
  assertEquals(parsed.next_field, "levels");
  assertEquals(parsed.done, true);
  const empty = parseModelOutput("{}");
  assertEquals(empty, {
    reply_fr: "",
    answers: [],
    lifestyle_items: [],
    next_field: "none",
    done: false,
  });
  let threw = false;
  try {
    parseModelOutput("pas de JSON");
  } catch {
    threw = true;
  }
  assert(threw);
});

Deno.test("schema helpers", () => {
  const land = { property_type: "terrain" };
  assertEquals(missingFields("technical", land).map((f) => f.column), [
    "sanitation",
    "outdoor_equipment",
  ]);
  assert(
    !isAsked(fieldByColumn("technical", "levels")!, {
      property_type: "appartement",
    }),
  );
  assert(
    promptFields("technical", house).some((f) => f.column === "pool_type"),
  );
  const schema = outputSchema("lifestyle") as {
    properties: { next_field: { enum: string[] } };
  };
  assertEquals(schema.properties.next_field.enum, [
    "noise_level",
    "overlooking",
    "secret_note",
    "none",
  ]);
  assertEquals(
    factLabel(fieldByColumn("technical", "heating_systems")!, ["pac", "gaz"]),
    "Pompe à chaleur, Gaz",
  );
  assertEquals(
    factLabel(fieldByColumn("technical", "pool_width_m")!, 4),
    "Largeur piscine 4 m",
  );
  assertEquals(
    factLabel(fieldByColumn("lifestyle", "secret_note")!, "x"),
    "Note secrète",
  );
  assertEquals(
    factLabel(fieldByColumn("technical", "rooms_count")!, 4),
    "4 pièces",
  );
});
