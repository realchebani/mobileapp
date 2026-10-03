# Runbook · Suivre une vente (EPIC-08)

En attendant le back-office web (EPIC-12), l’équipe suit les ventes depuis le **SQL Editor** du tableau de bord Supabase (projet « Mobileapp »), avec les fonctions `staff_*` de la migration `20261003080551_mise_en_vente.sql`. Elles ne sont pas appelables depuis l’application (exécution retirée à `anon` et `authenticated`).

**Phase de test** : chaque vente et chaque mandat portent `is_test = true` ; le mandat est une **signature de test** (case + signature dessinée), son PDF porte le filigrane « SPÉCIMEN — signature de test sans valeur juridique ». **Aucun paiement** n’est demandé dans l’application : les tarifs affichés sont indicatifs et les services sont des **demandes** traitées par l’équipe. Les ventes ne sont visibles que dans la saveur `development` (`SALES_ENABLED`).

## 1. Les ventes en cours

```sql
select s.id, s.formula, s.stage, s.asking_price_eur, s.property_id, s.lot_id,
       s.formula_chosen_at, s.mandate_signed_at, s.published_at, pr.first_name
from public.sales s
left join public.profiles pr on pr.id = s.owner_id
where s.stage <> 'withdrawn'
order by s.created_at desc;
```

Une vente porte sur **un bien** (`property_id`) **ou un lot** (`lot_id`). Un lot « ensemble » ne se vend qu’en entier ; un lot « ensemble ou séparément » se vend en entier **ou** bien par bien (jamais les deux à la fois). Un lot peut être mis en vente dès que son **bien principal** (`property_lots.main_property_id`, à défaut le plus ancien) est certifié.

## 2. Mandats et signatures

```sql
select m.id, m.sale_id, m.formula, m.kind, m.status, m.terms_version,
       m.presentation_price_eur, m.fee_rate, m.document_path, m.signed_at,
       sig.signer_name, sig.method, sig.signature_path, sig.user_agent
from public.mandates m
join public.mandate_signatures sig on sig.mandate_id = m.id
order by m.signed_at desc;
```

- Signature dessinée (`drawn_test`, PNG) ou nom tapé (`typed_test`, `typed_signature`, accessibilité). Le PDF est généré par l’Edge Function `render-mandate` dans le bucket privé `sale-documents` (`<owner id>/<sale id>/mandat-<mandate id>.pdf`, empreinte `document_sha256`). Si `document_path` est vide, le vendeur le régénère en ouvrant « Voir le mandat (PDF) ».
- La signature dessinée est dans `mandate-signatures` (`<owner id>/<sale id>/<mandate id>.png`).
- Co-propriétaires : ils « signeront hors de l’application ». Une fois leur signature recueillie :

```sql
select public.staff_record_offline_signature(
  '<mandate id>', '<property_owner id>', 'Marc Durand'
);
```

## 3. Vérifier une identité (obligatoire avant le mandat L’Expert)

Dans le back-office (EPIC-12) : onglet « Synthèse » du dossier, bouton « Identité vérifiée » de chaque propriétaire (admin, expert). Repli SQL :

La pièce d’identité est un document `piece_identite` du dossier (bien principal pour un lot). Après contrôle :

```sql
select id, first_name, last_name, identity_verified_at
from public.property_owners where property_id = '<property id>' order by position;

select public.staff_verify_identity('<property_owner id>');
```

Le vendeur reçoit la notification « Identité vérifiée » (ouvre sa vente si elle existe).

## 4. Demandes de services (rappel Premium, shooting, diagnostics)

```sql
select r.id, r.sale_id, r.kind, r.status, r.diagnostics, r.preferred_slots,
       r.scheduled_at, r.price_eur_ttc, r.created_at
from public.sale_requests r
where r.status in ('requested', 'scheduled')
order by r.created_at;
```

- `premium_setup` : rappeler le vendeur pour mettre en place Le Premium (aucun prélèvement dans l’app) ;
- `shooting_photo` / `shooting_photo_video` : jusqu’à 3 créneaux souhaités (`preferred_slots`, 10 h / 14 h des 3 jours ouvrés suivants) ;
- Tarifs indicatifs (`sale_service_price`) : rappel Premium 299 € (+ 99 €/mois), photographe 200 €, photo + vidéo 350 €, diagnostics **sur devis** (`price_eur_ttc` vide).
- `diagnostics` : liste présélectionnée par des règles explicites (DPE + ERP toujours, électricité / gaz > 15 ans, amiante avant 1997, plomb avant 1949), modifiable par le vendeur.

```sql
-- planifier (notification « Rendez-vous confirmé » avec la date)
select public.staff_update_sale_request('<request id>', 'scheduled', '2026-10-06 14:00+02');
-- clore / annuler
select public.staff_update_sale_request('<request id>', 'done');
select public.staff_update_sale_request('<request id>', 'cancelled', null, 'Motif interne');
```

## 5. Annonces

L’Essentiel et Le Premium : le vendeur publie lui-même (≥ 5 photos, titre, description, prix). L’Expert : l’agent (l’équipe en v1) prépare l’annonce puis la publie :

```sql
select public.staff_publish_expert_sale('<sale id>');
```

Photos d’annonce : `listing_photos` (la première par `sort_order` est la couverture), fichiers dans le bucket privé `listing-media` (`<owner id>/<sale id>/<photo id>.jpg`). Elles sont **copiées** depuis les photos du dossier (toutes, y compris celles où une personne est visible : choix du porteur de projet) ; la pièce d’identité et les autres documents ne sont jamais copiés. 40 photos au plus par annonce.

## 6. Retrait

Le vendeur retire sa vente depuis la carte « Ma vente » : annonce retirée, mandat `terminated`, demandes ouvertes annulées, photos d’annonce conservées. Un mandat signé n’est résiliable qu’après **30 jours** (`mandates.minimum_days`) ; pendant les tests, l’équipe peut retirer une vente à tout moment :

```sql
select public.staff_withdraw_sale('<sale id>', 'Fin de test');
```

L’équipe peut vérifier :

```sql
select id, stage, withdrawn_at, withdraw_reason from public.sales
where stage = 'withdrawn' order by withdrawn_at desc;
```

## 7. Stockage

Suivre l’espace (offre gratuite 1 Go) :

```sql
select bucket_id, count(*), pg_size_pretty(sum((metadata ->> 'size')::bigint))
from storage.objects
where bucket_id in ('listing-media', 'mandate-signatures', 'sale-documents')
group by 1;
```

## 8. Visites (EPIC-09)

Créneaux, demandes de visite, décisions de l’agent, comptes rendus et démonstration : runbook [Organiser les visites](organiser-les-visites.md). Un retrait de la vente annule ses visites à venir (prévenir les acquéreurs).
