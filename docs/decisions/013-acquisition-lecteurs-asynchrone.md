# 013 — Acquisition asynchrone des lecteurs graphiques

Date : 2026-10-18. Statut : accepté, session 042.

## Contexte
Les lecteurs graphiques peuvent lancer un scan AX depuis MainActor après expiration du cache partagé. Allonger le cache masquerait des changements réels. Le tiler et les commandes ont déjà un contrat de réconciliation synchrone.

## Décision
Ajouter une acquisition asynchrone réservée aux lecteurs. Collecter les fenêtres et leur focus AX hors du fil principal. Garder les écrans AppKit et la réconciliation sur MainActor. Partager une acquisition en cours par fichier d’état. Conserver les durées de validité existantes.

Avant de publier, contrôler la révision du cache, la configuration, le fichier d’état et la topologie. Une commande ou un producteur plus récent rend l’acquisition obsolète. Le lecteur utilise alors le relevé récent disponible, ou abandonne ce rafraîchissement et réessaie au cycle suivant. Aucun ancien relevé n’est réconcilié après ce contrôle.

## Conséquences
Les commandes explicites et le producteur du tiler gardent leur comportement. Leur déplacement hors du fil principal n’est pas inclus dans cette correction. Une acquisition de lecteur peut déjà être en cours quand le producteur démarre ; son résultat sera écarté. Les demandes de plusieurs lecteurs sont regroupées, pas les commandes. Les tests vérifient les appels, les invalidations et le fil d’exécution ; aucun gain temporel n’est annoncé.

## Protections après revue
Les caches AX associent une génération à chaque scan. Une invalidation, une réénumération de l’écrivain ou un scan plus récent interdit la publication d’un ancien index et la purge d’attributs récents. Le cache reste disponible aux processus lecteurs autonomes.

L’âge partagé part de la fin effective de l’acquisition, avant la reprise sur MainActor. Le contexte NSWorkspace du focus est préparé sur MainActor après l’inventaire ; seule sa lecture AX est déportée. Aucune multiplication des scans après timeout : les délais AX et la quarantaine restent les protections applicables.
