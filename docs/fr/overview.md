# Vue d’ensemble des bureaux et stages

La vue d’ensemble montre votre organisation Roadie : écrans, bureaux, stages et fenêtres. Elle complète le sélecteur Cmd+Tab. Elle couvre tout l’écran, y compris la barre de menus et le Dock, comme un aperçu global. Elle ne crée pas de Space macOS.

Ouvrez-la avec `roadie overview show`. Le geste trois doigts vers le haut peut appeler `roadie overview toggle` depuis BetterTouchTool. Le second geste ferme la vue. `roadie overview hide` ferme aussi la vue ; `roadie overview status` affiche les réglages et la disponibilité du démon, sans garantir que la vue soit visible.

Dans **Réglages Roadie > Vue d’ensemble**, choisissez :

- **Archipel**, par défaut : écrans en colonnes, bureaux empilés. Chaque écran reçoit la largeur dont il a besoin. Les traits obliques séparent les écrans.
- **Baies** : écrans en bandes horizontales, bureaux côte à côte.
- **Loupe au survol**, activée par défaut : les cartes du bureau sous la souris grandissent après une courte stabilisation. Le survol consulte ; il ne change pas le bureau actif.
- **Grossissement**, de 100 à 250 %, défaut 150 % : taille des cartes du bureau survolé par rapport aux autres. Les autres bureaux se resserrent si la place manque. Les vraies fenêtres gardent leur taille.
- **Raccourci interne**, facultatif : utilisez le bouton d’enregistrement pour saisir la combinaison au clavier. Vide, Roadie ne réserve aucune touche. BetterTouchTool, Karabiner ou un autre outil peuvent appeler la CLI.

La vue n’affiche aucun contrôle : ces réglages se changent dans les paramètres et s’appliquent à la vue ouverte. Le fond reprend le fond d’écran de l’écran, flouté, et masque les icônes du bureau. Sans image lisible, Roadie floute ce qui se trouve sous la vue. Les bureaux gardent leur ordre. La loupe ne change pas de bureau quand la souris reste immobile après un agrandissement.

Chaque bureau est une grille de cartes de même taille, au format 16:10, dans l’ordre de ses stages. Le nom du bureau est une puce ; un point vert indique le bureau actif, une puce bleue le bureau agrandi par la loupe. Sous chaque carte, l’icône et le titre de la fenêtre sont suivis d’une puce avec le nom de sa stage. Les puces de la stage de la fenêtre sélectionnée sont bleues. Un contour bleu indique la fenêtre sélectionnée. Les flèches et Tab changent la sélection ; Entrée ou un clic ouvrent la fenêtre dans son bureau et sa stage d’origine. Échap ferme immédiatement la vue, quel que soit le contrôle utilisé. Un clic sur un autre écran la ferme aussi.

Les bureaux occupés, nommés ou actifs sont représentés. Les stages vides ne sont pas affichées. Les bureaux inutilisés ne sont pas ajoutés uniquement parce que leur numéro est autorisé dans la configuration. En forte densité, la vue défile pour garder des cibles utilisables. Une capture remplit sa carte, recadrée par le haut ; elle est prise à la définition de la carte et ne change plus pendant la consultation. Quand une capture manque, l’icône de l’application sert de repère.

```toml
[overview]
enabled = true
presentation = "archipelago" # ou "bays"
loupe = true
magnification = 150
hotkey = "" # combinaison facultative ; préférer l’enregistrement au clavier
```

Les images utilisent le cache partagé du rail et du sélecteur. Le mouvement de souris ne déclenche ni relevé des fenêtres, ni lecture disque, ni capture. Les captures se font par lots bornés pendant l’ouverture. Cela décrit le mécanisme ; aucun gain de performance chiffré n’est garanti.

Les cartes restent compactes : les stages utilisent plusieurs rangées et colonnes selon leur contenu. Une stage avec une seule fenêtre ne prend pas toute la hauteur. La fenêtre survolée gagne de la place dans sa stage. La loupe reste dans la composition, sans panneau superposé. Le clic ouvre la fenêtre.

Si Mission Control apparaît aussi après le balayage trois doigts, désactivez ce geste dans Réglages Système > Trackpad > Gestes supplémentaires > Mission Control. Conservez le geste Roadie dans BetterTouchTool.
