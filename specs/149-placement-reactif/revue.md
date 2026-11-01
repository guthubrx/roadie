# Revue indépendante 149 — ronde 1

Task555234cc-c2b0-43e1-a847-3bb6a4e97ee3, requestb74e6949-7bb6-434a-9e5b-4251c135b3d4, source d2a1cd556319717804903db01243687b3f0e6b24. Résultat9854octets reçu et acquitté. Revue partielle en lecture seule : pas de shell ni de tests exécutés par l’enfant, certains artefacts non lus. Les faits Git Bridget attestent HEAD/base exacts et worktree propre, contrairement au niveau de vérification déclaré par le lecteur.

## Décisions sur les constats
1. Mission Control : confirmé par un test rouge. Cinq préparations lançaient cinq relevés. La préparation laisse désormais la passe courte gérer pause, stabilisation et reprise, sans acquisition AX. Le contrôle isCurrent est aussi fait avant toute acquisition.
2. Événement pendant une acquisition : confirmé par un test rouge. Le producteur exige maintenant la même génération d’observation à la publication. Une notification nouvelle fait rejeter le relevé, tandis que la demande reste en attente dans l’ordonnanceur. Les lecteurs graphiques gardent leur comportement existant.
3. Annulation : borne physique explicite. Une opération AX déjà partie n’est pas interruptible par Task.cancel. Le travail finit en arrière-plan, sans bloquer MainActor ; aucun résultat annulé ne peut être publié ou sauvegardé. Ne pas annoncer une interruption forcée de l’appel système.
4. Appels AX de création/abonnement : limite existante confirmée à la lecture. Les fenêtres inconnues et les abonnements initiaux conservent des appels directs ; les lectures de cadre des fenêtres suivies et les acquisitions périodiques sont les chemins corrigés et mesurés. Aucune promesse de suppression de tous les appels AX du fil principal.
5. JSON périodique : opérations locales conservées sur MainActor pour l’état cohérent et l’écriture atomique. Aucun ralentissement de secondes attribué à ce travail ; le relevé AX coûteux, lui, est hors fil principal.
6. Latence des événements : la fenêtre concernée attend sa propre lecture, comme auparavant, avec coalescence. Les autres fenêtres et la saisie ne sont plus retenues par cette attente. Les échecs de lecture transmettent une notification sans faux cadre.
7. Résultat périmé : publication rejetée volontairement. Le registre est géré au point d’écriture AX, avec permis et génération ; aucun callback ancien ne doit republier un ancien cadre. Pas de défaut nouveau reproduit sur ce point.
8. Préparation consommée ailleurs : seul propriétaire de production = ordonnanceur ; acceptation et consommation se succèdent sur MainActor sans attente. Pas d’autre appelant en production dans le code lu.

Deux régressions rouges dans Spec149ReviewTests, puis47tests ciblés verts. Une nouvelle ronde relira les deux corrections et ces décisions ; aucun verdict favorable indépendant inventé.

Un troisième test rouge reproduit la fermeture de Mission Control entre la préparation et la passe : une lecture AX partait encore. La préparation mémorise maintenant son observation de Mission Control avant de rendre la main ; la grâce de stabilisation reste donc active même si le second contrôle voit déjà Mission Control fermé. Cette correction accompagne les deux constats confirmés.
