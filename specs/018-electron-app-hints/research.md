# Research: Lettres d'accès dans les applications Electron

## Preuve de la cause

`~/.roadies/events.jsonl`, 2026-10-12 18:37 UTC : trois sessions `targets.interactive` dans T3 Code (pid 60116). Chaque fois, `targets.list` donne `count=44`, `partial=false`, et la seule cible applicative activée est `app:60116/0`, soit la fenêtre racine. Le parcours a fini dans son budget et n'a rien trouvé sous la fenêtre.

T3 Code embarque `Contents/Frameworks/Electron Framework.framework`.

## Decision: activer `AXManualAccessibility`

**Rationale**: Electron n'active son arbre d'accessibilité que pour VoiceOver ou sur demande explicite via `AXManualAccessibility` sur l'élément application. C'est l'API documentée par Electron pour les outils d'assistance tiers. Vimac et homerowless font de même. L'attribut renvoie `kAXErrorAttributeUnsupported` sur une application native, sans effet.

Sources :
- https://www.electronjs.org/docs/latest/tutorial/accessibility
- https://github.com/electron/electron/pull/10305
- https://github.com/nchudleigh/vimac/issues/78
- https://github.com/connerohnesorge/homerowless (« la première activation peut prendre ~150 ms »)

**Alternatives considered**:
- `AXEnhancedUserInterface` : réservé à VoiceOver, anime les déplacements de fenêtres, et la spec 017 le neutralise pendant l'écriture des cadres. Rejeté.
- Demander à l'utilisateur d'activer l'accessibilité dans chaque application : rejeté, T3 Code n'a pas ce réglage.

## Decision: détecter Electron par le bundle, pas par le code retour

**Rationale**: l'issue Electron #37465 signale des versions où l'écriture répond `kAXErrorAttributeUnsupported`. Le code retour ne prouve donc pas l'effet. La présence de `Contents/Frameworks/Electron Framework.framework` dans `NSRunningApplication.bundleURL` est stable et ne coûte qu'un accès disque.

**Alternatives considered**:
- Liste de bundle IDs : rejetée, à maintenir à la main.
- Relancer pour toute application qui ne montre que sa fenêtre : rejeté, ajoute une attente aux applications natives vides (FR-003).

## Decision: relance bornée sans état

**Rationale**: Chromium construit l'arbre de façon asynchrone après la demande. Règle : si l'application est Electron, que le parcours est complet (ni coupé par la profondeur, le temps ou la limite) et qu'aucune zone web (`AXWebArea`) n'a été lue, attendre 150 ms puis relancer, au plus deux fois. Sans cache par pid : une application déjà publiée montre sa zone web et ne relance pas. Attente ajoutée : 300 ms au plus.

**Correction d'après mesure (2026-10-12)** : la première version relançait si le parcours trouvait au plus 1 candidat. Mesure réelle dans T3 Code juste après l'activation : 4 candidats (boutons de fenêtre), 13 éléments lus, profondeur 6, parcours complet, aucune relance. Les boutons natifs de la fenêtre existent avant le contenu web : le nombre de candidats ne distingue pas « arbre vide » et « arbre publié ». La présence d'`AXWebArea` le fait.

**Alternatives considered**:
- Cache des pids déjà activés : rejeté, état en plus pour un gain nul (la règle se base sur le résultat).
- Activation proactive au changement d'application : rejetée pour l'instant, plus de code et d'appels ; à reconsidérer si la mesure montre une première session trop lente.

## Decision: ne pas désactiver après le parcours

**Rationale**: Vimac et homerowless laissent l'attribut actif. Le désactiver forcerait l'attente à chaque session. Coût : Electron maintient son arbre, avec un peu plus de CPU. Le levier existant `ax_boost_enabled` coupe le mécanisme.

## Decision: filtrer sur le cadre de la fenêtre

**Rationale**: dans une application web, l'arbre contient le contenu défilé hors de la vue. Le clic Roadie est un clic souris au centre du cadre (`postClick`). Un élément hors de la fenêtre ferait cliquer une autre fenêtre. Ces éléments consomment aussi `max_targets`.

## Decision: statistiques dans le rapport existant

**Rationale**: `AppTargetQueryReport` est déjà rendu à `TargetHintService.list`, qui écrit `targets.list`. Un champ optionnel `scan` et un événement `targets.app_scan` suffisent. La profondeur réelle de T3 Code et le coût par élément seront lus dans cet événement, puis serviront à régler `max_depth` et `timeout_ms` (Article XXII).

## Hors périmètre

- Lecture groupée des attributs (`AXUIElementCopyMultipleAttributeValues`) : optimisation possible si la mesure montre `stopReason=timeout`. À décider avec les chiffres.
- Navigateurs Chromium (Chrome).

## Decision: pas de demande à l'activation de l'application (mesure du 2026-10-12)

**Essai** : demande `AXManualAccessibility` dès `didActivateApplicationNotification`, une seule demande par processus.

**Mesure** (draw.io lancé, aucune autre demande) : zone web absente à 3, 6, 10 et 15 s. Une demande faite pendant le lancement peut être ignorée ; sans redemande, l'application reste vide. Avec une demande à chaque session, la zone web apparaît à une session suivante (t0 + 2,9 s et t0 + 8 s observés).

**Decision** : redemander à chaque parcours, sans cache. Code d'activation retiré (régression mesurée, gain non mesuré ; disjoncteur Article IV après 3 tentatives sur la première session).

**Limite assumée** : la toute première session après le lancement d'une application Electron peut ne montrer que la fenêtre. Le délai de construction observé varie de moins de 3 s à plus de 15 s ; une relance courte ne le couvre pas.

## Decision: réglage `max_depth = 30`, `timeout_ms = 250`

**Mesure** : contenu web de T3 Code à profondeur 15-18 ; ~0,6 ms par élément ; 150 cibles en 119-178 ms. `timeout_ms = 400` faisait attendre Finder 407 ms sans gain pour T3 Code.
