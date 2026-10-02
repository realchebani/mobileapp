-- EPIC-05 extension for EPIC-13 (owner decision Q5, 2026-10-02): the
-- non-certified estimate also covers garages / parkings (stationnement) and
-- outbuildings (dependance), from the median price of the DVF sales of a
-- single outbuilding ("Dépendance" alone in its mutation, no dwelling, no
-- commercial premises). Their price is per unit (DVF has no surface for
-- most outbuildings), so built_area_m2 is optional for them.
--
-- Additive: existing rows are unchanged. dvf_sources.format_version marks
-- the commune files cleaned before outbuildings were kept (version 1): the
-- Edge Function downloads them again (without ETag) on next use.

alter table public.dvf_sales
  drop constraint dvf_sales_property_type_check,
  add constraint dvf_sales_property_type_check
    check (property_type in ('maison', 'appartement', 'dependance')),
  alter column built_area_m2 drop not null,
  add constraint dvf_sales_dwelling_area_check
    check (property_type = 'dependance' or built_area_m2 is not null);

comment on table public.dvf_sales is
  'Cleaned DVF sales (one dwelling, or one outbuilding alone, per '
  'mutation), cache of dvf_sources.';

alter table public.dvf_sources
  add column format_version smallint not null default 1;

comment on column public.dvf_sources.format_version is
  'Cleaning version of the cached file: 1 = dwellings only, 2 = dwellings '
  'and single outbuildings.';

alter table public.market_snapshots
  drop constraint market_snapshots_property_type_check,
  add constraint market_snapshots_property_type_check
    check (property_type in ('maison', 'appartement', 'dependance'));
