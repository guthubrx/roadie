# CLI et réglages 061

roadie overview show : ouvrir ou relever la vue.
roadie overview toggle : ouvrir/fermer.
roadie overview hide : fermer, idempotent.
roadie overview status : état activé/configuré et disponibilité du récepteur ; la visibilité est journalisée par le contrôleur.

Aucun argument supplémentaire accepté. Les réglages persistants utilisent le service existant : table [overview], enabled/presentation/loupe/magnification/hotkey. Les commandes show/toggle/hide sont transmises au démon par notification distribuée existante. Refuser quand le composant récepteur overview est absent, via le registre ComponentLockFile partagé ; démarrage avec et sans target-mode. Raccourci vide : aucune réservation globale. BTT exécute /Users/moi/.local/bin/roadie overview toggle.
