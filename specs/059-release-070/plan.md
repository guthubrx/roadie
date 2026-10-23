# Plan 059
1. Réutiliser les scripts de tests, installation et DMG existants.
2. Passer la version applicative à 0.7.0 sans modifier la dépendance TOMLKit 0.6.0.
3. Regrouper le changelog et produire des notes FR/EN centrées sur les usages.
   Harmoniser aussi le guide anglais du sélecteur avec le guide français.
4. Revue indépendante des textes et versions. Suite Swift à deux tâches et scripts.
5. Compiler Release à deux tâches ; recette temporaire dérivée de package-dmg
   avec --skip-jenkins, comme la release précédente (pas d'automatisation Finder).
6. Vérifier le DMG monté en lecture seule et le SHA-256. Créer le reçu avant tag.
7. Intégrer main, pousser, tag annoté et release GitHub avec notes bilingues.
   Retélécharger les pièces publiées et comparer leurs empreintes.
8. Installer/restart avec certificat existant, contrôler santé/configuration,
   puis supprimer branche, builds et temporaires ; conserver les diagnostics.
