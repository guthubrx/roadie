# Contrat : événements de placement (journal `~/.roadies/events.jsonl`)

Ajouts **rétrocompatibles**. Les lecteurs existants ignorent les clés inconnues, et les anciennes lignes n'ont pas ces clés.

## Champs communs ajoutés à chaque événement

| Clé | Type | Sens |
|---|---|---|
| `tsMs` | entier | epoch en millisecondes, dérivé de `timestamp` |
| `episodeId` | chaîne, optionnelle | `ep_<epoch ms>` de la cause en cours |

`timestamp` garde son format ISO 8601 à la seconde.

## `layout_apply` : détails ajoutés

| Clé | Sens |
|---|---|
| `durationMs` | durée de la passe (plan + écriture) |
| `cause` | `ax:<notification>` (y compris les notifications système : `ax:activeSpaceDidChange`, `ax:didActivateApplication`, `ax:displayReconfigured`, `ax:didWake`), `command:<nom>` (dont `command:startup`), `drag`, `deadline:<nom>` (`burst`, `guard_cap`, `guard_poll`, `refusal_confirm`, `stable`...), `safety` |
| `pass` | rang de la passe dans l'épisode (1 = première) |
| `scans` | relevés complets faits pendant la passe |
| `axWrites` | écritures AX faites pendant la passe |
| `layoutVersion` | version de disposition appliquée (modes à arbre) |
| `windowWrites` | écritures par fenêtre dans la passe, format `"windowID:n,windowID:n"` |

## Nouveaux types

| Type | Détails | Quand |
|---|---|---|
| `layout_echo_ignored` | `windowID`, `deltaPt` | une frame observée est l'écho d'une écriture |
| `layout_app_response_accepted` | `windowID`, `requested`, `actual` | une application a imposé sa taille, puis l'a acceptée |
| `layout_external_change_reverted` | `windowID`, `observed`, `target` | changement hors geste et hors écho, ramené une fois à l'arbre |
| `layout_manual_gesture` | `windowID`, `edge`, `ratio` | un geste à la souris a modifié un ratio de l'arbre |
| `space_transition_guard` | `displayID`, `reason`, `closedBy` (`userSpace`, `spaceDidChange`, `timeout`), `heldMs` |
| `space_did_change` | `displayID` si connu | réception de `NSWorkspace.activeSpaceDidChangeNotification` (mesure du moment d'envoi) | à la fermeture de la garde de transition de bureau |
| `state_migrated` | `stages`, `backup` | migration `mutableBsp` vers l'arbre, une seule fois |

Les types retirés avec la suppression de `mutableBsp` (`mutable_bsp_geometry_adopted`, `mutable_bsp_order_repaired`, `mutable_bsp_resize_propagated`) restent lisibles dans les anciens journaux. Ils ne sont plus émis. Ils restent dans `AutomationEventCatalog` avec la mention « obsolète », pour que `roadie events subscribe --type` ne casse pas.

## `live_tick` : détails ajoutés (T221)

| Clé | Sens |
|---|---|
| `requestedDelayMs` | regroupement demandé (15 ou 30 ms) |
| `dueLagMs` | retard entre l'échéance et l'exécution sur le thread principal |
| `heldByGestureMs` | temps pendant lequel la demande a attendu le relâchement de la souris |
