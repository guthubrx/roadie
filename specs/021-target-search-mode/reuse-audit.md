# Audit de reutilisation de l'existant — 021-target-search-mode

## Decision

Statut: PASS
Date: 2026-10-13
Feature dir: /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/021-target-search-mode/specs/021-target-search-mode

Conclusion courte: le mode recherche réutilise la session à tap clavier, les fenêtres d'étiquettes, la normalisation de texte, les cibles et l'activation existantes. Deux fichiers nouveaux, justifiés : un modèle pur de recherche (aucun équivalent ; plusieurs usages : filtrage, navigation, validation) et l'enregistrement d'un raccourci global (aucun équivalent dans Roadie). La normalisation des noms de touches de la grille est réutilisée au lieu d'un nouvel analyseur.

## Synthese

| Metrique | Valeur |
|---|---:|
| Items extraits du plan | 9 |
| Items audites | 9 |
| Reutilisations deja prevues | 7 |
| Existants potentiellement pertinents | 1 |
| Duplications evidentes | 0 |
| Regles/memoires applicables | 3 |
| Specs existantes applicables | 3 |

## Reutilisations correctement identifiees

| Item du plan | Existant reutilise | Preuve | Commentaire |
|---|---|---|---|
| Session clavier | `KeyEventTapSession`, `installEventTap` | `Sources/RoadieDaemon/TargetOverlayPresenter.swift:153-208` | nouvelle session conforme au même protocole |
| Affichage des étiquettes | `TargetOverlayWindow`, `TargetOverlayView`, `TargetOverlayBadge` | `TargetOverlayPresenter.swift:793-1042` | état de recherche optionnel ; dessin inchangé sans lui |
| Normalisation du texte | `TargetHintService.normalized` | `Sources/RoadieDaemon/TargetHintService.swift:487` | + suppression des espaces |
| Cibles et labels | `TargetHintService.overlayState` / `list` | `TargetModeRuntimeController.swift:116-146` | même construction que le mode lettres |
| Activation | `TargetHintService.activate`, `AppTargetQueryService.click` | `AppTargetQueryService.swift` (click) | + `command-click` |
| Commande daemon | `TargetModeRuntimeController.handle` | `TargetModeRuntimeController.swift:103` | + `targets.search` |
| Noms de touches | `TargetGridConfig.normalizedKey` | `Sources/RoadieCore/Config.swift:835` | rendu partagé, alias `ctrl` et `hyper` ajoutés |

## Existant potentiellement pertinent non mentionne

| Item du plan | Existant proche | Preuve | Decision attendue |
|---|---|---|---|
| Disposition AZERTY → code physique | script jetable de l'utilisateur (`/tmp/bttroadie/layout.swift`, supprimé) | historique de session | même technique (`UCKeyTranslate`), réécrite dans le daemon ; aucun code Roadie existant |

## Duplications evidentes

| Item propose | Doublon existant | Preuve | Action requise |
|---|---|---|---|
| aucun | - | - | - |

## Memoires et regles applicables

| Source | Regle | Impact sur le plan |
|---|---|---|
| `roadie-install-signing` | `make install` (Roadie.app signée) | livraison |
| `t3-delegate-review-runtime` | contre-revue en `runtimeMode: auto` | contre-revue |
| constitution XIX | abstraction ≥ 3 usages | `TargetSearchModel` : filtrage, navigation, validation, propriétés |

## Specs livrees applicables

| Spec | Pattern deja etabli | Impact |
|---|---|---|
| 009 | cibles, labels, picker, overlay | base du mode recherche |
| 018 / 020 | cibles web, feuilles focalisables | texte des enfants rattaché aux feuilles |

## Journal de recherche

| Requete | Portee | Resultat |
|---|---|---|
| `rg -n "RegisterEventHotKey\|hotkey\|Hotkey"` | `Sources/` | aucun enregistrement de raccourci global |
| `rg -n "UCKeyTranslate\|TISCopyCurrent\|Carbon"` | `Sources/` | aucun |
| `rg -n "normalizedName\|normalizedKey"` | `Sources/` | `KeyInput.normalizedName`, `TargetGridConfig.normalizedKey` |
| `rg -n "reloadHandlers\|didReload"` | `Sources/` | aucun abonnement au rechargement |

## Arbitrages

| Sujet | Decision | Justification | Date |
|---|---|---|---|
| `TargetSearchModel` | creer nouveau | logique pure sans équivalent, testable sans écran | 2026-10-13 |
| `TargetSearchHotkey` | creer nouveau | aucun raccourci global dans Roadie | 2026-10-13 |
| `normalizedKey` | reutiliser (rendu interne au module) | évite un 2e analyseur de noms de touches | 2026-10-13 |

## Gate avant tasks

- [x] Aucune duplication evidente non arbitree
- [x] Chaque item extrait du plan a une ligne d'audit
- [x] Les regles projet applicables ont ete lues
- [x] Les specs existantes proches ont ete verifiees
- [x] Le plan.md a ete refactore ou les divergences sont justifiees
