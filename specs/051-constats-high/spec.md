# 051 - Constats HIGH restants de l'audit performance

Demande validée le 18 octobre 2026 (`/my.specify-all 1 a 4`, point 4). Dépend de la 048.

## Périmètre

Constats HIGH de l'audit du 15 octobre, relus sur le code au 18 octobre :

| Id | Constat | Statut avant 051 |
|---|---|---|
| A-02 | `kAXWindows` réénuméré pour chaque application à chaque relevé | ouvert |
| A-03 | application et bundle lus pour chaque fenêtre CG | ouvert |
| A-04 | chemins de configuration reconstruits à chaque lecture | ouvert |
| A-05 | minuterie focus-souris à 10 Hz même désactivée | partiel |
| B-01 | verrou exclusif sur `stages.json` à chaque relevé sans changement | ouvert |
| C-04 | dossier d'état surveillé pour l'enregistrement | résolu (040) |
| C-05 | relevé complet à chaque clic gauche avant le test de barre de titre | ouvert |
| C-06 | vignettes capturées rail replié | ouvert |
| D-02 | commandes exécutées en entier sur le fil principal | ouvert, assumé par l'ADR 013 |
| D-03 | relevés complets en double ou triple par commande | ouvert |

## Exigences

- R1 Un relevé lit l'identifiant d'application une fois par processus (A-03) et réutilise
  l'index AX d'une application s'il couvre toutes ses fenêtres visibles (A-02).
- R2 La lecture de la configuration ne reconstruit pas le chemin des règles générées (A-04).
- R3 Focus-souris désactivé : au plus un réveil par seconde (A-05).
- R4 Un relevé sans changement d'état ne prend pas le verrou exclusif de `stages.json` (B-01).
- R5 Un clic hors d'une barre de titre gérée ne construit pas de contexte de glisser du rail,
  donc pas de relevé sur ce chemin (C-05). Hors périmètre : la session de geste du tiler
  (`Sources/roadied/main.swift`, ancien constat A-11 MEDIUM) relève encore à chaque clic gauche
  en mode `run` ; le menu par clic droit activé relève avant son test de barre de titre (C-09).
- R6 Un panneau de rail replié ne demande pas de vignettes ; elles reprennent au dépliage (C-06).
- R7 Une commande en arbre (move, warp, resize) fait un seul relevé AX (D-03).
- R8 D-02 n'est pas changé : déplacer les commandes hors du fil principal touche
  l'architecture (ADR 013). Recommandation et décision demandées à l'utilisateur.
- R9 Comportements et budgets conservés ; suite de tests verte.

## Critères de réussite

Mesure avant/après au repos avec `specs/048-consommation-repos/mesures/mesure-repos.py` ;
comptage des relevés par commande en arbre par test ; résultats publiés avec limites.
