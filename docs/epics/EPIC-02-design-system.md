# EPIC-02 · Design system

**Objectif** : reproduire fidèlement dans Flutter le design system du canvas Claude Design (DS-Fondations, DS-Composants) pour construire tous les écrans.
**Statut** : 🚧 En cours

## US-02.1 · Compléter les états manquants du design ✅
*En tant que designer/développeur, je veux que les états interactifs soient définis avant d'être codés.*
- [x] Section « États (v1) » ajoutée à DS-Composants : champ (focus, erreur, désactivé), case à cocher, bouton (appuyé, désactivé, chargement), snackbar.

## US-02.2 · Fondations (tokens, typographie, thème) 🚧
*En tant que développeur, je veux des tokens et un thème Flutter fidèles au design.*
- [x] Couleurs (`RealestyColors`, dont palette Nuit et paires d'offres/états), espacements, rayons, ombres, animations.
- [x] Polices embarquées Sora, Hanken Grotesk, Michroma (licences OFL enregistrées).
- [x] `realestyTheme()` : ColorScheme, TextTheme, thèmes des composants Material.
- [ ] Vérification de fidélité validée.

## US-02.3 · Icônes et logo 🚧
- [x] 47 icônes SVG au trait (viewBox 24, trait 1.8) via `RealestyIcon`.
- [x] `RealestyLogo` (clair/sombre, avec ou sans wordmark) et visuel d'icône d'app 1024 px.
- [ ] Icône de l'app configurée sur iOS.

## US-02.4 · Composants 🚧
- [x] Boutons, bouton icône, bouton micro, champ texte, sélecteur, case à cocher, badges, tags de provenance, puces de choix, contrôle segmenté, compteur, progression segmentée, élément de liste, bandeau, bulles de l'agent, snackbar.
- [x] Tests à 100 % de couverture.
- [ ] Vérification de fidélité validée.
- 📋 Plus tard : barre d'onglets, carte de bien, mode Nuit vocal, anneau de progression, timeline.

## US-02.5 · Galerie du design system 🚧
*En tant que designer, je veux voir tous les composants sur l'iPhone pour les comparer au canvas.*
- [x] Page `DesignSystemGalleryPage`.
- [ ] Accessible depuis le flavor development uniquement.
