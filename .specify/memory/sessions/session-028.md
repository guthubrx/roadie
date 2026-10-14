# Session 028 - Recherche des contrôles et fermeture au clic extérieur

Date : 2026-10-14. Branche : session-028-search-dismissal.
Statut : clôturée, installée et validée. Six tâches terminées.

## Résultat

La recherche retrouve les textes des contrôles natifs portés par leurs enfants.
Les contrôles conservent leur identité et leur cible de clic. Les lignes, cellules
et textes hors fenêtre évitent des lectures de métadonnées inutiles, sans couper
les descendants visibles. Les garanties des cibles web restent inchangées.

Un clic hors de la barre de recherche ou de son panneau ferme la session et
atteint normalement l’application. Le Retour différé est annulé. Les clics
intérieurs la gardent ouverte, en recherche comme en commandes.

## Validation

1 458 tests Swift dans 156 suites, 26 tests des scripts et deux revues. La fixture
complète confirme le défaut avant correction, puis 956 appels AX de moins sur
2 428. Ce résultat ne mesure pas le temps d’Outlook réel.

Installation signée avec le certificat existant, configuration inchangée,
quatre contrôles de santé OK. L’utilisateur confirme Drafts et les clics sur
la version installée. Aucune nouvelle version publiée.

Les sources et journaux détaillés figurent dans
`specs/028-search-dismissal/implementation.md`. Le worktree lié à la conversation
est conservé ; la branche de session est supprimée après fusion.
