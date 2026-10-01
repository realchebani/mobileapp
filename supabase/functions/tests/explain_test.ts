import { assert, assertEquals, assertStringIncludes } from "jsr:@std/assert@1";
import {
  DEFAULT_ESTIMATE_MODEL,
  explainEstimate,
  explanationFacts,
  frenchNumber,
  numbersIn,
  templateExplanation,
  usesOnlyGivenNumbers,
} from "../_shared/estimation/explain.ts";
import { insufficient } from "../_shared/estimation/estimate.ts";
import type { EstimateResult } from "../_shared/estimation/types.ts";
import { subject } from "./helpers.ts";

const result: EstimateResult = {
  ...insufficient(null),
  status: "ok",
  dataUntil: "2025-12-19",
  lowEur: 420000,
  medianEur: 479000,
  highEur: 546000,
  priceM2Low: 3572,
  priceM2Median: 4162,
  priceM2High: 4648,
  confidence: 81,
  comparablesCount: 27,
  scope: "radius",
  radiusM: 500,
  months: 36,
  sales12m: 62,
  yoyChangePct: 0.2,
  factors: [{ sign: "+", label: "Piscine" }],
};

Deno.test("frenchNumber and numbersIn", () => {
  assertEquals(frenchNumber(479000), "479 000");
  assertEquals(frenchNumber(-1.5), "−1,5");
  assertEquals(numbersIn("De 420 000 à 546 000 €, soit 0,2 % sur 1 an"), [420000, 546000, 0.2, 1]);
});

Deno.test("template explanation", () => {
  const text = templateExplanation(subject(), result);
  assertStringIncludes(
    text,
    "D’après 27 ventes de maisons comparables à moins de 500 m de votre bien",
  );
  assertStringIncludes(text, "4 162 €/m²");
  assertStringIncludes(text, "non certifiés");
  assert(usesOnlyGivenNumbers(text, explanationFacts(subject(), result)));
  const commune = templateExplanation(
    subject({ type: "appartement" }),
    { ...result, scope: "commune", radiusM: null },
  );
  assertStringIncludes(commune, "appartements comparables à Chaponost");
  assertStringIncludes(
    templateExplanation(subject({ city: null }), { ...result, scope: "commune", radiusM: null }),
    "dans votre commune",
  );
  assertStringIncludes(templateExplanation(subject(), { ...result, radiusM: 2000 }), "2 km");
});

Deno.test("explanationFacts carries no address and the confidence level", () => {
  const facts = explanationFacts(subject(), result);
  assertEquals(facts.fiabilite, "élevée");
  assertEquals(facts.dernieres_ventes_connues, "décembre 2025");
  assertEquals(explanationFacts(subject(), { ...result, confidence: 50 }).fiabilite, "moyenne");
  assertEquals(explanationFacts(subject(), { ...result, confidence: 10 }).fiabilite, "faible");
  assertEquals(
    explanationFacts(subject(), { ...result, confidence: null, dataUntil: null, scope: "commune" })
      .zone,
    "commune",
  );
  assert(!JSON.stringify(facts).includes("45.71"));
});

function fakeFetch(response: () => Response | Promise<Response>) {
  const calls: { url: string; body: Record<string, unknown>; headers: Record<string, string> }[] =
    [];
  const fetcher = (url: string, init?: RequestInit) => {
    calls.push({
      url,
      body: JSON.parse(String(init?.body)),
      headers: init?.headers as Record<string, string>,
    });
    return Promise.resolve(response());
  };
  return { fetcher, calls };
}

const aiAnswer = (text: string) =>
  new Response(
    JSON.stringify({ choices: [{ message: { content: JSON.stringify({ explanation: text }) } }] }),
  );

Deno.test("explainEstimate keeps an AI text that only uses given numbers", async () => {
  const { fetcher, calls } = fakeFetch(() =>
    aiAnswer(
      "Selon 27 ventes, votre bien se situerait entre 420 000 € et 546 000 €, à titre indicatif.",
    )
  );
  const explanation = await explainEstimate(subject(), result, { apiKey: "k", fetch: fetcher });
  assertEquals(explanation.source, "ai");
  assertEquals(calls[0].url, "https://openrouter.ai/api/v1/chat/completions");
  assertEquals(calls[0].body.model, DEFAULT_ESTIMATE_MODEL);
  assertEquals(calls[0].headers.Authorization, "Bearer k");
  const model = await explainEstimate(subject(), result, {
    apiKey: "k",
    fetch: fetcher,
    model: "m",
  });
  assertEquals(model.source, "ai");
  assertEquals(calls[1].body.model, "m");
});

Deno.test("explainEstimate falls back to the template", async () => {
  const cases: [string, () => Response | Promise<Response>][] = [
    ["unknown_number", () => aiAnswer("Votre bien vaut 999 999 €.")],
    ["invalid_length", () => aiAnswer("")],
    ["http_500", () => new Response("boom", { status: 500 })],
    ["no_content", () => new Response(JSON.stringify({ choices: [] }))],
    ["SyntaxError", () => new Response("not json")],
  ];
  for (const [reason, response] of cases) {
    const { fetcher } = fakeFetch(response);
    const explanation = await explainEstimate(subject(), result, { apiKey: "k", fetch: fetcher });
    assertEquals(explanation.source, "template");
    assertStringIncludes(explanation.fallbackReason!, reason);
  }
  const none = await explainEstimate(subject(), result, { apiKey: undefined });
  assertEquals(none.fallbackReason, "no_api_key");
  const slow = await explainEstimate(subject(), result, {
    apiKey: "k",
    timeoutMs: 5,
    fetch: (_url, init) =>
      new Promise((_resolve, reject) =>
        init?.signal?.addEventListener("abort", () => reject(new DOMException("t", "AbortError")))
      ),
  });
  assertEquals(slow.fallbackReason, "AbortError");
  const thrown = await explainEstimate(subject(), result, {
    apiKey: "k",
    fetch: () => Promise.reject("offline"),
  });
  assertEquals(thrown.fallbackReason, "error");
});
