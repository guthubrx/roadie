# Revue indépendante 150

Task73d4dc8f-0396-48e1-bdd5-b8904e43ce75, request984a292e-3de1-4c56-9de8-dfe147ed0065, source459d653fd8df9c1ea0a94cfa0e902f3b3a69dc55. Résultat reçu et acquitté. Lecture seule, sans Git ni exécution de tests par le lecteur. Les faits du transport attestent la base exacte et le dossier propre.
Verdict : aucun défaut bloquant prouvé par lecture. Géométrie Quartz, absence d’AX pour la sélection d’écran, validation CLI et conservation de destination confirmées.

## Traitement des réserves
- R1 : la fonction pure et la CLI ne prouvent pas tout le parcours. Essais natifs réussis : fenêtre8583 vers une stage vide avec clavier sur LG et pointeur sur l’interne, puis nouvelle fenêtre9060 après fermeture de la seule fenêtre de validation. Même identifiant conservé au deuxième appui, cadre réel final confirmé.
- R2 : hypothèse de fenêtres sans scope ignorées non confirmée. preferredWindow termine par entries.first après la préférence pour les fenêtres gérées ; une fenêtre non gérée reste donc candidate. Aucun filtrage définitif par scope. Le parcours réel contrôle aussi le maintien du même identifiant.
- R3 : le repli vers activeStageScope ne s’applique pas à la destination explicite de type stage, dont stageScope renvoie toujours la valeur. Pas de défaut actuel.
- R4 : le pointeur est lu au traitement de la commande par le daemon. La destination reste ensuite conservée pendant l’attente d’ouverture. Aucune garantie d’horodatage exact à l’appui physique ni de délai absolu de file.

Le dossier distant reste conservé selon la garde Bridget. Aucun retrait forcé ; résultat acquitté et aucun travail supplémentaire demandé.
