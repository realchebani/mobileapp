// EPIC-08 · text of the TEST sale mandate (versioned). Structure of the
// Realesty exclusive mandate (articles 1 to 15, owner decision 2026-10-03),
// with generic clauses only: every variable comes from the dossier. It stays
// a SPECIMEN (test signature, no eIDAS signature yet). A new wording = a new
// version (same constant in the app and in the SQL function
// sale_terms_version()).

export const MANDATE_TERMS_VERSION = "test-2026-10-b";

export const SPECIMEN_NOTICE = "SPÉCIMEN — signature de test sans valeur juridique";

/** The agency (mandataire). */
export const REALESTY = {
  name: "Realesty",
  form: "SARL",
  rcs: "RCS Lyon 988 966 099",
  card: "carte professionnelle T CPI 6901 2025 000 000 091",
  vat: "FR49988966099",
  insurer: "AXA France IARD",
  address: "30 avenue Maréchal Foch, 69006 Lyon",
};

/** TVA rate of the agency's fees. */
export const VAT_RATE = 0.2;

/** Premium fees (indicative, same values as the app's SalePrices). */
export const PREMIUM_SETUP_EUR = 299;
export const PREMIUM_MONTHLY_EUR = 99;

export type Formula = "essentiel" | "premium" | "expert";

/** A cadastral parcel of a property. */
export interface MandateParcel {
  section: string | null;
  numero: string | null;
  areaM2: number | null;
}

