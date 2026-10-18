# Validation — session 041

## Tests

Le test AppKit a d’abord échoué sur l’absence de cartes à la destination (avant correction). Après correction : 16 tests ciblés, dont 12 combinaisons de mode et d’alignement ; comparaison de la géométrie de l’aperçu avec le rendu réel après reorderStage. Première suite complète : 1 613 tests / 189 suites réussis. Suite finale après revue : 1 614 tests / 189 suites réussis.

Les tests couvrent les modes icônes, mosaïque, empilé et perspective ; l’alignement haut, centre et bas ; les hauteurs différentes ; les stages nommées vides et les places cachées ; le cache de l’aperçu à destination inchangée ; les hit-tests originaux ; la sortie du panneau, l’annulation et un nouveau rendu.

## Revue indépendante

Mission Bridget 416b380c-ac99-48b7-bb4b-b714fd0295d6, demande roadie-041-preview-review-1. Revue en lecture seule, sans shell ni écran. Aucun défaut bloquant relevé. Le diff a été relu localement par le responsable.

- Fondu des légendes : le rafraîchissement des copies a été ajouté pendant la revue. Test de propagation ajouté.
- Second appui droit sans relâchement : nettoyage explicite d’un geste déjà ouvert avant le nouveau geste.
- Modes et stages vides : couverts par les 12 combinaisons ajoutées pendant la revue. Rendu des numéros futurs et noms personnels comparé pixel par pixel à une carte de référence.
- Annulation : le prochain timer reprend les mises à jour reçues pendant le geste. Ce délai préexistant reste inchangé.
- Dépôt au rang actuel : garde le comportement préexistant ; aucune nouvelle écriture pendant l’aperçu.

## Preuves visuelles

Preuves incomplètes : CUA renvoie « CUA_REPL_ENABLED_SURFACES is required » et screencapture « could not create image from display ». Aucun geste réel ou capture du bureau n’est attesté. Les tests AppKit construisent le panneau réel avec des données fictives et comparent géométrie, cibles et pixels des légendes. Ils ne remplacent pas la vérification visuelle sur le bureau. Aucun diaporama n’est fabriqué.

Journaux locaux : /Users/moi/.roadies/diagnostics/2026-10-18-session041/.

## Aimantation ajoutée sur demande

Choix utilisateur : stabiliser la destination sans attirer le curseur. Réglage de 0 à 100 %, défaut 50, dans Paramètres > Rail. Tolérance proportionnelle à l’intensité, bornée par l’espacement des destinations. Le dépôt lit la position stabilisée avant de retirer l’aperçu.

Reproduction avant correction : 72 assertions en échec sur les 12 variantes lors d’un mouvement de deux points autour du seuil. Après correction : 26 tests ciblés réussis. Tests additionnels : intensités 0/50/100, déplacement dans les deux sens et saut distant, bornes du parseur, modification persistée depuis SettingsService et trois appels au rechargement. Le catalogue comporte 80 réglages simples pour le rail, dont 49 numériques.

Suite complète avec aimantation : 1 616 tests / 189 suites, zéro échec.

Revue complémentaire 339955bd-d3b7-403e-9932-283f02b96235 : aucun risque bloquant. Remarques traitées : test comportemental du rechargement du même RailPanel à 0 puis 100, descente depuis la première position et commentaire du catalogue corrigé. Les 22 tests ciblés passent après ces ajouts. Aucun changement de production après la suite complète de 1 616 tests ; les empreintes du code compilé le confirment.

## Installation

18 octobre 2026 : compilation Release et installation terminées. Signature vérifiée et certificat conservé : 78a75e8032f190a20072eb91cc2919aac344ef78. UUID du daemon installé : 3533388F-83B1-3F5A-995C-B525D7656291. Application : /Users/moi/Applications/Roadie.app ; CLI : /Users/moi/.local/bin/roadie.

Redémarrage confirmé, PID 83654. Les quatre contrôles de santé sont OK, Accessibilité et configuration valides. Le premier appel a précédé l’ouverture de la socket au démarrage ; le contrôle après initialisation réussit. `roadie rail status` confirme `stages.reorder_magnetism=50.0`. Configuration personnelle inchangée. Aucun numéro de version ni release publique ajouté.
