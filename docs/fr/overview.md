# Vue d’ensemble des bureaux et stages

La vue d’ensemble montre votre organisation Roadie : écrans, bureaux, stages et fenêtres. Elle complète le sélecteur Cmd+Tab. Elle couvre tout l’écran, y compris la barre de menus et le Dock, comme un aperçu global. Elle ne crée pas de Space macOS.

Ouvrez-la avec `roadie overview show`. Un geste BetterTouchTool, par exemple quatre doigts vers le haut, peut appeler `roadie overview toggle`. Le second geste ferme la vue. `roadie overview hide` ferme aussi la vue ; `roadie overview status` affiche les réglages et la disponibilité du démon, sans garantir que la vue soit visible.

Dans **Réglages Roadie > Vue d’ensemble**, choisissez :

- **Archipel**, par défaut : écrans en colonnes, bureaux empilés. Chaque écran reçoit la largeur dont il a besoin. Les traits obliques séparent les écrans.
- **Baies** : écrans en bandes horizontales, bureaux côte à côte.
- **Loupe au survol**, activée par défaut : les cartes du bureau sous la souris grandissent après une courte stabilisation. Le survol consulte ; il ne change pas le bureau actif.
- **Grossissement**, de 100 à 250 %, défaut 150 % : taille des cartes du bureau survolé par rapport aux autres. Les autres bureaux se resserrent si la place manque. Les vraies fenêtres gardent leur taille.
- **Flou du fond d’écran**, de 0 à 100 %, défaut 20 % : un curseur et un aperçu de votre fond d’écran montrent le résultat en direct.
- **Couleur** et **épaisseur** (1 à 8 points, défaut 2) du contour de sélection.
- **Raccourci interne**, facultatif : utilisez le bouton d’enregistrement pour saisir la combinaison au clavier. Vide, Roadie ne réserve aucune touche. BetterTouchTool, Karabiner ou un autre outil peuvent appeler la CLI.

La composition est centrée en hauteur. La vue n’affiche aucun contrôle : ces réglages se changent dans les paramètres et s’appliquent à la vue ouverte. Le fond reprend le fond d’écran de l’écran, flouté, et masque les icônes du bureau. Sans image lisible, Roadie floute ce qui se trouve sous la vue. Les bureaux gardent leur ordre. La loupe ne change pas de bureau quand la souris reste immobile après un agrandissement.

Chaque bureau est une grille de cartes de même taille, au format 16:10, dans l’ordre de ses stages. Le nom du bureau est une puce ; un point vert indique le bureau actif, une puce bleue le bureau agrandi par la loupe. Sous chaque carte, l’icône et le titre de la fenêtre sont suivis d’une puce avec le nom de sa stage. Un contour marque la fenêtre sélectionnée : au départ la fenêtre au premier plan, puis celle choisie aux flèches ; c’est elle qu’Entrée ouvre. Les puces de sa stage passent en bleu. Le survol de la souris ne déplace pas la sélection : il agrandit avec la loupe et ajoute un fin liseré clair sur la carte qu’un clic ouvrirait. Les flèches et Tab changent la sélection ; Entrée ou un clic ouvrent la fenêtre dans son bureau et sa stage d’origine. Échap ferme immédiatement la vue, quel que soit le contrôle utilisé. Un clic sur un autre écran la ferme aussi.

Pour réordonner les bureaux d’un écran, faites glisser la puce d’un bureau vers l’espace où vous voulez l’insérer : au-dessus du premier, entre deux bureaux ou après le dernier, sur cet écran ou sur un autre. Pendant le geste, la vue montre en direct le résultat : les bureaux glissent pour faire de la place et le bureau déplacé apparaît en fantôme translucide à sa future place, déjà renuméroté. Les deux espaces qui touchent le bureau déplacé ne changent rien. Au relâchement, les bureaux sont renumérotés comme dans Mission Control : le bureau déplacé prend le numéro de sa nouvelle place et ceux d’entre les deux glissent d’un cran. Ses stages, fenêtres, nom, épinglages et sa place dans l’historique le suivent. Aucune fenêtre ne bouge à l’écran. Les raccourcis restent liés aux numéros : après avoir posé « Bureau 2 » en tête, `roadie desktop focus 1` ouvre ce bureau. Une règle `assign_desktop` vise aussi un numéro, donc la nouvelle place. La même opération existe en ligne de commande : `roadie desktop move 2 1`. Posé sur un autre écran, le bureau y devient un bureau à part entière, inséré à cette place ; les bureaux des deux écrans sont renumérotés. S’il était affiché, l’écran d’origine passe d’abord à un autre bureau. Ses fenêtres rejoignent l’autre écran, cachées jusqu’à ce que vous affichiez ce bureau.

