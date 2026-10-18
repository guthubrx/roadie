# Recherche de variantes - session 049 readonly

Racine : `/private/tmp/roadie-audit-049`.

## Critère de réussite sans trace de validation (F1)
`ls specs/04[89]*/validation.md specs/05*/validation.md` : 048 et 051 en ont un ; 049 non.
`grep -n "\[ \]" specs/049-reglages-macos/tasks.md` : T004 et T005 ouvertes.

## Écriture de préférences ou action sur un avertissement
`grep -rn "CFPreferencesSet\|defaults write\|UserDefaults(suiteName" Sources` : aucune écriture dans
le domaine `com.apple.WindowManager`. `grep -rn "level == .warn" Sources` : aucun consommateur. Sain.
