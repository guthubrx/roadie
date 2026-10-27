# Recherche 091

## R1 Touches
Le champ natif (`SearchInputPanel.sendEvent`) laisse aujourd'hui ⌥ + flèches à AppKit (mot
précédent ou suivant, début ou fin). Le tampon d'Alfred les prend : ⌥↑ (126), ⌥↓ (125), ⌥← (123),
⌥→ (124), ⌥⌫ (51). Décision : ces cinq touches avec ⌥ seul vont à la sélection ; le déplacement
par mot reste possible avec ⌥ + Maj ou les raccourcis de macOS (⌃A, ⌃E). Coût : une habitude
d'édition perdue dans ce seul champ, signalée dans la documentation.

## R2 Nouvelle stage commune
`stageScope(for:)` crée la stage d'une destination `.newStage` à chaque appel. Pour un lot, la
destination est résolue une fois, puis remplacée par `.stage(scope)` pour tous les objets ; Roadie
affiche la stage à la fin (`focus` de la dernière fenêtre envoyée).

## R3 Annuler un envoi groupé
`WindowMove` (081) gagne un champ facultatif `batch` (décodage des fichiers existants inchangé).
`undoable` renvoie tous les déplacements du dernier lot encore à leur place d'arrivée.

## R4 Applications et fichiers dans un lot
Une application ou un fichier « envoyé » vers une stage s'ouvre dans cette stage (verbe `openIn`
existant, une fenêtre neuve attendue 10 s chacune, en séquence pour attribuer chaque fenêtre).

**Correction du 27 octobre 2026.** Signalé : dans `=sqrt(2)+3`, ⌥ + flèches ne déplaçaient plus le
curseur. Règle retenue : ⌥↑ ⌥↓ vont à la sélection quand la ligne choisie se choisit (application,
fenêtre, fichier) ; ⌥← ⌥→ ⌥⌫ y vont quand une sélection existe. Sinon AppKit déplace le curseur ou
efface par mot, comme avant la 091 (calcul, chemin, texte sans sélection).
