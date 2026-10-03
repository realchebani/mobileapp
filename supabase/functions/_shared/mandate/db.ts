// Data access of render-mandate (interface). The Supabase implementation
// (caller's JWT for everything it reads, service role only to store the
// PDF and its path) is in supabase_db.ts; tests use an in-memory fake.

import type { MandateFacts } from "./template.ts";

/** A mandate the caller can read (RLS), with its sale owner. */
export interface MandateRow {
  id: string;
  sale_id: string;
  owner_id: string;
  document_path: string | null;
  document_sha256: string | null;
}

export interface MandateDb {
  /** The mandate [id] if the caller can read it. */
  mandate(id: string): Promise<MandateRow | null>;

  /** What the PDF shows. */
  facts(mandate: MandateRow): Promise<MandateFacts>;

  /** The drawn signature (PNG) of the mandate, if any. */
  signature(mandate: MandateRow): Promise<Uint8Array | null>;

  /** Stores the PDF at [path] (service role) and records it on the
   * mandate when it has none yet; returns the stored path and hash. */
  store(
    mandate: MandateRow,
    path: string,
    pdf: Uint8Array,
    sha256: string,
  ): Promise<{ path: string; sha256: string }>;
}
