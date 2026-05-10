# Documentation Roadie

Documentation en francais pour utiliser Roadie au quotidien, le configurer et l'integrer a un ecosysteme de scripts.

## Guides

- [Vue d'ensemble des fonctionnalites](features.md)
- [Commandes CLI](cli.md)
- [Configuration et rules](configuration-rules.md)
- [Evenements et Query API](events-query.md)
- [Cas d'usage](use-cases.md)

## Positionnement

Roadie est un window manager macOS en Swift qui combine :

- tiling automatique `bsp`, `mutableBsp`, `masterStack` et `float`;
- stages nommees et masquables, proches d'un workflow Stage Manager;
- desktops virtuels Roadie sans controle des Spaces macOS natifs;
- commandes CLI pour BetterTouchTool, Karabiner, scripts shell ou launchers;
- surface d'automatisation : events, rules, groups et query API.

Roadie garde SIP actif et n'utilise pas d'OSAX/SkyLight pour piloter les Spaces natifs.
