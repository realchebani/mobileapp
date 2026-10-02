# EPIC-16 · Voix prioritaire — étude & conception

Statut : **plan rédigé (aucun code)**, questions ouvertes §15. Branche `feat/epic-16-voix-prioritaire`. À coder **après la fusion d’EPIC-15** (« Photos du bien », en cours dans un autre worktree : il modifie V5 / V5c, `rooms`, la fiche pièce, V7 et l’aperçu V8) ; la tranche 0 rebase sur `main` et relit le code fusionné.

Epic : [EPIC-16](../epics/EPIC-16-voix-prioritaire.md). Plans précédents : [EPIC-14 · Voix étendue](2026-10-02-voix-etendue.md) (livré), [EPIC-13 · Multi-biens](2026-10-02-multi-biens.md) (livré), [EPIC-15 · Photos du bien](2026-10-02-photos-du-bien.md) (en cours, worktree `epic-15-photos`).

## 0. Contexte

### 0.1 Décisions du porteur de projet (2026-10-02, `docs/decisions.md`)

- **Voix (suite EPIC-14)** : voix prioritaire sur chaque étape (le remplissage démarre à la voix, l’écrit reste toujours possible) ; **pas de voix sur V1** ; **traçabilité pour l’expert** : fil de conversation + fiche de remplissage (champ, valeur, phrase d’origine) ; pièces : champs structurés quand ils existent, sinon **« Notes complémentaires »**. Inchangés : confirmations (risquées seulement), modèles les moins chers, quotas 120 tours / 20 min, « 4 sur 3 » calculé, pas de micro en V7, fiches vocales pour tous les types, voix de l’agent silencieuse pendant la dictée des pièces.
- **Pré-remplissage inter-étapes par la voix** : toute information dite qui concerne une autre étape est retranscrite et **pré-remplie** sur l’étape concernée avec un badge **« À confirmer »** (jamais redemandée, simplement reconfirmée) ; jamais appliquée sans confirmation ; phrase d’origine conservée pour l’expert.

### 0.2 Ce que fait le code aujourd’hui (EPIC-14 fusionné)

- **Micro facultatif** : chaque étape V1, V2, V3, V4b, V5c, V6 affiche un micro dans `AgentActionBar` (`onMicPressed`) selon `PropertyTypeProfile.hasVoice(step)` ; il ouvre la feuille modale Night `StepVoiceSheet` (`showStepVoiceSheet`) après `ensureVoiceConsent` (consentement v3, `VoicePreferences.consentKey = voice_consent_v3`). Rien n’est enregistré avant « Continuer » ; valeurs marquées `DictatedTag` (« Dicté »), annulation par rejeu (`VoiceFormMixin`).
- **V1** : feuille vocale `owners` (type de propriété + prénom / nom des co-propriétaires, `VOICE_DEFAULTS.coOwnerNames`), transcript effacé du journal (`IDENTITY_REMOVED`), réplique expurgée (`redactNames`).
- **V2** : adresse en dictée simple (`agent-transcribe` `mode=dictation`, jamais envoyée au modèle de langage, `[adresse non conservée]` au journal) + feuille `location` pour les servitudes.
- **Hors étape** : le modèle renvoie seulement des **codes** `out_of_step` (enum des colonnes des autres étapes, `otherStepColumns`) ; `validate.ts` les transforme en pastilles grises « Construction → Technique » ; **la valeur et la citation sont perdues** (rien n’est stocké, l’agent dit « je le noterai à l’étape Technique » et la question sera reposée).
- **Journal** `agent_sessions` / `agent_turns` (lecture seule pour le propriétaire, écrit par les fonctions en `service_role`) : `transcript`, `reply_fr`, `extracted` = tour validé (`patch`, `facts`, `entity_ops`, `confirmations`, `out_of_step`, `rejected`…) **sans les citations** (les `quote` du modèle servent à la validation puis sont jetées), `undone`. Vue `agent_step_stats` (coût / qualité, `service_role`).
- **Provenance** : `properties.provenance` (colonne → `declared` / `document` / `external` / `expert` / `ai`) ; `rooms.source` (`scan`, `plan`, `manual`, `voice`), `lifestyle_items.source` (`declared`, `voice`) ; `previous_estimates` sans source. Aucune trace « saisi vs dicté » par champ, ni de lien valeur → tour.
- **Pièces** : `rooms.description` (≤ 300, « Description » dans la fiche pièce et le tableau V5c). EPIC-15 y ajoute « Ajouter à la description » (constats de l’IA de vision) et retire la carte V5 « Scanner avec la caméra ».

### 0.3 Ce qu’EPIC-16 change

1. La **voix devient le mode d’entrée par défaut** de V2 à V6 (l’étape s’ouvre en mode voix, « Écrire plutôt » bascule à l’écrit ; préférence mémorisée sur l’appareil).
2. **V1 n’a plus de voix** (feuille, entité co-propriétaire et chemins « identité » retirés).
3. Une information d’une autre étape devient une **réponse en attente** (`pending_answers`), pré-remplie sur l’étape cible avec « À confirmer ».
4. Ce qui ne rentre dans aucun champ va dans des **« Notes complémentaires »** (pièce et étape).
5. **Traçabilité** : citations conservées au journal, origine de chaque valeur enregistrée (`field_sources`), fonctions `staff_*` (fil + fiche de remplissage) en attendant le back-office EPIC-12.

---

## 1. Principes retenus

1. **La voix propose, le vendeur voit, l’app écrit** (inchangé). Une réponse en attente n’est jamais écrite dans le dossier par le serveur : elle est stockée à part (`pending_answers`) et n’entre au dossier qu’après un geste du vendeur (« Continuer » sur l’étape où elle est affichée, « oui » dit ou touché).
2. **Jamais redemandée, seulement reconfirmée** : l’agent reçoit les valeurs pré-remplies de l’étape et ne pose pas la question ; il propose de les confirmer d’un mot.
3. **Une seule vérité par champ** : une nouvelle valeur dite pour le même champ remplace la précédente en attente (`superseded`) ; une valeur saisie à l’écran remplace la valeur en attente (`rejected`, résolution `modifie`).
4. **Preuve conservée** : chaque valeur dictée garde sa citation littérale, son tour et son heure, côté serveur (journal écrit en `service_role`), et l’app enregistre l’origine de chaque valeur au moment où elle l’écrit.
5. **Pas d’identité** : rien de V1 à la voix ; l’adresse reste en dictée simple (jamais au modèle, jamais au journal) ; téléphones et e-mails masqués dans tous les transcripts conservés.
6. **Voix par défaut, jamais obligatoire** : le formulaire reste complet et utilisable ; consentement, permission micro, disponibilité (`VOICE_ENABLED`, quota, réseau) et type de bien sont respectés ; tout échec retombe en mode écrit sans bloquer.

---

## 2. Expérience : voix prioritaire

### 2.1 Mode d’entrée et préférence

