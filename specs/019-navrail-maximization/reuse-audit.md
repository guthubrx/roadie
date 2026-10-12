# Audit de réutilisation de l'existant — maximisation réservée

## Decision

Statut: PASS
Date: 2026-10-12
Feature dir: specs/019-navrail-maximization

Le plan étend les services actuels. Aucun doublon évident ni arbitrage utilisateur requis. Le calcul de cadre partagé porte une règle métier absente du plein écran actuel.

## Synthese

| Métrique | Valeur |
|---|---:|
| Items extraits du plan | 13 |
| Items audités | 13 |
| Réutilisations déjà prévues | 9 |
| Existants potentiellement pertinents | 1 |
| Duplications évidentes | 0 |
| Règles/mémoires applicables | 5 |
| Specs existantes applicables | 3 |

## Reutilisations correctement identifiees

| Item du plan | Existant réutilisé | Preuve | Commentaire |
|---|---|---|---|
| Zoom réservé | WindowCommands.toggleFullscreen | Sources/RoadieDaemon/WindowCommands.swift:484 | Étendre la mécanique, garder un seul chemin. |
| Persistance du mode et restauration | LayoutIntent | Sources/RoadieDaemon/LayoutIntentStore.swift:4 | Deux champs optionnels, aucun store créé. |
| Cadre maximisé | outerGaps / RailSettings.width / RailPanel | Sources/RoadieDaemon/DaemonSnapshot.swift:1913 | Créer maximizedFrame : règle nouvelle, quatre usages réels ; marge entière du panneau. |
| Plans actualisés | validIntent / treeApplyPlan | Sources/RoadieDaemon/DaemonSnapshot.swift:1514 | Étendre la projection du zoom réservé. |
| Maintien et focus | fullscreenEntries / zoomReanchorCommands / focusRestoreCommand | Sources/RoadieDaemon/LayoutMaintainer.swift:1666 | Réutiliser protection du zoom, adapter sa cible. |
| Retour de stage | targetFullscreenMemberID | Sources/RoadieDaemon/StageCommands.swift:1231 | Recalculer le cadre réservé dans restauration. |
| Commande et aide | CLICommandRouter | Sources/RoadieDaemon/CLICommandRouter.swift:634 | Ajouter maximize au routeur existant. |
| Menu ciblé | WindowContextActionKind / addWindowSubmenu / execute | Sources/RoadieDaemon/TitlebarContextMenuController.swift:368 | Étendre le sous-menu existant. |
| Tests | PowerUserProvider / PowerUserWriter / suites existantes | Tests/RoadieDaemonTests/PowerUserFocusCommandTests.swift:8 | Réutiliser fixtures ; aucun framework nouveau. |
| Documentation | README et guides CLI EN/FR | docs/fr/cli.md:1 | Mise à jour des documents existants. |

| Restauration de zoom commune | Sortie toggleFullscreen et focusedHiddenRestore | Sources/RoadieDaemon/DaemonSnapshot.swift:1310 | Créer restoreZoomLayoutIntent : règle métier partagée, surtout float et scope local. |
| Recalage réservé avec mémoire de refus | fullscreenSizedReanchorTarget et mémoires de refus | Sources/RoadieDaemon/LayoutMaintainer.swift:1690 | Créer reservedZoomCommand pour focus et recalage : target réservée et refus partagés. |

| Sortie après fermeture de la cible | activeScopes et restoreZoomLayoutIntent | Sources/RoadieDaemon/LayoutMaintainer.swift:1564 | Détection sur snapshot existant, aucune nouvelle observation ni boucle. |

## Existant potentiellement pertinent non mentionne

Aucun item omis. La largeur 224 des cartes a été examinée : elle concerne leur contenu, pas une seconde fenêtre. Le panneau définit sa surface par config.railWidth.

## Duplications evidentes

Aucune.

## Memoires et regles applicables

| Source | Règle | Impact |
|---|---|---|
| AGENTS.md | Français, auteur utilisateur, préservation des travaux étrangers | Artefacts français, commit ciblé |
| ~/.speckit/constitution.md | III, XVI | Cycle complet, worktree 019 |
| ~/.speckit/constitution.md | XIX/XX | Une mécanique commune, aucune dépendance |
| .specify/memory/standards.md | Baselines et refs | Référence tests consultée |
| ~/.speckit/ref/adversarial-review.md | Revue du code non trivial | Audit indépendant après convergence |

## Specs livrees applicables

| Spec | Pattern déjà établi | Impact |
|---|---|---|
| 002 | CLI et menus de fenêtres | Extension |
| 016 | Zoom logique, cadres réellement appliqués | Extension |
| 017 | Arbre qui fait foi | Restauration par l'arbre, sans modifier ses ratios |

## Journal de recherche

| Requête | Portée | Résultat |
|---|---|---|
| rg toggleFullscreen/zoomedWindowID | Sources, Tests | Bascule et protection existantes |
| rg outerGaps/railWidth/visibleWidths | Sources | Réservation full-width nécessaire malgré auto-hide |
| rg maximize/fullscreen/menu | Sources, docs | Pas de commande réservée ; route/menu extensibles |
| rg restorePlacements/zoomReservesRail | Sources | Aucun équivalent : champs optionnels justifiés |

## Arbitrages

| Sujet | Décision | Justification | Date |
|---|---|---|---|
| Calcul maximizedFrame | Créer méthode métier dans SnapshotService | outerGaps seul peut réduire/supprimer left ; quatre usages concrets | 2026-10-12 |
| Type de zoom | Ajouter Bool optionnel à LayoutIntent | Deux modes seulement ; pas d'enum ni service nouveau | 2026-10-12 |
| Sauvegarde | Ajouter dictionnaire optionnel | Évite intent récursif et pile de zooms | 2026-10-12 |

Les méthodes privées ajoutées ont été recherchées par nom et responsabilité. Pas de wrapper neutre : la restauration choisit le moteur et sort du zoom ; le recalage applique une règle de cadre réservé et les mémoires de refus. La capture des nouvelles voisines réutilise le masque et LayoutIntentStore.

## Gate avant tasks

- [x] Aucune duplication évidente non arbitrée
- [x] Chaque item extrait du plan a une ligne d'audit
- [x] Les règles projet applicables ont été lues
- [x] Les specs existantes proches ont été vérifiées
- [x] Le plan.md a été refactoré ou les divergences sont justifiées
