# Guide Rapide : Menu Contextuel de Barre de Titre

## 1. Activer l'experiment

Dans `~/.config/roadies/roadies.toml` :

```toml
[experimental.titlebar_context_menu]
enabled = true
height = 36
leading_exclusion = 84
trailing_exclusion = 16
managed_windows_only = true
tile_candidates_only = true
include_stage_destinations = true
include_desktop_destinations = true
include_display_destinations = true
```

Puis :

```bash
roadie config validate
roadie config reload
```

## 2. Verifier la non-interference

1. Ouvrir une application avec menu contextuel dans le contenu.
2. Faire clic droit dans le contenu.
3. Verifier que Roadie ne montre pas son menu.
4. Faire clic droit dans la zone haute de la fenetre.
5. Verifier que Roadie montre son menu seulement si la fenetre est eligible.

## 3. Tester les destinations

Depuis le menu Roadie :

- envoyer la fenetre vers une autre stage ;
- envoyer la fenetre vers un autre desktop Roadie ;
- envoyer la fenetre vers un autre ecran.

Resultat attendu : seule la fenetre cible bouge, sans changement non demande des autres fenetres.

## 4. Ajuster la zone

Si le menu apparait trop bas dans une app :

```toml
[experimental.titlebar_context_menu]
height = 28
```

Si le menu gene les boutons de fenetre ou de toolbar :

```toml
[experimental.titlebar_context_menu]
leading_exclusion = 96
trailing_exclusion = 48
```

## Validation developpeur

```bash
./scripts/with-xcode swift test --filter TitlebarContextMenuTests
./scripts/with-xcode swift test --filter ConfigTests
make build
```

Resultats locaux :

- `TitlebarContextMenuTests` : 8 tests OK.
- `ConfigTests` : 14 tests OK sur le filtre, incluant les tests de configuration experimentale.
- `make build` : OK.

## Scenarios manuels

- iTerm2 : clic droit titlebar affiche le menu ; clic droit terminal reste a iTerm2.
- Finder : clic droit titlebar affiche le menu ; clic droit contenu reste a Finder.
- Firefox/Chromium/Electron : valider que Roadie privilegie l'absence de menu si la zone est ambigue.
- Popup/dialogue systeme : aucun menu Roadie.

## Matrice de validation SC-001

Pour mesurer le critere "95% des essais sur les fenetres standard testees", utiliser au minimum 20 essais repartis ainsi :

| Application | Essais titlebar | Resultat attendu |
|-------------|-----------------|------------------|
| iTerm2 | 5 | Menu Roadie affiche |
| Finder | 5 | Menu Roadie affiche |
| Firefox ou Chromium | 5 | Menu Roadie affiche seulement si la zone haute est non ambigue |
| Application Electron ou SwiftUI avec titlebar custom | 5 | Menu Roadie affiche seulement si la zone haute est non ambigue |

La validation echoue si un clic droit dans le contenu applicatif affiche le menu Roadie.
