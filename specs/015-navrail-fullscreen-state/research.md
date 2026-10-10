# Research: Etat fullscreen dans le navrail

## Decision: Etat de présentation partagé

**Décision**: Introduire un état `WindowPresentationState` partagé avec les valeurs `normal`, `maximized`, `nativeFullscreen`.

**Rationale**: Le navrail doit représenter ce que l'utilisateur doit reconnaître, pas recalculer des heuristiques locales. Un état partagé évite la divergence entre `roadied run` et le runtime modulaire.

**Alternatives considered**:

- Déduire l'état directement dans `StageCardView` : rejeté, car le renderer deviendrait source de vérité et divergerait des surfaces automation.
- Ajouter seulement une icône textuelle : rejeté, car l'utilisateur a explicitement préféré une bordure et parce qu'une icône seule est moins lisible en miniature.

## Decision: `maximized` par couverture de frame tolérante

**Décision**: Classer `maximized` quand la frame de fenêtre est proche du `visibleFrame` ou du `frame` display avec une tolérance.

**Rationale**: macOS, Dock, menu bar, DisplayLink, scaling et les gaps peuvent créer quelques pixels ou dizaines de pixels d'écart. Une égalité stricte serait instable.

**Alternatives considered**:

- Egalité exacte avec l'écran : rejetée, trop fragile.
- Utiliser uniquement le bouton zoom macOS : rejeté, l'état zoom/maximized n'est pas exposé de façon fiable et les gestionnaires de fenêtres peuvent produire un maximized sans bouton zoom.

## Decision: `nativeFullscreen` prioritaire si AX l'expose

**Décision**: Lire un signal AX fullscreen natif lorsque disponible, puis le faire primer sur `maximized`.

**Rationale**: Une fenêtre native fullscreen peut couvrir la même zone qu'une maximized, mais macOS lui applique un comportement de Space différent. L'état doit donc être plus spécifique.

**Alternatives considered**:

- Traiter tout fullscreen-like comme `maximized` : rejeté, car cela masque le comportement natif macOS.
- Créer une stage spéciale native fullscreen : rejeté, car cela casserait le modèle mental validé avec l'utilisateur.

## Decision: Rendu par bordures différenciées

**Décision**: Dessiner une bordure à quatre coins pour `maximized`, et une bordure continue complète pour `nativeFullscreen`.

**Rationale**: La différence par forme est lisible sans dépendre uniquement de la couleur. Cela respecte le besoin utilisateur et les contraintes d'accessibilité visuelle.

**Alternatives considered**:

- Pictogramme `⛶` : rejeté pour v1, moins intégré à la miniature et moins clair à faible taille.
- Changement de couleur seulement : rejeté, car insuffisant pour distinguer l'état sans hue.

## Sources

- Apple Human Interface Guidelines, Windows: les fenêtres structurent les workflows multitâches et les limites visuelles du contenu applicatif. Source: https://developer.apple.com/design/Human-Interface-Guidelines/windows
- W3C WCAG 2.2 Understanding SC 1.4.11 Non-text Contrast: les indicateurs graphiques nécessaires à l'identification d'un état doivent être suffisamment discernables. Source: https://www.w3.org/WAI/WCAG22/Understanding/non-text-contrast
- Nielsen Norman Group, heuristique "Recognition rather than recall": l'interface doit rendre l'état visible plutôt que forcer l'utilisateur à le mémoriser. Source consultée via le résumé des heuristiques NN/g.

## Risques

- Certaines apps peuvent ne pas exposer `AXFullScreen` de manière fiable. Mitigation : `nativeFullscreen` est best-effort ; `maximized` reste tolérant.
- Les fenêtres native fullscreen non présentes dans le Space courant peuvent ne pas être observables. Mitigation : conserver le modèle existant et ne pas inventer de fenêtre absente.
- Une bordure trop fine serait illisible. Mitigation : utiliser une épaisseur supérieure au trait normal et un contraste suffisant.
