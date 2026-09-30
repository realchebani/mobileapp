# EPIC-03 · Authentification par lien magique

**Objectif** : permettre à un utilisateur de se connecter avec son e-mail via un lien magique Supabase, puis de choisir son rôle (vendeur / acheteur).
**Statut** : ✅ Terminé

## US-03.1 · Écrans de connexion par e-mail (design) ✅
- [x] Artboards « 01b · Connexion par e-mail » et « 01c · Vérifiez vos e-mails » ajoutés au canvas ; « Continuer avec un e-mail » y mène.

## US-03.2 · Recevoir un lien de connexion ✅
*En tant que visiteur, je veux saisir mon e-mail et recevoir un lien, sans mot de passe.*
- [x] `AuthRepository.sendMagicLink` (PKCE, URL de retour par flavor, création de compte automatique).
- [x] `LoginCubit` : validation de l'e-mail, acceptation des CGU obligatoire, états envoi/envoyé/erreur.
- [x] Erreurs typées : e-mail invalide, adresse non autorisée, limite d'envoi, réseau.
- [x] Écrans Flutter 01 (Connexion), 01b (Connexion par e-mail), 01c (Vérifiez vos e-mails), avec messages d'erreur en français.

## US-03.3 · Ouvrir le lien et être connecté ✅
*En tant qu'utilisateur, je veux toucher le lien reçu et arriver connecté dans l'app.*
- [x] Schéma d'URL par flavor sur iOS, URL autorisées dans Supabase.
- [x] `AppBloc` : statut inconnu / non connecté / connecté, déconnexion.
- [x] Lien expiré ou déjà utilisé : erreur remontée (« renvoyez un lien »).
- [x] Navigation automatique selon le statut (go_router, fonction `appRedirect` testée) : Splash → Découvrir (1er lancement) → Connexion → Rôle → espace vendeur/acheteur.
- [x] Test de bout en bout sur iPhone validé par le porteur de projet (2026-09-30).

## US-03.4 · Renvoyer le lien / changer d'adresse ✅
- [x] Renvoi possible après 60 s (compte à rebours), relancé en cas de limite d'envoi.
- [x] Changement d'adresse sans effet de bord d'un envoi en cours.
- [x] Interface Flutter : compte à rebours lisible, « Ouvrir Mail », « Changer d’adresse e-mail ».

## US-03.5 · Profil et choix du rôle ✅
*En tant qu'utilisateur connecté, je veux indiquer si je veux vendre ou acheter.*
- [x] Table `profiles` (prénom, rôle), RLS « chacun sa ligne », création automatique à l'inscription — migration appliquée.
- [x] `ProfileRepository` (lecture du profil, mise à jour du rôle).
- [x] Écran « 02 · Sélecteur de rôle » ; espaces vendeur/acheteur provisoires avec déconnexion.

## US-03.6 · Découverte de l'app (onboarding) ✅
*En tant que nouveau visiteur, je veux comprendre la proposition de Realesty avant de me connecter.*
- [x] Splash puis « Découvrir » (4 pages) au premier lancement uniquement ; « Passer » / « J’ai déjà un compte ».

## Limites connues (v1)
- E-mails envoyés par le service par défaut de Supabase : modèle en anglais, ~2 envois/heure, uniquement vers les membres de l'organisation Supabase. Un SMTP (ex. Brevo) sera nécessaire avant d'ouvrir l'app à d'autres personnes.
- Le lien doit être ouvert sur l'iPhone qui l'a demandé (PKCE).
- Connexion Apple / Google : prévue au design, masquée en v1.
