# Contrat utilisateur

`roadie toggle maximize` active ou désactive la maximisation de la fenêtre active. Rail masqué, elle occupe toute la zone utile comme le plein écran Roadie. Rail visible ou épinglé avec `roadie rail pin`, elle se redimensionne à côté du navrail sans quitter la maximisation. La sortie textuelle nomme maximize et on/off ; le code de sortie existant distingue action/refus.

`roadie toggle fullscreen` garde son cadre plein écran Roadie. Il remplace un zoom réservé en conservant sa sauvegarde.

`roadie toggle native-fullscreen` reste la commande macOS.

Menu de titre configurable : sous-menu « Fenêtre », entrée « Maximiser / restaurer (garder le navrail) ». La cible est le windowID du menu ; aucun changement des raccourcis externes.

La nouvelle commande maximize passe par le socket du daemon lorsqu’il est actif. Le routage des deux anciennes commandes reste inchangé.
