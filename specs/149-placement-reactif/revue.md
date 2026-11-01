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


## Ronde 2 — reprises et échéances
Source a5be1985f4eb904a7c09ba3437bd45771dbf42f7. Request95f1c082-efc6-4fa6-a6c9-27635070e769, taskd81efce2-1989-4c5f-9a93-e246d6e7641a, child4375aab4-8940-4eed-970c-2f18d19aff81, message308a3792-0f78-48c5-8888-d237df65966b. Résultat11241octets reçu et acquitté. Lecture seule, sans exécution de tests.
- Les protections Mission Control et observation périmée sont confirmées.
- Deux constats confirmés en rouge : reprises non espacées après invalidation et échéance perdue. Correction dans970cdab : délai progressif plafonné à2s, demande conservée et journalisation bornée. Les tests contrôlent moins de15lectures en10s et la reprise.
- Un appel AX déjà lancé reste non interruptible. Son résultat annulé est rejeté. Aucun arrêt forcé du système.

## Ronde 3 — capture clavier et source corrigée
Source970cdab59ff1d97bb5885942ab8986ab1a767fe5. Request6cbe528a-8ef2-449b-9628-bb2a2696c749, taskfd13cdc0-62d2-4542-a38c-242562c09f7a, child0a4a30e9-25e3-4435-9929-e8246cf13a06, message3cb3b6d8-2f54-4a65-9c76-0856b5125ee0. Résultat6158octets reçu et acquitté. Confirmation bornée sans défaut bloquant, sans shell ni tests exécutés par l’enfant.
- Reprises bornées, révocation des contextes et nettoyage commun des trois captures confirmés.
- Une tâche clavier déjà en file peut conserver la session fermée. Constat confirmé à la lecture : la grille appelait show sans vérifier finished. Le callback commun revérifie désormais finished juste avant handle, sur MainActor.
- L’attente maximale de2s après rejets répétés est documentée dans ADR025. Le daemon continue à observer à fréquence réduite si le contexte reste instable ; cette continuité est voulue.
- Une entrée faible abandonnée renvoie nil sans retenir son propriétaire. Les sessions normales appellent le nettoyage commun.

Les trois revues emploient des worktrees discovery exacts et propres. Les trois résultats sont acquittés, continuable=false. Les worktrees distants restent conservés avec retention=review_required ; aucun outil de retrait de ces dossiers n’est exposé. Aucune suppression forcée ni nouvelle mission créée pour contourner cette garde.
