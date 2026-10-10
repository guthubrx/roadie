# Quickstart: Etat fullscreen dans le navrail

## Préparer

```bash
./scripts/test --filter WindowPresentationStateResolverTests
./scripts/test --filter AutomationSnapshotTests
./scripts/test --filter PowerUserFocusCommandTests
```

## Vérifier `maximized`

1. Lancer Roadie en mode modulaire.
2. Ouvrir une fenêtre dans une stage Roadie.
3. Maximiser la fenêtre sans fullscreen natif macOS.
4. Vérifier que la fenêtre reste dans la même stage du navrail.
5. Vérifier que sa vignette affiche une bordure à quatre coins.
6. Vérifier l'état automation :

```bash
./bin/roadie query state --json
```

La fenêtre doit avoir :

```json
"presentationState": "maximized"
```

## Vérifier `nativeFullscreen`

1. Mettre une fenêtre en fullscreen natif macOS.
2. Vérifier que le navrail reste visible si macOS permet son affichage dans ce Space.
3. Vérifier que la vignette affiche une bordure continue.
4. Vérifier l'état automation :

```json
"presentationState": "nativeFullscreen"
```

## Vérifier la parité monolithique/modulaire

1. Lancer `roadied run --yes`.
2. Capturer `./bin/roadie query state --json`.
3. Relancer via le script modulaire.
4. Capturer à nouveau `./bin/roadie query state --json`.
5. Comparer les `presentationState` des mêmes fenêtres observables.

## Vérifier l'absence de relayout induit

Pendant les étapes précédentes, surveiller :

```bash
tail -f ~/.roadies/events.jsonl
```

Le simple affichage d'un état `maximized` ou `nativeFullscreen` ne doit pas produire de `layout_apply` ou de commande de relayout nouvelle.
