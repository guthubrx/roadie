# Validation de la session 044

## Correction et tests
Le test reproduit l'absence des poignées avec des fenêtres de bordure transparentes dépassant les cadres de 12 points. Avant correction, les cas à deux et quatre fenêtres échouent, avec quatre assertions en échec. Après correction, ils passent ; les six variantes de vraies fenêtres/attributs inconnus continuent de bloquer la prise lorsqu'elles occupent l'interstice.

18 tests ciblés réussis ; suite complète : 1 689 tests dans 199 suites réussis. Le benchmark opt-in passe aussi et vérifie les cadres/persistance via le même helper. Les 292 empreintes Sources/Tests sont inchangées depuis les tests. Aucun script de production modifié ; les tests de scripts n'ont pas été relancés.

## Comparaison
Résultats et protocole dans comparatif.md. Temps médian de l'appel final : natif 1,73 / 1,92 ms et poignée 0,60 / 0,65 ms pour deux/quatre fenêtres. Le test inclut la persistance et les E/S disque, avec AX simulé. La préparation du relevé, les événements, l'ordonnanceur et le minuteur de 50 ms sont exclus. Un relevé évité pendant l'appel, mais une écriture simulée supplémentaire par poignée. Aucun gain de fluidité ou de latence réelle établi.

## Revue indépendante
Mission Bridget c768f33f-68f8-46a1-aeda-4669355e5108, demande roadie-044-review-1. Lecture seule des fichiers actuels ; shell indisponible, pas de diff ni de tests exécutés par le réviseur. Verdict favorable borné, aucun point bloquant.

Réserves traitées : le rapport précise les E/S disque et la différence de travail entre les deux chemins. Le benchmark contient des assertions fonctionnelles dans son helper ; aucun seuil temporel n'est voulu sur la machine chargée. Le nom de processus borders est une convention effectivement observée, pas une détection générique de transparence : un changement de cette convention masque les poignées par sécurité. Pas d'élargissement aux autres panneaux illisibles.

La construction de la liste d'occupation reste par écran comme avant la correction ; la déplacer constituerait une optimisation séparée sans gain mesuré. Les suggestions de renommage et de constantes de dessin ne changent pas le comportement et n'ont pas justifié d'élargir ce correctif.

La prise de clic réelle reste à vérifier. macOS déclare toutefois le panneau de poignée au niveau 3, au-dessus des fenêtres borders observées au niveau 0 : le dessin ne dépend donc pas du passage des clics à travers une bordure située au-dessus.

## Installation et observation native
Release installée et relancée le 18 octobre 2026. UUID compilé/installé : DEA0CA0C-6175-35D6-8A08-68473D919EC1. Signature stricte vérifiée ; certificat 78a75e8032f190a20072eb91cc2919aac344ef78 conservé. La recette d'installation existante a été utilisée avec compilation limitée à deux tâches, sans modifier le script versionné.

Application : /Users/moi/Applications/Roadie.app. CLI : /Users/moi/.local/bin/roadie. PID 54197 ; quatre contrôles santé OK, Accessibilité et configuration valides. Configuration personnelle inchangée : SHA-256 48fd91ee05ccc94cb5ed3ddb0a86b62abe511af99a2fbc1bc00b469e627a9099 avant/après.

Avant correction, CoreGraphics n'expose aucun panneau de poignée. Après relance, il expose le panneau 45100, niveau 3, rectangle AX x=3500, y=-759, largeur=8, hauteur=2114. Ce panneau correspond à la séparation des deux fenêtres du stage actif de l'écran externe. Le stage actif de l'écran interne ne contient plus qu'une fenêtre, donc aucune poignée n'y est attendue. Le réglage resize_handles est vrai et l'écart entre fenêtres vaut 10 points.

## Preuves incomplètes
CUA renvoie `CUA_REPL_ENABLED_SURFACES is required` et screencapture `could not create image from display`. Aucune capture, aucun clic ni diaporama vérifié n'est revendiqué. La présence du panneau dans macOS est établie ; son aspect et un glisser réel restent à confirmer. Les traces sont conservées hors Git dans /Users/moi/.roadies/diagnostics/2026-10-18-session044/.

## Git et nettoyage
Correction 826c2eeb intégrée par avance rapide et poussée sur origin/main. Branche session-044-poignees-visibles supprimée. Fichiers de compilation et recette temporaire d'installation retirés ; journaux conservés hors Git. Les deux seuls worktrees sont le dépôt principal et le worktree actif de la conversation, conservé détaché. Quatre contrôles santé OK après nettoyage. Un commit documentaire de clôture consigne ces opérations.
