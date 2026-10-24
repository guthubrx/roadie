# Sessions SpecKit

| Session | Statut | Branche | Specs | Notes |
|---|---|---|---|---|
| 002 | Implémentée | `002-roadie-ecosystem-upgrade` | `specs/002-roadie-ecosystem-upgrade` | Events, rules, power-user commands, window groups, query API |
| 016 | Implémentée (validation manuelle en attente) | `016-roadie-stabilization` | `specs/016-roadie-stabilization` | Stabilisation : 39 constats de revue (persistance, AX, moteur, CLI socket, rail, exploitation) |
| 017 | Implémentée (validation manuelle en attente) | `017-reactive-tiling` | `specs/017-reactive-tiling` | Tiling réactif façon yabai : arbre qui fait foi, une passe par événement, écho/geste, budget d'écriture |
| 019 | Implémentée | `019-navrail-maximization` | `specs/019-navrail-maximization` | Maximisation réservant le navrail, restauration, CLI/menu, 820 tests verts |

| 024 | Implémentée et publiée en v0.4.0 | `session-024-release-performance` (fusionnée, supprimée) | `specs/024-release-performance` | Trois HIGH corrigés, mesures, revue, 1 354 tests Swift, DMG vérifié |
| 025 | Clôturée, installée et validée | `session-025-settings-readability` (fusionnée, conservée pour la conversation T3) | `specs/025-settings-readability` | Polices indépendantes et immédiates, choix de tuilage lisibles, 1 372 tests Swift et 26 tests des scripts, revue sans défaut bloquant, test utilisateur confirmé |
| 026 | Clôturée, installée et validée | `session-026-command-bar` (fusionnée, supprimée) | `specs/026-command-bar` | Tab complète la sélection, barre fixe et sobre, 1 384 tests Swift, revue sans défaut bloquant, test utilisateur confirmé |
| 027 | Clôturée, installée, validée et publiée en v0.5.0 | `session-027-settings-complete` (fusionnée, supprimée) | `specs/027-settings-complete` | Saisie immédiate, retuilage, douze éditeurs de collections et familles de police Caps+F ; 1 440 tests Swift, 26 tests des scripts, santé OK, test utilisateur confirmé, DMG vérifié |
| 028 | Clôturée, installée et validée | `session-028-search-dismissal` (fusionnée, supprimée) | `specs/028-search-dismissal` | Libellés natifs recherchables, lectures AX inutiles réduites, fermeture au clic extérieur ; 1 458 tests Swift, 26 tests des scripts, revue et essai utilisateur confirmés |

| 030 | Implémentée, installée et redémarrée | `session-030-recuperation-demarrage` | `specs/030-recuperation-demarrage` | Récupération sur passe stable sans notification écran ; 1471 tests isolés, 1527 combinés, santé OK |

| 031 | Implémentée, installée et redémarrée | `session-031-libelles-temporaires` | `specs/031-libelles-temporaires` | Numéro et nom temporaires ; double Alt gauche grille, droite libellés ; 1 540 tests, repères vides temporaires, captures et santé OK |

| 039 | Implémentée, installée et redémarrée | `session-039-anomalies-journee` | `specs/039-anomalies-journee` | Cinq mécanismes corrigés ; 1 603 tests, quatre contrôles santé OK, traces archivées ; revue externe et preuve visuelle indisponibles |

| 029 | Intégrée ; documents récupérés le 18 octobre | `session-029-resize-rail` (fusionnée) | `specs/029-resize-rail` | Code livré dans 037, complété dans 039 ; anciens badges remplacés dans 031–033 ; réserve sur le geste natif conservée |
| 035 | Intégrée ; documents récupérés le 18 octobre | `session-035-audit-global` (fusionnée) | `specs/035-audit-global` | Corrections et tests livrés dans 037 ; coût des observations corrigé par lot ; rapports bruts archivés |

