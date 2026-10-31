# Plan — Session 143

Swift 6, macOS 14+, AppKit, Swift Testing. Aucune dépendance.

## Réutilisation et architecture
DropPreviewEngine calcule déjà toutes les places dans un contexte figé. DropPreviewController sera le propriétaire unique de l’aperçu réel pour les glissers de titre et du rail. Le fantôme reste visible. Les miniatures de la vue d’ensemble gardent leur propre mécanisme.

Ajouter un état transitoire réversible, sans mutation de StageStore. Réutiliser InteractiveFrameDispatcher et InteractiveWritePermit (session 142) : un lot actif et un dernier lot par PID, writer AX commun et refus durables. La source tenue est exclue. Chaque nouvelle cible contient aussi le retour aux cadres initiaux des fenêtres précédemment touchées qui ne participent plus au candidat.

Les coordonnées de visée viennent toujours du contexte initial. Le contrôle du contexte compare les scopes actifs, membres, arbres et intentions avant envoi et clôture. Une nouvelle génération externe révoque la session sans restaurer des cadres obsolètes.

Fin : solde des lots borné, révocation avant commande définitive ; la commande existante reste responsable de l’affectation, des proportions et du placement final. Annulation/sortie : retour aux cadres initiaux. Échap annule le glisser. Maintien suspendu jusqu’à la clôture bornée via l’activité de glisser existante ; aucun minuteur permanent au repos.

## Réglage
`[tiling] live_drag_preview = true`. Booléen décodé avec défaut, clé validée, descripteur FR/EN. Le changement de cette seule option ne retuile pas et n’invalide pas les intentions. Lecture à chaque mise à jour ; désactivation restaure l’aperçu en cours.

## Risques et choix
Une écriture AX déjà engagée n’est pas annulable ; contrôle entre attributs et publication protégée (ADR 022). Clôture bornée pour ne pas bloquer une application lente. Un nouveau clic annule aussi un dépôt différé. Ne pas ajouter de second writer, animation synthétique ou format persistant d’aperçu. Complexité : O(w) par cible après le calcul existant ; pas de nouveau calcul par image si le candidat ne change pas.

## Vérification / gates
Tests comportementaux : on/off, exclusion source, état persistant inchangé, changement cible et restauration, fin/annulation, génération externe, application lente. Suite complète Swift et scripts. Revue indépendante avec axes concurrence, complexité, minimalisme et responsabilité future. Build Release, installation signée et santé. Parcours natif et diaporama si bureau accessible ; signaler toute limite.

Constitution : worktree de conversation dédié, branche 143 depuis 415f6804, WIP 142 conservé avec limite native explicite. Sequential Thinking absent du catalogue ; alternatives et choix ci-dessus. Pas de réseau produit, authentification ou nouvelle bibliothèque.
