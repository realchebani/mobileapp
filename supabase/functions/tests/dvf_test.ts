import { assertEquals } from "jsr:@std/assert@1";
import { parseCsv, splitCsvLine } from "../_shared/dvf/csv.ts";
import { cleanDvfCsv, formatStreet } from "../_shared/dvf/clean.ts";

const fixture = (year: number) =>
  Deno.readTextFileSync(new URL(`../_shared/dvf/fixtures/69043_${year}.csv`, import.meta.url));

Deno.test("splitCsvLine handles quotes and escaped quotes", () => {
  assertEquals(splitCsvLine("a,b,,c"), ["a", "b", "", "c"]);
  assertEquals(splitCsvLine('a,"b, c","d ""e"""'), ["a", "b, c", 'd "e"']);
});

Deno.test("parseCsv keys records by header and skips blank lines", () => {
  assertEquals(parseCsv("x,y\r\n1,2\n\n3\n"), [{ x: "1", y: "2" }, { x: "3", y: "" }]);
  assertEquals(parseCsv(""), []);
});

Deno.test("formatStreet title-cases DVF street names", () => {
  assertEquals(formatStreet("RUE DE LA PAIX"), "Rue de la Paix");
  assertEquals(formatStreet("ALL D'ANNECY"), "All d'Annecy");
  assertEquals(formatStreet("L'ORME  SAINT-JEAN"), "L'Orme Saint-Jean");
  assertEquals(formatStreet("  "), null);
});

const HEADER =
  "id_mutation,date_mutation,numero_disposition,nature_mutation,valeur_fonciere,adresse_numero,adresse_suffixe,adresse_nom_voie,adresse_code_voie,code_postal,code_commune,nom_commune,code_departement,ancien_code_commune,ancien_nom_commune,id_parcelle,ancien_id_parcelle,numero_volume,lot1_numero,lot1_surface_carrez,lot2_numero,lot2_surface_carrez,lot3_numero,lot3_surface_carrez,lot4_numero,lot4_surface_carrez,lot5_numero,lot5_surface_carrez,nombre_lots,code_type_local,type_local,surface_reelle_bati,nombre_pieces_principales,code_nature_culture,nature_culture,code_nature_culture_speciale,nature_culture_speciale,surface_terrain,longitude,latitude";

function line(o: Record<string, string>): string {
  const cols = HEADER.split(",");
  return cols.map((c) => o[c] ?? "").join(",");
}

Deno.test("cleanDvfCsv keeps single-dwelling sales and counts the dropped ones", () => {
  const base = { nature_mutation: "Vente", date_mutation: "2025-03-02" };
  const csv = [
    HEADER,
    // House on two parcel lines + a dependency: kept, land summed.
    line({
      ...base,
      id_mutation: "m1",
      valeur_fonciere: "400000",
      adresse_nom_voie: "RUE DES LILAS",
      id_parcelle: "P1",
      type_local: "Maison",
      surface_reelle_bati: "100",
      nombre_pieces_principales: "5",
      code_nature_culture: "S",
      surface_terrain: "300",
      longitude: "4.7",
      latitude: "45.7",
    }),
    line({
      ...base,
      id_mutation: "m1",
      valeur_fonciere: "400000",
      id_parcelle: "P1",
      type_local: "Maison",
      surface_reelle_bati: "100",
      nombre_pieces_principales: "5",
      code_nature_culture: "J",
      surface_terrain: "200",
    }),
    line({
      ...base,
      id_mutation: "m1",
      valeur_fonciere: "400000",
      id_parcelle: "P1",
      type_local: "Dépendance",
    }),
    // Dependencies only.
    line({ ...base, id_mutation: "m2", valeur_fonciere: "10000", type_local: "Dépendance" }),
    // Two apartments.
    line({
      ...base,
      id_mutation: "m3",
      valeur_fonciere: "300000",
      id_parcelle: "P2",
      lot1_numero: "1",
      type_local: "Appartement",
      surface_reelle_bati: "50",
    }),
    line({
      ...base,
      id_mutation: "m3",
      valeur_fonciere: "300000",
      id_parcelle: "P2",
      lot1_numero: "2",
      type_local: "Appartement",
      surface_reelle_bati: "50",
    }),
    // Apartment with a shop.
    line({
      ...base,
      id_mutation: "m4",
      valeur_fonciere: "300000",
      id_parcelle: "P3",
      type_local: "Appartement",
      surface_reelle_bati: "60",
    }),
    line({
      ...base,
      id_mutation: "m4",
      valeur_fonciere: "300000",
      id_parcelle: "P3",
      type_local: "Local industriel. commercial ou assimilé",
      surface_reelle_bati: "30",
    }),
    // Not a sale.
    line({
      id_mutation: "m5",
      nature_mutation: "Echange",
      valeur_fonciere: "1",
      type_local: "Maison",
      surface_reelle_bati: "90",
    }),
    // Missing area / tiny area.
    line({
      ...base,
      id_mutation: "m6",
      valeur_fonciere: "100000",
      type_local: "Maison",
      surface_reelle_bati: "",
    }),
    line({
      ...base,
      id_mutation: "m7",
      valeur_fonciere: "100000",
      type_local: "Maison",
      surface_reelle_bati: "8",
    }),
    // Missing price.
    line({
      ...base,
      id_mutation: "m8",
      valeur_fonciere: "",
      type_local: "Maison",
      surface_reelle_bati: "80",
    }),
    // Extreme €/m².
    line({
      ...base,
      id_mutation: "m9",
      valeur_fonciere: "10000",
      type_local: "Appartement",
      surface_reelle_bati: "80",
    }),
    line({
      ...base,
      id_mutation: "m10",
      valeur_fonciere: "5000000",
      type_local: "Appartement",
      surface_reelle_bati: "80",
    }),
    // Apartment without coordinates nor rooms.
    line({
      ...base,
      id_mutation: "m11",
      nature_mutation: "Adjudication",
      valeur_fonciere: "200000.5",
      adresse_nom_voie: "",
      type_local: "Appartement",
      surface_reelle_bati: "40",
    }),
    line({ nature_mutation: "Vente" }),
  ].join("\n");
  const { sales, dropped } = cleanDvfCsv(csv, "69043", 2025);
  assertEquals(dropped, {
    dependencies: 1,
    multi_lots: 2,
    not_a_sale: 1,
    missing_area: 2,
    missing_price: 1,
    extreme: 2,
  });
  assertEquals(sales, [
    {
      idMutation: "m1",
      insee: "69043",
      year: 2025,
      soldOn: "2025-03-02",
      type: "maison",
      priceEur: 400000,
      areaM2: 100,
      rooms: 5,
      landM2: 500,
      street: "Rue des Lilas",
      lat: 45.7,
      lng: 4.7,
    },
    {
      idMutation: "m11",
      insee: "69043",
      year: 2025,
      soldOn: "2025-03-02",
      type: "appartement",
      priceEur: 200001,
      areaM2: 40,
      rooms: null,
      landM2: null,
      street: null,
      lat: null,
      lng: null,
    },
  ]);
});

Deno.test("cleanDvfCsv on the real Chaponost 2025 file", () => {
  const { sales, dropped } = cleanDvfCsv(fixture(2025), "69043", 2025);
  assertEquals(sales.length, 101);
  assertEquals(dropped, { not_a_sale: 1, dependencies: 48, multi_lots: 4, extreme: 1 });
  assertEquals(sales.every((s) => s.street === null || !/^\d/.test(s.street)), true);
});
