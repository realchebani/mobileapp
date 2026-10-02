# EPIC-13 · Plusieurs biens & lots de vente

**Objectif** : un vendeur peut créer plusieurs biens (multipropriétaire, maison + terrain voisin, appartement + garage séparé), de tout type, chacun avec son dossier complet, et regrouper des biens en un « lot de vente ».
**Statut** : ✅ Livré (2026-10-02), à valider sur iPhone — voir les écarts en fin de page

Plan : [Plusieurs biens & lots de vente](../plans/2026-10-02-multi-biens.md).

Arbitrages du porteur de projet (2026-10-02) :
- biens liés = **« Lot de vente »** : chaque bien a son dossier (audit, documents) ; les biens d’un lot sont vendus ensemble ou séparément ; l’estimation et la future annonce peuvent porter sur le lot ;
- **« Mes biens » dans l’onglet Mon bien** ; avec un seul bien, accès direct à son dossier comme aujourd’hui ;
- nouveau bien **pré-rempli** depuis un bien existant : propriétaires (V1) et pièce d’identité (V7) ;
- **tous les types de biens**, avec un audit allégé adapté au type.

## US-13.1 · Mes biens ✅
*En tant que vendeur ayant plusieurs biens, je veux les voir ensemble avec leur avancement, pour reprendre celui qui m’intéresse.*
- ✅ Avec un seul bien, l’onglet Mon bien montre directement son dossier (accueil brouillon ou tableau de bord V9), comme aujourd’hui.
- ✅ Avec deux biens ou plus, l’onglet Mon bien montre « Mes biens » : lots puis biens isolés ; pour chaque bien, icône du type, libellé court (type · adresse), statut (`Brouillon · étape k/n`, `Envoyé`, `Analyse en cours`, `Certifié`) et pastille de notification non lue.
- ✅ Toucher un bien ouvre son accueil ; « Retour » revient à « Mes biens ».
- ✅ Tirer pour actualiser recharge la liste, les lots et les notifications.

## US-13.2 · Ajouter un bien ✅
*En tant que vendeur, je veux ajouter un autre bien à tout moment, même si mon premier dossier est envoyé ou certifié.*
- ✅ « Ajouter un bien » dans « Mes biens » et, avec un seul bien, en bas de son accueil.
- ✅ Le type est choisi d’emblée (même grille que V3) ; V3 le montre déjà sélectionné.
- ✅ Plusieurs brouillons sont possibles (l’index « un brouillon par utilisateur » est supprimé) ; un double tap ou une réponse perdue ne crée jamais deux biens (identifiant généré par l’app).
- ✅ Au plus **5 biens au total** par vendeur pendant la phase de test (arbitrage Q11 ; contrôlé en base, message clair dans l’app).

## US-13.3 · Reprendre les propriétaires ✅
*En tant que vendeur, je ne veux pas ressaisir les propriétaires d’un bien que je possède avec les mêmes personnes.*
- ✅ À la création, « Reprendre mes informations de *bien X* » (coché par défaut) copie le type de propriété et les propriétaires de X.
- ✅ Les propriétaires repris restent modifiables en V1 sans changer le bien X ; V1 indique « Repris de *bien X* ».
- ✅ Aucun propriétaire n’est repris d’un autre utilisateur.

## US-13.4 · Réutiliser ma pièce d’identité ✅
*En tant que vendeur, je veux réutiliser la pièce d’identité déjà fournie, sans la scanner à nouveau.*
- ✅ À la création (même case que US-13.3), la pièce d’identité du bien X est ajoutée au nouveau bien sans ré-envoi depuis le téléphone (copie dans le dossier privé du nouveau bien).
- ✅ Le document copié se supprime ou se remplace indépendamment de l’original ; un rejet par l’expert sur un bien n’affecte pas l’autre.
- ✅ Dans V7, « Depuis un autre bien » permet de réutiliser tout document (ex. un titre de propriété commun) — selon Q1.
- ✅ Copie refusée si le bien de destination est verrouillé (RLS Storage existante).

## US-13.5 · Tous les types de biens ✅
*En tant que vendeur, je veux déclarer un garage, une cave ou un terrain aussi simplement qu’une maison.*
- ✅ V3 propose : Maison, Appartement, Terrain, Garage / parking / box, Cave / cellier / dépendance, Autre (+ Local commercial et Immeuble entier selon Q6).
- ✅ Précision demandée selon le type (terrain constructible ou non, type de stationnement, nature de la dépendance…).
- ✅ Les types sont acceptés par la base, l’app et l’agent vocal.

