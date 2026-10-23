# Session 058 - Cohérence et finition des paramètres
Branche : session-058-coherence-parametres
Création : 23 octobre 2026. Statut : Ready. Priorité : P1.
Correction demandée explicitement ; validation automatique des correctifs.
Estimation : 1 à 2 heures, tests, contrôle visuel et installation compris.
Tests : 0/0.

## Objectif
Rendre toutes les catégories de paramètres cohérentes, compactes et lisibles.
Corriger aussi les alignements de l'éditeur de profils du sélecteur.

## Parcours utilisateur et acceptation
### P1 - Régler une valeur sans chercher son contrôle
Dans Tuilage, Rail, Recherche et Sélecteur, les libellés occupent la colonne de
gauche ; champs, menus et interrupteurs commencent au même endroit à droite.
Le retour à la valeur par défaut garde un emplacement stable. Les valeurs valides
continuent de s'appliquer immédiatement, sans modifier les raccourcis existants.
### P1 - Lire une règle ou une liste
Les règles et autres formulaires partagent le même alignement. Chaque entrée a
un résumé identifiable et peut être repliée. Un interrupteur et son libellé restent
sur la même ligne. Les listes simples gardent ajout et suppression directs.
### P1 - Lire toute une aide
Un clic sur le bouton d'information ouvre une aide avec texte intégral lisible.
Une aide longue ou une grande police dispose d'un défilement ; aucune fin de texte
ne devient inaccessible. L'aide se ferme normalement sans changer la valeur.

## Exigences
- Toutes les catégories sont couvertes, y compris Général, Règles et Sélecteur.
- Une valeur ordinaire tient sur une ligne à largeur normale, sauf libellé long.
- Les sélecteurs d'un même formulaire partagent leurs bords gauche et droit.
- Titres redondants et aides permanentes évitables sont supprimés.
- Après essai : lignes plus compactes ; onglets du sélecteur visiblement groupés,
  de même largeur et étalés sur toute la zone. À grande police, deux rangées
  préservent les mots entiers, sans remplacer les onglets par un menu.
- Fenêtre minimale et polices 8 à 32 points restent utilisables sans débordement
  horizontal. Au besoin, une disposition verticale cohérente est utilisée.
- Les valeurs inconnues, brouillons, conflits, validations et application immédiate
  sont préservés. Aucun changement de configuration au seul affichage.
- Aucun nouveau thème, dépendance ou changement de comportement des fenêtres.

## Cas limites
Libellé très long, aide de plusieurs paragraphes, liste vide, plusieurs règles,
critères et actions dépliés, police maximale, menu avec valeur inconnue,
configuration invalide et modification externe pendant la saisie.

## Critères de réussite
Contrôle des douze catégories à largeur normale et minimale. Sur les formulaires
en colonnes, écart d'alignement entre contrôles inférieur à un point. Aides intégrales
accessibles. Tests, revue et reçu honnête des parcours observés.
