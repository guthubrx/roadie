# Résultats de la session 156

Correction des défauts confirmés dans les journaux des 7-14 novembre 2026.

## Comportements corrigés

- Rappel : le placement finit avant le focus, même si les animations sont actives. Le refus final déclenche une compensation des cadres et de l’état, uniquement si la génération et l’état restent ceux de la commande. Une reprise inter-Space bornée reste disponible au sélecteur.
- Lanceur : le parcours du cache des fichiers récents quitte le fil de rendu. Les résultats annulés sont rejetés ; les résultats déjà affichés restent disponibles avant Spotlight.
- Observation : quatre lots AX au maximum, regroupés par application. Chaque lot conserve son ordre ; le résultat conserve l’ordre CG et les caches gardent leurs contrôles de génération.
- Restauration : une ancienne identité absente de l’inventaire CG, ou réutilisée par un autre PID, ne provoque plus une écriture impossible. Une fenêtre existante sur un autre Space reste restaurable ; l’historique n’est pas supprimé.
- Animation : la capture de destination dispose de 120 ms après l’écriture. Une destination tardive laisse finir la sortie en fondu sans relancer l’animation. Les captures sources absentes et les écritures hors budget gardent leur repli direct.
- Clavier : le rail ne peut plus devenir fenêtre clé. Le diagnostic indique une observation indisponible lorsque le champ AX initial manque.
- Journaux : une reprise ordinaire de préparation reste comptée dans `live_tick`, sans deux événements supplémentaires. Le temps d’observation cumule les essais. `resultPhase=immediate` distingue le relevé immédiat des événements finaux des écritures différées.

Le rappel critique est immédiat car son contrat synchrone annonce un focus effectif. Les bascules ordinaires de stage conservent leurs animations. Aucune option utilisateur ni dépendance ajoutée.

## Mesures et régressions

Les nouveaux tests ont échoué sur l’ancien comportement avant les changements : refus final sans compensation, placement encore différé au moment du focus, rail pouvant devenir clé, lot AX séquentiel, identités CG périmées, budget commun de capture et bruit de préparation.

Le banc de 12 applications simulées avec 20 ms de lecture par lot passe de 283 ms (pic 1) à 86 ms (pic 4). C’est un banc reproductible, pas une mesure du gain sur toutes les applications réelles. Le test ne fixe pas de seuil de durée sensible à la charge ; il vérifie la concurrence bornée et l’ordre des résultats.

- Suite finale : `./scripts/test --no-parallel`, 2560 tests dans 391 suites, succès en 68,401 s.
- Scripts : `python3 -I -B -m unittest discover -s scripts/tests`, 29 tests, succès en 11,927 s.
- Build optimisé des deux exécutables : succès.
- Aucun workflow CI lancé.

## Contre-revue

La revue indépendante a proposé une transaction atomique commune entre génération et état persistant. Le parcours réel est sérialisé sur le fil principal : le serveur de commandes appelle le routeur par `DispatchQueue.main.sync`, le contrôleur du sélecteur et le runtime des gestes sont isolés sur `MainActor`. Le rappel ne suspend pas cette exécution par `await` ni par une boucle AppKit. Les lectures de préparation en arrière-plan ne créent pas de nouvelle intention de placement.

Le contrôle d’état est déjà effectué sous le verrou de `mutateChecked`. Un écrivain externe qui modifie le fichier est détecté par l’égalité avec l’état attendu. Ajouter un second protocole de verrouillage n’est donc pas justifié par le parcours existant. Les tests couvrent la conservation d’un état changé pendant le focus et le retour arrière sans changement concurrent. Cette justification dépend du maintien de la sérialisation des commandes ; une future exécution parallèle devra revoir ce contrat.

## Limites des preuves natives

Le candidat a été installé et activé. Santé 5/5, autorisations du daemon présentes, configuration inchangée et exigence de signature identique.

Les outils de cette session n’ont pas les permissions de simulation du clavier et de capture d’écran ; l’outil natif alternatif ne possède aucune surface active. Aucun parcours clavier physique ni diaporama visuel vérifié n’est revendiqué. Le refus AX d’une application réelle et les captures WindowServer tardives restent couverts par les régressions contrôlées, sans preuve visuelle complète.

Les essais sur une application fictive n’ont pas fourni un contexte de premier plan suffisamment stable. Deux affectations ont visé une fenêtre existante ; sa stage d’origine a été rétablie et contrôlée. Aucun essai supplémentaire d’affectation n’a été poursuivi. Tous les signets et stages temporaires ont été retirés et les processus fictifs ont été fermés. Les traces brutes et sauvegardes restent hors Git.

Preuves incomplètes : captures et frappes physiques indisponibles dans cette session. Le bon état du daemon ne démontre pas à lui seul la disparition de tous les symptômes intermittents de la semaine.
