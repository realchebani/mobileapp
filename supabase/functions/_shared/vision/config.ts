// Models of the vision AI (EPIC-15), configurable with Supabase secrets (no
// app release needed). Default = the cheapest multimodal model of the voice
// benchmark (owner decision 2026-10-02: cheapest by default during the test
// phase), to reassess on real photos.

export interface VisionModels {
  /** `OPENROUTER_MODEL_VISION`: room photos. */
  room: string;
  /** `OPENROUTER_MODEL_PLAN` (else the room model): floor plans. */
  plan: string;
}

export const DEFAULT_VISION_MODEL = "google/gemini-3.5-flash-lite";

type Env = { get(name: string): string | undefined };

function pick(env: Env, name: string): string | undefined {
  const value = env.get(name)?.trim();
  return value ? value : undefined;
}

export function visionModels(env: Env): VisionModels {
  const room = pick(env, "OPENROUTER_MODEL_VISION") ?? DEFAULT_VISION_MODEL;
  return { room, plan: pick(env, "OPENROUTER_MODEL_PLAN") ?? room };
}

/** Provider routing: never a provider that keeps or trains on the images. */
export const VISION_PROVIDER = { data_collection: "deny" };
