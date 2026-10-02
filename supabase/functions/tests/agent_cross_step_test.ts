// EPIC-16: answers said for another step (pending answers), notes, evidence
// and masked contacts, on the validation side.
import { assert, assertEquals } from "jsr:@std/assert@1";
import { maskContacts } from "../_shared/agent/anchors.ts";
import { crossStepSchema, outputSchema } from "../_shared/agent/schema.ts";
import { crossStepTargets } from "../_shared/agent/steps/index.ts";
import {
  type ModelCrossStep,
  parseModelOutput,
  validateTurn,
  type ValidationContext,
} from "../_shared/agent/validate.ts";
import { answer, f, output } from "./agent_helpers.ts";

const NB = " ";

function ctx(partial: Partial<ValidationContext>): ValidationContext {
  return {
    step: "context",
    values: { property_type: "maison" },
    transcript: "",
    currentYear: 2026,
    currentMonth: 10,
    interactive: true,
    ...partial,
  };
}

function cross(partial: Partial<ModelCrossStep>): ModelCrossStep {
  return { answers: [], entities: [], lifestyle_items: [], notes: [], ...partial };
}

Deno.test("cross-step targets: other voiced steps, never the type nor the secret note", () => {
  const house = crossStepTargets("context", { property_type: "maison" });
  const columns = house.fields.map((t) => t.field.column);
  assert(columns.includes("construction_year"));
  assert(columns.includes("heating_systems"));
  assert(columns.includes("pool_type")); // with its condition
  assert(columns.includes("special_situations"));
  assert(columns.includes("noise_level"));
  assert(!columns.includes("purchase_year")); // own step
  assert(!columns.includes("property_type"));
  assert(!columns.includes("secret_note"));
  assertEquals(house.entities.map((t) => t.entity.name), ["room"]);
  assertEquals(house.lifestyle, true);
  assertEquals(house.noteSteps, ["location", "technical", "rooms", "lifestyle"]);
  // From V4b, the estimates of V3 may be said; a garage has no rooms nor V6.
  const garage = crossStepTargets("technical", { property_type: "stationnement" });
  assertEquals(garage.entities.map((t) => t.entity.name), ["previous_estimate"]);
  assertEquals(garage.lifestyle, false);
  assertEquals(garage.noteSteps, ["location", "context"]);
  // The schema follows the targets (and never offers an empty enum).
  const schema = crossStepSchema("context", { property_type: "maison" }) as {
    properties: { answers: { items: { properties: { field: { enum: string[] } } } } };
  };
  assert(schema.properties.answers.items.properties.field.enum.includes("roof_year"));
  const lifestyle = outputSchema("lifestyle", { property_type: "local_commercial" }) as {
    properties: {
      cross_step: {
        properties: { entities: { items: { properties: { entity: { enum: string[] } } } } };
      };
    };
  };
  assertEquals(
    lifestyle.properties.cross_step.properties.entities.items.properties.entity.enum,
    ["previous_estimate"],
  );
});

Deno.test("V3: values for V4b and V6 become pending answers with their evidence", () => {
  const transcript =
    "On l’a achetée 320 000 € en 2012, elle date de 1998, chauffage au gaz, et il y a une école au bout de la rue.";
  const result = validateTurn(
    output({
      answers: [
        answer("purchase_price_eur", "320000", "320 000 €"),
        answer("purchase_year", "2012", "en 2012"),
      ],
      cross_step: cross({
        answers: [
          answer("construction_year", "1998", "elle date de 1998"),
          answer("heating_systems", "gaz", "chauffage au gaz"),
        ],
        lifestyle_items: [{
          kind: "asset",
          label: "École au bout de la rue",
          quote: "une école au bout de la rue",
        }],
      }),
    }),
    ctx({ transcript }),
  );
  assertEquals(result.patch, { purchase_price_eur: 320000, purchase_year: 2012 });
  assertEquals(result.cross_step.map((c) => [c.target_step, c.kind, c.field, c.value]), [
    ["technical", "field", "heating_systems", ["gaz"]],
    ["technical", "field", "construction_year", 1998],
    ["lifestyle", "lifestyle_item", null, { kind: "asset", label: "École au bout de la rue" }],
  ]);
  assertEquals(result.cross_step[1].label_fr, "Construction 1998");
  assertEquals(result.cross_step[2].label_fr, `Atout${NB}: École au bout de la rue`);
  assertEquals(result.evidence.map((e) => e.k), [
    "purchase_price_eur",
    "purchase_year",
    "x:0",
    "x:1",
    "x:2",
  ]);
  assertEquals(result.evidence[2], { k: "x:0", v: ["gaz"], q: "chauffage au gaz", c: 0.9 });
});

