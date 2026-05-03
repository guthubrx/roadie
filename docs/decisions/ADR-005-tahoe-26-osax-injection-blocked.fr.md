# ADR-005 — Injection scripting addition Dock bloquée sur macOS Tahoe 26

🇫🇷 **Français** · 🇬🇧 [English](ADR-005-tahoe-26-osax-injection-blocked.md)

**Date** : 2026-05-01
**Status** : Accepted
**Spec déclencheuse** : SPEC-004 fx-framework (post-livraison)
**Famille concernée** : SPEC-004 → SPEC-010 (effets visuels SIP-off)

## Contexte

ADR-004 (2026-05-01) a autorisé la famille SPEC-004+ à utiliser scripting addition Dock + SkyLight write privées **sous 6 conditions cumulatives**. La famille a été livrée et mergée (SPEC-004 framework + SPEC-005 à SPEC-010, 6 modules).

Lors de la première mise en service end-to-end sur la machine de dev (macOS Tahoe 26.2 build 25C56, Apple Silicon arm64e, SIP fully disabled), **le daemon, les modules `.dylib` et le bundle osax sont tous correctement compilés et installés, mais l'osax n'est jamais chargée par Dock**. Aucune erreur, aucun log, aucune trace : silence total côté système.

### État technique vérifié

Toutes les préconditions documentées (yabai wiki, SpecterOps blog 2025-08, archive scripting addition macOS 14+) sont remplies :

| # | Précondition | État vérifié | Commande |
|---|---|---|---|
| 1 | SIP fully disabled | ✅ `disabled` | `csrutil status` |
| 2 | Boot-args arm64e preview ABI | ✅ `-arm64e_preview_abi` | `nvram boot-args` |
| 3 | Bundle compilé arm64e (Pointer Auth) | ✅ `Mach-O 64-bit bundle arm64e` | `file .../MacOS/roadied` |
| 4 | Signature ad-hoc non-hardened | ✅ `flags=0x2(adhoc)`, hardened runtime absent | `codesign -dvvv` |
| 5 | Bundle root:wheel dans `/Library/ScriptingAdditions/` | ✅ Posé via popup admin | `ls -la` |
| 6 | Library validation désactivée globalement | ✅ `DisableLibraryValidation = 1` | `defaults read /Library/Preferences/com.apple.security.libraryvalidation` |
| 7 | Bundle Info.plist `OSAXHandlers` valide | ✅ Identifié `local.roadies.osax` | `plutil -p Info.plist` |
| 8 | SkyLight private headers liés (target arm64e-macos14) | ✅ Linké, symboles présents | `nm` sur le bundle |

### Symptômes observés

1. `osascript -e 'tell app "Dock" to load scripting additions'` ⇒ erreur de **parsing AppleScript localisé** (-2740/-2741 : "scripting additions" interprété comme nom de classe pluriel par le parser fr_FR). Workarounds (`LANG=en_US.UTF-8`, blocs `tell application "AppleScript"`, `osascript -l AppleScript`) tous échoués.
2. Force-load alternatifs (relance Dock via `killall Dock`, login/logout, reboot) : **`+[ROHooks load]` n'est jamais appelé**, aucune trace dans `log show --predicate 'subsystem == "local.roadies"'` ni dans `log stream --process Dock`.
3. Aucun crash report (`~/Library/Logs/DiagnosticReports/Dock-*.ips` vide pour la période).
4. AMFI ne logue rien (`log show --predicate 'eventMessage CONTAINS "AMFI"'` vide pour le bundle).

### Triangulation communauté

- **yabai PR #2644** (Tahoe scripting addition support) : ouverte 2025-06, **toujours non mergée** au 2026-05-01. Plusieurs contributeurs rapportent le même symptôme : bundle correctement signé arm64e + SIP off + boot-args, Dock ignore silencieusement.
- **Hammerspoon issue #3698** : `hs.spaces` (qui utilise un mécanisme similaire d'injection CGS) cassé depuis Sequoia 15.0, jamais réparé.
- **SpecterOps blog "Apple's Scripting Additions Death March"** (août 2025) : analyse forensique montrant qu'Apple a ajouté un check silencieux côté `loginwindow` / `launchd` qui rejette toute scripting addition tierce non signée par Apple, indépendamment de SIP/AMFI/library validation.

La conclusion empirique convergente : **Apple a effectivement (de facto) tué le mécanisme scripting addition sur Tahoe 26 pour les bundles tiers, sans documentation officielle ni message d'erreur**.

## Décision

