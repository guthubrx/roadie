# Plan

Réutiliser scripts/install, scripts/package-dmg et scripts/build-app-bundle.
Référence publiée vérifiée par gh : v0.5.0 du 14 octobre 2026. Regrouper les
changements en rail, redimensionnement, placement/mode flottant, recherche et
réactivité. README et index pointent vers 0.6.0 ; anciens liens conservés dans
l'historique. Ne pas publier de gain chiffré à partir d'une mesure contaminée.

Revue indépendante en lecture seule, tests Swift à deux tâches et scripts.
Construire avec les recettes existantes adaptées temporairement à deux tâches.
Vérifier le volume monté du DMG, Info.plist, architecture, signatures, exécutable
et somme de contrôle. Installer la même compilation avec le certificat local.
Commit, intégration main, tag, release avec notes préparées puis téléchargement
de contrôle. Nettoyer seulement les artefacts créés ou identifiés inutiles.
