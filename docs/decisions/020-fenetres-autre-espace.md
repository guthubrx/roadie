# ADR 020 - Atteindre une fenêtre sur un autre espace macOS

Date : 2026-10-28. Statut : Accepté.

## Contexte

Un plein écran natif crée un espace (Space) macOS séparé. Depuis cet espace, l'API
d'accessibilité (AX) ne liste pas les fenêtres du bureau ordinaire, et inversement. Le sélecteur
de Roadie ne pouvait ni trouver ni activer la fenêtre choisie (session 106).

Mesures du 28 octobre 2026 (espace actif lu par SkyLight) :

- `_SLPSSetFrontProcessWithOptions` avec le numéro de fenêtre : accepté, aucun changement d'espace ;
- `NSRunningApplication.activate()` depuis Roadie : aucun changement d'espace ;
- `NSWorkspace.openApplication` : changement d'espace en 300 ms, seulement si l'application n'a
  aucune fenêtre sur l'espace affiché, et si le réglage « Lors du basculement vers une application,
  passer à un espace avec des fenêtres ouvertes pour l'application » est actif ;
- élément AX par jeton distant (`_AXUIElementCreateWithRemoteToken`, méthode d'AltTab), puis focus et
  AXRaise : changement vers l'espace de cette fenêtre précise.

## Décision

Quand la fenêtre visée n'est pas listée par AX, Roadie :

1. ouvre l'application par LaunchServices et attend au plus 0,75 s qu'AX liste la fenêtre ;
2. sinon, construit l'élément AX par jeton distant (identifiants 0 à 999, au plus 0,3 s), le met au
   premier plan et attend jusqu'à 1,5 s au total.

Le symbole privé est résolu par `dlsym`. Absent, l'étape 2 est sautée et l'activation échoue comme
avant, avec annulation de l'état.

## Conséquences

Positives : Cmd+Tab fonctionne entre un plein écran natif et le bureau ordinaire, dans les deux sens.
L'événement `window.switcher_space_focus` indique l'étape utilisée (`opened`, `remote`, `focused`,
`waitedMs`).

Négatives : interface privée de macOS, susceptible de changer. Attente bloquante d'au plus 1,5 s sur
le fil principal pendant l'activation. Le réglage macOS cité doit être actif pour l'étape 1.
L'ouverture par LaunchServices peut envoyer l'événement « rouvrir » à l'application.

Rejeté : mise au premier plan SkyLight seule (sans effet mesuré) ; simulation de Ctrl+← / Ctrl+→
(dépend des raccourcis de l'utilisateur) ; bascule d'espace privée directe (désynchronise le Dock).
