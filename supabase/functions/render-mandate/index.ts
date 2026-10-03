// render-mandate: see ../_shared/mandate/handler.ts (handleRenderMandate).
// Reads with the caller's JWT (RLS); stores the PDF with the service role.

import { handleRenderMandate } from "../_shared/mandate/handler.ts";
import { callerMandateDb } from "../_shared/mandate/supabase_db.ts";

Deno.serve(async (request) => handleRenderMandate(request, { db: await callerMandateDb(request) }));
