# Validation145 — vérifiée

Chronologie des vérifications ; reçu final dans livraison.md.

Prototype isolé : cause native observée, source visible sur cible après fin de glisser session ; tableaux et captures horsGit. Tests :36/5 suites PASS, redcrossécran échoue bien avant retrait de la garde. Première intégration : qualification0,9ms acceptée, mais aucune décision de capture et déplacement natif ; pas de succès revendiqué. Diagnostic ajouté pour séparer clicCG, routeNSEvent et préparation de contexte. Le code chargé est une validation, pas la livraison définitive.

Les essais invalides avec source parkée sont conservés horsGit mais exclus des conclusions. Le démarrage a d’abord été demandé à une cible make start inexistante, puis corrigé immédiatement par scripts/roadiedctl start. Les pauses du daemon ont été suivies de relance et santé ; aucune application utilisateur arrêtée.

Version diagnostic chargée : PID10083. Essai external→internal avec garde des scopes et source visible : C914×1052 (4432,303)→673×934 (833,40), stable au mouvement suivant et après2s stationnaires. Capture de région : vrai contenuC remis en page. Échap pendant l’appui puis relâchement : les3 cadres intégralement restaurés. Traces : clicCG, routeNSEvent, préparation, qualification4,6ms et décisiontrue. Première tentative après activation n’a pas préparé de contexte ; cause exacte encore non attribuée, pas de correctif spéculatif appliqué.

## Vérification finale du mécanisme
Huit parcours intégrés réussis : les deux sens avec annulation puis dépôt sur AppKit ; Chrome vers externe avec annulation puis dépôt, Chrome vers interne avec annulation ; nouvel externe vers interne après chargement de la correction de masquage. Les cadres restent identiques après mouvement supplémentaire puis2s immobiles. Les captures de région montrent le contenu réel, avec reflow des mots. Aucun benchmark CPU/GPU ni latence physique revendiqué. Le premier essai intégré non préparé reste un échec ; le contrôle de préparation a aussi refusé un essai final avant clic car les cadres n’étaient pas encore stabilisés. Aucun de ces deux essais n’est compté comme succès.

Contrôles Chrome : ouverture d’un nouvel onglet au bouton+, fermeture de cet onglet parX et retour à la page fictive vérifiés. Deux clics dans le titre n’ont pas déclenché de capture Roadie ; l’action native a modifié la taille. Le bouton de fermeture de la fenêtre n’a pas été rejoué : scénario arrêté par une assertion trop restrictive sur la taille après double clic, puis Chrome propre fermé normalement par SIGTERM identifié. L’injection clavier CmdW dans ce profil n’a pas fonctionné ; elle n’est pas présentée comme un test réussi. Les tests de qualification144 couvrent aussi les contrôles et contenus non admissibles.

Masquage : test rouge sur excursion du parking, vert après garde caché/cible déjà atteinte. Les deux affectations involontaires ont été remises par les commandes transactionnelles existantes vers leur écran/bureau/stage initiaux. Observation après un second redémarrage :2/2 toujours au bon scope, au parking, sans fermeture des applications. Scopes utilisateur actifs remis à9 interne et3 externe. Les deux stages145 ont ensuite été supprimées par l’API quand les anciennes fenêtres fictives ont été reconnues fermées. Stage144 étrangère préservée.

Activation avant intégration : UUID833B2A78-2083-37FB-9355-4F14B488010F, PID85334 ; certificat78a75e8032f190a20072eb91cc2919aac344ef78 conservé, santé5/5. Deux requêtes CLI ont été émises trop tôt pendant l’ouverture du socket et ont reçu69 ; les contrôles réémis après disponibilité ont réussi. Aucun redémarrage supplémentaire n’a été lancé pour ces requêtes précoces.

Preuves : diaporama autonome vérifié (10étapes,3clics natifs horodatés,8images uniques ;453087octets). Aperçu T3 sans erreur, premier curseur/cercle orange contrôlé visuellement ; suivant, lecture/pause et dernière étape vérifiés dans le navigateur. Les captures sources et manifestes restent horsGit dans /Users/moi/.local/state/roadies/validation/2026-10-31-145. Les coordonnées retina sont converties dans le repère des pixels de capture, sans déplacement supposé du clic.

Tests finaux :64tests/10suites ciblés réussis, puis2420tests/362suites réussis en69,287s. Source figée après T007, aucun changement Sources/Tests depuis ce build.