Deno.test("cross-step answers: refusals, confidence, rules, duplicates, replacements", () => {
  const transcript =
    "c’est une maison, toiture refaite en 1990, construite en 1998, 4 pièces, 6 chambres, " +
    "ma note secrète, une piscine, plutôt 1985";
  const result = validateTurn(
    output({
      cross_step: cross({
        answers: [
          answer("property_type", "maison", "c’est une maison"),
          answer("secret_note", "ma note secrète", "ma note secrète"),
          answer("roof_year", "1990", "toiture refaite en 1990", 0.4),
          answer("construction_year", "1998", "construite en 1998", 0.6),
          answer("rooms_count", "4", "4 pièces"),
          answer("bedrooms_count", "6", "6 chambres"),
          answer("outdoor_equipment", "piscine", "une piscine"),
          answer("pool_length_m", "10", "dix mètres"),
          answer("living_area_m2", "120", "120"),
        ],
      }),
    }),
    ctx({
      transcript,
      values: { property_type: "maison", outdoor_equipment: ["piscine"], rooms_count: 4 },
    }),
  );
  assertEquals(result.rejected.map((r) => [r.field, r.reason]), [
    ["x:outdoor_equipment", "duplicate"],
    ["x:property_type", "unknown_field"],
    ["x:secret_note", "unknown_field"],
    ["x:roof_year", "low_confidence"],
    ["x:rooms_count", "duplicate"],
    ["x:bedrooms_count", "inconsistent"],
    ["x:pool_length_m", "quote_not_found"],
    ["x:living_area_m2", "quote_not_found"],
  ]);
  // A medium confidence is kept (confirmed anyway).
  assertEquals(result.cross_step.map((c) => [c.field, c.confidence]), [["construction_year", 0.6]]);

  // A value replacing a saved one says so; a pending one counts in the rules.
  const replaced = validateTurn(
    output({
      cross_step: cross({ answers: [answer("roof_year", "1985", "plutôt 1985")] }),
    }),
    ctx({
      transcript,
      values: { property_type: "maison", roof_year: 2000 },
      pending: [{
        id: "p1",
        target_step: "technical",
        kind: "field",
        field: "construction_year",
        value: 1998,
        label_fr: "Construction 1998",
      }],
    }),
  );
  assertEquals(replaced.rejected.map((r) => r.reason), ["inconsistent"]);
  const changed = validateTurn(
    output({
      cross_step: cross({ answers: [answer("roof_year", "1985", "plutôt 1985")] }),
    }),
    ctx({ transcript, values: { property_type: "maison", roof_year: 2000 } }),
  );
  assertEquals(changed.cross_step[0].changed_fr, `Année toiture${NB}: 2000 → 1985`);
});

Deno.test("cross-step entities: rooms and estimates, duplicates and missing values", () => {
  const transcript =
    "la cuisine fait 12 m², le séjour fait 30 m², une chambre, une agence l’a estimée 300 000 € en 03/2025";
  const result = validateTurn(
    output({
      cross_step: cross({
        entities: [
          {
            entity: "room",
            fields: [f("name", "cuisine", "la cuisine"), f("area_m2", "12", "fait 12 m²")],
          },
          {
            entity: "room",
            fields: [f("name", "séjour", "le séjour"), f("area_m2", "30", "fait 30 m²")],
          },
          { entity: "room", fields: [f("name", "chambre", "une chambre")] },
          { entity: "previous_estimate", fields: [f("price_eur", "300000", "300 000 €")] },
        ],
      }),
    }),
    ctx({
      step: "lifestyle",
      transcript,
      entities: { rooms: [{ name: "Séjour", area_m2: 30 }], estimates: [] },
    }),
  );
  assertEquals(result.cross_step.map((c) => [c.target_step, c.kind, c.label_fr]), [
    ["rooms", "room", `Cuisine · 12${NB}m²`],
    ["context", "previous_estimate", `Estimation 300${NB}000${NB}€`],
  ]);
  assertEquals(result.cross_step[0].value, { name: "Cuisine", area_m2: 12, kind: "kitchen" });
  assertEquals(result.rejected.map((r) => [r.field, r.reason]), [
    ["x:room", "duplicate"],
    ["x:room", "anchor_missing"],
  ]);
  // An estimate already saved, the own step's entity, an unknown entity.
  const again = validateTurn(
    output({
      cross_step: cross({
        entities: [
          { entity: "previous_estimate", fields: [f("price_eur", "300000", "300 000 €")] },
          { entity: "co_owner", fields: [] },
        ],
      }),
    }),
    ctx({
      step: "technical",
      transcript,
      entities: { rooms: [], estimates: [{ price_eur: 300000, estimated_month: null }] },
    }),
  );
  assertEquals(again.rejected.map((r) => [r.field, r.reason]), [
    ["x:previous_estimate", "duplicate"],
    ["x:co_owner", "unknown_field"],
  ]);
});

