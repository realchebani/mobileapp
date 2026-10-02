// EPIC-14: the step sheets of V1, V2, V3 and V4b (plan §4).
import { assert, assertEquals } from "jsr:@std/assert@1";
import { typo, validateTurn, type ValidationContext } from "../_shared/agent/validate.ts";
import { answer, f, op, output } from "./agent_helpers.ts";
import { outputSchema } from "../_shared/agent/schema.ts";

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

const NB = "\u00a0";

Deno.test("V3: several answers in one sentence (US-14.2)", () => {
  const transcript = "Achetée 320 000 € en 2012, pour une mutation, jamais estimée";
  const result = validateTurn(
    output({
      answers: [
        answer("purchase_price_eur", "320000", "Achetée 320 000 €"),
        answer("purchase_year", "2012", "en 2012"),
        answer("sale_reason", "mutation", "pour une mutation"),
        answer("previously_estimated", "false", "jamais estimée"),
      ],
    }),
    ctx({ transcript }),
  );
  assertEquals(result.patch, {
    purchase_price_eur: 320000,
    purchase_year: 2012,
    sale_reason: "mutation",
    previously_estimated: false,
  });
  assertEquals(result.facts.map((x) => x.label_fr), [
    `Prix d’achat 320${NB}000${NB}€`,
    "Achat 2012",
    "Raison mutation",
    `Déjà estimé${NB}: non`,
  ]);
  assertEquals(result.rejected, []);
  assertEquals(result.confirmations, []);
});

Deno.test("anchors: a number or a keyword must be in the quote", () => {
  const transcript = "on l’a achetée il y a longtemps, en deux mille douze, chauffage au bois";
  const result = validateTurn(
    output({
      answers: [
        answer("purchase_year", "2012", "en deux mille douze"),
        answer("purchase_price_eur", "250000", "il y a longtemps"),
        answer("sale_reason", "separation", "chauffage au bois"),
      ],
    }),
    ctx({ transcript }),
  );
  assertEquals(result.patch, { purchase_year: 2012 });
  assertEquals(result.rejected.map((r) => [r.field, r.reason]), [
    ["purchase_price_eur", "number_not_in_quote"],
    ["sale_reason", "anchor_missing"],
  ]);
  assertEquals(result.pending.map((p) => p.label_fr), [
    `Prix d’achat${NB}?`,
    `Raison${NB}?`,
  ]);
});

Deno.test("V3: a type change is confirmed with the answers it asks", () => {
  const transcript = "en fait c’est un garage, un box fermé, acheté en 2015";
  const result = validateTurn(
    output({
      answers: [
        answer("property_type", "stationnement", "c’est un garage"),
        answer("parking_kind", "box", "un box fermé"),
        answer("purchase_year", "2015", "acheté en 2015"),
      ],
    }),
    ctx({ transcript, values: { property_type: "maison" } }),
  );
  assertEquals(result.patch, { purchase_year: 2015 });
  assertEquals(result.confirmations.length, 1);
  assertEquals(result.confirmations[0].reason, "type_change");
  assertEquals(result.confirmations[0].id, "c1");
  assertEquals(result.confirmations[0].label_fr, `Type${NB}: garage / parking${NB}?`);
  assertEquals(result.confirmations[0].patch, {
    property_type: "stationnement",
    parking_kind: "box",
  });
  // A first choice of type is applied at once.
  const first = validateTurn(
    output({ answers: [answer("property_type", "appartement", "un appartement")] }),
    ctx({ transcript: "c’est un appartement", values: { property_type: null } }),
  );
  assertEquals(first.patch, { property_type: "appartement" });
  // Not interactive (no sheet): never changed.
  const night = validateTurn(
    output({ answers: [answer("property_type", "terrain", "un terrain")] }),
    ctx({ transcript: "un terrain", interactive: false }),
  );
  assertEquals(night.patch, {});
  assertEquals(night.rejected[0].reason, "not_allowed");
});

