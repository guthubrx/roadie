# Spec 164 — Layouts avancés : Onglets (`tabbed`) & Ruban défilant (`scrolling`) (Lot 7)

## Objectif

Ajouter deux nouveaux modes de disposition tuilée à Roadie, accessibles globalement (`tiling.default_strategy`), par stage (`roadie mode tabbed|scrolling`, `roadie stage mode ...`), depuis le lanceur et depuis le menu contextuel du NavRail :

1. **Mode Onglets (`tabbed` ; alias `tabs`, `onglets`)**
   - Empile toutes les fenêtres gérées de la stage dans le même rectangle de contenu (`TabbedLayoutStrategy`).
   - Lorsque la stage comporte une seule fenêtre, celle-ci occupe 100 % du conteneur (aucune barre d'onglets affichée, zéro espace perdu).
   - Lorsque la stage comporte au moins deux fenêtres, une bande supérieure de hauteur `tiling.tabbed_bar_height` (défaut `28 pt`, borné `20...44`) est réservée pour une barre d'onglets légère et cliquable (`StageTabBarController`) affichant l'icône d'application, le titre et la mise en surbrillance de l'onglet actif. Un clic sur un onglet focalise immédiatement cette fenêtre.
   - Zéro panneau créé et zéro charge tant qu'aucune stage active n'est en mode `tabbed` avec au moins 2 fenêtres.
   - Navigation clavier : `roadie focus left|up` et `roadie focus right|down` parcourent les onglets de la stage (bouclage propre) ; `roadie move left|right` réordonne l'onglet dans la stage.

2. **Mode Ruban défilant (`scrolling` ; alias `scroll`, `ribbon`, `niri`, `ruban`)**
   - Aligne les fenêtres côte à côte en colonnes de largeur `floor(container.width * tiling.scrolling_column_width)` (`tiling.scrolling_column_width` défaut `0.65`, borné `0.25...1.0`) séparées par `gaps_inner` (`ScrollingLayoutStrategy`).
   - Centre le ruban lorsque la largeur totale tient dans l'écran ; sinon défile horizontalement pour centrer la colonne focalisée (borné aux bords du ruban pour éviter tout vide aux extrémités), tout en gardant un débord minimal cliquable (24 pt) pour les colonnes hors fenêtre afin de respecter les limites macOS et éviter tout faux déclenchement de `HiddenWindowPlacement`.
   - Navigation clavier : `roadie focus left|right` déplace le focus vers la colonne précédente/suivante et recentre immédiatement le ruban ; `roadie move left|right` échange la colonne avec sa voisine ; la largeur des colonnes est pilotée de façon persistante par `tiling.scrolling_column_width`.

## Réglages TOML & Paramètres

- `[tiling].default_strategy` accepte désormais `bsp | spatialBsp | masterStack | tabbed | scrolling | float` (+ alias `tabs`, `onglets`, `scroll`, `ribbon`, `niri`, `ruban`).
- `[tiling].tabbed_bar_height = 28` (`20...44` pt)
- `[tiling].scrolling_column_width = 0.65` (`0.25...1.0`)
