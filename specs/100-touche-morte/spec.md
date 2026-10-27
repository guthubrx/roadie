# Session 100 - Touches mortes dans la barre

## Problème

Sur un clavier français, `~` se tape avec ⌥N, une touche morte : macOS affiche un tilde provisoire
(texte marqué), puis le valide à la touche suivante. Le texte marqué n'est pas transmis au modèle de la
barre. Au relâchement de ⌥, la barre se redessine avec l'ancienne saisie : `SearchInputPanel.update`
remplaçait alors le champ par cette saisie et effaçait le tilde. Même défaut pour `^` puis `e`.

## Observation

Test jetable sur le vrai `SearchInputPanel` : après `setMarkedText("˜")`, aucun `onChange` ; un
`update(text: "")` vidait l'éditeur (`editor=""`, `marked=false`).

## Exigences

- FR-001 : pendant une composition, un rendu de la barre ne modifie pas le texte du champ.
- FR-002 : le texte validé (`~`, `ê`) arrive au modèle par le chemin habituel ; `~` liste le dossier
  personnel (SPEC-087).
- FR-003 : hors composition, le modèle garde la main sur le texte (complétion `~/`, reprise de saisie).
