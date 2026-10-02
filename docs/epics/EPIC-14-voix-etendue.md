# EPIC-14 · Voix étendue à tout le tunnel vendeur

**Objectif** : permettre au vendeur de renseigner à la voix un maximum de champs du tunnel (V1 → V6), étape par étape, y compris en dictant ses pièces et leur description en V5c, avec plusieurs réponses par phrase et des corrections à la voix, sans perdre les garde-fous d’EPIC-06 (citation littérale, liste blanche, validation serveur, l’app seule écrit le dossier).
**Statut** : 🚧 Implémenté avec les **choix par défaut** (option recommandée de chaque question, plan §14) en attendant les arbitrages du porteur de projet ; reste le banc d’essai enregistré sur l’iPhone (US-14.9) et le test de bout en bout sur l’iPhone.

Plan : [Voix étendue à tout le tunnel](../plans/2026-10-02-voix-etendue.md).

Demande du porteur de projet (2026-10-02) : « le vocal avec l’agent IA doit pouvoir permettre de renseigner un maximum de champs dans ce tunnel — par exemple l’utilisateur doit pouvoir dicter les descriptions des pièces et éviter la saisie manuelle. »

Légende : ✅ fait · 🚧 partiel · 📋 à faire

## US-14.1 · Un micro sur chaque étape ✅
*En tant que vendeur, je veux pouvoir répondre à la voix sur n’importe quelle étape, pour éviter de taper.*
- ✅ Le micro apparaît sur V1, V2, V3, V4b, V5c et V6 quand l’étape a des champs dictables pour le type du bien (`PropertyTypeProfile.voiceSteps`) et que la voix est disponible ; jamais sur V7, ni sur un dossier envoyé (verrou serveur).
- ✅ Il ouvre une feuille vocale propre à l’étape (`StepVoiceSheet`), avec une intro qui dit ce qu’on peut dicter.
- ✅ Ce que l’agent retient apparaît en pastilles et dans le formulaire (étiquette « Dicté »), sans être enregistré avant « Continuer ».
- ✅ Le formulaire reste utilisable ; fermer la feuille ne perd rien (instantané « N réponses ajoutées · Annuler »).

## US-14.2 · Plusieurs réponses en une phrase ✅
*En tant que vendeur, je veux tout dire d’un trait.*
- ✅ « Achetée 320 000 € en 2012, pour une mutation, jamais estimée » remplit les quatre champs de V3.
- ✅ Chaque valeur retenue a une citation littérale et une ancre (nombre, y compris écrit en lettres, ou mot-clé) dans ma phrase ; sinon elle devient une question.
- ✅ Une information d’une autre étape n’est pas écrite ; l’agent dit où elle sera demandée (pastille grise « Construction → Technique »).

## US-14.3 · Dictée de pièces ✅
*En tant que vendeur, je veux décrire mes pièces une par une à voix haute pour remplir le tableau des surfaces.*
- ✅ V5 propose « Dicter mes pièces » ; V5c ouvre la dictée par le micro.
- ✅ « Le séjour fait 38 m² au rez-de-chaussée, parquet chêne, double vitrage » crée la pièce avec ces cinq valeurs ; plusieurs pièces dans une phrase créent plusieurs lignes ; les chambres sont numérotées ; « 4 sur 3 » donne 12 m².
- ✅ Un niveau non dit reprend celui de la pièce précédente (affiché, modifiable), jamais inventé.
- ✅ L’écoute reprend aussitôt après chaque pièce (agent silencieux, vibration) ; la liste des pièces dictées et le total habitable sont visibles.
- ✅ « Terminer » : récapitulatif parlé (« J’ai noté 9 pièces pour 115 m² habitables. Est-ce correct ? »), « oui » ferme, « non » reprend.
- ✅ Les pièces dictées sont enregistrées au « Tout est correct, continuer » (`source = voice`) ; surface habitable et annexes recalculées comme à l’écran.

## US-14.4 · Description des pièces ✅
*En tant que vendeur, je veux dicter ce qui caractérise chaque pièce.*
- ✅ Chaque pièce a une description facultative (300 caractères), dictée ou saisie dans la fiche pièce.
- ✅ La description ne contient que ce que j’ai dit (≥ 80 % de mots dits, aucun chiffre ajouté, ni téléphone ni e-mail) ; elle apparaît dans le tableau V5c et l’aperçu des données.

## US-14.5 · Corriger et annuler à la voix ✅
*En tant que vendeur, je veux corriger l’agent sans toucher l’écran.*
- ✅ « Non, plutôt 40 m² » remplace la dernière valeur concernée, signalée « corrigé ».
- ✅ « Annule » annule le dernier tour ; chaque pastille a sa croix ; « Annuler » après fermeture annule toute la session.
- ✅ Une valeur dictée qui remplace une valeur existante s’affiche « a → b » ; un écart fort demande confirmation.

## US-14.6 · Confirmer ce qui compte ✅
*En tant que vendeur, je veux que l’agent me demande confirmation avant un changement important.*
- ✅ Changement de type, suppression (pièce, estimation), co-propriétaire dicté, confiance moyenne, pièce redictée : « Est-ce correct ? » avec Oui / Non touchables ou dits ; une pièce ambiguë est redemandée. La suppression d’un co-propriétaire reste à l’écran (ses noms ne sont jamais envoyés à l’IA).
- ✅ « Oui », « non », « annule », « terminé » sont reconnus sans attendre l’agent.

## US-14.7 · Propriétaires et adresse à la voix ✅
*En tant que vendeur, je veux dicter qui possède le bien et son adresse, sans exposer mes coordonnées.*
- ✅ V1 : nombre de propriétaires et noms des co-propriétaires dictables (Q1 (b) par défaut), toujours confirmés ; téléphone et e-mail à l’écran (« À compléter : téléphone »).
- ✅ V2 : l’adresse dictée remplit le champ de recherche, je choisis la suggestion ; les parcelles restent sur la carte ; les servitudes sont dictables.
- ✅ Noms et adresse dictés non conservés dans l’historique de l’agent ; l’adresse n’est jamais envoyée au modèle de langage (consentement v3).

## US-14.8 · Contexte et technique pour tous les types ✅
*En tant que vendeur d’un garage, d’un terrain ou d’un local, je veux aussi répondre à la voix.*
- ✅ V3 et V4b dictables pour les 8 types, avec leurs champs EPIC-13 (précision du type, surface utile, niveau, équipements).
- ✅ L’audit vocal V4 « Night » reste proposé pour maison, appartement et autre (lien « Conversation guidée » sur V4b).
- ✅ Le serveur refuse une étape non vocale pour le type (parité app / serveur testée).

## US-14.9 · Coût et qualité suivis 🚧
*En tant que porteur de projet, je veux maîtriser le coût et la qualité de la voix étendue.*
- ✅ Coût et qualité par étape et par modèle consultables (vue `agent_step_stats`, runbook `docs/runbooks/suivi-voix.md`) : tours, coût, rejets, annulations, corrections.
- ✅ Le modèle de l’agent peut être changé pour une seule étape par secret (`OPENROUTER_MODEL_AGENT_<ÉTAPE>`), sans republier l’app.
- 📋 Banc étendu (40 phrases enregistrées sur l’iPhone) rejoué avant de fixer les défauts ; quotas inchangés (✅) sauf décision.
