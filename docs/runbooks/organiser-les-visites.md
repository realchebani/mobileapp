# Runbook · Organiser les visites (EPIC-09)

Tant qu’il n’existe **ni app acquéreur ni Espace Agences**, l’équipe saisit les demandes de visite, les décisions de l’agent et les comptes rendus depuis le **SQL Editor** du tableau de bord Supabase (projet « Mobileapp »), avec les fonctions `staff_*` de la migration `20261003155915_visites.sql`. Elles ne sont pas appelables depuis l’application (exécution réservée au rôle `postgres` du SQL Editor et à `service_role`) et chacune écrit une ligne dans `staff_audit_log` (acteur `sql_editor`).

**Phase de test** : chaque demande porte `is_test = true` ; les données de démonstration portent en plus `source = 'demo'`. Les visites ne sont visibles que dans la saveur `development` (`SALES_ENABLED`). **Notifications dans l’app uniquement** : l’équipe prévient l’acquéreur elle-même (téléphone), à chaque décision ou annulation (§4).

Règles fixes (constantes de `visit_settings_defaults()`, mêmes valeurs dans l’app : `VisitDefaults`) : cases d’**une heure de 08:00 à 20:00** (heure de Paris), **24 h** de délai de prévenance, **6 semaines** d’horizon, issue d’une visite modifiable **7 jours**, rappel la veille **à partir de 18 h**.

## 1. Les demandes à traiter

```sql
-- Demandes ouvertes, de la plus proche à la plus lointaine
select r.id, r.sale_id, s.formula, r.buyer_label, r.status, r.handled_by,
       r.requalification, r.slot_starts_at at time zone 'Europe/Paris' as creneau,
       r.source, r.responded_at, r.buyer_informed_at
from public.visit_requests r
join public.sales s on s.id = r.sale_id
where r.status in ('pending', 'accepted')
order by r.slot_starts_at;

-- À prévenir : décisions du vendeur pas encore relayées à l’acquéreur
select r.id, r.buyer_label, r.status, r.status_reason, r.cancelled_by,
       r.slot_starts_at at time zone 'Europe/Paris' as creneau, r.responded_at
from public.visit_requests r
where r.buyer_informed_at is null
  and (r.status in ('accepted', 'refused')
       or (r.status = 'cancelled' and r.cancelled_by = 'seller'))
order by coalesce(r.cancelled_at, r.responded_at);
```

Les créneaux ouverts d’une vente, semaine par semaine (le vendeur les règle dans V12) : on ne peut pas appeler `visit_week` depuis le SQL Editor (elle vérifie le vendeur connecté) ; lire directement :

```sql
select weekday, start_minute / 60 as heure from public.visit_availability
where sale_id = '<sale id>' order by 1, 2;
select starts_at at time zone 'Europe/Paris', state from public.visit_slot_overrides
where sale_id = '<sale id>' order by 1;
```

## 2. Saisir une demande de visite

Confidentialité (obligatoire) :
- `buyer_label` = **prénom(s) + initiale du nom** (« Thomas & Léa B. »), jamais le nom complet ; `buyer_initials` = 1 à 3 lettres (« TL ») ;
- **aucune coordonnée** : la base refuse un « @ » ou une suite de chiffres de type téléphone dans le libellé et l’instantané ;
- l’instantané (`buyer_snapshot`, version 1) n’accepte que les clés `v`, `household`, `financing`, `capacity`, `timeline` (≤ 80 caractères), `subscores` (≤ 5 `{label, score, max}`, `0 ≤ score ≤ max ≤ 100`) et `reasons` (≤ 5 textes de ≤ 160 caractères). Jamais de revenus, d’adresse ni de pièce.
- **Adresse exacte du bien** : jamais communiquée à un acquéreur avant une visite acceptée (choix par défaut du plan, Q14) ; l’annonce ne montre que la commune et le quartier.

```sql
select public.staff_create_visit_request(
  p_sale_id => '<sale id>',
  p_slot_starts_at => '2026-10-10 10:00 Europe/Paris',
  p_buyer_label => 'Thomas & Léa B.',
  p_buyer_initials => 'TL',
  p_source => 'staff',                 -- ou 'agency'
  p_flags => '{"pass_visite": true, "budget_validated": true, "search_mandate_signed": true}',
  p_score => 94,
  p_snapshot => '{"v": 1, "household": "Couple, 1 enfant",
    "financing": "Validé par le courtier", "capacity": "Compatible avec votre prix",
    "timeline": "Achat sous 3 mois",
    "subscores": [{"label": "Intérieur", "score": 33, "max": 35},
                  {"label": "Extérieur & trajets", "score": 32, "max": 35},
                  {"label": "Financement", "score": 29, "max": 30}],
    "reasons": ["Garage avec coin atelier", "École primaire à pied"]}'
);
```

