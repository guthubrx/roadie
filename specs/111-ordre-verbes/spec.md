# Session 111 : ordre appris des verbes

## Besoin

Reprise d'Alfred (« Ordre des actions ») : le verbe le plus utilisé pour un type d'objet passe en tête.

## Règle

- Un verbe choisi à la deuxième étape (après Tab), ou à la troisième (destination), compte pour son type
  d'objet : application, fichier, projet, adresse, fenêtre, stage, bureau, écran, cible.
- Mémoire : le classement appris existant (`launcher-ranking.json`, fréquence-récence à demi-vie de 10 jours),
  clé `verb:<type>:<verbe>`. Retour direct sur un objet ne compte pas : seul un choix explicite de verbe compte.
- Les verbes sont triés par score décroissant ; à égalité, l'ordre par défaut reste. Le filtre par la saisie
  s'applique ensuite.
- Réglage `learn_verb_order` (Paramètres > Recherche), actif par défaut. `learning_enabled = false` coupe aussi
  cet apprentissage (classement vide, rien n'est enregistré).

## Hors périmètre

- Ordre appris des destinations (déjà classées par la saisie).
