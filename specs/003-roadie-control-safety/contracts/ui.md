# Contrat UI : Roadie Control Center

## Barre de menus

Le menu Roadie affiche :

- statut daemon : running, stopped, degraded, unknown
- statut config : valid, reload failed, reload pending
- desktop/stage actif
- nombre de fenetres gerees
- derniere erreur si presente

## Actions obligatoires

- Ouvrir les reglages
- Recharger la config
- Reappliquer le layout
- Reveler la config dans Finder
- Reveler le repertoire d'etat
- Ouvrir les logs
- Lancer le doctor
- Quitter Roadie proprement

## Fenêtre de réglages

La fenetre settings doit permettre au minimum :

- consulter le chemin de config actif
- activer/desactiver Control Center
- activer/desactiver safe config reload
- activer/desactiver restore safety
- activer/desactiver transient system windows
- consulter les options layout persistence v2
- configurer les width presets/nudge si la story US6 est implementee

## Etats d'erreur

- Si `roadied` ne tourne pas, le menu affiche l'etat stopped et propose les actions non dangereuses.
- Si la config est invalide, le menu affiche l'erreur et conserve les actions reveal/reload.
- Si les permissions Accessibilite manquent, le menu affiche un diagnostic visible.

## Contraintes

- L'UI ne doit pas contenir de logique de tiling.
- L'UI consomme `ControlCenterState` et invoque des services/commandes existants.
- Pas d'animation de fenetres dans cette session.
