# 046 — Placement sur l'écran actif par défaut

Demande validée le 18 octobre 2026 : généraliser le réglage dont l'essai utilisateur
confirme « Même stage, intégration rapide » lors de deux ouvertures par ⌘N.

Sans choix enregistré, une nouvelle fenêtre doit rejoindre le stage courant de
l'écran actif (`focused_display`). Les choix explicites `mouse` et `macos` restent
respectés. La fenêtre des paramètres doit parler des nouvelles fenêtres, proposer
des noms français lisibles et expliquer le cas d'une souris restée sur l'autre écran.

Aligner constructeur, décodage sans clé ou valeur invalide, catalogue et exemple.
Documenter le défaut dans les guides français/anglais et le changelog. Ne modifier
ni l'ordonnanceur, ni les délais, ni le mécanisme de placement : l'essai réel a
confirmé que le réglage existant suffit. Aucun gain chiffré de performance revendiqué.
