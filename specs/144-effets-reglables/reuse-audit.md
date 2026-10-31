# Audit de reutilisation de l'existant — 144

## Decision
Statut: PASS
Date: 2026-10-31
Feature dir: /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/025-settings-readability/specs/144-effets-reglables

Le plan étend les sessions et writers existants. Deux responsabilités nouvelles sont nécessaires : calcul commun des mouvements et orchestration asynchrone de frames hors geste. Aucun second store ou backend de capture. L’adaptation du résultat différé doit être testée explicitement.

## Synthese
| Metrique | Valeur |
|---|---:|
| Items extraits du plan | 9 |
| Items audites | 9 |
| Reutilisations deja prevues | 6 |
| Existants potentiellement pertinents | 3 |
| Duplications evidentes | 0 |
| Regles/memoires applicables | 5 |
| Specs existantes applicables | 7 |

## Reutilisations correctement identifiees
| Item du plan | Existant reutilise | Preuve | Commentaire |
|---|---|---|---|
| Configuration | EffectsConfig | Sources/RoadieCore/Config.swift:501 | REUTILISER ; étendre, pas second store |
| Paramètres | SettingsCatalog, SettingsOrganization | Sources/RoadieDaemon/SettingsCatalog.swift:199 | REUTILISER ; catégorie Effets et surcharges |
| Session aperçu réel | LiveDropPreview | Sources/RoadieDaemon/LiveDropPreview.swift:9 | REUTILISER ; source admise seulement avec propriété |
| Writer/coalescence | InteractiveFrameDispatcher | Sources/RoadieDaemon/InteractiveFrameDispatcher.swift:32 | REUTILISER ; un dernier lot par PID |
| Geste | WindowDragReorderController / RailController | Sources/RoadieDaemon/DropPreviewController.swift:543 | REUTILISER ; tap comme entrée supplémentaire |
| Résultat différé | ApplyResultItem / SnapshotService.apply | Sources/RoadieDaemon/DaemonSnapshot.swift:1431 | REUTILISER ; pas de writer synchrone menteur |

## Existant potentiellement pertinent non mentionne
| Item du plan | Existant proche | Preuve | Decision attendue |
|---|---|---|---|
| Calcul et horloge communs | cubic local overview / NSAnimationContext rail | Sources/RoadieDaemon/OverviewPanel.swift:474 ; Sources/RoadieDaemon/RailPanel.swift:267 | CREER calcul et ordonnanceur partagés ; remplacer ces duplications, quatre usages réels |
| FrameTransitionRuntime | LiveDropPreview / NativeResizeRuntime | Sources/RoadieDaemon/LiveDropPreview.swift:22 ; Sources/RoadieDaemon/NativeResizeRuntime.swift:1 | CREER adaptateur hors geste, réutiliser dispatcher ; ne pas mélanger persistance du geste et animation |
| Tap souris | KeyEventTapSession | Sources/RoadieDaemon/TargetOverlayPresenter.swift:289 | Étendre propriétaire du geste avec le motif bas niveau ; protocole privé clavier sans admissibilité souris, ne pas le généraliser pour deux taps |

## Duplications evidentes
Aucune proposition de responsabilité 1:1 déjà existante non réutilisée.

## Memoires et regles applicables
| Source | Regle | Impact sur le plan |
|---|---|---|
| AGENTS.md | livraison activée et vérifiée | Git seul insuffisant |
| Constitution XVIII | complexité | O(k) et file bornée |
| Constitution XIX/XX | réutilisation / mainteneur | pas de nouveau backend/capture/dépendance |
| Constitution VII | décision structurante | ADR avant code |
| my-specify-all | gates Analyze/Converge/audit | pas de commit avant gates |

## Specs livrees applicables
| Spec | Pattern deja etabli | Impact |
|---|---|---|
| 142 | permis révocable, writer hors main | réutilisé |
| 143 | original frames, contexte figé, annulation | étendu |
| 061 | overview AppKit | réutilisé |
| 071 | transitions de cartes | remplacées par politique commune |
| 078 | aperçu réversible, maintien borné | pas de renouvellement indéfini |
| 023 | catalogue et TOML | réutilisés |
| 057 | paramètres par usage | page Effets |

