# Research — Stage Manager Suckless

**Feature** : 001-stage-manager | **Phase** : 0 (recherche technique) | **Date** : 2026-05-01

Ce document consolide les décisions techniques prises avant l'implémentation. Toutes les zones d'incertitude soulevées dans `plan.md` Technical Context sont résolues ici.

---

## D1 — Mécanisme de masquage de fenêtre

**Decision** : utiliser `kAXMinimizedAttribute = true/false` via `AXUIElementSetAttributeValue` sur l'élément AX de la fenêtre.

**Rationale** :
- API publique stable depuis macOS 10.5 (utilisée par toutes les solutions de window management)
- Préserve la position, taille et l'espace virtuel d'origine de la fenêtre (FR-012)
- Animation Dock visible mais courte (~250 ms) — acceptable au regard de l'objectif suckless (pas de hack pour la masquer)
- Code de retour AXError clair pour le gestionnaire d'erreurs (fail loud)

**Alternatives considered** :
- *Déplacer hors écran* (`kAXPosition` à `(-10000, -10000)`) : violerait FR-012 (modifie position) et nécessiterait un état additionnel pour mémoriser l'origine. Plus de code, plus de bugs.
- *`SLSSetWindowListWorkspace`* (SkyLight privé) : déplacerait vers un Space caché, pas d'animation Dock, mais API privée non documentée, casse possible à chaque release macOS, complexité largement supérieure pour gain marginal.
- *Cacher l'app entière* (`NSRunningApplication.hide()`) : trop grossier — masque toutes les fenêtres de l'app, viole les edge cases multi-fenêtre.

---

## D2 — Identifiant fenêtre stable

**Decision** : `CGWindowID` (UInt32) obtenu via la fonction privée `_AXUIElementGetWindow(AXUIElement, &CGWindowID) -> AXError`.

**Rationale** :
- Stable pour la durée de vie de la fenêtre, indépendant du titre, position, espace, app actif
- Récupérable depuis n'importe quel `AXUIElement` représentant une fenêtre
- Récupérable inversement depuis `CGWindowListCopyWindowInfo` via la clé `kCGWindowNumber` — ce qui permet de vérifier qu'une fenêtre est toujours vivante (auto-GC, FR-006)
- Utilisé en production par yabai, AeroSpace, Hammerspoon, Rectangle, Amethyst depuis 10+ ans : stabilité empirique très forte malgré le statut privé
- Conforme au principe C de la constitution projet

**Déclaration Swift** :
```swift
@_silgen_name("_AXUIElementGetWindow")
func _AXUIElementGetWindow(_ element: AXUIElement, _ wid: UnsafeMutablePointer<CGWindowID>) -> AXError
```

L'attribut `@_silgen_name` lie le symbole sans header — Swift n'a pas besoin de bridging header. Le symbole est exporté par `HIServices.framework` (sous-framework de `ApplicationServices`).

