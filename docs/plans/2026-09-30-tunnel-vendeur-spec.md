# Realesty · Seller tunnel spec ("Tunnel vendeur · L’audit conversationnel")

Source: Claude Design canvas "Realesty · App mobile" (claude.ai/artifact/7iUZPTfM8Kf6xrEY4nnS5v, version 1790799952-11dc), row y=7500.
Mockup files (for developers): `scratchpad/seller-design/project/*.dc.html` (+ `canvas.json`). Open them in a browser for pixel reference.
Visual tokens/components: `scratchpad/ds-spec.md`. Flutter DS widgets already in `lib/ui/components/`:
`RealestyButton` (primary/accent/secondary/text), `RealestyIconButton`, `RealestyMicButton`, `RealestyTextField`, `RealestySelect`, `RealestyStepper`, `RealestySegmentedControl`, `RealestyChoiceChip`, `RealestyCheckbox`, `RealestyBadge` (essentiel/premium/expert/compatibility/passVisite/certified/toComplete/missing/neutral), `ProvenanceTag` (declared/document/externalSource/expertVerified/aiEstimated), `SegmentedProgress`, `RealestyListItem` (tone neutral/success/error), `InlineBanner` (warning/info), `AgentAvatar`, `AgentBubble`, `UserBubble` (all with `onDark`), `RealestySnackBar`.

Copy below is verbatim from the mockups (French, typographic apostrophes ’ and non-breaking spaces as in source). Values shown in mockups (Sophie Durand, 540 m², 1998…) are sample data, not defaults, unless stated.

---

## 0. Shared tunnel patterns (build once)

### 0.1 `TunnelHeader` (new composite, not in DS)
Row, padding 54/20/10 in mockup → use SafeArea + 10 top.
- Left: `RealestyIconButton` chevron-left, aria "Retour" (light) — V4/V5b use dark variant with close icon, aria "Fermer".
- Center (2 lines, centered): caption 12/600 Texte discret = `Étape N · <Nom>`; title Sora 16/600 = `Audit de votre bien` (V4: `Audit technique`).
- Right, one of:
  - mode pill (h32, pill, white, 1px Bordure carte, 12/700, icon 14): `Écran` (keyboard icon) on V1, V2, V3, V4b; `Vocal` on V6 (mic icon); on V4 Night variant bg Nuit 2, border #2F3B34, text Lueur `Vocal`.
  - step counter Sora 14/600, width 44: `5/7` (V5, V5c), `7/7` (V7).
- Below: `SegmentedProgress` 7 segments, padding 0 20 8. On V4 (Night): done = Lueur #8BE05A, todo = #2F3B34.

Step names (caption) and progress: V1 `Étape 1 · Propriétaires` 1/7 · V2 `Étape 2 · Cadastre` 2/7 · V3 `Étape 3 · Contexte` 3/7 · V4 & V4b `Étape 4 · Technique` 4/7 · V5 & V5c `Étape 5 · Pièces` 5/7 · V6 `Étape 6 · Cadre de vie` 6/7 · V7 `Étape 7 · Documents` 7/7 (all segments done). V5b, V8, V8b: no TunnelHeader/SegmentedProgress.

### 0.2 Agent chat pattern
- One `AgentBubble` (avatar 36 + "Agent Realesty" + sparkle) at the top of each step with the step question. One question per screen ("one question at a time").
- `UserBubble` appears only on V4 (voice transcript). On screen-mode steps the user "answers" through the form controls below the bubble; no user bubble is shown.
- v1 (keyboard-first): agent bubble text is static copy per step (no LLM needed). Later: agent may rephrase / follow-up.

### 0.3 `AgentActionBar` (new composite, bottom, sticky)
Padding 12 20 34 (use SafeArea bottom), bg Ivoire, top border 1px Bordure carte, column gap 10:
- Hint line 12 Texte discret centered (copy per screen below).
- Row gap 14: `RealestyMicButton` (aria "Parler à l’agent") + expanded `RealestyButton` (primary unless noted).
- v1: mic button visible but either hidden or showing a snackbar "bientôt disponible" — decision needed (recommend hide behind a feature flag; hint then reads only as written). Everything reachable by voice has a screen equivalent except V4 (voice mode itself) and V6 "Parlez librement" free-talk classification.

### 0.4 `SelectableCard` (new, not in DS; used V1 and V3)
2-column grid gap 12 (V3: 10). Card padding 14, radius 16, border 1.5: unselected white / Ligne; selected Vert teinte / Vert texte. Top row: icon tile 40 radius 12 (unselected Surface 2 + Encre icon; selected white + Vert texte icon) and a 22px radio dot on the right (selected: filled Vert texte with white check 14). Below: title 15/700, optional subtitle 13 Texte discret. Single-select.

### 0.5 Section label
"Légende" style (12/700 uppercase 0.08em Texte discret) — e.g. `Propriétaire 1 · vous`, `Type de bien`, `Historique`, `Estimation précédente`. V4b and V6 use h2 section titles (Sora 18/600 "Titre 2").

---

## 1. Tunnel order & navigation map

```
Role (02) → V1 → V2 → V3 → V4 (voice) ⇄ V4b (screen) → V5
V5 ─ "Scanner avec la caméra" → V5b (loop per room) → V5c
V5 ─ "Importer ou photographier un plan" → V5c (pre-filled)
V5 ─ "Saisir manuellement" → V5c (empty)
V5c → V6 → V7 → V8 ⇄ V8b ; V8 → V9 Dashboard ; V8b → V9b RapportValeur
```
Mockup back links: V1←Role, V2←V1, V3←V2, V4 close→V3, V4b back→V4, V5 back→V4b, V5b close→V5, V5c back→V5b (real app: back to V5 or last room), V6←V5c, V7←V6, V8 none, V8b back→V8.
Keyboard-first v1: V3 "Continuer" goes to **V4b** directly (V4 deferred).

---

## 2. Screens

### V1 · Identification des propriétaires (`Proprietaires.dc.html`)
Purpose: who owns the property; contact of each owner. Creates the property draft.
In: from Role selector (seller). Out: `Continuer` → V2. Progress 1/7, pill `Écran`.

