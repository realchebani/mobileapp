// VisionDb on Supabase. The dossier (room_photos, property_documents,
// properties) and its files are read with the CALLER's JWT, so RLS and the
// Storage policies decide what they may see. The journal (vision_requests)
// and the analysis columns are written with the service role, always
// scoped to the verified caller, through SQL functions that re-check at
// write time that the dossier is still a draft (photos_hardening).

import { createClient, type SupabaseClient } from "npm:@supabase/supabase-js@2";
import type {
  DocumentRow,
  Download,
  PhotoRow,
  RequestUpdate,
  Reservation,
  VisionDb,
  VisionKind,
} from "./db.ts";
import { VISION_LIMITS } from "./db.ts";
import type { PlanReading, RoomPhotoAnalysis } from "./validate.ts";

const BUCKET = "property-documents";

function fail(error: { message: string } | null): void {
  if (error) throw new Error(`db: ${error.message}`);
}

const noSession = { persistSession: false, autoRefreshToken: false };

/** The data access of a signed-in caller, or null without a valid JWT. */
export async function callerVisionDb(request: Request): Promise<VisionDb | null> {
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
  return new SupabaseVisionDb(caller, service, data.user.id);
}

type WithProperty = { property: { status: string } | null };

export class SupabaseVisionDb implements VisionDb {
  constructor(
    private readonly caller: SupabaseClient,
    private readonly service: SupabaseClient,
    private readonly userId: string,
  ) {}

  async photo(id: string): Promise<PhotoRow | null> {
    const { data, error } = await this.caller.from("room_photos")
      .select("id,property_id,storage_path,analysis,property:properties(status)")
      .eq("id", id).maybeSingle();
    fail(error);
    if (!data) return null;
    const row = data as unknown as Omit<PhotoRow, "property_status"> & WithProperty;
    return {
      id: row.id,
      property_id: row.property_id,
      storage_path: row.storage_path,
      analysis: row.analysis,
      property_status: row.property?.status ?? "unknown",
    };
  }

  async document(id: string): Promise<DocumentRow | null> {
    const { data, error } = await this.caller.from("property_documents")
      .select(
        "id,property_id,kind,mime_type,storage_path,extracted,property:properties(status)",
      )
      .eq("id", id).maybeSingle();
    fail(error);
    if (!data) return null;
    const row = data as unknown as Omit<DocumentRow, "property_status"> & WithProperty;
    return {
      id: row.id,
      property_id: row.property_id,
      kind: row.kind,
      mime_type: row.mime_type,
      storage_path: row.storage_path,
      extracted: row.extracted,
      property_status: row.property?.status ?? "unknown",
    };
  }

  async download(path: string, maxBytes: number): Promise<Download> {
    const { data, error } = await this.caller.storage.from(BUCKET).download(path);
    if (error || !data) return "missing";
    if (data.size > maxBytes) return "too_large";
    return new Uint8Array(await data.arrayBuffer());
  }

  async reserve(
    kind: VisionKind,
    propertyId: string,
    targetId: string,
    since: Date,
  ): Promise<Reservation> {
    const { data, error } = await this.service.rpc("vision_reserve_target", {
      p_owner_id: this.userId,
      p_property_id: propertyId,
      p_kind: kind,
      p_target_id: targetId,
      p_since: since.toISOString(),
      p_max: kind === "plan" ? VISION_LIMITS.plansPerDay : VISION_LIMITS.photosPerDay,
      p_busy_seconds: kind === "plan" ? VISION_LIMITS.planBusySeconds : VISION_LIMITS.busySeconds,
    });
    fail(error);
    const row = (data as { request_id: string | null; outcome: string }[] | null)?.[0];
    if (row?.outcome === "busy") return "busy";
    return row?.outcome === "reserved" && row.request_id ? { id: row.request_id } : "quota";
  }

  async finish(requestId: string, update: RequestUpdate): Promise<void> {
    const { error } = await this.service.from("vision_requests").update(update)
      .eq("id", requestId).eq("owner_id", this.userId);
    fail(error);
  }

  async saveAnalysis(photo: PhotoRow, analysis: RoomPhotoAnalysis): Promise<boolean> {
    const { data, error } = await this.service.rpc("vision_save_photo_analysis", {
      p_owner_id: this.userId,
      p_photo_id: photo.id,
      p_analysis: analysis,
    });
    fail(error);
    return data === true;
  }

  async saveReading(document: DocumentRow, reading: PlanReading): Promise<boolean> {
    // Merged with the other keys of `extracted` in the database.
    const { data, error } = await this.service.rpc("vision_save_plan_reading", {
      p_owner_id: this.userId,
      p_document_id: document.id,
      p_reading: reading,
    });
    fail(error);
    return data === true;
  }
}
