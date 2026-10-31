# État transitoire
Session candidate/native : jeton unique révocable, cible WindowSnapshot, scope, configuration, arbre initial, géométrie, séparations préparées, dernière frame observée, arbre provisoire, phase (candidat/suivi/clôture), génération attendue. Cet état ne change pas le format de stages.json.
Lots par PID : une opération active, un dernier lot en attente. Une observation cible active au plus. Une clôture porte le même jeton et est ignorée si la session a changé.
