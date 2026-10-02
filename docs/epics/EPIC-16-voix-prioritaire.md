# EPIC-16 · Voix prioritaire

**Objectif** : faire de la voix le mode d’entrée par défaut du tunnel vendeur (V2 → V6), sans voix sur V1, en pré-remplissant sur leur étape les informations dites ailleurs (badge « À confirmer », jamais appliquées sans geste du vendeur), en gardant dans des « Notes complémentaires » tout ce qui n’a pas de champ, et en donnant à l’expert le fil de conversation et une fiche de remplissage (valeur, source, phrase d’origine, tour, heure, confirmée ou non).
**Statut** : 📋 À faire — plan rédigé, questions ouvertes ; à coder après la fusion d’EPIC-15 (photos du bien).

Plan : [Voix prioritaire](../plans/2026-10-03-voix-prioritaire.md).

Décisions du porteur de projet (2026-10-02, [`decisions.md`](../decisions.md)) : « Voix (suite EPIC-14) » et « Pré-remplissage inter-étapes par la voix ». Inchangés : confirmations des seuls changements risqués, modèles les moins chers, quotas 120 tours / 20 min, « 4 sur 3 » calculé, pas de micro en V7, voix pour tous les types, agent silencieux pendant la dictée des pièces.

Légende : ✅ fait · 🚧 partiel · 📋 à faire

## US-16.1 · La voix par défaut sur chaque étape 📋
*En tant que vendeur, je veux que chaque étape démarre à la voix pour remplir mon dossier sans taper.*
- 📋 V2 (adresse en dictée), V3, V4b, V5c (dictée si aucune pièce) et V6 s’ouvrent en mode voix quand la voix est disponible pour l’étape et le type, avec l’écoute lancée ; V5 met « Dicter mes pièces » en tête.
- 📋 Pas d’ouverture automatique sur une étape complète, un dossier envoyé, sans consentement, micro refusé, quota épuisé ou hors ligne : formulaire + micro.
- 📋 Le formulaire reste complet et utilisable ; tout peut être saisi à l’écran.

## US-16.2 · « Écrire plutôt », préférence mémorisée 📋
*En tant que vendeur, je veux passer à l’écrit d’un geste et que l’app s’en souvienne.*
- 📋 « Écrire plutôt » ferme la feuille et les étapes suivantes s’ouvrent à l’écrit, sur cet appareil, même après redémarrage.
- 📋 « Répondre à la voix » rétablit le mode voix ; le micro ponctuel ne change pas la préférence.

## US-16.3 · Pas de voix sur V1 📋
*En tant que vendeur, je saisis mes propriétaires à l’écran, sans que leurs noms passent par l’IA.*
- 📋 V1 n’a ni micro ni feuille ; le serveur refuse l’étape `owners`.
- 📋 Le consentement v4 ne mentionne plus les noms ; aucune valeur d’une autre étape n’est pré-remplie en V1.

## US-16.4 · Ce que je dis pour une autre étape est pré-rempli 📋
*En tant que vendeur, je veux ne jamais avoir à redire une information.*
- 📋 « Elle date de 1998, chauffage au gaz » dit en V3 apparaît en V4b pré-rempli avec « À confirmer » ; l’agent ne le redemande pas et propose de confirmer.
- 📋 « Oui » ou « Continuer » l’enregistre ; une valeur modifiée ou effacée à l’écran n’est pas enregistrée telle quelle et la proposition est close.
- 📋 Une pièce, une estimation, un atout ou une note dits ailleurs apparaissent sur leur étape « À confirmer ».
- 📋 Ni adresse, ni parcelle, ni type de bien, ni note secrète, ni rien de V1 n’est pré-rempli.
- 📋 Une nouvelle valeur pour le même champ remplace la précédente ; la croix d’une pastille « Noté pour … » l’annule.

## US-16.5 · Mise à jour d’une étape déjà validée 📋
*En tant que vendeur, je veux corriger à la voix une étape déjà passée, en voyant ce qui change.*
- 📋 Une valeur dite pour une étape validée est proposée « Mettre à jour Contexte · 300 000 → 320 000 € ? Oui · Non » ; « Oui » l’enregistre aussitôt, « Non » l’écarte.
- 📋 Une pièce ou une estimation dite pour une étape validée apparaît « À confirmer » sur cette étape (lien « Voir »).
- 📋 V7 liste les informations encore à confirmer sans bloquer l’envoi ; à l’envoi elles ne sont pas appliquées.

## US-16.6 · Notes complémentaires 📋
*En tant que vendeur, je veux que tout ce que je dis soit gardé, même sans case prévue.*
- 📋 La fiche pièce et le tableau V5c affichent « Notes complémentaires » (600 car.) ; ce qui est dit sur une pièce sans champ y est ajouté.
- 📋 V2, V3, V4b, V5c et V6 ont un champ « Notes complémentaires » (1 000 car.), dicté ou saisi.
- 📋 Une note ne contient que des mots dits (≥ 80 %), aucun chiffre ajouté, ni téléphone ni e-mail ; l’aperçu V8 les affiche.

## US-16.7 · Fil de conversation pour l’expert 📋
*En tant qu’expert, je veux relire l’échange vocal du vendeur.*
- 📋 `staff_voice_thread(<bien>)` rend tous les tours (heure, étape, transcription, réplique, valeurs retenues / en attente / rejetées, annulations), sans données d’identité (pas de V1, adresse non conservée, contacts masqués).
- 📋 Inaccessible aux clients (`authenticated`, `anon`) ; documenté dans un runbook.

## US-16.8 · Fiche de remplissage 📋
*En tant qu’expert, je veux savoir d’où vient chaque valeur du dossier.*
- 📋 `staff_fill_sheet(<bien>)` rend, par champ (bien, pièces, estimations, atouts, notes) : valeur, source (dicté / dicté autre étape / saisi / extrait / externe / non tracé), citation, tour, heures, confirmé ou non, vérifié.
- 📋 Les réponses en attente non acceptées y figurent avec leur statut (rejetée, remplacée, expirée).
- 📋 Les colonnes sont documentées comme contrat pour EPIC-12 (back-office expert).

## US-16.9 · Coût et qualité suivis 📋
*En tant que porteur de projet, je veux mesurer l’effet de la voix par défaut et du pré-remplissage.*
- 📋 `agent_step_stats` ajoute le nombre de réponses inter-étapes, le taux d’acceptation et le nombre de notes.
- 📋 Banc rejoué avec 16 nouvelles phrases ; quotas et modèles inchangés sauf décision.