| 042 | Clôturée, intégrée et installée | `session-042-couts-traitement` (fusionnée, supprimée) | `specs/042-couts-traitement` | Six coûts corrigés ; 1 628 tests / 192 suites, santé OK, sans benchmark ; revue initiale traitée, second passage indisponible |
| 043 | Intégrée et installée ; gestes réels non vérifiés | `session-043-redimensionnement-fiable` (fusionnée, supprimée) | `specs/043-redimensionnement-fiable` | Trois P1 ; 1 685 tests / 199 suites et 26 tests de scripts, deuxième revue favorable, santé OK ; bureau inaccessible |
| 044 | Intégrée et installée ; geste réel non vérifié | `session-044-poignees-visibles` (fusionnée, supprimée) | `specs/044-poignees-visibles` | Poignées avec JankyBorders, repère plus lisible, 1 689 tests / 199 suites, comparatif logiciel partiel, présence native et santé OK |
| 045 | Clôturée, intégrée et installée ; essai réel confirmé | `session-045-capture-redimensionnement` (fusionnée, supprimée) | `specs/045-capture-redimensionnement` | Capture native et poignée arbitrées à l'acceptation ; 1 693 tests / 199 suites, revue traitée, taille conservée et santé OK |
| 046 | Clôturée, intégrée et installée | `session-046-placement-ecran-actif` (fusionnée, supprimée) | `specs/046-placement-ecran-actif` | Écran actif par défaut, paramètres et docs alignés, choix explicites conservés ; 1 696 tests / 199 suites, revue traitée, santé OK |
| 047 | Clôturée, intégrée et installée | `session-047-fenetre-flottante` (fusionnée, supprimée) | `specs/047-fenetre-flottante` | `toggle floating` par épinglage de portée stage ; 1 707 tests / 200 suites, aller-retour réel, santé OK |
| 048 | Clôturée, intégrée et installée | `session-048-consommation-repos` (fusionnée, supprimée) | `specs/048-consommation-repos` | CPU au repos 11,45 % → 2,34 % ; ADR 015 ; audit V15 inconclusive (option A) |
| 051 | Clôturée, intégrée et installée | `session-051-constats-high` (fusionnée, supprimée) | `specs/051-constats-high` | 8 constats HIGH corrigés, D-02 laissé ; audit V15 inconclusive (option A) |
| 049 | Clôturée, intégrée et installée | `session-049-reglages-macos` (fusionnée, supprimée) | `specs/049-reglages-macos` | Santé `macos-window-settings` ; ok en réel |
| 050 | Clôturée, intégrée et installée | `session-050-double-clic-titre` (fusionnée, supprimée) | `specs/050-double-clic-titre` | Double-clic désactivé par défaut ; 1 744 tests |
| 052 | Clôturée, intégrée et installée | `session-052-rail-reconnexions` (fusionnée, supprimée) | `specs/052-rail-reconnexions` | Rail défilable, priorité aux stages occupées, parking réutilisé, A-11 et V15 borné ; revue traitée, 1 754 tests, santé OK |
| 053 | Intégrée et installée ; dépôts confirmés, repère vide à confirmer | `session-053-depot-rail` (fusionnée, supprimée) | `specs/053-depot-rail` | Ordre fixe, dépôt haut/interstice/bas, ancre atomique ; 1 760 tests, revue traitée, santé OK ; carte vide toujours identifiable ; rendu réel à confirmer |

| 054 | Clôturée, publiée et installée | `session-054-release-060` (fusionnée, supprimée) | `specs/054-release-060` | 0.6.0 Latest, docs FR/EN, revue traitée ; 1 760 tests Swift + 26 scripts, téléchargement et santé 5/5 vérifiés, nettoyage terminé |
| 055 | Intégrée et installée ; essai proposé | `session-055-fullscreen-sans-rail` (fusionnée, supprimée) | `specs/055-fullscreen-sans-rail` | Plein écran sans rail, Ctrl gauche+Alt gauche+F BTT ; 1 761 tests, revue traitée, santé 5/5 ; preuve réelle à confirmer |
| 062 | Implémentée et installée | `session-062-fenetres-mission-control` | `specs/062-fenetres-mission-control` | Mission Control ne rétrécit plus les fenêtres masquées : pause de la disposition, relevés provisoires, masquage en position seule, écriture sans réponse reprise ; 1 928 tests, santé 5/5 |
| 063 | En cours | `session-062-fenetres-mission-control` (intégration directe) | `specs/063-release-080` | Publication 0.8.0 : vue d'ensemble, sélecteur, Mission Control, CLI |
