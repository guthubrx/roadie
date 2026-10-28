# Spec 106 - Sélecteur depuis et vers un plein écran natif

Date : 2026-10-28. Type : correction.

## Problème

Dans Firefox en plein écran natif, Cmd+Tab vers T3 Code affichait « Action refusée par
l'application » et « 0 fenêtres ». Le retour de T3 vers le plein écran de Firefox échouait aussi.

Cause : un plein écran natif est un espace (Space) macOS séparé. Depuis cet espace, AX ne liste pas
les fenêtres du bureau ordinaire, et inversement. Roadie ne trouvait pas la fenêtre choisie,
annulait l'activation (`restore failed`) et rouvrait le sélecteur. La relecture qui suivait
l'annulation n'obtenait pas de relevé (`snapshot=none`) : la liste s'affichait vide.

## Exigences

- E1. Cmd+Tab d'un plein écran natif vers une fenêtre du bureau ordinaire l'affiche et la met au
  premier plan.
- E2. Cmd+Tab du bureau ordinaire vers une fenêtre en plein écran natif revient sur son espace, même
  si l'application a une autre fenêtre sur le bureau ordinaire.
- E3. Un relevé absent après un échec n'est pas montré comme une liste vide.
- E4. Un échec reste annulé sans perte de l'état écrit par une autre commande (comportement SPEC-056).

## Hors périmètre

- Changer d'espace quand le réglage macOS « Lors du basculement vers une application, passer à un
  espace avec des fenêtres ouvertes pour l'application » est désactivé (voir ADR 020).
- Les bureaux Roadie, distincts des espaces macOS.
