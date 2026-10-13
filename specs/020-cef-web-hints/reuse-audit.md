# Audit de reutilisation de l'existant — 020-cef-web-hints

## Decision

Statut: PASS
Date: 2026-10-13
Feature dir: /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/020-cef-web-hints/specs/020-cef-web-hints

Conclusion courte: Roadie étend le parcours et les statistiques de la spec 018, sans nouveau fichier, service ni clé. Côté Bluejay, une ligne sur une branche `pr/*`, intégrée par le mécanisme existant `build-bluejay-with-prs.sh`.

## Synthese

| Metrique | Valeur |
|---|---:|
| Items extraits du plan | 5 |
| Items audites | 5 |
| Reutilisations deja prevues | 4 |
| Existants potentiellement pertinents | 1 |
| Duplications evidentes | 0 |
| Regles/memoires applicables | 4 |
| Specs existantes applicables | 2 |

## Reutilisations correctement identifiees

| Item du plan | Existant reutilise | Preuve | Commentaire |
|---|---|---|---|
| Parcours en préordre, chemins | `LiveAppTargetProvider.scan` | `Sources/RoadieDaemon/AppTargetQueryService.swift:254` | même parcours, un drapeau « zone web » en plus |
| Détection de zone web | `sawWebArea` (018) | `AppTargetQueryService.swift:277` | même test de rôle |
| Statistiques et événement | `AppTargetScanStats`, `targets.app_scan` | `AppTargetQueryService.swift:21`, `TargetHintService.swift:274` | deux champs en plus |
| Filtre visible | `visibleFrame` (018) | `AppTargetQueryService.swift:136` | appliqué aux nouveaux candidats |
| Intégration Bluejay | `build-bluejay-with-prs.sh`, `bluejay-build-prs.conf` | `/Users/moi/11.Repositories/grayjay/AGENTS.md` | branche `pr/*` détectée automatiquement |

## Existant potentiellement pertinent non mentionne

| Item du plan | Existant proche | Preuve | Decision attendue |
|---|---|---|---|
| Lecture « settable » | `AXUIElementIsAttributeSettable` dans RoadieAX | `Sources/RoadieAX/SystemSnapshotProvider.swift:767` | appel système direct, pas de helper partagé à extraire (1 usage par module) |

## Duplications evidentes

| Item propose | Doublon existant | Preuve | Action requise |
|---|---|---|---|
| aucun | - | - | - |

## Memoires et regles applicables

| Source | Regle | Impact sur le plan |
|---|---|---|
| `roadie-install-signing` | installer via `make install` (Roadie.app signée) | livraison Roadie |
| `t3-delegate-review-runtime` | contre-revue en `runtimeMode: auto` | contre-revue |
| `AGENTS.md` Grayjay | build Bluejay par le worktree d'intégration et `build-bluejay-with-prs.sh` | livraison Bluejay |
| constitution XX §6 | pas de données personnelles vers un LLM externe | le relevé jetable n'est pas transmis à la contre-revue |

## Specs livrees applicables

| Spec | Pattern deja etabli | Impact |
|---|---|---|
| 018-electron-app-hints | statistiques, filtre visible, relance | règle ajoutée dans le même parcours |
| 009-roadie-target-mode | découverte AX isolée du layout | inchangé |

## Journal de recherche

| Requete | Portee | Resultat |
|---|---|---|
| `rg -n "AXFocused\|IsAttributeSettable\|AXWebArea\|rejected\|histogram" Sources` | Roadie | aucun tri par focalisabilité, aucun histogramme de rôles |
| `rg -n "cef.Start("` | Grayjay `Program.cs` | lignes 394, 398, 400 ; 394 = Windows et macOS |

## Arbitrages

| Sujet | Decision | Justification | Date |
|---|---|---|---|
| Option CEF limitée à macOS | creer (une condition) | la ligne 394 sert aussi Windows ; le besoin est macOS | 2026-10-13 |

## Gate avant tasks

- [x] Aucune duplication evidente non arbitree
- [x] Chaque item extrait du plan a une ligne d'audit
- [x] Les regles projet applicables ont ete lues
- [x] Les specs existantes proches ont ete verifiees
- [x] Le plan.md a ete refactore ou les divergences sont justifiees
