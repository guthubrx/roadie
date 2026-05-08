# Modèle de Données : Roadie Control & Safety

## ControlCenterState

**But**: Etat compact affiche par la barre de menus et la fenetre de reglages.

**Champs**:

- `daemonStatus`: running, stopped, degraded, unknown
- `configPath`: chemin abrege de la configuration active
- `configStatus`: valid, reloadPending, reloadFailed, fallback
- `activeDesktop`: label/index actif si disponible
- `activeStage`: stage actif si disponible
- `windowCount`: nombre de fenetres gerees
- `lastError`: derniere erreur importante optionnelle
- `lastReloadAt`: date optionnelle du dernier reload
- `actions`: disponibilite des actions reload, reapply, reveal config, reveal state, quit

**Relations**:

- Agrege `ConfigReloadState`, `DaemonHealth`, `RoadieState` et dernier evenement d'erreur.

## ConfigReloadState

**But**: Representer la configuration active et le resultat du dernier reload.

**Champs**:

- `activeConfig`: configuration valide actuellement appliquee
- `activePath`: chemin source
- `activeVersion`: hash ou revision locale de contenu
- `pendingPath`: chemin en cours de reload optionnel
- `lastValidation`: success, failed, skipped
- `lastError`: message structure optionnel
- `lastAttemptAt`: date de tentative
- `lastAppliedAt`: date d'application

**Transitions**:

- `idle -> validating -> applied`
- `idle -> validating -> failedKeepingPrevious`
- `failedKeepingPrevious -> validating -> applied`

**Regles**:

- Une config invalide ne remplace jamais `activeConfig`.
- Les erreurs sont publiees en evenement et exposees au Control Center.

## RestoreSafetySnapshot

**But**: Sauvegarde minimale permettant de rendre les fenetres recuperables apres arret ou crash.

**Champs**:

- `schemaVersion`
- `createdAt`
- `daemonPID`
- `windows`: liste de `RestoreWindowState`
- `activeDisplayID`
- `activeDesktop`
- `activeStage`

## RestoreWindowState

**Champs**:

- `windowID`: identifiant volatile si disponible
- `identity`: `WindowIdentityV2`
- `frame`: derniere frame connue
- `visibleFrame`: frame ecran de secours
- `wasManaged`: bool
- `wasHiddenByRoadie`: bool
- `stageScope`: scope optionnel
- `groupID`: optionnel

**Regles**:

- La restauration vise d'abord la visibilite et la recuperabilite.
- Si la frame sauvegardee est hors ecran, utiliser une frame visible de secours.

## WindowIdentityV2

**But**: Matcher une fenetre entre deux snapshots malgre des IDs volatils.

**Champs**:

- `bundleID`
- `appName`
- `title`
- `role`
- `subrole`
- `pidHint`
- `windowIDHint`
- `createdAt`

**Regles de matching**:

- Match fort : bundle ID + titre + role/subrole compatibles.
- Match moyen : bundle ID + app name + titre partiel.
- Match faible : app name seul, insuffisant pour restauration automatique.
- Un etat deja affecte ne peut pas etre reutilise pour une autre fenetre.

## TransientWindowState

**But**: Decrire la presence d'une fenetre systeme transitoire.

**Champs**:

- `isActive`
- `reason`: sheet, dialog, popover, menu, openSavePanel, unknownTransient
- `ownerBundleID`
- `recoverable`: bool
- `frame`: optionnelle
- `detectedAt`

**Regles**:

- Si `isActive`, suspendre tiling/focus non essentiels.
- Si `recoverable` et hors ecran, tenter une remise en zone visible.

## WidthAdjustmentIntent

**But**: Representer une demande utilisateur de changement de largeur.

**Champs**:

- `scope`: activeWindow, activeRoot, allWindows
- `mode`: presetNext, presetPrevious, nudge, explicitRatio
- `delta`: optionnel
- `targetRatio`: optionnel
- `createdAt`

**Regles**:

- Rejeter si le layout actif ne supporte pas l'ajustement.
- Clamper les ratios dans les bornes documentees.
- Persister comme intention utilisateur lorsque l'application reussit.
