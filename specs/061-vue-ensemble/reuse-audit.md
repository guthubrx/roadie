# Audit de reutilisation de l'existant - 061

## Decision
Statut: PASS
Date: 2026-10-24
Feature dir: specs/061-vue-ensemble
Conclusion : pas de nouvelle acquisition, activation, persistance ou transport. Le panneau et sa projection géométrique portent un usage distinct du cycle du sélecteur.

## Synthese
| Metrique | Valeur |
|---|---:|
| Items extraits du plan | 8 |
| Items audites | 8 |
| Reutilisations deja prevues | 5 |
| Existants potentiellement pertinents | 3 |
| Duplications evidentes | 0 |
| Regles/memoires applicables | 3 |
| Specs existantes applicables | 4 |

## Reutilisations correctement identifiees
| Item du plan | Existant reutilise | Preuve | Commentaire |
|---|---|---|---|
| Inventaire et activation | WindowSwitcherService | Sources/RoadieDaemon/WindowSwitcherService.swift:30,57 | Étendre résultat par snapshot déjà acquis |
| Images | RailThumbnailStore.shared | Sources/RoadieDaemon/RailThumbnailStore.swift:62,92 | Rétention owner overview, pas de capture au survol |
| Raccourci facultatif | TargetSearchHotkey | Sources/RoadieDaemon/TargetSearchHotkey.swift:10 | Signature et source de réglage injectables, défauts existants conservés |
| Réglages | SettingsService et recorder | Sources/RoadieDaemon/SettingsView.swift:310 | Catalogue scalaire et saisie clavier existants |
| CLI | notification distribuée et router | Sources/RoadieDaemon/WindowSwitcherRuntimeBridge.swift:7 | Même transport, commande distincte |

## Existant potentiellement pertinent non mentionne
| Item du plan | Existant proche | Preuve | Decision attendue |
|---|---|---|---|
| Géométrie globale | WindowSwitcherGroupedGeometry | Sources/RoadieDaemon/WindowSwitcherGrouping.swift:218 | Créer : ne représente ni régions écrans ni loupe de bureau |
| Carte de fenêtre | WindowSwitcherCardView | Sources/RoadieDaemon/WindowSwitcherPanel.swift:153 | Réutiliser si image entière, sinon dessin contenu dans panneau métier |
| Configuration | WindowSwitcherConfig | Sources/RoadieCore/WindowSwitcherConfig.swift:5 | Créer OverviewConfig : état et cycle indépendants |

## Duplications evidentes
Aucune duplication non arbitrée.

## Memoires et regles applicables
| Source | Regle | Impact sur le plan |
|---|---|---|
| AGENTS.md | revue et preuves visibles | Parcours natif, limites explicites |
| .specify/memory/constitution.md | frugalité et propriété | Pas de dépendance ni transport nouveau |
| .specify/memory/standards.md | refs tests | Tests déterministes avant preuve native |

## Specs livrees applicables
| Spec | Pattern deja etabli | Impact |
|---|---|---|
| 053 | destinations stables | Identités stables |
| 056 | activation et inventaire | Réutilisation intégrale |
| 057/058 | recorder et formulaires | Extension catalogue seulement |
| 060 | présentations et images | Reprise des cartes et vérification densité |

## Journal de recherche
| Requete | Portee | Resultat |
|---|---|---|
| rg Overview/archipelago/magnification | Sources Tests | Aucun aperçu global équivalent ; overview du switcher reste une présentation |
| rg load/activate | WindowSwitcherService | Acquisition et transaction réutilisables |
| rg requestCaptures/prune | RailThumbnailStore | Propriétaire distinct possible |
| rg TargetSearchHotkey / signature | RoadieDaemon | Injection nécessaire pour éviter collision |
| rg Settings / groups | RoadieDaemon | SettingsOrganization partition existante |

## Arbitrages
| Sujet | Decision | Justification | Date |
|---|---|---|---|
| Modèle et géométrie | créer OverviewModel | Le plan 060 n’a pas de régions écrans ni loupe ; nouvel usage métier, pas framework | 2026-10-24 |
| Panneau et contrôleur | créer | Consultation persistante globale, ne modifie pas la machine de cycle Cmd+Tab | 2026-10-24 |
| Configuration | créer | Défauts et état indépendants ; service d’écriture partagé | 2026-10-24 |
| Commandes | étendre routeur, pont propre | Même notification système, aucune nouvelle couche réseau | 2026-10-24 |

## Gate avant tasks
- [x] Aucune duplication evidente non arbitree
- [x] Chaque item extrait du plan a une ligne d'audit
- [x] Les regles projet applicables ont ete lues
- [x] Les specs existantes proches ont ete verifiees
- [x] Le plan.md a ete refactore ou les divergences sont justifiees

## Décision de rendu pendant implémentation
CREER un canevas métier groupé dans OverviewPanel plutôt que 64 WindowSwitcherCardView : ces cartes recréent leurs sous-vues et leur géométrie n’a pas de régions imbriquées ni de loupe. Le canevas garde les images en mémoire et redessine seulement ; il utilise les mêmes rectangles pour le dessin, le clavier et les clics. Aucun nouveau cache ni framework de composants. La conversion WindowSwitcherEntry -> PersistentStageMember reprend celle du contrôleur du sélecteur.

Récepteur CLI : REUTILISER ComponentLockFile (Sources/RoadieDaemon/ComponentLockFile.swift:33,170). Un verrou overview tenu pendant le cycle de vie rend la disponibilité explicite, y compris face à un ancien démon. Aucun fichier de statut ou accusé réseau ajouté.

Correction de complexité : réutiliser Dictionary/Set locaux dans OverviewModel, sans nouvelle classe de cache ni invalidation. Identités et ordre persistés préservés.

Retour de densité : réutiliser le même canevas, cache et hit-test pour l’aperçu flottant de fenêtre. Aucun second panneau ou timer. Le tick existant réserve d’abord au plus une capture haute définition à la fenêtre consultée, dans le même verrou de lot partagé. Les autres demandes restent bornées à quatre et le survol ne capture pas.
