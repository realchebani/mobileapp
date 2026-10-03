// purge-accounts: see ../_shared/account/purge.ts (handlePurgeAccounts).
// Deployed with --no-verify-jwt: pg_cron calls it with the shared secret
// PURGE_ACCOUNTS_SECRET in the x-purge-secret header, not with a JWT.

import { handlePurgeAccounts } from "../_shared/account/purge.ts";
import { servicePurgeDb } from "../_shared/account/supabase_db.ts";

Deno.serve((request) =>
  handlePurgeAccounts(request, {
    secret: Deno.env.get("PURGE_ACCOUNTS_SECRET"),
    db: servicePurgeDb,
  })
);