- Nouveau réglage d’appareil `VoicePreferences.inputMode` (`voice` par défaut, `text`) — clé `voice_input_mode` dans `SharedPreferences`, **une préférence globale par appareil** (Q3).
- **Mode voix** (par défaut) : à l’ouverture d’une étape vocale, la feuille vocale de l’étape s’ouvre d’elle-même (Q1, Q2) ; son en-tête porte un bouton texte **« Écrire plutôt »** qui ferme la feuille, passe la préférence à `text` et laisse le formulaire.
- **Mode écrit** : l’étape s’ouvre sur le formulaire ; la barre d’action garde le micro (usage ponctuel, ne change pas la préférence) et un lien **« Répondre à la voix »** qui repasse la préférence à `voice` et ouvre la feuille.
- **Pas d’ouverture automatique** (le formulaire s’affiche, micro visible) quand :
  - l’étape est **déjà complète** (revisite par « Retour », ou étape déjà validée sans réponse en attente) ;
  - la voix est **indisponible** : `VoiceServices.isAvailable` faux, type sans voix pour l’étape (`hasVoice`), dossier verrouillé, quota du jour épuisé (dernier 429 mémorisé jusqu’à minuit UTC), hors ligne (échec réseau de la dernière session) ;
  - le **micro est refusé** (permission iOS) : bandeau « Micro désactivé · Réglages » une fois par session, préférence inchangée ;
  - le **consentement** est refusé : l’écran RGPD (v4, §9) est montré à la première ouverture automatique ; un refus passe la préférence à `text` (le vendeur peut toujours toucher le micro plus tard).
- **3 tours sans rien retenir** (existant, `missesBeforeScreenMode`) : la feuille propose « Continuer à l’écrit » ; un toucher ferme la feuille **sans** changer la préférence.
- L’écoute démarre automatiquement à l’ouverture (orbe animé, vibration courte) quand le consentement et la permission sont acquis (Q2).

### 2.2 Par étape

| Étape | Mode voix par défaut | Notes |
|---|---|---|
| **V1 · Propriétaires** | **aucune voix** | Micro, feuille `owners`, co-propriétaires dictés et consentement « noms » retirés. Formulaire seul (pré-rempli depuis le profil / un autre bien, EPIC-13). |
| **V2 · Adresse** | le champ « Adresse du bien » s’ouvre **en dictée** (orbe dans le champ, transcription seule, inchangé côté serveur) ; après le choix de la suggestion et la confirmation des parcelles (carte, inchangée), la **feuille `location`** s’ouvre pour les situations particulières et les notes | « Écrire plutôt » sous le champ dicté ; jamais de pré-remplissage d’adresse depuis une autre étape. |
| **V3 · Contexte** | feuille `context` ouverte d’emblée | Le changement de type reste confirmé. |
| **V4 Night / V4b** | V4b : feuille `technical` ouverte d’emblée ; lien « Conversation guidée » (audit Night V4) inchangé pour maison / appartement / autre | La redirection V3 → V4 (logements) reste celle d’EPIC-14 (Q4 d’EPIC-14). |
| **V5 · Méthode** | pas de feuille (cartes) ; en mode voix, la carte **« Dicter mes pièces »** passe en tête avec le badge « Recommandé » | Cartes EPIC-15 (« Lire un plan ») conservées. |
| **V5c · Pièces** | si aucune pièce : **dictée de pièces** ouverte d’emblée (agent silencieux, récapitulatif parlé, inchangé) ; sinon formulaire + micro | Pièces pré-remplies par d’autres étapes affichées « À confirmer » (§3). |
| **V6 · Cadre de vie** | feuille `lifestyle` ouverte d’emblée | Note secrète jamais pré-remplie. |
| **V7 · Documents** | pas de micro (inchangé) | Carte « Informations dictées à confirmer (n) » si des réponses en attente restent (§3.5). |
| V8 | — | Aperçu : notes complémentaires et pièces avec notes. |

### 2.3 Feuille vocale (évolutions de `StepVoiceSheet`)

- En-tête : titre de l’étape, **« Écrire plutôt »** (bouton texte, 44 px), sourdine (existant).
- **Intro** : si l’étape a des réponses en attente, l’intro les liste et demande une confirmation globale : « J’ai déjà noté : construction en 1998, chauffage au gaz. C’est bien ça ? Dites oui, ou corrigez. » (texte construit par l’app, non parlé — pas de tour consommé ; la première réplique de l’agent, elle, est parlée) ; sinon l’intro d’EPIC-14.
- **Pastilles** : « Compris » (existant), **« Noté pour Technique · Construction 1998 »** (nouveau, Lueur atténuée, icône flèche, sans croix : annulable depuis l’étape cible ; croix « Annuler » tant que la feuille est ouverte → statut `rejected`), confirmations (existant), **confirmation de mise à jour** d’une étape validée (§3.4).
- **« oui » local** : avec une confirmation en attente, inchangé ; sinon, s’il reste des valeurs « À confirmer » sur l’étape, « oui » / « c’est ça » / « exact » les **confirment toutes** (le badge devient « Dicté ✓ »), sans appel au modèle.
- Le formulaire derrière la feuille montre les valeurs pré-remplies et dictées (inchangé). La feuille reste modale (Q1).

---

## 3. Pré-remplissage inter-étapes

### 3.1 Parcours

1. Sur V3, le vendeur dit : « On l’a achetée 320 000 € en 2012, elle date de 1998, chauffage au gaz, et il y a une école au bout de la rue. »
2. `agent-turn` (`step = context`) : `answers` = prix et année d’achat (appliqués au brouillon V3, inchangé) ; **`cross_step`** = `construction_year = 1998` (Technique), `heating_systems = [gaz]` (Technique), élément de cadre de vie « École au bout de la rue » (atout, Cadre de vie). Chaque valeur est validée **avec la définition du champ de l’étape cible** (bornes, codes du type, ancres, citation) puis **insérée par le serveur dans `pending_answers`** (statut `pending`, citation, tour).
3. La réplique : « C’est noté. J’ai aussi pris l’année de construction et le chauffage pour l’étape Technique, et l’école pour le cadre de vie. Avez-vous déjà fait estimer le bien ? » Pastilles « Noté pour Technique · Construction 1998 », « Noté pour Technique · Chauffage gaz », « Noté pour Cadre de vie · École au bout de la rue ».
4. Sur V4b : le formulaire s’ouvre **pré-rempli** (1998, gaz) avec le badge **« À confirmer »** sur chaque champ ; la feuille s’ouvre, l’intro rappelle les deux valeurs, l’agent ne les redemande pas (le prompt les reçoit comme « pré-remplies, à confirmer, ne pas redemander »).
5. Le vendeur dit « oui » (local) ou touche « Continuer » : les valeurs sont enregistrées avec l’étape (`saveAndContinue`), puis les lignes `pending_answers` passent à `accepted` (résolution `oui` ou `continuer`). S’il modifie ou efface la valeur à l’écran : `rejected` (résolution `modifie` / `efface`) ; s’il redit une autre valeur : la nouvelle remplace l’ancienne (`superseded`), la nouvelle est un « Dicté » normal de l’étape.

### 3.2 Ce qui peut être pré-rempli

| Cible | Forme | Exemple dit ailleurs | Exclusions |
|---|---|---|---|
| V2 `location` | champs `special_situations`, `special_situation_other` ; note d’étape | « il y a une servitude de passage » | **adresse, parcelles** (jamais) |
| V3 `context` | tous ses champs, sauf `property_type` (Q6 bis) ; entité **estimation précédente** (`create` seulement) | « une agence l’a estimée 300 000 € en mars » | changement de type (structurant : seulement sur V3) |
| V4b `technical` | tous les champs du type (`isAsked`, conditions PAC / piscine évaluées sur dossier + brouillon) | « chaudière gaz de 2015 », « toiture refaite en 2010 » | — |
| V5c `rooms` | entité **pièce** (`create` seulement, nom + surface + niveau + sol + vitrage + notes) | « la cuisine fait 12 m² » dit en V3 | `update` / `delete` d’une pièce (les références R* ne sont envoyées qu’en V5c) |
| V6 `lifestyle` | `noise_level`, `overlooking` (si `asksNeighbourhood`), **atouts / vigilances** | « c’est très calme, pas de vis-à-vis » | `secret_note` (jamais) |
| toutes | **note d’étape** (§4) | « le grenier est aménageable » dit en V3 → note Technique | — |
| V1 | **rien** (Q6) | — | `ownership_type`, noms, coordonnées |

