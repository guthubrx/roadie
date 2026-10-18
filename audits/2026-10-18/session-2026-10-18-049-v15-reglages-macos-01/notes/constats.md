# Constats - session 049 readonly (révision 0)

Auditeur : Claude (Opus), `independent=false`.

## F1 - LOW - Critère de réussite non vérifié : pas de validation consignée

- Fichier : `specs/049-reglages-macos/tasks.md:6` (T004 non cochée) ; aucun `validation.md`.
- La spec (l. 25-28) exige que `roadie query health` installé renvoie `ok` sur la machine de
  l'utilisateur. Le commit ne contient ni validation, ni revue, ni résultat d'installation.
- Observation de cet audit : les quatre préférences valent 0 sur la machine (macOS 26.2), donc la
  logique donnerait `ok` ; le binaire installé n'a pas été exécuté (installation interdite).
- Correction : exécuter la suite, installer, consigner `roadie query health` dans un `validation.md`
  et cocher T004, ou réduire le critère.

## Points relus sans défaut
- `failed` ne dépend que de `.fail` : le nouvel avertissement ne change ni le code de sortie de
  `daemon health` ni `heal()`.
- Aucune écriture de préférences (R5) ; aucun consommateur de `.warn`.
- Défauts retenus (Stage Manager désactivé ; juxtaposition par bord et par barre des menus activées
  depuis macOS 15 ; clic sur le fond d'écran « Toujours » depuis macOS 14) : cohérents avec le
  comportement connu de ces versions, non documentés par Apple (limite déjà écrite).
- Observation : le message et les chemins sont en français seulement ; sur un macOS en anglais, les
  noms ne correspondent pas aux libellés de Réglages Système. Non retenu comme défaut (convention des
  messages du projet non spécifiée) ; signalé dans `axes.md`.
