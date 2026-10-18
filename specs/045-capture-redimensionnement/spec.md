# 045 — Capture fiable du redimensionnement natif

Correction automatique, autorisée dans la suite de 043/044 après le test réel du 18 octobre 2026. Objectif : ne jamais perdre un geste natif parce qu'une poignée pourrait exister sous le curseur.

Trace réelle : le 18 octobre à 14:28:32 UTC, Chrome 46100 passe de y=279/h=695 à y=599/h=375 pendant l'appui, puis revient à y=279/h=695 au relâchement. Aucun geste natif ciblé n'est enregistré. Des gestes de poignée réussissent ensuite. Le garde géométrique de main.swift élimine la cible avant qu'une poignée accepte le clic ; les décorations borders bloquent aussi le picker natif.

Corriger l'arbitrage à l'acceptation effective par la poignée et partager le filtre étroit de décoration avec le picker. Conserver les vrais obstacles, le geste natif non accepté par une poignée, les minimums des applications et la priorité de la dernière intention. Pas de nouveau réglage ni dépendance. Vérifier par reproduction déterministe, tests, installation et court essai réel assisté par l'utilisateur.
