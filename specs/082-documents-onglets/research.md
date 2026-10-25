# Recherche 082

## R1 Documents
`axDocumentRead` (077/080) : fichier ou adresse web, une lecture AX par fenêtre, en tâche détachée
groupée par application. Chrome n'expose que l'adresse de l'onglet affiché.

## R2 Onglets
AppleScript des navigateurs Chromium (`windows`, `tabs`, `bounds`, `title`, `URL`,
`active tab index`) et de Safari (`name`, `URL`, `current tab`). Exécuté par `osascript` en
processus séparé, avec délai de 2 s : un navigateur bloqué ne bloque pas la barre. Autorisation
d'automatisation demandée par macOS au premier usage (« roadied souhaite contrôler… »). Sortie en
lignes séparées par tabulations.

## R3 Fenêtre d'un onglet
Les fenêtres AppleScript n'ont pas le `CGWindowID`. Leur `bounds` (haut-gauche) se compare au cadre
de la fenêtre gérée du même navigateur (2 points de tolérance).

## R4 Firefox
Ni `AXDocument` (relevé 077) ni dictionnaire AppleScript d'onglets : non couvert.
