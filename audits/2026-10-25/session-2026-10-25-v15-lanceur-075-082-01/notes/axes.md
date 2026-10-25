# Axes - révision 1

- Sécurité : aucune authentification ni réseau ; scripts AppleScript construits avec des
  identifiants de navigateurs fixes et des entiers (aucun texte saisi interpolé) ; `qlmanage` reçoit
  un chemin en argument, pas de shell. Règles écrites relues avant remplacement. Secrets : aucun.
- Fiabilité : maintien d'aperçu à échéance, placements et positions bornés (10 s, 20 s), annulation
  bornée (10 min) ; restauration de l'aperçu vérifiée en réel (0 fenêtre à plus de 2 points).
- Tests : 2 028 tests, suites Spec075 à Spec082 ; essais réels par CLI ; clavier non simulé.
- Performance : délais et annulations présents ; aucune mesure de latence (critère 50 ms non
  mesuré) ; F2 écriture synchrone bornée.
- Complexité : fonctions annotées O(…) ; bornes : 200 déplacements, 6 contextes, 9 rangs, 40
  fichiers, 5 lignes par section.
- Qualité : refus expliqués (abréviations, projets, stage anonyme) ; F1 demande d'autorisation.
- Architecture : logique pure dans des types séparés (LauncherPhrase, LauncherAliases,
  StageProjects, LauncherMemory, LauncherOpenItems) ; contrôleur `TargetModeRuntimeController`
  devenu volumineux (point de vigilance) ; aucune dépendance de module ajoutée.
- Hygiène IA : invariants dans research.md et commentaires ; revue indépendante impossible
  (Bridget : capability_unavailable, project_mapping_unknown).
- Minimalisme : aucune dépendance ; options de diagnostic (`--preview-only`, `--open-items`)
  documentées et utiles aux essais réels.
- Métier : AXDocument lu en chaîne ou URL (défaut corrigé en 077) ; noms de stage réels (067).
- Traçabilité : chaque session a spec, plan, research, reuse-audit, tasks, validation ; limites
  notées.
