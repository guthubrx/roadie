# Validation 106

## Relevés avant correction

- 04:08:09 à 04:08:13 : `window.switcher_focus_failed`, `reason=restore failed`, fenêtre 638 (T3).
- Réglage `AppleSpacesSwitchOnActivate` à 0 au départ.

## Sondes jetables (hors dépôt, `/tmp/roadie-probe106/`)

Espace actif lu par `SLSGetActiveSpace`, espace de la fenêtre par `SLSCopySpacesForWindows`.

| Méthode, depuis le plein écran de Firefox (espace 200 ou 213) | Réglage | Espace après 1,5 s |
|---|---|---|
| `_SLPSSetFrontProcessWithOptions` + enregistrements « clé » (fenêtre 638) | désactivé | inchangé |
| SkyLight, même méthode, dans Roadie | activé | inchangé (`focused=false`) |
| `NSRunningApplication.activate()` | activé | inchangé |
| `NSWorkspace.openApplication` (ouverture du Dock) | activé | espace 3 en 300 ms |

Retour : Firefox a une fenêtre 498 sur l'espace plein écran 220 et une fenêtre 129 sur l'espace 3.
L'ouverture du Dock ne bascule pas (`opened=true`, `focused=false` à 04:39:54).

## Correction

1. Ouverture par LaunchServices, attente qu'AX liste la fenêtre (au plus 0,75 s).
2. Sinon, élément AX par jeton distant (`_AXUIElementCreateWithRemoteToken`), focus et AXRaise sur la
   fenêtre elle-même, attente jusqu'à 1,5 s au total.
3. Relecture de la liste du sélecteur, au plus trois fois, quand le relevé manque.

## Essai réel (utilisateur, 2026-10-28)

- 05:01:33 : Firefox plein écran natif vers T3 : `opened=true remote=false focused=true`.
- 05:01:46 : T3 vers Firefox plein écran : `opened=true remote=true focused=true`.
- 05:01:50 : de nouveau vers T3 : réussi. Confirmation utilisateur : « aller et retour ok ».

## Tests

- `Spec056ActivationTests.windowOnAnotherSpaceIsReachedByOpeningItsApplication` : repli réussi
  (stage cible active) et repli échoué (état annulé).
- Suite complète : voir le commit.

## Limites

- Le réglage macOS « passer à un espace avec des fenêtres ouvertes pour l'application » est activé
  pour l'essai. Désactivé, l'étape 1 ne change pas d'espace ; l'étape 2 n'a pas été essayée seule.
- L'ouverture par LaunchServices peut envoyer à l'application l'événement « rouvrir » ; une
  application sans fenêtre visible peut alors en créer une.
- Preuves visuelles incomplètes : bureau de l'utilisateur non capturé ; relevés et confirmation orale.
