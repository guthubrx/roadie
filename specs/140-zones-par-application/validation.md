# Session 140 - Zones de clics par application

**Date** : 30 octobre 2026.

- Nouvelle liste `[[switcher.zone_clicks_per_app]]` : `app` (identifiant ou nom, sans casse) et `count` (0 à 10,
  3 si absent). Paramètres > Sélecteur > « Zones de clics par application ».
- Les applications absentes de la liste prennent `zone_clicks_per_window` (valeur globale). Une application à 0
  ne crée aucune zone de clic ; une application à plus de 0 en crée même si la valeur globale vaut 0.
- `ZonePolicy.clicksPerWindow(bundleID:appName:)` (recherche O(1)) sert à la conservation (`kept`) et à
  l'enregistrement des clics (`ZoneClickRecorder`).
- Tests `Spec140ZonesPerAppTests` ; listes du catalogue et de la catégorie Sélecteur mises à jour.
- Suite complète : 2 354 tests dans 352 suites. Roadie installé, PID 17919, santé 5/5, signature roadied-cert.
- Configuration de l'utilisateur inchangée (liste vide : comportement identique à avant).
- Preuves visuelles : non produites, clics et frappes simulés refusés sur ce poste ; aucun changement d'écran
  hors de la nouvelle ligne des Paramètres.