Deno.test("V3: previous estimates (entity)", () => {
  const transcript = "Une agence Century 21 l’a estimée 300 000 € en mars 2024, et retire " +
    "l’estimation de 280 000";
  const result = validateTurn(
    output({
      entity_ops: [
        op({
          entity: "previous_estimate",
          fields: [
            f("price_eur", "300000", "estimée 300 000 €"),
            f("estimated_month", "03/2024", "en mars 2024"),
            f("agency_name", "Century 21", "agence Century 21"),
          ],
        }),
        op({
          entity: "previous_estimate",
          op: "delete",
          target: "E1",
          target_quote: "l’estimation de 280 000",
        }),
        op({ entity: "previous_estimate", op: "update", target: "E9", fields: [] }),
        op({
          entity: "previous_estimate",
          fields: [f("estimated_month", "03/2027", "en mars 2024")],
        }),
      ],
    }),
    ctx({
      transcript,
      estimates: [{ ref: "E1", price_eur: 280000, estimated_month: null, agency_name: null }],
    }),
  );
  assertEquals(result.entity_ops.length, 1);
  assertEquals(result.entity_ops[0].values, {
    price_eur: 300000,
    estimated_month: "2024-03-01",
    agency_name: "Century 21",
  });
  assertEquals(result.patch, { previously_estimated: true });
  assertEquals(result.confirmations.map((c) => [c.reason, c.label_fr]), [
    ["delete", `Supprimer l’estimation de 280${NB}000${NB}€${NB}?`],
  ]);
  assertEquals(
    result.rejected.map((r) => r.reason),
    ["unknown_target", "out_of_range"],
  );
});

Deno.test("V2: special situations, « aucune » is exclusive and confirmed", () => {
  const passage = validateTurn(
    output({
      answers: [
        answer("special_situations", "servitude_passage", "un droit de passage"),
        answer("special_situation_other", "Un puits commun avec le voisin", "puits commun"),
      ],
    }),
    ctx({
      step: "location",
      transcript: "il y a un droit de passage et un puits commun avec le voisin",
      values: { property_type: "maison", special_situations: ["aucune"] },
    }),
  );
  assertEquals(passage.patch, {
    special_situations: ["servitude_passage"],
    special_situation_other: "Un puits commun avec le voisin",
  });
  const none = validateTurn(
    output({ answers: [answer("special_situations", "aucune", "aucune servitude")] }),
    ctx({
      step: "location",
      transcript: "finalement aucune servitude",
      values: { property_type: "maison", special_situations: ["servitude_passage"] },
    }),
  );
  assertEquals(none.patch, {});
  assertEquals(none.confirmations[0].reason, "clear_situations");
  assertEquals(none.confirmations[0].patch, { special_situations: ["aucune"] });
  // An invented precision is not covered by what was said.
  const invented = validateTurn(
    output({
      answers: [answer("special_situation_other", "Ligne haute tension de 20 000 volts", "ligne")],
    }),
    ctx({ step: "location", transcript: "il y a une ligne", values: {} }),
  );
  assertEquals(invented.rejected[0].reason, "not_covered");
});

Deno.test("V1: ownership and co-owners, always confirmed", () => {
  const transcript = "nous sommes deux, avec mon frère Marc Durand";
  const result = validateTurn(
    output({
      answers: [answer("ownership_type", "multiple", "nous sommes deux")],
      entity_ops: [
        op({
          entity: "co_owner",
          fields: [f("first_name", "Marc", "Marc"), f("last_name", "Durand", "Durand")],
        }),
        op({ entity: "co_owner", op: "delete", target: "P2" }),
      ],
    }),
    ctx({ step: "owners", transcript, values: { property_type: "maison" } }),
  );
  assertEquals(result.patch, { ownership_type: "multiple" });
  assertEquals(result.entity_ops, []);
  assertEquals(result.confirmations.length, 1);
  assertEquals(result.confirmations[0].reason, "co_owner");
  assertEquals(result.confirmations[0].label_fr, `Marc Durand${NB}?`);
  assertEquals(result.confirmations[0].patch, { ownership_type: "multiple" });
  assertEquals(result.confirmations[0].entity_ops[0].values, {
    first_name: "Marc",
    last_name: "Durand",
  });
  assertEquals(result.rejected.map((r) => r.reason), ["not_allowed"]);
  // A single owner has no co-owner; digits are not a name.
  const single = validateTurn(
    output({
      entity_ops: [
        op({
          entity: "co_owner",
          fields: [f("first_name", "Marc", "Marc"), f("last_name", "D2", "D2")],
        }),
        op({
          entity: "co_owner",
          fields: [f("first_name", "Marc", "Marc"), f("last_name", "Durand", "Durand")],
        }),
      ],
    }),
    ctx({
      step: "owners",
      transcript: "Marc D2 Marc Durand",
      values: { property_type: "maison", ownership_type: "single" },
    }),
  );
  assertEquals(single.rejected.map((r) => r.reason), [
    "invalid_value",
    "inconsistent",
    "inconsistent",
  ]);
});

