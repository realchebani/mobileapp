# EPIC-06 · Voix + agent IA du tunnel vendeur — étude & conception

Statut : proposition (aucun code écrit). Rédigé le 2026-10-01 à partir de `CLAUDE.md`, du plan et de la spec du tunnel (§0.2–0.3, V4, V4b, V6), des migrations, du code (`AgentActionBar.voiceEnabled = false`, `Provenance`, `LifestyleCubit`, `TechnicalCubit`, `SellerTunnelCubit.save`) et des maquettes `AuditVocalTechnique.dc.html` (V4) et `AuditVie.dc.html` (V6).

Décisions du porteur de projet : voix + agent = chantier dédié ; **toute l’IA passe par OpenRouter** (clé en secret Supabase `OPENROUTER_API_KEY`, présence vérifiée avec `supabase secrets list`) ; raisonnement avec Claude ; **reconnaissance vocale (STT) et synthèse vocale (TTS) par des modèles peu coûteux d’OpenRouter** plutôt que la reconnaissance sur l’iPhone (mise à jour du 2026-10-01).

Périmètre proposé pour EPIC-06 v1 : **V4 audit vocal technique** (écran Night), **V6 « Parlez librement »**, **micro de l’`AgentActionBar`** sur V4b (ouvre V4) et V6, **voix de l’agent** (TTS). Hors v1 : dictée sur V1 (données personnelles), V2, V5c (phase 2), agent « Une question ? », interruption de l’agent pendant qu’il parle (*barge-in*), temps réel (WebSocket).

---

## 1. Audio via OpenRouter — relevé du 2026-10-01

### 1.1 Ce qu’offre OpenRouter (docs `openrouter.ai/docs/llms.txt`, API `GET /api/v1/models`)
| Besoin | Point d’entrée | Envoi / retour | Notes |
|---|---|---|---|
| **STT** | `POST /api/v1/audio/transcriptions` | JSON `{model, input_audio: {data: <base64 brut>, format: "wav"|"mp3"|"flac"|"m4a"|"ogg"|"webm"|"aac"}, language: "fr", temperature}` (ou multipart OpenAI, 25 Mo max) → `{text, usage: {seconds, cost}}` ; `verbose_json` → segments / mots horodatés | Découverte : `GET /api/v1/models?output_modalities=transcription`. Tarif **à la seconde** d’audio (Whisper, Voxtral…) ou au jeton (gpt-4o-*-transcribe, Gemini Transcribe). **Les préférences de routage (`order`, `only`, `ignore`) ne s’appliquent pas aux transcriptions** (on ne peut pas imposer un fournisseur UE). Options fournisseur via `provider.options.<slug>` (ex. `prompt` de vocabulaire chez Groq). Les fournisseurs coupent à ~60 s de traitement : découper. |
| **TTS** | `POST /api/v1/audio/speech` (compatible OpenAI) | JSON `{model, input (≤ 3 000 car.), voice, response_format: "mp3"|"pcm" (défaut pcm), speed}` → **flux d’octets audio brut** (`audio/mpeg` ou `audio/pcm`), en-tête `X-Generation-Id` | Découverte : `?output_modalities=speech`. Tarif **au caractère** (la plupart) ou au jeton audio (Gemini TTS). Gemini 3.8 TTS lit le texte tel quel (consignes de style via `provider.options` `speech_metadata`). |
| Audio dans le chat (un seul modèle écoute + raisonne) | `POST /api/v1/chat/completions` avec un bloc `{type: "input_audio", input_audio: {data, format}}` | base64 obligatoire (pas d’URL) ; formats courants wav, mp3, aiff, aac, ogg, flac, m4a, pcm16, pcm24 | **Aucun modèle Claude n’accepte l’audio** sur OpenRouter (modalités d’entrée texte/image/fichier). Modèles audio → texte avec sortie structurée : Gemini 3.x Flash / Flash-Lite, Qwen3.8 Omni Flash, Xiaomi MiMo v2.6, Voxtral Small… ; audio → audio : `openai/gpt-audio(-mini)` (sortie audio en flux). |

