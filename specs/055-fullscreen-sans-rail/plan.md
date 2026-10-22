# Plan

Réutilisation : LayoutIntent.zoomedWindowID et zoomReservesRail existent.
RailController lit déjà les intents actifs pour protéger maximize ; étendre cette
lecture en partitionnant IDs du zoom avec rail et sans rail, puis transmettre
les IDs explicites à railHiddenDisplayIDs. Le masquage existant orderOut et sa
signature hidden restaurent le panneau, sans nouveau timer ni configuration.
Tester une/deux fenêtres, autre écran/stage, focus et restauration. Vérifier le
geste par tests et installation ; preuve réelle seulement si bureau accessible.
Actualiser docs FR/EN et changelog non publié, pas de nouvelle release demandée.
Revue indépendante, suite à deux tâches, installation signée puis santé.

Cas additionnel : toggle fullscreen déduisait la sortie d'après la taille seule.
Une fenêtre déjà grande sans intent doit au contraire entrer dans le mode explicite
pour cacher le rail. Ne restaurer qu'en présence du même marqueur de zoom ; garder
les transitions maximize/fullscreen et les cadres de restauration existants.
