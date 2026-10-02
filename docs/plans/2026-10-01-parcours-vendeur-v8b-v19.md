# Realesty · Seller space spec, V8b → V19 ("Vendeur · Dashboard, offres & gestion")

Status: proposal (no code written). Written 2026-10-01 from `CLAUDE.md`, `docs/README.md`, `docs/decisions.md`, `docs/epics/*.md`, `docs/plans/2026-09-30-tunnel-vendeur*.md`, `supabase/migrations/*`, the current router / V8 code (`lib/app/router/*`, `lib/seller_tunnel/view/seller_home_page.dart`, `lib/seller_tunnel/steps/submitted/**`), and the parallel drafts `scratchpad/next/epic05-estimation.md` and `epic06-voice-agent.md`. This document does not repeat their data and algorithm work.

Source: Claude Design canvas "Realesty · App mobile" (claude.ai/artifact/7iUZPTfM8Kf6xrEY4nnS5v, version 1790834884-d9b1), rows y=7500 (V8, V8b), y=9940 (V9–V19) and y=4040 (C1 Coffre-fort, C2 Mon compte, which are the tab roots).
Mockup files (for developers): `scratchpad/seller-design-next/project/*.dc.html` (+ `canvas.json`). Open them in a browser for pixel reference. A text extractor is in `scratchpad/ext.py` (`python3 ext.py File.dc.html`).
Tokens and components: `scratchpad/ds-spec.md` and `lib/ui/`. Copy below is verbatim from the mockups (French, typographic ’). Values in the mockups (Sophie Durand, 525 000 €, Julien M., Chaponost…) are sample data.

Coordination with the other drafts:
- **EPIC-05** owns the numbers on V8 and V8b: DVF comparables, €/m² trend, `market_snapshots`, the `estimate-property` Edge Function, `MarketSynthesisPage` (slice E9, route `/vendeur/marche`). This spec only covers how V8b fits into navigation and links to V9b. V9b's "Secteur" tab reuses the EPIC-05 snapshot.
- **EPIC-06** owns OpenRouter calls, voice, and the agent. The floating `Une question ?` button on every V8b–V19 mockup is out of scope here; it stays hidden until EPIC-06 phase 2 (EPIC-06 Q9). Any AI-written text (listing description, report explanation) reuses the EPIC-06 OpenRouter client, under the rule: AI phrases, never invents figures.

---

## 0. Summary of the proposal

1. Once the dossier is sent (`status ≠ draft`), the seller lives in a **4-tab space** (`Mon bien` · `Visites` · `Coffre-fort` · `Compte`). **V9 Dashboard** is the `Mon bien` root. V8 becomes a status screen you reach from V9. Its `Retour à mon dossier` button turns into the mockup's `Aller au tableau de bord`.
2. The dossier lifecycle (`properties.status`) is unchanged. A **new `property_sales` row** carries the sale lifecycle: chosen formula, mandate, publication, offer, compromis, sold.
3. In v1, every action that needs another human (expert, agent, notary, buyer) is **entered by staff through the Supabase dashboard**, using documented SQL snippets or `security definer` functions. The app only reads it. A web back-office comes later.
4. The work is split into **5 epics** (EPIC-07 → EPIC-11). Before any buyer side exists, these can ship for real: EPIC-07 (dashboard + certified report), the V10/V11 formula choice and listing draft from EPIC-08, V12 slots, EPIC-11 (vault + account), plus staff-fed versions of V13–V17.

---

## 1. Navigation map

### 1.1 Current state (code)
- `/vendeur` → `SellerHomePage` ("Mon dossier vendeur": start/resume the audit, log out, design-system link in dev). `/vendeur/audit/<step>` → V1…V8 inside `ShellRoute(SellerTunnelShell)`, which provides `SellerTunnelCubit`.
- Sent dossier: `resumeStep` = V8, `SellerTunnelGate` redirects editable steps to V8. In V8, `Retour à mon dossier` (`submittedBackToDossier`) calls `context.leaveTunnel` and goes back to `SellerHomePage`, whose CTA reads `Voir mon dossier envoyé`.
- `appRedirect` lets through anything under `/vendeur/` for a seller. No tab bar exists, and the DS spec marks it "Tab bar (deferred)".

### 1.2 Target map

```
Role (02) ─ seller ─► /vendeur
   status = draft ─────► SellerHomePage (start / resume) ─► V1 … V7 ─ send ─► V8 (once, full screen)
   status ≠ draft ─────► [tab shell] Mon bien = V9

V8 ─ "Aller au tableau de bord" ─► V9            V8 ─ "Voir la synthèse du marché" ─► V8b
V8b ─ "Retour au suivi de mon dossier" ─► pop (V8 or V9)   V8b ─ "Consulter le rapport complet" (certified) ─► V9b

Tab "Mon bien" (V9 Dashboard, hub — content adapts to dossier status and sale stage)
 ├─ "Suivi de mon dossier" row (pre-certification) ─► V8 (pushed, no tabs)
 ├─ "Voir la synthèse du marché" ─► V8b (pushed)
 ├─ "Voir le rapport complet" (certified) ─► V9b (tabs visible)
 │     └─ "Mettre en vente à 525 000 €" ─► V10 sheet
 ├─ "Mettre mon bien en vente" (certified, no formula) ─► V10 bottom sheet over V9
 │     ├─ "Choisir L’Essentiel" ─► V11 ─ "Activer et préparer mon annonce" ─► V11a
 │     ├─ "Choisir Le Premium"  ─► V11b ─ "Continuer vers mes créneaux" ─► V11a (listing first; see Q6)
 │     └─ "Choisir L’Expert"    ─► V11c ─ "Signer le mandat" ─► V15
 ├─ "Préparer mon annonce" (formula 1 %, not published) ─► V11a ─ "Publier et ouvrir mes créneaux" ─► V12
 │     ├─ "Lancer la vidéo de visite" ─► V11a-2 ─► V11a-3   (deferred, §3.5)
 ├─ "Tableau de bord de vente" (1 %, published) ─► V12b ─► V16 (offer) / V13 / V14
 ├─ "Ma vente" (3 %) ─► V15 ─► V16 / V14
 └─ "Suivi de la vente" (offer accepted) ─► V17

Tab "Visites" (V13 Demandes de visite)
 ├─ calendar icon "Mes créneaux" ─► V12
 ├─ card ─► V13b profil light ─ "Accepter la visite" ─► back to V13
 └─ past visit ─► V14 compte rendu ─ "Ouvrir la négociation" ─► V16

Tab "Coffre-fort" (C1) ─ category ─► V18 (Mes documents, section opened)
Tab "Compte" (C2 Mon compte) ─ "Informations personnelles" / profile ─► V19 ; "Se déconnecter"
```

Tab bar visibility follows the mockups. **With tabs:** V9, V9b, V12, V12b, V13, V15, V17, V18, C1, C2. **Full screen (pushed above the shell):** V8, V8b, V10 (sheet), V11, V11a, V11a-2, V11a-3, V11b, V11c, V13b, V14, V16, V19, and the whole V1–V7 tunnel.

### 1.3 Routes (proposal)
| Screen | Path | Branch / presentation |
|---|---|---|
| V9 Dashboard | `/vendeur` | tab 0 root (draft → `SellerHomePage` in the same slot, §1.5) |
| V8 Attente expert | `/vendeur/audit/envoye` (unchanged) | root navigator, full screen |
| V8b Synthèse du marché | `/vendeur/marche` (EPIC-05 E9) | root navigator |
| V9b Rapport d’avis de valeur | `/vendeur/rapport` | tab 0 child |
| V10 Choix de l’offre | modal bottom sheet from V9/V9b (no route; deep link `/vendeur?formule=1` optional) | sheet |
| V11 / V11b / V11c | `/vendeur/formule/essentiel` · `/premium` · `/expert` | root navigator |
| V11a Mise en vente | `/vendeur/annonce` | root navigator |
| V11a-2 / V11a-3 | `/vendeur/annonce/captation` · `/vendeur/annonce/visite-virtuelle` | root (deferred) |
| V12b Tableau de bord de vente | `/vendeur/performance` | tab 0 child |
| V15 Commercialisation | `/vendeur/vente` | tab 0 child |
| V16 Négociation | `/vendeur/offres/:offerId` | root navigator |
| V17 Suivi de la vente | `/vendeur/vente/suivi` | tab 0 child |
| V13 Demandes de visite | `/vendeur/visites` | tab 1 root |
| V12 Créneaux | `/vendeur/visites/creneaux` | tab 1 child |
| V13b Profil acquéreur | `/vendeur/visites/:requestId` | root navigator |
| V14 Compte rendu | `/vendeur/visites/:requestId/compte-rendu` | root navigator |
| C1 Coffre-fort | `/vendeur/coffre` | tab 2 root |
| V18 Mes documents | `/vendeur/coffre/documents?rubrique=<code>` | tab 2 child |
| C2 Mon compte | `/vendeur/compte` | tab 3 root |
| V19 Informations & sécurité | `/vendeur/compte/profil` | root navigator |

Implementation: in `app_router.dart`, the existing `ShellRoute(SellerTunnelShell)` stays the outer shell. It still provides the dossier cubit (rename it `SellerSpaceShell` later if useful). Inside it sits a `StatefulShellRoute.indexedStack` with 4 branches, whose builder is a new `SellerTabScaffold` (body + `RealestyTabBar`). Full-screen routes use `parentNavigatorKey: rootNavigatorKey`. `appRedirect` needs no change, since everything stays under `/vendeur/`. Status gating lives in a `SellerSpaceGate`, the same pattern as `SellerTunnelGate`.

### 1.4 Entry conditions per screen
`S` = `properties.status`, `F` = `property_sales.formula` (null / essentiel / premium / expert), `G` = `property_sales.stage` (§4.2). When a condition fails, redirect to `/vendeur` (V9).

| Screen | Allowed when | Notes |
|---|---|---|
| V8 | S ∈ {submitted, in_review, certified} | shown once after sending; afterwards reached from V9 |
| V8b | S ≠ draft **and** an `ok` market snapshot exists (EPIC-05) | otherwise the V8 button stays hidden |
| V9 | S ≠ draft | 3 hero variants: *pending* (submitted / in_review), *certified*, *selling* (G ≥ published) |
| V9b | S = certified **and** a `valuations` row exists | |
| V10 | S = certified and F = null (or G = plan_chosen, to change formula before activation) | |
| V11 / V11b / V11c | S = certified and F = that formula and G ∈ {plan_chosen, activating} | |
| V11a | F ∈ {essentiel, premium} and G ∈ {activating, ready, published} | price and description editable after publication too (mockup: `Modifiable à tout moment, même après publication.`) |
| V12 | F ∈ {essentiel, premium} and G ≥ ready | Expert: agent handles slots → hidden |
| V12b | F ∈ {essentiel, premium} and G ≥ published | |
| V13 / V13b | G ≥ published (any formula; Expert = read-only, agent decides) | empty state before |
| V14 | a visit with a report exists | |
| V15 | F = expert and G ≥ mandate_signed | |
| V16 | an offer exists for this sale | Expert: seller sees and approves; agent negotiates (Q8) |
| V17 | G ∈ {under_offer_accepted, under_compromis, sold} | |
| C1 / V18 / C2 / V19 | always (seller role) | V18 also lists the draft's documents |

### 1.5 What replaces `SellerHomePage` and V8's "Retour à mon dossier"
- **Draft** dossier (or none): `/vendeur` keeps showing `SellerHomePage` (Commencer / Reprendre l’audit) **inside the tab shell**. That way the `Compte` tab, which takes over log-out and the dev-only design-system link, is always reachable. The `Visites` tab shows an empty state; the `Coffre-fort` tab lists the draft's documents. Alternative in Q3.
- **Sent** dossier: `/vendeur` = V9. The `Voir mon dossier envoyé` label (`sellerHomeSubmitted`) disappears.
- **V8**: `Retour à mon dossier` → **`Aller au tableau de bord`** (mockup copy, `context.go('/vendeur')`). `Consulter l’aperçu de mes données` is unchanged. The `Voir la synthèse du marché` button is unhidden by EPIC-05 E8. V8 gets a back button (`Retour`) when it is pushed from V9.
- After sending (V7 → V8), V8 shows once as the confirmation screen. Relaunching the app on a sent dossier opens V9, not V8. So `SellerTunnelState.resumeStep` for a non-draft dossier is only used by the gate, not by the home screen.
- `Se déconnecter` moves to C2 (`Compte`). The design-system link (dev flavor) goes at the bottom of C2.

### 1.6 Multiple properties
`SellerTunnelCubit` loads one dossier. The DB allows one draft but any number of sent dossiers. v1 keeps "the most recent non-draft dossier, else the draft" as the current property. A property switcher is deferred (Q12).

---

## 2. Shared building blocks

### 2.1 Existing DS components (lib/ui) reused
`RealestyButton` (primary / accent / secondary / text, `trailingIcon`), `RealestyIconButton` (Retour, Partager, Notifications, Fermer), `RealestyTextField`, `RealestySelect`, `RealestySegmentedControl` (V9b tabs, V10 tabs, V12b period, V13 filter), `RealestyChoiceChip` (V11b diagnostics, V12b feedback tags), `RealestyCheckbox`, `RealestyBadge` (essentiel / premium / expert / compatibility / passVisite / certified / toComplete / missing / neutral), `ProvenanceTag` (V9b fiche technique), `RealestyListItem` (rows with status), `InlineBanner` (info / warning), `AgentAvatar` / `AgentBubble`, `SegmentedProgress`, `RealestySnackBar`, `RealestyPressable`. Tunnel widgets: `SectionLabel`, `SectionTitle`. V8 widgets to promote to `lib/ui`: `submitted_timeline.dart` (the vertical stepper used by V8, V11c, V15 activity, V16 history, V17) and `AiEstimateCard` (the V9 pending hero).