### 1.2 STT — modèles relevés (prix OpenRouter, convertis par minute d’audio)
| Modèle | Prix | Français / remarques |
|---|---|---|
| `openai/whisper-large-v3-turbo` (DeepInfra US, Groq) | **0,0002 $/min** (DeepInfra) – 0,0007 $/min (Groq) | Multilingue correct en français ; vocabulaire du bâtiment à vérifier ; très rapide chez Groq. **Le moins cher.** |
| `qwen/qwen3-asr-0.6b`, `nvidia/nemotron-3.5-asr-streaming-multilingual-0.6b` | 0,0002 $/min | Petits modèles ; français à tester. |
| `openai/whisper-large-v3`, `qwen/qwen3-asr-1.7b` | 0,00045 $/min | |
| `mistralai/voxtral-mini-3b-2507` | 0,001 $/min | Mistral (français natif). |
| `mistralai/voxtral-mini-transcribe` (Mistral, point UE `mistral/eu` à 0,0033 $/min) | **0,003 $/min** | Modèle de transcription dédié de Mistral, très bon en français ; fournisseur européen. **Recommandé par défaut.** |
| `openai/gpt-4o-mini-transcribe` | 1,25 $ / 5 $ par M jetons (≈ 0,003 $/min) | Bon en français. |
| `openai/gpt-transcribe`, `deepgram/nova-3` | 0,0045 / 0,0043 $/min | |
| `openai/whisper-1`, `fish-audio/transcribe-1` | 0,006 $/min | |
Une session type (~15 min de parole) coûte donc **0,003 $ (Whisper Turbo) à 0,045 $ (Voxtral Mini Transcribe)**.

### 1.3 TTS — modèles relevés
| Modèle | Prix | Français / remarques |
|---|---|---|
| `hexgrad/kokoro-82m` (DeepInfra) | **0,62 $ / M caractères** | 8 langues dont le français (une seule voix française, qualité moyenne). **Le moins cher.** |
| `google/gemini-3.8-flash-lite-tts` | 0,5 $/M jetons texte + 6 $/M jetons audio (≈ 0,009 $/min de parole) | Voix naturelles multilingues, rapide. **Recommandé** (bon rapport qualité/prix). |
| `google/gemini-3.8-flash-tts` | 0,5 $ + 9 $/M jetons audio | Plus expressif. |
| `mistralai/voxtral-mini-tts-2603` | 16 $/M car. | Français natif, clonage de voix (une « voix Realesty »). |
| `fish-audio/s2.1-pro`, `qwen/qwen-audio-3.0-tts-flash`, `x-ai/grok-voice-tts-1.0`, `microsoft/mai-voice-2-flash` | 15 $/M car. | Multilingues. |
| `deepgram/aura-2` 30 $, `minimax/speech-2.8-turbo` 60 $, `-hd` 100 $/M car. | | Plus chers. |
Une session (≈ 45 répliques de ~120 caractères, ~5 min de voix) : **0,003 $ (Kokoro)**, **≈ 0,05 $ (Gemini 3.8 Flash Lite TTS)**, ≈ 0,08 $ (Voxtral TTS / 15 $/M car.).

### 1.4 Les deux architectures possibles
**Option 1 (recommandée) — STT puis Claude puis TTS**
`agent-transcribe` (Voxtral Mini Transcribe) → `agent-turn` (Claude, texte, sortie JSON stricte) → `agent-speech` (Gemini 3.8 Flash Lite TTS, mp3).
- + Extraction fiable (Claude), transcription explicite affichée et vérifiable (contrôle des citations littérales), chaque brique remplaçable, `agent-turn` réutilisable pour une saisie au clavier.
- − 3 appels, latence plus élevée.

**Option 2 — un seul modèle multimodal écoute et raisonne** (ex. `google/gemini-3.1-flash-lite` : audio 0,5 $/M jetons, texte 0,25 $ / 1,5 $ ; ou `google/gemini-3.5-flash-lite`, `qwen/qwen3.8-omni-flash`), puis TTS.
- + Un appel de moins (≈ 1–2 s gagnées), coût le plus bas.
- − Pas Claude (décision du porteur de projet : raisonnement Claude) ; la transcription est produite par le même modèle que l’extraction (le contrôle « citation littérale » perd de sa force) ; extraction structurée moins sûre sur des réponses longues ; audio envoyé à Google.
- Variante tout-audio `openai/gpt-audio-mini` (audio en entrée et en sortie dans un appel en flux) : intéressante pour le temps réel plus tard, non retenue en v1.

**Coût d’une session type** (≈ 15 min de parole utilisateur, ≈ 45 tours, répliques de 120 caractères ; Claude avec ~2,5 k jetons de consignes en cache + ~0,8 k variables + 250 en sortie par tour) :
| Combinaison | STT | Raisonnement | TTS | **Total / session** |
|---|---|---|---|---|
| Opt. 1 · Voxtral Transcribe + **Claude Opus 5.5** + Gemini Flash Lite TTS | 0,045 | 0,39 (0,82 sans cache) | 0,048 | **≈ 0,48 $** |
| Opt. 1 · Voxtral Transcribe + **Claude Sonnet 5.5** + Gemini Flash Lite TTS | 0,045 | 0,21 (0,41) | 0,048 | **≈ 0,30 $** |
| Opt. 1 · Voxtral Transcribe + **Claude Haiku 4.5** + Gemini Flash Lite TTS | 0,045 | 0,10 (0,20) | 0,048 | **≈ 0,20 $** |
| Opt. 1 « au plus bas » · Whisper Turbo + Claude Haiku 4.5 + Kokoro | 0,003 | 0,10 | 0,003 | **≈ 0,11 $** |
| Opt. 2 · Gemini 3.1 Flash-Lite (audio + raisonnement) + Gemini Flash Lite TTS | (inclus) 0,05 | | 0,048 | **≈ 0,10 $** |
| Opt. 2 « au plus bas » · Gemini 3.1 Flash-Lite + Kokoro | 0,05 | | 0,003 | **≈ 0,05 $** |
Tarifs OpenRouter du 2026-10-01 : Claude Opus 5.5 4 $/20 $, Sonnet 5.5 2 $/10 $, Haiku 4.5 1 $/5 $ par M jetons (lecture de cache ≈ 0,20 / 0,20 / 0,10 $). Chiffres à confirmer par `usage.cost` réel (journalisé, §4).

