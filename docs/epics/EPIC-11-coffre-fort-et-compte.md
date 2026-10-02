# EPIC-11 · Coffre-fort & compte

**Objectif** : le vendeur retrouve les documents de chaque bien (et de ses lots), en ajoute même après l’envoi, choisit qui pourra les voir, gère son profil, sa langue et ses notifications, et peut supprimer son compte depuis l’app.
**Statut** : 📋 À faire (questions ouvertes ; bloquantes : Q2, Q3, Q8 du plan).

Plan : [Coffre-fort & compte](../plans/2026-10-03-coffre-fort-et-compte.md). Spec d’origine : [Parcours vendeur V8b → V19](../plans/2026-10-01-parcours-vendeur-v8b-v19.md) (§3 C1, V18, C2, V19, §6 EPIC-11).

Décisions applicables : notifications **dans l’app uniquement** ; **e-mail en lecture seule** ; aucun paiement (facturation masquée) ; suppression du compte dans l’app (exigence App Store) ; plusieurs biens & lots (EPIC-13).

Légende : ✅ fait · 🚧 partiel · 📋 à faire

## US-11.1 · Coffre-fort par rubriques (C1) 📋
*En tant que vendeur, je veux retrouver les documents de chaque bien par rubrique.*
- 📋 Rubriques avec compteurs et statut, recherche, récents ; documents requis manquants signalés avec « Scanner ».
- 📋 Plusieurs biens : choix du bien ou du lot ; un seul bien : pas de sélecteur.
- 📋 Avis de valeur (et mandat d’EPIC-08) en lecture seule dans « Mandats & visites ».

## US-11.2 · Mes documents d’un bien (V18) 📋
- 📋 Sections repliables, statuts (Reçu, Analyse en cours, Analysé, Vérifié expert, À remplacer + motif), visibilité, « Ajouté après l’envoi » ; vue lot avec le bien de chaque document.

## US-11.3 · Ajouter un document à tout moment 📋
- 📋 Scanner (multipage → PDF), importer ou reprendre d’un autre bien, comme en V7, même après l’envoi.
- 📋 Les documents d’origine restent verrouillés ; ceux ajoutés après l’envoi se suppriment ou se remplacent tant qu’ils ne sont pas vérifiés.

## US-11.4 · Détail et téléchargement 📋
- 📋 Aperçu, ouverture du PDF, titre modifiable, télécharger, remplacer / supprimer selon les règles.

## US-11.5 · Qui peut voir ce document 📋
- 📋 Interrupteurs Acquéreurs certifiés / Notaire enregistrés ; pièce d’identité toujours privée ; mention que rien n’est encore partagé.

## US-11.6 · Mon compte (C2) et mes informations (V19) 📋
- 📋 Prénom, nom, téléphone, adresse postale modifiables ; e-mail en lecture seule ; méthode de connexion affichée.
- 📋 Propriétaires du bien et statut d’identité ; lien vers la pièce d’identité ; éléments sans objet en v1 masqués.

## US-11.7 · Langue 📋
- 📋 Langue de l’appareil, français, anglais ou espagnol ; changement immédiat et mémorisé.

## US-11.8 · Notifications 📋
- 📋 Liste complète groupée par date, avec le bien concerné ; ouverture de l’écran lié ; tout marquer comme lu ; « Tout voir » depuis la cloche.

## US-11.9 · Supprimer mon compte 📋
- 📋 Écran listant ce qui sera supprimé, saisie « SUPPRIMER », suppression définitive des fichiers puis du compte, déconnexion et confirmation.
- 📋 Refus expliqué si une vente est active ; impossible pour un membre de l’équipe.

## US-11.10 · Vérification des documents par l’équipe (avant EPIC-12) 📋
- 📋 `staff_verify_document` / `staff_reject_document` + runbook ; notification « Un document est à remplacer » qui ouvre la bonne rubrique.
