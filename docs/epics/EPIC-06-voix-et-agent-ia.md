# EPIC-06 · Voix et agent IA

**Objectif** : permettre au vendeur de répondre au tunnel à la voix, avec un agent qui pose les questions et remplit le dossier (audit vocal V4, « Parlez librement » V6, micro de la barre d'action), en gardant toujours l'équivalent à l'écran.
**Statut** : 🚧 En cours — banc d'essai fait, chaîne STT → agent → TTS codée et déployée (Edge Functions), écrans V4 / V6 codés ; migration `agent_conversations` écrite mais **pas encore poussée** (à valider), modèles par défaut = les moins chers pour la phase de test (Whisper Turbo, Gemini 3.5 Flash-Lite, Kokoro), à réévaluer ensuite.

Décisions : IA via OpenRouter (clé uniquement en secret Supabase) ; modèles STT / agent / TTS **configurables côté serveur** (`OPENROUTER_MODEL_STT`, `OPENROUTER_MODEL_AGENT`, `OPENROUTER_MODEL_TTS`, `OPENROUTER_TTS_VOICE`) ; **consentement explicite** au premier usage du micro ; mode écran toujours disponible. Plan et banc d'essai : `docs/plans/2026-10-01-voix-et-agent-ia.md`.

Légende : ✅ fait · 🚧 partiel · 📋 à faire

### US-06.1 · Parler à l'agent — 🚧
*En tant que vendeur, je veux répondre à l'agent à la voix, en français.*
- ✅ Écran d'information et de consentement au premier usage (prestataires qui traitent l'audio, aucune conservation de l'audio, pas de données d'identité, mode écran) ; un refus mène au mode écran.
- ✅ Micro demandé ensuite (`NSMicrophoneUsageDescription` en français) ; un refus affiche un message avec un lien Réglages et le mode écran.
- ✅ Fin de phrase détectée après 1,2 s de silence, ou « J'ai fini » ; 60 s au plus par tour.
- 🚧 Transcription en ≈ 0,5 s côté serveur (banc, audio synthétique) : à mesurer sur iPhone en 4G.
- ✅ L'audio n'est conservé ni sur le téléphone (fichier supprimé après lecture) ni sur le serveur (traité en mémoire).
- ✅ Dépendances `record` (BSD-3) et `audioplayers` (MIT) : contrôle de licences vert.

### US-06.2 · Agent qui comprend mes réponses — ✅
*En tant que vendeur, je veux décrire mon bien librement et que l'agent remplisse les bonnes cases.*
- ✅ Seules les informations dites sont retenues : citation littérale vérifiée côté serveur, confiance ≥ 0,7, sinon pastille « … ? ».
- ✅ Validation serveur avec les règles des écrans (codes, bornes, toiture ≥ construction, chambres ≤ pièces, séjour ≤ surface) ; une valeur invalide n'est jamais renvoyée à l'app.
- ✅ Une question à la fois, en vouvoyant (consignes de l'agent).
- ✅ Réponse illisible de l'agent : une nouvelle tentative, puis « Pouvez-vous répéter ? » sans rien retenir.
- 🚧 Dossier envoyé : refus serveur (409) et verrou de l'app (redirection V8) ; RLS des nouvelles tables écrite, migration pas encore poussée.
- ✅ Aucune donnée d'identité envoyée (colonnes lues en liste blanche, note secrète masquée dans le prompt).

### US-06.3 · L'agent me répond à voix haute — ✅
*En tant que vendeur, je veux entendre l'agent pour garder les yeux libres pendant la visite de mon bien.*
- ✅ Réplique lue (TTS configurable), texte toujours affiché.
- ✅ Micro coupé pendant que l'agent parle, écoute relancée ensuite.
- ✅ « Couper la voix de l'agent » (préférence mémorisée sur l'appareil).
- ✅ Une panne de la voix n'interrompt pas la conversation ; un audio tronqué (trop court pour le texte) est remplacé par la réplique en texte seul.

### US-06.4 · Audit technique à la voix (V4) — 🚧
*En tant que vendeur, je veux faire l'audit technique en conversation.*
- ✅ Écran Night : orbe et onde pilotés par le niveau du micro, bulles, pastilles comprises / en attente, progression Night.
- 🚧 Toucher une pastille ouvre V4b pour corriger (pas de mini-fiche dans V4).
- ✅ Pause / reprise ; « Passer », le clavier et « Vérifier mes réponses » ouvrent V4b pré-rempli (réponses enregistrées en « Déclaré »).
- ✅ Reprise après fermeture : l'agent relit le dossier à chaque tour et ne redemande que ce qui manque.
- ✅ Erreurs : message, Réessayer (le tour enregistré est rejoué) ou mode écran.
- ✅ « Importer » un plan le dépose dans le coffre (type plan).
- ✅ V3 « Continuer » ouvre V4 quand la voix est disponible ; micro de V4b → V4. 📋 Segment Voix / Écran de l'en-tête V4b.

### US-06.5 · Cadre de vie dicté (V6) — ✅
*En tant que vendeur, je veux parler librement de mon quartier et que l'agent classe atouts et points de vigilance.*
- ✅ Micro de la barre d'action (« Parlez librement, l'agent classe vos réponses ») → feuille Night d'écoute.
- ✅ Atouts / points de vigilance (140 car., 10 max, sans doublon), étiquette « Ajouté à la voix », modifiables, supprimables, enregistrés à « Continuer » avec la source « voix ».
- ✅ Bruit et vis-à-vis positionnés quand ils sont dits ; note secrète proposée en suggestion (« Utiliser »), jamais imposée.

### US-06.6 · Coûts et suivi — 🚧
*En tant que porteur de projet, je veux maîtriser le coût et la qualité de la voix et de l'agent.*
- ✅ Banc d'essai reproductible (`supabase/functions/_bench`) : latence, coût, exactitude d'extraction par modèle.
- ✅ Journal par tour (`agent_turns`) : modèles, secondes d'audio, jetons, latences, coût `usage.cost` STT + agent (le coût TTS n'est pas renvoyé par OpenRouter).
- ✅ Quotas : 120 tours et 20 min d'audio par utilisateur et par jour (429).
- ✅ Modèles et voix changeables par secret Supabase ; voix activée par flavor (`VOICE_ENABLED`, développement seulement).
- 📋 Purge à 90 jours des tours (décision Q5 en attente).
