-- EPIC-14 · agent_step_stats is a read-only report: service_role keeps
-- SELECT only (the default privileges had granted it every privilege).
revoke all on table public.agent_step_stats from service_role;
grant select on table public.agent_step_stats to service_role;
