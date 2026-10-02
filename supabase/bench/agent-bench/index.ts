// Benchmark relay (owner only): runs ONE OpenRouter call (TTS, STT or an
// agent turn with the production prompt and validation) and returns its
// output, latency and cost. The OpenRouter key stays server-side. Access
// requires the `AGENT_BENCH_TOKEN` secret in the `x-bench-token` header.
// Kept out of supabase/functions/ so that it is never deployed by mistake.
// For a benchmark run only: copy it to supabase/functions/agent-bench/,
// replace "../../functions/_shared/" by "../_shared/" in the imports, set the
// AGENT_BENCH_TOKEN secret, deploy, run supabase/bench/run.ts, then delete
// the function, the copy and the secret.

import { OpenRouterClient } from "../../functions/_shared/openrouter/client.ts";
import { agentProvider } from "../../functions/_shared/agent/config.ts";
import { buildMessages } from "../../functions/_shared/agent/prompt.ts";
import { type AgentStep, outputSchema } from "../../functions/_shared/agent/schema.ts";
import { parseModelOutput, validateTurn } from "../../functions/_shared/agent/validate.ts";
import { toBase64 } from "../../functions/_shared/openrouter/client.ts";
import { pcmToWav, speechFormatFor } from "../../functions/_shared/openrouter/audio.ts";

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

function sameToken(a: string, b: string): boolean {
  if (a.length !== b.length || a.length < 16) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

Deno.serve(async (request) => {
  const expected = Deno.env.get("AGENT_BENCH_TOKEN") ?? "";
  if (!sameToken(request.headers.get("x-bench-token") ?? "", expected)) {
    return json({ error: "forbidden" }, 403);
  }
  const client = new OpenRouterClient({
    apiKey: Deno.env.get("OPENROUTER_API_KEY") ?? "",
    timeoutMs: 60_000,
  });
  try {
    const body = await request.json();
    switch (body.op) {
      case "tts": {
        const format = speechFormatFor(body.model);
        const result = await client.speech({
          model: body.model,
          input: body.input,
          voice: body.voice,
          format,
        });
        const audio = format === "pcm" ? pcmToWav(result.audio) : result.audio;
        return json({
          audio_base64: toBase64(audio),
          extension: format === "pcm" ? "wav" : "mp3",
          content_type: result.contentType,
          generation_id: result.generationId,
          bytes: result.audio.length,
          ms: result.ms,
        });
      }
      case "cost":
        return json({ cost: await client.generationCost(body.generation_id) });
      case "stt": {
        const result = await client.transcribe({
          model: body.model,
          audioBase64: body.audio_base64,
          format: body.format,
          language: "fr",
        });
        return json(result);
      }
      case "agent": {
        const step = body.step as AgentStep;
        const currentYear = new Date().getFullYear();
        const result = await client.chat({
          model: body.model,
          messages: buildMessages({
            step,
            values: body.values,
            transcript: body.transcript,
            currentYear,
            lifestyleLabels: { asset: [], watch_point: [] },
          }),
          jsonSchema: { name: "agent_turn", schema: outputSchema(step) },
          maxTokens: 1200,
          temperature: 0,
          provider: agentProvider(body.model),
        });
        let validated = null;
        let parseError = null;
        try {
          validated = validateTurn(parseModelOutput(result.content), {
            step,
            values: body.values,
            transcript: body.transcript,
            currentYear,
          });
        } catch (error) {
          parseError = String(error);
        }
        return json({
          raw: result.content,
          usage: result.usage,
          ms: result.ms,
          validated,
          parse_error: parseError,
        });
      }
      default:
        return json({ error: "unknown op" }, 400);
    }
  } catch (error) {
    const status = typeof (error as { status?: number }).status === "number"
      ? (error as { status: number }).status
      : 500;
    return json({ error: String((error as Error).message ?? error) }, status);
  }
});
