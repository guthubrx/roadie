# ADR 021 - Fichiers déjà ouverts avant la réponse de Spotlight

Date : 2026-10-29. Statut : Accepté.

## Contexte

Sous forte charge, Spotlight répond à la barre en 0,4 à 4,6 s (mesures `launcher.timing` de la session 123). Les
fichiers arrivaient donc toujours après le reste. Quand ils arrivaient, des fichiers jamais ouverts au nom plus proche
de la saisie chassaient les documents que l'utilisateur ouvre réellement.

Comparaison des autres lanceurs (relevé du 29 octobre 2026) : Alfred interroge Spotlight à chaque recherche et garde
ses choix appris à part ; LaunchBar et Raycast tiennent leur propre index des fichiers. Une même requête Spotlight
répétée accélère d'elle-même (629 puis 303 ms).

## Décision

- Roadie garde en mémoire la liste des fichiers ouverts (`kMDItemLastUsedDate` sur 10 ans, environ 1 000 fichiers),
  relue en fond toutes les 5 minutes au plus. Elle répond par « contient » dès la première touche.
- Spotlight reste interrogé en fond (`MDQuery`, délai de 120 ms, seule la dernière saisie compte) et complète la liste.
- Un fichier déjà ouvert passe devant un fichier jamais ouvert ; les choix appris restent prioritaires.

Pas d'index complet des fichiers : coût d'écriture et de maintenance hors de proportion avec le besoin.

## Conséquences

Positives : les documents utiles s'affichent en 50 ms environ et ne bougent plus à l'arrivée de Spotlight.

Négatives : un fichier jamais ouvert reste lié à la vitesse de Spotlight. Un fichier ouvert depuis moins de
5 minutes peut manquer à la liste locale jusqu'à sa relecture ; Spotlight le rattrape.
