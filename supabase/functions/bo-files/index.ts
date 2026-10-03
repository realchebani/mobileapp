// bo-files: see ../_shared/backoffice/handler.ts (handleBoFiles).
// Checks with the caller's JWT (bo_check_files); signs with the service role.

import { handleBoFiles, parseOrigins } from "../_shared/backoffice/handler.ts";
import { callerBoFilesDb } from "../_shared/backoffice/supabase_db.ts";

const allowedOrigins = parseOrigins(Deno.env.get("BO_ALLOWED_ORIGINS"));

Deno.serve(async (request) =>
  handleBoFiles(request, {
    db: request.method === "POST" ? await callerBoFilesDb(request) : null,
    allowedOrigins,
  })
);