**Alternatives considered** :
- *`(bundleID, title)`* : interdit par constitution projet (titre Terminal change en permanence).
- *`(pid, AX window index)`* : non stable (l'index change si une fenêtre est créée/fermée).
- *`AXIdentifierAttribute`* : rarement renseigné par les apps, totalement absent des terminaux.

---

## D3 — Récupérer la fenêtre frontmost (pour `assign`)

**Decision** : pipeline en 3 étapes :
1. `NSWorkspace.shared.frontmostApplication` → `NSRunningApplication`
2. `AXUIElementCreateApplication(pid)` → `AXUIElement` représentant l'app
3. `AXUIElementCopyAttributeValue(appElem, kAXFocusedWindowAttribute, &focused)` → `AXUIElement` de la fenêtre

Puis `_AXUIElementGetWindow` pour extraire le `CGWindowID`.

**Rationale** : pipeline standard documenté Apple, utilisé par tous les outils du domaine. Aucune ambiguïté.

**Edge case géré** : si `kAXFocusedWindowAttribute` retourne `nil` (cas pathologique : Finder seul actif, app sans fenêtre), l'outil affiche une erreur sur stderr et exit non nul (cf. FR-008 et US2 scénario 3).

---

## D4 — Inverse : retrouver l'`AXUIElement` depuis un `CGWindowID`

**Decision** : itération sur les fenêtres AX de l'app correspondante (récupérée via le `pid` mémorisé dans le fichier de stage), avec filtre sur le `CGWindowID` matchant.

**Pseudo-code** :
```
for each line in ~/.stage/<N>:
    pid, bundle_id, target_wid = parse(line)
    appElem = AXUIElementCreateApplication(pid)
    windows = AXUIElementCopyAttributeValue(appElem, kAXWindowsAttribute)
    for win in windows:
        if _AXUIElementGetWindow(win) == target_wid:
            AXUIElementSetAttributeValue(win, kAXMinimizedAttribute, true)
            break
```

**Rationale** :
- Direct : l'app est connue par `pid` stocké en même temps que `CGWindowID`. Pas besoin de scanner toutes les apps.
- Robuste : si l'app a été quittée, `AXUIElementCreateApplication` retourne un élément invalide → erreur AX au premier `Copy` → retrait de la ligne (auto-GC).
- Aucune API privée nécessaire pour ce pipeline (uniquement pour `_AXUIElementGetWindow` côté écriture).

**Alternative considered** : maintenir une référence directe `AXUIElement` en mémoire. Rejeté : impossible de sérialiser un `AXUIElement` entre invocations de la commande.

---

## D5 — Format de persistance

**Decision** : 3 fichiers texte plats dans `~/.stage/`.

| Fichier | Format | Exemple |
|---|---|---|
| `~/.stage/1` | Une ligne par fenêtre. Champs séparés par TAB : `<pid>\t<bundle_id>\t<cg_window_id>` | `1234\tcom.apple.Terminal\t987654` |
| `~/.stage/2` | Idem | `5678\torg.mozilla.firefox\t111222` |
| `~/.stage/current` | Un seul caractère : `1` ou `2` | `1` |

**Rationale** :
- Conforme au principe E (constitution projet)
- Édition manuelle possible avec `vi`, `nano`, `cat >>`
- Parsing en Swift : `try String(contentsOfFile:).split(separator: "\n").map { $0.split(separator: "\t") }`. ~5 lignes.
- Écriture atomique via `String.write(toFile:atomically: true, encoding:)` — garantit qu'aucune lecture concurrente ne verra un état partiel.

**Alternatives considered** :
- *JSON* : ajouterait `Codable` et boilerplate, viole principe E.
- *Plist* : verbeux, illisible à l'œil, viole principe E.
- *SQLite* : overkill total pour 50 lignes.
- *Variables d'environnement* : non persistant entre invocations de la commande (le shell ne se les passe pas).

---

## D6 — Vérification AXIsProcessTrusted

**Decision** : appel à `AXIsProcessTrusted()` au tout début de `main()`. Si `false`, afficher sur stderr les instructions Réglages Système et exit code 2.

**Message exact** :
```
stage : permission Accessibility manquante.
Ouvre Réglages Système → Confidentialité et sécurité → Accessibilité,
ajoute le binaire (chemin : <chemin absolu>) et coche-le.
```

**Rationale** :
- Pas de fallback silencieux (principe D : fail loud)
- Code 2 distingue ce cas (configuration utilisateur) du code 1 (erreur runtime)
- Pas de prompt système intempestif via `AXIsProcessTrustedWithOptions(... promptFlag: true)` : le prompt apparaît une seule fois et n'est pas reproductible. Mieux vaut documenter clairement.

**Alternative considered** : utiliser `AXIsProcessTrustedWithOptions` avec `kAXTrustedCheckOptionPrompt`. Rejeté : déclenche une popup système sans prévisibilité, bruyant.

---

## D7 — Concurrence et atomicité

**Decision** : aucune protection concurrente. L'outil est mono-utilisateur, mono-invocation, pas de daemon. L'utilisateur ne lance pas `stage 1` et `stage 2` simultanément (cas non réaliste). L'écriture atomique de Foundation suffit pour éviter la corruption en cas de Ctrl+C en plein switch.

**Rationale** : ajouter du locking violerait le principe A (suckless). Le coût d'un cas pathologique (corruption sur Ctrl+C entre lecture et écriture) est de l'ordre de "perdre la dernière modification du fichier d'état". Acceptable et facile à diagnostiquer (le fichier reste lisible).

---

## D8 — Tests

**Decision** : tests d'acceptation en shell pur, exécutés contre le binaire compilé sur une machine de dev avec environnement réel macOS.

**Stratégie** :
- Pas de mocks AX (impossible et inutile)
- Chaque test ouvre/ferme des fenêtres réelles via `osascript` (Terminal, TextEdit) puis exécute `stage` et vérifie l'état des fichiers `~/.stage/`
- Tests idempotents : setup nettoie `~/.stage/`, teardown ferme les fenêtres ouvertes
- Lancement manuel ou via `make test` — pas de CI macOS prévue (machine perso)

**Rationale** :
- XCTest demanderait un `Package.swift` ou un projet Xcode → viole principe B
- Les comportements à tester sont des effets de bord système (visibilité fenêtre) — pas testables en isolation
- Shell tests = lisibles, modifiables, debug en `bash -x`

**Couverture cible** : les 4 fichiers `tests/0[1-4]-*.sh` couvrent l'ensemble des FR (FR-001 à FR-012) et des edge cases.

---

## D9 — Build & distribution

**Decision** : Makefile minimal, binaire universal (x86_64 + arm64).

```makefile
CC      = swiftc
FLAGS   = -O -whole-module-optimization
BIN     = stage
PREFIX ?= $(HOME)/.local

$(BIN): stage.swift
	$(CC) $(FLAGS) -target x86_64-apple-macos11 -o $(BIN).x86_64 stage.swift
	$(CC) $(FLAGS) -target arm64-apple-macos11   -o $(BIN).arm64  stage.swift
	lipo -create -output $(BIN) $(BIN).x86_64 $(BIN).arm64
	rm $(BIN).x86_64 $(BIN).arm64

install: $(BIN)
	install -m 755 $(BIN) $(PREFIX)/bin/$(BIN)

clean:
	rm -f $(BIN)

test: $(BIN)
	@for t in tests/*.sh; do bash "$$t" || exit 1; done

.PHONY: install clean test
```

**Rationale** : 16 lignes, fait tout ce qu'il faut, lisible. Codesigning pas requis pour usage local. Gatekeeper bypass déjà acquis par la permission Accessibility.

---

## Synthèse des décisions

| ID | Sujet | Décision résumée |
|---|---|---|
| D1 | Masquage fenêtre | `kAXMinimizedAttribute` AX public |
| D2 | Identifiant stable | `CGWindowID` via `_AXUIElementGetWindow` privé |
| D3 | Frontmost | `NSWorkspace` → AX app → `kAXFocusedWindowAttribute` |
| D4 | CG → AX | itération bornée par `pid` du fichier de stage |
| D5 | Persistance | 3 fichiers texte TAB-séparés dans `~/.stage/` |
| D6 | Permission | `AXIsProcessTrusted` au démarrage, exit 2 si manquant |
| D7 | Concurrence | aucune protection (mono-utilisateur, atomic write Foundation) |
| D8 | Tests | shell pur contre binaire réel |
| D9 | Build | Makefile + `swiftc` + `lipo` (binaire universel) |

Aucun `NEEDS CLARIFICATION` ne subsiste. Phase 0 close.
