// AgentDb on Supabase with the CALLER's JWT: every query goes through RLS
// (owner only, writes only while the property is a draft).

import { createClient, type SupabaseClient } from "npm:@supabase/supabase-js@2";
import {
  type AgentDb,
  type DailyUsage,
  PROPERTY_COLUMNS,
  type PropertyRow,
  type SessionRow,
  type TurnInsert,
  type TurnRow,
  type TurnUpdate,
} from "./db.ts";
import type { AgentStep } from "./schema.ts";

const TURN_COLUMNS = "id,session_id,transcript,reply_fr,tts_ms,cost_usd";

function fail(error: { message: string } | null): void {
  if (error) throw new Error(`db: ${error.message}`);
}

/** A client acting as the caller, or null without a bearer token. */
export function callerDb(request: Request): AgentDb | null {
  const authorization = request.headers.get("Authorization");
  if (!authorization?.startsWith("Bearer ")) return null;
  const client = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_ANON_KEY")!,
    {
      global: { headers: { Authorization: authorization } },
      auth: { persistSession: false, autoRefreshToken: false },
    },
  );
  return new SupabaseAgentDb(client);
}

export class SupabaseAgentDb implements AgentDb {
  constructor(private readonly client: SupabaseClient) {}

  async property(id: string): Promise<PropertyRow | null> {
    const { data, error } = await this.client.from("properties")
      .select(PROPERTY_COLUMNS).eq("id", id).maybeSingle();
    fail(error);
    return data as PropertyRow | null;
  }

  async lifestyleLabels(propertyId: string) {
    const { data, error } = await this.client.from("lifestyle_items")
      .select("kind,label").eq("property_id", propertyId);
    fail(error);
    const rows = (data ?? []) as { kind: string; label: string }[];
    return {
      asset: rows.filter((r) => r.kind === "asset").map((r) => r.label),
      watch_point: rows.filter((r) => r.kind === "watch_point").map((r) =>
        r.label
      ),
    };
  }

  async session(propertyId: string, step: AgentStep): Promise<SessionRow> {
    for (let attempt = 0; attempt < 2; attempt++) {
      const { data, error } = await this.client.from("agent_sessions")
        .select("id,property_id,step").eq("property_id", propertyId)
        .eq("step", step).eq("status", "active").maybeSingle();
      fail(error);
      if (data) return data as SessionRow;
      const inserted = await this.client.from("agent_sessions")
        .insert({ property_id: propertyId, step })
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
    const { error } = await this.client.from("agent_sessions").update(patch)
      .eq("id", id);
    fail(error);
  }

  async turn(id: string) {
    const { data, error } = await this.client.from("agent_turns")
      .select(`${TURN_COLUMNS},session:agent_sessions(id,property_id,step)`)
      .eq("id", id).maybeSingle();
    fail(error);
    return data as (TurnRow & { session: SessionRow }) | null;
  }

  async recentTurns(sessionId: string, limit: number): Promise<TurnRow[]> {
    const { data, error } = await this.client.from("agent_turns")
      .select(TURN_COLUMNS).eq("session_id", sessionId)
      .order("created_at", { ascending: false }).limit(limit);
    fail(error);
    return ((data ?? []) as TurnRow[]).reverse();
  }

  async insertTurn(turn: TurnInsert): Promise<TurnRow> {
    const { data, error } = await this.client.from("agent_turns").insert(turn)
      .select(TURN_COLUMNS).single();
    fail(error);
    return data as TurnRow;
  }

  async updateTurn(id: string, patch: TurnUpdate): Promise<void> {
    const { error } = await this.client.from("agent_turns").update(patch)
      .eq("id", id);
    fail(error);
  }

  async usageSince(since: Date): Promise<DailyUsage> {
    const { data, error } = await this.client.from("agent_turns")
      .select("audio_seconds").gte("created_at", since.toISOString());
    fail(error);
    const rows = (data ?? []) as { audio_seconds: number | null }[];
    return {
      turns: rows.length,
      audioSeconds: rows.reduce(
        (sum, r) => sum + Number(r.audio_seconds ?? 0),
        0,
      ),
    };
  }
}
