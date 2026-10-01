# EPIC-05 · Estimation non certifiée (tendance de prix)

**Objectif** : donner au vendeur, dès l'envoi de son dossier, une première estimation **non certifiée** de son bien, en croisant les ventes réelles (DVF) et la tendance du prix au m² de son secteur. L'expert reste seul à certifier la valeur.
**Statut** : 📋 En préparation (plan et cahier des charges en cours de rédaction)

Décisions : sans annonces en vente en v1 ; affichage sur la carte « Tendance IA » (V8) et l'écran « Synthèse du marché » (V8b) ; l'IA (Claude via OpenRouter) rédige seulement l'explication à partir des chiffres calculés.

Principe retenu : ventes comparables DVF (même type, rayon croissant 500 m → commune, 3–5 ans, surface ±30 %, ventes aberrantes écartées), médiane et quartiles du prix au m² pondérés par proximité et récence, courbe semestrielle sur 5 ans projetant les ventes à aujourd'hui, ajustements simples (annexes, terrain, année, équipements), indice de confiance.

Règles validées :
- calcul **une seule fois, à l'envoi** du dossier (pas de recalcul ; l'expert certifie ensuite) ;
- ventes comparables affichées avec **la rue sans le numéro** ;
- **moins de 5 ventes comparables → pas d'estimation**, message « l'expert s'en charge ».

Les user stories seront détaillées avec le plan.