- Le créneau doit être **ouvert par le vendeur**, à plus de 24 h et dans l’horizon ; sinon `slot_closed` (forcer avec `p_outside_slots => true` si le vendeur l’a demandé par téléphone).
- La vente doit être **publiée** (`sale_closed` sinon) et le compte du vendeur actif (`account_deactivated`).
- Le Premium : la demande arrive « Requalification en cours » (`requalification = 'pending'`) ; le vendeur peut l’accepter à tout moment.
- **L’Expert** : la demande est gérée par l’agent (`handled_by = 'agent'`), le vendeur la voit en lecture seule. Pour une visite organisée directement par l’agent : `p_status => 'accepted'` (notification « Visite programmée par votre agent »).
- Rejouable : passer `p_request_id => '<uuid>'` pour qu’un second appel ne crée pas de doublon.

Le vendeur reçoit la notification « Nouvelle demande de visite » (ouvre la demande).

## 3. Requalifier (Le Premium) et décider pour l’agent

```sql
-- Après l’appel de l’acquéreur (Le Premium)
select public.staff_requalify_visit_request('<request id>',
  '{"budget_validated": true, "pass_visite": true}');

-- Décision de l’agent (L’Expert) ou à la demande du vendeur
select public.staff_respond_visit_request('<request id>', 'accept');
select public.staff_respond_visit_request('<request id>', 'refuse', 'not_available');
-- motifs : not_available, profile_not_matching, other
```

Accepter une demande **refuse automatiquement les autres demandes en attente du vendeur sur le même créneau** (`slot_taken`) — à prévenir aussi. Un vendeur ne peut avoir qu’une visite acceptée par créneau, tous biens confondus.

## 4. Prévenir l’acquéreur

Après chaque décision (acceptation, refus, annulation par le vendeur), appeler l’acquéreur :
- **acceptée** : confirmer le créneau ; l’adresse exacte peut lui être donnée à ce moment-là (Q14, option recommandée, en attente du porteur de projet) ;
- **refusée** : message **neutre** (« Le vendeur n’est pas disponible sur ce créneau »), **jamais le motif** saisi par le vendeur ni sa note privée ;
- **annulée par le vendeur** : proposer un autre créneau.

Puis marquer la demande :

```sql
select public.staff_mark_buyer_informed('<request id>');
```

## 5. Annulations et issue d’une visite

```sql
-- L’acquéreur ou l’agent annule (notification « Visite annulée … »)
select public.staff_cancel_visit('<request id>', 'buyer');
select public.staff_cancel_visit('<request id>', 'agent', 'other');

-- Issue d’une visite passée (le vendeur peut aussi le faire pendant 7 jours)
select public.staff_set_visit_outcome('<request id>', 'no_show');  -- ou 'done'
```

Un retrait de la vente annule ses visites à venir (`status_reason = 'sale_withdrawn'`) : prévenir les acquéreurs concernés.

## 6. Publier un compte rendu (V14)

Visites L’Expert et, en Premium, débrief après l’appel de l’acquéreur (pas de compte rendu en L’Essentiel : le vendeur garde sa note privée).

```sql
select public.staff_publish_visit_report('<request id>', '{
  "author_kind": "agent",
  "author_label": "Camille, agence partenaire",
  "agency_label": "Agence Val d’Yzeron",
  "interest_level": "high",
  "liked": ["Luminosité du séjour", "Garage atelier", "Jardin clos"],
  "concerns": ["Salle de bain à rafraîchir"],
  "next_steps": ["contre_visite", "offre_annoncee"],
  "comment": "Les acquéreurs souhaitent une contre-visite en semaine."
}');
```

- `author_kind` : `agent` ou `team` (« Équipe Realesty » par défaut) ; `interest_level` : `low`, `medium`, `high` ; `next_steps` ⊂ `contre_visite`, `offre_annoncee`, `reflexion`, `pas_interesse` ; ≤ 8 points appréciés / freins de ≤ 120 caractères ; commentaire ≤ 1 000.
- Rappeler la fonction remplace le compte rendu (republication). Le vendeur reçoit « Compte rendu de visite disponible ».

## 7. Rappels et ménage (pg_cron)

La tâche horaire `visits-housekeeping` (`7 * * * *`) appelle `visits_housekeeping()` : demandes en attente dont le créneau est passé → `expired` ; visites acceptées terminées → `done` ; exceptions de créneaux passées supprimées ; **à partir de 18 h (Paris)**, notification « Visite demain » des visites acceptées du lendemain (une seule fois, `reminded_at`). À la main :

```sql
select public.visits_housekeeping();
select jobname, schedule, active from cron.job where jobname = 'visits-housekeeping';
select status, return_message, start_time from cron.job_run_details
where jobid = (select jobid from cron.job where jobname = 'visits-housekeeping')
order by start_time desc limit 5;
```

## 8. Démonstration

Sur une vente **de test publiée** : 3 demandes de la maquette (Thomas & Léa B. 94 %, Nadia K. 88 %, Paul & Inès R. 81 %) sur les 3 prochains créneaux ouverts (à défaut les jours suivants à 10 h, 11 h et 14 h), plus une visite passée réalisée avec son compte rendu publié (V14).

```sql
select public.staff_seed_demo_visits('<sale id>');   -- renvoie 4
select public.staff_purge_demo_visits('<sale id>');  -- supprime demandes, comptes rendus, notes et notifications de démo
```
