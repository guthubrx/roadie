# Spécification 026 — Barre Caps+F sobre et fixe

**Branche** : `session-026-command-bar` | **Date** : 2026-10-14
**Statut** : en cours | **Validation utilisateur** : « go »

## Besoin

Compléter la saisie avec Tab et rendre la barre stable et sobre, avec un aspect
de champ de conversation. Conserver les tailles de police indépendantes de la session 025.

## Scénarios et exigences

- US1 / FR-001 : en recherche, Tab remplace la requête par le titre de la cible
  sélectionnée, sans l'activer ; aucun résultat ou titre vide ne change la saisie.
  Les flèches, Ctrl-N, Ctrl-P et Maj-Tab gardent leur navigation existante.
- US2 / FR-002 : en mode commande, Tab accepte la suggestion sélectionnée.
  Les Tab suivants parcourent les alternatives ; commandes et arguments restent complétables.
- US3 / FR-003 : position et largeur de la barre indépendantes de la saisie,
  des résultats, des suggestions et des messages ; largeur 640 points, bornée
  à l'écran, ancrage bas-centre conservé. Les panneaux restent au-dessus.
- US4 / FR-004 : retirer la loupe et les mots « correspondance(s) » ; afficher
  le nombre de résultats dans une pastille à droite, séparée du texte de saisie.
- US5 / FR-005 : police système San Francisco proportionnelle, bordure neutre
  de 0,5 point, fond sombre discret, coins arrondis et sélection sobre.
- FR-006 : le texte long reste lisible par troncature, sans recouvrir le compteur
  ni déplacer la barre ; les réglages de taille s'appliquent toujours immédiatement.
- FR-007 : une complétion ne déclenche ni clic ni commande. Un titre commençant
  par `/` ne doit pas faire entrer accidentellement en mode commande.

## Validation

Tests Swift : routage de Tab, cible sélectionnée, absence de résultat, complétion
des commandes et arguments ; géométrie identique avec textes et listes de tailles
différentes, compteur séparé, petits écrans et grandes polices. Rendus AppKit hors
écran inspectés puis test utilisateur de la version installée.

## Hors périmètre

Nouvelles commandes, nouvelles dépendances, moteur de tuilage et nouvelle release.
