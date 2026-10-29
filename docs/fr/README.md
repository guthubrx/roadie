# Documentation Roadie

Guides français pour les sources actuelles de `main`. Le [README principal](../../README.fr.md) explique l’installation, les permissions, les commandes et la confidentialité. [English](../en/README.md).

## Guides

- [Vue d’ensemble des fonctionnalités](features.md)
- [Commandes CLI](cli.md)
- [Vue d’ensemble des bureaux et stages](overview.md)
- [Lanceur et workflows d'Alfred](launcher.md)
- [Sélecteur de fenêtres](window-switcher.md)
- [Configuration et règles](configuration-rules.md)
- [Événements et API de requêtes](events-query.md)
- [Cas d’usage](use-cases.md)
- [Notes de release 0.10.0](../releases/v0.10.0.md)
- [Notes de release 0.9.0](../releases/v0.9.0.md)
- [Notes de release 0.8.0](../releases/v0.8.0.md)
- [Notes de release 0.7.0](../releases/v0.7.0.md)

`roadie toggle maximize` agrandit la fenêtre active en gardant la bande du navrail visible libre. Relance la commande pour restaurer la disposition. Les voisines de la même stage sont cachées pendant la maximisation. Activer une autre fenêtre de cette stage restaure directement la disposition. Changer de stage conserve le zoom sauvegardé. Avec le masquage automatique, le rail masqué laisse toute la zone utile, comme le plein écran Roadie. Quand il revient au survol ou avec `roadie rail pin`, la fenêtre se redimensionne pour lui laisser la place, sans quitter la maximisation. Le menu de titre propose aussi « Fenêtre → Maximiser / restaurer (garder le navrail) » lorsqu'il est activé.

`roadie toggle fullscreen` utilise toute la zone utile et cache le rail, même au survol, sans activer le plein écran macOS. `roadie toggle native-fullscreen` utilise le plein écran macOS. Les deux modes Roadie peuvent se remplacer directement ; répéter le mode actif restaure la disposition précédente.

## Fonctions actuelles

Roadie combine tiling automatique, stages nommés et bureaux virtuels Roadie. Chaque écran garde son bureau courant, son stage actif et sa disposition. SIP reste actif. Roadie ne pilote pas les Spaces natifs de macOS.

- **Tuilage réactif :** `spatialBsp` conserve un arbre binaire persistant. Les événements déclenchent les mises à jour. Les fenêtres temporairement absentes gardent leur place enregistrée. `mutableBsp` et `yabai` restent des alias. Les modes `bsp`, `masterStack` et `float` restent disponibles.
- **Glisser-déposer :** un dépôt au centre échange les fenêtres du même stage. Un dépôt sur un bord insère la fenêtre. L’aperçu entre écrans suit le pointeur, y compris vers un stage tilé vide. Les tailles minimales des applications peuvent limiter les proportions finales.
- **Retour d’écran :** les stages sont mis en attente au débranchement. Le retour conserve les positions visibles utiles. Les anciennes références absentes ne créent plus de cartes visibles dans le rail.
- **Nav rail :** ordre choisi conservé, aperçu de réorganisation et aimantation réglable. Dépôt sur une carte pour la rejoindre, dans un interstice pour créer une stage à cet endroit. Liste défilable et cartes nommées vides identifiables.
- **Lanceur :** applications, fenêtres, documents et onglets ouverts, fichiers, signets, réglages, calcul et web dans une seule barre ; verbes, destinations et phrases (`safari perso gauche`) ; workflows d'Alfred sans Powerpack, thèmes d'Alfred. [Guide](launcher.md).
- **Sélecteur de fenêtres :** retrouve une fenêtre dans son bureau, sa stage et son écran. Recherche, flèches, souris et profils configurables ; raccourcis gérés par Roadie, BetterTouchTool ou un outil externe.
- **Outils de fenêtre :** bordure de focus, focus à la souris, actions de barre de titre, épinglages, signets et groupes persistants.
- **Exécution fiable :** socket local, écritures atomiques, cache partagé, rechargement validé de la configuration, récupération des fenêtres masquées et requêtes de santé.
- **Automatisation :** CLI, règles TOML, requêtes JSON, événements JSONL et diagnostics de performance en lecture seule.
- **Boîte de commandes et réglages :** `/` dans la recherche, complétion par Tab et historique. `/settings` propose la saisie immédiate, les éditeurs de listes, de stages et de règles, ainsi que les polices indépendantes. `/set` permet aussi de lire, modifier ou rétablir une valeur.
- **Navigation et outils visuels :** cibles clavier, recherche dans les fenêtres visibles, contrôles exposés par les applications, grilles écran/fenêtre et macros courtes.
- **Exécution modulaire :** processus séparés pour le tiling, le rail, la bordure, le focus, les actions de barre de titre et les cibles. Les profils limités au rôle de compagnon restent à définir.

## Mettre à jour et contrôler

Depuis le dossier des sources :

```bash
make install
make restart
roadie query health
```

Si une session de développement tmux tourne, lance d’abord `make stop`. L’installation conserve le certificat existant quand c’est possible. Si le certificat requis manque, elle s’arrête avant de remplacer l’application.

Dans `spatialBsp`, utilise `warp` à la place de `layout insert` ou `layout join-with`. Utilise `resize` à la place de `layout width`. `layout flatten` équilibre l’arbre enregistré.

## Confidentialité

L’application fonctionne localement. Les sources actuelles ne contiennent aucun service de télémétrie ou d’envoi distant. L’état, les logs, les macros, les exports et les captures peuvent toutefois contenir des titres de fenêtres ou d’autres données privées. Relis et anonymise ces éléments avant de les partager. Voir [Confidentialité](../../README.fr.md#confidentialité).
