# Contrat utilisateur

`roadie toggle maximize` active ou désactive la maximisation de la fenêtre active à côté du navrail. La sortie textuelle nomme maximize et on/off ; le code de sortie existant distingue action/refus.

`roadie toggle fullscreen` garde son cadre plein écran Roadie. Il remplace un zoom réservé en conservant sa sauvegarde.

`roadie toggle native-fullscreen` reste la commande macOS.

Menu de titre configurable : sous-menu « Fenêtre », entrée « Maximiser / restaurer (garder le navrail) ». La cible est le windowID du menu ; aucun changement des raccourcis externes.

La nouvelle commande maximize passe par le socket du daemon lorsqu’il est actif. Le routage des deux anciennes commandes reste inchangé.
