import { assert, assertEquals, assertRejects } from "jsr:@std/assert@1";
import { OpenRouterClient, OpenRouterError, toBase64 } from "../_shared/openrouter/client.ts";
import {
  audioSeconds,
  isSpeechTooShort,
  mp3Info,
  pcmToWav,
  repairXingHeader,
  speechFormatFor,
} from "../_shared/openrouter/audio.ts";

type Call = { url: string; init?: RequestInit };

function fakeFetch(responses: Response[], calls: Call[] = []) {
  return (url: string, init?: RequestInit) => {
    calls.push({ url, init });
    const next = responses.shift();
    return next ? Promise.resolve(next) : Promise.reject(new TypeError("net"));
  };
}

function client(responses: Response[], calls: Call[] = [], timeoutMs = 1000) {
  let t = 0;
  return new OpenRouterClient({
    apiKey: "test-key",
    fetch: fakeFetch(responses, calls),
    timeoutMs,
    now: () => (t += 100),
  });
}

Deno.test("requires an API key", () => {
  let error: unknown;
  try {
    new OpenRouterClient({ apiKey: "" });
  } catch (e) {
    error = e;
  }
  assert(error instanceof OpenRouterError);
});

Deno.test("chat sends the structured-output request and reads usage", async () => {
  const calls: Call[] = [];
  const result = await client([
    Response.json({
      choices: [{ message: { content: '{"ok":true}' } }],
      usage: { prompt_tokens: 10, completion_tokens: 5, cost: 0.001 },
    }),
  ], calls).chat({
    model: "anthropic/claude-haiku-4.5",
    messages: [{ role: "user", content: "x" }],
    jsonSchema: { name: "s", schema: { type: "object" } },
    maxTokens: 10,
    temperature: 0,
    reasoningEffort: "low",
    provider: { data_collection: "deny" },
  });
  assertEquals(result, {
    content: '{"ok":true}',
    usage: { promptTokens: 10, completionTokens: 5, cost: 0.001 },
    ms: 100,
  });
  assertEquals(calls[0].url, "https://openrouter.ai/api/v1/chat/completions");
  const body = JSON.parse(calls[0].init!.body as string);
  assertEquals(body.response_format.json_schema.strict, true);
  assertEquals(body.reasoning, { effort: "low" });
  assertEquals(body.max_tokens, 10);
  assertEquals(
    (calls[0].init!.headers as Record<string, string>).Authorization,
    "Bearer test-key",
  );
});

Deno.test("chat without options and with missing usage", async () => {
  const calls: Call[] = [];
  const result = await client([
    Response.json({ choices: [{ message: { content: "x" } }] }),
  ], calls).chat({ model: "m", messages: [] });
  assertEquals(result.usage, {
    promptTokens: null,
    completionTokens: null,
    cost: null,
  });
  const body = JSON.parse(calls[0].init!.body as string);
  assertEquals(Object.keys(body).sort(), ["messages", "model", "usage"]);
});

Deno.test("chat errors never carry the key", async () => {
  const error = await assertRejects(
    () =>
      client([new Response("bad", { status: 429 })]).chat({
        model: "m",
        messages: [],
      }),
    OpenRouterError,
  );
  assertEquals(error.status, 429);
  assert(!error.message.includes("test-key"));
  await assertRejects(
    () =>
      client([Response.json({ choices: [] })]).chat({
        model: "m",
        messages: [],
      }),
    OpenRouterError,
    "empty answer",
  );
  const network = await assertRejects(
    () => client([]).chat({ model: "m", messages: [] }),
    OpenRouterError,
  );
  assertEquals(network.status, 502);
});

Deno.test("requests time out", async () => {
  const slow = new OpenRouterClient({
    apiKey: "k",
    timeoutMs: 5,
    fetch: (_url, init) =>
      new Promise((_resolve, reject) => {
        init?.signal?.addEventListener("abort", () =>
          reject(new DOMException("aborted", "AbortError")));
      }),
  });
  const error = await assertRejects(
    () => slow.chat({ model: "m", messages: [] }),
    OpenRouterError,
  );
  assertEquals(error.status, 504);
});

Deno.test("transcribe", async () => {
  const calls: Call[] = [];
  const result = await client([
    Response.json({ text: " Bonjour ", usage: { seconds: 2, cost: 0.0001 } }),
  ], calls).transcribe({ model: "stt", audioBase64: "AAA", format: "m4a" });
  assertEquals(result, { text: "Bonjour", seconds: 2, cost: 0.0001, ms: 100 });
  const body = JSON.parse(calls[0].init!.body as string);
  assertEquals(body.input_audio, { data: "AAA", format: "m4a" });
  assertEquals(body.language, "fr");
  const empty = await client([Response.json({})]).transcribe({
    model: "stt",
    audioBase64: "A",
    format: "wav",
    language: "en",
  });
  assertEquals(empty.text, "");
});

