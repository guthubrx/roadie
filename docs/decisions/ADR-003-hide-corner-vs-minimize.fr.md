# ADR-003 — Stratégie de masquage : coin écran (vs minimize, vs Spaces)

🇫🇷 **Français** · 🇬🇧 [English](ADR-003-hide-corner-vs-minimize.md)

**Date** : 2026-05-01 | **Statut** : Accepté

## Contexte

Le stage manager (plugin opt-in) doit pouvoir masquer les fenêtres d'un stage non-actif sans les perdre, et les restaurer fidèlement à la bascule.

Options :

1. **yabai-style** : utiliser les Spaces macOS. Chaque stage = un Space. Bascule = `yabai -m space --focus N` via scripting addition. Nécessite **SIP partiellement off**.

2. **AeroSpace-style** : déplacer les fenêtres hors écran, à `(-100000, -100000)`. Conserver leur frame d'origine en mémoire pour restauration. Pas de Spaces, pas de SIP.

3. **stage SPEC-001** : minimisation native via `kAXMinimizedAttribute = true`. Pas de Spaces, pas de SIP, mais animation Dock visible et yabai/JankyBorders ré-tilent à la dé-min (clignotement vu en SPEC-001).

## Décision

**Option 2 (coin écran) en stratégie principale**, avec **option 3 (minimize) disponible via config** pour les utilisateurs qui préfèrent.

Justification :
- Option 1 exclue par FR-005 (pas de SIP désactivé).
- Option 2 = AeroSpace, validée 2 ans en prod, pas de clignotement parce que les fenêtres restent dans la même Space sans changement d'état AX significatif.
- Option 3 fournie en fallback configurable car certains utilisateurs préfèrent l'animation Dock pour avoir une indication visuelle.

Limitation **identifiée** d'option 2 : les fenêtres déplacées en coin restent dans la liste Cmd+Tab. AeroSpace original ignore ce problème ; nous ajoutons un mode `"hybrid"` (corner + minimize natif) en option pour mitiger.

## Spécification HideStrategy

```swift
enum HideStrategy: String, Codable {
    case corner    // déplace à (-100000, -100000), sauvegarde la frame
    case minimize  // kAXMinimizedAttribute = true
    case hybrid    // corner + minimize (résout Cmd+Tab)
}
```

## Conséquences

### Positives

- **Bascule rapide** (~50 ms par fenêtre AX setPosition vs ~250 ms animation minimize).
- **Pas de SIP** requis.
- **Pas d'interférence** avec d'autres tilers en cours (yabai/AeroSpace ne tournent pas en parallèle de toute façon).
- **Configurable** : l'utilisateur choisit son trade-off Cmd+Tab.

### Négatives

- Mode `corner` = fenêtres "ghost" dans Cmd+Tab. Acceptable pour beaucoup d'utilisateurs (idem AeroSpace).
- Mode `hybrid` ajoute la latence minimize (250 ms) et l'animation Dock pour les fenêtres masquées. À évaluer empiriquement.

## Alternatives rejetées

- **Suppression / ré-ouverture** des fenêtres : casserait l'état applicatif (documents non sauvegardés, etc.). Inacceptable.
- **Hidden Space créé à la volée** : nécessiterait CGSGetSpaces (privé), proche de SkyLight, hors scope V1.

## Références

- AeroSpace : `Sources/AppBundle/tree/MacWindow.swift` — `hideInCorner` / `unhideFromCorner`
- yabai : `src/space_manager.c` — `space_manager_set_active_space`
- SPEC-001 : `stage.swift` cmdSwitch (minimize natif)
- research.md §3 (stratégies masquage)
