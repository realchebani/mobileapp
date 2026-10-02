// Models of the voice agent, configurable with Supabase secrets (no app
// release needed). Defaults = the cheapest options of the benchmark for the
// test phase (owner decision, 2026-10-02), to reassess afterwards
// (docs/plans/2026-10-01-voix-et-agent-ia.md).

export interface AgentModels {
  stt: string;
  agent: string;
  tts: string;
  ttsVoice: string | undefined;
}

export const DEFAULT_MODELS: AgentModels = {
  stt: "openai/whisper-large-v3-turbo",
  agent: "google/gemini-3.5-flash-lite",
  tts: "hexgrad/kokoro-82m",
  // The voice of the TTS model (`defaultVoice`): ff_siwis for Kokoro.
  ttsVoice: undefined,
};

type Env = { get(name: string): string | undefined };

function pick(env: Env, name: string): string | undefined {
  const value = env.get(name)?.trim();
  return value ? value : undefined;
}

/** The models from `OPENROUTER_MODEL_STT`, `…_AGENT`, `…_TTS` and
 * `OPENROUTER_TTS_VOICE`, falling back to [DEFAULT_MODELS]. */
export function agentModels(env: Env): AgentModels {
  return {
    stt: pick(env, "OPENROUTER_MODEL_STT") ?? DEFAULT_MODELS.stt,
    agent: pick(env, "OPENROUTER_MODEL_AGENT") ?? DEFAULT_MODELS.agent,
    tts: pick(env, "OPENROUTER_MODEL_TTS") ?? DEFAULT_MODELS.tts,
    ttsVoice: pick(env, "OPENROUTER_TTS_VOICE") ?? DEFAULT_MODELS.ttsVoice,
  };
}

/** Provider routing for the agent model: no training on our data, and the
 * vendor's own endpoint for Claude. */
export function agentProvider(model: string): Record<string, unknown> {
  return model.startsWith("anthropic/")
    ? { order: ["anthropic"], allow_fallbacks: false, data_collection: "deny" }
    : { data_collection: "deny" };
}
