# Revue154

Revue indépendante1 en lecture seule du diff complet fourni avec base4f3694fb. Tâche c1845399-51ee-406a-a187-383157361aa0. Aucun build/test par le relecteurLinux. Résultat lu et accusé.

## Constats et traitement

1. Comparaison du zoom trop large : réduite à son identifiant de fenêtre. La génération protège les commandes concurrentes.
2. Dédoublonnage : un seul appui natif observé pour deux entrées AppKit dans l'essai avant correction ; identité complétée par le point ; timestamps inconnus acceptés. Journaliser le doublon filtré pour vérification native.
3. Test du clic : couvre le point et un clic distinct, pas seulement deux nombres temporels.
4. Retrait/changement du zoom pendant le geste : annulation voulue, couvert.
5. Lecture d'intents : une lecture par validation remplace une lecture par portée ; aucun gain CPU revendiqué.
6. Visibilité de load : le relecteur l'attribue aux tests, mais le nouvel appelant est LiveDropPreview en production. Pas de nouvelle méthode ni duplication nécessaire.

La revue confirme la cohérence de la clé scope.description et la validation avant l'effacement de l'intent par le dépôt. Le chemin natif reste à vérifier après chargement. Potentiel minimalisme : environ3 lignes, traité par la comparaison d'identifiants. Rapport original et reçu horsGit.

## Ronde2

Tâche d31df4e8-9df7-4292-b7d0-f3fc1103d57b : aucun défaut bloquant trouvé dans le patch final appliqué mentalement à la base. Les deux appelants du routeur, l'accès de load dans le module, le type des identifiants et l'ordre validation/dépôt ont été vérifiés. Les tests finaux ne figurent pas dans cette vue ; aucun test ni essai natif du relecteur. Résultat lu et accusé.

Remarque conservée : des écritures externes retirant puis remettant le même identifiant de zoom entre deux validations ne sont pas distinguées par cette seule comparaison. Les commandes Roadie invalident aussi la génération, qui reste contrôlée. Les raisons de rejet sont conservées pour répondre au besoin de diagnostic.

## Revue complémentaire du défaut Notification Center

Tâche a6e98dfd-a872-450f-9017-519b43f487d0 : lecture du patch et de deux régressions ; aucun test exécuté. Aucun blocage net pour titre, bord natif et focus. Constat moyen confirmé : le calcul d'occupation des poignées gardait l'ancien filtre. Remplacé lui aussi par le prédicat commun dans DividerResizeRuntime.

Le cadre réel enregistré est exactement celui de l'écran interne(0,0,1512,982), pas sa zone utile(0,32,1512,950). L'égalité stricte est conservée pour ne pas laisser passer un vrai panneau ; une autre géométrie de conteneur demanderait une observation avant élargissement. Les cas de panneau petit et de panneau identifié à la taille d'un écran restent bloquants en test. frontWindow sert aussi au menu contextuel du titre : même résultat voulu pour ce fond transparent. Aucun gain de performance revendiqué.

Rapports lus et accusés. Les vues distantes de revue restent sous leur garde native ; ce ne sont pas des worktrees Git locaux.

## Revue de la garde Ctrl + glisser

Tâche890203d2-7fbc-4ec6-8ff0-3cb070ccdab5, résultat lu. Lecture du patch fourni sur une vue du commit de base, sans tests Mac. La correction de fond est confirmée. Les appels qui obtiennent false annulent immédiatement la session ; le diagnostic ne boucle donc pas. Le dépôt utilise les identifiants et cadres du contexte, sans nouvel appel aux consommateurs mainHint cités par la revue.

Le risque signalé de doublons dans Dictionary(uniqueKeysWithValues:) est conditionnel. Le fournisseur produit une entrée par NSScreen, identifiée par CGDisplayCreateUUIDFromDisplayID. Aucun doublon n'est observé. La correction garde cet invariant déjà utilisé par le moteur ; elle n'ajoute pas une politique de fusion arbitraire de deux écrans homonymes. Le coût de deux petits dictionnaires reste O(d) ; aucune optimisation ni baisse CPU revendiquée.

Le test amorce le cache par sharedSnapshot avant begin ; l'échec rouge du cas frame.x et le succès du cas isMain vérifient que ce cache est utilisé. Les variantes visibleFrame seul et ajout/retrait d'écran ne sont pas exécutées séparément. La comparaison inclut ces champs et la liste des identifiants. L'absence de cache conserve le comportement antérieur.

L'accusé Bridget de cette quatrième revue a échoué avec « réponse daemon indisponible : budget JSONL dépassé ». Résultat conservé et incident signalé au mainteneur découvert par rôle, sans rejeu de la mission. Les trois autres revues avaient été accusées.
