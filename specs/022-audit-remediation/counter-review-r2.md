# Contre-revue round 2 (GPT-6-Astra, Codex) - verdict REJECT

Périmètre : jusqu'à `8f331531`. 1064 tests verts. Les 34 corrections validées au round 1 tiennent ;
aucun interblocage du verrou `roadied.local.lock` (une commande locale de plus de 10 s fait échouer
le démarrage du daemon : comportement voulu du délai borné). 7 constats, aucun HIGH.

| ID | Sév. | Fichier | Problème | Correction attendue |
|----|------|---------|----------|---------------------|
| R2-01 | MED | `WindowCommands.swift:607`, `StageCommands.swift:1006`, `LayoutCommandService.swift:44` | Échec annoncé après modification effective : l'entrée en zoom masque les voisines avant `saveChecked` (pas de retour arrière) ; `setMode` enregistre le mode avant de supprimer l'intent (la suppression peut échouer après) ; `balance` exécute tout le `map` avant de chercher un refus. | Persister les décisions avant les effets AX ; échec tardif = restauration ou résultat partiel explicite ; `balance` s'arrête au premier refus. |
| R2-02 | MED | `AppTargetQueryService.swift:832` | La revalidation suit des indices d'enfants : un autre élément au même indice et au même cadre passe. Elle contrôle `target.frame` alors que le clic peut viser `target.clickFrame`. | Identité stable de l'élément pendant la session (référence AX) ; revalider la zone réellement cliquée ; tests remplacement à cadre identique et contenu déplacé dans un parent immobile. |
| R2-03 | MED | `AppTargetQueryService.swift:854` | La relecture peut cumuler des délais AX sur le fil principal : après un échec (même `cannotComplete`), `child` appelle `copyChildren(boost: true)` (7 attributs de plus) sans échéance globale ; seconde énumération des fenêtres après le contrôle du focus. | Abandon immédiat sur dépassement AX, échéance globale, réutiliser la fenêtre déjà résolue ; mesurer le délai validation → clic. |
| R2-04 | MED | `EventSubscriptionService.swift:147` | Rotation concurrente pendant la collecte des générations : descripteurs `[B, B, A]`, B lu deux fois. | Ensemble cohérent de générations (sous verrou de rotation si possible) ; dédupliquer les inodes ; test de rotation pendant la collecte. |
| R2-05 | LOW | `BorderController.swift:232` | Pastille de groupe sans borne de largeur : sur une fenêtre étroite, origine négative, le fond couvre la fenêtre. | Borner la largeur, tronquer le libellé sur une ligne. |
| R2-06 | LOW | `CLICommandRouter.swift:270` | Le marqueur « not visible » est cherché dans tout le message : `stage create "not visible"` répété sort en 1. | Statut d'échec explicite, ou diagnostic reconnu sans analyser les valeurs utilisateur. |
| R2-07 | LOW | `StageCommands.swift:326` | Helper privé `persistenceFailure` qui relaie seulement le constructeur statique homonyme. | Appeler directement `.persistenceFailure` (~4 lignes). |
