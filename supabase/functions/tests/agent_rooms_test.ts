// EPIC-14: V5c dictation of rooms (plan §2.5, §4.3).
import { assert, assertEquals } from "jsr:@std/assert@1";
import { validateTurn, type ValidationContext } from "../_shared/agent/validate.ts";
import {
  designate,
  roomKindOf,
  roomNumberOf,
  roomNumbersIn,
  type RoomRow,
} from "../_shared/agent/rooms.ts";
import { f, op, output } from "./agent_helpers.ts";

const NB = " ";

function room(ref: string, name: string, area: number, extra: Partial<RoomRow> = {}): RoomRow {
  return {
    ref,
    name,
    level: "rdc",
    area_m2: area,
    floor_covering: null,
    glazing: null,
    ceiling_height_m: null,
    is_annex: false,
    ...extra,
  };
}

function ctx(transcript: string, rooms: RoomRow[] = [], extra: Partial<ValidationContext> = {}) {
  return {
    step: "rooms" as const,
    values: { property_type: "maison" },
    transcript,
    currentYear: 2026,
    interactive: true,
    rooms,
    ...extra,
  };
}

Deno.test("a dictated room with its five values and a description (US-14.3)", () => {
  const transcript = "Le séjour fait 38 m² au rez-de-chaussée, parquet chêne, double vitrage, " +
    "il est ouvert sur la cuisine avec une cheminée.";
  const result = validateTurn(
    output({
      entity_ops: [op({
        fields: [
          f("name", "Séjour", "Le séjour"),
          f("area_m2", "38", "fait 38 m²"),
          f("level", "rdc", "au rez-de-chaussée"),
          f("floor_covering", "parquet_chene", "parquet chêne"),
          f("glazing", "double", "double vitrage"),
          f(
            "description",
            "Ouvert sur la cuisine, avec une cheminée",
            "ouvert sur la cuisine avec une cheminée",
          ),
        ],
      })],
    }),
    ctx(transcript),
  );
  assertEquals(result.rejected, []);
  assertEquals(result.entity_ops.length, 1);
  const created = result.entity_ops[0];
  assertEquals(created.op, "create");
  assertEquals(created.target, "new");
  assertEquals(created.values, {
    name: "Séjour",
    kind: "livingRoom",
    area_m2: 38,
    level: "rdc",
    floor_covering: "parquet_chene",
    glazing: "double",
    description: "Ouvert sur la cuisine, avec une cheminée",
  });
  assertEquals(
    created.label_fr,
    `Séjour · Rez-de-chaussée · 38${NB}m² · Parquet chêne · Double vitrage`,
  );
});

Deno.test("several rooms in one sentence, a level said once, dimensions", () => {
  const transcript = "À l’étage, trois chambres de 12, 11 et 10 m², toutes en parquet, " +
    "et un bureau de 4 sur 3";
  const level = f("level", "etage_1", "À l’étage");
  const floor = f("floor_covering", "parquet", "toutes en parquet");
  const result = validateTurn(
    output({
      entity_ops: [
        op({
          fields: [
            f("name", "Chambre", "trois chambres"),
            f("area_m2", "12", "de 12"),
            level,
            floor,
          ],
        }),
        op({
          fields: [f("name", "Chambre", "trois chambres"), f("area_m2", "11", "11"), level, floor],
        }),
        op({
          fields: [
            f("name", "Chambre", "trois chambres"),
            f("area_m2", "10", "10 m²"),
            level,
            floor,
          ],
        }),
        op({ fields: [f("name", "Bureau", "un bureau"), f("area_m2", "4x3", "de 4 sur 3")] }),
      ],
    }),
    ctx(transcript, [room("R1", "Chambre", 9, { level: "etage_1" })]),
  );
  assertEquals(result.rejected, []);
  assertEquals(result.entity_ops.map((o) => [o.values.name, o.values.area_m2, o.values.level]), [
    ["Chambre", 12, "etage_1"],
    ["Chambre", 11, "etage_1"],
    ["Chambre", 10, "etage_1"],
    ["Bureau", 12, undefined],
  ]);
  assertEquals(result.entity_ops[3].values.dimensions, `4 × 3${NB}m`);
});

