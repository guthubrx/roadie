# ADR 002 : Frontiere API publique Roadie Control & Safety

## Statut

Accepte.

## Contexte

La session 003 ajoute une surface macOS visible et plusieurs mecanismes de securite operationnelle : Control Center, reload atomique de configuration, restauration en cas d'arret ou de crash, detection de fenetres systeme transitoires, persistance layout v2 et commandes width presets/nudge.

Ces fonctionnalites touchent des zones sensibles pour un window manager macOS. Les sources Miri montrent des idees utiles, mais certaines approches comme les animations de fenetres ou les APIs privees augmenteraient fortement le risque pour Roadie.

## Decision

Roadie Control & Safety reste sur des APIs publiques :

- AppKit et SwiftUI pour le Control Center.
- Foundation pour le stockage local, les snapshots et la validation.
- ApplicationServices/Accessibility pour l'observation et les actions fenetre.
- Aucun usage de SkyLight, MultitouchSupport ou autre framework prive.
- Aucune animation de fenetre dans cette session.

Le Control Center vit dans un target Swift dedie `RoadieControlCenter`. Le daemon conserve la logique de tiling, de config, de restore et de query. Les modeles partages restent dans `RoadieCore`.

Le crash watcher est un chemin de commande separe lance explicitement par Roadie quand restore safety est active. Il observe le PID du daemon, lit le dernier snapshot de securite et applique une restauration idempotente best-effort si le daemon disparait. Il ne devient pas un LaunchAgent autonome dans cette session ; l'installation systeme durable reste hors scope.

## Consequences Positives

- Le daemon reste decouple de l'UI AppKit/SwiftUI.
- La notarisation et la compatibilite macOS restent plus simples.
- Les tests peuvent cibler les modeles et services sans lancer une UI complete.
- Les chemins de secours restent comprehensibles et idempotents.

## Consequences Negatives

- Pas d'animations ni de visuels riches de fenetres.
- Le watcher de crash depend du lancement par Roadie et ne couvre pas encore tous les scenarios d'installation systeme.
- Certaines integrations power-user devront passer par CLI/query/events plutot que par plugins natifs.
