# Sélecteur de fenêtres

Le sélecteur retrouve les fenêtres gérées par Roadie dans leur bureau, leur stage
et leur écran.
Il ouvre ce contexte avant de donner le focus à la fenêtre. Il ne déplace pas la
fenêtre dans la stage courante.

## Utilisation

Les raccourcis peuvent être gérés par **BetterTouchTool ou Karabiner**, comme les
autres commandes Roadie. Aucun raccourci global d'ouverture n'est enregistré
par défaut par Roadie. Exemple avec **⌘ Tab** dans BetterTouchTool :

- ⌘ Tab exécute `roadie switcher cycle --hold cmd` ;
- ⌘ Maj Tab exécute `roadie switcher cycle --hold cmd --backwards` ;
- relâcher ⌘ ouvre la fenêtre sélectionnée ; Échap annule.

Dans une action shell, utilise le chemin complet du binaire installé :
`/Users/moi/.local/bin/roadie`. Pour une autre installation, adapte ce chemin.
Un raccourci interne reste possible en remplissant le champ facultatif du profil.

Le profil peut aussi garder le sélecteur ouvert après le relâchement. Dans ce
mode, recherche une application, un titre, une stage ou un bureau, puis valide
avec Retour ou un clic. La sélection garde son identité pendant la recherche.
L'aperçu agrandi ne donne pas le focus à la vraie fenêtre.

AltTab peut rester installé pour comparer les deux outils. Choisis des
raccourcis différents dans leurs réglages.

## Profils et raccourcis

Dans **Paramètres > Sélecteur > Profils de raccourcis**, sélectionne un profil
ou crée un nouveau profil. Son nom décrit son usage ; l'identifiant reste interne.
Choisis **Roadie**, **BetterTouchTool** ou **Outil externe / commande**.

Les onglets **Raccourci**, **Fenêtres**, **Navigation** et **Apparence** occupent
toute la largeur. À grande police, ils passent sur deux rangées. Le premier
choisit le déclenchement ; les autres règlent le contenu et la présentation.

Avec Roadie ou BTT, clique sur **Enregistrer**, puis appuie sur la combinaison.
Les touches s'affichent en symboles ; Échap annule et Effacer retire la combinaison.
La capture ne reste active que pendant cet enregistrement. Elle utilise l'accès
Accessibilité déjà accordé au daemon Roadie.

BTT doit être ouvert pour créer ou modifier sa liaison. Roadie prépare une paire
suivant/inverse, vérifie les entrées, puis l'active. Un échec conserve ou restaure
la configuration précédente. Les raccourcis non reconnus ne sont pas supprimés.
Après configuration, essaie la combinaison physique : une relecture d'entrée ne
prouve pas son interception. L'option externe conserve les commandes CLI/BTT et
Karabiner déjà utilisées.

Trois modes sont proposés au relâchement :

- **Activer la fenêtre choisie** : basculer rapidement ;
- **Rester ouvert** : naviguer et utiliser les actions, puis valider ;
- **Passer en recherche** : saisir le nom recherché après relâchement.

Le champ de recherche et le menu Actions suivent le mode ou un choix explicite.
Cmd+F ouvre la recherche lorsqu'elle est autorisée. Échap quitte d'abord une
recherche ouverte en cours de session, puis ferme le sélecteur ; une session
ouverte directement en recherche se ferme par Échap.

## Navigation au clavier et à la souris

Les quatre flèches déplacent la sélection selon la grille, même en maintenant
les modificateurs du raccourci d'ouverture, par exemple Commande après ⌘ Tab. Sur une dernière ligne
incomplète, Haut/Bas choisissent la carte la plus proche de la colonne visée.
Le survol sélectionne une carte ; le clic active sa fenêtre. Un pointeur immobile
ne reprend pas la sélection après une action au clavier. Ces deux modes de
navigation se règlent par profil. Pendant la saisie d'un texte de recherche,
Gauche/Droite gardent leur rôle d'édition et Haut/Bas parcourent les résultats.
La composition de texte et les raccourcis macOS d'édition restent disponibles.

## Réglages

Dans **Paramètres > Sélecteur**, choisis l'affichage en vignettes, icônes ou
liste. La grille de miniatures se place à côté du grand aperçu. Sur un écran
étroit, elle passe dessous. Le champ de recherche garde la largeur du panneau.
Ajuste la taille automatique, la largeur des vignettes, la taille et la
famille de police. Les réglages prennent effet sans redémarrage.

Tu peux définir jusqu'à neuf profils de raccourcis. Chaque profil possède :

- un nom et, si souhaité, un raccourci interne ;
- une portée : toutes les fenêtres, écran, bureau, stage ou application active ;
- un ordre : récent, titre ou stage ;
- un choix pour les fenêtres réduites, applications masquées et plein écran ;
- une option pour afficher une seule fenêtre par application ;
- une validation au relâchement ou un maintien ouvert.

Chaque profil peut suivre l'apparence commune ou remplacer le style, le grand aperçu, la taille des vignettes et la police. Vider une valeur personnalisée rétablit le choix commun.

Les exclusions par identifiant d'application s'appliquent à tous les profils.
Les commandes d'action ciblent la fenêtre sélectionnée : fermer, réduire ou
restaurer, masquer ou quitter normalement l'application, maximiser, plein écran
Roadie. Quitter une application reste soumis à ses éventuelles demandes de
sauvegarde.

## Commandes et gestes

```sh
roadie switcher show
roadie switcher cycle --hold cmd
roadie switcher cycle --hold cmd --backwards
roadie switcher show --profile all
roadie switcher next
roadie switcher previous
roadie switcher accept
roadie switcher cancel
```

BetterTouchTool peut appeler ces commandes depuis un geste. `show` utilise
l'identifiant du profil, pas son nom affiché. La CLI confirme la mise en file de
la commande ; cette réponse ne prouve pas qu'une fenêtre a ensuite été activée.
`cycle` suit le relâchement des modificateurs indiqués par `--hold` (exemples :
`cmd`, `ctrl+alt`). `show` garde le panneau ouvert jusqu’à validation explicite.
Le daemon et son composant graphique doivent être actifs. En mode standard,
le sélecteur reste disponible avec `--no-target-mode`. En mode modulaire, il
partage le processus `target-mode` avec les autres interfaces clavier.

## Aperçus et limites

Le rail et le sélecteur partagent leur cache d'images dans le même processus.
Une icône et le titre restent disponibles lorsqu'une capture manque. Les images
peuvent dater du dernier relevé ; le sélecteur n'est pas un flux vidéo permanent.

Si macOS ne permet pas de vérifier l’état d’une fenêtre hors écran, la carte
indique « état non vérifié ». Un profil qui exclut les fenêtres réduites,
masquées ou plein écran écarte aussi ces états inconnus.

Les bureaux Roadie sont distincts des Spaces natifs de macOS. Cette intégration
ne constitue pas une gestion complète des Spaces ni des onglets natifs.
Le sélecteur est une implémentation propre à Roadie ; il n'importe pas le code,
les ressources ou la licence commerciale d'AltTab.
