// French explanation of the estimate (plan §3.8). The AI (Claude through
// OpenRouter) only phrases figures computed by the method: every number of
// its text must come from the input, otherwise — or when the call fails —
// a deterministic template is used. The key is never logged nor returned.
import type { EstimateResult, Subject } from "./types.ts";

export const DEFAULT_ESTIMATE_MODEL = "anthropic/claude-opus-5.5";
const ENDPOINT = "https://openrouter.ai/api/v1/chat/completions";
const TIMEOUT_MS = 15000;
const MAX_LENGTH = 900;

export type FetchLike = (input: string, init?: RequestInit) => Promise<Response>;

export interface Explanation {
  text: string;
  source: "ai" | "template";
  /** Why the template was used (diagnosis, never contains the key). */
  fallbackReason?: string;
}

/** French grouping with a narrow no-break space: 479000 → « 479 000 ». */
export function frenchNumber(value: number): string {
  const [whole, decimals] = Math.abs(value).toString().split(".");
  const grouped = whole.replace(/\B(?=(\d{3})+(?!\d))/g, " ");
  return `${value < 0 ? "−" : ""}${grouped}${decimals ? `,${decimals}` : ""}`;
}

/** « 500 m », « 1 km », « 2 km ». */
function radiusLabel(radius: number): string {
  return radius < 1000 ? `${radius} m` : `${radius / 1000} km`;
}

function confidenceLevel(score: number): string {
  return score >= 70 ? "élevée" : score >= 40 ? "moyenne" : "faible";
}

/** The figures given to the AI: no personal data (no name, no address). */
export function explanationFacts(subject: Subject, result: EstimateResult) {
  return {
    type_de_bien: subject.type,
    commune: subject.city,
    surface_habitable_m2: Math.round(subject.livingAreaM2),
    ventes_comparables: result.comparablesCount,
    zone: result.scope === "radius" && result.radiusM !== null
      ? `rayon de ${radiusLabel(result.radiusM)}`
      : "commune",
    periode_annees: result.months === null ? null : Math.round(result.months / 12),
    prix_m2_bas: result.priceM2Low,
    prix_m2_median: result.priceM2Median,
    prix_m2_haut: result.priceM2High,
    fourchette_basse_eur: result.lowEur,
    valeur_mediane_eur: result.medianEur,
    fourchette_haute_eur: result.highEur,
    ventes_sur_12_mois: result.sales12m,
    evolution_sur_1_an_pct: result.yoyChangePct,
    annee_des_dernieres_ventes: result.dataUntil ? Number(result.dataUntil.slice(0, 4)) : null,
    fiabilite: result.confidence === null ? null : confidenceLevel(result.confidence),
  };
}

/** Deterministic French text used when the AI is unavailable or unreliable. */
export function templateExplanation(subject: Subject, result: EstimateResult): string {
  const kind = subject.type === "maison" ? "maisons" : "appartements";
  const where = result.scope === "radius" && result.radiusM !== null
    ? `à moins de ${radiusLabel(result.radiusM)} de votre bien`
    : subject.city
    ? `à ${subject.city}`
    : "dans votre commune";
  const period = result.months === null
    ? ""
    : ` sur les ${Math.round(result.months / 12)} dernières années`;
  return `D’après ${result.comparablesCount} ventes de ${kind} comparables ${where}${period}, ` +
    `le prix médian ressort à ${frenchNumber(result.priceM2Median ?? 0)} €/m², ` +
    `soit une tendance de ${frenchNumber(result.lowEur ?? 0)} à ` +
    `${frenchNumber(result.highEur ?? 0)} € pour ` +
    `${frenchNumber(Math.round(subject.livingAreaM2))} m². ` +
    "Ces chiffres sont indicatifs et non certifiés\u00a0: votre expert établira la valeur de votre bien.";
}

/** Every number written in [text], normalised (« 479 000 » → 479000, « 0,2 » → 0.2). */
export function numbersIn(text: string): number[] {
  const matches = text.match(/\d+(?:[\s  ]\d{3})*(?:[.,]\d+)?/g) ?? [];
  return matches.map((match) => Number(match.replace(/[\s  ]/g, "").replace(",", ".")));
}

