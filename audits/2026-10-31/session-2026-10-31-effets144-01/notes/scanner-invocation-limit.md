# Invocation des scanners

La CLI audit.py refuse --command avec un nom d'outil différent de custom. Les deux commandes ciblées ont donc été exécutées par runner.execute puis adapters.import_run, les mêmes fonctions appelées par la CLI. Les verrous machine/session, budgets temps/mémoire/processus/sortie, versions, commandes et empreintes restent appliqués. Aucun fichier du moteur ou des règles figées n'a été modifié.

Gitleaks directory sur le worktree absolu ne scannait aucun octet car le chemin contient .worktrees, exclu par la règle standard. Une copie des1553 fichiers du manifeste a été construite hors de ce chemin, avec correspondance SHA exacte (scanner-snapshot-map.json). Gitleaks a réellement scanné la copie : aucun candidat. Ce contrôle ne vaut que pour les fichiers inventoriés. Les exclusions audits/dependencies existantes sont conservées ; les sources ne sont pas exclues dans la copie.

OSV sur la racine héritait aussi de l'exclusion du worktree. Le verrou Package.resolved exact est passé explicitement : TOMLKit0.6.0, aucune vulnérabilité signalée, pas de dépendance modifiée. L'historique Gitleaks demeure borné après v0.4.0 jusqu'à37e5cd92 ; aucun résultat avant cette borne n'est affirmé. Les erreurs initiales révision0 sont conservées ; seuls les runs complets révision1 font preuve finale.
