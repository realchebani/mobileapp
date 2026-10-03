# EPIC-09 · Visites

**Objectif** : une fois l’annonce en ligne, le vendeur ouvre ses créneaux de visite, traite les demandes (accepter, refuser, annuler), découvre le profil « light » de chaque acquéreur et lit les comptes rendus de visite.
**Statut** : 📋 À faire (plan rédigé, aucun code)

Plan : [Visites](../plans/2026-10-03-visites.md). Spec d’origine : [Parcours vendeur V8b → V19](../plans/2026-10-01-parcours-vendeur-v8b-v19.md) (§3 V12, V13, V13b, V14, §4.4, §6 EPIC-09). Plan frère : [Vente & négociation](../plans/2026-10-03-vente-et-negociation.md) (EPIC-10, qui reprend V12b). Runbook équipe à créer : `docs/runbooks/organiser-les-visites.md`.

Décisions applicables : **pas d’app acquéreur en v1** (demandes, décisions de l’agent et comptes rendus saisis par l’équipe via des fonctions `staff_*`, démo marquée `demo`, tout en `is_test`) ; notifications in-app seulement (pas de SMS / e-mail / push) ; mandat de test et aucun paiement ; créneaux et demandes **par vente** (un bien ou un lot) ; adresse exacte après une visite acceptée : **proposée, non décidée** (plan Q14).

Légende : ✅ fait · 🚧 partiel · 📋 à faire

## US-09.1 · Ouvrir mes créneaux de visite (V12) 📋
*En tant que vendeur L’Essentiel ou Premium, je veux ouvrir et fermer mes créneaux semaine par semaine.*
- 📋 Semaine navigable jusqu’à 6 semaines, cases horaires Disponible / Réservé / Fermé avec légende ; délai de prévenance de 24 h.
- 📋 « Répéter chaque semaine » applique mes créneaux à toutes les semaines ; « Seulement ce jour-là » crée une exception ; durée d’une visite 30 / 45 / 60 min.
- 📋 Une case réservée ne peut pas être fermée (message) ; une visite acceptée sur un autre de mes biens bloque la case.
- 📋 Enregistrement automatique ; en cas d’erreur réseau, retour à l’état enregistré et message.

## US-09.2 · Voir mes demandes de visite (V13) 📋
*En tant que vendeur, je veux voir les demandes en attente, confirmées et passées de tous mes biens en vente.*
- 📋 Segments avec compteurs ; carte avec date, compatibilité et badges de qualification ; filtre par bien si j’en vends plusieurs.
- 📋 Pastille sur l’onglet Visites tant qu’une demande attend ma réponse.
- 📋 États vides avant la mise en ligne et sans demande.

## US-09.3 · Accepter ou refuser une visite 📋
*En tant que vendeur 1 %, je veux accepter ou refuser une demande de visite.*
- 📋 Accepter confirme la visite et refuse automatiquement les autres demandes du même créneau.
- 📋 Refuser ouvre une feuille avec un motif facultatif, jamais transmis tel quel à l’acquéreur.
- 📋 L’Expert : lecture seule, « Géré par votre agent ».

## US-09.4 · Annuler une visite et indiquer son issue 📋
*En tant que vendeur, je veux annuler une visite confirmée et dire si l’acquéreur est venu.*
- 📋 Annulation avec confirmation intégrée ; l’équipe prévient l’acquéreur.
- 📋 Une visite passée est « Réalisée » par défaut ; « Acquéreur absent » possible pendant 7 jours ; note privée.

## US-09.5 · Profil light de l’acquéreur (V13b) 📋
*En tant que vendeur, je veux savoir pourquoi un acquéreur est compatible sans voir ses données privées.*
- 📋 Score et sous-scores, raisons, foyer, financement, capacité, calendrier ; mention de confidentialité.
- 📋 Blocs vides masqués ; aucune coordonnée, aucun revenu, aucune pièce justificative.

## US-09.6 · Lire le compte rendu d’une visite (V14) 📋
*En tant que vendeur, je veux lire le compte rendu d’une visite menée par un agent.*
- 📋 Auteur, acquéreur, niveau d’intérêt, points appréciés, freins, prochaine étape.
- 📋 « Ouvrir la négociation » quand une offre de cet acquéreur existe (EPIC-10).

## US-09.7 · Être prévenu 📋
*En tant que vendeur, je veux être prévenu dans l’app de ce qui concerne mes visites.*
- 📋 Notifications : nouvelle demande, requalification ou décision de l’agent, annulation, rappel la veille, compte rendu publié ; chacune ouvre la demande.

## US-09.8 · Saisie par l’équipe et démonstration 📋
*En tant qu’équipe Realesty, je veux saisir les visites à la place des acquéreurs et des agences tant qu’ils n’ont pas d’app.*
- 📋 Fonctions `staff_*` (créer une demande, requalifier, décider pour l’agent, annuler, issue, publier un compte rendu) non appelables depuis l’app ; runbook « Organiser les visites ».
- 📋 Démo de 3 demandes (`source = demo`, `is_test`) sur une vente de test, supprimable en une commande.

## US-09.9 · Prêt pour l’app acquéreur 📋
*En tant qu’équipe produit, je veux que l’app acquéreur se branche sans migration de données.*
- 📋 `buyer_user_id`, `source`, instantané versionné et contrôlé (liste blanche), note du vendeur séparée, créneaux calculés côté serveur.
- 📋 Aucune politique du vendeur ne joint les tables de l’acquéreur.
