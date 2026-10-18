# ADR-009 : Un arbre qui fait foi et une passe par événement

## Statut

Accepté. Mis en oeuvre par la SPEC-017 (`specs/017-reactive-tiling/research.md`, décisions R1 à R15 et amendements A1 à A20).

## Contexte

Le 2026-10-11, Roadie détectait un changement en 73 ms. Il mettait pourtant environ 6 s à poser une disposition stable après une sortie de plein écran natif : une attente fixe de 2 s, puis jusqu'à 7 passes espacées de 500 ms.

Le mode par défaut de l'utilisateur, `mutableBsp`, n'avait pas de structure qui fait foi. Il recalculait l'ordre, le sens et les proportions depuis la position observée des fenêtres. Chaque passe changeait donc la passe suivante. Roadie prenait aussi ses propres placements pour des gestes de l'utilisateur, ce qui faisait « sauter » les fenêtres.

yabai, lui, garde un arbre en mémoire qui fait foi. Il traite chaque événement une seule fois et pose chaque fenêtre une fois.

## Décision

1. **Un seul moteur à arbre.** `spatialBsp` (SPEC-013/014) devient l'unique moteur à arbre. `mutableBsp` et `yabai` en sont des alias dans la config. Les stages `mutableBsp` persistées sont migrées une fois, sous verrou, avec une sauvegarde des octets d'origine.
2. **L'arbre fait foi.** En mode arbre, la disposition se calcule uniquement depuis l'arbre, projeté sans les fenêtres absentes. Les intentions géométriques ne s'appliquent plus, sauf le marqueur de zoom. La position observée ne modifie l'arbre que lors d'un geste reconnu à la souris.
3. **Une passe par événement.** Un ordonnanceur unique, sur le thread principal, regroupe les événements pendant 15 à 30 ms et n'en perd aucun. Il arme un seul minuteur sur la prochaine échéance interne. Une passe rassemble tous les placements dans un plan unique, dédoublonné par fenêtre, appliqué une fois. Le relevé périodique devient un filet de sécurité à 2 s.
4. **Écho, réponse, geste, changement externe.** Un registre des frames écrites, au point unique d'écriture Accessibility, classe chaque frame observée. Un geste n'est reconnu que par une session de souris sur la fenêtre. Un changement externe est ramené une fois à l'arbre.
5. **Budget d'écriture.** Pour chaque génération de placement (ouverte par une intention externe), une fenêtre reçoit au plus 2 écritures : l'écriture initiale et une correction après un refus de taille confirmé. Ensuite, la taille obtenue est acceptée.
6. **Écriture façon yabai.** L'ordre est taille, position, taille. `AXEnhancedUserInterface` est neutralisé pendant l'écriture. Il y a une seule relecture.
7. **Attentes conditionnelles.** Pas d'attente pour un changement isolé. Une stabilisation courte n'a lieu que pour une vraie rafale. La garde de transition de bureau se ferme dès que le bureau courant de l'écran est un bureau utilisateur (voir ADR-010).

## Conséquences positives

- Disposition stable en une passe pour les événements ordinaires. Plus de tâtonnement ni d'oscillation.
- Placements prévisibles : une nouvelle fenêtre coupe la fenêtre active, une fenêtre fermée rend sa place à sa voisine.
- Suppression de plusieurs centaines de lignes propres à `mutableBsp`.
- Mesure reproductible à la milliseconde (`tsMs`, épisodes, `scripts/measure-layout-reactivity`).

## Conséquences négatives

- Comportement changé pour les utilisateurs de `mutableBsp` : la disposition suit l'arbre, et non plus la géométrie observée. La migration construit l'arbre initial depuis la géométrie pour éviter un saut.
- Les modes `bsp` et `masterStack` gardent leur stratégie dérivée de la géométrie. Ils profitent du plan unique et de la reconnaissance d'écho, sans la garantie d'une passe.
- Les lecteurs du snapshot (bordure, focus qui suit la souris) gardent leur cadence actuelle, avec un relevé au plus toutes les 150 ms. Amendé par `015-releves-lecteurs-au-repos.md` : sans changement observé, un relevé reste réutilisable jusqu'au filet du tiler.
