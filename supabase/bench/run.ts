// Benchmark driver of the voice agent (STT → agent → TTS), run locally:
//
//   BENCH_URL=https://<ref>.supabase.co/functions/v1/agent-bench \
//   BENCH_TOKEN=<AGENT_BENCH_TOKEN> BENCH_AUTH=<anon key> BENCH_OUT=<dir> \
//   deno run -A supabase/bench/run.ts [--only=stt,agent,e2e,tts]
//
// Every OpenRouter call goes through the `agent-bench` Edge Function (the
// key never leaves Supabase). Test audio: recordings in <BENCH_OUT>/audio/
// <id>.m4a when present; otherwise generated — half with an OpenRouter TTS
// model, half with macOS `say` — then re-encoded like the app (AAC 16 kHz
// mono, `afconvert`). Synthetic audio is cleaner than a real phone
// recording: STT results are optimistic.

import { normalize } from "../functions/_shared/agent/validate.ts";

const url = Deno.env.get("BENCH_URL")!;
const token = Deno.env.get("BENCH_TOKEN")!;
/** A JWT accepted by the Functions gateway (the project's public anon key). */
const auth = Deno.env.get("BENCH_AUTH")!;
const out = Deno.env.get("BENCH_OUT") ?? "./bench-out";
const only = (Deno.args.find((a) => a.startsWith("--only="))?.slice(7) ??
  "stt,agent,e2e,tts").split(",");

export const STT_MODELS = [
  "mistralai/voxtral-mini-transcribe",
  "openai/whisper-large-v3-turbo",
  "openai/gpt-4o-mini-transcribe",
];
export const AGENT_MODELS = [
  "anthropic/claude-haiku-4.5",
  "anthropic/claude-sonnet-5.5",
  "google/gemini-3.5-flash-lite",
];
export const TTS_MODELS: [string, string][] = [
  ["google/gemini-3.8-flash-lite-tts", "Kore"],
  ["hexgrad/kokoro-82m", "ff_siwis"],
  ["mistralai/voxtral-mini-tts-2603", "fr_marie_neutral"],
];
const AUDIO_TTS: [string, string][] = [
  ["google/gemini-3.8-flash-lite-tts", "Kore"],
  ["google/gemini-3.8-flash-lite-tts", "Puck"],
  ["google/gemini-3.8-flash-lite-tts", "Aoede"],
  ["google/gemini-3.8-flash-lite-tts", "Charon"],
];
const SAY_VOICES = [
  "Jacques",
  "Flo (Français (France))",
  "Thomas",
  "Eddy (Français (France))",
];
const SAMPLE_REPLIES = [
  "Parfait, c’est noté. Et pour l’assainissement : tout-à-l’égout ou fosse septique ?",
  "Merci. Votre maison a-t-elle une piscine, un garage ou une terrasse ?",
  "J’ai tout ce qu’il me faut. Vérifions ensemble le récapitulatif.",
];

interface Utterance {
  id: string;
  step: "technical" | "lifestyle";
  values: Record<string, unknown>;
  text: string;
  expected: Record<string, unknown>;
  expected_items?: { asset: number; watch_point: number };
}

const utterances: Utterance[] = JSON.parse(
  await Deno.readTextFile(new URL("./utterances.json", import.meta.url)),
);

