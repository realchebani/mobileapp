# EPIC-12 · Back-office expert

**Objectif** : un mini back-office web permet à l’équipe, à un expert embauché (rôle dédié, accès restreint) et à des experts partenaires (dossiers attribués) d’examiner les dossiers envoyés — données, photos, documents, traçabilité vocale — et de certifier l’avis de valeur avec un formulaire structuré, sans accès direct à la base.
**Statut** : 🚧 Codé (B0–B8, B10, B11) avec les choix par défaut du plan (§12 bis) ; **pas encore hébergé** (domaine, DNS et compte d’hébergement à fournir) ; aperçu vendeur (B9) à faire.

Plan : [Back-office expert](../plans/2026-10-03-back-office-expert.md). Runbook : [back-office.md](../runbooks/back-office.md). Le [runbook « Certifier un dossier »](../runbooks/certifier-un-dossier.md) reste le repli SQL.

Décisions applicables : Flutter web dans le dépôt (`backoffice/`) ; rôles dans la table `staff_members` lue par des fonctions `security definer`, **TOTP obligatoire** ; experts partenaires limités aux **dossiers attribués** (initiales + commune, jamais de pièce d’identité) ; un partenaire **soumet**, un expert interne ou l’admin **certifie** ; rapport structuré + PDF facultatif ; certification par bien ; notifications in-app.

Légende : ✅ fait · 🚧 partiel · 📋 à faire

## US-12.1 · Se connecter de façon sûre 🚧
- ✅ Lien magique puis code TOTP (enrôlement par QR code au premier accès) ; sans rôle actif : « Accès refusé » ; désactivation immédiate (vérifiée à chaque appel).
- ✅ Aucune clé secrète dans le site (contrôle CI sur `build/web`) ; CSP stricte prête (`web/_headers`).
- 📋 Hébergement sur un domaine (Cloudflare Pages recommandé) et URL de redirection de production ; SMTP avant d’inviter un partenaire externe.

## US-12.2 · Gérer l’équipe (admin) ✅
- ✅ Ajouter un expert ou un partenaire (organisation) à partir d’un compte existant, le modifier, retirer son accès (ses dossiers reviennent dans la file) ; un admin ne peut ni se retirer ni se rétrograder.
- ✅ Attribuer / retirer un dossier ; un partenaire ne voit que ses dossiers.

## US-12.3 · Voir la file des dossiers ✅
- ✅ Dossiers envoyés du plus ancien au plus récent, alerte au-delà de 48 h, filtres (statut, mes dossiers, non attribués, recherche), indicateurs (documents à vérifier, ajouts après l’envoi, photos, voix, brouillon / à valider, compte vendeur désactivé), lots regroupés.
- ✅ « Prendre en charge » passe le dossier en examen et prévient le vendeur (l’admin ou l’expert s’attribue un dossier libre).

## US-12.4 · Examiner un dossier ✅
- ✅ Réponses avec provenance (fiche de remplissage, « À vérifier », « Non confirmé »), propriétaires (masqués pour un partenaire), lot et ses biens, parcelles (lien Géoportail), pièces, photos par pièce (contrôles, analyse IA « suggestion »), documents, instantané DVF.
- ✅ Chaque ouverture de dossier et de fichier est journalisée ; fichiers par URL signée de 5 minutes.

## US-12.5 · Vérifier les documents et l’identité ✅
- ✅ Vérifier / refuser avec motif (modèles de motifs ; le vendeur reçoit « Un document est à remplacer ») ; « Identité vérifiée » par propriétaire (admin, expert).

## US-12.6 · Suivre ce qui a été dit ✅
- ✅ Fiche de remplissage avec phrase d’origine et fil vocal par étape (valeurs retenues, écartées, pour une autre étape, tours annulés barrés).

## US-12.7 · Rédiger l’avis de valeur 🚧
- ✅ Formulaire structuré (sections de V9b), enregistrement automatique avec verrou optimiste et bandeau de conflit, erreurs identiques à la base (validateur partagé + fixture de parité), pré-remplissage de la fiche technique et import des ventes DVF, contrôle des totaux d’ajustements.
- 📋 Aperçu vendeur (onglets V9b) : tranche B9.

## US-12.8 · Certifier et joindre le PDF ✅
- ✅ Un expert ou l’admin certifie après récapitulatif (statut, notification, rapport visible sur V9 / V9b) ; un partenaire soumet pour validation, l’expert peut renvoyer avec un commentaire ; PDF envoyé par URL signée et lié (nombre de pages).

## US-12.9 · Lots ✅
- ✅ Contexte du lot (mode de vente, état de chaque bien, navigation vers les biens accessibles) ; certification bien par bien.

## US-12.10 · Journal d’audit ✅
- ✅ Toute action journalisée (y compris les fonctions `staff_*` du SQL Editor), non modifiable ; l’admin filtre (personne, action, dossier, période) et exporte en CSV ; les autres membres voient leurs propres actions.