Champs non demandés pour le type au moment de la saisie : refusés (`not_asked`). Si le type change ensuite (EPIC-13), les réponses en attente devenues hors sujet restent `pending` mais **masquées** (comme `clearedFrom`), puis `expired` à l’envoi.

### 3.3 Règles

- **Confiance** : < 0,5 → rejet (journal) ; 0,5–0,7 → stockée, badge « À confirmer » (toute réponse en attente est confirmée de toute façon) avec la mention « ? » dans la pastille.
- **Une réponse en attente par champ** (index unique partiel) : une nouvelle valeur dite pour le même champ, depuis n’importe quelle étape, remplace la précédente (`superseded`).
- **Entités** : pièces, estimations, atouts / vigilances en attente sont des lignes distinctes ; doublon (même nom de pièce et même surface, même libellé d’atout normalisé, même prix + mois) → ignoré (`duplicate`).
- **Règles croisées** (année toiture ≥ construction, chambres ≤ pièces, séjour ≤ habitable…) : évaluées par le serveur sur **dossier + brouillon courant + réponses en attente** ; à l’application dans l’étape cible, la validation de l’écran (existant) s’applique en plus.
- **Correction au tour suivant** (« non, 1999 ») : le dernier tour retenu inclut les réponses `cross_step` (`lastRetained`) ; une correction remplace la ligne (`superseded`).
- **Annulation** : la croix d’une pastille « Noté pour … » ou « Annuler ce tour » dans la feuille passe la ligne à `rejected` (résolution `annule`) et marque le tour `undone` (existant).
- **Limite** : 8 réponses inter-étapes par tour, 100 lignes `pending` par bien (au-delà : `full`, la réplique dit de les donner à l’étape concernée).

### 3.4 Étape déjà validée (Q4)

Une étape cible est « validée » si elle est avant l’étape de reprise du bien dans l’ordre du profil (`SellerTunnelState` : position de la cible < `current_step`).

- **Champs** : la feuille montre une **confirmation de mise à jour** : « Mettre à jour Contexte · Prix d’achat : 300 000 → 320 000 € ? Oui · Non » (« Ajouter à Contexte · … ? » si le champ était vide). « Oui » (touché ou dit, local) → l’app écrit aussitôt via `SellerTunnelCubit.save` (colonne + provenance `declared` + `field_sources`, §5.3), puis `accepted` (résolution `oui`). « Non » → `rejected` (`non`). Sans réponse : la ligne reste `pending`, visible sur l’étape (badge) et en V7.
- **Entités** (pièce dite en V6 alors que V5c est validée, estimation dite en V4b) : pas d’écriture depuis la feuille (la surface habitable est recalculée en V5c) ; pastille « Noté pour Pièces · Cellier 4 m² · Voir » → après la fermeture de la feuille, lien vers l’étape où l’élément apparaît « À confirmer » (« Tout est correct, continuer » l’accepte).
- Un dossier envoyé n’a plus de voix (verrou inchangé).

### 3.5 Réponses en attente non confirmées (Q5)

- **Accueil du bien / reprise** : aucune modification (les badges sont sur les étapes).
- **V7** : carte non bloquante « Informations dictées à confirmer (2) » (liste : étape, valeur, « Voir » → l’étape). L’envoi reste possible.
- **À l’envoi** (`status` draft → submitted) : un déclencheur passe les lignes encore `pending` à `expired` (résolution `envoi`). Elles **ne sont jamais appliquées** ; l’expert les voit dans la fiche comme « dit, non confirmé ».

---

## 4. Notes complémentaires

- **Pièces** : `rooms.description` est **renommée à l’écran « Notes complémentaires »** (colonne inchangée, Q8 : EPIC-15 l’utilise déjà), longueur portée de 300 à **600** caractères. L’agent `rooms` met dans `description` **tout ce qui est dit sur la pièce et n’a pas de champ** (règle de couverture inchangée : ≥ 80 % des mots dits, aucun chiffre absent du transcript, ni téléphone ni e-mail ; consigne : factuel, sans adjectif ajouté). Les phrases successives sur la même pièce s’**ajoutent** (séparateur « · »), au lieu de remplacer.
- **Étapes** (Q7) : nouvelle colonne `properties.step_notes` (objet `{location, context, technical, rooms, lifestyle}`, ≤ 1 000 caractères chacun). Champ **« Notes complémentaires »** (multiligne, facultatif) en bas de V2, V3, V4b, V5c (notes générales sur les surfaces) et V6, saisi ou dicté. L’agent renvoie `notes: [{text, quote}]` pour l’étape ouverte (ce qui n’entre dans aucun champ ni entité), et `cross_step.notes` pour une autre étape (en attente, « À confirmer »). Mêmes règles de couverture que les notes de pièce.
- Les notes ne sont **jamais renvoyées au prompt** (injection, coût) : seulement leur présence (« notes : oui »).
- V8 (aperçu) affiche les notes de chaque étape et de chaque pièce ; l’expert les lit dans la fiche (§5).

---

## 5. Traçabilité pour l’expert

### 5.1 (a) Fil de conversation

- Tous les tours du journal, par étape, dans l’ordre : heure, transcription, réplique de l’agent, valeurs retenues (dans l’étape, en attente pour une autre étape, notes), valeurs rejetées et motif, confirmations, annulations (`undone`).
- **Sans identité** : V1 n’a plus de tours (les anciens tours V1 gardent `[identité non conservée]`) ; adresse dictée = `[adresse non conservée]` (existant) ; **téléphones et e-mails masqués** dans tout transcript, réplique et note avant écriture au journal (`maskContacts`, `[numéro masqué]`, `[e-mail masqué]`) ; Q9 pour les noms de personnes.
- Les audios ne sont jamais conservés (inchangé).

### 5.2 (b) Fiche de remplissage

Une ligne par champ renseigné du dossier (et par champ de chaque pièce, estimation, atout / vigilance, note), plus une ligne par réponse en attente non acceptée :

| Colonne | Contenu |
|---|---|
| `step` | étape (libellé du catalogue) |
| `entity`, `entity_label` | `property` / `room` « Séjour » / `previous_estimate` « Estimation 1 » / `lifestyle_item` / `note` |
| `field`, `label_fr` | code et libellé (« Année de construction ») |
| `value` | valeur enregistrée (texte lisible, codes traduits par le catalogue) ; pour une réponse non acceptée, la valeur proposée |
| `source` | **`dicte`** (dans l’étape) · **`dicte_autre_etape`** (pré-rempli puis confirmé) · **`saisi`** · **`extrait`** (plan ou photo, EPIC-15) · **`externe`** (BAN, cadastre, copie depuis un autre bien) · **`non_trace`** (valeur antérieure à EPIC-16) |
| `quote` | phrase d’origine (citation littérale, depuis le journal) |
| `turn_id`, `said_at` | tour et heure de la phrase |
| `saved_at` | heure d’enregistrement par l’app |
| `confirmed` | vrai si la valeur est au dossier ; `confirmation` : `continuer`, `oui`, `mise_a_jour` ; faux pour `pending` / `rejected` / `expired` (avec leur statut) |
| `verified` | vrai si le tour cité appartient bien à une session de ce bien et que la valeur du journal correspond à la valeur enregistrée (sinon « à vérifier ») |

### 5.3 Données nécessaires (et pourquoi)

