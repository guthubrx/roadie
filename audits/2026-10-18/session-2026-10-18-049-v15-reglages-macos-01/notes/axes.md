# Analyse par axe - diff 049 (commit 3dd5563b, readonly)

## Sécurité
Lecture seule de préférences locales par `CFPreferencesCopyAppValue` ; aucune écriture, aucun réseau,
aucun secret. Le message n'expose que des libellés fixes.

## Logique et données
Invariants 1-4 de `contexte.md`. Valeurs non booléennes (chaîne) traitées comme absentes : défaut de
la version. Ordre des réglages fixe. F1 (validation absente).

## Concurrence
Fonction pure du lecteur et de la version ; aucun état partagé ajouté.

## Complexité
O(r), r = 4 réglages, annotée. Quatre lectures CFPreferences par appel de santé.

## Tests
Cinq tests sur la logique avec préférences injectées. Non testés : branchement dans `run()` (une ligne),
lecteur réel par défaut. Pas de linter.

## Architecture
Injection du lecteur et de la version par l'initialiseur, défauts sans effet sur les appelants
existants. Aucune dépendance ajoutée.

## Minimalisme et frugalité
Checklist : `if let flag = value as? Bool` est inatteignable après le cas `NSNumber` pour les valeurs
CFPreferences (booléens pontés en NSNumber) : ~1 ligne ; type `MacOSWindowSetting` public utilisé par
le contrôle et les tests (justifié) ; aucune dépendance, aucun changement hors périmètre.
Potentiel minimalisme : ~1 ligne (méthode : relecture du diff source).

## Vertus LLM et responsabilité future
Petit changement explicable, défauts et limites écrits dans `research.md`. Docs FR/EN et CHANGELOG à
jour. Faiblesse : aucune validation ni revue consignée (F1). Message en français seulement. Cet audit
n'est pas indépendant.

## Observabilité
Le contrôle apparaît dans `daemon health --json` ; aucun journal ajouté.
