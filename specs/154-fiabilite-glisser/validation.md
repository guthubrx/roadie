# Validation 154

## Résultat actif

Version optimisée installée sur le Mac le 10 novembre 2026. UUID `7796DB9C-F20C-3BD7-9910-00B8B001105E`, daemon PID 7760 après activation. Les cinq contrôles santé sont OK : processus, daemon, tests internes, état et réglages macOS. Certificat `roadied-cert` conservé, empreinte `78a75e8032f190a20072eb91cc2919aac344ef78`.

Les 536 empreintes des fichiers Swift Sources/Tests sont identiques avant les tests, après compilation et après les parcours natifs. Le build actif correspond à ces sources. Aucun numéro de release publique n'est créé pour cette correction.

## Diagnostic et corrections

Les journaux conservés couvrent le 7 novembre à 15:41:47 UTC jusqu'au 10 novembre au début de l'analyse. La rotation ne permet pas de revoir les sept jours complets. Aucun rapport de crash Roadie trouvé depuis le 3 novembre. Les compteurs et leur portée figurent dans observations.md. Les refus AX observés ne sont pas tous attribuables à un défaut de Roadie.

La version 153 bloque un transfert fictif depuis une fenêtre agrandie par Roadie : après le dépôt demandé sur l'écran interne, elle reste sur l'écran externe. Le test de régression échoue sur la base 4f3694fb. Le suivi compare maintenant le zoom initial au zoom courant ; un zoom déjà présent n'annule plus le geste. Un changement de zoom, d'arbre, de membres, de stage ou de génération reste protégé. Échap conserve le zoom et restaure les cadres.

Un appui CGEvent observé avait produit deux entrées AppKit. Le routeur filtre le doublon avant de révoquer l'aperçu : même timestamp positif et même point. Un timestamp inconnu reste accepté. Les doublons filtrés et abandons sont journalisés.

Le relevé natif montre aussi un fond Notification Center sans sous-rôle, à la taille exacte de l'écran interne. Le picker le prenait pour un obstacle. La règle étroite déjà utilisée par les gestes modificateurs s'applique maintenant au titre, au bord, au focus et aux poignées. Les vrais panneaux restent bloquants. Le test échoue sur les trois pickers avant correction.

Enfin, la garde Ctrl + glisser comparait tout DisplaySnapshot. Un changement de isMain lié au focus annulait le geste sans changement géométrique. Le test reproduit ce rejet. La comparaison porte désormais sur les identifiants et cadres complets/utiles. Le changement de frame.x continue d'annuler. Les raisons distinguent géométrie, génération, configuration, identité et stage/pin.

## Vérifications

- 2 523 tests Swift dans 383 suites réussis en 157,362 s, sur les sources finales figées.
- 28 tests de scripts réussis en 22,138 s.
- 45 tests ciblés des sessions 151, 153 et 154 réussis après la dernière correction.
- Quatre revues indépendantes en lecture seule sur les patchs fournis et leur base publiée. Les relecteurs Linux n'ont exécuté ni tests Mac ni parcours natifs. Constats, réponses et limites dans revue.md.
- Une assertion temporelle de la session 144 a échoué dans un passage ciblé parallèle sous charge. Elle passe ensuite en séquentiel et dans la suite finale. Aucun changement produit n'a été fondé sur cet échec seul.

## Parcours sur le Mac

Les captures ne contiennent que deux fenêtres fictives. Le glisser par le titre rejoint l'écran externe puis l'interne. Deux dépôts changed=true sont journalisés ; cadres et affectations sont relus. Ces essais utilisent UUID F44DA24C-0DD9-3F30-8A7C-CEEF77D305A9, qui contient déjà les corrections du zoom, des doublons et du fond transparent.

Sur le binaire final 7796DB9C, Ctrl + glisser depuis le contenu de la fenêtre fictive 1226 rejoint l'écran externe, bureau 3, stage 9, cadre (2585,−166,914,1052). Le journal finit par modifier_gesture.ended reason=finished. La copie est présente pendant le geste, alpha WindowServer 0,85. Une paire down/up injectée par le pilote est observée. Le résultat est relu depuis le daemon après relâchement.

Échap a rendu exactement les cadres des deux fenêtres fictives à leur position de départ. Le contrôle natif d'une poignée de séparation n'est pas enregistré ; son filtre est couvert par lecture et par les régressions des pickers. Les parcours ne prétendent pas couvrir chaque application privée de l'utilisateur.

## Preuves

Diaporama autonome : preuves-corrections/2026-11-10-154/preuves.html. Douze étapes, cinq appuis injectés puis observés par un tap natif. Repère orange de la première action inspecté. Pause, lecture, précédent, suivant, sélection, dernière étape et zoom contrôlés ; console PROOFS_CONTROL_CHECK: PASS. Le plein écran est câblé, sans essai natif séparé. Affichage html_preview puis html_render effectué. Les captures et manifestes originaux restent hors Git.

## Configuration et construction

Les paramètres de glisser sont conservés. Une modification concurrente de configuration utilisateur est présente ; elle est conservée, sans restauration de l'ancienne copie. Aucun réglage BTT permanent n'est créé ou modifié par les actions de test.

Deux constructions intermédiaires ont été refusées après modification de source pendant le build. Aucun de ces builds refusés n'a été activé. Le gel par empreinte précède la suite finale et la compilation optimisée réussies. Des avertissements de cache SwiftPM sont présents ; ils n'empêchent pas les constructions finales.

Le banc d'essai synchrone reçoit parfois un mouseUp supplémentaire (PID 0), avant celui du pilote. Un autre essai est annulé avec stage_or_pin_changed pendant la réactivation de la seconde fenêtre fictive. Ces essais ne sont pas comptés comme réussites. Le pilote final prépare la fenêtre visée et tourne séparément de l'action appelante ; aucune paire supplémentaire n'y est observée. Aucun correctif produit n'a été ajouté sur la seule base de ces essais perturbés.

## Conservation

Retour arrière 153 et originaux conservés dans /Users/moi/.local/state/roadies/validation/2026-11-10-154. Les quatre vues distantes de revue restent sous la garde native de Bridget ; aucun parcours de retrait n'est exposé ici. Ce ne sont pas des worktrees Git locaux. Le résultat de la quatrième revue est conservé malgré l'échec de son ACK ; incident transmis au mainteneur, reçu accepted, sans succès de réparation présumé.

L'intégration, le push et le nettoyage final sont consignés après vérification dans livraison.md.
