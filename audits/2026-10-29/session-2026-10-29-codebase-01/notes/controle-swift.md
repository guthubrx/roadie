# Contrôles Swift, analyse statique et tests

- Compilation et tests : `scripts/test --package-path <worktree de conversation> --jobs 2 --no-parallel
  --skip "Audit022R4LotT6Tests|Settings027IPCTests"`, run `20261029T180536484946Z` : 2 267 tests dans
  331 suites réussis en 46,2 s (208 s avec compilation). Le worktree de conversation est au commit figé
  3c9d66d9 et propre (vérifié par `git status` et `git rev-parse`). Deux suites exclues : signaux forcés
  et notification système globale. `Spec088ScriptRunnerTests`, exclue en octobre, a été exécutée.
- Scripts Python : 28 tests réussis (run `20261029T180935866623Z`).
- SwiftLint 6 règles ciblées (run `20261029T180949045528Z`) : 45 signaux (33 le 27 octobre). Les
  12 nouveaux ont été relus : 8 `try!` sur expressions régulières constantes d'AlfredBridge (couvertes
  par les tests), conversions AX précédées d'un contrôle `CFGetTypeID` (LauncherFocusRestore:49,
  TargetModeRuntimeController:910, AXDocument:21), `baseAddress!` sur tampons non vides
  (WindowKeyFocus:36, LauncherBookmarks:332-333), déballages après filtre (LauncherSearchContext:164,
  AlfredFileFilter:30). Aucun arrêt possible démontré. Les règles de style ne sont pas une recherche
  exhaustive de défauts.
- Semgrep (pack CI figé et règles locales) : 0 signal. Couverture Swift réduite à quelques règles.
- Gitleaks fichiers : 0 signal. Historique : complet interrompu à 300 s ; borné depuis v0.4.0
  (5ab0ab95, exclusif) jusqu'au commit figé, 0 signal. Commits antérieurs à v0.4.0 non vérifiés.
- OSV-Scanner : 0 avis (une dépendance verrouillée, TOMLKit 0.6.0).
- ShellCheck absent : les scripts shell ne sont pas analysés statiquement ; ils n'ont changé que de
  3 lignes depuis l'audit du 27 octobre.
- Modules : 5 bibliothèques et 2 exécutables SwiftPM, graphe acyclique imposé par SwiftPM ;
  RoadieDaemon regroupe 62 730 lignes, ses dépendances internes ne sont pas cartographiées.