Deno.test("speech and generation cost", async () => {
  const calls: Call[] = [];
  const c = client([
    new Response(new Uint8Array([1, 2, 3]), {
      headers: { "content-type": "audio/mpeg", "x-generation-id": "g1" },
    }),
    new Response(new Uint8Array([4])),
    Response.json({ data: { total_cost: 0.002 } }),
    new Response("no", { status: 404 }),
  ], calls);
  const speech = await c.speech({
    model: "tts",
    input: "Salut",
    voice: "Kore",
    speed: 1,
  });
  assertEquals(speech.audio, new Uint8Array([1, 2, 3]));
  assertEquals(speech.generationId, "g1");
  assertEquals(
    JSON.parse(calls[0].init!.body as string).response_format,
    "mp3",
  );
  const bare = await c.speech({ model: "tts", input: "Salut", format: "pcm" });
  assertEquals(bare.contentType, "audio/mpeg");
  assertEquals(bare.generationId, null);
  assertEquals(await c.generationCost("g1"), 0.002);
  assertEquals(await c.generationCost("g2"), null);
});

Deno.test("audio helpers", () => {
  assertEquals(toBase64(new Uint8Array([104, 105])), "aGk=");
  assertEquals(speechFormatFor("google/gemini-3.8-flash-lite-tts"), "pcm");
  assertEquals(speechFormatFor("hexgrad/kokoro-82m"), "mp3");
  const wav = pcmToWav(new Uint8Array([1, 2, 3, 4]));
  assertEquals(wav.length, 48);
  assertEquals(new TextDecoder().decode(wav.slice(0, 4)), "RIFF");
  assertEquals(new DataView(wav.buffer).getUint32(24, true), 24000);
});

/** [count] frames with header bytes [b1, b2] (MPEG-1 or MPEG-2 Layer III). */
function frames(count: number, b1: number, b2: number, size: number) {
  const bytes = new Uint8Array(count * size);
  for (let i = 0; i < count; i++) bytes.set([0xff, b1, b2, 0xc4], i * size);
  return bytes;
}

Deno.test("mp3Info walks MPEG frames after an ID3 tag", () => {
  // MPEG-1, 128 kbit/s, 44.1 kHz: 417 bytes, 1152 samples per frame.
  const mpeg1 = frames(10, 0xfb, 0x90, 417);
  const tagged = new Uint8Array(20 + mpeg1.length);
  tagged.set([0x49, 0x44, 0x33, 4, 0, 0, 0, 0, 0, 10], 0);
  tagged.set(mpeg1, 20);
  const info = mp3Info(tagged)!;
  assertEquals(info.start, 20);
  assertEquals(info.frames, 10);
  assertEquals(Math.round(info.seconds * 1000), 261);
  assertEquals(mp3Info(new Uint8Array([1, 2, 3, 4])), null);
  assertEquals(mp3Info(frames(2, 0xf7, 0x44, 96)), null); // layer II
  assertEquals(mp3Info(frames(2, 0xeb, 0x44, 96)), null); // reserved
  assertEquals(mp3Info(frames(2, 0xf3, 0x4c, 96)), null); // bad rate
  assertEquals(mp3Info(frames(2, 0xf3, 0x04, 96)), null); // free bitrate
  assertEquals(audioSeconds(new Uint8Array(4), "mp3"), 0);
});

Deno.test("repairXingHeader", () => {
  const plain = frames(5, 0xf3, 0x44, 96);
  assertEquals(repairXingHeader(plain), plain);
  assertEquals(repairXingHeader(new Uint8Array(3)).length, 3);
  // An "Info" tag with the byte count only.
  const info = frames(5, 0xf3, 0x44, 96);
  info.set([0x49, 0x6e, 0x66, 0x6f, 0, 0, 0, 2], 13);
  const repaired = repairXingHeader(info);
  assertEquals(new DataView(repaired.buffer).getUint32(21), 480);
  // A correct frame count is kept.
  const right = frames(5, 0xf3, 0x44, 96);
  right.set([0x58, 0x69, 0x6e, 0x67, 0, 0, 0, 1, 0, 0, 0, 4], 13);
  assertEquals(new DataView(repairXingHeader(right).buffer).getUint32(21), 4);
});

Deno.test("speech duration checks", () => {
  assertEquals(audioSeconds(new Uint8Array(48_044), "wav"), 1);
  assertEquals(audioSeconds(new Uint8Array(10), "wav"), 0);
  assert(isSpeechTooShort(1, 82));
  assert(!isSpeechTooShort(4.7, 82));
  assert(!isSpeechTooShort(0, 10));
});
