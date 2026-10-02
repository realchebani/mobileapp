# EPIC-15 · Photos du bien

**Objectif** : permettre au vendeur de photographier chaque pièce de son bien depuis V5c, avec des contrôles de qualité sur le téléphone et des suggestions d’une IA de vision qu’il accepte ou non, et de pré-remplir ses pièces en photographiant un plan ; les photos servent à l’expert (constat, défauts compris) puis à l’annonce.
**Statut** : 🚧 Livré dans l’app et le backend (fonctions déployées) ; reste l’essai sur l’iPhone avec de vraies pièces (calibrage des seuils de qualité, banc d’essai du modèle de vision sur 30 photos réelles).

Plan : [Photos du bien](../plans/2026-10-02-photos-du-bien.md). Étude : [Capture visuelle du bien](../plans/2026-10-02-capture-visuelle-etude.md).

Légende : ✅ fait · 🚧 partiel · 📋 à faire

## US-15.1 · Photographier chaque pièce depuis V5c ✅
*En tant que vendeur, je veux ajouter des photos à chaque pièce du récapitulatif, pour que l’expert voie mon bien.*
- ✅ Chaque ligne du tableau V5c a un bouton photo avec le nombre de photos ; la fiche d’une pièce propose « Photos de la pièce ».
- ✅ L’écran « Photos de la pièce » permet de photographier (appareil photo) ou de choisir plusieurs photos dans la photothèque, de les voir, de mettre une photo en premier et d’en supprimer ; un envoi raté peut être relancé ou retiré.
- ✅ Une pièce encore jamais enregistrée l’est avant la première photo (sans doublon).
- ✅ 12 photos au plus par pièce, 150 par bien ; les photos sont réduites à 2 048 px (JPEG) avant l’envoi.
- ✅ Les photos d’une pièce supprimée sont supprimées avec elle (avertissement dans la fiche).
- ✅ Changer l’ordre des photos est enregistré en une fois (jamais d’ordre à moitié enregistré).

## US-15.2 · Contrôles de qualité sur le téléphone 🚧
*En tant que vendeur, je veux savoir tout de suite si une photo est ratée.*
- ✅ L’écran de prise de vue affiche une grille, un niveau et la consigne « Personne dans le champ » ; il conseille d’allumer et d’ouvrir les rideaux et de montrer aussi les défauts.
- 🚧 Après chaque photo, l’app vérifie la lumière, la netteté et l’inclinaison ; en cas de défaut, elle propose « Reprendre » ou « Garder ». Seuils v1 à calibrer sur l’iPhone avec de vraies pièces.
- ✅ Les défauts sont aussi signalés sur les miniatures (photothèque comprise).

## US-15.3 · Suggestions de l’IA avec consentement ✅
*En tant que vendeur, je veux que l’app me propose le type de pièce, le revêtement et le vitrage à partir de mes photos, sans rien imposer.*
- ✅ Je peux retirer mon accord à tout moment (« Désactiver les suggestions de l’IA », Compte) ; le serveur refuse toute analyse sans accord.
- ✅ La position GPS et l’appareil (EXIF) ne quittent jamais le téléphone — y compris pour les images importées comme documents en V7 (JPEG, PNG, HEIC, sans perte de qualité ; un PDF n’est jamais modifié).
- ✅ Une analyse n’est jamais enregistrée sur un dossier envoyé entre-temps, et deux demandes simultanées pour la même photo ne coûtent qu’une analyse.
- ✅ À la première photo, un écran explique l’analyse (fournisseur via OpenRouter, sans conservation ni entraînement, jamais de mesure) ; je peux accepter ou refuser, et changer d’avis plus tard.
- ✅ Avec mon accord, chaque photo est analysée une fois : type de pièce, revêtement, vitrage, constats (sans chiffre), objets personnels à ranger, personne visible.
- ✅ Les suggestions s’appliquent seulement si je tape « Appliquer » / « Ajouter à la description » ; elles reviennent dans la fiche de la pièce et sont enregistrées avec « Continuer » comme mes réponses.
- ✅ Une photo où une personne est visible est signalée « à reprendre ou supprimer » (pas de floutage automatique en v1).
- ✅ Quotas : 200 analyses de photos et 10 lectures de plan par jour ; le modèle se change par secret.

## US-15.4 · Lire un plan en V5 ✅
*En tant que vendeur, je veux photographier mon plan pour ne pas saisir chaque pièce.*
- ✅ V5 propose « Lire un plan » (scanner ou photothèque) ; la carte « Scanner avec la caméra » a disparu.
- ✅ L’IA ne relève que les pièces et surfaces imprimées sur le plan ; une surface absente reste vide.
- ✅ Je vérifie chaque ligne (garder ou non, corriger le nom, le niveau, la surface) ; un écart entre la somme et le total imprimé est signalé.
- ✅ Si j’ai déjà des pièces, je choisis de les compléter ou de les remplacer ; une lecture ratée se relance sans renvoyer le plan.
- ✅ Les pièces gardées telles qu’imprimées arrivent dans V5c avec l’étiquette « Plan » / « Extrait d’un document » (`source = plan`), celles que j’ai corrigées sont « Déclaré » ; le plan est aussi rangé dans les documents (V7).
- ✅ Sans consentement à l’IA, le plan est seulement déposé pour l’expert.

## US-15.5 · Une photo par pièce principale pour envoyer le dossier ✅
*En tant que Realesty, je veux que l’expert ait au moins une photo de chaque pièce principale.*
- ✅ V5c indique les pièces principales sans photo et le nombre de pièces principales photographiées.
- ✅ En V7, « Envoyer » est bloqué tant qu’une pièce principale n’a pas de photo (types avec pièces seulement) ; le message liste les pièces et propose d’y retourner.
- ✅ Une fois le dossier envoyé, la base refuse la suppression de la dernière photo d’une pièce principale ; l’app l’explique (« Cette pièce principale doit garder au moins une photo… »).
- ✅ Le score de transparence compte les photos des pièces principales.
- ✅ L’aperçu des données (V8) affiche le nombre de photos par pièce.

## US-15.6 · L’expert retrouve les photos ✅
*En tant qu’expert, je veux les photos classées par pièce avec ce que l’IA y a vu.*
- ✅ Les photos sont dans `room_photos` (par pièce, ordre, contrôles, analyse IA) et le bucket privé du dossier ; le runbook explique comment les consulter.
- ✅ L’équipe peut lister les fichiers orphelins du stockage (`staff_orphan_files`) et les supprimer à la main (runbook §5).
- ✅ Le composant de photos est réutilisable à la mise en vente (V11a, EPIC-08) : point d’accroche décrit dans le plan §4.6 (à brancher avec EPIC-08).