Deno.test("evidence: number, glazing word, level keyword, covered description", () => {
  const transcript = "la cuisine fait douze mètres carrés, en double, avec un îlot";
  const result = validateTurn(
    output({
      entity_ops: [op({
        fields: [
          f("name", "Cuisine", "la cuisine"),
          f("area_m2", "21", "douze mètres carrés"),
          f("glazing", "double", "en double"),
          f("level", "etage_1", "la cuisine"),
          f("description", "Avec un îlot central en marbre", "avec un îlot"),
        ],
      })],
    }),
    ctx(transcript),
  );
  assertEquals(result.entity_ops, []);
  assertEquals(result.rejected.map((r) => [r.field, r.reason]), [
    ["room:area_m2", "number_not_in_quote"],
    ["room:glazing", "anchor_missing"],
    ["room:level", "anchor_missing"],
    ["room:description", "not_covered"],
  ]);
  assertEquals(result.pending.map((p) => p.label_fr), [`Cuisine${NB}: surface${NB}?`]);
});

Deno.test("existing rooms: designation, ambiguity, merge, delete", () => {
  const rooms = [
    room("R1", "Séjour", 38),
    room("R2", "Chambre 1", 12, { level: "etage_1" }),
    room("R3", "Chambre 2", 11, { level: "etage_1" }),
    room("R4", "Cuisine", 12.8),
    room("R5", "Cellier", 4.2, { is_annex: true }),
  ];
  const transcript = "non le séjour fait 40 m², la chambre 2 a du carrelage, la chambre fait " +
    "13 m², la cuisine fait 14 m², supprime le cellier, et le garage fait 20 m²";
  const result = validateTurn(
    output({
      entity_ops: [
        op({
          op: "update",
          target: "R1",
          target_quote: "le séjour",
          correction: true,
          fields: [f("area_m2", "40", "fait 40 m²")],
        }),
        op({
          op: "update",
          target: "R3",
          target_quote: "la chambre 2",
          fields: [f("floor_covering", "carrelage", "du carrelage")],
        }),
        op({
          op: "update",
          target: "R2",
          target_quote: "la chambre",
          fields: [f("area_m2", "13", "13 m²")],
        }),
        op({ fields: [f("name", "Cuisine", "la cuisine"), f("area_m2", "14", "fait 14 m²")] }),
        op({ op: "delete", target: "R5", target_quote: "le cellier" }),
        op({
          op: "update",
          target: "R4",
          target_quote: "le garage",
          fields: [f("area_m2", "20", "fait 20 m²")],
        }),
      ],
    }),
    ctx(transcript, rooms),
  );
  assertEquals(result.entity_ops.map((o) => [o.op, o.target, o.values, o.label_fr]), [
    ["update", "R1", { area_m2: 40 }, `Séjour · Rez-de-chaussée · 40${NB}m² (corrigé)`],
    [
      "update",
      "R3",
      { floor_covering: "carrelage" },
      `Chambre 2 · Étage · 11${NB}m² · Carrelage`,
    ],
  ]);
  assertEquals(result.entity_ops[0].changed_fr, `Modifiée${NB}: 38 → 40${NB}m²`);
  assertEquals(result.corrections, ["room:R1"]);
  assertEquals(result.confirmations.map((c) => [c.reason, c.label_fr]), [
    ["merge_room", `Modifier Cuisine${NB}: 12,8 → 14${NB}m²${NB}?`],
    ["delete", `Supprimer Cellier (4,2${NB}m²)${NB}?`],
  ]);
  assertEquals(result.confirmations[0].entity_ops[0].target, "R4");
  assertEquals(result.rejected.map((r) => r.reason), ["ambiguous", "mismatch"]);
  assertEquals(result.pending.map((p) => p.label_fr), [
    `Quelle pièce${NB}: Chambre 1, Chambre 2${NB}?`,
  ]);
});