## US-13.6 · Audit adapté au type ✅
*En tant que vendeur d’un garage, je ne veux répondre qu’aux questions qui le concernent.*
- ✅ Les étapes, sections de V4b, champs requis, documents listés et réponses du score de transparence suivent le tableau du plan (§7), via un seul modèle `PropertyTypeProfile`.
- ✅ Les étapes sans objet sont sautées (ex. garage : V1 → V2 → V3 → V4b allégé → V7) et le compteur « k/n » de l’en-tête en tient compte.
- ✅ Titre de propriété et pièce d’identité restent les seuls documents bloquants pour tous les types.
- ✅ Changer de type en brouillon masque les réponses hors sujet sans les effacer — selon Q9.

## US-13.7 · Lot de vente ✅
*En tant que vendeur d’une maison et du terrain voisin, je veux les regrouper pour les vendre ensemble.*
- ✅ Créer un lot à l’ajout d’un bien (« Vendu avec un autre bien ? ») ou depuis « Mes biens » ; nommer le lot ; choisir le bien principal et le mode de vente (ensemble / ensemble ou séparément — selon Q3).
- ✅ Un bien appartient à au plus un lot ; un lot ne contient que des biens du même vendeur (contrôlé en base).
- ✅ Le lot est figé dès qu’un de ses biens est pris en charge par l’expert (`in_review`) ou certifié.
- ✅ Chaque bien du lot garde son dossier, son envoi et sa certification.

## US-13.8 · Estimation par bien et par lot ✅
*En tant que vendeur d’un lot, je veux une idée de la valeur de l’ensemble.*
- ✅ Estimation par bien : maison, appartement, et aussi **garage / dépendance** (médiane des ventes DVF de dépendances seules, prix à l’unité — arbitrage Q5) ; les autres types affichent « l’expert vous donnera directement son avis de valeur ».
- ✅ Fiche du lot : fourchette = somme des estimations des biens quand chaque bien estimable l’est ; sinon, estimations bien par bien et « estimé par l’expert » pour les autres — selon Q4.
- ✅ Une dépendance sur la même parcelle que le bien principal n’est pas additionnée (« comprise dans l’estimation »).
- ✅ Le lot ne déclenche aucun calcul serveur supplémentaire.

## US-13.9 · Notifications et liens par bien ✅
*En tant que vendeur, je veux qu’une notification m’ouvre le bon bien.*
- ✅ Routes par bien : `/vendeur/biens/<id>`, `…/audit/<étape>`, `…/rapport`, `…/marche` ; fiche de lot `/vendeur/lots/<id>`.
- ✅ Les notifications (nouvelles et existantes) ouvrent `/vendeur/biens/<id>/rapport` ; la feuille de notifications indique le bien concerné.
- ✅ Les anciennes routes (`/vendeur/rapport`, `/vendeur/audit/…`) redirigent vers le bien ouvert ou le seul bien.
- ✅ Le verrouillage (dossier envoyé → V8) s’applique bien par bien.

## US-13.10 · Supprimer un brouillon ✅
*En tant que vendeur, je veux supprimer un bien créé par erreur.*
- ✅ « Supprimer » sur un brouillon dans « Mes biens », avec confirmation intégrée à l’écran.
- ✅ Les fichiers du bien sont supprimés du stockage, puis le bien et ses données.
- ✅ Un bien envoyé ou certifié ne peut pas être supprimé (RLS existante) ; le lot sans membre est supprimé.

## US-13.11 · Voix selon le type ✅
*En tant que vendeur, je veux que l’agent vocal ne me propose que ce qui a du sens pour mon bien.*
- ✅ Micro proposé en V4 / V6 seulement pour maison, appartement, autre (les autres types : audit à l’écran).
- ✅ Les Edge Functions de l’agent connaissent les nouveaux types et refusent les types non vocaux ; champs requis alignés sur l’app (test de parité).

## Écarts et points à valider

- Fiche du lot, « Mes biens », « Ajouter un bien » et la grille V3 à 8 types ne sont pas dans le canevas Claude Design : construits avec le design system, à ajouter au canevas.
- Le texte « l’expert vous donnera directement son avis de valeur » n’est pas encore décliné par type (même message pour terrain, local, immeuble, autre).
- Réutiliser un document « Depuis un autre bien » ne propose que les documents du même type (titre de propriété ↔ titre de propriété).
- Les pièces (V5c) et le cadre de vie d’un ancien type ne sont pas effacés à l’envoi : seules les colonnes du bien le sont (Q9).
