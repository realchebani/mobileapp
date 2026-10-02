// plan-reader: see ../_shared/vision/handlers.ts (handlePlanReader). Uses
// the caller's JWT (RLS); the OpenRouter key and the model come from
// Supabase secrets (OPENROUTER_API_KEY, OPENROUTER_MODEL_PLAN, else
// OPENROUTER_MODEL_VISION).

import { OpenRouterClient } from "../_shared/openrouter/client.ts";
import { visionModels } from "../_shared/vision/config.ts";
import { handlePlanReader } from "../_shared/vision/handlers.ts";
import { callerVisionDb } from "../_shared/vision/supabase_db.ts";

Deno.serve(async (request) =>
  handlePlanReader(request, {
    db: await callerVisionDb(request),
    openrouter: new OpenRouterClient({
      apiKey: Deno.env.get("OPENROUTER_API_KEY") ?? "",
      timeoutMs: 60_000,
    }),
    models: visionModels(Deno.env),
  })
);
