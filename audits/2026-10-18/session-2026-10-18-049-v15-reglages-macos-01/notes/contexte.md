# Preuve de contexte - audit V15 readonly, session 049 (réglages macOS qui gênent le tuilage)

Racine figée : `/private/tmp/roadie-audit-049` (worktree détaché, commit 3dd5563b24b29ca83312e2c15f881ad4787d51c0).
Revue différentielle : base 38f69a6a799aa3a9767ca042715a7d436e804a4b (051). Mode readonly, un cycle.
Auditeur : Claude (Opus), même agent que l'orchestration, `independent=false`. Aucune revue indépendante.

## Biens à protéger
- Diagnostic exact de `roadie daemon health` / `roadie query health` (aucune fausse alerte, aucun échec induit).
- Réglages macOS de l'utilisateur : jamais modifiés (R5).
- Code de sortie de `daemon health` (scripts) : fondé sur `failed`, donc sur `.fail` seulement.

## Acteurs et points d'entrée
- `DaemonHealthService.run()` (`DaemonHealth.swift:136-155`), appelé par `CLICommandRouter.swift:698`
  (`daemon health`), `AutomationQueryService.swift:66` (`query health`) et `heal()` (`DaemonHealth.swift:186`).
- Lecteur de préférences par défaut : `CFPreferencesCopyAppValue(key, "com.apple.WindowManager")`
  (`DaemonHealth.swift:122`), lecture seule ; version majeure par `ProcessInfo`.
- Aucun point d'entrée réseau ; aucune donnée externe non fiable (préférences locales de l'utilisateur).

## Invariants vérifiés à la lecture
1. Le contrôle rend `warn` ou `ok`, jamais `fail` (`macOSWindowSettingsCheck`) ; `failed` ne compte que `.fail` (l. 32-34).
2. Valeur explicite prioritaire (NSNumber/Bool) ; clé absente -> défaut selon la version (`isEnabled`, l. 96-101).
3. Aucun appel d'écriture de préférences (`CFPreferencesSet*`, `defaults write`) : recherche vide dans `Sources/`.
4. Aucun consommateur ne déclenche une action sur `.warn` (recherche `level == .warn` dans `Sources/`).

## Observation runtime (lecture seule)
`defaults read com.apple.WindowManager` (run 20261018T181128556802Z), macOS 26.2 :
`GloballyEnabled = 0`, `EnableTilingByEdgeDrag = 0`, `EnableTopTilingByEdgeDrag = 0`,
`EnableStandardClickToShowDesktop = 0`. Par la logique du contrôle, le niveau attendu est `ok`.
Le binaire installé n'a pas été exécuté (aucune installation autorisée).

## Fichiers lus
Diff complet ; `DaemonHealth.swift` (1-200) ; `CLICommandRouter.swift:690-712` ; `LayoutMaintainer.swift:270-300` ;
`AutomationQueryService.swift:60-70` ; `scripts/install` (l. 172) ; spec, plan, research, reuse-audit, tasks ; docs FR/EN, CHANGELOG.

## Zones non lues et inconnues
- Défauts macOS d'une clé absente : non documentés par Apple (limite écrite dans `research.md`).
- Rendu texte de `Formatters.swift` pour `warn` : non relu en détail.