**Recommandation** : Option 1 avec **Voxtral Mini Transcribe** (français, fournisseur Mistral) + **Claude** + **Gemini 3.8 Flash Lite TTS** ; modèle Claude choisi par le porteur de projet (Opus 5.5 ≈ 0,48 $/session, Sonnet 5.5 ≈ 0,30 $, Haiku 4.5 ≈ 0,20 $) — tous les modèles sont des secrets (`OPENROUTER_MODEL_STT`, `OPENROUTER_MODEL_AGENT`, `OPENROUTER_MODEL_TTS`, `OPENROUTER_TTS_VOICE`), changeables sans republier l’app. La tranche A4 inclut un **banc d’essai** (20 phrases réelles enregistrées sur l’iPhone, vocabulaire du bâtiment, bruit de fond) pour comparer Voxtral / Whisper Turbo / gpt-4o-mini-transcribe et Kokoro / Gemini TTS avant de figer les défauts. L’option 2 reste un repli « économique » si le coût Claude devient un problème.

### 1.5 Latence visée par tour (Option 1)
fin de parole détectée (1,2 s de silence) → envoi (~80 Ko en 4G : 0,2–0,4 s) → **STT** 0,5–1,5 s (bulle utilisateur affichée) → **Claude** 1,5–4 s selon le modèle (bulle agent + pastilles affichées) → **TTS** 0,6–1,5 s (voix) ≈ **3–7 s** jusqu’à la voix, texte visible ~1 s plus tôt. Pas de streaming en v1 (le JSON d’extraction doit être validé en entier) ; optimisations ultérieures : TTS en `pcm` en flux, réplique en SSE avant l’extraction. Option 2 : ≈ 2–4 s.

---

## 2. Côté iPhone : enregistrement et lecture

### 2.1 Enregistrement : `record` 7.1.1 (BSD-3-Clause)
- Dépendances (vérifiées récursivement sur pub.dev) : `record_android`, `record_ios`, `record_linux`, `record_macos`, `record_web`, `record_windows`, `record_platform_interface`, `plugin_platform_interface`, `meta`, `web` — **toutes BSD-3** → conforme au contrôle de licences (MIT/BSD/Apache), aucune exclusion.
- Configuration : `RecordConfig(encoder: AudioEncoder.aacLc, sampleRate: 16000, numChannels: 1, bitRate: 32000)` → fichier `.m4a` temporaire (≈ 4 Ko/s : 20 s ≈ 80 Ko, ≈ 107 Ko en base64) ; format `m4a` accepté par l’endpoint STT. Durée max d’un tour : 60 s (arrêt automatique, limite fournisseurs).
- `onAmplitudeChanged(Duration(milliseconds: 80))` → niveau en dB pour l’orbe et les barres d’onde, **et** détection de fin de parole maison (parole détectée puis < −45 dB pendant 1,2 s → arrêt et envoi) ; bouton « J’ai fini » pour forcer.
- iOS : seulement `NSMicrophoneUsageDescription` (+ `InfoPlist.strings` fr/en/es) ; plus de permission de reconnaissance vocale. Le fichier est supprimé après envoi.

### 2.2 Lecture : `audioplayers` 6.8.1 (MIT)
- 44 dépendances transitives toutes MIT / BSD-3 / Apache-2.0 (vérifié). Alternative `just_audio` 0.10.6 (MIT/Apache, 39 dépendances, toutes autorisées) — plus lourde, inutile ici.
- Le mp3 reçu est écrit dans le dossier temporaire puis lu (`DeviceFileSource`) ; `AudioContext` iOS en `playAndRecord` + `defaultToSpeaker` pour ne pas casser la session audio de `record`. **Micro coupé pendant que l’agent parle** (pas d’écho, pas de barge-in en v1). Bouton « couper le son de l’agent » (préférence locale) : l’agent écrit seulement.

### 2.3 Abstraction testable
`packages/voice_repository` (nouveau package Dart) : `VoiceRecorder` (`Future<bool> requestPermission()`, `Stream<double> levels`, `Future<void> start()`, `Future<RecordedAudio?> stop()` → octets + format + durée, détection de silence configurable) et `VoicePlayer` (`Future<void> play(Uint8List mp3)`, `stop()`, `Stream<bool> isPlaying`). Seuls deux fichiers importent `record` / `audioplayers` ; cubits et tests utilisent des faux. Job CI `dart_package` à ajouter.

