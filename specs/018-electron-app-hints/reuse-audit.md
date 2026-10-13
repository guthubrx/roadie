# Audit de reutilisation de l'existant — 018-electron-app-hints

## Decision

Statut: PASS
Date: 2026-10-12
Feature dir: /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/018-electron-app-hints/specs/018-electron-app-hints

Conclusion courte: le plan étend le service existant `LiveAppTargetProvider` et le rapport `AppTargetQueryReport`. Aucun fichier, service, clé de configuration ou dépendance n'est créé. Le seul type nouveau, `AppTargetScanStats`, est une valeur portée par le rapport existant ; aucun équivalent n'existe.

## Synthese

| Metrique | Valeur |
|---|---:|
| Items extraits du plan | 6 |
| Items audites | 6 |
| Reutilisations deja prevues | 5 |
| Existants potentiellement pertinents | 2 |
| Duplications evidentes | 0 |
| Regles/memoires applicables | 4 |
| Specs existantes applicables | 2 |

## Reutilisations correctement identifiees

| Item du plan | Existant reutilise | Preuve | Commentaire |
|---|---|---|---|
| Parcours AX | `LiveAppTargetProvider.candidates` | `Sources/RoadieDaemon/AppTargetQueryService.swift:83` | étendu, pas dupliqué |
| Levier d'activation | `axBoostEnabled`, `additionalBoostBundleIDs` | `Sources/RoadieCore/Config.swift:616-618` ; calcul `effectiveBoost` `AppTargetQueryService.swift:93` | aucune nouvelle clé (FR-008) |
| Rapport du parcours | `AppTargetQueryReport` | `AppTargetQueryService.swift:5` | champ optionnel `scan` |
| Journalisation | `EventLog` dans `TargetHintService.list` | `Sources/RoadieDaemon/TargetHintService.swift:279` | même journal, événement `targets.app_scan` |
| Lecture du cadre | `copyFrame` | `AppTargetQueryService.swift:245` | sert aussi au cadre de la fenêtre |

## Existant potentiellement pertinent non mentionne

| Item du plan | Existant proche | Preuve | Decision attendue |
|---|---|---|---|
| Filtre visible | filtre de l'overlay sur l'écran | `Sources/RoadieDaemon/TargetOverlayPresenter.swift:878` | ne recouvre pas le besoin : il teste l'écran, pas la fenêtre, et n'agit qu'à l'affichage, après la limite `max_targets`. Filtre fenêtre conservé |
| Délai AX court | `AXMessaging.application(pid)` | `Sources/RoadieAX/SystemSnapshotProvider.swift:253` | `internal` à RoadieAX. Hors périmètre ; noté comme piste si la mesure montre des appels lents |

## Duplications evidentes

| Item propose | Doublon existant | Preuve | Action requise |
|---|---|---|---|
| aucun | - | - | - |

## Memoires et regles applicables

| Source | Regle | Impact sur le plan |
|---|---|---|
| mémoire `roadie-install-signing` | installer Roadie.app signée `roadied-cert`, sinon l'Accessibilité saute | livraison via `make install` uniquement |
| mémoire `commit-regularly` | commits par lot, fichiers nommés, jamais `commit -a` | Phase 8 |
| constitution XIX | pas d'abstraction pour moins de 3 usages | politique de relance en fonction statique, pas de protocole d'IO AX |
| constitution XXII | mesurer avant d'optimiser | lecture groupée des attributs hors périmètre |

## Specs livrees applicables

| Spec | Pattern deja etabli | Impact |
|---|---|---|
| 009-roadie-target-mode | découverte AX isolée du layout, bornée par profondeur, nombre, temps | FR-007 conservé |
| 017-reactive-tiling | neutralisation d'`AXEnhancedUserInterface` à l'écriture des cadres | attribut différent (`AXManualAccessibility`) : pas d'interaction |

## Journal de recherche

| Requete | Portee | Resultat |
|---|---|---|
| `rg -n "AXManualAccessibility\|Electron Framework\|isElectron"` | `Sources/` | aucun résultat |
| `rg -n "ScanStats\|scanStats\|offscreen"` | `Sources/` | aucun résultat |
| `rg -n "intersects\("` | `Sources/` | overlay (écran), snapshot (écrans) : pas de filtre fenêtre |
| `rg -n "LiveAppTargetProvider\|AppTargetQueryService("` | `Sources/` | un seul fournisseur réel, un seul point d'appel (`TargetHintService`) |
| `rg -n "enum AXMessaging"` | `Sources/RoadieAX` | interne au module |

## Arbitrages

| Sujet | Decision | Justification | Date |
|---|---|---|---|
| `AppTargetScanStats` | creer nouveau | aucun type de statistiques de parcours AX n'existe ; valeur simple portée par le rapport | 2026-10-12 |

## Gate avant tasks

- [x] Aucune duplication evidente non arbitree
- [x] Chaque item extrait du plan a une ligne d'audit
- [x] Les regles projet applicables ont ete lues
- [x] Les specs existantes proches ont ete verifiees
- [x] Le plan.md a ete refactore ou les divergences sont justifiees
