// Cleans a geo-dvf commune file: groups the lines by mutation and keeps
// the sales of exactly one dwelling (plan §3.2).
import { parseCsv } from "./csv.ts";
import type { DvfSale, OutbuildingSale, PropertyType } from "../estimation/types.ts";

const SALE_NATURES = new Set([
  "Vente",
  "Vente en l'état futur d'achèvement",
  "Adjudication",
]);
const DWELLINGS: Record<string, PropertyType> = {
  Maison: "maison",
  Appartement: "appartement",
};
const COMMERCIAL = "Local industriel. commercial ou assimilé";
const OUTBUILDING = "Dépendance";

/** Version of the cleaning (dvf_sources.format_version): 2 also keeps the
 * sales of one outbuilding alone (EPIC-13). */
export const CLEAN_FORMAT_VERSION = 2;

/** Fixed bounds of a plausible outbuilding price (€): a parking space in a
 * small town to a garage in a dense city. */
export const MIN_OUTBUILDING_PRICE = 1000;
export const MAX_OUTBUILDING_PRICE = 250000;

/** Fixed bounds of a plausible price per m² (€). */
export const MIN_PRICE_M2 = 500;
export const MAX_PRICE_M2 = 25000;

export type DropReason =
  | "not_a_sale"
  | "dependencies"
  | "multi_lots"
  | "missing_area"
  | "missing_price"
  | "extreme";

export interface CleanResult {
  sales: DvfSale[];
  /** Sales of one outbuilding alone (no dwelling, no commercial premises). */
  outbuildings: OutbuildingSale[];
  dropped: Partial<Record<DropReason, number>>;
}

const LOWER_WORDS = new Set([
  "de",
  "du",
  "des",
  "la",
  "le",
  "les",
  "et",
  "en",
  "au",
  "aux",
  "sur",
  "sous",
  "a",
]);

/** "RUE DE LA PAIX" → "Rue de la Paix"; "ALL D'ANNECY" → "All d'Annecy". */
export function formatStreet(raw: string): string | null {
  const name = raw.trim().replace(/\s+/g, " ").toLowerCase();
  if (name === "") return null;
  const capitalize = (word: string) =>
    word
      .split("-")
      .map((part) => (part === "" ? part : part[0].toUpperCase() + part.slice(1)))
      .join("-");
  return name
    .split(" ")
    .map((word, index) => {
      if (index > 0 && LOWER_WORDS.has(word)) return word;
      const elided = word.match(/^([dl])'(.+)$/);
      if (elided) {
        const article = index === 0 ? elided[1].toUpperCase() : elided[1];
        return `${article}'${capitalize(elided[2])}`;
      }
      return capitalize(word);
    })
    .join(" ")
    .slice(0, 200);
}

function num(value: string | undefined): number | null {
  if (value === undefined || value.trim() === "") return null;
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : null;
}

/** Cleans the CSV [text] of commune [insee] for [year]. */
export function cleanDvfCsv(text: string, insee: string, year: number): CleanResult {
  const groups = new Map<string, Record<string, string>[]>();
  for (const record of parseCsv(text)) {
    const id = record["id_mutation"];
    if (!id) continue;
    const rows = groups.get(id);
    if (rows) rows.push(record);
    else groups.set(id, [record]);
  }
  const sales: DvfSale[] = [];
  const outbuildings: OutbuildingSale[] = [];
  const dropped: Partial<Record<DropReason, number>> = {};
  const drop = (reason: DropReason) => {
    dropped[reason] = (dropped[reason] ?? 0) + 1;
  };
  for (const [id, rows] of groups) {
    const first = rows[0];
    if (!SALE_NATURES.has(first["nature_mutation"])) {
      drop("not_a_sale");
      continue;
    }
    const locals = new Map<string, Record<string, string>>();
    const annexes = new Map<string, Record<string, string>>();
    let commercial = false;
    for (const row of rows) {
      const kind = row["type_local"];
      if (kind === COMMERCIAL) commercial = true;
      if (kind === OUTBUILDING) {
        const key = `${row["id_parcelle"]}|${row["lot1_numero"] ?? ""}`;
        if (!annexes.has(key)) annexes.set(key, row);
      }
      if (!(kind in DWELLINGS)) continue;
      const key = [
        kind,
        row["id_parcelle"],
        row["surface_reelle_bati"],
        kind === "Appartement" ? row["lot1_numero"] : "",
      ].join("|");
      if (!locals.has(key)) locals.set(key, row);
    }
    if (locals.size === 0) {
      const price = num(first["valeur_fonciere"]);
      if (
        !commercial && annexes.size === 1 && price !== null &&
        price >= MIN_OUTBUILDING_PRICE && price <= MAX_OUTBUILDING_PRICE
      ) {
        const annex = [...annexes.values()][0];
        outbuildings.push({
          idMutation: id,
          insee,
          year,
          soldOn: first["date_mutation"],
          priceEur: Math.round(price),
          street: formatStreet(annex["adresse_nom_voie"] ?? ""),
          lat: num(annex["latitude"]),
          lng: num(annex["longitude"]),
        });
      } else {
        drop("dependencies");
      }
      continue;
    }
    if (locals.size > 1 || commercial) {
      drop("multi_lots");
      continue;
    }
    const dwelling = [...locals.values()][0];
    const area = num(dwelling["surface_reelle_bati"]);
    if (area === null || area < 9) {
      drop("missing_area");
      continue;
    }
    const price = num(first["valeur_fonciere"]);
    if (price === null || price <= 0) {
      drop("missing_price");
      continue;
    }
    const priceM2 = price / area;
    if (priceM2 < MIN_PRICE_M2 || priceM2 > MAX_PRICE_M2) {
      drop("extreme");
      continue;
    }
    // Land: each parcel × culture counted once.
    const parcels = new Map<string, number>();
    for (const row of rows) {
      const land = num(row["surface_terrain"]);
      if (land !== null) {
        parcels.set(`${row["id_parcelle"]}|${row["code_nature_culture"]}`, land);
      }
    }
    const land = [...parcels.values()].reduce((sum, value) => sum + value, 0);
    const rooms = num(dwelling["nombre_pieces_principales"]);
    sales.push({
      idMutation: id,
      insee,
      year,
      soldOn: first["date_mutation"],
      type: DWELLINGS[dwelling["type_local"]],
      priceEur: Math.round(price),
      areaM2: area,
      rooms: rooms === null ? null : Math.round(rooms),
      landM2: land > 0 ? Math.round(land) : null,
      street: formatStreet(dwelling["adresse_nom_voie"] ?? ""),
      lat: num(dwelling["latitude"]),
      lng: num(dwelling["longitude"]),
    });
  }
  return { sales, outbuildings, dropped };
}
