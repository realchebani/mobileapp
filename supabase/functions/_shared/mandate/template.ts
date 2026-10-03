// EPIC-08 · text of the TEST sale mandate (versioned). Written by Realesty
// for internal tests only: it is explicitly not a contract (owner decision
// 2026-10-01: test signature, legal set-up to validate before any real
// seller). A new wording = a new version (and the same constant in the app
// and in the SQL function sale_terms_version()).

export const MANDATE_TERMS_VERSION = "test-2026-10";

export const SPECIMEN_NOTICE = "SPÉCIMEN — signature de test sans valeur juridique";

export type Formula = "essentiel" | "premium" | "expert";

/** A property of the mandate (the property sold, or each one of the lot). */
export interface MandateProperty {
  type: string | null;
  address: string | null;
  areaM2: number | null;
}

/** Everything the mandate shows, read from the database. */
export interface MandateFacts {
  mandateId: string;
  formula: Formula;
  kind: "exclusif_sans_engagement" | "exclusif_3_mois";
  termsVersion: string;
  presentationPriceEur: number | null;
  feeRate: number;
  durationMonths: number | null;
  owners: string[];
  properties: MandateProperty[];
  isLot: boolean;
  signerName: string;
  signedAt: Date;
  userAgent: string | null;
  appVersion: string | null;
}

export interface MandateSection {
  title: string;
  lines: string[];
}

const FORMULAS: Record<Formula, string> = {
  essentiel: "L’Essentiel",
  premium: "Le Premium",
  expert: "L’Expert",
};

const TYPES: Record<string, string> = {
  maison: "Maison",
  appartement: "Appartement",
  terrain: "Terrain",
  stationnement: "Stationnement",
  dependance: "Dépendance",
  local_commercial: "Local commercial",
  immeuble: "Immeuble",
  autre: "Bien",
};

/** 525000 → "525 000" (no-break spaces: the PDF font has no U+202F). */
export function frenchNumber(value: number): string {
  return Math.round(value).toString().replace(/\B(?=(\d{3})+(?!\d))/g, " ");
}

/** "1,00" / "3,00" → "1" / "3"; "2,5" stays. */
function rate(value: number): string {
  return Number.isInteger(value) ? `${value}` : `${value}`.replace(".", ",");
}

/** dd/mm/yyyy à HHhMM, Paris time. */
export function frenchDateTime(date: Date): string {
  const parts = new Intl.DateTimeFormat("fr-FR", {
    timeZone: "Europe/Paris",
    day: "2-digit",
    month: "2-digit",
    year: "numeric",
    hour: "2-digit",
    minute: "2-digit",
  }).formatToParts(date);
  const part = (type: string) => parts.find((p) => p.type === type)?.value ?? "";
  return `${part("day")}/${part("month")}/${part("year")} à ${part("hour")}h${part("minute")}`;
}

function propertyLine(property: MandateProperty): string {
  const type = TYPES[property.type ?? "autre"] ?? TYPES.autre;
  const area = property.areaM2 ? ` de ${frenchNumber(property.areaM2)} m²` : "";
  return `${type}${area}${property.address ? `, ${property.address}` : ""}`;
}

/** The sections of the mandate, in order (pure: tested on its own). */
export function mandateSections(facts: MandateFacts): MandateSection[] {
  const expert = facts.formula === "expert";
  const price = facts.presentationPriceEur === null
    ? "à définir avec le vendeur"
    : `${frenchNumber(facts.presentationPriceEur)} €`;
  return [
    {
      title: "Avertissement",
      lines: [
        "Ce document est un mandat de TEST, établi pendant la phase de test interne de",
        "Realesty. Il n’a aucune valeur juridique et n’engage ni le vendeur ni Realesty.",
      ],
    },
    {
      title: "Parties",
      lines: [
        `Mandant(s) : ${facts.owners.length ? facts.owners.join(", ") : facts.signerName}.`,
        "Mandataire : Realesty (phase de test, sans carte professionnelle engagée).",
      ],
    },
    {
      title: facts.isLot ? "Désignation des biens (vente en lot)" : "Désignation du bien",
      lines: facts.properties.map((property) => `• ${propertyLine(property)}`),
    },
    {
      title: "Conditions",
      lines: [
        `Formule : ${FORMULAS[facts.formula]}.`,
        `Prix de présentation : ${price}.`,
        `Honoraires : ${rate(facts.feeRate)} % du prix de vente, dus uniquement en cas de vente.`,
        expert
          ? `Mandat exclusif d’une durée de ${facts.durationMonths ?? 3} mois.`
          : "Mandat exclusif sans engagement de durée.",
        expert
          ? "Résiliation : à l’échéance, ou à tout moment pendant la phase de test."
          : "Résiliation : à tout moment, en un clic, depuis l’application, sans frais.",
        "Aucun paiement n’est demandé dans l’application.",
      ],
    },
    {
      title: "Signature",
      lines: [
        `Signé électroniquement (signature de test dessinée) par ${facts.signerName},`,
        `le ${frenchDateTime(facts.signedAt)} (heure de Paris).`,
        `Conditions : version ${facts.termsVersion}. Mandat n° ${facts.mandateId}.`,
        `Appareil : ${facts.userAgent ?? "non renseigné"}${
          facts.appVersion ? ` · application ${facts.appVersion}` : ""
        }.`,
        ...(facts.owners.length > 1
          ? ["Les autres propriétaires signeront hors de l’application."]
          : []),
      ],
    },
  ];
}