---

## 3. Edge Functions

### 3.1 Vue d’ensemble (Option 1)
```
App ── m4a base64 ──► agent-transcribe ──► OpenRouter /audio/transcriptions (Voxtral) ──► {transcript}
App ── transcript ──► agent-turn ──► OpenRouter /chat/completions (Claude, JSON strict)
                       └─ lit le dossier (JWT, RLS), valide, journalise ─► {reply_fr, patch, facts, pending, …, turn_id}
App ── turn_id ─────► agent-speech ──► OpenRouter /audio/speech (Gemini TTS, mp3) ──► audio/mpeg
App : applique `patch` via SellerTunnelCubit.save(...) (provenance 'declared', RLS, verrou) ;
      V6 : ajoute les éléments au brouillon LifestyleCubit (source 'voice').
```
- Trois fonctions courtes plutôt qu’une : la bulle utilisateur s’affiche dès la transcription ; `agent-turn` reste purement texte (testable, réutilisable au clavier) ; `agent-speech` ne synthétise **que la réplique enregistrée du tour** (`turn_id` → `agent_turns.reply_fr`), donc la fonction ne peut pas servir de TTS gratuit pour n’importe quel texte.
- Toutes utilisent le **JWT de l’appelant** (client Supabase avec l’en-tête `Authorization`), jamais la clé service : RLS partout. Elles vérifient que le bien appartient à l’utilisateur et est un **brouillon** (sinon 409).
- `agent-transcribe` : corps ≤ 1,5 Mo (≈ 60 s), `language: "fr"`, `temperature: 0` ; renvoie `{transcript, seconds, cost}` ; n’enregistre pas l’audio (en mémoire seulement). Transcript vide → « Je n’ai rien entendu ».

### 3.2 `agent-turn` : l’IA propose, le serveur valide, l’app écrit
1. Lit le bien (RLS) ; refuse si `status ≠ 'draft'`.
2. Charge la session (`agent_sessions`) et ses 6 derniers tours.
3. Prompt : consignes fixes (mises en cache) + schéma des champs de l’étape (codes autorisés) + valeurs déjà connues + champs manquants + historique court + transcript (en données).
4. OpenRouter → Claude, `response_format: {type: "json_schema", strict: true}`, `reasoning: {effort: "low"}`, `provider: {order: ["anthropic"], allow_fallbacks: false, data_collection: "deny"}`. Pas de `tool_choice` forcé (refusé par les derniers Claude) : la sortie structurée suffit, un seul aller-retour.
5. Valide chaque valeur ; enregistre le tour ; renvoie le résultat.
- **La fonction n’écrit jamais dans le dossier.** Seul chemin d’écriture = celui des écrans (même cubit, mêmes droits colonne par colonne, même verrou `lock_submitted_dossiers`).

### 3.3 Champs par étape (mêmes colonnes que les écrans)
| Étape | Champs extraits (codes DB) |
|---|---|
| `technical` (V4 → données de V4b) | `construction_year`, `orientation` (`nord`…`traversant`), `living_area_m2`, `living_room_area_m2`, `rooms_count`, `bedrooms_count`, `levels` (`plain_pied`,`r1`,`r2_plus`), `wall_material` (7 codes), `adjacency` (`independant`,`1`,`2`,`3`), `roof_type` (`tuiles`,`ardoises`,`toit_terrasse`,`bac_acier`,`zinc`,`autre`), `roof_year`, `heating_systems` (10 codes, liste), `heat_pump_type` (`air_eau`,`air_air`,`geothermique`), `heat_pump_year`, `sanitation` (3 codes), `outdoor_equipment` (5 codes, liste), `pool_type` (5 codes), `pool_length_m`, `pool_width_m`. Adapté au `property_type` comme V4b (appartement sans niveaux/mitoyenneté/toiture ; terrain → pas de V4). |
| `lifestyle` (V6) | `lifestyle_items[] {kind: 'asset'|'watch_point', label ≤ 140}` (max 10 par type, sans doublon), `noise_level` 1–10, `overlooking` (`aucun`,`leger`,`important`), `secret_note` (≤ 500, proposée, jamais imposée). |
Validation partagée (TS, testée) : année de construction 1600…année courante ; toiture ≥ construction ; chambres ≤ pièces ; séjour ≤ surface habitable ; surface 5…2 000 ; listes = union avec l’existant sauf correction explicite.