/** A property of the mandate (the property sold, or each one of the lot). */
export interface MandateProperty {
  type: string | null;
  address: string | null;
  areaM2: number | null;
  roomsCount?: number | null;
  parcels?: MandateParcel[];
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
  minimumDays?: number | null;
  owners: string[];
  properties: MandateProperty[];
  isLot: boolean;
  signerName: string;
  signedAt: Date;
  userAgent: string | null;
  appVersion: string | null;
  /** Drawn (PNG) or typed (the name typed by the signer). */
  signatureMethod?: "drawn" | "typed";
  typedSignature?: string | null;
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

/** 5250 → "5 250,00 €". */
export function euros(value: number): string {
  const cents = Math.round(value * 100);
  const units = Math.trunc(cents / 100);
  const rest = Math.abs(cents % 100).toString().padStart(2, "0");
  return `${frenchNumber(units)},${rest} €`;
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

/** The fee of the mandate (TTC and HT), or null without a price. */
export function fees(facts: MandateFacts): { ttc: number; ht: number } | null {
  if (facts.presentationPriceEur === null) return null;
  const ttc = facts.presentationPriceEur * facts.feeRate / 100;
  return { ttc, ht: ttc / (1 + VAT_RATE) };
}

function propertyLine(property: MandateProperty): string {
  const type = TYPES[property.type ?? "autre"] ?? TYPES.autre;
  const area = property.areaM2 ? ` de ${frenchNumber(property.areaM2)} m²` : "";
  const rooms = property.roomsCount ? `, ${property.roomsCount} pièce(s)` : "";
  return `${type}${area}${rooms}${property.address ? `, ${property.address}` : ""}`;
}

function parcelLines(property: MandateProperty): string[] {
  return (property.parcels ?? []).map((parcel) =>
    `  Cadastre : section ${parcel.section ?? "?"}, n° ${parcel.numero ?? "?"}${
      parcel.areaM2 ? `, ${frenchNumber(parcel.areaM2)} m²` : ""
    }`
  );
}

/** The sections of the mandate, in order (pure: tested on its own). */
export function mandateSections(facts: MandateFacts): MandateSection[] {
  const price = facts.presentationPriceEur === null
    ? "à définir avec le MANDANT"
    : euros(facts.presentationPriceEur);
  const fee = fees(facts);
  const minimum = facts.minimumDays ?? 30;
  const typed = facts.signatureMethod === "typed";
  return [
    {
      title: "Avertissement",
      lines: [
        "Ce document est un mandat de TEST, établi pendant la phase de test interne de",
        "Realesty. Il n’a aucune valeur juridique et n’engage ni le MANDANT ni le MANDATAIRE.",
      ],
    },
    {
      title: "Entre les soussignés",
      lines: [
        `Le MANDANT : ${facts.owners.length ? facts.owners.join(", ") : facts.signerName},`,
        "ci-après dénommé(s) le « MANDANT » ou le « VENDEUR ».",
        `Le MANDATAIRE : ${REALESTY.name}, ${REALESTY.form}, ${REALESTY.rcs}, ${REALESTY.address},`,
        `${REALESTY.card}, mention « Transactions sur immeubles et fonds de commerce »,`,
        `non-détention de fonds ; TVA intracommunautaire ${REALESTY.vat} ;`,
        `assurée en responsabilité civile professionnelle auprès d’${REALESTY.insurer} ;`,
        "représentée par son représentant légal, ci-après dénommée le « MANDATAIRE ».",
      ],
    },
    {
      title: "Article 1. Objet du MANDAT",
      lines: [
        "Le MANDANT confie au MANDATAIRE la mission de trouver un acquéreur du BIEN aux",
        `conditions du MANDAT. Le MANDAT est exclusif. Formule choisie : ${
          FORMULAS[facts.formula]
        }.`,
      ],
    },
    {
      title: "Article 2. Déclarations sur les capacités des parties",
      lines: [
        "Le MANDANT déclare que l’état civil et les qualités indiqués sont exacts et qu’il a la",
        "capacité de vendre le BIEN.",
      ],
    },
    {
      title: facts.isLot
        ? "Article 3. Biens objet du MANDAT (vente en lot)"
        : "Article 3. Bien objet du MANDAT",
      lines: [
        "3.1 Nature : tel que déclaré par le MANDANT dans son dossier Realesty.",
        "3.2 Désignation :",
        ...facts.properties.flatMap((property) => [
          `• ${propertyLine(property)}`,
          ...parcelLines(property),
        ]),
        "3.3 Situation juridique : tel que le BIEN existe, avec tous droits y attachés.",
        "3.4 État d’occupation : à préciser par le MANDANT avant la mise en vente.",
      ],
    },
    {
      title: "Article 4. Prix du BIEN",
      lines: [
        `Prix de présentation : ${price}, payable le jour de la réitération authentique`,
        "de la vente. Ce prix a été fixé librement par le MANDANT après avoir reçu l’avis du",
        "MANDATAIRE ; il peut être modifié par le MANDANT depuis l’application.",
      ],
    },
    {
      title: "Article 5. Rémunération — Honoraires",
      lines: [
        `Honoraires : ${rate(facts.feeRate)} % du prix de vente, à la charge du VENDEUR, dus`,
        "uniquement en cas de vente, exigibles à la signature de l’acte authentique",
        "(article 6 de la loi n° 70-9 du 2 janvier 1970, dite loi Hoguet).",
        fee === null
          ? "Montant calculé sur le prix de vente définitif."
          : `Sur la base du prix de présentation : ${euros(fee.ttc)} TTC, soit ${euros(fee.ht)} HT`,
        `(TVA au taux de ${rate(VAT_RATE * 100)} %).`,
        ...(facts.formula === "premium"
          ? [
            `Formule Le Premium : frais de dossier de ${PREMIUM_SETUP_EUR} € TTC et abonnement de`,
            `${PREMIUM_MONTHLY_EUR} € TTC par mois (tarifs indicatifs ; aucun prélèvement pendant les tests).`,
          ]
          : []),
        "Barème d’honoraires en annexe.",
      ],
    },
    {
      title: "Article 6. Durée du MANDAT",
      lines: [
        "Le MANDAT est conclu sans engagement de durée. Le MANDANT peut y mettre fin à tout",
        `moment, sans frais, depuis l’application, à l’issue d’une période minimale de ${minimum} jours`,
        "après sa signature. Il prend fin également par la vente du BIEN, en cas de faute du",
        "MANDATAIRE (à tout moment) ou au décès ou à la liquidation de l’une des parties.",
      ],
    },
    {
      title: "Article 7. Obligations du MANDATAIRE",
      lines: [
        "Le MANDATAIRE s’engage notamment à : rédiger et publier l’annonce avec photographies",
        "dans Realesty ; organiser les visites et filtrer les acquéreurs selon la formule ;",
        "négocier au mieux des intérêts du MANDANT ; rendre compte de sa mission au moins une",
        "fois par mois et informer le MANDANT de toute offre et de la réalisation de la vente.",
      ],
    },
    {
      title: "Article 8. Obligations du MANDANT",
      lines: [
        "Le MANDANT s’engage notamment à : fournir les documents utiles (titre de propriété,",
        "diagnostics techniques obligatoires, état des risques) ; permettre les visites ;",
        "informer le MANDATAIRE de toute offre ; ne pas confier la vente du BIEN à un autre",
        "intermédiaire pendant le MANDAT (exclusivité).",
      ],
    },
    {
      title: "Article 9. Séquestre",
      lines: [
        "Le MANDANT autorise le MANDATAIRE à solliciter de l’acquéreur, à la signature d’un",
        "avant-contrat, un dépôt de garantie de 10 % au plus du prix, versé sur le compte",
        "séquestre du notaire chargé de l’acte authentique.",
      ],
    },
    {
      title: "Article 10. Clauses particulières",
      lines: [
        "Pendant le MANDAT et douze mois après sa fin, le MANDANT s’interdit de traiter",
        "directement avec un acquéreur présenté par le MANDATAIRE ; à défaut, une indemnité",
        "égale aux honoraires de l’article 5 serait due.",
      ],
    },
    {
      title: "Article 11. Engagement de non-discrimination",
      lines: [
        "Aucune personne ne peut se voir refuser une visite ou la vente pour un motif",
        "discriminatoire au sens de l’article 225-1 du Code pénal (article 225-2 : trois ans",
        "d’emprisonnement et 45 000 € d’amende).",
      ],
    },
    {
      title: "Article 12. Données personnelles",
      lines: [
        "Les données sont traitées pour l’exécution du MANDAT et conservées le temps des délais",
        "légaux. Droits d’accès, de rectification, d’effacement et de limitation auprès de",
        `${REALESTY.name}, ${REALESTY.address} ; réclamation possible auprès de la CNIL.`,
        "Opposition au démarchage téléphonique : www.bloctel.gouv.fr.",
      ],
    },
    {
      title: "Article 13. Élection de domicile",
      lines: [
        "Le MANDANT élit domicile à l’adresse de son compte Realesty, le MANDATAIRE à son siège.",
      ],
    },
    {
      title: "Article 14. Loi applicable et tribunal compétent",
      lines: [
        "Le MANDAT est régi par la loi française. Un MANDANT consommateur peut saisir",
        "gratuitement le médiateur de la consommation (articles L.611-1 et suivants du Code",
        "de la consommation) ; à défaut d’accord, les juridictions compétentes.",
      ],
    },
    {
      title: "Article 15. Contractualisation électronique",
      lines: [
        "Phase de test : le MANDAT est signé par une signature de test (case d’acceptation et",
        "signature dessinée ou nom tapé) sans valeur juridique. La signature électronique",
        "conforme au règlement eIDAS sera mise en place avant toute mise en vente réelle.",
      ],
    },
    {
      title: "Annexe — Barème d’honoraires",
      lines: [
        "L’Essentiel : 1 % TTC du prix de vente. Le Premium : 1 % TTC du prix de vente,",
        `plus ${PREMIUM_SETUP_EUR} € de frais de dossier et ${PREMIUM_MONTHLY_EUR} € par mois.`,
        "L’Expert : 3 % TTC du prix de vente.",
      ],
    },
    {
      title: "Signature",
      lines: [
        `Signé (signature de test ${typed ? "par nom tapé" : "dessinée"}) par ${facts.signerName},`,
        `le ${frenchDateTime(facts.signedAt)} (heure de Paris).`,
        `Conditions : version ${facts.termsVersion}. Mandat n° ${facts.mandateId}.`,
        `Appareil : ${facts.userAgent ?? "non renseigné"}${
          facts.appVersion ? ` · application ${facts.appVersion}` : ""
        }.`,
        ...(typed && facts.typedSignature ? [`Nom tapé : « ${facts.typedSignature} »`] : []),
        ...(facts.owners.length > 1
          ? ["Les autres propriétaires signeront hors de l’application."]
          : []),
      ],
    },
  ];
}