Deno.test("notes: own step and other steps, only words said, no contact", () => {
  const transcript =
    "le grenier est aménageable, la chaudière est dans le garage, appelez le 06 12 34 56 78";
  const result = validateTurn(
    output({
      notes: [
        { text: "Chaudière dans le garage", quote: "la chaudière est dans le garage" },
        { text: "Toiture refaite par un artisan réputé", quote: "le grenier" },
        { text: "Appeler le 06 12 34 56 78", quote: "appelez le 06 12 34 56 78" },
      ],
      cross_step: cross({
        notes: [
          { step: "technical", text: "Grenier aménageable", quote: "le grenier est aménageable" },
          { step: "location", text: "Grenier aménageable", quote: "le grenier est aménageable" },
        ],
      }),
    }),
    ctx({ step: "location", transcript }),
  );
  assertEquals(result.notes, [{ text: "Chaudière dans le garage" }]);
  assertEquals(result.cross_step.map((c) => [c.target_step, c.kind, c.value]), [
    ["technical", "note", "Grenier aménageable"],
  ]);
  assertEquals(result.rejected.map((r) => [r.field, r.reason]), [
    ["note", "not_covered"],
    ["note", "not_covered"],
    ["x:note", "unknown_field"],
  ]);
  assertEquals(result.evidence.map((e) => e.k), ["note:0", "x:0"]);
});

Deno.test("cross-step: eight per turn at most; parsed from the model's JSON", () => {
  const years = Array.from({ length: 10 }, (_, i) => 1990 + i);
  const transcript = `on a ${years.join(" ")}`;
  const lifestyle = Array.from({ length: 10 }, (_, i) => ({
    kind: "asset",
    label: `Atout numéro ${i}`,
    quote: "on a",
  }));
  const result = validateTurn(
    output({ cross_step: cross({ lifestyle_items: lifestyle }) }),
    ctx({ transcript }),
  );
  assertEquals(result.cross_step.length, 8);
  assertEquals(result.rejected.filter((r) => r.reason === "full").length, 2);

  const parsed = parseModelOutput(JSON.stringify({
    reply_fr: "Noté.",
    answers: [],
    notes: [{ text: "Vue dégagée", quote: "vue" }, { nope: 1 }],
    cross_step: {
      answers: [{ field: "construction_year", value: 1998, confidence: 0.9, quote: "1998" }],
      entities: [{ entity: "room", fields: [{ field: "name", value: "Cuisine", quote: "q" }] }, {}],
      lifestyle_items: [{ kind: "asset", label: "Calme", quote: "calme" }],
      notes: [{ step: "technical", text: "Grenier", quote: "grenier" }],
    },
    next_field: "none",
    done: false,
  }));
  assertEquals(parsed.notes, [{ text: "Vue dégagée", quote: "vue" }]);
  assertEquals(parsed.cross_step?.answers[0].value, "1998");
  assertEquals(parsed.cross_step?.entities.length, 1);
  assertEquals(parsed.cross_step?.entities[0].fields[0].confidence, 0);
  assertEquals(parsed.cross_step?.notes[0].step, "technical");
  const empty = parseModelOutput('{"reply_fr":"x","cross_step":{"answers":[]}}');
  assertEquals(empty.cross_step, undefined);
  assertEquals(empty.notes, undefined);
});

Deno.test("maskContacts: phones and e-mails, never years nor prices", () => {
  assertEquals(maskContacts("appelez le 06 12 34 56 78 svp"), "appelez le [numéro masqué] svp");
  assertEquals(maskContacts("+33 6 12 34 56 78"), "[numéro masqué]");
  assertEquals(maskContacts("0612345678"), "[numéro masqué]");
  assertEquals(maskContacts("00 44 20 7946 0958"), "[numéro masqué]");
  assertEquals(maskContacts("écrivez à jean.dupont@gmail.com"), "écrivez à [e-mail masqué]");
  assertEquals(
    maskContacts("jean point dupont arobase gmail point com merci"),
    "[e-mail masqué] merci",
  );
  const kept = "construite en 1998 2015 pour 320 000 euros, 12 m², 1 200 000 €";
  assertEquals(maskContacts(kept), kept);
});

Deno.test("evidence of entity changes and confirmations", () => {
  const transcript = "la cuisine fait 12 m² en carrelage et supprime le bureau";
  const result = validateTurn(
    output({
      entity_ops: [
        {
          entity: "room",
          op: "create",
          target: "new",
          target_quote: "",
          fields: [
            f("name", "cuisine", "la cuisine"),
            f("area_m2", "12", "fait 12 m²"),
            f("floor_covering", "carrelage", "en carrelage"),
          ],
        },
        { entity: "room", op: "delete", target: "R1", target_quote: "le bureau", fields: [] },
      ],
    }),
    ctx({
      step: "rooms",
      transcript,
      rooms: [{
        ref: "R1",
        name: "Bureau",
        level: null,
        area_m2: 9,
        floor_covering: null,
        glazing: null,
        ceiling_height_m: null,
        is_annex: false,
      }],
    }),
  );
  assertEquals(result.evidence.map((e) => e.k), [
    "op:0.name",
    "op:0.area_m2",
    "op:0.floor_covering",
  ]);
  assertEquals(result.confirmations[0].reason, "delete");
  // A confirmed answer keeps its evidence (applied after « oui »).
  const strong = validateTurn(
    output({ answers: [answer("purchase_year", "1950", "en 1950")] }),
    ctx({
      transcript: "achetée en 1950",
      values: { property_type: "maison", purchase_year: 2012 },
    }),
  );
  assertEquals(strong.confirmations[0].reason, "strong_change");
  assertEquals(strong.evidence.map((e) => e.k), ["purchase_year"]);
});