Layout:
1. TunnelHeader (`Étape 1 · Propriétaires` / `Audit de votre bien` / `Écran`).
2. AgentBubble: `Bonjour ! Je vais vous accompagner pas à pas, à votre rythme. Pour commencer : êtes-vous le seul et unique propriétaire de ce bien ?`
3. SelectableCard ×2: `Unique propriétaire` (user icon) · `Plusieurs propriétaires` + subtitle `Couple, indivision, héritage…` (users icon). Mockup: second selected.
4. Section label `Propriétaire 1 · vous`
5. Row of 2 `RealestyTextField`: `Prénom` (Sophie), `Nom` (Durand).
6. `RealestyTextField` `Téléphone`, leading phone icon (06 12 34 56 78).
7. `RealestyTextField` `E-mail`, leading chat icon (sophie.durand@email.fr).
8. Co-owner card (white, radius 16, border): initials avatar 40 (Surface 2, Sora 14/600 `MD`), name 15/600 `Marc Durand`, subtitle 13 `Co-propriétaire · 06 98 76 54 32`, trailing `RealestyIconButton` pen (aria `Modifier`). One card per extra owner; only when "Plusieurs".
9. `RealestyButton.text` with plus icon: `Ajouter un co-propriétaire` (only when "Plusieurs").
10. AgentActionBar: hint `Répondez à la voix ou à l’écran`, CTA `Continuer`.

Inputs:
| Field | Type | Options | Req. | Validation / default |
|---|---|---|---|---|
| ownership_type | SelectableCard single | `Unique propriétaire` / `Plusieurs propriétaires` | yes | no default (require choice) |
| Prénom, Nom | text | – | yes | 1–100 chars; prefill Prénom from `profiles.first_name` |
| Téléphone | phone text | – | yes | FR mobile/landline (`^(?:\+33\|0)[1-9](?:[ .-]?\d{2}){4}$`), store E.164 |
| E-mail | email | – | yes | email format; prefill from auth email |
| Co-owner (each) | sub-form (not designed → propose bottom sheet with Prénom, Nom, Téléphone, E-mail; E-mail optional) | – | ≥1 when "Plusieurs" | same rules |
CTA enabled when ownership chosen + owner 1 valid + (if multiple) ≥1 co-owner. Provenance: none shown (all Déclaré).

### V2 · Géoloc & cadastre (`Cadastre.dc.html`)
Purpose: locate the property and confirm the cadastral parcel. Out `Continuer` → V3. Progress 2/7, pill `Écran`.

Layout:
1. TunnelHeader `Étape 2 · Cadastre`.
2. AgentBubble (templated): `J’ai localisé votre parcelle : section AB, n° 98, pour 540 m², avec maison et piscine. Cela correspond-il exactement aux limites de votre propriété ?` → template `J’ai localisé votre parcelle : section {section}, n° {numero}, pour {surface} m²{, avec …}. Cela correspond-il exactement aux limites de votre propriété ?` (v1: drop the "avec maison et piscine" part — not available from cadastre API).
3. `RealestyTextField` label `Adresse du bien`, leading pin icon, value e.g. `12 rue de la Colombe, 69630 Chaponost` → address autocomplete (suggestion list under field; not designed — use RealestyListItem rows).
4. Map, h210 radius 16: aerial image + parcel polygon (fill rgba(108,196,58,.34), stroke Lueur 3.5). Top-right column of 2 `RealestyIconButton` 40: target icon aria `Me géolocaliser`, plus icon aria `Zoomer`. Bottom-left dark badge (h26 pill Encre bg white text, pin icon): `Parcelle AB 98 sélectionnée`. Tapping another parcel selects it (implied by "Modifier / ajouter").
5. Parcel card (white radius 16): left `Section · Parcelle` (13 discret) + Sora 20/600 `AB · 98`; right aligned `Surface cadastrale` + `540 m²`. Then `ProvenanceTag.externalSource` (`Source externe`) + 12 discret `Registre cadastral · à confirmer avec votre titre de propriété`.
6. Two buttons side by side (h48, 15/600): primary with check `Oui, c’est correct`; secondary with plus `Modifier / ajouter`.
7. Label 13/600 `Êtes-vous concerné par une situation particulière ?` + wrap of `RealestyChoiceChip`: `Servitude de passage`, `Servitude de réseaux`, `Autre`, `Aucune` (mockup: Aucune selected).
8. AgentActionBar: `Répondez à la voix ou à l’écran` / `Continuer`.

Inputs:
| Field | Type | Options | Req. | Validation / default |
|---|---|---|---|---|
| Adresse du bien | text + autocomplete (BAN) | suggestions | yes | must pick a BAN result (housenumber/street precision) |
| Me géolocaliser | action | – | – | device GPS → reverse geocode → fill address |
| Parcel selection | map tap / auto from address point | – | yes | default = parcel containing geocoded point |
| parcel_confirmed | 2 buttons | `Oui, c’est correct` / `Modifier / ajouter` | yes | "Modifier / ajouter" enables multi-parcel selection on map (add/remove parcels); confirm required before Continuer |
| special_situations | chips, multi-select; `Aucune` exclusive | `Servitude de passage`, `Servitude de réseaux`, `Autre`, `Aucune` | yes (≥1) | default none selected; `Autre` → propose free-text field (not designed) |
Data shown: section, numéro, contenance (m²) = Source externe (cadastre).

### V3 · Contexte & type de bien (`Contexte.dc.html`)
Purpose: property type, ownership history, reason for sale, previous estimates. Out `Continuer` → V4 (v1: V4b). Progress 3/7, pill `Écran`.

Layout:
1. TunnelHeader `Étape 3 · Contexte`.
2. AgentBubble: `Depuis quelle année êtes-vous propriétaire ? Et de quel type de bien s’agit-il ? J’adapterai mes questions.`
3. Section label `Type de bien`; SelectableCard grid 2×2: `Maison` (home icon), `Appartement` (building), `Terrain` (land), `Autre` + subtitle `Immeuble, local, garage…` (grid icon). Mockup: Maison selected.
4. Section label `Historique`.
5. Row 2 fields: `Année d’achat` (2012); `Prix d’achat` suffix `€` (320 000) with helper 12 discret `Facultatif`.
6. Label `Construit par vous ?` + `RealestySegmentedControl` `Oui` / `Non` (Non).
7. Label `Raison de la vente` + chips: `Mutation`, `Agrandissement`, `Séparation`, `Investissement`, `Autre` (Agrandissement selected).
8. Label `Déjà estimé par une agence ?` + segmented `Oui` / `Non` (Oui).
9. If Oui: card (white radius 16) with section label `Estimation précédente`; row: `Prix estimé` suffix `€` (510 000), `Date` leading calendar icon placeholder `mm/aaaa`; field `Agence` leading building icon placeholder `Nom de l’agence`; `RealestyButton.text` plus `Ajouter une autre agence` (adds another estimate card).
10. AgentActionBar hint `Les questions facultatives peuvent être passées`, CTA `Continuer`.