### 2.2 New components (add to `lib/ui/components/` + gallery + tests)
| Component | Used by | Spec (from mockups / DS) |
|---|---|---|
| `RealestyTabBar` | tab shell | DS: padding 6 8 26 (+ safe area), white, top border Bordure carte; 4 items icon 22 + label 11; active Encre w700 + 4×4 dot Vert `#6CC43A`; inactive Texte discret w600; min height 48. Labels `Mon bien`, `Visites`, `Coffre-fort`, `Compte`; icons house, calendar, safe, user. `aria-label` `Navigation principale`. Badge dot for unread notifications/requests (new, Q11). |
| `RealestySwitch` / `SwitchRow` | V11 (retouche IA, home staging), V11a, V11a-3, V12, V18 visibility sheet, V19/C2 | DS "Répéter chaque semaine" toggle: title 15/600 + subtitle 13 Texte discret + switch on the right (on = Vert texte). |
| `HeroValueCard` (dark) | V9, V9b | bg Encre radius 20 padding 20; caption 12/700 uppercase `#A9B5AD`; value Sora 34/600 white; range 14 `#A9B5AD`; separator `#2F3B34`; expert avatar initials 36 `#26322B`; white button 46. Variant `pending` for the AI trend (badge `Indicative`). |
| `ActionCard` | V9 (3 rows), V17 partners | row 16 padding radius 18; icon tile 44 radius 12; title 16/700 + subtitle 13; chevron. Variants: `accent` (bg Vert `#6CC43A`, tile white 45 %) and `neutral` (white, border). |
| `KpiTile` | V8b (EPIC-05), V12b, V15 | padding 12 radius 14 white border; value Sora 18/600; label 12 Texte discret. Grid 3 columns (V12b: 2 × 3). |
| `KeyValueRow` | V9b, V11*, V16, V8b | label 14 Texte discret left, value 14/600 right, bottom border; padding 10 0. |
| `InitialsAvatar` | V9 (JM), V13 (TL), V15 (AP), V17 (HG), V19 (SD) | circle 36/40, Surface 2 or `#26322B` on dark, Sora 12–14/600. |
| `PropertySummaryCard` | V9 | white card radius 16: photo 76 radius 12 (first listing photo, otherwise placeholder with house icon), title 15/700 `Maison · 115 m² · 5 pièces`, address 13, status badge. |
| `OfferPlanCard` + `PlanTabs` | V10 | see V10. |
| `SignaturePad` | V11c (V11 if signature, Q5) | 130 h dashed border 1.5 `#D3D0C4`, radius 14; footer `Signez du bout du doigt` · `Effacer`; exports PNG (CustomPainter + `toImage`). |
| `WeekStrip` + `SlotGrid` | V12 | 7 day pills; hourly slots 3 states (`Disponible` / `Réservé` / `Fermé`) with legend. |
| `PriceRangeSlider` | V11a (price within range), V16 (counter-offer) | track with min / max labels (`505 000 €` · `545 000 €`), thumb, text field synced. |
| `MiniLineChart` | V9b Secteur (€/m² 2014→2025) | CustomPainter, no chart dependency; follow the `dataviz` skill palette. |
| `CollapsibleSection` | V18 (accordion `Tout replier`) | header: title + count + status badge + chevron. |
| `AgentFab` (`Une question ?`) | all | **not built** (EPIC-06 phase 2); listed so screens leave room (bottom inset). |

### 2.3 Feature layout and conventions
- New feature root **`lib/seller_space/`** (barrel `seller_space.dart`) with one folder per screen: `shell/`, `dashboard/` (V9), `report/` (V9b), `offers/` (V10, V11, V11b, V11c), `listing/` (V11a, V11a-2/3), `visits/` (V12, V13, V13b, V14), `sale/` (V12b, V15, V16, V17), `vault/` (C1, V18), `account/` (C2, V19). Page/View split, a cubit per screen, 100 % coverage.
- Data: a new local package **`packages/sale_repository`** (sales, mandates, orders, listing media, visits, offers, milestones, notifications, invoices). It needs a CI `dart_package` job. Valuations go into `property_repository` (`Valuation` model) after EPIC-05 E7 lands, to avoid two agents editing the same files.
- l10n prefixes: `dashboard*`, `report*`, `offerChoice*`, `activation*`, `listing*`, `slots*`, `salesBoard*`, `visitRequests*`, `buyerProfile*`, `visitReport*`, `sale*`, `negotiation*`, `saleTracking*`, `vault*`, `account*`, `tabBar*`. Add keys by read-modify-write of the ARB JSON immediately followed by `flutter gen-l10n`. Agents in the same tree must not run this concurrently: serialize ARB writes, or give each slice a separate ARB delta to merge in an integration slice.
- Copy fixes to apply in the app (design typos): V8b `sera ajustés` → `seront ajustés` (EPIC-05 already rewrites the sentence); `L'Essentiel` / `L'Expert` straight apostrophes → `L’Essentiel` / `L’Expert`; V11a badge `Premium · 1 %` must follow the chosen formula.

---

## 3. Screens

Each section lists: purpose · layout → components · verbatim copy · inputs and actions · data and its source. "Staff" means data entered by the Realesty team through the Supabase dashboard in v1 (§5).

### V8b · Synthèse du marché (`SyntheseMarche.dc.html`) — numbers in EPIC-05
- **Purpose**: show how the property sits against its sector, before certification; send the seller back to their follow-up or forward to the certified report.
- **Layout and data**: owned by EPIC-05 §5 / slice E9 (`MarketSynthesisPage`, `MarketRangeBar`, KPI tiles, comparables, factors, sources). Not repeated here.
- **Navigation (this spec)**:
  - Header: `Retour` = `context.pop()`, back to wherever it was opened (V8 or V9). `Partager` hidden in v1 (EPIC-05 Q7).
  - Footer, 2 buttons: `Consulter le rapport complet` (secondary, doc icon) **only when** S = certified and a valuation exists → `/vendeur/rapport`. `Retour au suivi de mon dossier` (primary) → pop. When opened from V9, the primary label stays the mockup's (it brings you back to the follow-up hub).
  - Entry points: V8 `Voir la synthèse du marché`; V9 *pending* hero `Voir la synthèse du marché` (new link, same label); V9b *Secteur* tab footer link (optional).
  - Hidden: `Une question ?`.
- **UX states**: snapshot `insufficient` → no V8b entry (V8 shows the EPIC-05 message); loading skeleton; read failure → `InlineBanner` + `Réessayer`.

### V9 · Dashboard propriétaire (`Dashboard.dc.html`) — tab "Mon bien" root
- **Purpose**: the seller's hub. It shows where the dossier and the sale stand and offers the single next action.
- **Layout → components** (top to bottom):
  1. Greeting: `Bonjour` (13/600 Texte discret) + first name (Sora 24/600, `profiles.first_name`); `RealestyIconButton` bell `Notifications` → notifications sheet (§3.13; hidden until EPIC-11 K4).
  2. `AgentBubble` (static copy per state, no LLM in v1).
  3. `PropertySummaryCard`: `Maison · 115 m² · 5 pièces` / `12 rue de la Colombe, Chaponost` / badge (`Rapport disponible` certified, success + check; *pending*: `Analyse en cours` neutral; *selling*: `En ligne` success).
  4. Hero:
     - *pending* (submitted / in_review): `HeroValueCard.pending` with the EPIC-05 Tendance IA (reuses `AiEstimateCard` data: `Tendance IA` · `Indicative` · range) + secondary link `Voir la synthèse du marché` (→ V8b) + `ActionCard.neutral` **`Suivi de mon dossier`** / subtitle = V8 step text (`Réponse estimée sous 24 h`, `Un expert analyse votre dossier`) → V8. When no estimate exists (EPIC-05 `insufficient`): `InlineBanner.info` `Pas assez de ventes comparables près de chez vous : l’expert vous donnera directement son avis de valeur.` (EPIC-05 copy).
     - *certified*: `HeroValueCard`: `Avis de valeur certifié` · badge `Certifié` · `525 000 €` · `Fourchette 505 000 – 545 000 € · Tendance IA initiale 518 000 €` · `JM` `Validé par Julien M., expert immobilier · 25/09/2026` · button `Voir le rapport complet` (→ V9b).
  5. Next action (`ActionCard`), depending on F / G:
     - certified, F = null: accent **`Mettre mon bien en vente`** / `Choisissez votre formule, dès 1 % au succès` → V10 sheet.
     - F = 1 %, G ∈ {activating, ready}: accent `Préparer mon annonce` / `Photos, description et prix avant publication` (new copy) → V11a; when G = plan_chosen → back to V11/V11b.
     - F = 1 %, G ≥ published: neutral **`Tableau de bord de vente`** / `Vues, visites, offres et diffusion en un coup d’œil` → V12b.
     - F = expert: neutral `Ma vente` / `Votre vente est pilotée par nos agents` (V15 copy) → V15.
     - G ≥ offer accepted: accent `Suivi de la vente` / `Sous compromis` → V17.
  6. `ActionCard` `Nos partenaires` / `Diagnostics, assurances, énergie, patrimoine` → C3: **hidden in v1** (C3 not in scope).
  7. Card **`Mon dossier`** + `92 %` + 6 px progress bar (= `transparency_score`, existing column), with 3 rows:
     - `Documents` / `6 analysés · 2 à compléter` + badge `Action requise` (warning, when required docs are missing: ID of each owner, diagnostics before publication) → V18.
     - `Surfaces & pièces` / `115 m² · 9 pièces · 24 photos · visite 360°` → V8 data preview sheet (`DossierSummarySheet`, existing) opened on the surfaces section. v1 subtitle: `{area} m² · {rooms} pièces` + `· {n} photos` once listing photos exist; drop `visite 360°` until V11a-3.
     - `Cadre de vie` / `3 atouts · 1 point de vigilance` (count of `lifestyle_items`) → same sheet, lifestyle section.
  8. `RealestyTabBar` (active `Mon bien`).
- **Agent bubble copy**: certified = `Votre avis de valeur certifié est disponible. Voulez-vous que je vous explique le rapport ou que l’on compare les 3 formules ensemble ?` (mockup). Other states (new copy, to validate): submitted `Votre dossier est entre les mains de notre expert. Je vous préviens dès que votre avis de valeur certifié est prêt.`; selling `Votre annonce est en ligne. Je surveille les demandes de visite pour vous.` No question in the bubble while the agent can't answer (EPIC-06): drop the second sentence of the certified copy in v1, or keep it if `Une question ?` ships.
- **Data**: `properties` (+ `rooms`, `lifestyle_items`, `property_documents` counts), `market_snapshots` (EPIC-05), `valuations` (§4.1), `property_sales` (§4.2), `profiles.first_name`. Cubit `DashboardCubit` combines them and refreshes on resume and pull-to-refresh. Realtime is not needed in v1.

### V9b · Rapport d’avis de valeur (`RapportValeur.dc.html`)
- **Purpose**: the expert's certified valuation, explained, with the path to listing.
- **Layout**: header `Retour` · `Rapport d’avis de valeur` · `Partager` (v1: shares the PDF link if present, otherwise hidden). Property card: photo, `12 rue de la Colombe 69630 Chaponost · Maison 115 m²`, badge `Certifié`. `HeroValueCard`: `Valeur certifiée` · `525 000 €` · `Fourchette 505 000 € – 545 000 € · soit 4 565 €/m²` · `JM Validé par Julien M., expert immobilier · 25 septembre 2026` · secondary button **`Télécharger le rapport (PDF · 11 pages)`** (signed URL from bucket `valuation-reports`; hidden when there is no PDF). Then `RealestySegmentedControl` with 4 tabs **`Synthèse` · `Le bien` · `Secteur` · `Prix`** and the tab bar.
- **Tab Synthèse**: 2 tiles `Prix conseillé` / `525 000 €` / `au cœur de la fourchette` and `Délai estimé` / `≈ 8 sem.` / `à ce prix`. `Comment nous arrivons à ce chiffre`: 4 numbered steps (`Tendance IA avant la visite` 518 000 € · `Analyse des méthodes` `ventes 70 % · concurrence 30 %` 521 000 € · `Constat de visite` `luminosité, état relevé` `+ 4 000 €` · `Valeur certifiée` `arrondie par l’expert` 525 000 €). `Pourquoi cette valeur` (+ / − lines). `Le prix décide du délai` / `Plus le prix s’éloigne de la valeur, plus la vente s’allonge.` + 4 rows (`505 000 €` `≈ 5 semaines` … `585 000 €` `très peu de visites`). Expert quote in quotation marks + signature `Julien M. · Expert immobilier · Realesty`. `Et maintenant ?` → `ActionCard.accent` **`Mettre en vente à 525 000 €`** / `Choisir ma formule, dès 1 % au succès` → V10 sheet (hidden when F is already set).
- **Tab Le bien**: description paragraph; `Fiche technique` / `Chaque information indique sa provenance.` + legend `Déclaré Document Externe Vérifié`, then rows label · value · `ProvenanceTag` (from `properties` columns + `properties.provenance`; the expert can upgrade a field to `expert` = `Vérifié`); `Surfaces pièce par pièce` / `Relevé par scan pièce par pièce dans l’appli.` (v1 text: `Déclaré pièce par pièce dans l’appli.` when `measurement_method = manual`), grouped by level, total `Surface habitable totale` (from `rooms`); `À proximité, à pied` + `Score piéton 10/10 · …` + POI list → **hidden in v1** (needs OSM/BPE data: backlog, shared with V6 "Données du quartier").
- **Tab Secteur**: `Prix moyen des maisons à {ville}` / `€/m² · 2014 à 2025` line chart + `4 258 €/m² prix moyen des maisons en 2025` / `+28,2 % depuis 2014 · +0,1 % sur 12 mois` / `63 ventes de maisons sur le secteur en 2025` / `98 jours délai de vente moyen en France`. `Ce qui s’est réellement vendu` / `Base DVF · maisons comparables à moins de 300 m` + rows. **Address rule**: the mockup shows `36 rue Lucien Cozon`, but the owner decided "street without number" (decisions 2026-10-01), so render `rue Lucien Cozon`. Expert note `Vente rue des Fauvettes écartée (bien atypique). Médiane retenue : 4 250 €/m².` `Les biens qui vous font concurrence` (A–E with `Retenu` / `Écarté`): **from the expert's input** (listings aren't an open source; the expert types them). Risks line `Sols et risques · …` (Géorisques, typed by the expert in v1). Curve and comparables come from the EPIC-05 snapshot as computed at submission; the expert's retained/excluded choices come from `valuations.comparables_override`.
- **Tab Prix**: `Ce qui déplace le prix` (base × surface, ± adjustments, `Méthode 1 corrigée`); `La méthode` / `Les ventes donnent la base, la concurrence dit ce que verra votre acquéreur.` (weights, `Pondération des méthodes`, `Contrôle : tendance IA`); `Ce qui vous revient` / `Sur la base du prix conseillé, hors diagnostics.` (`Avec Realesty · 1 % au succès` 519 750 € · `Avec une agence classique · 4 %` 504 000 € · `Vous gardez en plus` `+ 15 750 €`, **computed in the app** from the value: 1 % vs 4 %); `Le calcul que fera votre acquéreur` (`Prix affiché` · `+ Frais de notaire (≈ 7,5 %)` · `+ {works}` · `Coût total de son projet`, notary fees computed at 7.5 %, works line from the expert); `Sources …` line; legal footer `Avis de valeur établi à partir des déclarations du propriétaire, des documents du coffre-fort et des données publiques. Il ne constitue pas une expertise au sens réglementaire ; validité 3 mois.`
- **Data**: `valuations` (§4.1, staff-written JSON sections), `properties`/`rooms`, `market_snapshots` (EPIC-05). Everything is read-only.

