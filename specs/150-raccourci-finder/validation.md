# Validation 150 — en cours

Le raccourci initial26E8B454-8377-472B-9451-C6B982D74B9C appelle Open Finder. Une sauvegarde SQLite cohérente et le JSON des déclencheurs sont conservés hors Git. Le nouveau raccourci68ADABA4-8B3B-4DCC-8A63-0A1FE4860884 est dans le dossier global1001CD77-41C6-474A-B3D3-3C24F4B19153.
Le premier essai crée Finder8583 (aucune fenêtre Finder auparavant). Le second conserve le même identifiant, sans fenêtre supplémentaire. L’adaptateur initial a néanmoins révélé la course de focus documentée dans plan.md ; il est remplacé par une option native. Les essais initiaux ne valident donc pas la destination finale.
Tests de la correction native en cours. Aucune frappe physique simulée ni permission modifiée.


## Tests de source
Les2tests ciblés réussissent. Ils couvrent une stage vide sur l’autre écran, un autre bureau affiché, une origine verticale négative, le bord entre écrans, une position hors écran et un état sans scope. Les combinaisons CLI ambiguës sont refusées avant toute ouverture.
La suite complète réussit :2461tests dans373suites, exécution séquentielle,59,031s. Les530empreintes Sources/Tests sont enregistrées avant la compilation signée.
Le générateur de preuves fonctionne avec /usr/bin/python3 (Pillow disponible). Le Python par défaut3.15 n’a pas Pillow ; aucun paquet global n’a été installé.
La revue est admise sur459d653fd8df9c1ea0a94cfa0e902f3b3a69dc55 : request984a292e-3de1-4c56-9de8-dfe147ed0065, task73d4dc8f-0396-48e1-bdd5-b8904e43ce75, child03917654-ad69-47b8-8cc0-a02cc38979f4, message410f0a68-007d-4905-ad88-7abff4b4234f. Posture discovery et dossier privé, choix des axes par Bridget. Aucun verdict anticipé.


## Activation et parcours finaux
Application signée installée puis chargée : UUID DA4F188C-6530-3377-8E48-651BC315E227, PID12688.530empreintes de compilation inchangées ; TOML identique au fichier avant opération. Santé5/5 après démarrage et après parcours. Le socket n’était pas encore disponible au tout premier contrôle pendant le démarrage ; aucun redémarrage supplémentaire nécessaire.
Raccourci global68ADABA4-8B3B-4DCC-8A63-0A1FE4860884 : Commande+E, deux indicateurs d’activation à1, touche14, modificateur1048576, adaptation du clavier activée. Commande directe : /Users/moi/.local/bin/roadie launch /System/Library/CoreServices/Finder.app --here --mouse. Ancien raccourci26E8B454-8377-472B-9451-C6B982D74B9C retiré par API après sauvegarde et succès de la nouvelle action. Un seul identifiant ⌘E global actif relu dans get_triggers, occurrences imbriquées dédupliquées.

Parcours natifs via execute_assigned_actions_for_trigger :
1. PointeurQuartz1148,25;0 sur l’écran interne, clavier sur LG. Stage3 vide du bureau3 affichée sur l’interne : fenêtre Finder8583 ramenée dans cette stage, même identifiant,214ms observées.
2. Deuxième exécution : toujours8583, une seule fenêtre,260ms.
3. Fermeture de cette seule fenêtre de validation créée par le parent. Nombre de fenêtres Finder confirmé à0. Clavier sur LG, souris inchangée sur l’interne : nouvelle fenêtre9060 affectée à la même stage vide en998ms.
4. Stages affichées restaurées. Fenêtre9060 ramenée dans la stage initiale sous la souris,699ms. Le cadre réel lu dans Finder correspond au cadre persistant à3points près. Aucune autre fenêtre fermée, aucune permission changée.
Le premier lancement du pilote s’est arrêté sans mutation : la souris avait changé d’écran et la stage1 de cette cible était occupée. Le pilote sélectionne ensuite une stage vide existante, sans supposer son numéro. Ce n’était pas une défaillance du correctif.

La revue indépendante ne prouve aucun défaut bloquant. Sa demande de parcours natifs R1 est satisfaite par ces essais. R2 est une hypothèse écartée à la lecture : preferredWindow garde entries.first en dernier repli, même sans scope. R3 ne s’applique pas aux destinations stage explicites. R4 est une limite assumée : souris lue au traitement de la commande par le daemon, destination conservée pendant l’ouverture.

Preuves incomplètes : diaporama autonome relu, contrôles et parcours réels consignés, mais pas d’appui physique ⌘E enregistré ni de capture des contenus privés de Finder. Les commandes API de BTT exécutent la vraie action assignée ; elles ne prouvent pas le trajet physique de la touche. Les durées sont celles de ces essais, sans garantie générale.
