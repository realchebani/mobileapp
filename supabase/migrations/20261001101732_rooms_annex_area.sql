-- V5c distinguishes the living area (surface habitable) from the annexes
-- (garage, cellier, sous-sol, buanderie…):
-- - rooms.is_annex marks a room that is not part of the living area (an
--   annex is never a pièce principale);
-- - properties.annex_area_m2 stores the total of the annexes, next to
--   living_area_m2 (the total of the other rooms).

alter table public.rooms
  add column is_annex boolean not null default false,
  add constraint rooms_annex_not_main check (not (is_annex and is_main));

alter table public.properties
  add column annex_area_m2 numeric(7, 2) check (annex_area_m2 >= 0);

-- rooms keeps its table-level grant (select, insert, update, delete), which
-- covers the new column; properties grants updates column by column.
grant update (annex_area_m2) on table public.properties to authenticated;
