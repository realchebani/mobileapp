// Minimal OpenRouter client (chat, transcription, speech) for the Edge
// Functions. The API key is passed in by the caller (read from the
// `OPENROUTER_API_KEY` secret); it is never logged nor returned.

export type FetchLike = (
  input: string,
  init?: RequestInit,
) => Promise<Response>;

export interface OpenRouterOptions {
  apiKey: string;
  baseUrl?: string;
  fetch?: FetchLike;
  /** Per-request timeout (ms). */
  timeoutMs?: number;
  /** Clock used to measure latencies (tests). */
  now?: () => number;
}

/** An OpenRouter error, safe to log (it never carries the key). */
export class OpenRouterError extends Error {
  constructor(readonly status: number, message: string) {
    super(message);
    this.name = "OpenRouterError";
  }
}

export interface ChatMessage {
  role: "system" | "user" | "assistant";
  // deno-lint-ignore no-explicit-any
  content: string | any[];
}

export interface ChatRequest {
  model: string;
  messages: ChatMessage[];
  /** JSON Schema of a strict structured output. */
  jsonSchema?: { name: string; schema: Record<string, unknown> };
  maxTokens?: number;
  temperature?: number;
  reasoningEffort?: "minimal" | "low" | "medium" | "high";
  provider?: Record<string, unknown>;
}

export interface Usage {
  promptTokens: number | null;
  completionTokens: number | null;
  /** Cost reported by OpenRouter (USD). */
  cost: number | null;
}

export interface ChatResult {
  content: string;
  usage: Usage;
  ms: number;
}

export interface TranscriptionRequest {
  model: string;
  /** Raw base64 (no data: prefix). */
  audioBase64: string;
  format: "wav" | "mp3" | "flac" | "m4a" | "ogg" | "webm" | "aac";
  language?: string;
}

export interface TranscriptionResult {
  text: string;
  seconds: number | null;
  cost: number | null;
  ms: number;
}

export interface SpeechRequest {
  model: string;
  input: string;
  voice?: string;
  format?: "mp3" | "pcm";
  speed?: number;
}

export interface SpeechResult {
  audio: Uint8Array;
  contentType: string;
  generationId: string | null;
  ms: number;
}

const DEFAULT_BASE_URL = "https://openrouter.ai/api/v1";

function numberOrNull(value: unknown): number | null {
  return typeof value === "number" && Number.isFinite(value) ? value : null;
}

export class OpenRouterClient {
  readonly #apiKey: string;
  readonly #baseUrl: string;
  readonly #fetch: FetchLike;
  readonly #timeoutMs: number;
  readonly #now: () => number;

  constructor(options: OpenRouterOptions) {
    if (!options.apiKey) throw new OpenRouterError(500, "Missing API key");
    this.#apiKey = options.apiKey;
    this.#baseUrl = options.baseUrl ?? DEFAULT_BASE_URL;
    this.#fetch = options.fetch ?? ((input, init) => fetch(input, init));
    this.#timeoutMs = options.timeoutMs ?? 30_000;
    this.#now = options.now ?? (() => performance.now());
  }

  async #post(path: string, body: unknown): Promise<Response> {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), this.#timeoutMs);
    try {
      const response = await this.#fetch(`${this.#baseUrl}${path}`, {
        method: "POST",
        headers: {
          "Authorization": `Bearer ${this.#apiKey}`,
          "Content-Type": "application/json",
          "HTTP-Referer": "https://realesty.fr",
          "X-Title": "Realesty",
        },
        body: JSON.stringify(body),
        signal: controller.signal,
      });
      if (!response.ok) {
        const text = await response.text().catch(() => "");
        throw new OpenRouterError(
          response.status,
          `OpenRouter ${path} ${response.status}: ${text.slice(0, 300)}`,
        );
      }
      return response;
    } catch (error) {
      if (error instanceof OpenRouterError) throw error;
      const aborted = error instanceof DOMException &&
        error.name === "AbortError";
      throw new OpenRouterError(
        aborted ? 504 : 502,
        aborted ? `OpenRouter ${path} timed out` : `OpenRouter ${path} failed`,
      );
    } finally {
      clearTimeout(timer);
    }
  }

  async chat(request: ChatRequest): Promise<ChatResult> {
    const start = this.#now();
    const body: Record<string, unknown> = {
      model: request.model,
      messages: request.messages,
      usage: { include: true },
    };
    if (request.maxTokens !== undefined) body.max_tokens = request.maxTokens;
    if (request.temperature !== undefined) {
      body.temperature = request.temperature;
    }
    if (request.reasoningEffort) {
      body.reasoning = { effort: request.reasoningEffort };
    }
    if (request.provider) body.provider = request.provider;
    if (request.jsonSchema) {
      body.response_format = {
        type: "json_schema",
        json_schema: {
          name: request.jsonSchema.name,
          strict: true,
          schema: request.jsonSchema.schema,
        },
      };
    }
    const response = await this.#post("/chat/completions", body);
    const json = await response.json();
    const content = json?.choices?.[0]?.message?.content;
    if (typeof content !== "string") {
      throw new OpenRouterError(502, "OpenRouter chat: empty answer");
    }
    return {
      content,
      usage: {
        promptTokens: numberOrNull(json?.usage?.prompt_tokens),
        completionTokens: numberOrNull(json?.usage?.completion_tokens),
        cost: numberOrNull(json?.usage?.cost),
      },
      ms: Math.round(this.#now() - start),
    };
  }

  async transcribe(
    request: TranscriptionRequest,
  ): Promise<TranscriptionResult> {
    const start = this.#now();
    const response = await this.#post("/audio/transcriptions", {
      model: request.model,
      input_audio: { data: request.audioBase64, format: request.format },
      language: request.language ?? "fr",
      temperature: 0,
    });
    const json = await response.json();
    return {
      text: typeof json?.text === "string" ? json.text.trim() : "",
      seconds: numberOrNull(json?.usage?.seconds),
      cost: numberOrNull(json?.usage?.cost),
      ms: Math.round(this.#now() - start),
    };
  }

  async speech(request: SpeechRequest): Promise<SpeechResult> {
    const start = this.#now();
    const body: Record<string, unknown> = {
      model: request.model,
      input: request.input,
      response_format: request.format ?? "mp3",
    };
    if (request.voice) body.voice = request.voice;
    if (request.speed !== undefined) body.speed = request.speed;
    const response = await this.#post("/audio/speech", body);
    const audio = new Uint8Array(await response.arrayBuffer());
    return {
      audio,
      contentType: response.headers.get("content-type") ?? "audio/mpeg",
      generationId: response.headers.get("x-generation-id"),
      ms: Math.round(this.#now() - start),
    };
  }

  /** Cost of a generation (e.g. a speech), when OpenRouter knows it. */
  async generationCost(id: string): Promise<number | null> {
    const response = await this.#fetch(
      `${this.#baseUrl}/generation?id=${encodeURIComponent(id)}`,
      { headers: { "Authorization": `Bearer ${this.#apiKey}` } },
    );
    if (!response.ok) {
      await response.body?.cancel();
      return null;
    }
    const json = await response.json();
    return numberOrNull(json?.data?.total_cost);
  }
}

/** Base64 of [bytes] (chunked, safe for large buffers). */
export function toBase64(bytes: Uint8Array): string {
  let binary = "";
  const chunk = 0x8000;
  for (let i = 0; i < bytes.length; i += chunk) {
    binary += String.fromCharCode(...bytes.subarray(i, i + chunk));
  }
  return btoa(binary);
}