### V10 · Pop-up choix de l’offre (`ChoixOffre.dc.html`)
- **Purpose**: compare the 3 formulas and pick one.
- **Layout**: modal bottom sheet over V9 (dimmed background), title `Choisissez votre formule`, `Fermer`. `PlanTabs` = 3-segment control `1 %` · `1 % Premium` · `3 %`, **default tab = Premium** (mockup state `t = 1`; Q7). Each `OfferPlanCard`: badge (`RealestyBadge.essentiel/premium/expert`) + tagline, name (Sora), price line, fee line, estimate line, check-list, CTA.
  - Essentiel: `L’Essentiel · 1 %` `L’autonomie accompagnée` · `L’Essentiel` · `1 % au succès` · `Aucun frais de dossier · aucun abonnement` · `Soit ~5 250 € de commission sur la base de votre avis de valeur.` · ✓ `Audit IA complet et dossier technique certifié` · `Diffusion de votre annonce sur les portails` · `Filtrage des acquéreurs par le Pass Visite` · `Calendrier en direct : les acquéreurs réservent eux-mêmes` · `Retouche photo IA et home staging virtuel` · CTA **`Choisir L’Essentiel`**.
  - Premium: `Premium · 1 %` `La sérénité totale` · `Le Premium` · `1 % au succès` · `+ 299 € de frais de dossier · 99 €/mois` · `Soit ~5 250 € …` · ✓ `Tout L’Essentiel : audit IA, dossier certifié, diffusion, filtrage Pass Visite` · `Retouche photos IA, Homestaging virtuel vidéo immersive IA` · `Coaching humain et visibilité boostée` · `Requalification humaine de chaque acquéreur avant la visite, avec compte rendu` · CTA **`Choisir Le Premium`**.
  - Expert: `L’Expert · 3 %` `Zéro contrainte` · `L’Expert` · `3 % au succès` · `Honoraires uniquement en cas de vente` · `Soit ~15 750 € d’honoraires sur la base de votre avis de valeur.` · ✓ `Tout le Premium, avec un agent dédié` · `Visites menées par l’agent` · `Négociation des offres à votre place` · `Suivi complet jusqu’à la signature chez le notaire` · `Géré par Realesty ou une agence partenaire` · CTA **`Choisir L’Expert`**.
  - Hint `Touchez un onglet ou un point pour comparer les 3 formules` + text button `Comparer les 3 formules` (v1: a full-screen comparison table built from the same 3 lists; or hide it, Q7).
- **Action**: CTA → RPC `choose_formula(property_id, formula)` creates or updates `property_sales` (stage `plan_chosen`) → push V11 / V11b / V11c. Commission estimates = `round(valuation.value × rate, -1)` with `frenchNumber`. Allowed when S = certified.
- **Data**: `valuations.value_eur`; plan constants (rates, fees) in a Dart `SalesPlan` enum, mirrored in a `sales_plans` SQL check (Q4 for prices).

### V11 · Gestion 1 % L’Essentiel — activation (`ActivationEssentiel.dc.html`)
- **Purpose**: activate the Essentiel formula: accept the mandate, prepare photos, sort out diagnostics.
- **Layout**: header `Retour` (→ V10 sheet on V9) · `Formule L’Essentiel`; badges `L’Essentiel · 1 %` + `Activation en cours`; h1 `Activons votre formule L’Essentiel`; lede `Vous gardez la main, l’IA vous accompagne. Aucun frais : vous ne payez que si vous vendez.`; `AgentBubble` `Avec L’Essentiel, les acquéreurs certifiés Pass Visite réservent directement dans votre calendrier. Je vous aide pour les photos et je filtre les demandes.`; 3-step chips `1 · Mandat` `2 · Photos` `3 · Diagnostics` (anchors; done state from data).
  - Card `Votre formule L’Essentiel · 1 %`: `KeyValueRow`s `Frais de dossier` `0 €` · `Abonnement` `Aucun` · `Commission` `1 % au succès, soit ~5 250 €` · `Mandat` `Exclusif · sans engagement` + check-list (as V10 + `Calendrier en direct : les acquéreurs certifiés réservent eux-mêmes leur visite`, `Retouche photo IA et home staging virtuel inclus`).
  - Card `Mandat exclusif sans engagement` + badges `Exclusif` `Sans engagement`: rows `Type de mandat` `Exclusif` · `Durée` `Sans engagement` · `Résiliation` `À tout moment, en un clic`; `Pourquoi l’exclusivité ? Elle sécurise votre vente et nous permet d’engager tous nos moyens sur votre bien :` + 3 bullets (`Un seul prix et une seule annonce partout : …`, `Notre pack de communication complet est déployé sur votre bien : …`, `Chaque acquéreur passe par le Pass Visite : …`); `Vous restez libre : vous pouvez résilier le mandat à tout moment depuis votre espace, sans frais.`; `RealestyCheckbox` `J’ai lu et j’accepte les conditions du mandat L’Essentiel`; button **`Signer le mandat en ligne`**; hint `Votre pièce d’identité sera demandée à la signature.`
  - Card `Vos photos` + badge `À faire`: `Avec L’Essentiel, vous prenez vous-même vos photos : l’agent vous guide pièce par pièce et l’IA leur donne un rendu professionnel.`; `SwitchRow` `Retouche automatique IA` / `Luminosité, perspectives, objets personnels`; `SwitchRow` `Home staging virtuel` / `Proposé pour les pièces vides ou datées`; button `Prendre mes photos avec l’assistant` → v1: V11a photo picker (the guided capture V11a-2 is deferred).
  - Card `Options à la carte` + `Facultatif`: 3 rows with `Ajouter` (`Shooting photo` `Photographe partenaire, environ 1 h 30` `200 € TTC`; `Shooting photo + vidéo` `Photos et film de présentation du bien` `350 € TTC`; `Diagnostics obligatoires` `Diagnostiqueurs partenaires, présélection par l’IA` `250 € TTC`) + link `J’ai déjà mes diagnostics : les importer` (→ V18 Énergie section with an upload action).
  - Upsell link `Besoin d’être plus accompagné ? Le Premium ajoute coaching humain et requalification de chaque acquéreur.` → V11b (changes the formula while G = plan_chosen).
  - Sticky CTA **`Activer et préparer mon annonce`** → V11a.
- **Actions / rules**: `Signer le mandat en ligne` is enabled when the box is ticked; an invalid tap shows the error (tunnel pattern). v1 = **click-through acceptance** (Q5): RPC `accept_mandate(sale_id, terms_version)` stores the acceptance, then a server job renders the PDF into the vault. If the owner's ID document is missing (V7 can be sent without the co-owner's), show `InlineBanner.warning` with a link to V18 Identité. `Ajouter` creates a `sale_orders` row (`requested`); staff call back (no payment in the app). `Activer…` requires the mandate to be accepted, then stage → `activating`.
- **Data**: `property_sales`, `mandates`, `sale_orders`, `valuations.value_eur`.

### V11b · Gestion 1 % Premium — activation (`GestionPremium.dc.html`)
- **Purpose**: activate Premium: payment, shooting, diagnostics.
- **Layout**: header `Formule Premium`; badges `Premium · 1 %` `Activation en cours`; h1 `Activons votre formule Premium`; steps `1 · Paiement` `2 · Shooting` `3 · Diagnostics`.
  - Card `Prélèvement SEPA` + badge `Autorisé`: rows `Frais de dossier` `299 € · prélevés le 26/09` · `Abonnement` `99 €/mois` · `Commission` `1 % au succès`; `IBAN` field `FR76 •••• … 4821`. **v1: not built** (no payment provider, §5.3). Replace it with an `InlineBanner.info` `Un conseiller Realesty vous appelle pour mettre en place votre formule Premium.` (new copy) and a callback request (`sale_orders` kind `premium_setup`). Q4.
  - Card `Shooting photo professionnel` + `Option`: `Tarif préférentiel Realesty`, 2 choices `Photo 200 € TTC Environ 1 h 30` / `Photo + vidéo 350 € TTC Avec film de présentation` (`SelectableCard`), `Un photographe partenaire vient chez vous (environ 1 h 30). Créneau choisi :`, 3 slot chips (`Mar. 29 sept · 10 h` …), confirmation line `Shooting photo validé · 200 € TTC` + `Modifier ou annuler`. v1: the seller picks preferred slots; staff confirm (`sale_orders.status = scheduled`, `scheduled_at`). The proposed slots are typed by staff or generated (next 3 weekdays at 10 h / 14 h, Q10).
  - Card `Diagnostics obligatoires` + `Option`: `Obligatoires pour vendre. Faites-les réaliser par nos diagnostiqueurs partenaires à tarif préférentiel, ou importez les vôtres.`; `InlineBanner.warning` `Aucun diagnostic valide trouvé dans votre coffre-fort.` (shown when no `diagnostics` / `dpe` document exists); `Présélection de l’IA d’après votre audit (construction 1998, pompe à chaleur)` + chips `DPE` `Électricité` `Termites` `État des risques` `Gaz` `Amiante` `Plomb` (pre-selected by **deterministic rules**, not the LLM: DPE + ERP always; électricité / gaz when the installation is over 15 years old or unknown; amiante when built before 07/1997; plomb before 1949; termites when the commune is in a prefectoral zone (data needed, default "à vérifier"). Show "IA" wording only if the owner wants it, Q9); `250 € TTC Tarif préférentiel Realesty`; button `Valider les diagnostics · 250 € TTC` (→ `sale_orders` diagnostics `requested`); link to V18 to import.
  - Sticky CTA **`Continuer vers mes créneaux`**. Proposal: go to **V11a** first (the listing must exist before slots), then V11a → V12. The mockup links V11b straight to V12 (Q6).
- **Note**: Premium has no mandate step in the mockup, but a mandate is legally required for any formula (Q5). Add the same mandate card as V11 as step 0.

### V11c · Gestion 3 % — identité & mandat (`GestionExpert.dc.html`)
- **Purpose**: sign the exclusive mandate so an agent takes over.
- **Layout**: header `Formule Expert`; badge `L’Expert · 3 %`; h1 `Confiez la vente à nos agents`; lede `Visites, négociation et suivi notaire pris en charge.`; timeline card (promoted `SubmittedTimeline`): `Identité vérifiée` / `Sophie Durand, Marc Durand` (done) · `Mandat de vente` / `À signer par chaque propriétaire` (current) · `Agent assigné` / `Sous 24 h après signature` (todo). Mandate card: doc icon, `Mandat de vente` / `6 pages · Realesty / agence partenaire`, button `Lire` (opens the PDF from `mandates.document_path`); rows `Prix de présentation` `525 000 €` · `Honoraires` `3 % du prix de vente` · `Durée` `3 mois` · `Exclusivité` `Oui`. `Signature de Sophie Durand` + `SignaturePad`; checkbox `J’ai lu le mandat et j’accepte ses conditions.`; sticky CTA **`Signer le mandat`** → V15.
- **Rules**: one signature per owner (`mandate_signatures` per `property_owners` row). The current user signs for themselves; the timeline stays at `À signer par chaque propriétaire` until every owner has signed (co-owners need their own access, Q12). `Identité vérifiée` = each owner's `identity_verified_at` (staff, after checking the ID document). Until it is verified, the step shows `À vérifier` and signing is disabled with `Votre pièce d’identité doit être vérifiée par notre équipe avant la signature.` (new copy).
- **Data**: `mandates`, `mandate_signatures` (PNG in a private bucket), `property_owners.identity_verified_at`, `valuations.value_eur` as default presentation price (editable by staff).

