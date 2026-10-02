# EPIC-12 · Back-office expert

**Objectif** : un mini back-office web permet à l’équipe, à un expert embauché (rôle dédié, accès restreint) et à des experts partenaires (dossiers attribués) d’examiner les dossiers envoyés — données, photos, documents, traçabilité vocale — et de certifier l’avis de valeur avec un formulaire structuré, sans accès direct à la base.
**Statut** : 📋 À faire (questions ouvertes ; bloquantes : Q1, Q4, Q6, Q7 du plan).

Plan : [Back-office expert](../plans/2026-10-03-back-office-expert.md). Remplace à terme le [runbook « Certifier un dossier »](../runbooks/certifier-un-dossier.md) (conservé comme repli).

Décisions applicables : certification par **mini back-office web** (expert embauché + partenaires, confidentialité) ; rapport **structuré + PDF facultatif** ; certification **par bien** (lots) ; notifications in-app ; traçabilité vocale (fil + fiche de remplissage, EPIC-16) ; photos pour l’expert (EPIC-15).

Légende : ✅ fait · 🚧 partiel · 📋 à faire

## US-12.1 · Se connecter de façon sûre 📋
- 📋 Lien magique puis code TOTP ; sans rôle actif : « Accès refusé » ; désactivation immédiate.
- 📋 Aucune clé secrète dans le site (contrôle CI).

## US-12.2 · Gérer l’équipe (admin) 📋
- 📋 Ajouter un expert ou un partenaire, le désactiver ; attribuer un dossier ; un partenaire ne voit que ses dossiers.

## US-12.3 · Voir la file des dossiers 📋
- 📋 Dossiers envoyés triés par ancienneté, filtres, indicateurs (documents à vérifier, ajouts après l’envoi, photos, voix, brouillon), lots regroupés.
- 📋 « Prendre en charge » passe le dossier en examen et prévient le vendeur.

## US-12.4 · Examiner un dossier 📋
- 📋 Réponses avec provenance, propriétaires (masqués pour un partenaire), lot, photos par pièce (contrôles, analyse IA), documents, instantané DVF.
- 📋 Chaque ouverture de dossier et de fichier est journalisée.

## US-12.5 · Vérifier les documents et l’identité 📋
- 📋 Vérifier / refuser avec motif (notification au vendeur) ; identité vérifiée par propriétaire (débloque la signature Expert d’EPIC-08).

## US-12.6 · Suivre ce qui a été dit 📋
- 📋 Fil vocal par étape (transcriptions, valeurs extraites ou rejetées, tours annulés) ; fiche de remplissage (champ, valeur, phrase d’origine) quand EPIC-16 la fournit.

## US-12.7 · Rédiger l’avis de valeur 📋
- 📋 Formulaire structuré pré-rempli (fiche technique, comparables DVF), enregistrement automatique avec gestion des conflits, erreurs identiques à la base, aperçu vendeur.

## US-12.8 · Certifier et joindre le PDF 📋
- 📋 Un expert certifie (statut, notification, rapport visible sur V9 / V9b) ; un partenaire soumet pour validation ; PDF envoyé par URL signée et lié.

## US-12.9 · Lots 📋
- 📋 Contexte du lot (mode de vente, état de chaque bien, navigation) ; certification bien par bien.

## US-12.10 · Journal d’audit 📋
- 📋 Toute action journalisée, non modifiable ; filtre et export par l’admin.