1. **Citations au journal** : `agent_turns.extracted.evidence` (nouveau) = liste `{k, v, q, c}` — clé (`purchase_year`, `op:0.area_m2`, `note:0`, `x:2` pour la 3ᵉ réponse inter-étapes), valeur validée, citation, confiance — pour **chaque valeur retenue** (appliquée, à confirmer ou en attente). Écrit par la fonction (`service_role`) : l’app ne peut pas le falsifier.
2. **Origine de chaque valeur enregistrée** : `field_sources` (jsonb) sur `properties`, `rooms`, `previous_estimates`, `lifestyle_items` : `{colonne: {s, t?, k?, p?, at}}` — `s` source (§5.2), `t` tour, `k` clé de la preuve dans ce tour, `p` réponse en attente acceptée, `at` horodatage de l’enregistrement. **Écrit par l’app dans la même requête que la valeur** (même `update` / `upsert` : atomique, pas de seconde écriture à rattraper), via `Property.mergeFieldSources` (comme `mergeProvenance`). Une valeur saisie remplace l’entrée par `{s: saisi, at}`.
3. **Réponses en attente** : `pending_answers` (§6.2), écrites par le serveur, résolues par l’app.
4. **Catalogue des champs** : table de référence `dossier_field_catalog` (étape, entité, champ, libellé, ordre, table des codes → libellés), seedée par la migration ; servira à EPIC-12 pour l’affichage.

Le contrôle `verified` (jointure tour ↔ session ↔ bien, et `evidence.v` = valeur enregistrée) rend inutile un déclencheur de validation coûteux sur `field_sources` : une entrée forgée par un client modifié apparaît « à vérifier ».

### 5.4 Accès avant EPIC-12 (Q12)

- Fonctions SQL **`staff_voice_thread(p_property_id uuid)`** et **`staff_fill_sheet(p_property_id uuid)`** (`returns table`, `security invoker`, `set search_path = ''`), exécution révoquée pour `public`, `anon`, `authenticated`, accordée à `service_role` : lancées par l’équipe dans l’éditeur SQL (comme `staff_start_review`), et appelables plus tard par une Edge Function du back-office EPIC-12 (rôle expert vérifié côté fonction).
- Runbook **`docs/runbooks/fiche-de-remplissage.md`** : requêtes prêtes (`select * from public.staff_fill_sheet('<id>') order by …`), lecture des sources, cas « à vérifier », export CSV depuis l’éditeur ; lien depuis `certifier-un-dossier.md` (étape « relire la fiche de remplissage avant certification »).
- Forme stable pour EPIC-12 : les deux fonctions sont le contrat (colonnes documentées dans le runbook) ; l’écran expert les affichera telles quelles (fiche groupée par étape, citation au survol, lien vers le tour dans le fil).

---

## 6. Modèle de données et migrations

Une migration additive `supabase/migrations/<horodatage>_voix_prioritaire.sql`, créée par `supabase migration new voix_prioritaire` **après** la fusion d’EPIC-15 (son horodatage doit suivre `*_room_photos.sql`). Noms exacts des contraintes vérifiés avant écriture (`\d public.rooms`…). Sonde RLS dans un `DO` annulé, `db push --dry-run`, puis `db push`.

### 6.1 Colonnes

```sql
-- Notes complémentaires par étape et origine de chaque valeur (§4, §5.3).
alter table public.properties
  add column step_notes jsonb not null default '{}'
    check (public.step_notes_valid(step_notes)),
  add column field_sources jsonb not null default '{}'
    check (jsonb_typeof(field_sources) = 'object');
grant update (step_notes, field_sources) on table public.properties to authenticated;

-- step_notes_valid(jsonb): immutable; object whose keys are in
-- (location, context, technical, rooms, lifestyle) and values strings ≤ 1000.

alter table public.rooms
  drop constraint rooms_description_check,          -- nom à vérifier
  add constraint rooms_description_check check (char_length(description) <= 600),
  add column field_sources jsonb not null default '{}'
    check (jsonb_typeof(field_sources) = 'object');

alter table public.previous_estimates
  add column source text not null default 'manual' check (source in ('manual', 'voice')),
  add column field_sources jsonb not null default '{}'
    check (jsonb_typeof(field_sources) = 'object');

alter table public.lifestyle_items
  add column field_sources jsonb not null default '{}'
    check (jsonb_typeof(field_sources) = 'object');
```

Les tables enfants gardent leurs droits de table et le verrou (RLS `draft` / `submitted`) : les nouvelles colonnes sont couvertes. La contrainte `agent_sessions.step` **garde `owners`** (historique) ; seules les fonctions cessent d’en créer.

### 6.2 Table `pending_answers`

```sql
create table public.pending_answers (
  id uuid primary key default gen_random_uuid(),
  property_id uuid not null references public.properties (id) on delete cascade,
  owner_id uuid not null references auth.users (id) on delete cascade,
  target_step text not null
    check (target_step in ('location', 'context', 'technical', 'rooms', 'lifestyle')),
  kind text not null
    check (kind in ('field', 'room', 'previous_estimate', 'lifestyle_item', 'note')),
  field text check (char_length(field) <= 60),   -- colonne (kind = field)
  value jsonb not null,                           -- valeur typée, ou valeurs de l'entité
  label_fr text not null check (char_length(label_fr) <= 160),
  quote text not null check (char_length(quote) between 1 and 300),
  confidence numeric(3, 2) check (confidence between 0 and 1),
  source_step text not null,                      -- étape où la phrase a été dite
  turn_id uuid references public.agent_turns (id) on delete set null,
  status text not null default 'pending'
    check (status in ('pending', 'accepted', 'rejected', 'superseded', 'expired')),
  resolution text check (resolution in
    ('continuer', 'oui', 'non', 'modifie', 'efface', 'annule', 'remplace', 'envoi')),
  created_at timestamptz not null default now(),
  resolved_at timestamptz,
  check ((kind = 'field') = (field is not null))
);

create unique index pending_answers_one_open_field
  on public.pending_answers (property_id, field)
  where status = 'pending' and kind = 'field';
create index pending_answers_property
  on public.pending_answers (property_id, target_step, status);
```

- **RLS / droits** : `select` pour le propriétaire (`owner_id = auth.uid()`) ; **`update (status, resolution)`** seulement, pour le propriétaire, si le bien est `draft` ; aucun `insert` / `delete` client (écritures du serveur en `service_role`, comme le journal).
- Déclencheur `pending_answers_resolve` (before update) : seules les transitions `pending → accepted | rejected | superseded` sont permises au client, `resolution` obligatoire et cohérente (`accepted` ↔ `continuer` / `oui` ; `rejected` ↔ `non` / `modifie` / `efface` / `annule` ; `superseded` ↔ `remplace`, quand le vendeur redit une autre valeur sur l’étape cible), `resolved_at = now()`, toute autre colonne inchangée.
- Fonction **`agent_record_pending(p_owner_id uuid, p_property_id uuid, p_turn_id uuid, p_rows jsonb)`** (`service_role` seulement) : dans une transaction, passe à `superseded` (résolution `remplace`) la ligne `pending` du même champ, insère les nouvelles lignes, refuse au-delà de 100 lignes `pending` par bien ; renvoie les ids.
- Déclencheur sur `properties` (after update of `status`, `draft → submitted`) : lignes `pending` → `expired` (`envoi`).

### 6.3 Catalogue et fonctions staff

```sql
create table public.dossier_field_catalog (
  step text not null,          -- location | context | technical | rooms | lifestyle | documents…
  entity text not null,        -- property | room | previous_estimate | lifestyle_item | note
  field text not null,
  label_fr text not null,
  sort_order smallint not null,
  codes jsonb,                 -- code → libellé (enum / liste)
  primary key (entity, field)
);
-- seed : une ligne par colonne du tunnel (inventaire EPIC-14 §2, hors V1 identité et V7)
revoke all on table public.dossier_field_catalog from public, anon, authenticated;
grant select on table public.dossier_field_catalog to service_role;
```

