# Runbook · Fiche de remplissage et fil de conversation (EPIC-16)

Avant de certifier un dossier ([certifier-un-dossier.md](certifier-un-dossier.md)), l’expert relit **d’où vient chaque valeur** (fiche de remplissage) et, si besoin, **ce que le vendeur a dit** à l’assistant vocal (fil de conversation). En attendant le back-office EPIC-12, les deux se lisent dans le **SQL Editor** du tableau de bord Supabase (rôle `postgres`) ou avec `supabase db query --linked` (rôle `service_role`). Les fonctions ne sont pas appelables depuis l’application (exécution retirée à `public`, `anon` et `authenticated`).

Migrations : `supabase/migrations/20261002175436_voix_prioritaire.sql`, `20261002200016_fill_sheet_sources.sql` (corrections de la fiche). Plan : [Voix prioritaire](../plans/2026-10-03-voix-prioritaire.md) §5.

## 1. La fiche de remplissage

```sql
select step, entity, entity_label, label_fr, value, source, quote,
       said_at, saved_at, confirmed, confirmation, verified
from public.staff_fill_sheet('<property id>')
order by sort_order, entity_label, field;
```

Une ligne par valeur enregistrée du dossier (bien, pièces, estimations précédentes, atouts / points de vigilance, notes complémentaires d’étape), puis une ligne par **réponse dite pour une autre étape et non acceptée**.

### Colonnes (contrat pour EPIC-12)

| Colonne | Contenu |
|---|---|
| `step` | étape du tunnel : `location`, `context`, `technical`, `rooms`, `lifestyle` |
| `entity` | `property`, `room`, `previous_estimate`, `lifestyle_item`, `note` |
| `entity_id`, `entity_label` | ligne de la pièce / estimation / atout (« Séjour », « Estimation 1 », « Atout ») ; pour une réponse en attente, son id |
| `field`, `label_fr` | colonne et libellé (catalogue `dossier_field_catalog`) ; pour une note en attente : l’étape (`technical`…) et « Notes complémentaires » |
| `value` | valeur enregistrée, codes traduits par le catalogue ; pour une réponse non acceptée, la valeur proposée (le texte même pour une note) |
| `source` | `dicte` (dit sur l’étape), `dicte_autre_etape` (dit ailleurs, pré-rempli « À confirmer », puis confirmé), `saisi` (tapé), `extrait` (lu sur un plan ou une photo), `externe` (Base Adresse Nationale, cadastre, copie d’un autre bien), `non_trace` (valeur enregistrée avant EPIC-16), `invalide` (source inconnue : entrée forgée ou cassée, jamais vérifiée) |
| `quote` | phrase d’origine (citation littérale, prise dans le journal du serveur) |
| `turn_id`, `said_at` | tour de conversation et heure de la phrase |
| `saved_at` | heure d’enregistrement par l’application |
| `confirmed` | `true` si la valeur est au dossier et confirmée ; `false` pour une réponse non acceptée, ou pour une valeur déjà écrite mais liée à une réponse encore en attente (pièce enregistrée pour ses photos avant « Continuer ») |
| `confirmation` | pour une valeur dite ailleurs : `continuer` (bouton), `oui` (dit ou touché), `mise_a_jour` (étape déjà validée), ou le statut de sa réponse tant qu’elle n’est pas confirmée ; pour une réponse non acceptée : son statut `pending`, `rejected`, `superseded` ou `expired` |
| `verified` | `true` : le tour cité (ou la réponse acceptée) appartient bien à ce bien et sa valeur correspond à la valeur enregistrée ; `false` : **à vérifier** (dont une valeur « dicté » sans tour ni réponse, et toute source `invalide`) ; vide : sans objet (valeur tapée, externe ou non tracée) |
| `sort_order` | ordre d’affichage (étape, champ, ligne) |

### Lire la fiche

- **`verified = false`** : la valeur enregistrée ne correspond pas à ce qui a été dit (valeur retouchée sans changer sa source, ou `field_sources` écrit par un client modifié). Se fier à la citation et au fil (§2), demander au vendeur si besoin.
- **`dicte_autre_etape`** : le vendeur l’a dit à une autre étape ; la fiche montre la citation et comment il l’a confirmé.
- **Réponses non acceptées** (`confirmed = false`) : `expired` = encore en attente à l’envoi (jamais appliquée, « dit, non confirmé ») ; `rejected` = refusée ou modifiée par le vendeur ; `superseded` = remplacée par une autre valeur dite.
- **`non_trace`** : dossier rempli avant EPIC-16 ; une pièce dictée apparaît `dicte` sans citation, une pièce lue sur un plan `extrait`.
- Les notes complémentaires (étape ou pièce) ne contiennent que des mots dits ou tapés par le vendeur ; les téléphones et e-mails dits sont masqués (`[numéro masqué]`, `[e-mail masqué]`).

### Exporter en CSV

Dans le SQL Editor, lancer la requête puis **Export → CSV**. En ligne de commande :

```sh
supabase db query --linked --output-format json \
  "select * from public.staff_fill_sheet('<property id>') order by sort_order" > fiche.json
```

## 2. Le fil de conversation

```sql
select step, at, transcript, reply_fr, retained, cross_step, notes, rejected,
       confirmations, undone, error
from public.staff_voice_thread('<property id>');
```

Tous les tours, dans l’ordre : transcription, réplique de l’agent, valeurs retenues (`retained.patch`, `retained.entity_ops`, `retained.lifestyle_items`, `retained.evidence` = citations), valeurs dites pour une autre étape (`cross_step`), notes, rejets avec leur motif, confirmations demandées, tours annulés par le vendeur (`undone`). Les lignes de réservation sans contenu sont exclues.

Sans identité : V1 (propriétaires) n’a pas de voix ; les anciens tours V1 portent `[identité non conservée]` ; une adresse dictée apparaît `[adresse non conservée]` ; téléphones et e-mails sont masqués. Aucun audio n’est conservé.

## 3. Réponses en attente d’un dossier

```sql
select target_step, kind, field, label_fr, changed_fr, quote, status, resolution,
       created_at, resolved_at
from public.pending_answers
where property_id = '<property id>'
order by created_at;
```

## 4. Catalogue des champs

`select * from public.dossier_field_catalog order by sort_order;` — étape, entité, champ, libellé, codes → libellés. Tenu en parité avec le registre de l’agent (test `supabase/functions/tests/agent_handlers_cross_step_test.ts`) : ajouter une ligne par migration quand un champ est ajouté au tunnel.