## Journal de recherche
| Requete | Portee | Resultat |
|---|---|---|
| rg EffectsConfig / animations | Sources/RoadieCore | borders seul ; fx.animations encore unsupported |
| rg animation / ease / Timer | Sources/RoadieDaemon | rail et overview séparés |
| rg LayoutPreviewHold / InteractiveFrameDispatcher | Sources | lease lanceur et writer existants |
| rg WindowDrag / handleMouse | Sources/RoadieDaemon | moniteurs observateurs, aucune capture source existante |
| rg apply / status | Sources et Tests | contrat synchrone et consumers identifiés |
| manifeste Package.swift | dépendances | aucune nouvelle dépendance nécessaire |

## Arbitrages
| Sujet | Decision | Justification | Date |
|---|---|---|---|
| Session source | reutiliser | même contexte et restauration que voisines | 2026-10-31 |
| Calcul commun | creer nouveau | aucune primitive pure commune ; au moins quatre usages, suppression cubic local | 2026-10-31 |
| Runtime de frames | creer nouveau | les sessions de geste ne peuvent posséder des commandes ordinaires ; réutilisation de leur dispatcher | 2026-10-31 |
| Capture vidéo | ne pas creer | aucun besoin pour un contenu réel placé par AX | 2026-10-31 |

## Gate avant tasks
- [x] Aucune duplication evidente non arbitree
- [x] Chaque item extrait du plan a une ligne d'audit
- [x] Les regles projet applicables ont ete lues
- [x] Les specs existantes proches ont ete verifiees
- [x] Le plan.md a ete refactore ou les divergences sont justifiees

## Recherche pendant implémentation
- Motion.swift / EffectAnimator : recherches par nom et responsabilité sans calcul commun existant ; CREER, quatre consommateurs identifiés. Remplacement des animations locales rail/overview.
- SettingsCatalogEffects : REUTILISER extension du catalogue, motif SettingsCatalogOverview ; pas de nouveau service.
- Tests source réelle : REUTILISER Drag143Fixture/Backend en visibilité interne, pas une copie de fixture.
- WindowTitleDragAccess : recherche AXUIElementCopyElementAtPosition/AXTitleUIElement sans équivalent. CREER accès sémantique ciblé, réutiliser AXApplicationWindows et le contrôle CG ID/PID ; ne pas faire d’AX dans le callback.
- Aperçu local : recherche OverviewBlurPreview et vues des paramètres. REUTILISER SettingsView pour l’emplacement, CREER une petite vue de démonstration utilisant EffectAnimator ; pas de panneau ni d’horloge supplémentaires.

T033 : recherche finishAll/finishAnimations/completeAnimations dans Sources/RoadieDaemon, seul stop() du moteur existe. RÉUTILISER EffectAnimator : ajouter la terminaison aux cibles finales et réutiliser SettingsLiveApplyController.applyChange, qui observe déjà les modifications locales et distribuées. Aucun nouvel observateur, timer, type ou service. L’annulation existante stop() conserve son sens d’abandon sans callbacks.

T034, observation réelle : T3 Code expose son titre vide comme AXGroup sans action, de cadre exactement égal à la fenêtre ; le groupe interactif à droite possède AXShowMenu/AXScrollToVisible et mesure 160×90. RÉUTILISER WindowTitleDragAccess et AXWindowFrameWriter.frame(of:pid:) pour une lecture bornée du cadre ; ajouter la règle pure du conteneur racine sans action. Boutons, onglets, champs et petits groupes restent exclus. Pas de nouveau lecteur AX ni de permission. Firefox expose bien AXWindow dans sa bande de titre ; son cas nécessite le diagnostic de délai en cours.

T034, traces du geste utilisateur : rejet à 33,305 points du haut sur Firefox, parce que la qualification s’arrêtait à 32 alors que le détecteur utilisait 44. Les lectures AX aux hauteurs 26,3/33,3/39/43 renvoient toutes AXWindow. Alignement sur une seule constante de bande de titre ; gardes de boutons/onglets conservées. Un second geste rapide a reçu la décision avant le résultat AX (accepté à 5,9 ms, décision déjà prise). CRÉER une cellule de résultat à verrou dans le contrôleur existant : un producteur AX hors main, lecture du résultat par le tap et validation de l’identité/point/cadre par le gestionnaire de clic. Cette frontière doit être thread-safe et ne pas attendre MainActor. Aucun équivalent trouvé dans Sources/RoadieDaemon, RoadieCore ou RoadieAX ; pas de pool, de nouveau writer ou de polling. Le tap lance la lecture dès mouseDown sur le relevé en mémoire ; le clic traverse toujours. Une première movement déjà passée au natif empêche toute capture tardive.