Deno.test("V4b: EPIC-13 fields for a garage and an outbuilding", () => {
  const transcript = "le garage fait 18 m², au sous-sol, avec l’électricité et une porte motorisée";
  const result = validateTurn(
    output({
      answers: [
        answer("usable_area_m2", "18", "fait 18 m²"),
        answer("parking_level", "sous_sol", "au sous-sol"),
        answer(
          "parking_features",
          "electricite,porte_motorisee",
          "l’électricité et une porte motorisée",
        ),
        answer("living_area_m2", "18", "fait 18 m²"),
      ],
    }),
    ctx({ step: "technical", transcript, values: { property_type: "stationnement" } }),
  );
  assertEquals(result.patch, {
    usable_area_m2: 18,
    parking_level: "sous_sol",
    parking_features: ["porte_motorisee", "electricite"],
  });
  assertEquals(result.rejected.map((r) => r.reason), ["not_asked"]);
  const outbuilding = validateTurn(
    output({ answers: [answer("parking_features", "borne_recharge", "une borne de recharge")] }),
    ctx({
      step: "technical",
      transcript: "une borne de recharge",
      values: { property_type: "dependance" },
    }),
  );
  assertEquals(outbuilding.rejected[0].reason, "invalid_value");
});

Deno.test("confirmations: medium confidence and strong changes; corrections", () => {
  const transcript = "construite vers 1950, non plutôt en 1952, 180 m² habitables";
  const result = validateTurn(
    output({
      answers: [
        { ...answer("construction_year", "1952", "plutôt en 1952"), correction: true },
        answer("living_area_m2", "180", "180 m² habitables"),
        answer("orientation", "sud", "vers", 0.6),
      ],
    }),
    ctx({
      step: "technical",
      transcript,
      values: { property_type: "maison", construction_year: 1950, living_area_m2: 80 },
    }),
  );
  assertEquals(result.patch, { construction_year: 1952 });
  assertEquals(result.facts[0].label_fr, "Construction 1952 (corrigé)");
  assertEquals(result.facts[0].changed_fr, `Modifié${NB}: 1950 → 1952`);
  assertEquals(result.corrections, ["construction_year"]);
  assertEquals(result.confirmations.map((c) => [c.reason, c.label_fr]), [
    ["strong_change", `Surface habitable${NB}: 80${NB}m² → 180${NB}m²${NB}?`],
  ]);
  // "vers" has no keyword of "sud": asked again, not confirmed.
  assertEquals(result.rejected.map((r) => [r.field, r.reason]), [
    ["orientation", "anchor_missing"],
  ]);
  const medium = validateTurn(
    output({ answers: [answer("orientation", "sud", "plein sud", 0.6)] }),
    ctx({ step: "technical", transcript: "plein sud", values: { property_type: "maison" } }),
  );
  assertEquals(medium.confirmations[0].reason, "medium_confidence");
  assertEquals(medium.confirmations[0].patch, { orientation: "sud" });
  assertEquals(medium.confirmations[0].label_fr, `Exposition sud${NB}?`);
});

Deno.test("answers of another step are reported, never written", () => {
  const result = validateTurn(
    output({
      answers: [answer("purchase_year", "1998", "en 1998")],
      out_of_step: ["construction_year", "living_area_m2", "purchase_year", "unknown"],
    }),
    ctx({ transcript: "achetée en 1998, construite en 1975, 120 m²" }),
  );
  assertEquals(result.out_of_step.map((o) => [o.field, o.step, o.label_fr]), [
    ["construction_year", "technical", "Construction → Technique"],
    ["living_area_m2", "technical", "Surface habitable → Technique"],
  ]);
});

Deno.test("output schemas per step", () => {
  const rooms = outputSchema("rooms") as { required: string[] };
  assertEquals(rooms.required, [
    "reply_fr",
    "answers",
    "entity_ops",
    "out_of_step",
    "next_field",
    "done",
  ]);
  const context = outputSchema("context") as {
    properties: { out_of_step: { items: { enum: string[] } } };
  };
  assert(context.properties.out_of_step.items.enum.includes("construction_year"));
  assert(!context.properties.out_of_step.items.enum.includes("purchase_year"));
  assertEquals(typo("Pièce ? 12 m² · 3 €"), `Pièce${NB}? 12${NB}m² · 3${NB}€`);
});
