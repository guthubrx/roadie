# Validation 156

Code intégré et poussé sur main le 14 novembre 2026 :
`57b9e6ae6cf1e1742d246722f62aaba92d6d1537`.

Code installé et actif : Roadie 0.14.0 (`57b9e6ae`), PID 62557,
UUID `F38BCEF8-D412-3699-8761-D9E0C7A9AD05` (arm64).
Le commit de clôture ne change que la documentation ; les sources installées restent identiques.

- 2560 tests dans 391 suites : succès, 68,401 s.
- 29 tests de scripts : succès, 11,927 s.
- Compilation optimisée, vérification de signature et activation : succès.
- Santé du daemon actif : 5/5.
- Configuration inchangée octet pour octet ; exigence de signature identique.
- Autorisations Accessibilité et capture du daemon conservées.
- Aucun workflow CI ni publication de nouvelle release.

La contre-revue et sa réponse motivée sont consignées dans `implementation.md`.
Les limites des preuves natives y sont détaillées. Aucun diaporama vérifié ni essai
clavier physique n’est revendiqué : les outils de cette session n’en ont pas les permissions.
Les refus applicatifs et les captures tardives sont vérifiés par les régressions contrôlées.

## Ménage

Le cache de compilation de 1,4 Gio a été nettoyé par SwiftPM. Le worktree de validation
(46 Mo restants) et sa branche fusionnée ont été retirés par le ménage gardé, après
un rapport les classant supprimables. Les trois ressources temporaires de la fixture
ont été retirées après vérification de l’arrêt de leurs processus. Aucun stage ni
signet temporaire ne reste. La fenêtre existante déplacée pendant les essais a
retrouvé sa stage d’origine. Aucun processus utilisateur n’a été terminé.

Le seul checkout et la seule branche conservés après la clôture sont main.
Le worktree documentaire de clôture est soumis au même retrait gardé après ce commit.
Les exécutables installés restent hors du dépôt. Le retour arrière et les traces utiles
sont conservés hors Git, environ 48 Mo, dans :
`/Users/moi/.local/state/roadies/validation/2026-11-14-156`.
Ce dossier contient aussi les reçus de publication, de contrôle du runtime et de ménage.