### V11a · Gestion 1 % · Mise en ligne (`GestionEssentiel.dc.html`)
- **Purpose**: review and publish the listing (photos, description, price).
- **Layout**: header `Retour` (→ V9) · `Mise en vente` · `Aperçu` (eye icon → read-only listing preview; v1 hidden or simple preview). Badges `{formula} · 1 %` + `Brouillon` / `En ligne`; h1 `Votre annonce est prête`; lede `Générée à partir de votre audit. Relisez, ajustez, publiez.`
  - `Photos` + count `24 photos`: horizontal grid (first 4 with room labels + `+ 19`), tap → full-screen manager (add from library or camera, reorder, assign a room from `rooms`, delete, pick the cover). `SwitchRow`s `Retouche automatique IA` / `Luminosité, perspectives, floutage des photos personnelles` and `Home staging virtuel` / `Proposé pour les pièces vides ou datées` (v1: preferences only, saved on `property_sales`; processing deferred, show `Bientôt` caption, Q9).
  - `Visite virtuelle 360°` + `À réaliser`: copy `Filmez en vous baladant méthodiquement, pièce par pièce : notre IA reconstitue une visite virtuelle pour votre annonce.` + 3 bullets (`Environ 5 à 10 minutes pour une maison`, `Portes ouvertes, lumières allumées, rideaux tirés`, `L’agent vous guide pièce par pièce, à la voix`) + `Lancer la vidéo de visite` / `Voir un exemple de rendu`. **v1 hidden** (deferred, §5.5).
  - `Description` + badge `Généré par IA`: text preview + `Modifier le texte` (bottom sheet with a multiline `RealestyTextField`, 2 000 chars). v1 generation: a deterministic template from the audit, or an EPIC-06 OpenRouter call `generate-listing-description` (facts only from the dossier). Badge `Généré par IA` → `Modifié par vous` after an edit.
  - `Prix de présentation` + badge `Dans la fourchette` (success) / `Hors fourchette` (warning): `Votre prix` field `525 000 €` + `Modifiable à tout moment, même après publication.`; `PriceRangeSlider` `505 000 €` · `Avis de valeur certifié` · `545 000 €`; `La commission et l’annonce se mettent à jour automatiquement. Un prix hors fourchette peut allonger le délai de vente : l’expert vous le signalera.`; rows `Commission au succès` `1 % · 5 250 €` (live) · `Diffusion` `Realesty + portails` (v1: `Realesty`, §5.4) · `Visites` `Pass Visite requis`.
  - Sticky CTA **`Publier et ouvrir mes créneaux`** → RPC `publish_listing(sale_id)` (checks: mandate accepted, ≥ 1 photo (Q10: minimum), description, price) → stage `published`, `published_at` → V12.
- **Data**: `property_sales` (asking_price_eur, description, toggles), `listing_photos` + bucket `listing-media`, `rooms` (labels), `valuations` (range).

### V11a-2 · Captation vidéo de la visite (`CaptationVisite.dc.html`) and V11a-3 · Visualisation de la visite virtuelle (`VisiteVirtuelle.dc.html`) — deferred
- V11a-2: full-screen camera, `Pièce 1 sur 9 · Entrée / Séjour`, `Visite virtuelle REC 02:14`, coaching `Tournez lentement vers la droite`, agent voice bubble, quality chips `Luminosité OK` `Stabilité OK` `Un peu rapide`, room list, `Mettre en pause`, `Terminer l’enregistrement`, `Pièce suivante`.
- V11a-3: 360° viewer, `Séjour · 38,5 m²` `360°`, `Glissez pour regarder autour`, `Générée par l’IA` `À valider`, room list, `Plan de la visite` `Plain-pied`, `Vidéo source` `6 min 42 s`, `Pièces reconstituées` `9 sur 9`, `Surfaces mesurées` `115 m²`, switches `Flouter visages et photos personnelles` / `Afficher les métrés`, `Refilmer une pièce`, `Publier dans l’annonce`.
- **Why deferred**: 3D or 360° reconstruction from video is a product in itself (camera pipeline, heavy server processing, viewer). See §5.5 options. Nothing is built in v1; the V11a card is hidden.

### V12 · Gestion des créneaux de visite (`GestionCreneaux.dc.html`)
- **Purpose**: the seller publishes the time slots in which certified buyers can book (1 % formulas).
- **Layout**: header `Retour` · `Créneaux de visite`; h1 `Mes disponibilités`; lede `Les acquéreurs certifiés réservent dans vos créneaux. En Premium, un agent les requalifie avant confirmation.`; `AgentBubble` `Voulez-vous ouvrir aussi le samedi après-midi ? Beaucoup d’acquéreurs ne sont disponibles que le week-end.` (static tip, shown when no weekend slot is open); `WeekStrip` `Semaine du 28 sept.` + `Semaine précédente` / `Semaine suivante` + 7 day pills (`Lun 28` … `Dim 4`); day title `Samedi 3 octobre`; `SlotGrid` hours `09:00`…`18:00` (no 13:00, as in the mockup), legend `Disponible` `Réservé` `Fermé`; `SwitchRow` `Répéter chaque semaine` / `Mêmes créneaux jusqu’à la vente`; row `Durée d’une visite` / `45 min · 15 min de battement` (`RealestySelect`: 30 / 45 / 60 min); button **`Voir les demandes de visite`** → V13; tab bar (tab `Visites` active, since V12 is a child of the Visites branch).
- **Actions**: tap a slot to toggle Disponible ↔ Fermé; `Réservé` slots (accepted requests) can't be toggled (snackbar `Ce créneau est réservé : annulez d’abord la visite.`, new copy). Saves are debounced, with the 15 s timeout pattern.
- **Data**: `visit_availability` (weekly rules when repeat is on) + `visit_slot_overrides` (dated changes), `property_sales.visit_duration_min` / `visit_repeat_weekly`; booked = accepted `visit_requests`. Fully buildable without buyers.

### V12b · Tableau de bord de vente (`PerformanceVente.dc.html`)
- **Purpose**: listing performance at a glance (1 % formulas).
- **Layout**: header `Retour` · `Tableau de bord de vente` · `Partager` (hidden v1); badges `Premium · 1 %` + `En ligne depuis 12 jours`; `AgentBubble` (template from counts: `Votre annonce a été vue {views} fois et {visits} visites ont eu lieu. Une offre vous attend : voulez-vous qu’on l’analyse ensemble ?`); period segmented `7 jours` · `30 jours` · `Depuis la mise en ligne`; 6 `KpiTile`s `1 248 Vues de l’annonce` · `43 Mises en favori` · `18 Demandes de visite (Pass Visite)` · `6 Visites réalisées` · `2 Visites à venir` · `1 Offre reçue`; section `Offres` + `1 à examiner` → offer row (`TL` · `Thomas & Léa B.` · `Reçue aujourd’hui · financement validé` · `505 000 €`) → V16; `Prochaines visites` + `Tout voir` (→ V13) with 2 rows (`Nadia K. · 94 % compatible` `Sam. 3 oct. · 11 h 00` badge `Confirmée` / `À confirmer`); `Diffusion de l’annonce` `6 sites` + portal rows (`Realesty 612 vues · 12 demandes En ligne`, SeLoger, Leboncoin, Bien’ici, Logic-Immo, `Agences partenaires Diffusion au réseau · demain En attente`); `Retours des visiteurs` + `Comptes rendus` (→ V14) + tag chips (`Luminosité` `Garage atelier` `Piscine` `Salle de bain à rafraîchir`); tab bar.
- **v1 data**: requests / visits / offers counts from Realesty tables. **Views and favourites** need a buyer app (or portal feeds), so hide those 2 tiles until the buyer side exists (Q13). `Diffusion` shows only `Realesty` (`En ligne`), and portal rows are hidden (§5.4). Tags = the most frequent `visit_reports.liked` and `concerns`.

### V13 · Demandes de visite (`DemandesVisites.dc.html`) — tab "Visites" root
- **Purpose**: accept or refuse the buyers' visit requests.
- **Layout**: title `Visites` + `RealestyIconButton` calendar `Mes créneaux` (→ V12); h1 `Demandes de visite`; `AgentBubble` (template: `{n} nouvelles demandes. {name} sont les plus compatibles ({score} %) et ont été requalifiés par un agent. Je vous résume leur profil ?`; v1 drop the question); segmented `En attente · 3` · `Confirmées · 2` · `Passées`; request card: `InitialsAvatar` `TL`, name `Thomas & Léa B.` (→ V13b), `Sam. 3 oct. · 10 h 00`, `RealestyBadge.compatibility` `94 % compatible`, badges `Pass Visite` `Requalifié par un agent` `Budget validé` `Mandat signé`, buttons `Refuser` (secondary) / `Accepter` (primary); tab bar.
- **Actions**: RPC `respond_visit_request(id, 'accepted'|'refused')`, with an optimistic update and a confirmation sheet for `Refuser` (optional reason). Expert formula: read-only (badge `Géré par votre agent`, new copy).
- **Empty states** (new copy): pending `Aucune demande pour l’instant. Les acquéreurs certifiés réservent dans vos créneaux.` + button `Ouvrir des créneaux`; before publication `Les demandes de visite arriveront dès la mise en ligne de votre annonce.`
- **Data**: `visit_requests` (+ `buyer_snapshot` jsonb). Before the buyer side exists, rows are inserted by staff (agency visits, phone leads) or by a demo seed (§5.2).

