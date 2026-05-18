# Data Model: Roadie Target Mode

## TargetID

- **Description**: Identifiant stable dans le résultat courant.
- **Format**: Chaîne composée du type et de l'identité source, par exemple `window:123`, `stage:display/1/work`, `app:123/button/4`.
- **Validation**: Non vide, préfixe type obligatoire.

## TargetKind

- **Description**: Catégorie fonctionnelle.
- **Valeurs**:
  - `window`
  - `stage`
  - `display`
  - `desktop`
  - `bookmark`
  - `appElement`

## Target

- **id**: TargetID.
- **label**: Code court affichable ou tapable.
- **kind**: TargetKind.
- **title**: Nom principal lisible.
- **subtitle**: Contexte court.
- **matchText**: Texte normalisé pour recherche.
- **scope**: Display/desktop/stage/window si disponible.
- **frame**: Rectangle global si disponible.
- **isActive**: Vrai si la cible correspond au focus ou à la stage active.
- **source**: `roadie` ou `accessibility`.
- **actions**: Actions autorisées.
- **diagnostics**: Raisons utiles à l'inspecteur.

## TargetQuery

- **source**: `roadie`, `app`, `all`.
- **filter**: Texte facultatif.
- **includeHidden**: Inclure les stages non visibles si demandé explicitement.
- **maxResults**: Limite de résultats.
- **appTargetsEnabled**: Garde-fou expérimental.

## TargetModeConfig

- **enabled**: Active ou coupe toute la surface `roadie targets`.
- **pickerEnabled**: Active ou coupe le flux `targets pick`.
- **overlayEnabled**: Réserve l'activation du futur overlay graphique.
- **overlayLabelsOnly**: Préférence d'affichage labels-only pour les consommateurs overlay.
- **overlayDurationSeconds**: Durée d'affichage prévue pour un overlay visuel.
- **appMouseActionsEnabled**: Autorise explicitement `click`, `double-click` et `right-click` sur app targets.
- **scrollModeEnabled**: Réserve l'activation d'un futur scroll-mode applicatif.

Par défaut, le socle CLI et le picker sont actifs, mais l'overlay graphique, les
clics applicatifs et le scroll-mode restent désactivés.

## TargetGridConfig

- **enabled**: Active les commandes `roadie grid`.
- **overlayEnabled**: Autorise l'affichage visuel de la grille via TargetOverlayPresenter.
- **rows / columns**: Découpage de chaque niveau.
- **maxDepth**: Nombre maximal de subdivisions récursives.
- **hintCharacters**: Alphabet des cellules.
- **defaultScope**: `display` pour l'ecran cible complet ou `focused_window` pour la fenetre focussee.
- **actionDelayMs**: Petite pause après action souris pour laisser macOS appliquer l'événement.

## TargetRecordConfig

- **enabled**: Active `roadie record start`.
- **replayEnabled**: Active `roadie record replay`.
- **directory**: Dossier JSON des enregistrements.
- **defaultDurationSeconds / maxDurationSeconds**: Bornes de capture.
- **maxEvents**: Protection contre les captures infinies.
- **includeMouseMoves**: Enregistre les mouvements continus si activé.
- **includeKeyEvents**: Enregistre key down/up.
- **includeAXContext**: Ajoute la cible Roadie/AX la plus spécifique à chaque clic.
- **recordTextInput**: Désactivé par défaut pour ne pas écrire le texte saisi.

## TargetAction

- **targetID**: Cible à activer.
- **verb**:
  - `focus`
  - `switch`
  - `send-active`
  - `inspect`
  - `click`
  - `double-click`
  - `right-click`
- **followFocus**: Option applicable aux assignations.

## TargetPickResult

- **query**: Texte ou label demandé par l'utilisateur.
- **candidates**: Cibles candidates si le résultat est ambigu ou si aucune action n'est encore appliquée.
- **selected**: Cible unique retenue si résolution réussie.
- **action**: Action demandée ou action par défaut de la cible.
- **result**: Résultat d'activation si une action a été exécutée.
- **error**: `unknown_target`, `ambiguous_target`, `stale_target` ou `unsupported_action`.

## TargetOverlayState

- **visible**: Vrai si l'état demandé correspond à un affichage de labels.
- **labelsOnly**: Vrai si le consommateur ne doit afficher que les labels, sans décor lourd.
- **source**: `roadie`, `app` ou `all`.
- **targets**: Inventaire de cibles à afficher.
- **generatedAt**: Date de génération.
- **expiresAt**: Date facultative si un futur overlay doit s'auto-masquer.

## TargetGridCell

- **path**: Chemin récursif, par exemple `A`, `AA`, `AAG`.
- **label**: Label du niveau courant.
- **display**: ID, index, nom et frame visible.
- **scope / rootFrame**: Portee et frame racine utilisees avant subdivision.
- **frame / center**: Coordonnées globales AX utilisables pour actions souris.
- **row / column / depth**: Position logique dans la grille.

## TargetMacroRecording

- **name**: Nom de macro.
- **createdAt**: Date de capture.
- **durationSeconds**: Durée demandée.
- **events**: Liste ordonnée de `TargetMacroEvent`.

## TargetMacroEvent

- **t**: Temps relatif depuis le début de la capture.
- **kind**: `mouse-down`, `mouse-up`, `mouse-move`, `key-down`, `key-up`, `scroll`.
- **point**: Coordonnées écran si applicables.
- **target**: Cible Roadie/AX la plus spécifique si trouvée.
- **gridPath**: Chemin de grille de secours.
- **keyCode / modifiers / scrollDeltaY**: Détails bas niveau pour replay.

## TargetInspection

- **target**: Target.
- **summary**: Résumé humain.
- **identity**: App, bundle, title, window ID, stage ID, display ID.
- **state**: Tileable, floating, pinned, focused, active, hidden.
- **reasons**: Liste de raisons d'inclusion/exclusion.
- **recentEvents**: Types d'événements récents liés si disponibles.

## State Transitions

```text
listed -> inspected
listed -> activated
listed -> picked -> activated si cible unique
listed -> picked -> ambiguous_target si plusieurs candidates
activated -> stale_target si la cible a disparu
app_query -> partial si timeout ou limite atteinte
show -> hide sans effet layout
grid_path -> grid_action sans effet layout Roadie
record_start -> recording_json
recording_json -> replay_target -> replay_coordinates fallback
```
