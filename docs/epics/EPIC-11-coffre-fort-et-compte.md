# EPIC-11 · Coffre-fort & compte

**Objectif** : le vendeur retrouve les documents de chaque bien (et de ses lots), en ajoute même après l’envoi, choisit qui pourra les voir, gère son profil, sa langue et ses notifications, et peut supprimer son compte depuis l’app.
**Statut** : ✅ Livré (2026-10-03, branche `feat/epic-11-coffre-fort-compte`) — options recommandées pour les questions non bloquantes, à valider (plan, « Choix par défaut en attendant le porteur de projet »).

Plan : [Coffre-fort & compte](../plans/2026-10-03-coffre-fort-et-compte.md). Spec d’origine : [Parcours vendeur V8b → V19](../plans/2026-10-01-parcours-vendeur-v8b-v19.md) (§3 C1, V18, C2, V19, §6 EPIC-11). Runbooks : [Vérifier / refuser un document](../runbooks/certifier-un-dossier.md) (§4 bis), [Suppression des comptes](../runbooks/suppression-de-compte.md).

Décisions applicables : notifications **dans l’app uniquement** ; **e-mail en lecture seule** ; aucun paiement (facturation masquée) ; suppression du compte dans l’app (exigence App Store) ; plusieurs biens & lots (EPIC-13). Arbitrages du 2026-10-03 : **ajout libre après l’envoi** (« Ajouté après l’envoi »), suppression des seuls ajouts non vérifiés, remplacement des documents refusés ; **suppression du compte = désactivation immédiate puis suppression définitive après 30 jours**, réactivation possible entre-temps.

Légende : ✅ fait · 🚧 partiel · 📋 à faire

## US-11.1 · Coffre-fort par rubriques (C1) ✅
*En tant que vendeur, je veux retrouver les documents de chaque bien par rubrique.*
- ✅ Rubriques (Propriété, Fiscalité, Énergie, Travaux, Identité, Mandats & visites, Autres) avec compteurs et statut, recherche (sans accents), 3 récents ; titre de propriété et pièce d’identité de chaque propriétaire manquants signalés avec « Scanner ».
- ✅ Plusieurs biens : choix du bien ou du lot ; un seul bien : pas de sélecteur. 🚧 Le choix est gardé pour la session (pas encore mémorisé sur l’appareil).
- ✅ Avis de valeur certifié en lecture seule dans « Mandats & visites » (PDF, sinon le rapport V9b). 📋 Mandats d’EPIC-08 à y ajouter après la fusion.

## US-11.2 · Mes documents d’un bien (V18) ✅
- ✅ Sections repliables (« Tout replier / déplier »), statuts (Reçu, Analyse en cours, Analysé, Vérifié expert, À remplacer + motif), visibilité, « Ajouté après l’envoi » ; message de l’agent (pièce d’identité manquante, document à remplacer) ; vue lot avec le bien de chaque document.

## US-11.3 · Ajouter un document à tout moment ✅
- ✅ Scanner (multipage → PDF), importer (fichiers, photothèque) ou reprendre d’un autre bien, comme en V7, même après l’envoi ; type au choix (dont DPE, contrat d’entretien, assurance, copropriété) ; pièce d’identité rattachée à un propriétaire.
- ✅ Les documents d’origine restent verrouillés ; ceux ajoutés après l’envoi se suppriment ou se remplacent tant qu’ils ne sont pas vérifiés ; un document refusé se remplace (l’ancien reste pour l’expert).

## US-11.4 · Détail et téléchargement ✅
- ✅ Ouverture du document (URL signée 5 min), titre modifiable, télécharger (feuille de partage iOS), remplacer / supprimer selon les règles (confirmation intégrée), informations extraites si elles existent. 🚧 Pas de miniature d’image dans la feuille.

## US-11.5 · Qui peut voir ce document ✅
- ✅ Interrupteurs Acquéreurs certifiés / Notaire enregistrés (privé par défaut) ; pièce d’identité toujours privée (contrôle en base) ; mention que rien n’est encore partagé.

## US-11.6 · Mon compte (C2) et mes informations (V19) ✅
- ✅ Prénom, nom, téléphone, adresse postale modifiables (validation, défilement vers l’erreur, délai 15 s, « Quitter sans enregistrer ? ») ; e-mail en lecture seule ; méthode de connexion affichée.
- ✅ Propriétaires du bien et statut de leur pièce d’identité ; lien vers la rubrique Identité ; éléments sans objet en v1 masqués. 📋 « Identité vérifiée » quand EPIC-08 (`identity_verified_at`) sera fusionné ; « Ma formule » (EPIC-08) à ajouter dans C2.

## US-11.7 · Langue ✅
- ✅ Langue de l’appareil, français, anglais ou espagnol ; changement immédiat, mémorisé sur l’appareil et dans le profil (adopté par un autre appareil). Les notifications déjà reçues restent en français.

## US-11.8 · Notifications ✅
- ✅ Liste complète groupée (Aujourd’hui, Cette semaine, Plus ancien), avec le bien concerné, par pages de 50 ; ouverture de l’écran lié ; tout marquer comme lu ; « Tout voir » depuis la cloche (10 dernières).

## US-11.9 · Supprimer mon compte ✅
- ✅ Écran listant ce qui sera supprimé, délai de 30 jours, saisie « SUPPRIMER » (traduite), désactivation immédiate et déconnexion de tous les appareils, date de suppression affichée ; accessible depuis Compte, V19 et l’espace acquéreur provisoire.
- ✅ Reconnexion pendant 30 jours : écran « Votre compte est désactivé » → « Réactiver mon compte ».
- ✅ Purge automatique quotidienne (pg_cron → Edge Function `purge-accounts`) : fichiers de tous les buckets, puis compte ; journal anonyme `account_deletions`.
- ✅ Refus expliqué si une vente est active (EPIC-08, détectée à l’exécution) ; impossible pour un membre de l’équipe (EPIC-12) ; ces blocages sont revérifiés au moment de la purge (compte sauté et signalé à l’équipe).
- ✅ Un compte désactivé ne peut plus modifier ses données jusqu’à sa réactivation.

## US-11.10 · Vérification des documents par l’équipe (avant EPIC-12) ✅
- ✅ `staff_verify_document` / `staff_reject_document` + runbook ; notification « Un document est à remplacer » qui ouvre la bonne rubrique.
