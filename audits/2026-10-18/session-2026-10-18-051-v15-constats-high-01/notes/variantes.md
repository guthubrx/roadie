# Recherche de variantes - session 051 readonly

Racine : `/private/tmp/roadie-audit-051`.

## Relevé complet déclenché par un clic avant de savoir s'il sert (F1, F2)

Motifs : `grep -rn "addGlobalMonitorForEvents\|addLocalMonitorForEvents\|CGEvent.tapCreate" Sources`,
puis lecture de chaque gestionnaire et recherche de `snapshot()`, `sharedSnapshot()`, `readerSnapshot()`,
`makeContext()` sur son chemin.

| Moniteur | Événements | Relevé sur le chemin | Verdict |
|---|---|---|---|
| RailController.swift:231, 245 | clic gauche/droit | pré-filtre 051 puis `makeContext` -> `sharedSnapshot` | sain (C-05) |
| FocusFollowsMouseController.swift:140, 143 (UserInputActivity) | clic gauche | cible de geste `main.swift:429` -> `sharedSnapshot` | F1 |
| TitlebarContextMenuController.swift:175, 184 | clic droit | `snapshot()` l. 212 si option activée | F2 (option expérimentale) |
| SplitResizeController.swift:141, 156 | relâchement, glisser, touche | pendant un glisser de séparation seulement | hors repos, non retenu |
| TargetMacroService.swift:243, TargetOverlayPresenter.swift:315 | tap d'événements de la macro cible | actif pendant un enregistrement seulement | hors périmètre, non retenu |

## Mesure absente (F3)
`ls specs/*/mesures` : seule la 048 publie des mesures dans ce commit. Aucune autre spec 051.

## Réutilisation sans revalidation (A-02)
`grep -rn "AXWindowIndexCache.shared" Sources` : invalidations dans l'observateur (l. 160, 273) et
remplacement en fin de relevé (l. 822). Aucun autre lecteur de l'index. Pas de défaut retenu.
