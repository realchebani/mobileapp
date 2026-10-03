// PurgeDb on Supabase, with the service role (SQL functions of
// 20261003080523_coffre_fort_compte.sql, Storage API, Auth admin API).

import { createClient, type SupabaseClient } from "npm:@supabase/supabase-js@2";
import type { PurgeDb, StoredFile } from "./purge.ts";

function fail(error: { message: string } | null): void {
  if (error) throw new Error(`db: ${error.message}`);
}

/** The service-role data access of the purge. */
export function servicePurgeDb(): PurgeDb {
  return new SupabasePurgeDb(
    createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
      { auth: { persistSession: false, autoRefreshToken: false } },
    ),
  );
}

export class SupabasePurgeDb implements PurgeDb {
  constructor(private readonly client: SupabaseClient) {}

  async dueAccounts(limit: number): Promise<string[]> {
    const { data, error } = await this.client.rpc("account_purge_due", { p_limit: limit });
    fail(error);
    return ((data ?? []) as { user_id: string }[]).map((row) => row.user_id);
  }

  async begin(userId: string): Promise<boolean> {
    const { data, error } = await this.client.rpc("account_purge_begin", {
      p_user_id: userId,
    });
    fail(error);
    return data === true;
  }

  async check(userId: string): Promise<boolean> {
    const { data, error } = await this.client.rpc("account_purge_check", {
      p_user_id: userId,
    });
    fail(error);
    return data === true;
  }

  async files(userId: string): Promise<StoredFile[]> {
    const { data, error } = await this.client.rpc("account_purge_files", {
      p_user_id: userId,
    });
    fail(error);
    return ((data ?? []) as { bucket_id: string; name: string }[]).map((row) => ({
      bucket: row.bucket_id,
      name: row.name,
    }));
  }

  async removeFiles(bucket: string, names: string[]): Promise<void> {
    const { error } = await this.client.storage.from(bucket).remove(names);
    fail(error);
  }

  async deleteUser(userId: string): Promise<void> {
    const { error } = await this.client.auth.admin.deleteUser(userId);
    if (error && error.status !== 404) fail(error);
  }

  async finish(userId: string, filesCount: number): Promise<boolean> {
    const { data, error } = await this.client.rpc("account_purge_finish", {
      p_user_id: userId,
      p_files_count: filesCount,
    });
    fail(error);
    return data === true;
  }
}
