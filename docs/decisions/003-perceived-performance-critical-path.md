# ADR-003 : Chemin critique utilisateur et observabilite performance

## Statut

Accepte.

## Contexte

Les regressions recentes de stage, desktop et AltTab venaient d'un melange entre action utilisateur, lecture d'etat, correction periodique et surfaces secondaires. Quand une lecture peut suivre le focus externe ou persister de l'etat, le diagnostic lui-meme peut modifier Roadie. Quand le rail ou les diagnostics travaillent dans la meme sequence que la bascule, l'utilisateur ressent une latence qui ne vient pas de l'action principale.

## Decision

Roadie separe explicitement trois chemins :

- chemin critique utilisateur : rendre le contexte cible visible et focalisable;
- chemin d'observabilite : mesurer et exposer les interactions sans modifier l'etat;
- travail secondaire : rail, diagnostics, metriques et corrections periodiques.

Les queries et diagnostics doivent rester read-only (`followExternalFocus: false`, `persistState: false`). Les commandes explicites stage/desktop/AltTab enregistrent une interaction de performance et doivent privilegier un contexte cible direct avant de deleguer au tick global. Le timer `LayoutMaintainer` reste un filet de securite, pas la source principale de reactivite.

L'historique performance est local, borne aux 100 dernieres interactions, et stocke dans `~/.local/state/roadies/performance.json`. La tolerance initiale pour eviter un `setFrame` equivalent est de 2 points macOS.

## Consequences

- Les lenteurs deviennent comparables via `roadie performance summary`, `roadie performance recent` et `roadie query performance`.
- Les scripts peuvent surveiller les evenements `performance.interaction_completed` et `performance.threshold_breached`.
- Les surfaces secondaires peuvent etre rafraichies apres l'action principale si cela preserve la fluidite.
- Toute future optimisation doit prouver qu'elle ne reintroduit pas de lecture mutatrice dans les chemins query/diagnostic.

## Hors perimetre

- APIs privees macOS, OSAX, SkyLight ou controle natif des Spaces.
- Animations systeme de fenetres.
- Plugin runtime ou refonte Control Center.