- `staff_voice_thread(p_property_id)` → `(step, turn_id, at, transcript, reply_fr, retained jsonb, cross_step jsonb, notes jsonb, rejected jsonb, confirmations jsonb, undone boolean, error text)` depuis `agent_turns` ⋈ `agent_sessions`, trié par heure ; exclut les lignes de réservation sans contenu (`error in ('in_progress', 'empty')`).
- `staff_fill_sheet(p_property_id)` → colonnes du §5.2 : `to_jsonb(properties)` filtré par le catalogue ⋈ `field_sources` ⋈ `agent_turns.extracted -> 'evidence'` ; idem `rooms`, `previous_estimates`, `lifestyle_items`, `step_notes` ; plus `pending_answers` non `accepted`.
- Vue `agent_step_stats` : + `cross_step_count`, `pending_accept_rate` (acceptées / résolues), `notes_count` (suivi qualité).

### 6.4 Rétrocompatibilité

- Dossiers existants : `field_sources = {}` → la fiche les marque `non_trace` (sauf `rooms.source = voice` → `dicte` sans citation).
- Journal : les tours antérieurs n’ont pas d’`evidence` (citation vide dans la fiche).
- Aucune donnée supprimée ; le code `owners` disparaît des fonctions mais reste lisible.

---

## 7. Serveur (Edge Functions)

| Fichier | Changement |
|---|---|
| `_shared/agent/defaults.ts` | `coOwnerNames` supprimé ; `crossStepPrefill: true`, `stepNotes: true`, `crossStepMax: 8`, `pendingMax: 100` |
| `_shared/agent/steps/types.ts`, `steps/index.ts` | `owners` retiré de `AgentStep` / `AGENT_STEPS` / registre ; `voiceStepsFor` sans V1 ; **`crossStepTargets(step, values)`** : champs des autres étapes autorisés en pré-remplissage (sans adresse, parcelles, `property_type`, `secret_note`, ni V1) ; entités inter-étapes (`room` create, `previous_estimate` create, `lifestyle_item`) |
| `_shared/agent/steps/owners.ts` | **supprimé** (avec l’entité `co_owner`, `identity`, `redactNames`, `withoutIdentity`) |
| `_shared/agent/schema.ts` | sortie JSON : `cross_step: {answers: [{field, value, confidence, quote}], rooms: [...], estimates: [...], lifestyle_items: [...], notes: [{step, text, quote}]}` (enum des champs = `crossStepTargets`) ; `notes: [{text, quote}]` pour l’étape ouverte ; `out_of_step` conservé pour une information **sans valeur exploitable** (pastille grise, rien de stocké) |
| `_shared/agent/validate.ts` | `validateCrossStep` : chaque valeur validée avec la définition et les règles de **l’étape cible** (bornes, codes du type, ancres, citation, couverture, règles croisées sur dossier + brouillon + en attente), seuil de confiance 0,5, doublons, plafonds ; `validateNotes` (couverture, longueur, contacts) ; **`evidence`** pour toute valeur retenue ; notes de pièce ajoutées (pas remplacées) |
| `_shared/agent/prompt.ts` | consigne 5 réécrite (« informations d’une autre étape : `cross_step` avec la valeur et la citation ; ne jamais les mettre dans `answers` ») ; **catalogue compact des autres étapes** (champs, format, codes du type) dans un **second bloc système cacheable** (statique par étape × type) ; section « Valeurs pré-remplies à confirmer : … — ne les redemande pas ; si le vendeur les corrige, renvoie la nouvelle valeur » ; consigne notes (« ce qui ne correspond à aucun champ, factuel, sans nom de personne ») |
| `_shared/agent/handlers.ts` | refus `step = owners` (400) ; lecture des réponses en attente de l’étape (`db.pendingFor(property, step)`, envoyées au prompt et aux règles) ; après validation : `db.recordPending(...)` (RPC `agent_record_pending`) ; réponse + `cross_step: [{id, target_step, kind, field, value, label_fr, confidence}]`, `notes`, `superseded_ids` ; `maskContacts` sur transcript / réplique / notes avant `updateTurn` ; `extracted.evidence` ; `PROPERTY_COLUMNS` + `current_step` |
| `_shared/agent/db.ts`, `supabase_db.ts` | `pendingFor`, `recordPending` (service role, après contrôle de propriété avec le JWT de l’appelant — inchangé) ; `LIMITS.crossStep`, `LIMITS.notesChars` |
| `_shared/agent/anchors.ts` | `maskContacts` (motifs téléphone FR / international, e-mail) partagé avec la règle « pas de contact dans un texte libre » |
| `agent-transcribe` | `step = owners` refusé ; dictée d’adresse inchangée |
| `tests/` | étapes sans `owners` ; inter-étapes (valeurs, entités, notes, refus adresse / type / note secrète / V1, doublons, remplacement, plafonds) ; evidence ; masquage ; fixture de parité `voice_steps` sans V1 ; **catalogue** : parité entre `dossier_field_catalog` (SQL) et le registre (test qui lit la migration) |
| `supabase/bench/` | + 16 phrases enregistrées : 10 inter-étapes (une par paire d’étapes fréquente), 6 notes complémentaires ; mesure : valeurs justes en attente, faux positifs, coût / tour |

Le transcript reste envoyé au fournisseur STT puis au modèle (inchangé) ; seule l’adresse dictée échappe au modèle.

---

## 8. App

| Zone | Changement |
|---|---|
| `packages/property_repository` | `PendingAnswer` (+ `PendingStatus`, `PendingResolution`, `PendingKind`), `pendingAnswers(propertyId)`, `resolvePendingAnswers(ids, status, resolution)` ; `Property.stepNotes`, `Property.fieldSources`, `mergeFieldSources` ; `FieldSource` (`s`, `t`, `k`, `p`, `at`) ; `Room.fieldSources`, `Room.descriptionMaxLength = 600` ; `PreviousEstimate.source`, `.fieldSources` ; `LifestyleItem.fieldSources` ; colonnes `PropertyColumns.stepNotes`, `.fieldSources` |
| `packages/agent_repository` | `AgentStep.owners` retiré ; `AgentTurn.crossStep` (`AgentCrossStep`), `.notes`, `.supersededIds`, `.evidenceKeys` ; `coOwner` entité retirée |
| `lib/seller_tunnel/voice/` | `VoicePreferences.inputMode` + consentement **v4** ; **`VoiceFirstLauncher`** (décide l’ouverture automatique : préférence, disponibilité, permission, quota mémorisé, étape complète / réponses en attente) ; `StepVoiceSheet` : « Écrire plutôt », intro « déjà noté », pastilles « Noté pour … », confirmations de mise à jour, « oui » qui confirme les valeurs pré-remplies ; `VoiceFormMixin` : **origines** des valeurs (colonne → tour + clé de preuve) pour `field_sources`, application des notes ; `ToConfirmTag` (« À confirmer ») à côté de `DictatedTag` ; `LocalVoiceCommands` inchangé ; `VoiceDefaults` sans `coOwnerNames` |
| `lib/seller_tunnel/cubit/` | `SellerTunnelState.pendingAnswers` (chargées avec le bien, rafraîchies après un tour qui en crée) ; `pendingFor(step)` (masquées si hors sujet pour le type) ; `acceptPendingUpdate(pending)` (étape validée : `save` + `field_sources` + résolution) ; `resolvePending(ids, …)` ; échec réseau de la résolution : nouvelle tentative au prochain `refresh` (idempotent) |
| `lib/seller_tunnel/models/property_type_profile.dart` | `owners` retiré de `_voicedSteps` ; `prefillTargets` (miroir de `crossStepTargets`, fixture de parité) |
| `lib/seller_tunnel/widgets/` | `AgentActionBar` : lien « Répondre à la voix » en mode écrit ; **`StepNotesField`** (Notes complémentaires, 1 000 car., « Dicté » / « À confirmer ») |
| Étapes (`lib/seller_tunnel/steps/*`) | chaque cubit : brouillon initial = dossier + réponses en attente de l’étape (marquées « À confirmer ») ; au « Continuer » : `field_sources` des valeurs écrites (dicté / pré-rempli / saisi), puis résolution des lignes (`accepted` / `rejected`) ; notes d’étape ; ouverture automatique de la feuille via `VoiceFirstLauncher` |
| `steps/owners/**` | micro, feuille, `VoiceFormMixin`, co-propriétaire dicté, l10n `ownersVoice*` **retirés** ; `OwnersState` garde la règle « co-propriétaire complet » |
| `steps/location/**` | dictée d’adresse ouverte d’emblée en mode voix ; feuille situations + notes après les parcelles |
| `steps/property_context/**`, `technical/**`, `lifestyle/**` | feuille d’emblée ; pré-remplissage ; notes |
| `steps/method/**`, `surfaces/**` | carte « Dicter mes pièces » en tête ; dictée d’emblée si aucune pièce ; pièces en attente « À confirmer » dans le tableau ; « Notes complémentaires » (fiche pièce, tableau, 600) ; notes générales V5c |
| `steps/documents/**` | carte « Informations dictées à confirmer (n) » |
| `steps/submitted/widgets/dossier_summary_sheet.dart` | notes d’étape et de pièce |
| l10n | préfixes `voiceFirst*`, `prefill*`, `stepNotes*`, + libellés des étapes ; retrait de `ownersVoice*` ; texte du consentement v4 |