Pour déplacer une stage, faites glisser la puce de stage d’une de ses cartes. Les stages glissent pour lui faire de la place entre deux groupes de cartes, dans le même bureau, dans un autre bureau ou sur un autre écran, et ses cartes apparaissent en fantôme à leur future place. Au relâchement, la stage s’insère à cette place, avec ses fenêtres et son nom. Lâchée sous le dernier bureau d’un écran, elle crée un nouveau bureau qui la reçoit. Une stage affichée qui part vers un autre bureau laisse la place à une autre stage de son bureau : le bureau affiché ne change pas. Sur un autre écran, ses fenêtres y passent, cachées jusqu’à ce que la stage y soit affichée.

Pour déplacer une seule fenêtre, faites glisser sa carte sur n’importe quelle carte d’une autre stage, sur cet écran ou sur un autre. Sa carte rejoint en fantôme la stage visée ; au relâchement, la fenêtre y est déplacée. Lâchée dans la zone vide d’un bureau, elle crée une nouvelle stage dans ce bureau ; sous le dernier bureau d’un écran, elle crée un nouveau bureau et sa stage. Un fantôme « Nouvelle stage » ou « Nouveau bureau » montre ce qui va apparaître. Un simple clic ouvre toujours la fenêtre. Une fenêtre réduite ou placée sur un autre Space ne se déplace pas ainsi.

Un nom de stage est unique dans tout Roadie, tous écrans et bureaux confondus. Un renommage vers un nom déjà porté par une autre stage est refusé. `roadie state heal` corrige les doublons hérités : la copie qui a le plus de fenêtres garde le nom, les autres copies occupées deviennent « Nom 2 », « Nom 3 », et les copies vides redeviennent anonymes. Aucune fenêtre ne change de stage. Un workspace de la configuration ne nomme qu’une seule stage.

Les bureaux occupés, nommés ou actifs sont représentés. Les stages vides ne sont pas affichées. Les bureaux inutilisés ne sont pas ajoutés uniquement parce que leur numéro est autorisé dans la configuration. En forte densité, la vue défile pour garder des cibles utilisables. Une capture remplit sa carte, recadrée par le haut ; elle est prise à la définition de la carte et ne change plus pendant la consultation. Quand une capture manque, l’icône de l’application sert de repère.

```toml
[overview]
enabled = true
presentation = "archipelago" # ou "bays"
loupe = true
magnification = 150
background_blur = 20 # 0 = net, 100 = très flou
selection_color = "#66C2F7"
selection_width = 2 # points, de 1 à 8
hotkey = "" # combinaison facultative ; préférer l’enregistrement au clavier
```

Les images utilisent le cache partagé du rail et du sélecteur. Le mouvement de souris ne déclenche ni relevé des fenêtres, ni lecture disque, ni capture. Les captures se font par lots bornés pendant l’ouverture. Cela décrit le mécanisme ; aucun gain de performance chiffré n’est garanti.

Les cartes restent compactes : les stages utilisent plusieurs rangées et colonnes selon leur contenu. Une stage avec une seule fenêtre ne prend pas toute la hauteur. La fenêtre survolée gagne de la place dans sa stage. La loupe reste dans la composition, sans panneau superposé. Le clic ouvre la fenêtre.

Si Mission Control apparaît aussi après le balayage, désactivez le geste macOS correspondant dans Réglages Système > Trackpad > Gestes supplémentaires > Mission Control. Conservez le geste Roadie dans BetterTouchTool.
