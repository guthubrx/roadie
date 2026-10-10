# Data Model : Stabilisation de Roadie

## PersistentStageState (existant, `stages.json`)

- Inchangé dans sa structure. Ajouts :
  - `PersistentWindowPin.missingSince: Date?` : début d'absence ; l'épinglage est retiré après 45 s d'absence (FR-007).
  - `PersistentStageMember.pid: Int32?` : pid observé, utilisé par la réconciliation d'identité (FR-006). Optionnel pour rester compatible avec les fichiers existants.
- Écrit uniquement via `StageStore.mutate` ou `save` (sans écriture si inchangé).
- Un décodage en échec produit `stages.json.corrupt-<horodatage>` et bloque l'écriture.

## LayoutCommandIntent (existant, `layout-intents.json`)

- `arguments["presentation"] = "fullscreen"` marque un plein écran par commande (FR-001, FR-012).
- Ajout côté store : `missingDisplaySince` par display pour la grâce de 10 min avant purge (FR-020).

## RestoreSnapshot (existant, restore safety)

- Contient la dernière frame VISIBLE de chaque membre (jamais une frame masquée), écrit à chaque changement de stage et toutes les 30 s.

## DaemonStatus (nouveau, `daemon-status.json`)

Voir [contracts/daemon-status.md](./contracts/daemon-status.md).

## Registres en mémoire (non persistés)

- **AXUnresponsiveApps** : `pid → resumeAt` (5 s).
- **ClampedFrame / FailedFrame** (LayoutMaintainer) : ajout `recordedAt`, expiration 30 s, purge des fenêtres disparues.
- **Classement précédent** (DaemonSnapshot) : `WindowID → isTileCandidate` pour l'hystérésis (FR-008).