### 3.4 Sortie du modèle (JSON Schema strict)
```json
{
  "reply_fr": "Parfait. Et pour l’assainissement : tout-à-l’égout ou fosse septique ?",
  "answers": [
    {"field": "construction_year", "value": 1998, "confidence": 0.95, "quote": "elle date de 1998"},
    {"field": "wall_material", "value": "parpaing", "confidence": 0.9, "quote": "en parpaing"},
    {"field": "roof_type", "value": "tuiles", "confidence": 0.9, "quote": "toiture en tuiles"},
    {"field": "roof_year", "value": 2016, "confidence": 0.85, "quote": "refaite en 2016"}
  ],
  "lifestyle_items": [],
  "next_field": "sanitation",
  "done": false
}
```
- `field` = enum des champs de l’étape ; `value` typé (`anyOf`) ; `quote` = extrait **littéral** du transcript, vérifié côté serveur (sinon rejet : pas d’invention). Confiance ≥ 0,7 → `patch` ; sinon → `pending` (pastille « Assainissement ? »).
- Réponse au client : `{ turn_id, reply_fr, patch, facts: [{field, label_fr}], pending: [{field, label_fr}], lifestyle_items, done }` ; libellés des pastilles produits par le serveur à partir des codes.

### 3.5 Sécurité, confidentialité, quotas
- **Injection de consigne** : transcript dans un bloc `<transcript>` déclaré comme données non fiables ; défense réelle = sortie contrainte (schéma strict, liste blanche, validation, citation littérale) + aucun pouvoir d’écriture des fonctions + écriture par l’app sous RLS + verrou. Pire cas : une valeur fausse visible en pastille, corrigeable, sur son propre dossier.
- **L’audio quitte désormais l’iPhone** : OpenRouter → fournisseur STT (Mistral pour Voxtral ; routage non maîtrisable pour les transcriptions) ; la réplique de l’agent → Google (Gemini TTS). Consentement au premier usage (« Votre voix est transcrite par nos prestataires, elle n’est pas conservée »), mention dans la politique de confidentialité, audio jamais stocké (ni sur l’appareil après envoi, ni en base). Pas de données d’identité dans les prompts (V1/V2 hors périmètre).
- Quotas : 120 tours / utilisateur / jour ; 60 s d’audio par tour ; 20 min d’audio / jour ; transcript ≤ 2 000 caractères ; TTS ≤ 600 caractères par réplique. 429 au-delà.
- Journal `agent_turns` (texte, extraction, modèles, secondes d’audio, jetons, latences, coût `usage.cost`), supprimé avec le bien, purge à 90 jours (Q5).

### 3.6 État de la conversation
Source de vérité des réponses = **le dossier** : chaque tour relit les valeurs et recalcule les champs manquants → reprise correcte après fermeture de l’app, saisie à l’écran ou changement d’appareil. `agent_sessions` / `agent_turns` gardent l’historique court et la question en cours.

### 3.7 Repli vers le mode écran
| Situation | Comportement |
|---|---|
| Micro refusé | Message + lien Réglages ; V3 → V4b ; micro masqué. |
| Hors ligne / STT, Claude ou TTS en échec | STT : « Je n’ai pas pu vous entendre, réessayez » ; Claude : transcript conservé, Réessayer / clavier ; TTS : réplique affichée sans voix (jamais bloquant). |
| 3 tours sans extraction | L’agent propose le mode écran. |
| « Passer » / bouton clavier | → V4b pré-rempli (provenance Déclaré). |
| Quota atteint | Message + mode écran. |
| Dossier envoyé | Pas de voix (verrou `lockRedirect`). |
`AgentActionBar.voiceEnabled` devient une valeur d’exécution (`VoiceCapability` : flag `VOICE_ENABLED` dans `config/<flavor>.json` × permission micro), plus une constante. Option d’avenir : reconnaissance locale iOS (`speech_to_text`, BSD-3, dépendances BSD/Apache vérifiées) comme repli hors ligne — non prévue en v1.

### 3.8 Provenance
`Provenance` = `declared | document | external | expert | ai`. Une valeur **dite** par le vendeur reste **`declared`** (« Déclaré ») : l’IA ne fait que transcrire et classer. `ai` (« Estimé IA ») est réservé aux valeurs **déduites**, ce que l’agent v1 interdit. Pas de nouvelle valeur d’enum ; traçabilité par `lifestyle_items.source = 'voice'` (existant) et `agent_turns` (Q6).

---