Pas de nouvelle route. `?dictee=1` de V5c inchangé.

---

## 9. Données personnelles et consentement

- **Consentement v4** (`voice_consent_v4`) : retire la mention des noms de V1 ; ajoute « Vos échanges avec l’assistant (transcriptions et réponses, sans l’audio) sont conservés dans votre dossier pour l’expert qui le certifie ; les numéros de téléphone et e-mails sont masqués. Les informations que vous donnez pour une autre étape vous sont présentées pour confirmation. »
- Conservation : le journal et les réponses en attente vivent **avec le dossier** (suppression du bien → cascade) — Q10.
- Les réponses en attente ne contiennent que des valeurs de la liste blanche (aucune identité, pas d’adresse).
- Politique de confidentialité : paragraphe « Assistant vocal » mis à jour (tranche docs).

---

## 10. Coûts et quotas

- Quotas **inchangés** : 120 tours et 20 min d’audio par jour et par utilisateur, 60 s par tour. Un dossier complet à la voix : ≈ 40–55 tours (V1 en moins, confirmations « oui » locales), ≈ 10–14 min.
- Coût par tour : le catalogue des autres étapes ajoute ≈ 700–1 000 jetons d’entrée (bloc cacheable, statique par étape × type) et ≈ 60 jetons de sortie ; estimation **+15 à +25 % par tour** avec Gemini 3.5 Flash-Lite, compensée par les questions qui ne sont plus reposées. Dossier ≈ **0,07–0,09 $** (contre 0,06–0,08 $). À mesurer au banc (§7) ; si l’écart dépasse +30 %, option Q14 (b).
- Voix par défaut ⇒ davantage de vendeurs utilisent la voix : suivi par `agent_step_stats` (sessions par étape) ; règle de réévaluation EPIC-14 inchangée, + seuil `pending_accept_rate` < 70 % (trop de faux pré-remplissages) → banc sur l’étape source.

---

## 11. Risques et parades

| Risque | Effet | Parade |
|---|---|---|
| Faux pré-remplissage (une phrase mal classée vers une autre étape) | valeur fausse proposée | validation par la définition de l’étape cible (ancres, bornes, codes du type), badge « À confirmer », jamais appliqué sans geste, citation visible au toucher du badge, suivi `pending_accept_rate` |
| « Continuer » machinal qui valide sans lire | valeur pré-remplie acceptée sans être vue | badge très visible, intro de la feuille qui énonce les valeurs (et la première réplique parlée), l’expert voit `dicte_autre_etape` + citation ; option : exiger un geste par valeur (non retenu, friction) |
| Mise à jour d’une étape validée par erreur | donnée déjà vérifiée écrasée | confirmation explicite « a → b », écart fort signalé (règle EPIC-14), entités jamais écrites depuis la feuille |
| Feuille qui s’ouvre toute seule et agace | abandon, micro non désiré | « Écrire plutôt » mémorisé, pas d’ouverture sur une étape complète, pas d’écoute sans consentement ni permission, bascule après 3 tours vides |
| Permission micro demandée au mauvais moment | refus définitif iOS | écran de consentement (explication) avant la demande système ; refus → mode écrit + bandeau Réglages |
| Données d’identité dans le fil (noms dits en V3…) | RGPD | V1 sans voix, adresse hors modèle et hors journal, contacts masqués, consentement v4, Q9 |
| `field_sources` falsifié par un client modifié | fiche trompeuse | citation et valeur prises dans le journal serveur ; drapeau `verified` |
| Réponses en attente orphelines (changement de type, étape supprimée) | bruit pour l’expert | masquées dans l’app, `expired` à l’envoi, statut visible dans la fiche |
| Coût du prompt (catalogue) | budget | bloc cacheable, catalogue compact, banc, option Q14 (b) |
| Conflits avec EPIC-15 (V5 / V5c, fiche pièce, `rooms`, V7, V8, `property_repository`, ARB) | conflits de fusion | démarrage après fusion d’EPIC-15, tranche 0 de relecture, migration horodatée après `room_photos`, « Ajouter à la description » d’EPIC-15 devient « Ajouter aux notes » dans la tranche V5c |
| Concurrence app / serveur sur `pending_answers` (deux appareils) | double résolution | transitions contrôlées par déclencheur (`pending` seulement), résolution idempotente |
| Maquettes absentes (bouton « Écrire plutôt », badge « À confirmer », notes, carte V7) | allers-retours | composants Night existants, demande d’ajout au canevas, validation sur iPhone |

---

## 12. User stories (détail et statuts dans l’epic)

### US-16.1 · La voix par défaut sur chaque étape
*En tant que vendeur, je veux que chaque étape démarre à la voix pour remplir mon dossier sans taper.*
- [ ] V2 (adresse en dictée), V3, V4b, V5c (dictée si aucune pièce) et V6 s’ouvrent en mode voix quand la voix est disponible pour l’étape et le type, avec l’écoute lancée ; V5 met « Dicter mes pièces » en tête.
- [ ] Pas d’ouverture automatique sur une étape complète, un dossier envoyé, sans consentement, micro refusé, quota épuisé ou hors ligne : formulaire + micro.
- [ ] Le formulaire reste complet et utilisable ; tout peut être saisi à l’écran.

### US-16.2 · « Écrire plutôt », préférence mémorisée
*En tant que vendeur, je veux passer à l’écrit d’un geste et que l’app s’en souvienne.*
- [ ] « Écrire plutôt » ferme la feuille et les étapes suivantes s’ouvrent à l’écrit, sur cet appareil, même après redémarrage.
- [ ] « Répondre à la voix » rétablit le mode voix ; le micro ponctuel ne change pas la préférence.

