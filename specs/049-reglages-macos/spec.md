# 049 - Réglages macOS qui gênent le tuilage

Demande validée le 18 octobre 2026 (`/my.specify-all 1 a 4`, point 2), issue de la
comparaison avec TrellisWM (« Turn off what gets in the way »).

## Besoin

Certains réglages de macOS déplacent ou redimensionnent les fenêtres à la place de
Roadie. L'utilisateur ne le sait pas et croit que Roadie se trompe. `roadie query health`
doit signaler ces réglages et dire où les désactiver.

## Exigences

- R1 Un contrôle de santé `macos-window-settings` signale en avertissement (`warn`) :
  - Stage Manager actif ;
  - tuilage natif par glisser vers un bord de l'écran ;
  - remplissage de l'écran par glisser vers la barre des menus ;
  - clic sur le fond d'écran pour afficher le bureau.
  Le double-clic sur la barre de titre est ajouté par la session 050.
- R2 Une clé absente prend la valeur par défaut de macOS de la version installée.
- R3 Le message nomme chaque réglage en clair et le chemin dans Réglages Système.
- R4 Aucun réglage gênant : niveau `ok`. Le contrôle ne fait jamais échouer la santé.
- R5 Lecture seule : Roadie ne modifie jamais un réglage macOS.

## Critères de réussite

Tests avec des préférences injectées pour chaque cas ; `roadie query health` installé
renvoie `ok` sur la machine de l'utilisateur, dont les réglages sont déjà désactivés.
