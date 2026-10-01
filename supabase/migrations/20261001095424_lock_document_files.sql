-- Locks the document files of dossiers the expert has taken over, like
-- 20261001061318_lock_submitted_dossiers.sql locks their rows: in the
-- property-documents bucket (<owner id>/<property id>/<file>), files can only
-- be added, replaced or deleted while their property (2nd path segment)
-- belongs to the user and is a draft or submitted. Reading is unchanged.

drop policy "Owners can upload their property documents" on storage.objects;
drop policy "Owners can update their property documents" on storage.objects;
drop policy "Owners can delete their property documents" on storage.objects;

create policy "Owners can upload documents of their open properties"
  on storage.objects for insert
  to authenticated
  with check (
    bucket_id = 'property-documents'
    and (storage.foldername(objects.name))[1] = (select auth.uid())::text
    and exists (
      select 1 from public.properties p
      where p.id::text = (storage.foldername(objects.name))[2]
        and p.owner_id = (select auth.uid())
        and p.status in ('draft', 'submitted')
    )
  );

create policy "Owners can update documents of their open properties"
  on storage.objects for update
  to authenticated
  using (
    bucket_id = 'property-documents'
    and (storage.foldername(objects.name))[1] = (select auth.uid())::text
    and exists (
      select 1 from public.properties p
      where p.id::text = (storage.foldername(objects.name))[2]
        and p.owner_id = (select auth.uid())
        and p.status in ('draft', 'submitted')
    )
  )
  with check (
    bucket_id = 'property-documents'
    and (storage.foldername(objects.name))[1] = (select auth.uid())::text
    and exists (
      select 1 from public.properties p
      where p.id::text = (storage.foldername(objects.name))[2]
        and p.owner_id = (select auth.uid())
        and p.status in ('draft', 'submitted')
    )
  );

create policy "Owners can delete documents of their open properties"
  on storage.objects for delete
  to authenticated
  using (
    bucket_id = 'property-documents'
    and (storage.foldername(objects.name))[1] = (select auth.uid())::text
    and exists (
      select 1 from public.properties p
      where p.id::text = (storage.foldername(objects.name))[2]
        and p.owner_id = (select auth.uid())
        and p.status in ('draft', 'submitted')
    )
  );