## 4. Données / migration (nouvelle migration `*_agent_conversations.sql`, additive)
```sql
create table public.agent_sessions (
  id uuid primary key default gen_random_uuid(),
  property_id uuid not null references public.properties (id) on delete cascade,
  step text not null check (step in ('technical', 'lifestyle')),
  status text not null default 'active' check (status in ('active', 'done', 'abandoned')),
  next_field text check (char_length(next_field) <= 60),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create table public.agent_turns (
  id uuid primary key default gen_random_uuid(),
  session_id uuid not null references public.agent_sessions (id) on delete cascade,
  transcript text not null check (char_length(transcript) <= 2000),
  audio_seconds numeric(6, 2),
  reply_fr text check (char_length(reply_fr) <= 600),
  extracted jsonb,                      -- réponses validées + rejetées (avec raison)
  stt_model text, agent_model text, tts_model text,
  tokens_in integer, tokens_out integer,
  stt_ms integer, agent_ms integer, tts_ms integer,
  cost_usd numeric(8, 5),               -- somme des usage.cost STT + agent + TTS
  error text,
  created_at timestamptz not null default now()
);
-- RLS : lecture / insertion par le propriétaire du bien (via la session), insertion seulement
-- si le bien est un brouillon ; mise à jour limitée aux colonnes tts_ms / cost_usd (agent-speech).
-- Index : agent_sessions (property_id, step, status), agent_turns (session_id, created_at).
```
Aucune modification de `properties` ; `lifestyle_items.source` accepte déjà `'voice'`.

---

## 5. UX (maquettes V4 Night et V6)