Deno.test("copy from another room, the last room, limits", () => {
  const rooms = [
    room("R1", "Séjour", 38, { floor_covering: "parquet_chene", glazing: "double" }),
    room("R2", "Bureau", 9),
  ];
  const transcript = "le bureau fait 10 m², même sol que le séjour, la dernière fait 10 m² " +
    "et une salle de bain de 6 m², supprime le séjour";
  const result = validateTurn(
    output({
      entity_ops: [
        op({
          op: "update",
          target: "R2",
          target_quote: "le bureau",
          fields: [],
          copy_from: "R1",
          copy_fields: ["floor_covering"],
          copy_quote: "même sol que le séjour",
        }),
        op({
          op: "update",
          target: "R2",
          target_quote: "la dernière",
          fields: [f("area_m2", "10", "fait 10 m²")],
        }),
        op({
          fields: [f("name", "Salle de bain", "une salle de bain"), f("area_m2", "6", "de 6 m²")],
        }),
        op({ op: "delete", target: "R1", target_quote: "le séjour" }),
        op({ op: "delete", target: "R2", target_quote: "le bureau" }),
      ],
    }),
    ctx(transcript, rooms, { lastRoomRef: "R2" }),
  );
  assertEquals(result.entity_ops.map((o) => [o.target, o.values]), [
    ["R2", { floor_covering: "parquet_chene" }],
    ["R2", { area_m2: 10 }],
    ["new", { name: "Salle de bain", kind: "bathroom", area_m2: 6 }],
  ]);
  assertEquals(result.confirmations.length, 1);
  assertEquals(result.rejected.map((r) => r.reason), ["full"]);
  // 40 rooms at most, 2 000 m² habitable at most.
  const full = validateTurn(
    output({
      entity_ops: [op({ fields: [f("name", "Bureau", "un bureau"), f("area_m2", "9", "9 m²")] })],
    }),
    ctx(
      "un bureau de 9 m²",
      Array.from({ length: 40 }, (_, i) => room(`R${i + 1}`, `Pièce ${i}`, 10)),
    ),
  );
  assertEquals(full.rejected[0].reason, "full");
  const huge = validateTurn(
    output({
      entity_ops: [
        op({ fields: [f("name", "Séjour", "un séjour"), f("area_m2", "300", "300 m²")] }),
      ],
    }),
    ctx(
      "un séjour de 300 m²",
      Array.from({ length: 4 }, (_, i) => room(`R${i + 1}`, `Grange ${i}`, 450)),
    ),
  );
  assertEquals(huge.rejected[0].reason, "inconsistent");
});

Deno.test("the V4 Night audit never deletes nor merges", () => {
  const rooms = [room("R1", "Cuisine", 12)];
  const result = validateTurn(
    output({
      entity_ops: [
        op({ op: "delete", target: "R1", target_quote: "la cuisine" }),
        op({ fields: [f("name", "Cuisine", "la cuisine"), f("area_m2", "14", "14 m²")] }),
      ],
    }),
    ctx("supprime la cuisine, la cuisine fait 14 m²", rooms, { interactive: false }),
  );
  assertEquals(result.entity_ops, []);
  assertEquals(result.rejected.map((r) => r.reason), ["not_allowed", "ambiguous"]);
});

Deno.test("room helpers", () => {
  assertEquals(roomKindOf("Salle d’eau")?.kind, "showerRoom");
  assertEquals(roomKindOf("Salle de bains")?.kind, "bathroom");
  assertEquals(roomKindOf("Véranda"), null);
  assertEquals(roomNumberOf("Chambre 3"), 3);
  assertEquals(roomNumberOf("Chambre"), 1);
  assertEquals(roomNumbersIn("la deuxième chambre"), [2]);
  assert(roomNumbersIn("chambre numéro trois").includes(3));
  const rooms = [
    room("R1", "Véranda", 15),
    room("R2", "Chambre 1", 10),
    room("R3", "Chambre 2", 9),
  ];
  assertEquals(designate("R1", "la véranda", rooms, null).ok, true);
  assertEquals(designate("R1", "le jardin", rooms, null).ok, false);
  assertEquals(designate("R9", "la véranda", rooms, null).ok, false);
  assertEquals(designate("R3", "la deuxième chambre", rooms, null).ok, true);
  assertEquals(designate("R2", "la deuxième chambre", rooms, null).ok, false);
});

Deno.test("designation words must be said; copies are whitelisted; inputs kept", () => {
  const rooms = [
    room("R1", "Séjour", 38, { floor_covering: "parquet_chene", ceiling_height_m: 2.5 }),
    room("R2", "Bureau", 9),
  ];
  const before = JSON.stringify(rooms);
  const result = validateTurn(
    output({
      entity_ops: [
        op({
          op: "update",
          target: "R1",
          target_quote: "le salon",
          fields: [f("area_m2", "40", "40 m²")],
        }),
        op({
          op: "update",
          target: "R2",
          target_quote: "le bureau",
          fields: [f("area_m2", "10", "fait 10 m²")],
          copy_from: "R1",
          copy_fields: ["floor_covering", "area_m2", "name"],
          copy_quote: "même sol que le séjour",
        }),
      ],
    }),
    ctx("le séjour fait 40 m², le bureau fait 10 m², même sol que le séjour", rooms),
  );
  assertEquals(result.rejected.map((r) => [r.field, r.reason]), [["room", "quote_not_found"]]);
  assertEquals(result.entity_ops.map((o) => o.values), [
    { area_m2: 10, floor_covering: "parquet_chene" },
  ]);
  assertEquals(JSON.stringify(rooms), before);
});
