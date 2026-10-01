import { cleanDvfCsv } from "../_shared/dvf/clean.ts";
import type { DvfSale, Subject } from "../_shared/estimation/types.ts";

/** Cleaned sales of the Chaponost (69043) fixtures, 2021–2025. */
export function chaponostSales(): DvfSale[] {
  const sales: DvfSale[] = [];
  for (const year of [2021, 2022, 2023, 2024, 2025]) {
    const text = Deno.readTextFileSync(
      new URL(`../_shared/dvf/fixtures/69043_${year}.csv`, import.meta.url),
    );
    sales.push(...cleanDvfCsv(text, "69043", year).sales);
  }
  return sales;
}

export function subject(overrides: Partial<Subject> = {}): Subject {
  return {
    type: "maison",
    lat: 45.7104,
    lng: 4.7469,
    insee: "69043",
    city: "Chaponost",
    livingAreaM2: 115,
    roomsCount: 5,
    landM2: 540,
    constructionYear: 1990,
    heatPumpYear: null,
    roofYear: null,
    outdoorEquipment: [],
    poolType: null,
    noiseLevel: null,
    overlooking: null,
    assets: [],
    watchPoints: [],
    ...overrides,
  };
}

let counter = 0;

export function sale(overrides: Partial<DvfSale> = {}): DvfSale {
  counter++;
  return {
    idMutation: `s${counter}`,
    insee: "69043",
    year: 2025,
    soldOn: "2025-06-15",
    type: "maison",
    priceEur: 460000,
    areaM2: 115,
    rooms: 5,
    landM2: 500,
    street: "Rue Test",
    lat: 45.7104,
    lng: 4.7469,
    ...overrides,
  };
}
