# Plan technique — Session 142

Swift 6 / macOS 14+, AppKit, Swift Testing. Aucun ajout de dépendance.

## Architecture et contrats
1. Étendre les événements de geste existants pour ouvrir une session candidate et signaler la fin. Conserver le chemin normal au relâchement si le geste n’est pas un resize géré.
2. Le runtime interactif possède une copie de l’arbre, la géométrie, l’identité/PID/scope de la cible, la génération et la configuration initiales. Les observations fraîches viennent d’une lecture ciblée hors MainActor, limitée à une lecture active. Une session n’est active que si la taille change réellement.
3. Préparer le chemin des séparations une fois. Calcul des proportions et des cadres provisoires en mémoire, sans écriture de StageStore par mouvement. Réutiliser BSPTree, BSPDivider et CommandTreeGeometry ; cache des chemins pour éviter la recherche quadratique dans le chemin fréquent.
4. Réutiliser SnapshotService et WindowFrameWriting comme point d’écriture. Ajouter une permission révocable aux lots interactifs, contrôlée entre attributs. Distribution par PID hors MainActor, une opération active et un dernier lot en attente par application. Le lot ne contient jamais la fenêtre saisie. Les vieux résultats ne republient pas l’état courant.
5. Le runtime utilise un CADisplayLink uniquement pendant le geste, avec repli de cadence borné si aucun écran n’est disponible. Les callbacks ne font ni lecture AX ni écriture disque. L’observateur AX ne relit pas les cadres sur MainActor pendant les gestes : le suivi ciblé et la vérification finale prennent le relais.
6. Au relâchement : dernière observation bornée, solde/invalidation des lots, persistance unique sous validation de l’arbre de départ. Reprise de l’ordonnanceur après cette clôture. Changement de contexte : annulation, aucune sauvegarde obsolète.

## Réutilisation de l’existant
- UserInputActivity et GestureSession : mêmes identités et événements ; aucun moniteur concurrent.
- BSPTree/BSPDivider : même géométrie et bornes de ratios, extension préparée pour le suivi natif.
- SnapshotService, AXWindowFrameWriter, WrittenFrameRegistry : même writer, budgets et protections de refus.
- TickScheduler : garde normale conservée ; attente de clôture native ajoutée au câblage.
- StageStore.mutateChecked : seule transaction finale.

## Constitution et risques
Le worktree courant est dédié à cette conversation ; branche 142 créée depuis b223718f. Les analyses non suivies de la conversation sont conservées sans ajout automatique au commit. Aucun nouveau service réseau, format persistant ou réglage utilisateur. Les callbacks restent courts. Vérifier les minima, les dimensions imposées, le plein écran, les glissers et les commandes concurrentes. La performance native exige une mesure, pas seulement une fréquence de minuteur.

## Vérification
Tests de géométrie avant implémentation, tests de permission/annulation au point d’écriture, tests du runtime avec applications lentes et fin tardive. Suite Swift et scripts. Parcours natif avec fenêtres dédiées, mesures et preuves visuelles selon la compétence applicable. Revue indépendante puis build/install signé en conservant le certificat. Aucun bump de version ni publication de release demandé.
