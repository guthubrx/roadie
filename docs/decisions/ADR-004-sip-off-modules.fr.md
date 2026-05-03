# ADR-004 — Autoriser SIP-off via modules opt-in séparés

🇫🇷 **Français** · 🇬🇧 [English](ADR-004-sip-off-modules.md)

**Date** : 2026-05-01
**Status** : Accepted
**Spec déclencheuse** : SPEC-004 fx-framework
**Famille concernée** : SPEC-004 → SPEC-010 (framework + 6 modules)

## Contexte

L'utilisateur a exprimé la demande explicite (revue branche `/branch` du 2026-05-01) de pouvoir activer des fonctionnalités esthétiques et de manipulation cross-desktop type Hyprland :

- Suppression / customisation de l'ombre des fenêtres tierces
- Focus dimming (alpha non focused)
- Animations Bézier 60-120 FPS sur ouverture/fermeture/switch
- Bordures colorées autour de la fenêtre focused
- Frosted glass blur derrière fenêtres
- Déplacement programmatique fenêtre cross-desktop (FR-024 SPEC-003 DEFER V3)

Toutes ces fonctionnalités requièrent l'écriture sur les APIs privées SkyLight (`CGSSetWindowAlpha`, `CGSSetWindowShadow*`, `CGSSetWindowBackgroundBlur`, `CGSSetWindowTransform`, `CGSAddWindowsToSpaces`, etc.) qui ne sont accessibles que via le **process owner de la fenêtre cible**.

Pour atteindre les fenêtres tierces, le pattern industriel (yabai 10 ans de prod) est :
1. SIP partiellement désactivé (`csrutil enable --without fs --without debug --without nvram` sur macOS 14+)
2. Scripting addition Cocoa déposée dans `/Library/ScriptingAdditions/`
3. Injection dans Dock via `osascript -e 'tell app "Dock" to load scripting additions'`
4. Le code injecté tourne dans Dock (process privilégié avec connection master) et expose les CGS via socket Unix

Or l'article C' constitution-002 v1.2.0 stipulait :
> « **`SLS*`/SkyLight et scripting addition Dock interdits** (FR-005). »

Cet article bloque toute la famille SPEC-004+. Il faut donc l'amender, **mais étroitement**, pour préserver l'invariant qui a fait la robustesse de SPEC-001/002/003 : **aucune dépendance privée fragile dans le core**.

## Décision

Amender l'article C' vers la version 1.3.0 pour autoriser SkyLight write + scripting addition **uniquement dans des modules opt-in** chargés à runtime via `dlopen`, à **6 conditions cumulatives strictes** :

