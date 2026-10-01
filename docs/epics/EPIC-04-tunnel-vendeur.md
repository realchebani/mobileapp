# EPIC-04 · Tunnel vendeur (audit du bien)

**Objectif** : permettre au vendeur de constituer le dossier complet de son bien (propriétaires, localisation, contexte, caractéristiques techniques, surfaces, cadre de vie, documents) puis de l'envoyer à un expert pour validation.
**Statut** : 🚧 En cours · Plan : [2026-09-30-tunnel-vendeur](../plans/2026-09-30-tunnel-vendeur.md)

## US-04.1 · Dossier du bien enregistré ✅
*En tant que vendeur, je veux que mes réponses soient enregistrées au fur et à mesure, pour reprendre plus tard là où je me suis arrêté.*
- [x] Tables Supabase du dossier (bien, propriétaires, parcelles, estimations, pièces, cadre de vie, documents), accès réservé au propriétaire, stockage privé des documents.
- [x] Écran « Mon dossier vendeur » : Commencer / Reprendre l’audit (étape N/7).
- [x] Enregistrement à chaque étape et reprise à la dernière étape atteinte.
- [x] Dossier verrouillé pour le vendeur dès que l’expert le prend en charge ; un seul brouillon par vendeur.

## US-04.2 · Propriétaires (V1) 📋
*En tant que vendeur, je veux déclarer la situation de propriété et les copropriétaires.*

## US-04.3 · Localisation & cadastre (V2) 📋
*En tant que vendeur, je veux retrouver mon adresse et ma parcelle cadastrale sans les saisir entièrement.*

## US-04.4 · Contexte & type de bien (V3) ✅
*En tant que vendeur, je veux décrire le type de bien et son historique (achat, estimations précédentes).*
- [x] Type de bien (maison, appartement, terrain, autre + précision), année et prix d’achat, construit par vous, motif de vente.
- [x] Estimations précédentes (prix, mois, agence) ajoutables / supprimables, enregistrées sans doublon même après un échec réseau.
- [x] Validation avec messages et défilement jusqu’à la première erreur.
- Décisions à valider : « Construit par vous ? » masqué pour un terrain ; champ « Précisez » pour « Autre » ; montants entre 1 000 € et 100 M€.

## US-04.5 · Audit technique à l'écran (V4b) 📋
*En tant que vendeur, je veux décrire les caractéristiques techniques de mon bien sans utiliser la voix.*

## US-04.6 · Surfaces pièce par pièce (V5, V5c) 📋
*En tant que vendeur, je veux saisir mes pièces et leurs surfaces pour obtenir la surface habitable.*

## US-04.7 · Cadre de vie (V6) 📋
*En tant que vendeur, je veux décrire les atouts et points de vigilance du quartier.*

## US-04.8 · Coffre de documents et envoi (V7) 📋
*En tant que vendeur, je veux déposer mes documents et envoyer mon dossier à l'expert.*

## US-04.9 · Attente de validation (V8) 📋
*En tant que vendeur, je veux savoir où en est la validation de mon dossier.*
