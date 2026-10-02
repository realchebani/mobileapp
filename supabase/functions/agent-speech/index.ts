// agent-speech: see ../_shared/agent/handlers.ts (handleSpeech). Uses the caller's JWT
// (RLS); the OpenRouter key and models come from Supabase secrets.

import { OpenRouterClient } from "../_shared/openrouter/client.ts";
import { agentModels } from "../_shared/agent/config.ts";
import { handleSpeech } from "../_shared/agent/handlers.ts";
import { callerDb } from "../_shared/agent/supabase_db.ts";

Deno.serve(async (request) =>
  handleSpeech(request, {
    db: await callerDb(request),
    openrouter: new OpenRouterClient({
      apiKey: Deno.env.get("OPENROUTER_API_KEY") ?? "",
      timeoutMs: 45_000,
    }),
    models: agentModels(Deno.env),
  })
);
