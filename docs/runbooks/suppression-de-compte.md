# Runbook · Suppression des comptes (EPIC-11)

Arbitrage du porteur de projet (2026-10-03) : la suppression demandée dans l’app **désactive le compte immédiatement**, puis le **supprime définitivement 30 jours plus tard** ; d’ici là, l’utilisateur peut le réactiver en se reconnectant (écran « Votre compte est désactivé »).

## 1. Fonctionnement

- App : Compte → Mes données → « Supprimer mon compte » (aussi depuis V19 et l’espace acquéreur provisoire) → RPC `deactivate_account()` : `profiles.deactivated_at = now()`, `deletion_due_at = now() + 30 jours`, puis déconnexion de tous les appareils. Refus : vente active (`active_sale`, table `sales` d’EPIC-08 détectée à l’exécution par `to_regclass`, étapes `mandate_signed`, `published`, et plus tard `under_offer`, `under_compromis`), membre de l’équipe (`staff_account`, table `staff_members` d’EPIC-12 si elle existe).
- Reconnexion d’un compte désactivé : l’app n’ouvre que l’écran « Réactiver mon compte » (`reactivate_account()`).
- Purge : **pg_cron** (job `purge-deactivated-accounts`, tous les jours à 03:17 UTC) appelle `public.run_account_purge()`, qui, s’il y a au moins un compte échu, appelle l’Edge Function **`purge-accounts`** via **pg_net** avec l’en-tête `x-purge-secret`. Pour chaque compte échu (20 par exécution) : ligne `account_deletions` (`account_purge_begin`, re-vérifie que le compte est toujours désactivé et échu), suppression des fichiers de tous les buckets sous `<user id>/` (API Storage, par lots de 100 ; la suppression directe en SQL est bloquée par Supabase), suppression de l’utilisateur Auth (cascade : profil, biens et enfants, lots, notifications, journaux voix / vision ; `valuations.expert_user_id` mis à null), fin de la ligne (`account_purge_finish`, qui supprime aussi l’utilisateur en SQL si l’API ne l’a pas trouvé).
- Idempotent : une purge interrompue reprend à l’exécution suivante (`account_deletions.attempts`).
- `account_deletions` ne contient aucune donnée personnelle en clair (`email_sha256`, dates, nombre de biens et de fichiers) ; lecture service role / éditeur SQL seulement.

## 2. Secrets (déjà en place)

- Secret Edge Function `PURGE_ACCOUNTS_SECRET` = secret Vault `purge_accounts_secret` (même valeur, jamais dans le dépôt).
- Secret Vault `project_url` = `https://xbteiljpjfmiianlmbwn.supabase.co`.

Rotation :
```sh
S=$(openssl rand -hex 32)
supabase secrets set PURGE_ACCOUNTS_SECRET="$S"
supabase db query --linked "select vault.update_secret((select id from vault.secrets where name = 'purge_accounts_secret'), '$S')"
unset S
```

## 3. Suivre

```sql
-- Comptes désactivés et date de suppression
select id, deactivated_at, deletion_due_at from public.profiles
where deactivated_at is not null order by deletion_due_at;

-- Purges faites ou en cours
select * from public.account_deletions order by started_at desc;

-- Exécutions du job et réponses de la fonction
select * from cron.job_run_details
where jobid = (select jobid from cron.job where jobname = 'purge-deactivated-accounts')
order by start_time desc limit 10;
select id, status_code, content, created from net._http_response order by id desc limit 10;
```

## 4. Lancer la purge à la main

```sql
select public.run_account_purge();   -- renvoie l'id de la requête pg_net, null si rien d'échu
```
ou, sans pg_cron / pg_net :
```sh
curl -X POST https://xbteiljpjfmiianlmbwn.supabase.co/functions/v1/purge-accounts \
  -H "x-purge-secret: <PURGE_ACCOUNTS_SECRET>"
```

Supprimer tout de suite un compte (demande écrite de l’utilisateur, RGPD) : le rendre échu puis lancer la purge.
```sql
update public.profiles
set deactivated_at = coalesce(deactivated_at, now()), deletion_due_at = now()
where id = '<user id>';
select public.run_account_purge();
```

Annuler une suppression demandée (avant l’échéance) :
```sql
update public.profiles set deactivated_at = null, deletion_due_at = null where id = '<user id>';
```

## 5. Limites connues

- Un compte désactivé reste techniquement utilisable par l’API pendant 30 jours si une session survit (l’app déconnecte tous les appareils et n’ouvre que l’écran de réactivation) ; ses dossiers restent visibles de l’équipe : ne pas les traiter (le back-office EPIC-12 devra les signaler).
- Les notifications et e-mails Supabase ne sont pas envoyés pour la désactivation (aucun e-mail en v1).
- Rétention légale de documents contractuels (vrais mandats, factures) : à traiter quand ils existeront (aujourd’hui : mandats de test seulement).
