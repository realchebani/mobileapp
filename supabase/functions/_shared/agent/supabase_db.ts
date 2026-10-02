// AgentDb on Supabase. The dossier (properties, lifestyle_items) is read
// with the CALLER's JWT, so RLS decides what they may see; the handlers
// check it is their draft before anything is written. The journal
// (agent_sessions, agent_turns) is read-only for clients: it is written
// with the service role, always scoped to the verified caller (owner_id).

import { createClient, type SupabaseClient } from "npm:@supabase/supabase-js@2";
import {
  type AgentDb,
  type DailyUsage,
  LIMITS,
  PROPERTY_COLUMNS,
  type PropertyRow,
  type SessionRow,
  type TurnReservation,
  type TurnRow,
  type TurnUpdate,
} from "./db.ts";
import type { AgentStep } from "./schema.ts";

const TURN_COLUMNS = "id,session_id,transcript,reply_fr,extracted,tts_ms,cost_usd";

function fail(error: { message: string } | null): void {
  if (error) throw new Error(`db: ${error.message}`);
}

const noSession = { persistSession: false, autoRefreshToken: false };

/** The data access of a signed-in caller, or null without a valid JWT. */
export async function callerDb(request: Request): Promise<AgentDb | null> {
  const authorization = request.headers.get("Authorization");
  if (!authorization?.startsWith("Bearer ")) return null;
  const url = Deno.env.get("SUPABASE_URL")!;
  const caller = createClient(url, Deno.env.get("SUPABASE_ANON_KEY")!, {
    global: { headers: { Authorization: authorization } },
    auth: noSession,
  });
  const { data, error } = await caller.auth.getUser(authorization.slice(7));
  if (error || !data.user) return null;
  const service = createClient(url, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
    auth: noSession,
  });
  return new SupabaseAgentDb(caller, service, data.user.id);
}

export class SupabaseAgentDb implements AgentDb {
  constructor(
    private readonly caller: SupabaseClient,
    private readonly service: SupabaseClient,
    private readonly userId: string,
  ) {}

  async property(id: string): Promise<PropertyRow | null> {
    const { data, error } = await this.caller.from("properties")
      .select(PROPERTY_COLUMNS).eq("id", id).maybeSingle();
    fail(error);
    return data as PropertyRow | null;
  }

  async lifestyleLabels(propertyId: string) {
    const { data, error } = await this.caller.from("lifestyle_items")
      .select("kind,label").eq("property_id", propertyId);
    fail(error);
    const rows = (data ?? []) as { kind: string; label: string }[];
    return {
      asset: rows.filter((r) => r.kind === "asset").map((r) => r.label),
      watch_point: rows.filter((r) => r.kind === "watch_point").map((r) => r.label),
    };
  }

  async session(propertyId: string, step: AgentStep): Promise<SessionRow> {
    for (let attempt = 0; attempt < 2; attempt++) {
      const { data, error } = await this.service.from("agent_sessions")
        .select("id,property_id,step").eq("property_id", propertyId)
        .eq("owner_id", this.userId).eq("step", step).eq("status", "active")
        .maybeSingle();
      fail(error);
      if (data) return data as SessionRow;
      const inserted = await this.service.from("agent_sessions")
        .insert({ property_id: propertyId, owner_id: this.userId, step })
        .select("id,property_id,step").single();
      // A concurrent request created it (unique active session): reread.
      if (inserted.error?.code === "23505") continue;
      fail(inserted.error);
      return inserted.data as SessionRow;
    }
    throw new Error("db: no session");
  }

  async updateSession(
    id: string,
    patch: { next_field?: string | null; status?: "active" | "done" },
  ): Promise<void> {
    const { error } = await this.service.from("agent_sessions").update(patch)
      .eq("id", id).eq("owner_id", this.userId);
    fail(error);
  }

  async turn(id: string) {
    const { data, error } = await this.service.from("agent_turns")
      .select(`${TURN_COLUMNS},session:agent_sessions(id,property_id,step)`)
      .eq("id", id).eq("owner_id", this.userId).maybeSingle();
    fail(error);
    return data as (TurnRow & { session: SessionRow }) | null;
  }

  async recentTurns(sessionId: string, limit: number): Promise<TurnRow[]> {
    const { data, error } = await this.service.from("agent_turns")
      .select(TURN_COLUMNS).eq("session_id", sessionId).eq("owner_id", this.userId)
      .order("created_at", { ascending: false }).limit(limit);
    fail(error);
    return ((data ?? []) as TurnRow[]).reverse();
  }

  async reserveTurn(turn: TurnReservation): Promise<TurnRow | null> {
    const { data, error } = await this.service.rpc("agent_reserve_turn", {
      p_owner_id: this.userId,
      p_session_id: turn.session_id,
      p_transcript: turn.transcript,
      p_audio_seconds: turn.audio_seconds,
      p_since: turn.since.toISOString(),
      p_max_turns: LIMITS.turnsPerDay,
      p_max_audio_seconds: LIMITS.audioSecondsPerDay,
    });
    fail(error);
    if (typeof data !== "string") return null;
    return {
      id: data,
      session_id: turn.session_id,
      transcript: turn.transcript,
      reply_fr: null,
      extracted: null,
      tts_ms: null,
      cost_usd: null,
    };
  }

  async claimTurn(id: string): Promise<boolean> {
    // Conditional UPDATE … RETURNING: one caller wins.
    const { data, error } = await this.service.from("agent_turns")
      .update({ error: "in_progress" })
      .eq("id", id).eq("owner_id", this.userId)
      .is("reply_fr", null).is("extracted", null)
      .or("error.is.null,error.eq.agent_failed")
      .select("id");
    fail(error);
    return (data ?? []).length === 1;
  }

  async claimSpeech(id: string): Promise<boolean> {
    const { data, error } = await this.service.from("agent_turns")
      .update({ tts_ms: 0 })
      .eq("id", id).eq("owner_id", this.userId)
      .is("tts_ms", null).not("reply_fr", "is", null)
      .select("id");
    fail(error);
    return (data ?? []).length === 1;
  }

  async updateTurn(id: string, patch: TurnUpdate): Promise<void> {
    const { error } = await this.service.from("agent_turns").update(patch)
      .eq("id", id).eq("owner_id", this.userId);
    fail(error);
  }

  async usageSince(since: Date): Promise<DailyUsage> {
    const { data, error } = await this.service.from("agent_turns")
      .select("audio_seconds").eq("owner_id", this.userId)
      .gte("created_at", since.toISOString());
    fail(error);
    const rows = (data ?? []) as { audio_seconds: number | null }[];
    return {
      turns: rows.length,
      audioSeconds: rows.reduce((sum, r) => sum + Number(r.audio_seconds ?? 0), 0),
    };
  }
}