### US-16.3 · Pas de voix sur V1
*En tant que vendeur, je saisis mes propriétaires à l’écran, sans que leurs noms passent par l’IA.*
- [ ] V1 n’a ni micro ni feuille ; le serveur refuse l’étape `owners`.
- [ ] Le consentement v4 ne mentionne plus les noms ; aucune valeur d’une autre étape n’est pré-remplie en V1.

### US-16.4 · Ce que je dis pour une autre étape est pré-rempli
*En tant que vendeur, je veux ne jamais avoir à redire une information.*
- [ ] « Elle date de 1998, chauffage au gaz » dit en V3 apparaît en V4b pré-rempli avec « À confirmer » ; l’agent ne le redemande pas et propose de confirmer.
- [ ] « Oui » ou « Continuer » l’enregistre ; une valeur modifiée ou effacée à l’écran n’est pas enregistrée telle quelle et la proposition est close.
- [ ] Une pièce, une estimation, un atout ou une note dits ailleurs apparaissent sur leur étape « À confirmer ».
- [ ] Ni adresse, ni parcelle, ni type de bien, ni note secrète, ni rien de V1 n’est pré-rempli.
- [ ] Une nouvelle valeur pour le même champ remplace la précédente ; la croix d’une pastille « Noté pour … » l’annule.

### US-16.5 · Mise à jour d’une étape déjà validée
*En tant que vendeur, je veux corriger à la voix une étape déjà passée, en voyant ce qui change.*
- [ ] Une valeur dite pour une étape validée est proposée « Mettre à jour Contexte · 300 000 → 320 000 € ? Oui · Non » ; « Oui » l’enregistre aussitôt, « Non » l’écarte.
- [ ] Une pièce ou une estimation dite pour une étape validée apparaît « À confirmer » sur cette étape (lien « Voir »).
- [ ] V7 liste les informations encore à confirmer sans bloquer l’envoi ; à l’envoi elles ne sont pas appliquées.

### US-16.6 · Notes complémentaires
*En tant que vendeur, je veux que tout ce que je dis soit gardé, même sans case prévue.*
- [ ] La fiche pièce et le tableau V5c affichent « Notes complémentaires » (600 car.) ; ce qui est dit sur une pièce sans champ y est ajouté.
- [ ] V2, V3, V4b, V5c et V6 ont un champ « Notes complémentaires » (1 000 car.), dicté ou saisi.
- [ ] Une note ne contient que des mots dits (≥ 80 %), aucun chiffre ajouté, ni téléphone ni e-mail ; l’aperçu V8 les affiche.

### US-16.7 · Fil de conversation pour l’expert
*En tant qu’expert, je veux relire l’échange vocal du vendeur.*
- [ ] `staff_voice_thread(<bien>)` rend tous les tours (heure, étape, transcription, réplique, valeurs retenues / en attente / rejetées, annulations), sans données d’identité (pas de V1, adresse non conservée, contacts masqués).
- [ ] Inaccessible aux clients (`authenticated`, `anon`) ; documenté dans un runbook.

### US-16.8 · Fiche de remplissage
*En tant qu’expert, je veux savoir d’où vient chaque valeur du dossier.*
- [ ] `staff_fill_sheet(<bien>)` rend, par champ (bien, pièces, estimations, atouts, notes) : valeur, source (dicté / dicté autre étape / saisi / extrait / externe / non tracé), citation, tour, heures, confirmé ou non, vérifié.
- [ ] Les réponses en attente non acceptées y figurent avec leur statut (rejetée, remplacée, expirée).
- [ ] Les colonnes sont documentées comme contrat pour EPIC-12.

### US-16.9 · Coût et qualité suivis
*En tant que porteur de projet, je veux mesurer l’effet de la voix par défaut et du pré-remplissage.*
- [ ] `agent_step_stats` ajoute le nombre de réponses inter-étapes, le taux d’acceptation et le nombre de notes.
- [ ] Banc rejoué avec 16 nouvelles phrases ; quotas et modèles inchangés sauf décision.

---

## 13. Découpage (tranches de 1 à 2 h, un agent codeur chacune)

Prérequis : **EPIC-15 fusionné dans `main`**, puis `main` fusionné dans `feat/epic-16-voix-prioritaire`.

| # | Tranche | Fichiers possédés (exclusifs) | Dépend de |
|---|---|---|---|
| T0 | **Remise à niveau** : relire le code fusionné d’EPIC-15 (V5 / V5c, fiche pièce, `rooms`, V7, V8, repository), noms réels des contraintes, horodatage de la migration ; corriger ce plan ; journal | `docs/plans/2026-10-03-voix-prioritaire.md` | EPIC-15 fusionné |
| T1 | **Migration** `voix_prioritaire` (§6 : colonnes, `pending_answers` + RLS + déclencheurs + `agent_record_pending`, `dossier_field_catalog` + seed, `staff_voice_thread`, `staff_fill_sheet`, statistiques) ; sonde, dry-run, push | `supabase/migrations/<ts>_voix_prioritaire.sql` | T0 |
| T2 | **Registre serveur** : retrait d’`owners` (étape, entité, identité), `crossStepTargets`, schéma de sortie `cross_step` / `notes`, defaults ; tests | `supabase/functions/_shared/agent/steps/**`, `…/agent/schema.ts`, `…/agent/defaults.ts`, `supabase/functions/tests/agent_schema*`, `…/tests/agent_steps*` | T0 |
| T3 | **`property_repository`** : `PendingAnswer` + API, `stepNotes`, `fieldSources`, sources des estimations, longueur des notes de pièce ; tests 100 % | `packages/property_repository/**` | T0 |
| T4 | **Validation** : `validateCrossStep`, `validateNotes`, `evidence`, `maskContacts` ; tests | `…/agent/validate.ts`, `…/agent/anchors.ts`, `…/agent/rooms.ts`, `supabase/functions/tests/agent_validate*`, `…/tests/anchors*` | T2 |
| T5 | **Handlers / prompt / db** : réponses en attente (lecture, `recordPending`), catalogue en bloc cacheable, valeurs pré-remplies au prompt, masquage, refus `owners`, réponse étendue ; fixture de parité ; déploiement des trois fonctions | `…/agent/handlers.ts`, `prompt.ts`, `db.ts`, `supabase_db.ts`, `config.ts`, `supabase/functions/agent-*/**`, `supabase/functions/tests/fixtures/**`, `…/tests/agent_handlers*`, `…/tests/agent_prompt*` | T1, T4 |
| T6 | **`agent_repository`** : `crossStep`, `notes`, `supersededIds`, `evidenceKeys`, retrait d’`owners` / co-propriétaire ; tests | `packages/agent_repository/**` | contrats figés en T5 |
| T7 | **Cœur voix app** : `VoicePreferences.inputMode`, consentement v4, `VoiceFirstLauncher`, `StepVoiceSheet` (« Écrire plutôt », intro « déjà noté », pastilles « Noté pour … », confirmations de mise à jour, « oui » sur les pré-remplis), `VoiceFormMixin` (origines, notes), `ToConfirmTag` ; profil (`_voicedSteps`, `prefillTargets`) ; l10n `voiceFirst*`, `prefill*` | `lib/seller_tunnel/voice/**`, `lib/seller_tunnel/models/property_type_profile.dart` (+ tests) | T6 |
| T8 | **Tunnel** : `SellerTunnelCubit` / state (réponses en attente, mise à jour d’une étape validée, résolution, `field_sources`) ; `StepNotesField`, `AgentActionBar` (« Répondre à la voix ») ; l10n `stepNotes*` | `lib/seller_tunnel/cubit/**`, `lib/seller_tunnel/widgets/**`, `lib/seller_tunnel/view/**` | T3, T7 |
| T9 | **V1** : retrait de la voix (page, cubit, l10n `ownersVoice*`) | `lib/seller_tunnel/steps/owners/**` | T7 |
| T10 | **V2** : dictée d’adresse d’emblée, feuille après les parcelles, pré-remplissage situations, notes | `lib/seller_tunnel/steps/location/**` | T8 |
| T11 | **V3** : feuille d’emblée, pré-remplissage (champs + estimations), notes | `lib/seller_tunnel/steps/property_context/**` | T8 |
| T12 | **V4b** : feuille d’emblée, pré-remplissage, notes ; V4 Night inchangé | `lib/seller_tunnel/steps/technical/**`, `lib/seller_tunnel/steps/voice_audit/**` | T8 |
| T13 | **V5 / V5c** : carte en tête, dictée d’emblée, pièces « À confirmer », « Notes complémentaires » (fiche, tableau, 600 ; « Ajouter aux notes » d’EPIC-15), notes générales | `lib/seller_tunnel/steps/method/**`, `lib/seller_tunnel/steps/surfaces/**`, `lib/seller_tunnel/photos/**` (libellé seulement) | T8 |
| T14 | **V6, V7, V8** : feuille d’emblée V6 + pré-remplissage (bruit, vis-à-vis, atouts), carte V7 « à confirmer », aperçu V8 (notes) | `lib/seller_tunnel/steps/lifestyle/**`, `lib/seller_tunnel/steps/documents/**`, `lib/seller_tunnel/steps/submitted/**` | T8 |
| T15 | **Banc** : 16 phrases enregistrées sur l’iPhone, rapport (justesse, faux pré-remplissages, coût) | `supabase/bench/**` | T5 |
| T16 | **Docs & vérification** : epic, plan (journal), `CLAUDE.md` (voix prioritaire, pré-remplissage, fiche), runbooks `fiche-de-remplissage.md` + `certifier-un-dossier.md` + `suivi-voix.md`, spec du tunnel, politique de confidentialité, `decisions.md` ; test iPhone de bout en bout (parcours voix complet, « Écrire plutôt », pré-remplissage V3 → V4b → V6, fiche dans l’éditeur SQL) | `docs/**`, `CLAUDE.md` | toutes |

