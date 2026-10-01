# EPIC-04 · Tunnel vendeur (audit du bien)

**Objectif** : permettre au vendeur de constituer le dossier complet de son bien (propriétaires, localisation, contexte, caractéristiques techniques, surfaces, cadre de vie, documents) puis de l'envoyer à un expert pour validation.
**Statut** : ✅ Terminé (v1 à l’écran ; voix + agent IA, carte Mapbox et données de marché V8b à suivre) · Plan : [2026-09-30-tunnel-vendeur](../plans/2026-09-30-tunnel-vendeur.md)

## US-04.1 · Dossier du bien enregistré ✅
*En tant que vendeur, je veux que mes réponses soient enregistrées au fur et à mesure, pour reprendre plus tard là où je me suis arrêté.*
- [x] Tables Supabase du dossier (bien, propriétaires, parcelles, estimations, pièces, cadre de vie, documents), accès réservé au propriétaire, stockage privé des documents.
- [x] Écran « Mon dossier vendeur » : Commencer / Reprendre l’audit (étape N/7).
- [x] Enregistrement à chaque étape et reprise à la dernière étape atteinte.
- [x] Dossier verrouillé pour le vendeur dès que l’expert le prend en charge ; un seul brouillon par vendeur.

## US-04.2 · Propriétaires (V1) ✅
*En tant que vendeur, je veux déclarer la situation de propriété et les copropriétaires.*
- [x] Unique propriétaire / Plusieurs propriétaires.
- [x] Propriétaire principal prérempli (prénom du profil, e-mail du compte) ; téléphone français normalisé.
- [x] Copropriétaires : ajout, modification et suppression dans une fiche dédiée.
- [x] Validation à l’appui sur « Continuer », enregistrement robuste (pas de doublon ni de perte de saisie pendant l’enregistrement).

## US-04.3 · Localisation & cadastre (V2) ✅
*En tant que vendeur, je veux retrouver mon adresse et ma parcelle cadastrale sans les saisir entièrement.*
- [x] Adresse avec suggestions (géocodage Géoplateforme) ou « Me géolocaliser ».
- [x] Parcelle cadastrale trouvée automatiquement (API Carto IGN), affichée sur la photo aérienne IGN ; ajout / retrait de parcelles en touchant la carte ; confirmation.
- [x] Situations particulières (aucune, indivision, etc.).
- [x] Fonctionne hors ligne en mode dégradé (adresse saisie, parcelle non confirmée).
- Décision validée : V1–V3 (terrain, « Autre », bornes des montants, suppression dans la fiche).

## US-04.4 · Contexte & type de bien (V3) ✅
*En tant que vendeur, je veux décrire le type de bien et son historique (achat, estimations précédentes).*
- [x] Type de bien (maison, appartement, terrain, autre + précision), année et prix d’achat, construit par vous, motif de vente.
- [x] Estimations précédentes (prix, mois, agence) ajoutables / supprimables, enregistrées sans doublon même après un échec réseau.
- [x] Validation avec messages et défilement jusqu’à la première erreur.
- Décisions à valider : « Construit par vous ? » masqué pour un terrain ; champ « Précisez » pour « Autre » ; montants entre 1 000 € et 100 M€.

## US-04.5 · Audit technique à l'écran (V4b) ✅
*En tant que vendeur, je veux décrire les caractéristiques techniques de mon bien sans utiliser la voix.*
- [x] Carte d’identité, gros œuvre, chauffage & assainissement, extérieur & équipements ; champs PAC / piscine conditionnels.
- [x] Adapté au type : appartement sans niveaux/mitoyenneté/toiture ; terrain limité à l’assainissement et l’extérieur.
- [x] Étiquettes de provenance (Déclaré, Extrait d’un document, Source externe).
- Validé : adaptation appartement / terrain. À valider : listes proposées (exposition, toiture, type de PAC, type de piscine).

## US-04.6 · Surfaces pièce par pièce (V5, V5c) ✅
*En tant que vendeur, je veux saisir mes pièces et leurs surfaces pour obtenir la surface habitable.*
- [x] V5 : saisie manuelle (scan caméra et import de plan « Bientôt »).
- [x] V5c : pièces par niveau, fiche d’ajout / modification (nom, surface, niveau, revêtement, vitrage, pièce principale), total « Surface totale déclarée » en direct.
- [x] Surface habitable et annexes distinguées (garage, cellier, sous-sol, buanderie en annexe par défaut ; une annexe ne peut pas être pièce principale).

## US-04.7 · Cadre de vie (V6) ✅
*En tant que vendeur, je veux décrire les atouts et points de vigilance du quartier.*
- [x] Atouts et points de vigilance (10 max chacun), ajout / modification / suppression dans une fiche (saisie écrite à la place de la voix).
- [x] Niveau de bruit 1–10 (curseur), vis-à-vis, note libre.
- [x] Carte « Données du quartier » en attente de sources externes.
- Validé : libellés du bruit ; la note est destinée aux futurs visiteurs.

## US-04.8 · Coffre de documents et envoi (V7) ✅
*En tant que vendeur, je veux déposer mes documents et envoyer mon dossier à l'expert.*
- [x] Liste des pièces avec statut (manquant, facultatif, non concerné, reçu…), SPANC selon l’assainissement.
- [x] Ajout par photo (caméra) ou import (fichiers / photothèque), 20 Mo max, stockage privé ; ouverture par lien temporaire ; suppression.
- [x] Score de transparence (v1 calculé dans l’app : 70 % documents, 30 % réponses).
- [x] « Envoyer mon dossier à l’expert » (statut envoyé) ; dossier et fichiers verrouillés dès que l’expert le prend en charge.
- [x] Envoi bloqué sans titre de propriété ni pièce d’identité ; les autres pièces peuvent suivre (validé).
- [x] Dossier verrouillé dans l’app dès l’envoi : les étapes redirigent vers V8.

## US-04.9 · Attente de validation (V8) ✅
*En tant que vendeur, je veux savoir où en est la validation de mon dossier.*
- [x] Suivi en 3 étapes selon le statut (envoyé, en examen, certifié), date d’envoi en heure locale.
- [x] Carte « Tendance IA » si une estimation existe (masquée une fois certifié).
- [x] Aperçu en lecture seule de toutes les réponses ; retour au dossier.
- [x] Préférence de notification (enregistrée dans le dossier tant qu’il n’est pas en examen).
- Masqués en v1 : « Voir la synthèse du marché » (V8b) et « Une question ? ».
