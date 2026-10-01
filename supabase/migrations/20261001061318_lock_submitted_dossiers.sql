-- Locks dossiers the expert has taken over and tightens the seller tunnel
-- policies of 20260930204431_create_seller_tunnel.sql:
-- - a property (and its child rows) can only be changed while it is a
--   draft or submitted; in_review / certified dossiers are read-only;
-- - a property can only be deleted while it is a draft;
-- - an owner row can only be linked to the signed-in user's own profile;
-- - at most one draft per user.

-- properties ------------------------------------------------------------------

drop policy "Owners can update their properties" on public.properties;
create policy "Owners can update their open properties"
  on public.properties for update
  to authenticated
  using (
    (select auth.uid()) = owner_id and status in ('draft', 'submitted')
  )
  with check (
    (select auth.uid()) = owner_id and status in ('draft', 'submitted')
  );

drop policy "Owners can delete their properties" on public.properties;
create policy "Owners can delete their draft properties"
  on public.properties for delete
  to authenticated
  using ((select auth.uid()) = owner_id and status = 'draft');

create unique index properties_one_draft_per_owner
  on public.properties (owner_id)
  where status = 'draft';

-- child tables ------------------------------------------------------------------

do $$
declare
  child text;
  open_parent constant text :=
    'exists (select 1 from public.properties p '
    'where p.id = property_id and p.owner_id = (select auth.uid()) '
    'and p.status in (''draft'', ''submitted''))';
  own_profile text;
begin
  foreach child in array array[
    'property_owners', 'property_parcels', 'previous_estimates', 'rooms',
    'lifestyle_items', 'property_documents'
  ] loop
    own_profile := case
      when child = 'property_owners'
        then ' and (profile_id is null or profile_id = (select auth.uid()))'
      else ''
    end;

    execute format('drop policy %I on public.%I',
      'Owners can add ' || child || ' to their properties', child);
    execute format('drop policy %I on public.%I',
      'Owners can update the ' || child || ' of their properties', child);
    execute format('drop policy %I on public.%I',
      'Owners can delete the ' || child || ' of their properties', child);

    execute format(
      'create policy %I on public.%I for insert to authenticated '
      'with check (%s%s)',
      'Owners can add ' || child || ' to open properties', child,
      open_parent, own_profile
    );
    execute format(
      'create policy %I on public.%I for update to authenticated '
      'using (%s) with check (%s%s)',
      'Owners can update the ' || child || ' of open properties', child,
      open_parent, open_parent, own_profile
    );
    execute format(
      'create policy %I on public.%I for delete to authenticated '
      'using (%s)',
      'Owners can delete the ' || child || ' of open properties', child,
      open_parent
    );
  end loop;
end;
$$;
