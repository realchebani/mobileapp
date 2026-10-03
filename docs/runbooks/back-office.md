# Runbook · Back-office expert (EPIC-12)

Application web interne (Flutter web, dossier `backoffice/`) qui permet à l’équipe d’examiner et de certifier les dossiers envoyés, sans accès direct à la base. Plan : [Back-office expert](../plans/2026-10-03-back-office-expert.md). Migration : `supabase/migrations/20261003140416_back_office.sql`. Fichiers : Edge Function `bo-files`.

## 1. Principe de sécurité

- Le navigateur n’a que la **clé publishable**. Toutes les lectures et écritures passent par les fonctions SQL `bo_*` (`security definer`), qui vérifient à chaque appel :
  1. que l’utilisateur est un membre **actif** de `staff_members` (désactivation immédiate) ;
  2. que la session a passé la **double authentification** (JWT `aal = aal2`, code TOTP) ;
  3. le rôle (`admin`, `expert`, `partner_expert`) et l’accès au dossier (un partenaire ne voit que les dossiers qui lui sont **attribués**) ;
  4. puis journalisent l’action dans `staff_audit_log` (ajout seul).
- Les tables du vendeur gardent exactement leurs politiques RLS : un membre de l’équipe qui lirait `properties` directement ne voit **rien**.
- Les fichiers (documents, photos, rapports PDF) ne sont jamais servis par une politique Storage : `bo-files` vérifie la demande avec le JWT de l’appelant (`bo_check_files`), puis signe une URL de **5 minutes** avec le service role. Les **pièces d’identité sont refusées aux partenaires**.
- Erreurs renvoyées par les `bo_*` : `not_authenticated`, `not_staff`, `mfa_required`, `forbidden` (42501), `dossier_not_found`, `document_not_found`, `owner_not_found`, `member_not_found`, `user_not_found`, `draft_not_found`, `file_not_found` (P0002), `draft_conflict` (40001), `draft_submitted`, `dossier_closed`, `not_submitted`, `not_certified`, `draft_not_submitted` (55000), `draft_invalid` (22023, détail = liste des erreurs), `identity_document_forbidden`, `cannot_deactivate_self`, `cannot_demote_self` (42501).

## 2. Rôles

| | admin | expert | partner_expert |
|---|---|---|---|
| File des dossiers | tous les dossiers envoyés | tous | **attribués seulement** |
| Propriétaires | noms, téléphone, e-mail | idem | **initiales + commune** |
| Pièces d’identité | ✔ | ✔ | ✘ (liste et fichiers) |
| Autres documents : vérifier / refuser | ✔ | ✔ | ✔ |
| Prendre en charge (`bo_start_review`) | ✔ (s’attribue un dossier libre) | ✔ (idem) | dossiers attribués |
| Rédiger l’avis de valeur | ✔ | ✔ | ✔ |
| Certifier | ✔ | ✔ | ✘ : **soumet pour validation** |
| Identité vérifiée (EPIC-08) | ✔ | ✔ | ✘ |
| Attribuer, équipe, journal complet | ✔ | ✘ (ses propres actions) | ✘ (ses propres actions) |

Signataire de l’avis de valeur : `expert_user_id` du brouillon s’il est renseigné, sinon le partenaire qui a soumis le brouillon, sinon la personne qui certifie (nom et initiales repris de `staff_members`).

## 3. Premier administrateur (à faire une fois, par le porteur de projet)

Aucun compte d’administrateur n’est créé automatiquement.

1. Se connecter une fois au back-office (ou à l’app) avec l’adresse choisie : le lien magique crée l’utilisateur Supabase.
2. Dans le **SQL Editor** du tableau de bord (rôle `postgres`) :

```sql
insert into public.staff_members (user_id, role, display_name, initials)
select id, 'admin', 'Prénom N.', 'PN'
from auth.users where lower(email) = lower('<adresse e-mail>')
on conflict (user_id) do update
  set role = 'admin', active = true, deactivated_at = null;
```

3. Se reconnecter au back-office : l’écran « Double authentification » demande d’enrôler une application TOTP (Google Authenticator, 1Password, Authy…) en scannant le QR code, puis le code à 6 chiffres.

Ensuite, les autres membres s’ajoutent depuis l’écran **Équipe** (admin) : la personne se connecte une première fois (lien magique), puis l’admin saisit son e-mail, son rôle, son nom affiché au vendeur (« Julien M. ») et ses initiales (« JM »), et l’organisation pour un partenaire.

Avant d’inviter un **partenaire externe** : accord de confidentialité / sous-traitance RGPD signé, et SMTP personnalisé (Brevo, backlog) — le fournisseur d’e-mails par défaut n’envoie de liens qu’aux membres de l’organisation Supabase.

## 4. Gérer les accès en SQL (repli)

```sql
-- Membres
select m.*, u.email from public.staff_members m join auth.users u on u.id = m.user_id;

-- Retirer un accès immédiatement (et rendre ses dossiers à la file)
update public.staff_members set active = false, deactivated_at = now() where user_id = '<user id>';
update public.dossier_assignments set revoked_at = now()
where expert_user_id = '<user id>' and revoked_at is null;

-- Attributions en cours
select a.property_id, m.display_name, a.assigned_at
from public.dossier_assignments a join public.staff_members m on m.user_id = a.expert_user_id
where a.revoked_at is null;

-- Un membre a perdu son téléphone (TOTP) : supprimer son facteur ; il en enrôlera un nouveau
select id, factor_type, status, created_at from auth.mfa_factors where user_id = '<user id>';
delete from auth.mfa_factors where id = '<factor id>';
```

## 5. Journal d’audit

`staff_audit_log` : une ligne par action (`dossier_opened`, `file_signed`, `review_started`, `assigned`, `unassigned`, `draft_saved`, `submitted_for_approval`, `draft_returned`, `certified`, `report_upload_signed`, `report_attached`, `document_verified`, `document_rejected`, `identity_verified`, `member_added`, `member_updated`, `member_deactivated`). Les fonctions `staff_*` des runbooks écrivent aussi une ligne, avec `actor_role = 'sql_editor'`.

Le journal est **en ajout seul** : un déclencheur refuse toute modification ou suppression. Conservation : illimitée pendant la phase de test (Q10, choix par défaut). Purge exceptionnelle (SQL Editor uniquement) :

```sql
begin;
select set_config('realesty.audit_purge', 'on', true);
delete from public.staff_audit_log where at < now() - interval '5 years';
commit;
```

L’admin consulte et exporte le journal (CSV) depuis l’écran **Journal** du back-office.

## 6. Repli : le back-office est indisponible

Les runbooks SQL restent valables : [certifier-un-dossier.md](certifier-un-dossier.md) (`staff_start_review`, `staff_certify_property`, `staff_attach_valuation_report`, `staff_verify_document`, `staff_reject_document`), [suivre-une-vente.md](suivre-une-vente.md) (`staff_verify_identity`), [fiche-de-remplissage.md](fiche-de-remplissage.md). Ils journalisent `sql_editor`.

Corriger un avis de valeur déjà certifié : **runbook SQL** (« Corriger une erreur » dans [certifier-un-dossier.md](certifier-un-dossier.md)) ; pas d’action dans le back-office en v1 (Q9).

Un brouillon d’avis de valeur bloqué (conflit, partenaire désactivé) :

```sql
select property_id, version, status, updated_by, submitted_by, updated_at from public.valuation_drafts;
update public.valuation_drafts set status = 'editing' where property_id = '<property id>';
```