// deno-lint-ignore no-explicit-any
async function call(body: Record<string, unknown>): Promise<any> {
  const response = await fetch(url, {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${auth}`,
      "apikey": auth,
      "x-bench-token": token,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(body),
    signal: AbortSignal.timeout(120_000),
  });
  const json = await response.json();
  if (!response.ok) throw new Error(`${body.op} ${body.model}: ${json.error}`);
  return json;
}

async function run(cmd: string, args: string[]) {
  const { code, stderr } = await new Deno.Command(cmd, { args }).output();
  if (code !== 0) throw new Error(new TextDecoder().decode(stderr));
}

function fromBase64(b64: string): Uint8Array {
  return Uint8Array.from(atob(b64), (c) => c.charCodeAt(0));
}

function toBase64(bytes: Uint8Array): string {
  let s = "";
  for (let i = 0; i < bytes.length; i += 0x8000) {
    s += String.fromCharCode(...bytes.subarray(i, i + 0x8000));
  }
  return btoa(s);
}

async function exists(path: string) {
  try {
    await Deno.stat(path);
    return true;
  } catch {
    return false;
  }
}

/** Word error rate of [hyp] against [ref] (normalized words). */
export function wer(ref: string, hyp: string): number {
  const r = normalize(ref).split(" ").filter(Boolean);
  const h = normalize(hyp).split(" ").filter(Boolean);
  const d = Array.from(
    { length: r.length + 1 },
    (_, i) =>
      Array.from(
        { length: h.length + 1 },
        (_, j) => i === 0 ? j : j === 0 ? i : 0,
      ),
  );
  for (let i = 1; i <= r.length; i++) {
    for (let j = 1; j <= h.length; j++) {
      d[i][j] = Math.min(
        d[i - 1][j] + 1,
        d[i][j - 1] + 1,
        d[i - 1][j - 1] + (r[i - 1] === h[j - 1] ? 0 : 1),
      );
    }
  }
  return r.length ? d[r.length][h.length] / r.length : 0;
}

async function pool<T, R>(items: T[], size: number, fn: (t: T) => Promise<R>) {
  const results: R[] = new Array(items.length);
  let next = 0;
  await Promise.all(Array.from({ length: size }, async () => {
    while (next < items.length) {
      const i = next++;
      results[i] = await fn(items[i]);
    }
  }));
  return results;
}

/** Parallel calls (OpenRouter limits new accounts' requests per minute). */
const poolSize = Number(Deno.env.get("BENCH_POOL") ?? "4");
const audioDir = `${out}/audio`;
await Deno.mkdir(audioDir, { recursive: true });
const sources: Record<string, string> = {};
let audioCost = 0;

// 1. Test audio.
for (const [i, u] of utterances.entries()) {
  const m4a = `${audioDir}/${u.id}.m4a`;
  if (await exists(m4a)) {
    sources[u.id] = sources[u.id] ?? "recording";
    continue;
  }
  if (i % 2 === 0) {
    const [model, voice] = AUDIO_TTS[(i / 2) % AUDIO_TTS.length];
    const tts = await call({ op: "tts", model, voice, input: u.text });
    const mp3 = `${audioDir}/${u.id}.${tts.extension}`;
    await Deno.writeFile(mp3, fromBase64(tts.audio_base64));
    await run("afconvert", [
      "-f",
      "m4af",
      "-d",
      "aac@16000",
      "-c",
      "1",
      "-b",
      "32000",
      mp3,
      m4a,
    ]);
    sources[u.id] = `${model} (${voice})`;
    if (tts.generation_id) {
      await new Promise((r) => setTimeout(r, 1500));
      audioCost += (await call({ op: "cost", generation_id: tts.generation_id })).cost ??
        0;
    }
  } else {
    const voice = SAY_VOICES[((i - 1) / 2) % SAY_VOICES.length];
    const aiff = `${audioDir}/${u.id}.aiff`;
    await run("say", ["-v", voice, "-o", aiff, u.text]);
    await run("afconvert", [
      "-f",
      "m4af",
      "-d",
      "aac@16000",
      "-c",
      "1",
      "-b",
      "32000",
      aiff,
      m4a,
    ]);
    sources[u.id] = `macOS say (${voice})`;
  }
}

// deno-lint-ignore no-explicit-any
const report: Record<string, any> = {
  date: new Date().toISOString(),
  sources,
  audioCost,
};

// 2. STT.
if (only.includes("stt")) {
  report.stt = {};
  for (const model of STT_MODELS) {
    const rows = await pool(utterances, 4, async (u) => {
      const audio = await Deno.readFile(`${audioDir}/${u.id}.m4a`);
      try {
        const r = await call({
          op: "stt",
          model,
          audio_base64: toBase64(audio),
          format: "m4a",
        });
        return {
          id: u.id,
          text: r.text,
          wer: wer(u.text, r.text),
          ms: r.ms,
          cost: r.cost,
          seconds: r.seconds,
        };
      } catch (error) {
        return { id: u.id, error: String(error) };
      }
    });
    report.stt[model] = rows;
    console.log("stt", model, "done");
  }
}

function sameValue(a: unknown, b: unknown): boolean {
  if (Array.isArray(a) && Array.isArray(b)) {
    return a.length === b.length && a.every((x) => b.includes(x));
  }
  return a === b;
}

async function agentRow(
  model: string,
  u: Utterance,
  transcript: string,
  // deno-lint-ignore no-explicit-any
): Promise<any> {
  try {
    const r = await call({
      op: "agent",
      model,
      step: u.step,
      values: u.values,
      transcript,
    });
    const patch = r.validated?.patch ?? {};
    const suggestions = r.validated?.suggestions ?? {};
    let expectedN = 0, correct = 0, wrong = 0;
    for (const [field, value] of Object.entries(u.expected)) {
      expectedN++;
      if (value === "low") {
        correct += typeof patch[field] === "number" && patch[field] <= 4 ? 1 : 0;
      } else if (value === "high") {
        correct += typeof patch[field] === "number" && patch[field] >= 6 ? 1 : 0;
      } else if (value === "suggested") correct += field in suggestions ? 1 : 0;
      else correct += sameValue(patch[field], value) ? 1 : 0;
    }
    for (const [field, value] of Object.entries(patch)) {
      const exp = u.expected[field];
      if (exp === undefined) wrong++;
      else if (exp !== "low" && exp !== "high" && !sameValue(value, exp)) {
        wrong++;
      }
    }
    let itemsDiff = 0;
    if (u.expected_items) {
      // deno-lint-ignore no-explicit-any
      const items = (r.validated?.lifestyle_items ?? []) as any[];
      for (const kind of ["asset", "watch_point"] as const) {
        itemsDiff += Math.abs(
          items.filter((i) => i.kind === kind).length - u.expected_items[kind],
        );
      }
    }
    return {
      id: u.id,
      transcript,
      expected: expectedN,
      correct,
      wrong,
      itemsDiff,
      ms: r.ms,
      cost: r.usage.cost,
      tokensIn: r.usage.promptTokens,
      tokensOut: r.usage.completionTokens,
      reply: JSON.parse(r.raw).reply_fr,
      patch,
      items: r.validated?.lifestyle_items,
      rejected: r.validated?.rejected,
      parseError: r.parse_error,
    };
  } catch (error) {
    return { id: u.id, error: String(error) };
  }
}

// 3. Agent (on the reference text, to isolate extraction from STT).
if (only.includes("agent")) {
  report.agent = {};
  for (const model of AGENT_MODELS) {
    report.agent[model] = await pool(
      utterances,
      poolSize,
      (u) => agentRow(model, u, u.text),
    );
    console.log("agent", model, "done");
  }
}

// 3b. End to end: one agent model on each STT model's transcripts
// (from a previous `--only=stt` run).
if (only.includes("e2e")) {
  const model = Deno.env.get("E2E_AGENT") ?? AGENT_MODELS[0];
  const stt = JSON.parse(await Deno.readTextFile(`${out}/results-stt.json`)).stt;
  report.e2e = { agent: model, byStt: {} };
  const sttModels = Deno.env.get("E2E_STT")?.split(",") ?? STT_MODELS;
  for (const sttModel of sttModels) {
    const texts: Record<string, string> = Object.fromEntries(
      // deno-lint-ignore no-explicit-any
      stt[sttModel].map((x: any) => [x.id, x.text ?? ""]),
    );
    report.e2e.byStt[sttModel] = await pool(
      utterances,
      poolSize,
      (u) => agentRow(model, u, texts[u.id]),
    );
    console.log("e2e", sttModel, "done");
  }
}

// 4. TTS.
if (only.includes("tts")) {
  report.tts = {};
  for (const [model, voice] of TTS_MODELS) {
    const rows = [];
    for (const [i, input] of SAMPLE_REPLIES.entries()) {
      try {
        const r = await call({ op: "tts", model, voice, input });
        await Deno.writeFile(
          `${out}/tts-${model.replace("/", "_")}-${i}.${r.extension}`,
          fromBase64(r.audio_base64),
        );
        await new Promise((res) => setTimeout(res, 2000));
        const cost = r.generation_id
          ? (await call({ op: "cost", generation_id: r.generation_id })).cost
          : null;
        rows.push({ i, chars: input.length, ms: r.ms, bytes: r.bytes, cost });
      } catch (error) {
        rows.push({ i, error: String(error) });
      }
    }
    report.tts[model] = rows;
    console.log("tts", model, "done");
  }
}

await Deno.writeTextFile(
  `${out}/results-${only.join("-")}.json`,
  JSON.stringify(report, null, 2),
);
console.log("written", `${out}/results-${only.join("-")}.json`);