1. **Daemon core fonctionnel sans module** : un utilisateur "vanilla" (SIP intact, aucun module installé) DOIT avoir une expérience complète et excellente. Tests SPEC-002 + SPEC-003 régression à 100 %.
2. **Module = target `.dynamicLibrary` séparé** : jamais lié statiquement au daemon. Vérification automatique : `nm roadied | grep CGSSetWindow* | wc -l == 0` (gate ajoutée).
3. **Pas de crash si SIP fully on** : le daemon démarre normalement, les modules font no-op gracieux (osax non chargée par Dock = OSAXBridge log warning, jamais d'exception).
4. **Installation osax manuelle** : par script utilisateur (`scripts/install-fx.sh`), jamais par roadie automatiquement. L'utilisateur consent explicitement.
5. **SPEC dédiée par module** : chaque module a sa spec, son audit sécurité, son plafond LOC. Pas de "ajout discret" qui contournerait la revue.
6. **Désactivable via config** : flag `[fx.<module_name>] enabled = false` désactive le module sans le retirer.

L'amendement est cadré par cet ADR et la nouvelle spec SPEC-004.

## Alternatives considérées

### A. Refus pur et simple

Garder C' v1.2.0 strict, refuser la demande utilisateur.

**Rejet** : la demande est légitime et la voie technique est éprouvée (yabai 10 ans). Le refus serait dogmatique sans bénéfice.

### B. Autorisation totale dans le daemon core

Linker directement les SkyLight write dans `roadied`.

**Rejet** : viole la philosophie suckless du projet, expose tous les utilisateurs à la fragilité macOS .X+1 même ceux qui ne veulent pas les effets visuels. Surface d'attaque (SIP off) imposée à tous.

### C. Modules statiques avec flag de build

Compiler 2 versions du daemon : une "vanilla" sans CGS, une "fx" avec.

**Rejet** : fragmente la distribution (2 binaires), complique les tests CI (qui n'existent pas mais bon), force un choix au build time alors que l'utilisateur peut vouloir essayer/désactiver à chaud.

### D. Modules opt-in via `.dynamicLibrary` (RETENU)

Modules séparés chargés à runtime. Daemon core inchangé. Utilisateur installe ce qu'il veut.

**Adopté** : combine pragmatisme (la voie est éprouvée yabai-style) et préservation des invariants (core suckless intact).

## Conséquences

### Positives

- **Daemon vanilla strictement préservé** : aucune régression possible pour les utilisateurs qui ne touchent pas à SIP
- **Compartimentation totale** : suppression d'un `.dylib` ou de l'osax = retour 100 % vanilla
- **Audit modulaire** : chaque module fait l'objet d'une SPEC + audit dédié, pas de cumul de risque
- **LOC plafonds séparés** : core ≤ 4 000 (G' inchangé), opt-in cumulé ≤ 2 720 (nouveau plafond famille SPEC-004+)
- **Sécurité explicite** : l'utilisateur consent par installation manuelle de l'osax + désactivation SIP

### Négatives

- **SIP partial off** ouvre une vraie surface d'attaque pour les utilisateurs qui activent les modules. Documentation utilisateur explicite : "as-is, no warranty".
- **Fragilité macOS .X+1** : chaque update majeure peut casser le pattern (cf yabai 1-4 semaines de retard typique). Plan de mitigation : monitor yabai upstream, doc utilisateur claire.
- **Complexité legèrement accrue** du build : 1 target dynamicLibrary supplémentaire (`RoadieFXCore`) + bundle Cocoa séparé (`roadied.osax`). Géré par `scripts/install-fx.sh`.
- **Non-distribution App Store** : impossible avec scripting addition tiers. Acceptable car le projet n'a jamais visé l'App Store (déjà incompatible avec Accessibility daemon-style).

### Neutres

- **Pas de retro-incompatibilité** : les utilisateurs SPEC-001/002/003 actuels ne voient aucune différence avant d'installer manuellement les modules.
- **Constitution évolution naturelle** : C' était dur à 1.0.0 par prudence, s'adapte à 1.3.0 maintenant que les invariants sont éprouvés.

## Conditions de garde (rappelées)

| # | Condition | Vérification automatique |
|---|---|---|
| 1 | Daemon core 100 % fonctionnel sans module | Tests SPEC-002 + SPEC-003 (régression) + SC-007 SPEC-004 |
| 2 | Modules `.dynamicLibrary` séparés | `nm roadied | grep CGSSetWindow* | wc -l == 0` |
| 3 | Pas de crash si SIP fully on | Test intégration `11-fx-vanilla.sh` |
| 4 | Osax installation manuelle | Code review : aucun appel `osascript ... load scripting additions` dans le daemon |
| 5 | SPEC dédiée par module | Vérifié par revue avant merge |
| 6 | Flag config désactive | Test : config `[fx.X] enabled=false` → module no-op vérifié |

## Références

- [Disabling SIP — yabai Wiki](https://github.com/koekeishiya/yabai/wiki/Disabling-System-Integrity-Protection)
- [yabai sa.dylib injection pattern](https://github.com/koekeishiya/yabai/tree/master/sa)
- Constitution projet 002-tiler-stage v1.3.0 (article C' amendé)
- SPEC-004 fx-framework (famille SIP-off)

## Auteurs

Projet roadies, branche `004-fx-framework`, 2026-05-01
