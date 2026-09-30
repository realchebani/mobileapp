# Plan — Design system & authentification (Realesty v1)

## Contexte
L'app Flutter est encore le squelette Very Good CLI (écran compteur). Objectif : poser le design system issu du canvas Claude Design « Realesty · App mobile » (DS-Fondations, DS-Composants) et une authentification Supabase par **lien magique** (choix de l'utilisateur : pas de SMTP pour l'instant), pour obtenir sur l'iPhone le parcours Splash → Découvrir → Connexion → e-mail → lien magique → Rôle. Les écrans V1–V3 du tunnel vendeur viendront ensuite sur cette base.

## Phase 0 — Compléter le design (Claude Design)
Le canvas ne couvre pas tout ce dont l'auth a besoin. Ajout dans la rangée « Zone commune & routage » :
- **01b · Connexion par e-mail** : champ e-mail, bouton « Recevoir mon lien », case CGU.
- **01c · Vérifiez vos e-mails** : message « lien envoyé à … », bouton « Ouvrir Mail », « Renvoyer le lien » (avec délai de 60 s), « Changer d'adresse ».
- Dans **DS-Composants**, états manquants : champ (focus, erreur + message), case à cocher non cochée, bouton désactivé / chargement, snackbar d'erreur.
L'utilisateur valide ces artboards avant le code.