### V13b · Vue profil « light » acquéreur (`ProfilAcheteur.dc.html`)
- **Purpose**: know who is coming without seeing their private data.
- **Layout**: header `Retour` · `Profil acquéreur`; `InitialsAvatar` + `Thomas & Léa B.` + badges `Pass Visite certifié` `Mandat signé`; big score `94 %` `Matching Score` with 3 bars `Intérieur 33/35` · `Extérieur & trajets 32/35` · `Financement 29/30`; `Pourquoi votre maison leur correspond` (3 lines); rows `Foyer` `Couple, 1 enfant` · `Financement` `Validé par le courtier` · `Capacité` `Compatible avec votre prix` · `Calendrier` `Achat sous 3 mois`; `InlineBanner.info` `Coordonnées, revenus et pièces justificatives restent masqués. Ils ne sont jamais partagés avec le vendeur.`; footer `Refuser` / **`Accepter la visite`** (→ V13, same RPC).
- **Data**: `visit_requests.buyer_snapshot` (a frozen light profile, never a join to the buyer's private tables; RLS principle §4.6). The score and reasons come from the future buyer tunnel (A1–A5); staff-entered rows may leave them empty, and the UI then hides those blocks.

### V14 · Compte rendu (`CompteRendu.dc.html`)
- **Purpose**: debrief of a visit carried out by an agent (Premium requalification / Expert visits).
- **Layout**: header `Retour` · `Compte rendu` · `Partager` (hidden); `Visite du sam. 3 oct. · 10 h 00` + formula badge; h1 `Compte rendu de visite`; author card `CR` `Camille, agence partenaire` / `Agence Val d’Yzeron · a mené la visite` / `Saisi dans l’Espace Agences · publié le 3 oct. à 12 h 10`; buyer card (`TL` `Thomas & Léa B.` `Pass Visite · financement validé` `94 % compatible`); `Niveau d’intérêt` `Élevé`; `Points appréciés` (4 lines); `Freins exprimés` (2 lines); `Prochaine étape` chips `Contre-visite` `Offre annoncée` + text; CTA **`Ouvrir la négociation`** (→ V16 when an offer exists; otherwise hidden).
- **Data**: `visit_reports` (staff-written in v1; written by agencies through P10 later). Read-only.

### V15 · Commercialisation (3 %) (`Commercialisation.dc.html`)
- **Purpose**: the Expert-formula seller follows what the agent does.
- **Layout**: title `Ma vente` + bell; badges `L’Expert · 3 %` `En commercialisation`; h1 `Votre vente est pilotée par nos agents`; agent card `AP` `Camille, agence partenaire` / `Ouest lyonnais · répond sous 24 h` + buttons `Appeler` (`tel:` via `url_launcher`, BSD) / `Message` (v1: `mailto:` or hidden, §5.8); 4 `KpiTile`s `1 248 Vues` `18 Pass Visite` `6 Visites` `1 Offre` (v1 hide Vues); accent banner `1 offre à examiner` → V16; `Activité` timeline (`Offre reçue · 505 000 €` `Aujourd’hui, 11 h 20` · `Visite de Thomas & Léa B.` `Sam. 3 oct. · compte rendu disponible` · `Annonce diffusée` `Realesty et portails partenaires · 26 sept.` · `Mandat signé` `25 sept.`); button `Voir le dernier compte rendu` → V14; tab bar.
- **Data**: `sale_contacts` (agent, staff), `sale_events` (a view over mandate / publication / visits / offers timestamps), counts. Agent assignment: staff in v1.

### V16 · Interface de négociation (`Negociation.dc.html`)
- **Purpose**: answer an offer: accept, refuse or counter.
- **Layout**: header `Retour` · `Négociation`; `AgentBubble` (template: `Cette offre est {pct} % sous votre prix, avec un financement déjà validé. …`; computed figure, no LLM); offer card `TL` `Thomas & Léa B.` / `Offre reçue aujourd’hui · valable 7 jours` / `Pass Visite`; `505 000 €` `−3,8 % vs prix affiché`; rows `Prix affiché` `525 000 €` · `Financement` `Prêt · accord courtier` · `Condition suspensive` `Obtention du prêt` · `Signature souhaitée` `Avant le 15 nov.`; buttons `Refuser` / `Accepter`; section `Faire une contre-proposition`: `Montant proposé` field `515 000 €` + `PriceRangeSlider` (`505 000 €` ↔ `525 000 €`, bounded by offer and asking price), `Message` textarea (placeholder from mockup: `Nous pouvons laisser l’électroménager de la cuisine.`, 500 chars); `Historique` (`Offre de 505 000 €` `Thomas & Léa B. · aujourd’hui` · `Visite + compte rendu` `Sam. 3 oct.`); `Chaque offre est horodatée et archivée dans votre coffre-fort.`; CTA **`Envoyer la contre-proposition`**.
- **Actions**: RPCs `respond_offer(offer_id, 'accepted'|'refused')` and `counter_offer(offer_id, amount, message)` (inserts a `from_party = seller` offer, parent = the buyer's). `Accepter` opens a confirmation sheet (`Accepter l’offre de 505 000 € ? Les autres offres seront refusées.`, new copy), then sale stage → `offer_accepted` and V17. An accepted offer is not a legal commitment; the compromis is. Say so in the sheet: `Votre notaire et l’acquéreur sont prévenus pour préparer le compromis.` (new copy). Expert formula: the mockup shows the same screen; the agent negotiates, so the seller only approves (Q8).
- **Data**: `offers`, `sale_events`. In v1, offers are entered by staff (agent / phone / partner); the buyer side writes them later.

### V17 · Suivi de la vente (`SuiviVente.dc.html`)
- **Purpose**: follow the steps from the accepted offer to the deed.
- **Layout**: header `Retour` · `Ma vente`; badge `Sous compromis`; h1 `Suivi de la vente`; `Maison · 12 rue de la Colombe`; `AgentBubble` (template from the next milestone: `Prochaine étape : {milestone}, avant le {date}. Je vous préviens dès que …`); 2 tiles `Prix de vente` `515 000 €` · `Commission 1 %` `5 150 €`; milestones timeline `Offre acceptée · 515 000 €` `12 oct.` · `Compromis signé` `28 oct. · copie disponible` · `Délai de rétractation` `Terminé le 8 nov.` · `Condition suspensive : prêt` `Échéance le 30 nov.` · `Acte authentique` `Prévu mi-janvier chez le notaire`; doc row `Copie du compromis` `PDF · 32 pages` + `Télécharger`; `Vos interlocuteurs`: notary card (`HG` `Me Hélène Garnier` `Notaire en charge de l’acte`, office, phone, e-mail, `Appeler` `Écrire`) and agent card (`Affiché uniquement en formule L’Expert · 3 %`); section `Préparer le déménagement` (partners) → **hidden v1** (C3 out of scope); tab bar.
- **Data**: `sale_milestones` (staff), `sale_contacts`, `offers` (accepted amount), the compromis as a `property_documents` row of kind `compromis` (staff upload). The retraction end date can be computed: compromis signature + 10 days (SRU), shown as `Terminé le …` once past.

### C1 · Coffre-fort (`CoffreFort.dc.html`) — tab "Coffre-fort" root
- **Layout**: title `Coffre-fort` + `Ajouter un document`; segmented `Espace vendeur` · `Espace acquéreur` (hide the second until the buyer side exists); search `Rechercher un document` (client-side filter); category rows `Propriété 3 documents` · `Fiscalité 2 documents` · `Énergie 4 documents` · `Travaux 3 documents` · `Identité 2 à ajouter` · `Mandats & visites 2 documents` · `Facturation Realesty 5 factures` (→ V18, section opened); `Récents` (3 latest: `Avis de valeur certifié` `Validé le 25/09 par Julien M.` `Vérifié expert`, …, missing ID with `Manquant` + `Scanner`); footer `Chiffrement de bout en bout. Accès limité à vous et à l’expert en charge du dossier.` (the claim must be true: Storage is encrypted at rest, not end-to-end, so use `Documents chiffrés et stockés en Europe. Accès limité à vous et à l’équipe Realesty en charge du dossier.` until real E2E exists; Q14).
- **Category mapping** of `property_documents.kind` (§4.5): Propriété = titre_propriete, plan; Fiscalité = taxe_fonciere; Énergie = diagnostics, dpe, facture_energie, contrat_entretien; Travaux = facture_travaux, rapport_spanc; Identité = piece_identite; Mandats & visites = mandat, compte_rendu, offre, compromis, avis_valeur; Facturation = `invoices`.

### V18 · Coffre-fort · Mes documents (`CoffreDossier.dc.html`)
- **Layout**: header `Retour` · `Coffre-fort · Espace vendeur` · `Mes documents` + `Ajouter un document`; counters `14 documents` `2 à ajouter`; `Touchez une rubrique pour l’ouvrir ou la replier` + `Tout replier`; `AgentBubble` contextual (`Il manque vos pièces d’identité pour finaliser le mandat. Scannez-les en 30 secondes : je vérifie automatiquement leur validité.` In v1, drop "je vérifie automatiquement": staff verify); `CollapsibleSection`s with the status summary (`3 documents · tous vérifiés` `3/3`, `0 document sur 2` `À compléter`, `4 documents · 1 en analyse`); document row: title, subtitle, status badge (`Vérifié expert` / `Analysé` / `Analyse en cours` / `Manquant`), visibility chip (`Notaire`, `Acquéreurs · Notaire`, `Acquéreurs`, `Privé`) with aria `Qui peut voir ce document : …`; missing row → `Scanner` (reuses the V7 scanner flow).
  - Detail sheet (tap a row): preview, `Facture pompe à chaleur` `PDF · 2 pages · ajouté le 12/09/2026` `Analysé par l’IA`; `Informations extraites` rows with `ProvenanceTag.document` (from `property_documents.extracted`, written by OCR later; hidden when empty); `Qui peut voir ce document ?` + `SwitchRow` `Acquéreurs certifiés` / `Dans la Super-fiche, après Pass Visite` and `Notaire` / `Transmis au compromis`; buttons `Télécharger` / `Remplacer`.
  - `Facturation` section `5 factures · formule Premium`: rows (`Frais de dossier Premium` `299 € TTC · payée le 20/09/2026` `Payée` `Privé · non partageable`, …, `Commission Realesty` `1 % du prix de vente, soit ~5 250 €, réglée chez le notaire` `Au succès`), `SEPA •••• 4821` `Moyen de paiement` (hidden v1), `Télécharger toutes les factures (PDF)` (hidden v1).
  - Footer: `Realesty a accès par défaut à vos documents pour certifier votre dossier. Pour chacun, vous choisissez qui d’autre peut le voir. Chiffrement de bout en bout, chaque ouverture est enregistrée.` (same caveat as C1; "chaque ouverture est enregistrée" needs an access log, §4.5).
- **Rules**: adding documents after sending must be allowed (missing ID, diagnostics, mandate PDFs). Today RLS locks rows and files once `status ∉ {draft, submitted}`. Proposal: a new policy lets the owner **add** documents (and delete the ones they added after the lock) at any status; documents present at certification stay locked (`locked_at`). Visibility changes go through an RPC.
- **Data**: `property_documents` (+ new columns), `invoices`, Storage `property-documents` (signed URLs, existing).

### C2 · Mon compte (`EspaceAdmin.dc.html`) — tab "Compte" root
- **Layout**: title `Mon compte`; identity card `SD` `Sophie Durand` `sophie.durand@gmail.com` + badges `Vendeuse` (`Acquéreuse`) + edit (→ V19); `Profil actif` segmented `Vendeur` · `Acquéreur` (v1: switches `profiles.role`, which already drives `appRedirect`; Q15); section `Mon dossier vendeur`: `Propriétaires` `Sophie et Marc Durand` (→ V19) · `Ma formule` `Le Premium · 99 €/mois` `Active` (→ formula details + `Résilier le mandat` for Essentiel, Q5) · `Paiements` `SEPA •••• 4821 · prochain le 1er oct.` (hidden v1) · `Factures Realesty` `5 factures` (→ V18 Facturation); section `Mon projet d’achat` (buyer only, hidden); `Mes partenaires` (hidden v1); `Connexion & sécurité`: `Informations personnelles` `Nom, e-mail, téléphone, adresse` (→ V19) · `Méthodes de connexion` (v1 text `Lien de connexion par e-mail`) · `Connexion par Face ID` / `Double authentification` / `Appareils connectés` (hidden v1, Q16); `Préférences`: `Notifications` `Visites, offres, alertes de prix` (→ simple switches, local + `profiles`), `Agent IA` `Mode vocal par défaut` (EPIC-06; hidden until then), `Langue` `Français` (read-only); `Confidentialité` `Mes données` `Exporter ou supprimer` (v1: `Supprimer mon compte` → Edge Function `delete-account`, Q17); `Se déconnecter` (moved from `SellerHomePage`); dev flavor: `Design system`; tab bar.

### V19 · Mon compte · Informations & sécurité (`MonCompteProfil.dc.html`)
- **Layout**: header `Retour` · `Informations & sécurité` · h1 `Mon compte`; avatar `SD` + `Changer la photo` (hidden v1); `Mes informations`: `Prénom` `Nom` `E-mail` `Téléphone` `Adresse postale` (`RealestyTextField`; e-mail read-only in v1, since changing it means `auth.updateUser` + confirmation e-mail, Q16); `Propriétaires du bien`: `Sophie Durand (vous)` `Identité vérifiée` `Vérifiée`; `Marc Durand` `Invitation envoyée le 22/09` `En attente`; `Inviter un co-propriétaire` (v1 hidden, Q12); `Sécurité`: Face ID, 2FA, `Méthodes de connexion` `Apple · Google · e-mail`, `Mot de passe` `Modifié il y a 3 mois` (**not applicable**: magic link only, so hide); `Pièce d’identité` `Requise pour signer le mandat` `À ajouter` (→ V18 Identité); `Supprimer mon compte` (confirmation sheet). Save button: sticky `Enregistrer` (new; the mockup has none), with the tunnel validation pattern.
- **Data**: `profiles` (+ `last_name`, `phone`, `postal_address`), `auth.users.email`, `property_owners` (+ `identity_verified_at`).

### 3.13 Notifications (bell on V9 / V15)
- Not designed as a screen. Proposal: a bottom sheet listing `notifications` rows (title, body, relative date, unread dot); tap → route; mark as read. Sources: DB triggers on certification, new visit request, new offer, new report, milestone. Push and e-mail are deferred (§5.7).

---

## 4. Data model additions (Postgres, Supabase)

All migrations are additive, `text + check` enums, and use `updated_at` triggers (`seller_tunnel_set_updated_at`). RLS and column grants follow the existing pattern. **Backend-only columns get no grant; state transitions go through `security definer` RPCs that check ownership and the current stage.** Staff writes happen in the Supabase dashboard / SQL editor as `postgres` or `service_role`, which bypass RLS. Each "staff action" has a documented SQL function (`staff_*`) whose execute grant is revoked from `anon` and `authenticated`.

### 4.1 `valuations` (EPIC-07) — the certified valuation (V9, V9b)
```
id uuid pk, property_id uuid fk properties on delete cascade,
value_eur int not null, low_eur int not null, high_eur int not null, price_m2_eur int,
estimated_delay_weeks smallint, delay_curve jsonb        -- [{price_eur, label}]  "Le prix décide du délai"
method_steps jsonb    -- [{label, detail, amount_eur}] "Comment nous arrivons à ce chiffre"
reasons jsonb         -- [{sign:'+'|'-', text}]
adjustments jsonb     -- [{label, amount_eur}] + base {price_m2, area} "Ce qui déplace le prix"
method_weights jsonb  -- {sales:{weight,value}, competition:{weight,value}, ai_check}
comparables_override jsonb -- DVF rows retained / excluded + note (refs EPIC-05 snapshot ids)
competitors jsonb     -- [{label, type, area_m2, price_eur, note, days_online, retained}]
risks_note text, description text, expert_quote text, works_estimate_eur int,
expert_user_id uuid null, expert_display_name text not null, expert_initials text,
certified_at timestamptz not null, valid_until date not null,        -- certified_at + 3 months
report_storage_path text, report_pages smallint, created_at, updated_at
```
- RLS: owner `select` via the property join; **no insert / update grant** for `authenticated`.
- `staff_certify_property(property_id, valuation jsonb)`: inserts the valuation, sets `properties.status = 'certified'`, can upgrade `provenance` keys to `expert`, writes a `notifications` row. `staff_start_review(property_id)` sets `in_review` (which locks the dossier, as today).
- Bucket `valuation-reports` (private, PDF): owner read on `<owner id>/<property id>/…`; no client write.

### 4.2 `property_sales` (EPIC-08) — one sale per property
```
id uuid pk, property_id uuid unique fk, owner_id uuid default auth.uid(),
formula text check in ('essentiel','premium','expert'),
stage text not null default 'plan_chosen' check in ('plan_chosen','activating','ready','published',
      'offer_accepted','under_compromis','sold','withdrawn'),
asking_price_eur int, listing_description text (≤ 2000), description_source text ('template','ai','seller'),
ai_retouch_enabled bool default true, home_staging_enabled bool default false,
visit_duration_min smallint default 45, visit_buffer_min smallint default 15, visit_repeat_weekly bool default true,
formula_chosen_at, activated_at, published_at, sold_at, withdrawn_at timestamptz, created_at, updated_at
```
- RLS: owner select. Owner `update` only on (asking_price_eur, listing_description, description_source, toggles, visit_*), while stage ∉ {sold, withdrawn}. Insert and stage changes only via RPCs: `choose_formula` (property certified; formula changeable while plan_chosen), `activate_sale`, `publish_listing`, `withdraw_sale` (Essentiel "résiliation en un clic").
- Trigger: once `properties.status = certified`, the dossier stays locked (unchanged). `property_sales` is the new editable surface.

### 4.3 Mandate, orders, media (EPIC-08)
- `mandates`: id, sale_id fk, kind (`exclusive_open_ended`, `exclusive_3_months`), terms_version text, presentation_price_eur, fee_rate numeric(4,2), duration_months, document_path (generated PDF), status (`to_sign`,`signed`,`terminated`), signed_at, terminated_at. Owner select. RPC `accept_mandate(sale_id, terms_version)` creates or signs it; `terminate_mandate`.
- `mandate_signatures`: id, mandate_id, owner_id → `property_owners`, signer_user_id = auth.uid(), method (`checkbox`,`drawn`), signature_path (PNG in bucket `mandate-signatures`), signed_at, user_agent. Insert via RPC only (checks that the signer's profile is linked to that owner row).
- `property_owners.identity_verified_at timestamptz` (staff only, no grant).
- `sale_orders`: id, sale_id, kind (`shooting_photo`,`shooting_photo_video`,`diagnostics`,`premium_setup`), diagnostics text[], preferred_slots timestamptz[], status (`requested`,`scheduled`,`done`,`cancelled`), scheduled_at, price_eur_ttc, created_at. Owner insert (status `requested`) and cancel; staff update.
- `listing_photos`: id, sale_id, storage_path, room_id null fk rooms, caption, sort_order, is_cover, width, height, retouched_path null. Owner CRUD while stage ∉ {sold, withdrawn}. Bucket **`listing-media`** (private, JPEG/PNG/HEIC, 15 MB) under `<owner id>/<property id>/…`, write policy based on the sale stage (not the dossier status). Publication to buyers later uses signed URLs or a public derivative bucket.

### 4.4 Visits (EPIC-09)
- `visit_availability`: id, sale_id, weekday smallint 1–7, start_minute smallint, created_at (weekly rule, used when `visit_repeat_weekly`).
- `visit_slot_overrides`: id, sale_id, starts_at timestamptz, state (`open`,`closed`). The effective slots of a week = rules ± overrides − booked.
- `visit_requests`: id, sale_id, buyer_user_id uuid null (null = staff-entered), buyer_label text (`Thomas & Léa B.`), buyer_initials, slot_starts_at, status (`pending`,`accepted`,`refused`,`cancelled`,`done`,`no_show`), compatibility_score smallint null, pass_visite bool, requalified bool, budget_validated bool, search_mandate_signed bool, buyer_snapshot jsonb (subscores, reasons, household, financing, capacity, timeline), source (`buyer_app`,`staff`,`agency`,`demo`), created_at, responded_at. Seller select; RPC `respond_visit_request`. Buyer policies come later (own rows only). **No join from seller policies to buyer tables**: the snapshot is the only shared data.
- `visit_reports`: id, visit_request_id, author_label, agency_label, interest_level (`low`,`medium`,`high`), liked text[], concerns text[], next_steps text[], comment, published_at. Seller select only.

### 4.5 Sale, offers, vault, account, notifications (EPIC-10 / EPIC-11)
- `offers`: id, sale_id, parent_offer_id null, from_party (`buyer`,`seller`), buyer_label, visit_request_id null, amount_eur, financing (`loan`,`cash`,`mixed`), financing_status text, suspensive_conditions text[], desired_signing_before date, valid_until date, message text (≤ 500), status (`received`,`accepted`,`refused`,`countered`,`expired`,`withdrawn`), source, created_at, responded_at. Seller select; RPCs `respond_offer`, `counter_offer` (amount between the buyer offer and the asking price; inserts a seller row and sets the parent to `countered`). An accepted offer refuses the others and moves the sale to `offer_accepted`. Each accepted offer gets archived as a `property_documents` row of kind `offre` (server-generated PDF later).
- `sale_milestones`: id, sale_id, kind (`offer_accepted`,`compromis_signed`,`retraction_end`,`loan_condition`,`deed`), due_date, due_label (`mi-janvier`), done_at, document_id null. Staff-written; seller select.
- `sale_contacts`: id, sale_id, role (`agent`,`notary`), name, organisation, area_label, phone, email, response_time_label. Staff-written.
- `sale_events` **view** (security_invoker) unioning mandate signed, published, visits, reports, offers, for the V15 timeline.
- `property_documents`: extend the `kind` check with `dpe`, `contrat_entretien`, `mandat`, `compte_rendu`, `offre`, `compromis`, `avis_valeur`; add `visibility text[] default '{}'` (`buyers`,`notary`), `verified_at` (staff), `locked_at`, `owner_ref uuid null` (which owner an ID belongs to), `added_after_lock bool`. New policy: owner may insert documents at any status (restrictive `storage_path` rule unchanged) and delete only rows with `added_after_lock`. Storage policies get the same exception (path-segment check + property ownership). RPC `set_document_visibility(doc_id, visibility)`; the ID document and invoices are forced to `{}` (`Privé · non partageable`).
- `document_access_log` (optional, for "chaque ouverture est enregistrée"): document_id, user_id, opened_at. Written by an RPC `open_document(doc_id)` that returns the signed URL.
- `invoices`: id, sale_id, label, amount_eur_ttc numeric, status (`paid`,`pending`,`upcoming`,`on_success`), due_date, paid_at, pdf_path. Staff-written; owner select.
- `profiles`: add `last_name`, `phone`, `postal_address` (grant update); `notification_prefs jsonb` (visites / offres / alertes).
- `notifications`: id, user_id default auth.uid(), kind, title, body, route, read_at, created_at. User selects their own rows and updates `read_at` only (column grant); inserts come from triggers (`security definer`) or staff.

### 4.6 RLS principles (summary)
1. **Owner-only reads** through `properties.owner_id`, joined from every child (`sale_id → property_sales.owner_id` is denormalised for cheap policies).
2. **No direct writes to state columns**: stage, status, verified flags, valuation and expert data have no grant; transitions go through `security definer` RPCs (`set search_path = ''`, ownership + current-state checks, typed errors mapped to l10n messages).
3. **Staff = service role in v1** (dashboard / SQL editor / Edge Functions). Later: `staff_members(user_id, role in ('expert','agent','admin'))` + `public.is_staff()` used in `select` / `update` policies, and a web back-office.
4. **Buyer data stays on the buyer side**: the seller only reads snapshots copied at request / offer time; the buyer side gets its own policies later (own requests and offers; a public `listings` view exposing a published sale's non-private fields).
5. **Co-owners** (later): a `property_members(property_id, user_id, role)` table replaces `owner_id` checks with a membership check (Q12).
6. Probe each new policy with rolled-back `DO` blocks (`supabase db query --linked`), as done for the tunnel.

---

## 5. Dependencies on things that don't exist yet — v1 approach

| # | Dependency | Needed by | v1 approach (proposed) | Later |
|---|---|---|---|---|
| 5.1 | **Expert back-office**: who sets `in_review` / `certified`, writes the V9b report, verifies IDs and documents | V8 states, V9, V9b, V11c identity, V18 badges | **Supabase dashboard + documented SQL functions** (`staff_start_review`, `staff_certify_property(jsonb)`, `staff_verify_identity`, `staff_verify_document`). A runbook `docs/runbooks/certifier-un-dossier.md` with a JSON template of the report, plus a PDF made by the expert with any tool and uploaded to `valuation-reports`. The expert is the owner or a hired expert with dashboard access (Q1). | Web back-office (Flutter web flavor or an admin tool), `staff_members`, expert app (the visit to the property, "Constat de visite"). |
| 5.2 | **Buyers & visit requests** (buyer tunnel A1–A16, Pass Visite, matching score) | V12b, V13, V13b, V14, V16 | Build the tables and screens now. Rows come from **staff entries** (Expert-formula agency visits, phone leads) and an optional **demo seed** (`supabase/seed/demo_buyers.sql`, `source = 'demo'`, applied only on demand to the owner's test property). Empty states otherwise. Matching score / Pass Visite badges hidden when null. | Buyer tunnel writes `visit_requests` with a snapshot; the matching engine fills the score. |
| 5.3 | **Payments** (Premium 299 € + 99 €/mois SEPA, options 200 / 350 / 250 €) and **mandate signature** (1 % / 3 %) | V11, V11b, V11c, V18 Facturation, C2 | **No payment in the app**: options and Premium create `sale_orders` (`requested`), and staff invoice outside the app, entering `invoices` for display. **Mandate**: v1 click-through acceptance + drawn signature stored with timestamp, terms version and server-generated PDF, **marked as pending legal validation** (Q5): do not open to real sellers before that. | Stripe (SEPA Direct Debit + Billing) or GoCardless; qualified e-signature provider (Yousign, French, eIDAS) via Edge Function + webhook; mandate register numbering (loi Hoguet). |
| 5.4 | **Listing publication** (where?) | V11a, V12b diffusion, V15 | `publish_listing` sets stage `published`: the listing exists **in Realesty only** (visible to the future buyer app). `Diffusion` row shows `Realesty`. Portal rows hidden. | Multi-diffusion through a feed aggregator (e.g. Ubiflow / Poliris-format feeds), which requires a professional (carte T / partner agency) account; stats ingestion per portal. |
| 5.5 | **Virtual tour capture** (V11a-2, V11a-3), AI retouch, home staging | V11, V11a | **Deferred**: cards hidden; the retouch / staging toggles are stored as preferences, with a `Bientôt` caption. Photos are plain uploads. | Partner SDK / service (360° capture apps) or own pipeline (video upload → server reconstruction); AI retouch via an image model (budget question). |
| 5.6 | **Agencies / agents** (P1–P11: compte rendu P10, delegation P9, agent V15) | V14, V15, V17 | Staff enter `sale_contacts`, `visit_reports`, `offers` from what the partner agency sends by e-mail or phone. | Espace Agences writes them directly with `staff_members(role='agent')` scoped to delegated sales. |
| 5.7 | **Notifications / e-mail** | V8 (`Me prévenir…`), V9 bell, V13, V16 | **In-app `notifications` table** filled by triggers; badge on the bell and tab bar. No push (free Apple account: no APNs), no transactional e-mail (no SMTP yet). The existing V8 e-mail line stays a promise until 5.7 lands, so reword it to `Vous serez prévenu(e) dans l’application.` (Q11). | Brevo SMTP + `pg_net` / Edge Function e-mails (backlog item already exists); APNs push once on a paid Apple account (FCM/APNs via Edge Function). |
| 5.8 | **Negotiation / messaging between users** | V15 `Message`, V16 | Offers are structured rows (no chat). `Appeler` / `Écrire` open `tel:` / `mailto:` to the staff-entered contact. | In-app messaging (threads table + realtime) once both sides exist. |
| 5.9 | **Market data** (V8b, V9b Secteur) | V8b, V9, V9b | **EPIC-05** (`market_snapshots`). V9b adds the expert's overrides only. | — |
| 5.10 | **AI agent** (`Une question ?`, agent bubbles, AI descriptions) | all | Static template bubbles; button hidden; listing description from a template, or one OpenRouter call through the **EPIC-06** client. | EPIC-06 phase 2. |
| 5.11 | **Co-owner accounts / invitation** | V11c (each owner signs), V19 | Only the main owner uses the app. Co-owner signatures are collected outside the app (staff mark `mandate_signatures` with `method = 'offline'`). | `property_members` + invitation by magic link (Edge Function with `auth.admin.inviteUserByEmail`, needs SMTP). |
| 5.12 | **Points of interest / risks** (V9b `À proximité`, `Sols et risques`) | V9b | Hidden POIs; the risks line is typed by the expert. | OSM / BPE INSEE + Géorisques APIs (Edge Function, cached). |

---

## 6. Epics, user stories and implementation slices

General rules (same as EPIC-04): one branch + PR per epic, each slice coded by one agent and checked by an independent verification agent (tests 100 %, analyze, bloc lint, render at 390×844 vs mockups), `docs/` updated in the same change, migrations applied with `supabase db push --dry-run` then `db push`, RLS probed. A slice is ~1–2 h. "Owns" = files only this slice may edit while the wave runs. Shared files (`app_router.dart`, `app_routes.dart`, ARB files, `lib/ui/ui.dart` barrel, `.github/workflows/main.yaml`) are edited only by the slice marked as their owner, or in a short integration slice.

### EPIC-07 · Espace vendeur : tableau de bord & avis de valeur (V8b nav, V9, V9b, tab bar)
**Objectif** : après l’envoi, le vendeur retrouve son bien dans un espace à onglets, suit la certification et consulte son avis de valeur certifié.

- **US-07.1 · Espace vendeur à onglets** — *En tant que vendeur, je veux un espace avec les onglets Mon bien, Visites, Coffre-fort et Compte, pour retrouver chaque sujet en un geste.*
  - [ ] Barre d’onglets conforme au design system (actif : encre + point vert), visible sur V9, V9b, V12, V12b, V13, V15, V17, V18, C1, C2 ; masquée sur les écrans plein écran.
  - [ ] Chaque onglet conserve sa pile de navigation (retour à l’onglet = même écran).
  - [ ] Dossier brouillon : « Mon bien » propose Commencer / Reprendre l’audit ; dossier envoyé : « Mon bien » = tableau de bord.
  - [ ] « Se déconnecter » est dans l’onglet Compte ; l’ancien écran « Mon dossier vendeur » n’apparaît plus pour un dossier envoyé.
- **US-07.2 · Tableau de bord avant certification** — *En tant que vendeur dont le dossier est en analyse, je veux voir où en est l’expert et ma tendance IA.*
  - [ ] Carte du bien (type, surface, pièces, adresse) + badge « Analyse en cours ».
  - [ ] Tendance IA indicative (EPIC-05) ou message « l’expert s’en charge » ; lien « Voir la synthèse du marché ».
  - [ ] Ligne « Suivi de mon dossier » → V8 ; V8 propose « Aller au tableau de bord ».
  - [ ] Carte « Mon dossier » : score, documents (dont « Action requise »), surfaces & pièces, cadre de vie, ouvrant l’aperçu des données.
- **US-07.3 · Avis de valeur certifié sur le tableau de bord** — *En tant que vendeur, je veux voir ma valeur certifiée dès qu’elle est disponible.*
  - [ ] Carte sombre « Avis de valeur certifié » : valeur, fourchette, tendance IA initiale, expert et date, bouton « Voir le rapport complet ».
  - [ ] « Mettre mon bien en vente » apparaît seulement si le dossier est certifié et sans formule choisie.
  - [ ] Notification in-app « Votre avis de valeur certifié est disponible » (si EPIC-11 K4 livré).
- **US-07.4 · Rapport d’avis de valeur (V9b)** — *En tant que vendeur, je veux comprendre comment l’expert a fixé la valeur de mon bien.*
  - [ ] 4 onglets Synthèse / Le bien / Secteur / Prix, contenus du §3 ; données de l’expert, du dossier (avec provenance) et de l’estimation EPIC-05.
  - [ ] Ventes comparables affichées avec la rue sans numéro.
  - [ ] « Ce qui vous revient » et « Le calcul que fera votre acquéreur » calculés dans l’app (1 % vs 4 %, frais de notaire ≈ 7,5 %).
  - [ ] « Télécharger le rapport (PDF · N pages) » si un PDF existe ; mention légale « validité 3 mois ».
  - [ ] « Mettre en vente à {valeur} » ouvre le choix de la formule.
- **US-07.5 · Synthèse du marché dans le parcours** — *En tant que vendeur, je veux passer de la synthèse du marché à mon suivi ou à mon rapport.*
  - [ ] V8b accessible depuis V8 et V9 ; « Retour au suivi de mon dossier » revient à l’écran d’origine ; « Consulter le rapport complet » seulement une fois certifié.
- **US-07.6 · Certification par l’expert (back-office v1)** — *En tant qu’expert Realesty, je veux passer un dossier en examen puis le certifier avec mon rapport.*
  - [ ] Fonctions SQL `staff_start_review` / `staff_certify_property` (non appelables depuis l’app), runbook en français avec un modèle JSON du rapport.
  - [ ] La certification verrouille le dossier, renseigne `valuations` et passe le statut à `certified`.

| Slice | Content | Owns | Depends on |
|---|---|---|---|
| D1 | Migration `*_valuations.sql` (table, RLS, bucket `valuation-reports`, `staff_*` functions, notification hook stub) + RLS probe + runbook `docs/runbooks/certifier-un-dossier.md` + test dossier certified with sample JSON | `supabase/migrations/*_valuations.sql`, `docs/runbooks/**` | — |
| D2 | `Valuation` model + `getLatestValuation(propertyId)` + `valuationReportUrl` in `property_repository`, package tests | `packages/property_repository/lib/src/models/valuation.dart`, repository methods (after EPIC-05 E7 merged) | D1, EPIC-05 E7 |
| D3 | DS components wave 1: `RealestyTabBar`, `RealestySwitch`/`SwitchRow`, `KpiTile`, `KeyValueRow`, `InitialsAvatar`, `ActionCard`, `HeroValueCard`, promote `Timeline` from V8 + gallery + tests | `lib/ui/components/<new>.dart`, `lib/ui/ui.dart`, `lib/ui/gallery/**`, `lib/seller_tunnel/steps/submitted/widgets/submitted_timeline.dart` (move) | — |
| D4 | Tab shell: `StatefulShellRoute` in the seller `ShellRoute`, `SellerTabScaffold`, placeholder roots for Visites / Coffre-fort / Compte (C2 with logout + dev link), `SellerSpaceGate`, routes constants, V8 CTA `Aller au tableau de bord`, `SellerHomePage` draft-only; update `app_test` walk | `lib/app/router/**`, `lib/seller_space/shell/**`, `lib/seller_tunnel/view/seller_home_page.dart`, `submitted_page.dart` (CTA only), ARB `tabBar*` | D3 |
| D5 | V9 Dashboard: `DashboardCubit` (property, snapshot, valuation, sale stub), 3 hero variants, next-action logic, Mon dossier card, data preview sheet reuse | `lib/seller_space/dashboard/**`, ARB `dashboard*` | D2, D3, D4 |
| D6 | V9b scaffold + header + hero + PDF + tabs Synthèse & Prix (app-side computations) | `lib/seller_space/report/{report_page,cubit,tabs/synthesis_tab,tabs/price_tab}.dart`, ARB `report*` | D2, D3, D4 |
| D7 | V9b tabs Le bien (fiche technique with provenance, surfaces by level) & Secteur (`MiniLineChart`, DVF list from the EPIC-05 snapshot + overrides, competitors, risks) | `lib/seller_space/report/tabs/{property_tab,sector_tab}.dart`, `lib/ui/components/mini_line_chart.dart` | D6, EPIC-05 E7 |
| D8 | V8b wiring: route in the shell, entry from V9, footer buttons by status, pop behaviour; end-to-end test V7 → V8 → V9 → V8b → V9b with a certified fake | router entry for `/vendeur/marche` (if not done by E9), `lib/seller_tunnel/market/**` (footer only, coordinate with E9) | D5, D6, EPIC-05 E9 |

Waves: {D1, D3} → {D2, D4} → {D5, D6} → {D7, D8}.

### EPIC-08 · Formules & mise en vente (V10, V11, V11b, V11c, V11a ; V11a-2/3 différés)
**Objectif** : le vendeur choisit sa formule, accepte son mandat, prépare et publie son annonce.

- **US-08.1 · Choisir ma formule (V10)** — *En tant que vendeur certifié, je veux comparer L’Essentiel, Le Premium et L’Expert et en choisir une.*
  - [ ] Feuille à 3 onglets (Premium par défaut), contenus et prix du design, commission estimée à partir de ma valeur certifiée.
  - [ ] Le choix est enregistré ; je peux changer de formule tant que l’activation n’a pas commencé.
- **US-08.2 · Activer L’Essentiel (V11)** — *En tant que vendeur, je veux activer L’Essentiel en acceptant le mandat exclusif sans engagement.*
  - [ ] Récapitulatif de la formule et du mandat ; case « J’ai lu et j’accepte… » obligatoire avant « Signer le mandat en ligne ».
  - [ ] Acceptation horodatée, version des conditions conservée, mandat PDF déposé dans le coffre-fort (« Mandats & visites »).
  - [ ] Pièce d’identité manquante signalée avec un lien vers le coffre-fort.
  - [ ] Options à la carte demandées (shooting, diagnostics) : demande enregistrée, « Un conseiller vous recontacte ».
- **US-08.3 · Activer Le Premium (V11b)** — *En tant que vendeur, je veux activer Le Premium et réserver shooting et diagnostics.*
  - [ ] v1 sans prélèvement : demande de mise en place enregistrée et message de rappel par un conseiller.
  - [ ] Choix photo / photo + vidéo et d’un créneau préféré ; diagnostics présélectionnés d’après l’audit (règles explicites), modifiables.
  - [ ] Étape mandat présente (comme L’Essentiel) si validé par Q5.
- **US-08.4 · Signer le mandat L’Expert (V11c)** — *En tant que vendeur, je veux signer le mandat de 3 mois et qu’un agent me soit assigné.*
  - [ ] Suivi Identité vérifiée → Mandat de vente → Agent assigné ; lecture du mandat (PDF).
  - [ ] Signature au doigt + case d’acceptation ; signature désactivée tant que l’identité n’est pas vérifiée.
  - [ ] Après signature : écran Ma vente (V15).
- **US-08.5 · Préparer et publier mon annonce (V11a)** — *En tant que vendeur 1 %, je veux relire mes photos, ma description et mon prix, puis publier.*
  - [ ] Photos : ajout (photothèque / appareil), pièce associée, ordre, couverture, suppression.
  - [ ] Description générée à partir de l’audit (aucun chiffre inventé), modifiable.
  - [ ] Prix avec position dans la fourchette certifiée, avertissement hors fourchette, commission mise à jour en direct.
  - [ ] « Publier et ouvrir mes créneaux » refusé tant qu’il manque mandat, photo, description ou prix (erreurs affichées).

| Slice | Content | Owns | Depends on |
|---|---|---|---|
| O1 | Migration `*_property_sales.sql`: `property_sales`, `mandates`, `mandate_signatures`, `sale_orders`, `listing_photos`, `property_owners.identity_verified_at`, buckets `listing-media` + `mandate-signatures`, RPCs (`choose_formula`, `activate_sale`, `accept_mandate`, `sign_mandate`, `publish_listing`, `withdraw_sale`), staff functions; RLS probe | `supabase/migrations/*_property_sales.sql` | D1 (valuations) |
| O2 | New package `packages/sale_repository` (models, RPC calls, media upload), tests, CI job | `packages/sale_repository/**`, `.github/workflows/main.yaml`, `pubspec.yaml` (dependency line), `bootstrap.dart` + `App` (provide repo), `test/helpers/mocks.dart` | O1 |
| O3 | DS wave 2: `OfferPlanCard`, `PriceRangeSlider`, `SignaturePad`, `PropertySummaryCard`, `CollapsibleSection` + gallery | `lib/ui/components/<new>.dart`, `lib/ui/ui.dart`, gallery | D3 |
| O4 | V10 sheet + `SalesPlan` enum + entry from V9 / V9b | `lib/seller_space/offers/choice/**`, ARB `offerChoice*` | O2, O3, D5 |
| O5 | V11 Essentiel activation (mandate acceptance, photo prefs, options) | `lib/seller_space/offers/essentiel/**`, `lib/seller_space/offers/widgets/mandate_card.dart`, ARB `activation*` | O4 |
| O6 | V11b Premium activation (callback request, shooting choice, diagnostics rules) | `lib/seller_space/offers/premium/**`, `lib/seller_space/offers/data/diagnostics_rules.dart` | O4 (reuses O5's `mandate_card`, so run after O5 or with a stub) |
| O7 | V11c Expert (timeline, mandate PDF, signature pad upload, sign RPC) + mandate PDF Edge Function `render-mandate` (template-based) | `lib/seller_space/offers/expert/**`, `supabase/functions/render-mandate/**` | O4 |
| O8 | V11a listing editor: photos manager + description sheet + price + publish | `lib/seller_space/listing/**`, ARB `listing*` | O2, O3 |
| O9 | Listing description: template generator in Dart (v1) or Edge Function `generate-listing-description` using the EPIC-06 OpenRouter client | `lib/seller_space/listing/data/description_template.dart` or `supabase/functions/generate-listing-description/**` | O8, EPIC-06 client |

Waves: {O1, O3} → {O2} → {O4, O8} → {O5, O7, O9} → {O6}.

### EPIC-09 · Visites (V12, V13, V13b, V14, V12b)
**Objectif** : le vendeur ouvre ses créneaux, traite les demandes de visite et lit les comptes rendus.

- **US-09.1 · Mes créneaux de visite (V12)** — *En tant que vendeur 1 %, je veux ouvrir et fermer mes créneaux de visite semaine par semaine.*
  - [ ] Semaine navigable, créneaux horaires Disponible / Réservé / Fermé, légende.
  - [ ] « Répéter chaque semaine » et durée d’une visite (30 / 45 / 60 min + 15 min de battement) enregistrés.
  - [ ] Un créneau réservé ne peut pas être fermé.
- **US-09.2 · Demandes de visite (V13)** — *En tant que vendeur, je veux accepter ou refuser les demandes de visite.*
  - [ ] Onglets En attente / Confirmées / Passées avec compteurs ; carte avec date, compatibilité et badges de qualification.
  - [ ] Accepter / Refuser (confirmation pour Refuser) ; formule L’Expert : lecture seule.
  - [ ] États vides avant publication et sans demande.
- **US-09.3 · Profil light de l’acquéreur (V13b)** — *En tant que vendeur, je veux savoir pourquoi un acquéreur est compatible sans voir ses données privées.*
  - [ ] Score et sous-scores, raisons, foyer, financement, capacité, calendrier ; mention de confidentialité ; blocs absents masqués.
- **US-09.4 · Compte rendu de visite (V14)** — *En tant que vendeur, je veux lire le compte rendu d’une visite menée par un agent.*
  - [ ] Auteur, acquéreur, niveau d’intérêt, points appréciés, freins, prochaine étape ; « Ouvrir la négociation » si une offre existe.
- **US-09.5 · Tableau de bord de vente (V12b)** — *En tant que vendeur 1 %, je veux suivre l’activité de mon annonce.*
  - [ ] Période 7 j / 30 j / depuis la mise en ligne ; demandes, visites réalisées et à venir, offres (vues et favoris masqués tant qu’il n’y a pas d’app acquéreur).
  - [ ] Offre à examiner → négociation ; prochaines visites → V13 ; retours des visiteurs (tags) → comptes rendus.

| Slice | Content | Owns | Depends on |
|---|---|---|---|
| VI1 | Migration `*_visits.sql` (availability, overrides, requests, reports, RPC `respond_visit_request`, staff functions) + demo seed script + RLS probe | `supabase/migrations/*_visits.sql`, `supabase/seed/demo_buyers.sql` | O1 |
| VI2 | `sale_repository`: visits API + models + effective-slot computation (pure Dart, tested) | `packages/sale_repository/lib/src/visits/**` | VI1, O2 |
| VI3 | V12 slots (`WeekStrip`, `SlotGrid` in `lib/ui`), cubit with debounced saves | `lib/seller_space/visits/slots/**`, `lib/ui/components/{week_strip,slot_grid}.dart`, ARB `slots*` | VI2, D4 |
| VI4 | V13 Visites tab root (replaces the D4 placeholder) + empty states | `lib/seller_space/visits/requests/**`, ARB `visitRequests*` | VI2, D4 |
| VI5 | V13b + V14 pages | `lib/seller_space/visits/{buyer_profile,report}/**`, ARB `buyerProfile*`, `visitReport*` | VI4 |
| VI6 | V12b sales board | `lib/seller_space/sale/performance/**`, ARB `salesBoard*` | VI2, N2 (offers API) |

### EPIC-10 · Commercialisation, négociation & suivi de la vente (V15, V16, V17)
**Objectif** : le vendeur suit la commercialisation (L’Expert), répond aux offres et suit la vente jusqu’à l’acte.

- **US-10.1 · Ma vente avec L’Expert (V15)** — *En tant que vendeur 3 %, je veux voir mon agent, l’activité et les offres.*
  - [ ] Carte de l’agent (Appeler / Écrire), compteurs, bandeau d’offre à examiner, fil d’activité daté, dernier compte rendu.
- **US-10.2 · Répondre à une offre (V16)** — *En tant que vendeur, je veux accepter, refuser ou contre-proposer une offre.*
  - [ ] Offre, écart avec le prix affiché, financement, condition suspensive, date de signature souhaitée, validité.
  - [ ] Contre-proposition bornée entre l’offre et le prix affiché, message facultatif (500 caractères) ; historique horodaté.
  - [ ] Acceptation confirmée ; les autres offres sont refusées ; l’offre est archivée dans le coffre-fort.
- **US-10.3 · Suivi de la vente (V17)** — *En tant que vendeur, je veux suivre les étapes jusqu’à l’acte authentique.*
  - [ ] Prix de vente et commission ; étapes offre acceptée, compromis, rétractation (calculée), condition de prêt, acte ; copie du compromis ; interlocuteurs (notaire, agent en L’Expert).

| Slice | Content | Owns | Depends on |
|---|---|---|---|
| N1 | Migration `*_offers_and_sale.sql` (`offers`, `sale_milestones`, `sale_contacts`, view `sale_events`, RPCs `respond_offer` / `counter_offer`, staff functions) + RLS probe | `supabase/migrations/*_offers_and_sale.sql` | O1, VI1 (view joins visits) |
| N2 | `sale_repository`: offers / milestones / contacts / events API | `packages/sale_repository/lib/src/sale/**` | N1, O2 |
| N3 | V15 page (+ `url_launcher` for tel / mailto; BSD-3) | `lib/seller_space/sale/commercialisation/**`, ARB `sale*`, `pubspec.yaml` (url_launcher) | N2 |
| N4 | V16 negotiation | `lib/seller_space/sale/negotiation/**`, ARB `negotiation*` | N2, O3 (`PriceRangeSlider`) |
| N5 | V17 tracking | `lib/seller_space/sale/tracking/**`, ARB `saleTracking*` | N2 |

### EPIC-11 · Coffre-fort & compte (C1, V18, C2, V19, notifications)
**Objectif** : le vendeur retrouve tous ses documents, décide qui peut les voir, gère son compte et ses notifications.

- **US-11.1 · Coffre-fort par rubriques (C1, V18)** — *En tant que vendeur, je veux retrouver mes documents par rubrique et ajouter ceux qui manquent, même après l’envoi.*
  - [ ] Rubriques Propriété, Fiscalité, Énergie, Travaux, Identité, Mandats & visites, Facturation, avec compteurs et statuts ; recherche ; récents.
  - [ ] Ajout d’un document à tout moment (scan / import V7) ; les documents certifiés restent verrouillés.
  - [ ] Détail : aperçu, informations extraites (si présentes), Télécharger / Remplacer (si non verrouillé).
- **US-11.2 · Qui peut voir ce document** — *En tant que vendeur, je veux choisir pour chaque document s’il est visible des acquéreurs certifiés et du notaire.*
  - [ ] Interrupteurs Acquéreurs certifiés / Notaire ; pièce d’identité et factures toujours privées.
- **US-11.3 · Mon compte (C2, V19)** — *En tant que vendeur, je veux gérer mes informations et me déconnecter.*
  - [ ] Prénom, nom, téléphone, adresse postale modifiables (e-mail affiché) ; propriétaires du bien et statut d’identité ; « Pièce d’identité » vers le coffre-fort.
  - [ ] Ma formule, factures ; préférences de notifications ; Se déconnecter ; Supprimer mon compte (confirmation).
- **US-11.4 · Notifications dans l’app** — *En tant que vendeur, je veux être prévenu des étapes importantes dans l’app.*
  - [ ] Cloche avec pastille, liste des notifications (certification, demande de visite, offre, compte rendu, étape de vente), lien vers l’écran concerné, marquées lues.

| Slice | Content | Owns | Depends on |
|---|---|---|---|
| K1 | Migration `*_vault_and_account.sql` (document kinds, visibility, post-lock insert policies incl. Storage, `set_document_visibility`, `open_document`, `invoices`, `profiles` columns, `notifications` + triggers on valuations / visit_requests / offers when those tables exist) + RLS probe | `supabase/migrations/*_vault_and_account.sql` | D1 (+ O1 / VI1 / N1 for triggers; otherwise add the triggers in their own migrations) |
| K2 | `property_repository` + `profile_repository` extensions (documents visibility, invoices, profile fields), `NotificationRepository` (in `sale_repository` or a new `notification_repository` package) | package files listed | K1 |
| K3 | C1 root + V18 accordion, detail sheet, add flow reusing V7 scanner/importer (extract the picker into a shared widget) | `lib/seller_space/vault/**`, `lib/seller_tunnel/steps/documents/widgets/<picker>` (extract only), ARB `vault*` | K2, D4 |
| K4 | C2 root (replaces the D4 placeholder) + V19 form + delete-account Edge Function | `lib/seller_space/account/**`, `supabase/functions/delete-account/**`, ARB `account*` | K2, D4 |
| K5 | Notifications sheet + bell badges (V9, V15) + tab dot | `lib/seller_space/notifications/**` | K2, D5 |

### 6.6 What is realistically achievable before a buyer side exists
- **Fully real**: EPIC-07 (once one person acts as expert through the dashboard), EPIC-11 (vault, visibility, account, in-app notifications), V10 formula choice, V11a listing draft (photos, description, price) and "publication" inside Realesty, and V12 slots.
- **Real but staff-fed**: V11/V11c mandates (click-through, pending legal validation), shooting and diagnostics requests, V15 (agent and activity typed by staff), V14 reports, V16 offers entered by staff (the Expert formula fits well, since an agency brings real offers), and V17 milestones. V13/V13b work with staff-entered or demo requests.
- **Not meaningful without buyers / partners**: views, favourites and portal diffusion stats (V12b, V15), Pass Visite and matching scores, buyer-initiated requests and offers, messaging, payments (provider decision), virtual tour.
- Suggested order: **EPIC-07 → EPIC-11 (K1–K4) → EPIC-08 (O1–O5, O8) → EPIC-09 V12/V13 → EPIC-10**. The buyer tunnel can start in parallel after EPIC-08 O1, because it needs `property_sales` + `listing_photos` to show a published property.

---

## 7. Open questions for the owner

1. **Who certifies, and with which tool?** (a) You, through the Supabase dashboard + SQL runbook (proposed v1); (b) a hired expert given dashboard access (needs a staff role and a confidentiality agreement); (c) a minimal web back-office before the first real seller (≈ 2–3 extra slices); (d) a partner expert network sending reports that staff type in.
2. **V9b report format**: (a) structured in-app (JSON from the expert) + optional PDF (proposed); (b) PDF only + 5 summary fields (value, range, expert, date, quote), with the tabs hidden; (c) in-app only, PDF generated server-side later.
3. **Draft dossier and tab bar**: (a) tab bar from the start, `Mon bien` = Commencer / Reprendre (proposed); (b) no tabs until the dossier is sent (current home kept, logout there); (c) V8 stays the `Mon bien` root until certification, V9 afterwards.
4. **Payments**: (a) none in v1: requests + offline invoices (proposed); (b) Stripe SEPA Direct Debit + Billing for Premium; (c) GoCardless; (d) drop the Premium fees and keep 1 % / 3 % at success only. Also confirm the amounts: 299 €, 99 €/mois, 200 / 350 / 250 € TTC.
5. **Mandate (legal)**: a sale mandate needs a professional holding a carte T (loi Hoguet), a numbered register and a written, signed mandate. (a) The partner agency is the mandatary and Realesty is its tech provider; (b) Realesty obtains its own carte T; (c) a qualified e-signature provider (Yousign) from day one; (d) click-through + drawn signature for internal testing only (proposed for v1, no real sellers). This is not legal advice: have a lawyer validate it before opening to real sellers.
6. **Premium flow order**: (a) V11b → V11a (listing) → V12 (proposed); (b) V11b → V12 as in the mockup, with the listing prepared by the Premium coach; (c) a common "activation" screen for both 1 % formulas.
7. **V10 defaults**: default tab (a) Premium as in the mockup; (b) Essentiel (cheapest); (c) the agent's recommendation. And `Comparer les 3 formules`: (a) comparison table; (b) hidden in v1.
8. **Offers under L’Expert**: (a) the seller sees V16 and decides, the agent advises (proposed); (b) the agent negotiates and the seller only accepts the final offer; (c) the seller chooses per offer.
9. **"IA" claims in v1** (diagnostics pre-selection, photo retouch, home staging, generated description): (a) keep the wording but use deterministic rules / templates; (b) wording "Présélection d’après votre audit" (no AI claim) until a model really runs; (c) hide these features.
10. **Publication requirements**: minimum photos (a) 1; (b) 5; (c) 10 + cover; shooting slots proposed by (a) staff; (b) automatic next 3 weekdays.
11. **Notifications before SMTP / push**: (a) in-app only and reword V8's e-mail promise (proposed); (b) set up Brevo SMTP now (already in the backlog) and send e-mails for certification, requests and offers; (c) wait for a paid Apple account for push.
12. **Co-owners and multiple properties**: (a) main owner only, co-owners sign offline (proposed); (b) invite co-owners with read access + their own signature; (c) full shared access. Multiple properties: (a) one current property (proposed); (b) property switcher on V9.
13. **V12b / V15 views and favourites**: (a) hide until the buyer app exists (proposed); (b) show Realesty-only counts once the buyer app ships; (c) manual figures typed by staff.
14. **"Chiffrement de bout en bout" (C1, V18)**: the current storage is encrypted at rest, not end-to-end. (a) Change the copy (proposed); (b) implement client-side encryption (blocks expert / AI reading and OCR); (c) remove the line.
15. **Seller who is also a buyer (C2 `Profil actif`)**: (a) one role at a time, switch in Compte (proposed); (b) defer the switch until the buyer side exists; (c) combined tab bar.
16. **Account security (V19)**: Face ID, 2FA, password, Apple / Google don't apply to magic-link v1. (a) Hide (proposed); (b) Face ID app lock with `local_auth` (BSD) now; (c) wait for Apple / Google sign-in (paid Apple account). E-mail change: (a) read-only; (b) editable with confirmation.
17. **Account deletion**: (a) Edge Function deleting user + data + files (immediate); (b) request by e-mail handled by staff; (c) soft-delete with 30-day grace. Note: App Store rules require in-app deletion for apps with account creation.
18. **Withdrawing the mandate / formula**: where does `Résilier` live? (a) C2 `Ma formule`; (b) V9 menu; (c) by contacting the team. What happens to the listing and visits then?

---

## 8. Design gaps and inconsistencies to send back to Claude Design
- V9 is only designed in the *certified* state: add the *pending* (submitted / in_review) and *selling* variants, plus the empty draft state.
- V11a (`GestionEssentiel`) shows the badge `Premium · 1 %`; V11b links straight to V12, skipping V11a; Premium has no mandate step.
- V8b sources sentence typo (`sera ajustés`); straight apostrophes in `L'Essentiel` / `L'Expert` badges.
- V9b comparables show house numbers, which conflicts with the "street without number" decision.
- C1 / V18 "chiffrement de bout en bout" and "chaque ouverture est enregistrée" (see Q14).
- V19 security block assumes passwords, Apple / Google, Face ID, 2FA.
- V12b mixes Premium badge with portal stats that need multi-diffusion; V15 is 3 % only, while V16 links back to V15 even for 1 % sellers. Back targets depend on the formula.
- No notifications screen; no confirmation sheets for refusing a visit or accepting an offer; no empty states for V13 / V12b / V15.

## 9. Arbitrages du porteur de projet (2026-10-01)
- Q1 Certification : **mini back-office web** (options b, c, d combinées) — un expert embauché avec un rôle dédié et un accès restreint, et des experts partenaires (connexion directe au back-office ou rapports saisis par l'équipe). Nouvel epic à planifier (EPIC-12 Back-office expert).
- Q2 Rapport V9b : **structuré dans l'app + PDF facultatif**.
- Q3 Barre d'onglets : **dès le début** ; « Mon bien » = Commencer / Reprendre l'audit tant que le dossier est en brouillon ; déconnexion dans « Compte ».
- Q11 Notifications : **dans l'app uniquement** ; reformuler la promesse d'e-mail de V8.
- Questions 4–10 et 12–18 : à trancher avant EPIC-08 à EPIC-11.

## 10. Journal d’exécution — EPIC-07

- **2026-10-01/02 · EPIC-07 (branche `feat/epic-07-dashboard-vendeur`)**
  - D1 ✅ Migration `20261001162633_valuations_and_notifications.sql` poussée (tables `valuations`, `notifications`, bucket `valuation-reports`, fonctions `staff_start_review` / `staff_certify_property` / `staff_attach_valuation_report`) ; RLS vérifiée (bloc `DO` annulé : propriétaire lit son avis et ses notifications, ne peut ni écrire ni appeler les fonctions ; autre utilisateur et `anon` ne voient rien). Runbook `docs/runbooks/certifier-un-dossier.md`. La notification de certification est créée par la fonction (pas de trigger).
  - D2 ✅ (écart au plan) Modèles et accès dans un **nouveau paquet `packages/sale_repository`** (`ValuationRepository`, `NotificationRepository`) plutôt que dans `property_repository`, pour ne pas toucher aux fichiers d’EPIC-05 en parallèle ; EPIC-08 y ajoutera les ventes. Job CI ajouté.
  - D3 ✅ `RealestyTabBar`, `HeroValueCard`, `ActionCard`, `KeyValueRow`, `InitialsAvatar`, icône `download` (+ galerie). Pas encore extraits : `Timeline` de V8, `KpiTile`, `RealestySwitch`.
  - D4 ✅ `StatefulShellRoute` à 4 onglets dans le `ShellRoute` vendeur ; les étapes V1–V8 restent des sous-routes de `/vendeur` posées sur le navigateur vendeur (au-dessus des onglets, avec Mon bien dessous) ; `SellerHomePage` = brouillon seulement ; Compte (C2 v1) avec déconnexion ; Visites / Coffre-fort « Bientôt ». V8 : « Aller au tableau de bord », promesses d’e-mail remplacées par la notification dans l’app. `SellerTunnelCubit.refresh()` (rechargement silencieux, tirer pour actualiser).
  - D5 ✅ V9 (variantes en attente / certifiée), sans `DashboardCubit` : V9 lit le dossier (`SellerTunnelCubit`), `ValuationCubit` et `NotificationsCubit` fournis par la coque. Lien V8b masqué tant que `/vendeur/marche` n’existe pas (détection automatique de la route).
  - D6/D7 🚧 V9b : 4 onglets alimentés par le rapport structuré ; la fiche technique vient de l’expert (`technical_sheet`) plutôt que des colonnes du dossier ; courbe du secteur (`MiniLineChart`) en attente de l’instantané EPIC-05.
  - K5 (anticipé) ✅ Notifications in-app : cloche avec pastille, point sur l’onglet Mon bien, liste en feuille, ouverture de l’écran lié, marquage lu à la fermeture.
  - D8 📋 Branchement V8b (route, pied de page) : avec EPIC-05.
