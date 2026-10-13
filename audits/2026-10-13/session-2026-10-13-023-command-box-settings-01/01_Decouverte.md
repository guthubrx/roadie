# Découverte - feature 023

Mode S : 25 fichiers de code et de tests dans le diff `acc10e13..HEAD` (10 sources neuves, 5 sources modifiées, 10 fichiers de tests), plus docs et exemple. Lecture intégrale, sans échantillonnage.

Modèle de menace léger :
- Actif : `~/.config/roadies/roadies.toml` (éventuellement un lien symbolique vers un dépôt de dotfiles), sa sauvegarde et le journal d'événements.
- Surface : saisie de la boîte de commandes (tap clavier global), champs de la fenêtre de réglages, `/set nom valeur`.
- Attaquant probable : aucun attaquant distant. Le risque principal est l'erreur de l'utilisateur ou une valeur mal échappée qui casse le fichier, ou une donnée personnelle qui fuit dans le journal.
- Frontière de privilège : aucune. Le daemon tourne sous l'utilisateur et écrit dans ses propres dossiers.
