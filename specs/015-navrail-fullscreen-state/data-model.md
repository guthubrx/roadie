# Data Model: Etat fullscreen dans le navrail

## WindowPresentationState

Représente l'état de présentation utilisateur d'une fenêtre Roadie.

### Champs

- `rawValue`: chaîne stable exposée en JSON.

### Valeurs

- `normal`: fenêtre sans état fullscreen/maximized détecté.
- `maximized`: fenêtre couvrant presque tout l'espace utile d'un display tout en restant une fenêtre Roadie normale.
- `nativeFullscreen`: fenêtre en fullscreen natif macOS ou signalée comme telle par Accessibility.

### Règles

- `nativeFullscreen` prime toujours sur `maximized`.
- Une valeur absente dans un ancien snapshot JSON se lit comme `normal`.
- Le nom exposé à l'utilisateur est `maximized`, même si certains chemins internes parlent encore de `fullscreen-like`.

## DetectionEvidence

Informations utilisées pour classifier l'état.

### Champs

- `windowFrame`: frame AX/CGWindow de la fenêtre.
- `displayFrame`: frame complète du display.
- `displayVisibleFrame`: frame utile du display, hors zones macOS réservées.
- `nativeFullscreenSignal`: booléen issu d'Accessibility si disponible.

### Règles

- La détection doit rester pure et déterministe pour un snapshot donné.
- La tolérance de frame doit accepter les écarts dus au Dock, à la barre de menu, aux gaps et aux clamps.

## NavrailWindowPresentation

Vue consommée par le renderer du navrail.

### Champs

- `windowID`: identifiant Roadie de fenêtre.
- `presentationState`: `normal`, `maximized` ou `nativeFullscreen`.

### Règles

- Le navrail ne modifie jamais cet état.
- Le navrail conserve la stage membership existante.
- Le rendu est une conséquence de `presentationState`, pas une nouvelle source de vérité.

## AutomationWindowSnapshot

Snapshot de fenêtre exposé aux agents et commandes `roadie query`.

### Nouveau champ

- `presentationState`: état de présentation de la fenêtre.

### Compatibilité

- Les consommateurs anciens qui ignorent le champ continuent de fonctionner.
- Les anciens JSON sans champ `presentationState` doivent décoder en `normal`.