Vagues : **0** = T0 · **1** = T1, T2, T3 · **2** = T4 · **3** = T5 · **4** = T6, T15 · **5** = T7 · **6** = T8, T9 · **7** = T10, T11, T12, T13, T14 (dossiers disjoints) · **8** = T16.

ARB : lecture-modification-écriture JSON puis `flutter gen-l10n` immédiatement ; dans les vagues 5 à 7, **une seule tranche écrit `lib/l10n/arb/*` à la fois** (ordre T7 → T8 → T9 → T10 → T11 → T12 → T13 → T14), préfixes distincts. `test/app/view/app_test.dart` (parcours V1 → V8) et `test/helpers/**` : modifiés par T8 seulement (les autres tranches signalent leurs besoins). Chaque tranche est contrôlée par un agent indépendant (tests 100 %, revue, rendu 390 × 844) avant commit.

---

## 14. Hors périmètre

- Back-office expert (EPIC-12) : seulement les fonctions `staff_*` et le runbook.
- Panneau vocal ancré non modal (Q1 b), conversation unique sur tout le tunnel.
- Pré-remplissage de l’adresse, des parcelles, du type de bien et de V1.
- Voix sur V7, barge-in, reconnaissance sur l’appareil.
- Réponses en attente venant des photos ou du plan (EPIC-15 garde ses suggestions dans son écran).

---

## 15. Questions ouvertes (porteur de projet)

1. **Forme du mode voix** : (a) **la feuille vocale modale d’EPIC-14 s’ouvre d’elle-même, « Écrire plutôt » la ferme** (proposé : réutilise l’existant, l’annulation par rejeu reste sûre) ; (b) panneau vocal ancré non modal, formulaire éditable en même temps (meilleure visibilité, ≈ +2 tranches, annulation à revoir) ; (c) (a) maintenant, (b) après les tests.
2. **Démarrage de l’écoute** : (a) **automatique à l’ouverture si consentement et micro acquis, sauf étape complète** (proposé) ; (b) feuille ouverte, écoute au toucher de l’orbe ; (c) automatique partout, même en revisite.
3. **Portée de la préférence « Écrire plutôt »** : (a) **globale à l’appareil** (proposé) ; (b) par étape ; (c) par bien.
4. **Étape déjà validée** : (a) **champs : confirmation « a → b » dans la feuille, enregistrée au « Oui » ; entités : « À confirmer » sur l’étape** (proposé) ; (b) toujours en attente, confirmée en retournant sur l’étape ; (c) pas de pré-remplissage vers une étape validée.
5. **Réponses non confirmées à l’envoi** : (a) **carte non bloquante en V7, expirées à l’envoi, visibles par l’expert comme « non confirmées »** (proposé) ; (b) envoi bloqué tant qu’il en reste ; (c) écartées sans trace.
6. **V1 comme cible** : (a) **rien de V1 n’est pré-rempli** (proposé, cohérent avec « pas de voix sur V1 ») ; (b) seulement « un seul / plusieurs propriétaires » (sans nom). **6 bis — type de bien** : (a) **jamais pré-rempli** (structurant, choisi en V3) (proposé) ; (b) pré-rempli « À confirmer » s’il n’est pas encore choisi.
7. **Notes complémentaires** : (a) **notes de pièce (600 car.) + une note par étape V2, V3, V4b, V5c, V6 (1 000 car.)** (proposé) ; (b) notes de pièce seulement ; (c) une seule note globale du dossier.
8. **Colonne des notes de pièce** : (a) **garder `rooms.description`, libellé « Notes complémentaires »** (proposé : pas de conflit avec EPIC-15) ; (b) renommer la colonne en `notes`.
9. **Noms de personnes dits hors V1** (« avec mon frère Marc… ») dans le fil conservé : (a) **transcriptions gardées, téléphones / e-mails masqués, consigne « aucun nom » dans les notes** (proposé) ; (b) masquage automatique des noms propres (masque aussi des noms de lieux utiles à l’expert) ; (c) pas de transcription pour l’expert, seulement les citations retenues.
10. **Conservation du fil et des réponses en attente** : (a) **durée de vie du dossier (supprimés avec le bien)** (proposé) ; (b) purge 12 mois après la certification ou l’abandon.
11. **Sources de la fiche** : (a) **dicté · dicté autre étape · saisi · extrait · externe · non tracé** (proposé) ; (b) dicté / saisi / extrait / externe seulement (le pré-remplissage fusionné avec « dicté »).
12. **Accès expert avant EPIC-12** : (a) **fonctions `staff_*` dans l’éditeur SQL + runbook** (proposé) ; (b) en plus, export PDF de la fiche joint au dossier à l’envoi.
13. **Confiance moyenne (0,5–0,7) en inter-étapes** : (a) **stockée avec « ? » dans la pastille, confirmée comme les autres** (proposé) ; (b) rejetée (seulement ≥ 0,7).
14. **Coût du catalogue au prompt** : (a) **catalogue compact des autres étapes dans un bloc cacheable** (proposé, +15–25 % par tour, à mesurer) ; (b) le modèle renvoie le texte dit et le serveur déduit le code par les ancres lexicales (prompt plus court, moins de champs reconnus) ; (c) inter-étapes limité aux champs numériques et aux notes.

---

## Journal d’exécution

- 2026-10-03 : plan rédigé (aucun code), EPIC-16 créé ; en attente des arbitrages (§15) et de la fusion d’EPIC-15.
