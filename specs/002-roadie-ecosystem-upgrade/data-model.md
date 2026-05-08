# Data Model: Roadie Ecosystem Upgrade

## RoadieEventEnvelope

Événement stable publié par Roadie.

**Fields**:

- `schemaVersion`: entier, commence à `1`.
- `id`: identifiant unique d'événement.
- `timestamp`: ISO-8601 UTC.
- `type`: nom stable (`window.created`, `desktop.changed`, `rule.applied`, etc.).
- `scope`: contexte optionnel (`window`, `display`, `desktop`, `stage`, `layout`, `rule`, `command`).
- `subject`: objet principal optionnel `{ "kind": "...", "id": "..." }`.
- `correlationId`: identifiant partagé entre commande, effets et événements dérivés.
- `cause`: origine (`ax`, `command`, `rule`, `startup`, `config_reload`, `system`).
- `payload`: objet JSON typé selon `type`.

**Validation**:

- `type` obligatoire et non vide.
- `timestamp` obligatoire.
- `payload` doit rester JSON sérialisable sans valeur Swift spécifique.
- ajout de champs autorisé ; suppression/renommage interdit sans nouvelle version.

## EventSubscription

Vue logique d'un consommateur d'événements.

**Fields**:

- `from`: `now`, `beginning`, ou offset journal si supporté.
- `types`: liste optionnelle de types inclus.
- `scopes`: liste optionnelle de scopes inclus.
- `initialState`: booléen.
- `format`: `jsonl` par défaut.

**Transitions**:

- `starting` -> `snapshot_emitted` si `initialState=true`.
- `starting` -> `streaming`.
- `streaming` -> `closed` sur interruption utilisateur ou fin explicite.

## RoadieStateSnapshot

État contractuel destiné aux intégrations.

**Fields**:

- `schemaVersion`
- `generatedAt`
- `activeDisplayId`
- `activeDesktopId`
- `activeStageId`
- `focusedWindowId`
- `displays[]`
- `desktops[]`
- `stages[]`
- `windows[]`
- `groups[]`
- `rules[]` si demandé explicitement

**Validation**:

- toute fenêtre référencée par un stage ou groupe doit exister dans `windows[]`.
- les IDs exposés doivent être stables pendant la durée de vie de l'objet macOS observé.

## WindowRule

Règle déclarative issue de la configuration TOML.

**Fields**:

- `id`: nom stable fourni par l'utilisateur ou généré depuis l'ordre.
- `enabled`: booléen, par défaut `true`.
- `priority`: entier, plus petit appliqué avant plus grand.
- `match`: critères `app`, `title`, `role`, `subrole`, `display`, `desktop`, `stage`, `isFloating`.
- `action`: effets `manage`, `exclude`, `assignDesktop`, `assignStage`, `floating`, `layout`, `gapOverride`, `scratchpad`, `emitEvent`.
- `stopProcessing`: booléen, par défaut `false`.

**Validation**:

- une règle doit avoir au moins un critère `match`.
- regex invalides refusées à la validation de config.
- action contradictoire (`exclude=true` et `layout=tile`) refusée.
- IDs dupliqués refusés.

## RuleEvaluation

Trace d'application d'une règle.

**Fields**:

- `ruleId`
- `windowId`
- `matched`: booléen.
- `actionsApplied[]`
- `reason`
- `correlationId`

**Events**:

- `rule.matched`
- `rule.applied`
- `rule.skipped`
- `rule.failed`

## WindowGroup

Conteneur Roadie pour plusieurs fenêtres dans un slot.

**Fields**:

- `id`
- `stageId`
- `members[]`: IDs fenêtres.
- `activeMemberId`
- `presentation`: `stack` ou `tabs`.
- `locked`: booléen.
- `createdAt`

**Validation**:

- groupe avec moins de deux membres doit être automatiquement dissous ou refusé selon la commande.
- `activeMemberId` doit appartenir à `members`.
- une fenêtre ne peut appartenir qu'à un groupe dans un stage donné.

## LayoutCommandIntent

Commande power-user exposée au CLI.

**Fields**:

- `id`
- `command`: `split`, `joinWith`, `flatten`, `insert`, `zoomParent`, `focusBackAndForth`, `desktopBackAndForth`, `summonWorkspace`.
- `target`
- `arguments`
- `source`: `cli`, `btt`, `rule`
- `correlationId`

**Events**:

- `command.received`
- `command.applied`
- `command.failed`