### V4 · Audit vocal technique — `VoiceAuditPage` (route `/vendeur/audit/technique-vocal`)
- Fond **Nuit `#0F1713`** (racine Ivoire dans la maquette mais éléments Night — Q7) ; en-tête : fermer sombre 44 (`#18221D`, « Fermer » → V3), légende `Étape 4 · Technique` (#A9B5AD), titre `Audit technique`, pastille `Vocal` (fond `#18221D`, bordure `#2F3B34`, texte Lueur `#8BE05A`) ; `SegmentedProgress` Night 4/7.
- **Orbe** 170 / 132 / 95 / cœur 64 Lueur (micro, halo `0 0 40px rgba(139,224,90,.45)`). États : *écoute* (respiration selon le niveau du micro), *transcription / réflexion* (pulsation lente), *l’agent parle* (anneaux pilotés par la lecture, icône haut-parleur), *pause*.
- **Onde** : 34 barres 3 px (hauteur 4–28 px) depuis `onAmplitudeChanged` pendant l’écoute ; texte 13 px #A9B5AD : `L’agent vous écoute…` / `Je retranscris…` / `L’agent réfléchit…` / `L’agent vous répond…` / `En pause`.
- Conversation : `AgentBubble(onDark)` (réplique, lue à voix haute) ; `UserBubble` Lueur / Encre (transcription) ; pastilles de faits Lueur (`Construction 1998`, `Parpaing`, `Toiture tuiles · 2016`) et en attente `#26322B` (`Assainissement ?`) ; toucher une pastille → mini-fiche de correction (contrôles de V4b).
- Carte plan (Nuit 2) `Vous avez un plan ? Importez-le pour pré-remplir pièces et surfaces.` + `Importer` → dépôt `kind = plan` (sélecteur de V7, sans extraction en v1).
- Bas : clavier 56 (`Passer en mode écran` → V4b), pause 76 Lueur (`Mettre en pause` / `Reprendre`), lien `Passer` → V4b ; option « Couper la voix de l’agent ».
- Tour : écoute → fin de parole (silence 1,2 s ou « J’ai fini ») → transcription → réflexion → voix → écoute relancée. `done: true` → « J’ai tout ce qu’il me faut, vérifions ensemble » → V4b pré-rempli pour relecture.
- Navigation : V3 « Continuer » → V4 si la voix est disponible, sinon V4b ; V4b retour → V4 ; segment `Voix / Écran` de V4b réactivé. VoiceOver : la réplique est aussi annoncée en texte.

### V6 · « Parlez librement » (`LifestylePage`)
- Le micro de l’`AgentActionBar` (hint `Parlez librement, l’agent classe vos réponses`) ouvre une **feuille Night** compacte (orbe 95/64, onde, transcription, `J’ai fini`).
- Les éléments proposés s’ajoutent aux listes **Atouts** / **Points de vigilance** avec surbrillance et étiquette « Ajouté à la voix », modifiables / supprimables ; bruit et vis-à-vis positionnés ; note secrète proposée en suggestion. Réplique courte lue (« J’ai noté 3 atouts et 1 point de vigilance »). Rien n’est enregistré avant « Continuer ».

---

## 6. User stories (FR) et critères d’acceptation

### US-06.1 · Parler à l’agent
*En tant que vendeur, je veux répondre à l’agent à la voix, en français.*
- [ ] L’accès au micro est demandé au premier usage, avec un texte explicatif ; un refus mène au mode écran avec un lien vers les Réglages.
- [ ] Un message d’information au premier usage explique que la voix est transcrite par un prestataire et n’est pas conservée.
- [ ] La fin de ma phrase est détectée après un court silence (ou « J’ai fini ») ; un tour dure 60 s au plus.
- [ ] Ma phrase transcrite s’affiche dans ma bulle en moins de 2 s en conditions normales.
- [ ] L’audio n’est conservé ni sur le téléphone ni sur le serveur.
- [ ] Dépendances sous licences MIT / BSD / Apache uniquement (contrôle de licences vert).

### US-06.2 · Agent qui comprend mes réponses
*En tant que vendeur, je veux décrire mon bien librement et que l’agent remplisse les bonnes cases.*
- [ ] Seules les informations dites explicitement sont retenues ; une information douteuse devient une question (« Assainissement ? »).
- [ ] Les valeurs respectent les règles des écrans (codes, bornes, cohérences) ; une valeur invalide n’est jamais enregistrée.
- [ ] Une seule question à la fois, en vouvoyant, sur les champs manquants.
- [ ] Un dossier envoyé ne peut pas être modifié par la voix (refus serveur + RLS).
- [ ] Aucune donnée d’identité (nom, téléphone, e-mail, adresse) n’est envoyée aux modèles.

### US-06.3 · L’agent me répond à voix haute
*En tant que vendeur, je veux entendre l’agent pour garder les yeux libres pendant la visite de mon bien.*
- [ ] Chaque réplique est lue avec une voix française naturelle, le texte restant affiché.
- [ ] Le micro est coupé pendant que l’agent parle ; l’écoute reprend ensuite automatiquement.
- [ ] Je peux couper la voix de l’agent (préférence mémorisée).
- [ ] Une panne de la voix n’empêche pas la conversation (texte seul).

### US-06.4 · Audit technique à la voix (V4)
*En tant que vendeur, je veux faire l’audit technique en conversation.*
- [ ] Écran Night conforme à la maquette : orbe et onde animés, bulles, pastilles comprises / en attente.
- [ ] Toucher une pastille permet de corriger la valeur.
- [ ] Pause / reprise ; « Passer » et le clavier ouvrent V4b pré-rempli (provenance « Déclaré »).
- [ ] Après fermeture de l’app, l’audit reprend aux questions restantes.
- [ ] En cas d’erreur : message, transcription conservée, Réessayer ou mode écran.
- [ ] « Importer » un plan dépose le document dans le coffre (type plan).

### US-06.5 · Cadre de vie dicté (V6)
*En tant que vendeur, je veux parler librement de mon quartier et que l’agent classe atouts et points de vigilance.*
- [ ] Le texte dicté est classé en atouts / points de vigilance (140 caractères max, 10 max chacun, sans doublon).
- [ ] Bruit et vis-à-vis proposés quand je les mentionne ; note secrète proposée, jamais imposée.
- [ ] Éléments ajoutés à la voix signalés, modifiables, supprimables, enregistrés à « Continuer » (source « voix »).

### US-06.6 · Coûts et suivi
*En tant que porteur de projet, je veux maîtriser le coût et la qualité de la voix et de l’agent.*
- [ ] Chaque tour journalise modèles, durée audio, jetons, latences (STT / agent / TTS) et coût réel (`usage.cost`).
- [ ] Quotas : 120 tours et 20 min d’audio par utilisateur et par jour.
- [ ] Les modèles STT / agent / TTS et la voix se changent par secret Supabase, sans republier l’app.

---

## 7. Découpage (tranches de 1 à 2 h, un agent codeur chacune)

| # | Tranche | Fichiers possédés (exclusifs) | Dépend de |
|---|---|---|---|
| A1 | **Migration** `agent_conversations` (tables, RLS, index) + `db push` + sonde RLS | `supabase/migrations/2026…_agent_conversations.sql` | — |
| A2 | **Schémas d’étape + validation** (TS) : champs, codes, libellés FR, règles, JSON Schema strict par étape / type de bien, libellés de pastilles ; tests Deno | `supabase/functions/_shared/agent/schema.ts`, `validate.ts`, `labels.ts` (+ tests) | — |
| A3 | **Client OpenRouter partagé** : chat (json_schema, `reasoning`, `provider`), `/audio/transcriptions`, `/audio/speech`, délais, lecture de `usage.cost` ; tests avec faux serveur (partagé avec EPIC-05 E5 : un seul propriétaire) | `supabase/functions/_shared/openrouter/*.ts` | — |
| A4 | **`agent-transcribe` + `agent-speech`** (auth JWT, brouillon, quotas, tailles, journal) + **banc d’essai** STT/TTS (20 phrases enregistrées, rapport WER / latence / coût) → choix des modèles par défaut | `supabase/functions/agent-transcribe/**`, `supabase/functions/agent-speech/**`, `supabase/functions/_shared/agent/quota.ts`, `scratchpad` du banc | A1, A3 |
| A5 | **`agent-turn`** : session, prompt (consignes en cache), appel Claude, contrôle des citations, seuils, réponse, journal ; déploiement ; tests de bout en bout sur dossier de test | `supabase/functions/agent-turn/**`, `supabase/functions/_shared/agent/prompt.ts` | A1, A2, A3 |
| A6 | **Package `voice_repository`** : `VoiceRecorder` (`record`, m4a AAC 16 kHz mono, niveaux, fin de parole), `VoicePlayer` (`audioplayers`, contexte audio iOS), faux ; Info.plist + `InfoPlist.strings` ; job CI | `packages/voice_repository/**`, `ios/Runner/Info.plist`, `ios/Runner/*.lproj/InfoPlist.strings`, `pubspec.yaml`, `.github/workflows/main.yaml` | — |
| A7 | **Package `agent_repository`** : `transcribe(audio)`, `turn(propertyId, step, transcript)`, `speech(turnId)` → modèles, erreurs typées (verrouillé, quota, réseau) ; tests | `packages/agent_repository/**`, `lib/bootstrap.dart` (+1 dépôt), `test/helpers/mocks.dart` (+1 mock) | contrats figés en A2/A4/A5 |
| A8 | **Capacité voix** : `VoiceCapability` (flag × permission), `AgentActionBar` piloté par elle, routage V3 → V4 / V4b, segment Voix/Écran de V4b, consentement au premier usage | `lib/seller_tunnel/voice/**`, `lib/seller_tunnel/widgets/agent_action_bar.dart`, `lib/seller_tunnel/models/seller_tunnel_step.dart`, `lib/app/router/**`, `config/*.json` | A6 |
| A9 | **Widgets Night** : `ListeningOrb` (états écoute / réflexion / parole / pause), `VoiceWaveform`, `FactPill`, `UserBubble` Lueur, en-tête et progression Night ; galerie ; tests pixel | `lib/ui/components/voice/**`, `lib/ui/ui.dart`, galerie | — |
| A10 | **V4 + `VoiceAuditCubit`** (boucle écoute → transcription → tour → voix, application du patch, pastilles, correction, Passer / clavier, import plan, couper la voix) ; l10n `voiceAudit*` ; tests 100 % | `lib/seller_tunnel/steps/voice_audit/**`, ARB (`voiceAudit*`) | A7, A8, A9 |
| A11 | **V6 « Parlez librement »** : feuille d’écoute, intégration `LifestyleCubit` ; l10n `lifestyleVoice*` ; tests | `lib/seller_tunnel/steps/lifestyle/**`, ARB (`lifestyleVoice*`) | A7, A8, A9 |
| A12 | **Docs & vérification** : `docs/epics/EPIC-06-voix-agent.md`, plan, spec V4/V6, politique de confidentialité (voix transcrite par prestataire), test iPhone réel (latence, bruit, coût d’une session) | `docs/**` | toutes |

Parallélisme : vague 1 = A1, A2, A3, A6, A9 ; vague 2 = A4, A5, A8 ; vague 3 = A7 ; vague 4 = A10 et A11 (dossiers disjoints) ; puis A12. ARB : lecture-modification-écriture JSON + `flutter gen-l10n` immédiat, préfixes distincts.

---

## 8. Questions ouvertes (porteur de projet)
1. **Modèle Claude** de l’agent : Opus 5.5 (≈ 0,48 $/session de 15 min), Sonnet 5.5 (≈ 0,30 $) ou Haiku 4.5 (≈ 0,20 $) ? Ou l’option 2 sans Claude (≈ 0,05–0,10 $) ?
2. **STT / TTS par défaut** : Voxtral Mini Transcribe + Gemini 3.8 Flash Lite TTS (proposé) — à confirmer après le banc d’essai (A4) ; une voix Realesty clonée (Voxtral TTS, 16 $/M car.) plus tard ?
3. **RGPD** : la voix part chez Mistral (STT) et la réplique chez Google (TTS) via OpenRouter ; routage non maîtrisable pour la transcription. DPA OpenRouter, mention dans la politique de confidentialité, consentement explicite : à valider.
4. L’agent parle par défaut (proposé) ou texte seul avec option voix ?
5. Conservation des transcriptions : 90 jours (proposé), durée du dossier, ou extractions seulement ?
6. Faut-il distinguer « dit à la voix » de « saisi » pour l’expert, ou « Déclaré » suffit-il ?
7. V4 en fond Nuit confirmé ? Feuille V6 Night ou claire ?
8. Fin de l’audit vocal : relecture obligatoire sur V4b (proposé) ou passage direct à V5 ?
9. Phase 2 : interruption de l’agent (barge-in), temps réel, dictée V3 / V5c, agent « Une question ? » — dans EPIC-06 ou un epic séparé ?

## Arbitrages du porteur de projet (2026-10-01)
- **Modèles configurables, benchmark d'abord** : la chaîne STT → agent → TTS est paramétrable côté serveur (identifiants de modèles OpenRouter) ; un benchmark sur 20 phrases réelles enregistrées compare les options (Voxtral / Whisper ; Claude Haiku / Sonnet / Gemini Flash-Lite ; TTS) avant de fixer les modèles par défaut avec le porteur de projet.
- **RGPD : consentement explicite** au premier usage du micro (écran d'information : fournisseurs qui traitent l'audio, aucune conservation de l'audio), mode écran toujours disponible.