## Phase 1 — Design system Flutter (`lib/ui/`)
Barrel `lib/ui/ui.dart`, conventions du dépôt (`material_ui`, constructeurs `const new`).
- **Tokens** : `RealestyColors` (ThemeExtension : Encre #141A17, Encre 2 #39413B, Texte discret #5B635D, Ligne #D3D0C4, Bordure carte #E3E1D8, Ivoire #F6F5EF, Surface #FFFFFF, Surface 2 #EEEDE5, Vert Realesty #6CC43A, Vert texte #2E7D14, Vert teinte #E7F4DE, paires Premium/Expert/Attention/Erreur, palette Nuit réservée voix/caméra), `RealestySpacing` (4…40), `RealestyRadius` (6/12/14/16/18/24/999), ombres niveaux 1 et 2.
- **Typo** : polices **embarquées en assets** (Sora, Hanken Grotesk, Michroma — licence OFL, pas de téléchargement à l'exécution). `TextTheme` : Display 32/38, Titre 1 26/32, Titre 2 18/24, Corps 16/24, Corps S 14/20, Libellé 13/600, Légende 12/700 majuscules.
- **Thème** : `realestyTheme()` → `ThemeData` (scaffold Ivoire, `ColorScheme` mappé, thèmes boutons/champs/checkbox/snackbar) branché dans `lib/app/view/app.dart`.
- **Icônes & logo** : SVG extraits du canvas (trait 1.8, viewBox 24) dans `assets/icons/`, rendus via `flutter_svg` (MIT) par un widget `RealestyIcon`. Widget `RealestyLogo` (variantes clair / sombre, avec ou sans wordmark). Icône de l'app générée depuis le logo (`flutter_launcher_icons`).
- **Composants v1** (ceux utilisés par Splash→Rôle et V1–V3) : `RealestyButton` (primary, accent, secondary, text ; états loading/disabled), `RealestyIconButton`, `RealestyTextField` (+ label, icône, suffixe, erreur), `RealestySelect`, `RealestyCheckbox`, `RealestyBadge`, `ProvenanceTag`, `ChoiceChip`, `SegmentedControl`, `Stepper` (compteur), `SegmentedProgress`, `ListItem`, `InlineBanner`, `AgentBubble` + avatar. Reportés : tab bar, carte bien, mode Nuit/orbe vocal, anneau, timeline, switch.
- **Galerie** : page « Design system » accessible seulement en flavor development, pour contrôler le rendu sur l'iPhone.

## Phase 2 — Authentification (lien magique)
**Supabase (`supabase/config.toml` puis `supabase config push`)**
- Schéma d'URL = bundle ID par flavor : `fr.realesty.mobile.dev://login-callback` (etc.). Ajout de ces URL à `additional_redirect_urls`.
- Migration `supabase/migrations/…_profiles.sql` : table `profiles` (id → auth.users, first_name, role `seller|buyer` nullable, timestamps), RLS « chacun sa ligne », trigger de création à l'inscription. Appliquée par `supabase db push` (**demande le mot de passe de la base**).

**iOS** : `CFBundleURLTypes` dans `ios/Runner/Info.plist` avec `$(PRODUCT_BUNDLE_IDENTIFIER)` → un schéma par flavor sans config en plus. (Android plus tard.)
**Config** : `AUTH_REDIRECT_URL` ajouté à `config/<flavor>.json`.

**Code (architecture VGV)**
- `packages/auth_repository/` (package Dart local) : `AuthRepository` qui encapsule `SupabaseClient.auth` → `sendMagicLink(email)`, `signOut()`, `Stream<User?> user`, `currentUser`. Le reste de l'app ne touche jamais Supabase directement. Un `ProfileRepository` (lecture/écriture du rôle) dans le même esprit.
- `lib/app/bloc/app_bloc.dart` : statut `unknown / unauthenticated / authenticated` à partir du flux utilisateur. `supabase_flutter` gère seul la réception du lien (PKCE) et la persistance de session.
- **Routage** : `go_router` (BSD) avec `redirect` selon `AppBloc` + indicateur « onboarding vu » (`shared_preferences`, déjà tiré par supabase_flutter).
- **Écrans** (`lib/<feature>/{cubit,view}`, pattern Page/View) :
  - `splash` (00) : pendant la restauration de session.
  - `onboarding` (00b Découvrir) : 4 pages, seulement au 1er lancement.
  - `login` (01) : Apple/Google **masqués en v1**, « Continuer avec un e-mail » ; CGU obligatoire ; « Reprendre un dossier » et « Espace Agences » masqués.
  - `login_email` (01b) + `check_inbox` (01c) : `LoginCubit` (validation e-mail, envoi, erreurs réseau / limite d'envoi, renvoi avec délai).
  - `role` (02) : enregistre `role` dans `profiles` ; « Bonjour » sans prénom tant qu'il n'est pas collecté ; « vendre » → écran d'attente de V1.
  - Déconnexion temporaire depuis l'écran d'attente, en attendant « Mon compte ».
- Chaînes en français dans `app_fr.arb` (en/es traduites au passage).
- Suppression de la feature `counter`.

## Limites connues (v1)
- E-mail par défaut de Supabase : modèle en anglais, ~2 envois/heure, uniquement vers les membres de l'organisation Supabase. OK pour tester seul ; il faudra un SMTP avant d'inviter d'autres personnes.
- Le lien doit être ouvert **sur l'iPhone** qui l'a demandé (PKCE).

## Découpage d'exécution (sous-agents)
1. Phase 0 (moi, dans le canvas) → validation de l'utilisateur.
2. En parallèle : **agent A** design system (Phase 1) ; **agent B** Supabase + `auth_repository` + `AppBloc` + routage (sans UI).
3. Puis écrans d'auth (moi), qui assemblent A et B.

## Vérification
- `flutter analyze`, `dart run bloc_tools:bloc lint .`, `very_good test --coverage` : la CI VGV exige 100 % de couverture, donc tests de widgets pour chaque composant, `blocTest` pour `AppBloc`/`LoginCubit`, tests de `AuthRepository` avec client Supabase mocké (mocktail).
- `supabase config push` et `supabase db push` : relire le diff avant de valider.
- Build release + installation sur l'iPhone (commandes dans CLAUDE.md), puis test de bout en bout : e-mail → lien ouvert dans Mail → retour dans l'app connecté → choix du rôle → ligne `profiles` visible dans Supabase → fermer/rouvrir l'app (session conservée) → déconnexion.
- Galerie design system comparée au canvas sur l'iPhone.
