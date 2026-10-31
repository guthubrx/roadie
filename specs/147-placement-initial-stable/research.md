# Diagnostic147 — données avant correction

Utilisateur : nouvelle fenêtre iTerm2, pas rappel d’une fenêtre connue. Version146 et diagnostic147 ont le même mécanisme ; le diagnostic ajoute seulement effects.frames_policy avec IDs directs et cadres. La première hypothèse (tentative assimilée à stabilisation, donc retour à l’animation) n’est PAS retenue comme cause de cette série : quatre nouvelles fenêtres au raccourci CmdN sont toutes explicitement directes.

Premier cas500897 : naissance570×436 à150,40 sur l’écran interne ; taille914×942 encore à150,40 ; déplacement4432,-759 ; taille finale914×1052. Le premier agrandissement est donc bien effectué à l’ancien emplacement. Trois cas suivants500916/500933/500948 : naissance à4432,-759, puis cible finale au même endroit. La position de naissance mémorisée par iTerm varie et rend le défaut intermittent. Captures/CG et décisions sont dans /Users/moi/.local/state/roadies/validation/2026-10-31-147 (bruts copiés à la clôture).

Cause dans AXWindowFrameWriter.write : séquence sizeBefore, position, sizeAfter. Le premier placement146 supprime l’interpolation mais ne change pas cet ordre. L’application contraint la première taille à l’écran d’origine, ce qui crée un agrandissement visible au mauvais endroit avant le déplacement.

Décision : une première disposition ajoute une tentative de position AVANT la séquence existante. Le trio historique reste conservé pour finir taille et position et pour les refus non fatals de cette tentative anticipée. Les fenêtres déjà stabilisées gardent strictement leur chemin. Pas de suivi de cycle de vie nouveau : hypothèse non confirmée, aucun dictionnaire supplémentaire. Le budget reste par tentative de cadre, pas par attribut.

Limites/outils : CUA refuse son initialisation (CUA_REPL_ENABLED_SURFACES is required) ; pilote natif signé déjà présent réutilisé pour CmdN. Première préparation AppleScript par nom iTerm2 a échoué à la compilation, avant création ; chemin absolu du même iTerm officiel a résolu le dictionnaire. Un summon lancé avant disponibilité a signalé stale window pruned ; le relevé frais suivant a correctement confirmé l’ancrage, aucune restauration globale exécutée.