Inputs:
| Field | Type | Options | Req. | Validation / default |
|---|---|---|---|---|
| property_type | SelectableCard single | `Maison`, `Appartement`, `Terrain`, `Autre` | yes | – ; `Autre` → free text (not designed). Drives V4b fields (e.g. Terrain skips V4b/V5, Appartement hides Mitoyenneté/Toiture/Assainissement/Piscine — adaptation not designed, propose) |
| Année d’achat | number (4 digits) | – | yes | 1900..current year; ≤ now |
| Prix d’achat | number € (thousands separator space) | – | no (`Facultatif`) | 1 000..100 000 000 |
| Construit par vous ? | segmented | `Oui` / `Non` | yes | no default in v1 |
| Raison de la vente | chips single | `Mutation`, `Agrandissement`, `Séparation`, `Investissement`, `Autre` | no (optional per hint) | – |
| Déjà estimé par une agence ? | segmented | `Oui` / `Non` | no | – |
| Prix estimé | number € | – | if Oui | > 0 |
| Date | month/year text `mm/aaaa` | – | no | valid month, ≤ now |
| Agence | text | – | no | ≤ 120 chars |
Provenance: none displayed (Déclaré).

### V4 · Audit vocal technique (`AuditVocalTechnique.dc.html`) — VOICE ONLY, DEFER
Purpose: technical audit by voice conversation. Night mode (Nuit palette; mockup root bg is Ivoire but all elements are Night-palette — treat as Nuit #0F1713, confirm with design).
Header: dark icon button close (aria `Fermer` → V3), caption `Étape 4 · Technique` (#A9B5AD), title `Audit technique`, pill `Vocal` (Lueur text). SegmentedProgress Night 4/7.
Layout: listening orb (concentric circles 170/132/95, core 64 Lueur with mic) + waveform bars + `L’agent vous écoute…`; `AgentBubble(onDark)` `Parfait. En quelle année la maison a-t-elle été construite, et avec quels matériaux ?`; `UserBubble` variant **Lueur bg / Encre text** (differs from DS Encre user bubble — onDark variant) `Elle date de 1998, en parpaing, avec une toiture en tuiles refaite en 2016…`; extracted-fact pills (h26 Lueur, check icon): `Construction 1998`, `Parpaing`, `Toiture tuiles · 2016`, pending pill (Nuit 3, white) `Assainissement ?`; plan import card (Nuit 2, plan icon tile): `Vous avez un plan ? Importez-le pour pré-remplir pièces et surfaces.` + small Lueur button `Importer`.
Bottom controls: left 56 dark button keyboard icon (aria `Passer en mode écran` → V4b); center 76 Lueur pause button (aria `Mettre en pause`); right text link `Passer` → V4b.
Screen equivalent: everything → V4b. "Importer" plan → document upload (kind=plan), also offered on V5.

### V4b · Audit technique (mode écran) (`AuditTechniqueEcran.dc.html`)
Purpose: technical identity card of the building. Out `Enregistrer et continuer` → V5. Progress 4/7, pill `Écran`.

Layout:
1. TunnelHeader `Étape 4 · Technique`, back → V4 (v1: V3).
2. `RealestySegmentedControl` with icons: `Voix` (mic) / `Écran` (keyboard) — Écran selected. (v1: hide or disable Voix.)
3. h2 `Carte d’identité`
   - Row: `Année de construction` text (1998) · `Exposition` Select (`Sud`).
   - Row: `Surface habitable` suffix `m²` (115) · `Surface séjour` suffix `m²` (38,5).
   - `RealestyStepper` `Pièces` (5), `RealestyStepper` `Chambres` (3) (buttons aria `Retirer` / `Ajouter`).
   - Label `Niveaux` + segmented `Plain-pied` / `R+1` / `R+2 et plus` (R+1).
4. h2 `Gros œuvre`
   - Label `Matériaux des murs` + chips `Parpaing`, `Brique`, `Pierre`, `Béton`, `Moellon`, `Bois`, `Pisé` (Parpaing).
   - Label `Mitoyenneté` + chips `Indépendant`, `1 côté`, `2 côtés`, `3 côtés` (Indépendant).
   - Row: `Toiture` Select (`Tuiles`) · `Année toiture` (2016) with `ProvenanceTag.declared` below.
5. h2 `Chauffage & assainissement`
   - Label `Énergie principale` + chips `Électricité`, `Gaz`, `Fioul`, `Pompe à chaleur`, `Bois` (Pompe à chaleur).
   - If Pompe à chaleur: row `Type de PAC` Select (`Air / eau`) · `Année PAC` (2021) with `ProvenanceTag.document` (`Extrait d’un document`).
   - Label `Assainissement` + chips `Tout-à-l’égout`, `Fosse septique`, `Puits perdu` (Tout-à-l’égout).
6. h2 `Extérieur & équipements`
   - Label `Équipements extérieurs` + chips (multi) `Piscine`, `Garage`, `Terrasse`, `Abri de jardin`, `Portail motorisé` (first three selected).
   - If Piscine: row `Type de piscine` Select (`Enterrée · liner`) · `Dimensions` text suffix `m` (`8 × 4`) with `ProvenanceTag.declared`.
7. Info note (13, discret, with tag inline): `Chaque information indique sa provenance. Une facture importée transforme « Déclaré » en « Extrait d’un document ».`
8. AgentActionBar `Répondez à la voix ou à l’écran` / `Enregistrer et continuer`.

Inputs:
| Field | Type | Options (verbatim where shown) | Req. | Validation / default |
|---|---|---|---|---|
| Année de construction | number | – | yes | 1600..current year |
| Exposition | select | shown `Sud`; propose `Nord`, `Nord-Est`, `Est`, `Sud-Est`, `Sud`, `Sud-Ouest`, `Ouest`, `Nord-Ouest`, `Traversant` | no | – |
| Surface habitable | decimal m² (comma) | – | yes | 5..2000; pre-filled later by V5c total (keep in sync, V5c wins) |
| Surface séjour | decimal m² | – | no | ≤ surface habitable |
| Pièces | stepper | – | yes | 1..30, default 1 |
| Chambres | stepper | – | yes | 0..Pièces, default 0 |
| Niveaux | segmented | `Plain-pied`, `R+1`, `R+2 et plus` | yes (maison) | – |
| Matériaux des murs | chips single | `Parpaing`, `Brique`, `Pierre`, `Béton`, `Moellon`, `Bois`, `Pisé` | no | – |
| Mitoyenneté | chips single | `Indépendant`, `1 côté`, `2 côtés`, `3 côtés` | no (maison) | – |
| Toiture | select | shown `Tuiles`; propose `Tuiles`, `Ardoises`, `Toit-terrasse`, `Bac acier`, `Zinc`, `Autre` | no | – |
| Année toiture | number | – | no | ≥ construction year, ≤ now |
| Énergie principale | chips single | `Électricité`, `Gaz`, `Fioul`, `Pompe à chaleur`, `Bois` | yes | – |
| Type de PAC | select (if PAC) | shown `Air / eau`; propose `Air / eau`, `Air / air`, `Géothermique` | no | – |
| Année PAC | number (if PAC) | – | no | ≤ now |
| Assainissement | chips single | `Tout-à-l’égout`, `Fosse septique`, `Puits perdu` | no | – |
| Équipements extérieurs | chips multi | `Piscine`, `Garage`, `Terrasse`, `Abri de jardin`, `Portail motorisé` | no | – |
| Type de piscine | select (if Piscine) | shown `Enterrée · liner`; propose `Enterrée · liner`, `Enterrée · coque`, `Enterrée · béton`, `Semi-enterrée`, `Hors-sol` | no | – |
| Dimensions | text `L × l` m | – | no | parse two decimals |
Provenance: each field defaults Déclaré; becomes Extrait d’un document when filled from a V7 document. Show ProvenanceTag under fields that have a non-trivial provenance (mockup shows it on Année toiture, Année PAC, Dimensions).

### V5 · Choix de la méthode de relevé (`MethodeReleve.dc.html`)
Purpose: choose how rooms/surfaces are captured. Progress 5/7, counter `5/7` (no mode pill). No AgentActionBar.
Layout:
1. TunnelHeader `Étape 5 · Pièces`, back → V4b.
2. AgentBubble: `C’est le moment le plus important : la visite guidée ! Comment préférez-vous relever vos pièces ?`
3. Three method cards (radius 18, border 1.5, icon tile 48 radius 14, title 16/700, description 13 discret), each fully tappable:
   - `Scanner avec la caméra` + `RealestyBadge.certified`-colored badge (no icon) `Recommandé`; `Surfaces, volumes et revêtements détectés pendant que vous filmez chaque pièce à 360°.` Highlighted (border Vert texte, tile Vert teinte). → V5b.
   - `Importer ou photographier un plan` — `L’IA extrait la liste des pièces et leurs surfaces pour pré-remplir le tableau.` → V5c (after upload + extraction).
   - `Saisir manuellement` — `Remplissez vous-même le tableau des surfaces, pièce par pièce.` → V5c.
4. Info note (Surface 2 radius 12, info icon): `Les mesures réalisées au téléphone sont estimatives. Elles sont distinguées des surfaces issues d’un plan et vérifiées par l’expert.`
Input: measurement_method (single tap) ∈ scan / plan / manual.
v1: show only "Saisir manuellement" active; plan option = plain upload stored for the expert (no extraction) then manual table; camera card hidden or badged "Bientôt" (decision).

### V5b · Scan pièce par pièce (`ScanPiece.dc.html`) — CAMERA, DEFER
Night camera screen. Top 470px camera feed with AR measurement dots (Lueur) and unmeasured points (white ring). Overlay header: dark close (aria `Fermer` → V5), caption `Pièce 3 sur 9 · Rez-de-chaussée`, title `Séjour`, dark button aria `Recommencer la pièce` (refresh icon). Live chips: `38,5 m²` (Lueur, check) and `HSP 2,50 m` (Nuit 3). AgentBubble(onDark): `Superbe séjour ! Tournez lentement vers la baie vitrée côté piscine : la lumière est idéale pour la photo.`
Bottom sheet (Ivoire, radius 20 top): `Dossier complété à 62 %` + green badges `Photos 4/4`, `360°`; linear progress (h5, 62 %); row Selects `Revêtement de sol` (`Parquet chêne`) · `Vitrage` (`Double`); primary CTA `Valider et passer à la pièce suivante` (arrow) → next room; after last room → V5c.
Screen equivalent: V5c manual row editing (name, level, area, floor covering). Propose options Revêtement: `Parquet chêne`, `Parquet`, `Carrelage`, `Moquette`, `Béton ciré`, `Stratifié`, `Vinyle`, `Autre` (values seen in V5c); Vitrage: `Simple`, `Double`, `Triple`.

### V5c · Récapitulatif des surfaces (`RecapSurfaces.dc.html`)
Purpose: table of rooms and surfaces; the v1 manual entry screen. Progress 5/7, counter `5/7`. Out `Tout est correct, continuer` → V6.
Layout:
1. TunnelHeader `Étape 5 · Pièces`, back (mockup → V5b; v1 → V5).
2. AgentBubble (templated): `Et voilà ! Nous obtenons 115 m² habitables répartis sur 5 pièces principales. Tout vous semble correct ?` → `…{total} m² habitables répartis sur {n} pièces principales…` (pièces principales = séjour/chambres/bureau, i.e. rooms flagged `is_main`).
3. Badges: `RealestyBadge.certified` `9 pièces scannées` (method-dependent: v1 manual → e.g. `{n} pièces saisies` — copy to confirm) and `RealestyBadge.toComplete` with icon `Mesures estimatives` (only for scan method).
4. Rooms card (white radius 16), grouped by level with group label 12/700 discret: `Rez-de-chaussée`, `Étage`. Each row: name 15/600, area 15/600 (`38,5`, unit implied m²), floor covering 13 discret, trailing 36px pen button aria `Modifier <nom>`. Sample rows: RDC — Entrée 6,0 Carrelage · Séjour 38,5 Parquet chêne · Cuisine 12,8 Carrelage · Bureau 7,5 Parquet · Cellier 4,2 Béton ciré · WC 1,6 Carrelage; Étage — Chambre 1 12,4 Moquette · Chambre 2 11,0 Parquet · Chambre 3 10,2 Parquet · Salle de bain 6,3 Carrelage · Dégagement 4,5 Parquet.
5. Total bar (Encre bg, white): `Surface habitable totale` + Sora 20/600 `115,0 m²` (sum of rows, 1 decimal, comma).
6. `RealestyButton.text` plus `Ajouter une pièce`.
7. AgentActionBar `Répondez à la voix ou à l’écran` / `Tout est correct, continuer`.

Room edit/add (not designed → bottom sheet): fields `Nom` (text, with quick chips: Entrée, Séjour, Cuisine, Chambre, Salle de bain, Salle d’eau, WC, Bureau, Cellier, Dégagement, Garage, Autre), `Niveau` (select: Sous-sol, Rez-de-chaussée, Étage, Étage 2, Combles), `Surface` decimal m² (0.5..500, required), `Revêtement de sol` select (optional), `Vitrage` select (optional), delete action. Validation: ≥1 room to continue. On continue, write total to property.living_area_m2 (provenance Déclaré for manual, Estimé IA/"Mesures estimatives" for scan).

### V6 · Audit vocal de vie (`AuditVie.dc.html`)
Purpose: life quality: strengths, watch-points, noise, overlooking, secret note. Progress 6/7, pill `Vocal` (despite screen form). Out `Continuer` → V7.
Layout:
1. TunnelHeader `Étape 6 · Cadre de vie`, back → V5c.
2. AgentBubble: `Au-delà de la technique, comment vivez-vous ici ? Quels sont les atouts de la maison et les points à signaler ?`
3. h2 `Atouts` + count badge (certified colors, no icon) `3`. List of item rows (white radius 12 border): leading 28px green pill icon, text 15, trailing pen icon (edit). Samples: `École primaire à 4 min à pied`, `Bus ligne 17 au bout de la rue`, `Impasse calme, sans passage`. `RealestyButton.text` plus `Ajouter un atout`.
4. h2 `Points de vigilance` + count badge toComplete `1`. Row with warning-colored pill icon: `Rue principale chargée entre 8h et 9h`. Text button `Ajouter un point`.
5. Label `Bruit et circulation ressentis` + value badge (certified colors) `3/10 · Calme`. Slider 1–10 step 1 on gradient track (#2E9E3F → #8CC63F → #F2C230 → #F08A24 → #D33A2C), thumb white 30 border 3 #5FB43A; tick labels 1…10 (selected Encre); ends `Très calme` (Vert texte) / `Très bruyant` (Erreur). **New component `NoiseSlider`** (not in DS).
6. Label `Vis-à-vis` + segmented `Aucun` / `Léger` / `Important` (Léger).
7. Card: icon + `Données du quartier ajoutées` 14/700 + `ProvenanceTag.externalSource`; text 13 discret `Exemples de sources externes qui complètent vos réponses : débit internet, qualité de l’air, projets d’urbanisme, temps de trajet réels.` (v1: static info card or hide.)
8. Textarea (h96, radius 12) label `Note secrète pour les futurs visiteurs`, sample `La meilleure boulangerie du quartier est à l’angle de la rue, et le marché du dimanche est à 5 min à pied.`
9. AgentActionBar hint `Parlez librement, l’agent classe vos réponses` / `Continuer`.

Inputs:
| Field | Type | Req. | Validation / default |
|---|---|---|---|
| Atouts (list) | add/edit/delete short text (inline field or bottom sheet — not designed) | no | 3..140 chars each, max 10 |
| Points de vigilance (list) | same | no | same |
| Bruit et circulation ressentis | slider 1..10 | no | default 3? → propose default null shown at 5 until touched; label mapping propose 1–2 `Très calme`, 3–4 `Calme`, 5–6 `Modéré`, 7–8 `Bruyant`, 9–10 `Très bruyant` (only "Calme" at 3 is in mockup) |
| Vis-à-vis | segmented `Aucun`/`Léger`/`Important` | no | – |
| Note secrète | multiline text | no | ≤ 500 chars |
Voice-only: "Parlez librement, l’agent classe vos réponses" (free speech auto-sorted into atouts/vigilance). Screen equivalent: the add buttons.

### V7 · Le Vault documents (`VaultDocuments.dc.html`)
Purpose: collect documents; transparency score; submit dossier. Progress 7/7 (all green), counter `7/7`. Out `Envoyer mon dossier à l’expert` → V8.
Layout:
1. TunnelHeader `Étape 7 · Documents`, back → V6.
2. AgentBubble: `Dernière étape : vos documents. Photographiez-les ou importez-les, je pré-remplis votre dossier et vous vérifiez.`
3. Score card: progress ring 64 (DS Ring) center `72`; title 700 `Score de transparence`; 13 discret `Ajoutez vos factures de chauffage pour atteindre le badge « Transparence Or ».` (hint = next best missing document).
4. Documents card: `RealestyListItem` rows (tile tone + title + subtitle + trailing badge [+ action link 13/700 Vert texte]):
   | Title | Subtitle (sample) | Tile tone | Badge | Action |
   |---|---|---|---|---|
   | `Titre de propriété` | `Acquisition 2012 · 540 m² confirmés` | success | certified `Analysé` (check) | – |
   | `Taxe foncière 2025` | `1 240 €/an extrait automatiquement` | success | certified `Analysé` | – |
   | `Factures d’énergie` | `3 factures · extraction en cours` | neutral | toComplete `Analyse en cours` (icon) | – |
   | `Facture travaux · PAC 2021` | `Reçue, en attente de l’expert` | neutral | neutral `Reçu` | – |
   | `Pièce d’identité` | `Obligatoire pour la certification` | error | missing `Manquant` | `Scanner` |
   | `Diagnostics` | `DPE, électricité, amiante…` | error | missing `Manquant` | `Commander` |
   | `Rapport SPANC` | `Raccordé au tout-à-l’égout` | neutral | neutral `Non concerné` | – |
5. Two buttons (h48): primary camera/scan `Scanner`; secondary upload `Importer`.
6. Info note (Surface 2, lock icon): `Documents chiffrés, consultés uniquement par l’expert en charge de votre dossier. Vous pouvez les supprimer à tout moment.`
7. AgentActionBar hint (templated) `2 documents manquants : l’expert pourra vous les redemander` → `{n} documents manquants : l’expert pourra vous les redemander`; CTA **accent** `Envoyer mon dossier à l’expert` (trailing arrow).

Inputs / rules:
- Upload: `Scanner` = camera capture (image_picker camera or document scanner, v1 camera photo is fine), `Importer` = file picker (PDF/JPG/PNG/HEIC, ≤ 20 MB). After pick, ask document kind (select, not designed — bottom sheet listing the kinds above + `Plan`, `Autre`). Row actions `Scanner` / `Commander` on missing rows open capture for that kind / external diagnostics ordering (v1: `Commander` → info sheet or hidden).
- Statuses: `Manquant` → `Reçu` (uploaded) → `Analyse en cours` → `Analysé`; `Non concerné` computed (SPANC not applicable when V4b Assainissement = Tout-à-l’égout, subtitle then `Raccordé au tout-à-l’égout`). v1 without OCR: statuses stop at `Reçu`.
- Required docs: `Pièce d’identité` is "Obligatoire pour la certification" but submit is allowed with missing docs (hint says expert may ask later). Submit requires steps V1–V6 complete.
- Transparency score: formula not designed — propose weighted doc completeness + field completeness (0–100), computed server-side.
- Data extracted (Analysé) updates property fields with provenance `document` (e.g. purchase year/area from titre, taxe foncière amount).

### V8 · Attente validation expert (`AttenteExpert.dc.html`)
Purpose: confirmation after submission; AI indicative range; expert-review timeline; notifications opt-in. No header, no progress.
Layout:
1. Success icon circle 96 Vert teinte; h1 Sora 24/600 `Merci Sophie, votre dossier est complet` (→ `Merci {prénom}, votre dossier est complet`); 15 discret `Il part en analyse chez un expert immobilier. Vous serez alertée dès que votre avis de valeur certifié sera disponible.` (gendered "alertée" — use `alerté·e` or gender-neutral copy: decision).
2. Card "Tendance IA": label 12/700 `Tendance IA` + badge toComplete `Indicative`; Sora 24/600 `495 000 – 540 000 €`; range bar (track Bordure carte h10, fill Vert Realesty, median marker 4×32 Encre); labels `495 k€` · bold `Médiane 518 k€` · `540 k€`; 13 discret `Calculée le 24/09/2026 à partir de vos réponses, documents et références de marché. Non validée par un professionnel.`; secondary button (chart icon + chevron) `Voir la synthèse du marché` → V8b. Provenance = Estimé IA.
3. Timeline card (vertical stepper, nodes 24): done (Vert texte filled, check) `Dossier complet` / `Transmis le 24/09 à 18 h 42`; current (Attention bg, 2px #8F5400 border, dot) `Analyse professionnelle` / `Réponse estimée sous 24 h`; todo (white, 2px Ligne, grey title) `Avis de valeur certifié` / `Consultable ici et envoyé par e-mail`. **New `VerticalTimeline`** (stepper nodes are in DS).
4. Row: `Me prévenir par notification` 15/600 + 13 discret `Et par e-mail à sophie.durand@email.fr`; switch on (DS switch; aria same label).
5. Bottom: primary `Aller au tableau de bord` → V9 Dashboard; text button `Consulter l’aperçu de mes données` (→ read-only summary of answers; not designed).
6. Floating pill button (Encre, h52, avatar 40 Nuit 3) `Une question ?` aria `Poser une question à l’agent Realesty` (v1: hide or open support/contact).
Inputs: notify_push toggle (default on; request OS push permission when turned on).

### V8b · Synthèse du marché (`SyntheseMarche.dc.html`)
Purpose: indicative market context. Header: back (→ V8) · title `Synthèse du marché` · share icon button (aria `Partager`). No progress.
Layout:
1. Badges: toComplete `Indicatif`; neutral with clock icon `Mis à jour le 24/09/2026`.
2. h1 `Votre bien face au marché`; 14 discret `Maison 115 m² · Chaponost · tendance IA 518 000 €, soit environ 4 504 €/m².` (template `{type} {surface} m² · {commune} · tendance IA {median} €, soit environ {median/surface} €/m².`)
3. Card `Prix au m² dans votre secteur`: range track with sector band (Vert teinte, border Vert texte), median tick, property marker (Encre circle with home icon); labels `3 800 €/m²` · `Médiane secteur 4 350 €/m²` · `5 200 €/m²`.
4. 3 KPI tiles (radius 14): `58 j` `Délai de vente moyen` · `34` `Ventes sur 12 mois` · `+2,1 %` `Évolution des prix sur 1 an`.
5. h2 `Ventes comparables récentes` + card list (tile 40 home icon, title/subtitle, right price 15/600 + €/m² 12): `Maison 108 m² · 5 p.` / `Vendue en mars 2026 · à 400 m` / `498 000 €` / `4 611 €/m²` · `Maison 124 m² · 6 p.` / `Vendue en janv. 2026 · à 900 m` / `536 000 €` / `4 323 €/m²` · `Maison 101 m² · 4 p.` / `Vendue en nov. 2025 · à 1,2 km` / `452 000 €` / `4 475 €/m²`.
6. Card h2 `Ce qui influence votre estimation`: rows with 24px pill `+` (green) or `−` (warning): `+ Pompe à chaleur 2021 et toiture refaite en 2016`, `+ Terrain de 540 m² avec piscine enterrée`, `+ École primaire à 4 min à pied`, `− Salle de bain à rafraîchir`, `− Circulation le matin sur la rue principale`.
7. Card `Biens similaires en vente` + neutral badge `5 annonces`; key/values: `Prix médian affiché` `529 000 €` · `Écart moyen prix affiché / vendu` `−3,4 %` · `Ancienneté moyenne des annonces` `41 jours`.
8. Info note: `Sources : ventes notariées (DVF) et annonces actives du secteur. Chiffres indicatifs, analysés et sera ajustés par notre expert dans votre avis de valeur.` (**copy typo** "analysés et sera ajustés" → suggest "analysés et ajustés"; confirm.)
9. Buttons: secondary (doc icon) `Consulter le rapport complet` → V9b; primary `Retour au suivi de mon dossier` → V8. Floating `Une question ?`.
No inputs. All figures are Source externe (DVF) / Estimé IA; read-only.

---

## 3. External data per screen

| Screen | Need | v1 source |
|---|---|---|
| V2 | Address autocomplete | BAN `https://api-adresse.data.gouv.fr/search/?q={q}&autocomplete=1&limit=5` (returns label, housenumber, street, postcode, city, citycode INSEE, id, coordinates lon/lat). No key. Debounce 300 ms, min 3 chars. (Note: service migrating to Géoplateforme `data.geopf.fr/geocodage/search` — same params; wrap behind a repository.) |
| V2 | "Me géolocaliser" | device GPS (geolocator) + BAN reverse `https://api-adresse.data.gouv.fr/reverse/?lon={lon}&lat={lat}` |
| V2 | Parcel at point | API Carto IGN `https://apicarto.ign.fr/api/cadastre/parcelle?geom={"type":"Point","coordinates":[lon,lat]}` (URL-encode geom) → GeoJSON FeatureCollection, properties `idu`, `section`, `numero`, `contenance` (m²), `code_insee`, `nom_com`, geometry MultiPolygon. Also `?code_insee=&section=&numero=` for manual lookup. |
| V2 | Map with aerial + parcel outline | flutter_map + IGN Géoplateforme WMTS (no key): `https://data.geopf.fr/wmts?SERVICE=WMTS&REQUEST=GetTile&VERSION=1.0.0&LAYER=ORTHOIMAGERY.ORTHOPHOTOS&STYLE=normal&TILEMATRIXSET=PM&TILEMATRIX={z}&TILEROW={y}&TILECOL={x}&FORMAT=image/jpeg`; optional overlay `CADASTRALPARCELS.PARCELLAIRE_EXPRESS` (image/png). Fallback OSM tiles (respect usage policy / attribution). Polygon from API Carto geometry. |
| V3 | none | – |
| V4b | none (later: pre-fill construction year / DPE via ADEME DPE open data by address) | – |
| V5 | plan import (AI extraction) | deferred; v1 stores file only |
| V6 | neighbourhood data (internet speed, air quality, urbanism, travel times) | deferred (ARCEP, Atmo, Géoportail urbanisme…) |
| V7 | document storage | Supabase Storage private bucket `property-documents/{property_id}/…`, RLS by owner; OCR/extraction deferred |
| V8 | AI indicative range | v1: server-side (Edge Function) from DVF: median €/m² of comparable sales (same type, commune/radius, last 24 months) × living area, ±5 % band — or hide the card until expert value exists (decision) |
| V8b | sector €/m², sales count, YoY, comparables, delay | DVF open data (`files.data.gouv.fr/geo-dvf/latest/csv/{year}/communes/{dep}/{insee}.csv`, or Cerema "DVF+" open API) ingested server-side; "Délai de vente moyen" and "Biens similaires en vente" need listings data (not open) → hide in v1 |

---

## 4. Data model (Supabase Postgres)

All tables: `id uuid pk default gen_random_uuid()`, `created_at/updated_at timestamptz not null default now()`, RLS "owner of property" (`properties.seller_id = auth.uid()`). Enumerations as `text` + `check` (consistent with existing `profiles.role`).

### `properties` (one seller dossier)
| Column | Type | Written by |
|---|---|---|
| seller_id | uuid not null → profiles(id) on delete cascade | V1 (create) |
| status | text check in ('draft','submitted','in_review','certified') default 'draft' | V7 submit → 'submitted' |
| current_step | smallint default 1 (1..7, resume point) | every step |
| ownership_type | text check in ('single','multiple') | V1 |
| address_label | text | V2 |
| address_housenumber, address_street, address_postcode, address_city | text | V2 |
| address_citycode | text (INSEE) | V2 |
| address_ban_id | text | V2 |
| lat, lng | double precision | V2 |
| parcel_confirmed | boolean default false | V2 |
| special_situations | text[] (values 'servitude_passage','servitude_reseaux','autre','aucune') | V2 |
| special_situation_other | text | V2 |
| property_type | text check in ('maison','appartement','terrain','autre') | V3 |
| property_type_other | text | V3 |
| purchase_year | smallint | V3 (V7 doc may overwrite) |
| purchase_price_eur | integer null | V3 |
| self_built | boolean | V3 |
| sale_reason | text check in ('mutation','agrandissement','separation','investissement','autre') | V3 |
| previously_estimated | boolean | V3 |
| construction_year | smallint | V4b |
| orientation | text | V4b |
| living_area_m2 | numeric(7,2) | V4b, overwritten by V5c total |
| living_room_area_m2 | numeric(6,2) | V4b |
| rooms_count, bedrooms_count | smallint | V4b |
| levels | text check in ('plain_pied','r1','r2_plus') | V4b |
| wall_material | text check in ('parpaing','brique','pierre','beton','moellon','bois','pise') | V4b |
| adjacency | text check in ('independant','1','2','3') | V4b |
| roof_type | text | V4b |
| roof_year | smallint | V4b |
| heating_energy | text check in ('electricite','gaz','fioul','pac','bois') | V4b |
| heat_pump_type | text | V4b |
| heat_pump_year | smallint | V4b |
| sanitation | text check in ('tout_a_l_egout','fosse_septique','puits_perdu') | V4b |
| outdoor_equipment | text[] ('piscine','garage','terrasse','abri_jardin','portail_motorise') | V4b |
| pool_type | text | V4b |
| pool_length_m, pool_width_m | numeric(5,2) | V4b |
| measurement_method | text check in ('scan','plan','manual') | V5 |
| noise_level | smallint check 1..10 | V6 |
| overlooking | text check in ('aucun','leger','important') | V6 |
| secret_note | text check length ≤ 500 | V6 |
| provenance | jsonb default '{}' — map column_name → 'declared'\|'document'\|'external'\|'expert'\|'ai' (+ optional source document id) | all steps; V7 extraction; expert |
| transparency_score | smallint 0..100 | server (on V7 changes) |
| submitted_at | timestamptz | V7 |
| notify_push | boolean default true | V8 |
| ai_estimate_low_eur, ai_estimate_median_eur, ai_estimate_high_eur | integer | server after V7 submit (shown V8/V8b) |
| ai_estimate_computed_at | timestamptz | server |

### `property_owners`
id, property_id uuid → properties on delete cascade, position smallint (1 = user), profile_id uuid null → profiles (for position 1), first_name text not null, last_name text not null, phone text (E.164), email text null — written by V1. Unique (property_id, position).

### `property_parcels` (supports "Modifier / ajouter" multi-parcel)
id, property_id, idu text (14-char cadastre id), code_insee text, section text, numero text, area_m2 integer (contenance), geometry jsonb (GeoJSON; or `geography(MultiPolygon,4326)` if PostGIS enabled), source text default 'apicarto' — V2.

### `previous_estimates`
id, property_id, price_eur integer not null, estimated_month date null (1st of month from `mm/aaaa`), agency_name text null — V3.

### `rooms`
id, property_id, name text not null, level text check in ('sous_sol','rdc','etage_1','etage_2','combles'), sort_order smallint, area_m2 numeric(6,2) not null, ceiling_height_m numeric(4,2) null (scan HSP), floor_covering text null, glazing text null ('simple','double','triple'), is_main boolean (pièce principale), source text check in ('scan','plan','manual'), photos_count smallint default 0, scan_data jsonb null — V5c (v1), V5b (later).

### `lifestyle_items`
id, property_id, kind text check in ('asset','watch_point'), label text not null, sort_order smallint, source text ('declared','voice') — V6.

### `property_documents`
id, property_id, kind text check in ('titre_propriete','taxe_fonciere','facture_energie','facture_travaux','piece_identite','diagnostics','rapport_spanc','plan','autre'), storage_path text not null, file_name text, mime_type text, size_bytes integer, status text check in ('received','analyzing','analyzed','rejected') default 'received', extracted jsonb null (OCR output), uploaded_at timestamptz default now() — V7 (also V4 "Importer", V5 plan).
"Manquant" / "Non concerné" are computed in the app (required kinds minus uploaded kinds; SPANC not applicable when sanitation = 'tout_a_l_egout'), not stored.

### `market_snapshots` (read-only for app, written by backend)
id, property_id, computed_at timestamptz, price_m2_low, price_m2_median, price_m2_high integer, sales_12m integer, yoy_change_pct numeric(5,2), avg_days_on_market integer null, comparables jsonb (list {type, area_m2, rooms, sold_on, distance_m, price_eur}), factors jsonb (list {sign:'+'|'-', label}), listings_summary jsonb null — V8b.

Expert review state (timeline in V8) derives from `properties.status` + `submitted_at`; a later `expert_reviews` table is out of scope.

---

## 5. V1 implementation slices (keyboard/screen-first; voice, camera scan, 3D, OCR deferred)

Each ≈1–2 h for one developer agent. Order = priority.

1. **S1 · Supabase schema** — migration for `properties`, `property_owners`, `property_parcels`, `previous_estimates`, `rooms`, `lifestyle_items`, `property_documents` + RLS + updated_at triggers + private storage bucket policy. Deps: none.
2. **S2 · `property_repository` package + tunnel shell** — models, CRUD (create draft, patch fields, upsert child rows), `SellerTunnelCubit` (current property, step, save-on-continue, resume at `current_step`); GoRouter routes `/seller/audit/1..7`; shared `TunnelHeader`, `AgentActionBar` (mic hidden via flag), `SelectableCard`. Deps: S1.
3. **S3 · V1 Propriétaires** — ownership cards, owner 1 fields (prefilled), co-owner bottom sheet + cards, validation, save. Deps: S2.
4. **S4 · V3 Contexte** — type cards, history fields, segmented, chips, conditional previous-estimate cards (+ add). Deps: S2. (Can run in parallel with S3/S5.)
5. **S5 · V2a Adresse** — BAN autocomplete field + reverse geocode "Me géolocaliser", `address_repository`; save address/lat/lng. Deps: S2.
6. **S6 · V2b Cadastre & carte** — API Carto parcel lookup, flutter_map with IGN ortho tiles + polygon, parcel card with `Source externe`, confirm/modify (tap-to-add parcels), special-situation chips; templated agent bubble. Deps: S5.
7. **S7 · V4b Audit technique (1/2)** — sections Carte d’identité + Gros œuvre (fields, selects, steppers, segmented, chips) + provenance tag rendering from `provenance` jsonb. Deps: S2.
8. **S8 · V4b Audit technique (2/2)** — Chauffage & assainissement + Extérieur & équipements with conditional PAC/piscine fields, validation, save; adapt visible sections by property_type. Deps: S7.
9. **S9 · V5 méthode + V5c tableau (manual)** — method screen (manual active, plan = upload stub, scan disabled), rooms table grouped by level, add/edit/delete room sheet, live total, templated bubble, write living_area_m2. Deps: S2 (plan upload option needs S11).
10. **S10 · V6 Cadre de vie** — atouts/vigilance list editing, `NoiseSlider`, vis-à-vis segmented, secret note, static neighbourhood info card. Deps: S2.
11. **S11 · V7 Vault (upload)** — document list with computed statuses, Scanner (camera) / Importer (file picker) + kind picker sheet, upload to Storage, delete; simple transparency score (client-side v1); submit (status → submitted, submitted_at). Deps: S1, S2 (+S8 for SPANC rule).
12. **S12 · V8 Attente expert** — confirmation screen, vertical timeline from status/submitted_at, notification switch (+ permission), buttons to Dashboard / data summary; AI card hidden unless estimate present. Deps: S11.
13. **S13 · Market data backend (optional for v1)** — Edge Function ingesting DVF for the commune → `market_snapshots` + ai_estimate_*; then V8 Tendance IA card. Deps: S1, S6.
14. **S14 · V8b Synthèse du marché** — read-only screen from `market_snapshots` (hide listings/delay blocks when null). Deps: S13.

Deferred (post-v1): V4 voice audit + mic everywhere (speech-to-text + LLM slot filling), V5b camera/AR scan, plan & document OCR extraction (provenance → "Extrait d’un document"), neighbourhood external data (V6), "Commander" diagnostics, "Une question ?" agent chat, Transparence Or badge logic.

## 6. Open questions for design/product
- V4 Night background (mockup root is Ivoire) — confirm Nuit.
- Mic button behaviour in v1 (hide vs "bientôt").
- Unspecified select option lists (Exposition, Toiture, Type de PAC, Type de piscine, Revêtement, Vitrage) — proposals above.
- Noise-slider labels other than `3/10 · Calme`.
- Gendered copy `Vous serez alertée`; typo `analysés et sera ajustés`.
- V5c badge copy when method is manual (`9 pièces scannées` only fits scan).
- Terrain / Appartement adaptation of V4b–V5.
- Not designed: address suggestions list, co-owner form, room editor, document kind picker, "Aperçu de mes données", empty/error/loading states.
