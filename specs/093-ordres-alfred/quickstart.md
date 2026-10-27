# Essai 093

1. `roadie workflow list` : « ordres à Alfred : … » à la place de « parle à Alfred ».
2. `roadie workflow alfred search "emoji "` : la barre s'ouvre avec « emoji ».
3. Dans un workflow, un script `osascript -e 'tell application id "com.runningwithcrayons.Alfred" to
   run trigger "x" in workflow "id"'` lance le déclencheur dans Roadie ; Alfred ne s'ouvre pas.
4. `roadie workflow alfred set ID cle valeur` puis `cat ~/.roadies/workflows-settings/ID.json`.