function allowedNumbers(value: unknown, into: Set<number>): Set<number> {
  if (typeof value === "number") {
    into.add(value);
    into.add(Math.abs(value));
  } else if (typeof value === "string") {
    for (const number of numbersIn(value)) into.add(number);
  } else if (Array.isArray(value)) {
    for (const item of value) allowedNumbers(item, into);
  } else if (value && typeof value === "object") {
    for (const item of Object.values(value)) allowedNumbers(item, into);
  }
  return into;
}

/** True when every number of [text] appears in [facts]. */
export function usesOnlyGivenNumbers(text: string, facts: unknown): boolean {
  const allowed = allowedNumbers(facts, new Set());
  return numbersIn(text).every((number) => allowed.has(number));
}

const SYSTEM_PROMPT = [
  "Tu es l’agent Realesty. Tu rédiges en français, en vouvoyant le vendeur,",
  "trois phrases courtes au maximum (450 caractères en tout), sur un ton prudent, pour expliquer d’où vient une",
  "tendance de prix NON CERTIFIÉE de son bien.",
  "Utilise UNIQUEMENT les nombres du JSON fourni, recopiés à l’identique (tu",
  "peux les écrire avec des espaces de milliers) ; n’ajoute aucun autre",
  "chiffre, aucun pourcentage, aucune date ni promesse. Rappelle que la",
  "tendance est indicative et que l’expert certifiera la valeur.",
  "Le bloc <facteurs> liste des caractéristiques du bien, sans effet chiffré.",
].join(" ");

export interface ExplainOptions {
  apiKey: string | undefined;
  model?: string;
  fetch?: FetchLike;
  timeoutMs?: number;
}

/** Asks the AI for the explanation; falls back to the template on any problem. */
export async function explainEstimate(
  subject: Subject,
  result: EstimateResult,
  options: ExplainOptions,
): Promise<Explanation> {
  const template = (fallbackReason: string): Explanation => ({
    text: templateExplanation(subject, result),
    source: "template",
    fallbackReason,
  });
  if (!options.apiKey) return template("no_api_key");
  const facts = explanationFacts(subject, result);
  // Only the factors derived from structured answers: the seller's free
  // text (V6 assets / watch points) is never sent to OpenRouter.
  const freeText = new Set([...subject.assets, ...subject.watchPoints].map((l) => l.trim()));
  const factors = result.factors
    .filter((f) => !freeText.has(f.label))
    .map((f) => `${f.sign} ${f.label}`)
    .join("\n");
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), options.timeoutMs ?? TIMEOUT_MS);
  try {
    const response = await (options.fetch ?? fetch)(ENDPOINT, {
      method: "POST",
      signal: controller.signal,
      headers: {
        "Authorization": `Bearer ${options.apiKey}`,
        "Content-Type": "application/json",
        "HTTP-Referer": "https://realesty.fr",
        "X-Title": "Realesty",
      },
      body: JSON.stringify({
        model: options.model || DEFAULT_ESTIMATE_MODEL,
        max_tokens: 1200,
        temperature: 0.2,
        provider: { data_collection: "deny" },
        response_format: {
          type: "json_schema",
          json_schema: {
            name: "explication",
            strict: true,
            schema: {
              type: "object",
              properties: { explanation: { type: "string" } },
              required: ["explanation"],
              additionalProperties: false,
            },
          },
        },
        messages: [
          { role: "system", content: SYSTEM_PROMPT },
          {
            role: "user",
            content: `Chiffres calculés :\n${JSON.stringify(facts)}\n` +
              `<facteurs>\n${factors}\n</facteurs>`,
          },
        ],
      }),
    });
    if (!response.ok) {
      const detail = (await response.text()).slice(0, 200);
      return template(`http_${response.status}: ${detail}`);
    }
    const body = await response.json();
    const content = body?.choices?.[0]?.message?.content;
    if (typeof content !== "string") {
      const choice = body?.choices?.[0];
      return template(
        `no_content: ${choice?.finish_reason ?? ""} ${
          JSON.stringify(choice?.message ?? body?.error ?? null).slice(0, 300)
        }`,
      );
    }
    const parsed = JSON.parse(content);
    const text = typeof parsed?.explanation === "string" ? parsed.explanation.trim() : "";
    if (text === "" || text.length > MAX_LENGTH) return template("invalid_length");
    if (!usesOnlyGivenNumbers(text, facts)) return template(`unknown_number: ${text}`);
    return { text, source: "ai" };
  } catch (error) {
    return template(error instanceof Error ? error.name : "error");
  } finally {
    clearTimeout(timer);
  }
}
