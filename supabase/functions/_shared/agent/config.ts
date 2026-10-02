// Models of the voice agent, configurable with Supabase secrets (no app
// release needed). Defaults = the cheapest options of the benchmark for the
// test phase (owner decision, 2026-10-02), to reassess afterwards
// (docs/plans/2026-10-01-voix-et-agent-ia.md).

import { AGENT_STEPS, type AgentStep } from "./steps/types.ts";

export interface AgentModels {
  stt: string;
  agent: string;
  tts: string;
  ttsVoice: string | undefined;
  /** Agent model of one step only (`OPENROUTER_MODEL_AGENT_<STEP>`, e.g.
   * `…_ROOMS`): the re-evaluation hook of EPIC-14 (plan §7.4), switched
   * by secret without an app release. */
  agentByStep?: Partial<Record<AgentStep, string>>;
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

/** The models from `OPENROUTER_MODEL_STT`, `…_AGENT`, `…_TTS`,
 * `OPENROUTER_TTS_VOICE` and the per-step `OPENROUTER_MODEL_AGENT_<STEP>`,
 * falling back to [DEFAULT_MODELS]. */
export function agentModels(env: Env): AgentModels {
  const agentByStep: Partial<Record<AgentStep, string>> = {};
  for (const step of AGENT_STEPS) {
    const model = pick(env, `OPENROUTER_MODEL_AGENT_${step.toUpperCase()}`);
    if (model) agentByStep[step] = model;
  }
  return {
    stt: pick(env, "OPENROUTER_MODEL_STT") ?? DEFAULT_MODELS.stt,
    agent: pick(env, "OPENROUTER_MODEL_AGENT") ?? DEFAULT_MODELS.agent,
    tts: pick(env, "OPENROUTER_MODEL_TTS") ?? DEFAULT_MODELS.tts,
    ttsVoice: pick(env, "OPENROUTER_TTS_VOICE") ?? DEFAULT_MODELS.ttsVoice,
    agentByStep,
  };
}

/** The agent model of [step]: its own secret, else the common one. */
export function agentModelFor(models: AgentModels, step: AgentStep): string {
  return models.agentByStep?.[step] ?? models.agent;
}

/** Provider routing for the agent model: no training on our data, and the
 * vendor's own endpoint for Claude. */
export function agentProvider(model: string): Record<string, unknown> {
  return model.startsWith("anthropic/")
    ? { order: ["anthropic"], allow_fallbacks: false, data_collection: "deny" }
    : { data_collection: "deny" };
}
