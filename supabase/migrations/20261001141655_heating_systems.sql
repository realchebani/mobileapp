-- V4b · the seller can declare several heating systems (US-04.10), e.g.
-- radiateurs électriques + poêle à bois. properties.heating_systems replaces
-- the single "énergie principale" (heating_energy) in the tunnel:
-- - the codes of heating_energy are kept as they are, so the backfill is a
--   plain copy (with its provenance);
-- - heating_energy is left in place (no longer written by the app) so that
--   nothing is lost; it can be dropped once no client reads it.
-- The heat pump details (heat_pump_type / heat_pump_year) are asked when
-- 'pac' is among the selected systems.

alter table public.properties
  add column heating_systems text[] not null default '{}'
    check (heating_systems <@ array[
      'electricite', 'pac', 'gaz', 'fioul', 'bois', 'granules', 'cheminee',
      'reseau_chaleur', 'solaire', 'autre'
    ]::text[]);

comment on column public.properties.heating_systems is
  'V4b · heating systems (multiple choice): electricite (radiateurs '
  'électriques), pac, gaz, fioul, bois (chaudière / poêle à bois), granules '
  '(poêle à granulés), cheminee (cheminée / insert), reseau_chaleur, '
  'solaire, autre.';

comment on column public.properties.heating_energy is
  'Legacy single main heating energy, superseded by heating_systems '
  '(20261001141655_heating_systems.sql); no longer written by the app.';

update public.properties
set
  heating_systems = array[heating_energy],
  provenance = case
    when provenance ? 'heating_energy'
      then provenance
        || jsonb_build_object('heating_systems', provenance -> 'heating_energy')
    else provenance
  end
where heating_energy is not null;

-- properties grants updates column by column.
grant update (heating_systems) on table public.properties to authenticated;
