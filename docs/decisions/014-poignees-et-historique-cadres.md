# 014 — Séparations explicites et historique des cadres

Date : 2026-10-18. Statut : accepté pour la session 043.

## Contexte
Les événements de géométrie ne donnent pas directement l'intention de l'utilisateur. Une notification d'une écriture ancienne peut arriver après une nouvelle cible. Le mode spatialBsp connaît déjà ses séparations et ses minimums.

## Décision
- Garder l'arbre binaire et le redimensionnement natif ; ajouter des prises AppKit dans les espaces libres des splits visibles.
- Placer ces contrôles dans le processus tiler/run, seul écrivain canonique. Réutiliser SnapshotService et les transactions StageStore.
- Figer l'inventaire du geste. Les mouvements remplacent une seule cible en attente. Un minuteur applique au plus 20 cibles par seconde et le relâchement applique la dernière. Aucun scan AX dans mouseDragged.
- Annuler la cible en attente si le stage, l'arbre, la configuration ou la topologie ne correspond plus au contexte. Les modifications déjà validées restent persistées.
- Garder un historique récent de 32 cadres au plus par fenêtre, pendant 1,5 seconde. Séparer reconnaissance d'écho et confirmation de refus ; ne pas absorber un événement durant un appui souris.
- Préserver générations, budgets et confirmation par observation fraîche. Corriger seulement les conflits de refus reproduits dans les tests.

## Conséquences
Le geste désigne une séparation stable et passe par le même écrivain AX que les commandes. L'historique a un coût borné par événement. Le réglage de visibilité ne retuile pas les fenêtres. Le placement AX reste synchrone hors mouseDragged ; son passage en arrière-plan appartient à une autre évolution.

L'accès au bureau n'est pas garanti dans cet environnement. Les tests du modèle et de la frontière AppKit ne remplacent pas une vérification visuelle réelle ; la livraison précise cette limite. Aucun gain de performance n'est annoncé sans mesure.
