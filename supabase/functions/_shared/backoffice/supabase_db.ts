// BoFilesDb on Supabase: the checks run as the CALLER (bo_check_files,
// bo_prepare_report_upload: role, MFA, dossier access, journal); signing
// uses the service role, only for the locations those functions returned.

import { createClient, type SupabaseClient } from "npm:@supabase/supabase-js@2";
import {
  type BoFilesDb,
  type FileItem,
  type FileLocation,
  RpcError,
  type UploadTarget,
} from "./handler.ts";

const noSession = { persistSession: false, autoRefreshToken: false };

/** The data access of a signed-in caller, or null without a valid JWT. */
export async function callerBoFilesDb(request: Request): Promise<BoFilesDb | null> {
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
  return new SupabaseBoFilesDb(caller, service);
}

function rpcError(error: { code?: string; message: string }): RpcError {
  return new RpcError(error.code ?? "", error.message);
}

export class SupabaseBoFilesDb implements BoFilesDb {
  constructor(
    private readonly caller: SupabaseClient,
    private readonly service: SupabaseClient,
  ) {}

  async checkFiles(propertyId: string, items: FileItem[]): Promise<FileLocation[]> {
    const { data, error } = await this.caller.rpc("bo_check_files", {
      p_property_id: propertyId,
      p_items: items,
    });
    if (error) throw rpcError(error);
    return data as FileLocation[];
  }

  async prepareUpload(propertyId: string): Promise<UploadTarget> {
    const { data, error } = await this.caller.rpc("bo_prepare_report_upload", {
      p_property_id: propertyId,
    });
    if (error) throw rpcError(error);
    return data as UploadTarget;
  }

  async signDownload(bucket: string, path: string, seconds: number): Promise<string> {
    const { data, error } = await this.service.storage.from(bucket)
      .createSignedUrl(path, seconds);
    if (error || !data) throw new Error(`sign: ${error?.message}`);
    return data.signedUrl;
  }

  async signUpload(bucket: string, path: string): Promise<{ signedUrl: string; token: string }> {
    const { data, error } = await this.service.storage.from(bucket).createSignedUploadUrl(path);
    if (error || !data) throw new Error(`sign upload: ${error?.message}`);
    return { signedUrl: data.signedUrl, token: data.token };
  }
}
