# Session 085 - Modificateur des raccourcis 1 à 9

Demande du 26 octobre 2026 : Commande est déjà pris chez l'utilisateur. La touche des
raccourcis 1 à 9 du lanceur doit se choisir dans les paramètres. Défaut : Commande. Chez
l'utilisateur : Maj.

## Exigences

- **FR-001** `experimental.target_mode.pick_modifier` : `command` (défaut), `shift`, `alt` ou
  `control`. Une autre valeur revient à `command`.
- **FR-002** Ce modificateur + un chiffre (rangée du haut ou pavé, par code physique) ouvre la
  ligne de ce rang, à toutes les étapes. Les autres modificateurs + chiffre ne l'ouvrent plus.
- **FR-003** Le rappel à droite des lignes montre le symbole choisi (⌘, ⇧, ⌥, ⌃).
- **FR-004** Le réglage apparaît dans Paramètres > Recherche, avec sa limite : avec `shift`,
  les chiffres de la rangée du haut ne s'écrivent plus dans la recherche en AZERTY.
- **FR-005** Configuration de l'utilisateur réglée à `shift`, après sauvegarde.

## Compatibilité

Maj + lettre reste aux pastilles (SPEC-084) : lettres et chiffres n'ont pas les mêmes codes.
Avec `alt` ou `control`, tenir la touche annonce toujours la variante de Retour ; la
touche + chiffre ouvre la ligne par son action normale.
