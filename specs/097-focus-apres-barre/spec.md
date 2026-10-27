# Spécification 097 - Revenir et focus clavier après la barre

Demande du 27 octobre 2026 : « pour le moment Échap et Revenir font la même chose, ça me renvoie à
celle en cours avant omnibox roadie... et en plus à chaque fois quand je suis dans T3 [je perds] le
focus sur la zone de saisie et donc je ne peux plus taper ». Correction de la SPEC-081 (validation
automatique).

## Constat
- `/Users/moi/.roadies/events.jsonl`, 06:53:57 et 06:54:04 : « Revenir » active la fenêtre 638
  (T3 Code), celle où l'utilisateur était déjà. Le calcul retirait seulement la fenêtre active lue ;
  si cette lecture est vide ou ne désigne pas une cible connue, la première fenêtre de l'historique,
  la fenêtre en cours, était proposée.
- Le panneau de la barre prend le clavier sans activer Roadie. Fermé par Échap, il ne rend pas la
  frappe à T3 Code. Activer une application déjà au premier plan ne change rien.

## Exigences
- **FR-001** « Revenir » propose la fenêtre vue avant la fenêtre en cours. La fenêtre en cours est la
  fenêtre active si elle est une cible connue, sinon la plus récente de l'historique.
- **FR-002** Avant l'affichage de la barre, Roadie lit la fenêtre et l'élément qui ont le clavier dans
  l'application au premier plan (100 ms au plus par lecture). Après Échap, si cette application est
  toujours au premier plan, Roadie remet la fenêtre principale et l'élément au focus.
- **FR-003** Événements de diagnostic : `launcher.idle_back` (fenêtre active, trois plus récentes,
  proposition) et `launcher.focus_restore` (élément gardé ou non, résultats des écritures, focus relu
  200 ms après).

## Critères de réussite
- SC-001 Tests : la fenêtre précédente est proposée, jamais la fenêtre en cours, focus vide ou inconnu.
- SC-002 Essai réel dans T3 Code : Échap rend la frappe à la zone de saisie.

## Hors périmètre
Fermeture par un clic ailleurs (le clic choisit le focus) ; actions qui changent de fenêtre.