**Accepter la limitation** : la famille SPEC-004+ reste mergée et livrée, le framework fonctionne correctement (les 6 modules `.dylib` sont chargés via `dlopen` et reçoivent leurs events), **mais aucun effet visuel CGS n'atteint Dock tant qu'Apple ou la communauté yabai/Hammerspoon n'ont pas trouvé un mécanisme de remplacement**.

**Aucun investissement spéculatif** dans des contournements (Mach thread injection style task_for_pid → estimé 6h+ pour proof-of-concept fragile, hors scope minimaliste de la constitution G').

**Veille active** : monitorer yabai PR #2644 et l'écosystème (Hammerspoon, AeroSpace, Übersicht) pour détecter le moment où un nouveau pattern d'injection émerge.

## État runtime actuel (post-livraison)

### Ce qui fonctionne (sans osax injectée)

| Capacité | Source | Fonctionne ? |
|---|---|---|
| Tiling BSP/master-stack | SPEC-002 | ✅ |
| Stage Manager (raccourcis ⌥1/⌥2) | SPEC-002 | ✅ |
| Multi-desktop awareness (per-desktop state) | SPEC-003 | ✅ |
| Drag-to-adapt | SPEC-002 | ✅ |
| Click-to-raise | SPEC-002 | ✅ |
| 13 raccourcis BTT | SPEC-002 | ✅ |
| `roadie fx status` (CLI) | SPEC-004 | ✅ affiche les 6 modules chargés |
| `dlopen` des 6 modules `.dylib` + dispatch d'events | SPEC-004 | ✅ |
| NSWindow border overlays (fenêtre roadie propre) | SPEC-008 | ✅ contour visuel |
| CAKeyframeAnimation pulse sur focus change | SPEC-008 | ✅ |
| `roadie events --follow` (stream JSON-lines stable, no broken pipe) | SPEC-003+ | ✅ |

### Ce qui est inerte (requiert osax)

| Capacité | Source | État |
|---|---|---|
| Shadowless (suppression ombre fenêtres tierces) | SPEC-005 | 🟡 module chargé, no-op silencieux |
| Inactive window dimming | SPEC-006 | 🟡 idem |
| Per-app baseline alpha | SPEC-006 | 🟡 idem |
| Stage hide via alpha=0 | SPEC-006 | 🟡 fallback `HideStrategy.corner` actif |
| Fade-in / fade-out fenêtre | SPEC-007 | 🟡 idem |
| Slide horizontal workspace switch | SPEC-007 | 🟡 idem |
| Crossfade stage switch | SPEC-007 | 🟡 idem |
| Resize animation (frame interpolée) | SPEC-007 | 🟡 idem |
| Frosted glass blur | SPEC-009 | 🟡 idem |
| `roadie window space N` (move cross-desktop) | SPEC-010 | 🟡 idem |
| `roadie window stick` | SPEC-010 | 🟡 idem |
| `roadie window pin` (always-on-top niveau CGS) | SPEC-010 | 🟡 idem (level NSWindow géré côté borders OK pour fenêtres roadie) |

### Cas partiel

| Capacité | État |
|---|---|
| Borders niveau CGS sur fenêtres tierces (palettes flottantes) | NSWindow overlay roadie reste correct sur fenêtres standard ; sur palettes natives `.floating` (Photoshop, Sketch), l'overlay peut passer dessous sans `SLSSetWindowLevel` côté tiers |

## Conséquences

### Positives

- **Zéro régression sur le core** (SPEC-001/002/003) : les modules sont chargés à vide, le daemon vanilla continue de tourner exactement comme avant.
- **Architecture validée à blanc** : tout le framework (FXLoader, OSAXBridge, AnimationLoop, BezierEngine) est testé empiriquement sur le chemin no-op. Le jour où l'injection redevient possible, **aucune migration de code**, juste l'osax qui se charge.
- **Effort sunk cost négligeable** : le framework représente ~2 000 LOC alignées sur le pattern industriel yabai. Si Apple bouge dans le sens inverse (improbable) ou si la communauté trouve un workaround, on bascule en quelques heures.
- **Compartimentation conditions ADR-004 préservées** : aucune des 6 conditions n'est violée par cette indisponibilité runtime — la condition #3 ("pas de crash si SIP fully on / osax absente") est même validée à 100 % puisque toutes les machines sont dans cette configuration de fait.

### Négatives

- **Promesse utilisateur partiellement non tenue** : l'expérience "HypRoadie" (Bézier curves, focus dimming, crossfade) annoncée dans SPEC-004+ est **inerte** sur Tahoe 26. Document à mettre à jour : README + SPEC-004 spec.md doivent être amendés pour signaler la limitation Tahoe explicitement (statut `Delivered (runtime-blocked Tahoe 26)`).
- **Surface d'attaque inutilement ouverte** : la machine de dev a SIP partial off + library validation off pour rien (les effets ne tournent pas). Recommandation côté utilisateur : **réactiver SIP** (`csrutil enable`) tant que l'injection ne fonctionne pas, et le redésactiver le jour où un workaround émerge. Le daemon vanilla n'en pâtit pas.
- **Confiance dans le pattern scripting addition érodée** : ADR-004 misait sur "10 ans de prod yabai". Cette stabilité est terminée. Toute SPEC future devra considérer ce pattern comme **provisoire et non garanti**.

### Neutres

- **Pas d'impact LOC** : aucune ligne à retirer. Le framework reste prêt.
- **Documentation utilisateur à mettre à jour** uniquement (README + SPEC-004 status).

## Alternatives considérées

### A. Retirer la famille SPEC-004+ (revert)

Annuler tous les merges, garder uniquement SPEC-001/002/003.

**Rejet** : sunk cost économique pur. Le code fonctionne, les tests passent, le no-op gracieux est exemplaire. Retirer = jeter ~2 000 LOC propres pour rien. Le jour où l'injection revient, il faudrait tout refaire.

### B. Investir dans Mach thread injection (`task_for_pid`)

Pattern alternatif : depuis un process root, attacher Dock via `task_for_pid` + injecter une thread qui charge le `.dylib`.

**Rejet** :
- Estimé 6-12h pour un POC fragile (chaque update macOS peut casser).
- Requiert `com.apple.security.cs.debugger` entitlement Apple-signé (impossible sans Developer ID payant + provisioning profile pour l'utilisateur).
- Surface d'attaque encore plus large (process root permanent).
- Hors scope constitution G' (minimalisme LOC).

### C. Demander entitlement `com.apple.private.security.scripting-addition-loading` (style yabai PR #2644)

Tentative de bypass via entitlement custom déposé dans le bundle.

**Rejet** : le fil yabai #2644 montre que Apple ignore aussi cet entitlement sur Tahoe 26 si la signature n'est pas Apple. Pure imitation.

### D. Attendre + monitor (RETENU)

Accepter la limitation, garder le framework prêt, attendre signal positif communauté (yabai PR mergée OU publication d'un nouveau pattern).

**Adopté** : seule option économiquement saine. Coût marginal = surveillance passive.

## Plan d'action immédiat

1. **README projet** : ajouter une section "Tahoe 26 limitation" pointant vers cet ADR.
2. **SPEC-004 spec.md** : amender le statut "Delivered" en "Delivered (runtime-blocked on macOS 26+, framework ready)".
3. **SPEC-005 → SPEC-010 spec.md** : ajouter une note "Effets inertes tant qu'osax non injectée — voir ADR-005".
4. **Recommandation utilisateur dev** : `csrutil enable` + retirer `-arm64e_preview_abi` des boot-args jusqu'à signal positif. Le daemon core tourne identique.
5. **Watch list** : `gh issue subscribe koekeishiya/yabai 2644` (rappel manuel mensuel).

## Conditions de réouverture

Cet ADR redevient `Superseded` (et la famille SPEC-004+ redevient pleinement opérationnelle) si **l'une** des conditions suivantes est remplie :

- yabai PR #2644 mergée + bundle yabai-sa.dylib fonctionnel observé sur Tahoe 26.
- Apple publie un mécanisme officiel de scripting addition tierce (très improbable).
- Un nouveau pattern d'injection émergent (ex: DriverKit user-space, Endpoint Security extensions abusées) est documenté par 2+ projets indépendants stable sur Tahoe 26.
- L'utilisateur accepte explicitement d'investir dans l'alternative B (Mach thread injection) avec ses contraintes (Developer ID payant + LOC supplémentaires hors plafond G').

Dans tous les cas : un **nouvel ADR-006** sera produit pour acter la réouverture, pas de modification silencieuse de cet ADR.

## Références

- [yabai PR #2644 — Tahoe scripting addition support](https://github.com/koekeishiya/yabai/pull/2644)
- [Hammerspoon issue #3698 — hs.spaces broken Sequoia+](https://github.com/Hammerspoon/hammerspoon/issues/3698)
- SpecterOps blog "Apple's Scripting Additions Death March" (août 2025)
- ADR-004 — Autoriser SIP-off via modules opt-in séparés
- Constitution projet 002-tiler-stage v1.3.0 (article C')
- SPEC-004 fx-framework + spec.md `Delivered (runtime-blocked Tahoe 26)`
- État système vérifié : macOS 26.2 (25C56), arm64e, SIP disabled, `-arm64e_preview_abi`, library validation off

## Auteurs

Projet roadies, post-merge SPEC-004+ → main, 2026-05-01
