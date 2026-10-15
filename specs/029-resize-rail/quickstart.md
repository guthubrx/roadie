# Vérification : session 029

Les tests et compilations sont lancés par le parent uniquement. Ne pas modifier les sources ou tests pendant leur exécution. Toutes les commandes de test passent par le script qui isole HOME.

## Tests ciblés, puis suite complète

```bash
/Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/025-settings-readability/scripts/test --filter Spec029ResizeTests
/Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/025-settings-readability/scripts/test --filter Spec029RailTests
/Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/025-settings-readability/scripts/test --filter Spec029DisplayParkingTests
/Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/025-settings-readability/scripts/test --filter Spec029RestorationRetryTests
/Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/025-settings-readability/scripts/test
```

Conserver une preuve rouge sur l’ancienne logique, avec interfaces compatibles, puis verte sur la correction. Exécuter aussi les tests des scripts selon les commandes existantes du projet. Baseline avant session : 1 458 tests Swift et 26 tests des scripts. Les fixtures ne demandent pas d’autorisation d’accessibilité réelle.

## Installation et essai réel

Après tests et deux revues, le parent installe avec /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/025-settings-readability/scripts/install. Il conserve le certificat existant, utilise `make restart` dans ce worktree, puis vérifie les quatre contrôles de santé.

Sur la version installée, l’utilisateur vérifie :

1. Avec deux puis quatre fenêtres, tirer la séparation et relâcher. La taille reste après 2 s. Un bord extérieur reste réaligné dans sa tuile et les minima restent respectés. Un clic simple ne lance pas de redimensionnement.
2. Comparer numéro de carte, menu d’envoi « numéro · nom » et commande par position. Ils désignent le même stage. Le badge reste visible avant et après le fondu du nom. Un stage vide nommé reste accessible.
3. Débrancher puis rebrancher l’écran. Vérifier un retour court, puis un retour après plus de 60 s. L’ordre, les membres et les noms sont conservés. Les modifications faites pendant l’absence restent présentes.
4. Vérifier le déplacement vers un autre stage et le retour d’écran après longue absence. Aucun regroupement de membres ni destination fantôme ne doit apparaître.
5. Contrôler l’absence de rafale de restaurations et la réponse du daemon. Les fenêtres saines restent réactives quand une autre refuse une écriture.

Attendre cette validation avant commit de code et fusion. Aucune nouvelle release.

La configuration réelle /Users/moi/.config/roadies/roadies.toml et l’état /Users/moi/.roadies/stages.json ne servent pas de fixtures et ne sont pas modifiés pour faire passer les tests.
