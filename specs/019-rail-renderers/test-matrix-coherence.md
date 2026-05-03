# Test Matrix — Cohérence navrail × tiling × chemins d'input

**Spec** : SPEC-019 rail-renderers (couvre aussi les invariants SPEC-014/018)
**ADR** : [ADR-007](../../docs/decisions/ADR-007-test-matrix-coherence-navrail-tiling.md)
**Audience** : agent Claude Code intelligent + skill `gui` activée
**Mode lecture seule** : OUI pour les sections 0-2. Écriture autorisée UNIQUEMENT sur la grille (section 3).

---

## Section 0 — Mode opératoire (à exécuter dans l'ordre)

### Phase 1 — Setup (1 fois, avant tout TC)

```bash
# 1. Branche + outils
git branch --show-current     # doit être 019-rail-renderers
which cliclick                # doit retourner /opt/homebrew/bin/cliclick
cliclick p                    # vérifier permissions Accessibility (sinon STOP)

# 2. Build à jour
PATH=/usr/bin:/bin:/usr/sbin:/sbin:/Applications/Xcode.app/Contents/Developer/usr/bin swift build 2>&1 | tail -3

# 3. Daemon
pkill -f "roadied --daemon" 2>&1 || true ; sleep 1
./.build/debug/roadied --daemon > /tmp/roadied.log 2>&1 &
sleep 4
./.build/debug/roadie daemon status 2>&1 | grep -E "version|current_stage"

# 4. Rail
cp .build/debug/roadie-rail ~/.local/bin/roadie-rail
pkill -f roadie-rail 2>&1 || true ; sleep 1
./.build/debug/roadie rail toggle 2>&1

# 5. Inventaire écrans + desktops
./.build/debug/roadie display list 2>&1
./.build/debug/roadie desktop list 2>&1

# 6. BTT vivant (sinon TC-Bxxx tous BLOCKED)
pgrep -x BetterTouchTool > /dev/null || echo "BTT not running — BTT TC will be BLOCKED"

# 7. Inventaire des hotkeys roadie configurés via BTT (référence)
osascript -e 'tell application "BetterTouchTool" to get_triggers' \
  | python3 -c "import json,sys; [print(t.get('BTTLayoutIndependentChar','?'), '→', t.get('BTTShellTaskActionScript','')) for t in json.load(sys.stdin) if 'roadie' in t.get('BTTShellTaskActionScript','')]" \
  > /tmp/btt-roadie-map.txt
wc -l /tmp/btt-roadie-map.txt   # attendu : 58 lignes (cf. ADR-007)
```

**STOP et escalade humaine si l'une des étapes échoue.** L'agent ne corrige pas l'infrastructure.

### Phase 2 — Boucle par classe

Pour chaque classe (TC-100 → TC-1300, dans l'ordre) :

1. **Étape A** — Passer tous les TC de la classe en lecture seule. Remplir `Status` de la grille.
2. **Étape B** — Si `FAIL > 0` :
   - **Diagnostic empirique obligatoire** : logs daemon (`tail -100 ~/.local/state/roadies/daemon.log`), screenshots `/tmp/hui-tc-XXX-*.png`, `roadie windows list`, `roadie stage list --display <uuid>`.
   - Identifier la cause racine (1 fix peut résoudre plusieurs FAIL).
   - Appliquer fix → build → reinstall (`cp .build/debug/roadie* ~/.local/bin/`) → restart daemon + rail.
   - Noter `Fix applied` dans la grille (commit + fichier + 1 phrase rationale).
   - Re-passer les TC FAIL → noter `Post-fix status`.
   - **Max 2 cycles fix** par classe sinon STOP.
3. **Étape C** — Si tout PASS / Post-fix=PASS : `git tag tc-class-<name>-pass` + classe suivante.

### Phase 3 — Régression complète

Re-passer toute la suite TC-100 → TC-1399 en lecture seule. Remplir `Phase 3 status`. Toute différence vs passe initiale = régression.

### Garde-fous (dérogation interdite à l'agent)

- **Aucun fix sans diagnostic empirique** (logs + screenshots + state daemon).
- **Max 2 cycles fix par classe**.
- **L'agent ne modifie jamais les sections 0-2 de ce fichier**.
- **Pas de SKIP de confort** : seulement matériel manquant (2e écran, BTT down, …).

### Notation des chemins d'input

Chaque TC précise son **chemin d'input** car la même action atomique se déclenche par plusieurs voies :

| Symbole | Chemin |
|---|---|
| `[CLI]` | Commande `roadie X` direct via shell |
| `[BTT]` | Hotkey BTT configuré (cf. carte BTT 58 hotkeys, /tmp/btt-roadie-map.txt) |
| `[NAV]` | Action via le panel navrail (clic, drag-drop, menu contextuel) |
| `[OS]` | Raccourci macOS natif **non passé par roadie** (ex: Ctrl+→ pour switch desktop natif, Cmd+Tab pour focus app) |
| `[WP]` | Wallpaper-click (création stage par clic sur le bureau) |

Quand une action est testée par plusieurs chemins, ils sont déclinés en `TC-XXXa`, `TC-XXXb`, `TC-XXXc`. Le résultat attendu doit être **identique** quel que soit le chemin (sauf cas où la spec stipule différemment).

### Convention coordonnées

- Origine `(0,0)` = haut-gauche du **primary display** (NSScreen.frame.origin == .zero).
- Pour le 2nd écran (LG), coordonnées négatives en y si placé au-dessus, ou x négatif si à gauche du primary. Lire `roadie display list` pour la frame exacte.
- `cliclick` interprète les coordonnées en points logiques (Retina géré).

---

## Section 1 — Invariants

| ID | Invariant |
|---|---|
| **INV-1** | Le navrail d'un panel montre les stages de **son** écran (pas un autre) |
| **INV-2** | Le contenu visible à l'écran correspond aux wids du stage actif du scope |
| **INV-3** | Stage 1 toujours présente sur chaque (display, desktop) — jamais « No stages yet » |
| **INV-4** | 1 wid = 1 stage max (pas de double-attribution disque ou mémoire) |
| **INV-5** | Pas de helper window 66×20 dans aucune stage |
| **INV-6** | Hide/show correct au switch (offscreen `frame.x < -1000` vs on-screen `frame.x ≥ 0`) |
| **INV-7** | La mémoire stage actif par (display, desktop) est conservée à l'aller-retour |
| **INV-8** | Les actions du panel propagent au scope **du panel**, pas à l'inférence curseur |
| **INV-9** | Les chemins d'input équivalents (CLI/BTT/NAV) produisent un état final identique |
| **INV-10** | Le tiling reste valide après chaque mutation (pas de leaf orpheline, pas de cellule dégénérée) |

---

## Section 2 — Test cases

### Classe TC-100 — Boot et état initial

#### TC-101 — Stage 1 listée sur primary

- **Catégorie** : observation passive
- **Chemin** : [CLI]
- **Invariants** : INV-3
- **Action** :
  ```bash
  PRIMARY_UUID=$(./.build/debug/roadie display list --json 2>&1 | grep -oE '"uuid": "[^"]+"' | head -1 | cut -d'"' -f4)
  ./.build/debug/roadie stage list --display "$PRIMARY_UUID" 2>&1 > /tmp/hui-tc-101.txt
  ```
- **Attendu** : `/tmp/hui-tc-101.txt` contient au moins `* 1 (1)` (stage 1 active).

#### TC-102 — Stage 1 sur chaque écran physique connecté

- **Catégorie** : observation passive
- **Chemin** : [CLI]
- **Invariants** : INV-3
- **Action** :
  ```bash
  for uuid in $(./.build/debug/roadie display list --json 2>&1 | grep -oE '"uuid": "[^"]+"' | cut -d'"' -f4); do
      echo "=== $uuid ==="
      ./.build/debug/roadie stage list --display "$uuid" 2>&1
  done > /tmp/hui-tc-102.txt
  ```
- **Attendu** : pour chaque display détecté, la sortie contient au moins une stage avec id `1`. Si 1 écran : 1 section. Si 2 écrans : 2 sections.

#### TC-103 — Aucun helper 66×20 dans les fichiers stages persistés

- **Catégorie** : observation passive
- **Chemin** : [filesystem]
- **Invariants** : INV-5
- **Action** :
  ```bash
  find ~/.config/roadies/stages -name "*.toml" -not -name "_active*" -not -name "*legacy*" \
    -exec grep -l "w = 66\|h = 20\b" {} \; > /tmp/hui-tc-103.txt
  wc -l /tmp/hui-tc-103.txt
  ```
- **Attendu** : 0 lignes dans `/tmp/hui-tc-103.txt`.

#### TC-104 — Aucune wid double-attribuée

- **Catégorie** : observation passive
- **Chemin** : [filesystem]
- **Invariants** : INV-4
- **Action** :
  ```bash
  grep -h "cg_window_id" ~/.config/roadies/stages/*/*/*.toml 2>/dev/null \
    | sort | uniq -c | awk '$1 > 1' > /tmp/hui-tc-104.txt
  ```
- **Attendu** : `/tmp/hui-tc-104.txt` vide.

#### TC-105 — 58 hotkeys BTT roadie configurés

- **Catégorie** : observation passive
- **Chemin** : [BTT]
- **Invariants** : INV-9 (prérequis pour les TC BTT)
- **Action** :
  ```bash
  wc -l /tmp/btt-roadie-map.txt
  ```
- **Attendu** : ≥ 50 lignes (référence : 58 hotkeys au snapshot ADR-007). Si < 50, BLOCKED tous les TC `[BTT]`.

---

### Classe TC-200 — Display × scope

#### TC-201 — Hover bord gauche fait apparaître le panel rail (primary)

- **Chemin** : [NAV]
- **Invariants** : INV-1, INV-3
- **Action** :
  ```bash
  cliclick m:1500,500 ; sleep 1
  screencapture -x /tmp/hui-tc-201-before.png
  cliclick -e 600 m:0,500 ; sleep 2
  screencapture -x /tmp/hui-tc-201-after.png
  ```
- **Attendu (Navrail)** : `after.png` montre des vignettes dans `x ∈ [0,320]`, `before.png` non.

#### TC-202 — Le panel primary affiche les stages du primary

- **Chemin** : [NAV]
- **Invariants** : INV-1
- **Action** :
  ```bash
  PRIMARY_UUID=$(./.build/debug/roadie display list --json 2>&1 | grep -oE '"uuid": "[^"]+"' | head -1 | cut -d'"' -f4)
  ./.build/debug/roadie stage list --display "$PRIMARY_UUID" 2>&1 > /tmp/hui-tc-202-state.txt
  cliclick -e 600 m:0,500 ; sleep 2
  screencapture -x -R0,0,400,1280 /tmp/hui-tc-202-rail.png
  ```
- **Attendu** : nombre de cellules visibles dans `rail.png` == nombre de stages dans `state.txt`.

#### TC-203 — Avec 2 écrans, chaque panel affiche ses propres stages

- **Chemin** : [NAV]
- **Invariants** : INV-1
- **Préconditions** : 2 écrans détectés (sinon SKIP)
- **Action** :
  ```bash
  PRIMARY_UUID=$(./.build/debug/roadie display list --json 2>&1 | grep -oE '"uuid": "[^"]+"' | sed -n '1p' | cut -d'"' -f4)
  SECOND_UUID=$(./.build/debug/roadie display list --json 2>&1 | grep -oE '"uuid": "[^"]+"' | sed -n '2p' | cut -d'"' -f4)
  SECOND_FRAME=$(./.build/debug/roadie display list --json 2>&1 | python3 -c "import json,sys; d=json.load(sys.stdin)['displays']; print(*d[1]['frame']) if len(d)>=2 else print('')")
  ./.build/debug/roadie stage create A "AlphaPrim" --display "$PRIMARY_UUID" 2>&1
  ./.build/debug/roadie stage create B "BetaSecond" --display "$SECOND_UUID" 2>&1
  cliclick -e 600 m:0,500 ; sleep 2
  screencapture -x -R0,0,400,1280 /tmp/hui-tc-203-primary.png
  # Hover bord gauche du 2e écran (calculer x = SECOND_FRAME[0])
  X2=$(echo "$SECOND_FRAME" | awk '{print $1}')
  Y2=$(echo "$SECOND_FRAME" | awk '{print $2 + 500}')
  cliclick -e 600 m:$X2,$Y2 ; sleep 2
  screencapture -x /tmp/hui-tc-203-secondary.png
  ```
- **Attendu** : `primary.png` contient `AlphaPrim` et PAS `BetaSecond`. `secondary.png` inverse.

#### TC-204 — `roadie stage list` (sans flag) reflète le scope curseur

- **Chemin** : [CLI]
- **Invariants** : INV-8
- **Action** :
  ```bash
  cliclick -e 400 m:1000,500 ; sleep 1
  ./.build/debug/roadie stage list 2>&1 > /tmp/hui-tc-204-primary.txt
  # Si 2 écrans : déplacer curseur sur 2nd
  ./.build/debug/roadie display list --json 2>&1 | grep -q '"index": 2' && {
      cliclick -e 400 m:-100,1500 ; sleep 1
      ./.build/debug/roadie stage list 2>&1 > /tmp/hui-tc-204-secondary.txt
      diff /tmp/hui-tc-204-primary.txt /tmp/hui-tc-204-secondary.txt
  }
  ```
- **Attendu** : si 2 écrans, les 2 sorties diffèrent. Si 1 écran, SKIP la 2nde moitié.

#### TC-205 — `roadie display focus N` change l'écran actif [CLI]

- **Chemin** : [CLI]
- **Invariants** : INV-8
- **Préconditions** : 2 écrans
- **Action** :
  ```bash
  ./.build/debug/roadie display current 2>&1 > /tmp/hui-tc-205-before.txt
  ./.build/debug/roadie display focus 2 2>&1 ; sleep 0.5
  ./.build/debug/roadie display current 2>&1 > /tmp/hui-tc-205-after.txt
  diff /tmp/hui-tc-205-before.txt /tmp/hui-tc-205-after.txt
  ```
- **Attendu** : diff non-vide (display current a changé).

---

### Classe TC-300 — Desktop × scope (multi-chemins)

> Les hotkeys BTT pour desktops : `⌘+1` … `⌘+0` → `roadie desktop focus 1..10`. `⌥+⇧+P/N/M` → prev/next/last.

#### TC-301a — Switch desktop via [CLI]

- **Chemin** : [CLI]
- **Invariants** : INV-7
- **Action** :
  ```bash
  ./.build/debug/roadie desktop focus 1 2>&1 ; sleep 0.5
  ./.build/debug/roadie stage 2 2>&1 ; sleep 0.5  # marquer stage 2 actif sur D1
  ./.build/debug/roadie desktop focus 2 2>&1 ; sleep 0.5
  ./.build/debug/roadie desktop focus 1 2>&1 ; sleep 0.5
  ./.build/debug/roadie daemon status 2>&1 | grep current_stage
  ```
- **Attendu** : `current_stage: 2` (mémoire conservée).

#### TC-301b — Switch desktop via [BTT] (`⌘+1` puis `⌘+2` puis `⌘+1`)

- **Chemin** : [BTT]
- **Invariants** : INV-7, INV-9 (résultat identique à TC-301a)
- **Préconditions** : TC-105 PASS
- **Action** :
  ```bash
  cliclick -e 200 kd:cmd kp:1 ku:cmd ; sleep 0.5  # Cmd+1
  ./.build/debug/roadie stage 2 2>&1 ; sleep 0.5
  cliclick -e 200 kd:cmd kp:2 ku:cmd ; sleep 0.5  # Cmd+2
  cliclick -e 200 kd:cmd kp:1 ku:cmd ; sleep 0.5  # Cmd+1
  ./.build/debug/roadie daemon status 2>&1 | grep current_stage
  ```
- **Attendu** : `current_stage: 2` (identique TC-301a — INV-9).

#### TC-301c — Switch desktop via [BTT] hotkeys directionnels (`⌥+⇧+N` next, `⌥+⇧+P` prev)

- **Chemin** : [BTT]
- **Invariants** : INV-9
- **Action** :
  ```bash
  ./.build/debug/roadie desktop focus 1 2>&1 ; sleep 0.5
  cliclick -e 200 kd:alt kd:shift kp:n ku:shift ku:alt ; sleep 0.5  # Alt+Shift+N → desktop next
  ./.build/debug/roadie desktop current 2>&1 > /tmp/hui-tc-301c-after.txt
  ```
- **Attendu** : desktop courant a augmenté de 1 (= 2).

#### TC-302 — Wids du desktop quitté hidden offscreen

- **Chemin** : [CLI]
- **Invariants** : INV-6
- **Action** :
  ```bash
  ./.build/debug/roadie desktop focus 1 2>&1 ; sleep 0.5
  ./.build/debug/roadie windows list 2>&1 | grep "tiled stage" | awk '{print $1, $5}' > /tmp/hui-tc-302-d1.txt
  ./.build/debug/roadie desktop focus 2 2>&1 ; sleep 0.5
  ./.build/debug/roadie windows list 2>&1 | grep "tiled" | awk '{print $1, $5}' | grep -E "^[0-9]+ -[0-9]{3,}" > /tmp/hui-tc-302-d2-hidden.txt
  ```
- **Attendu** : `d2-hidden.txt` contient les wids de D1 avec frame.x < -1000.

#### TC-303 — Stage 1 auto-créée sur desktop jamais visité

- **Chemin** : [CLI]
- **Invariants** : INV-3
- **Action** :
  ```bash
  ./.build/debug/roadie desktop focus 5 2>&1 || true ; sleep 1
  ./.build/debug/roadie stage list 2>&1 | grep -E "^\* 1 |^  1 "
  ```
- **Attendu** : au moins une ligne (stage 1 présente).

#### TC-304 — Cycle complet desktop 1→2→…→10→1 [BTT]

- **Chemin** : [BTT]
- **Invariants** : INV-9
- **Action** :
  ```bash
  for n in 1 2 3 4 5 6 7 8 9 0; do
      cliclick -e 100 kd:cmd kp:$n ku:cmd ; sleep 0.3
  done
  cliclick -e 100 kd:cmd kp:1 ku:cmd ; sleep 0.5
  ./.build/debug/roadie desktop current 2>&1 | grep "current_id: 1"
  ```
- **Attendu** : retour à desktop 1, daemon vivant.

#### TC-305 — Move window cross-desktop via [BTT] (`⌘+⇧+1..9`)

- **Chemin** : [BTT]
- **Invariants** : INV-9, INV-6
- **Action** :
  ```bash
  ./.build/debug/roadie desktop focus 1 2>&1 ; sleep 0.5
  WID=$(./.build/debug/roadie windows list 2>&1 | grep "focused" | awk '{print $1}')
  cliclick -e 200 kd:cmd kd:shift kp:2 ku:shift ku:cmd ; sleep 0.5  # Cmd+Shift+2 → window desktop 2
  ./.build/debug/roadie windows list 2>&1 | grep "^$WID"
  # vérifier que la wid est offscreen sur D1 (déplacée vers D2)
  ```
- **Attendu** : la wid focused a frame.x < -1000 ou disparaît du listing tiled de D1.

#### TC-306 — Move window cross-display via [BTT] (`⌘+⌥+⌃+1..N`)

- **Chemin** : [BTT]
- **Invariants** : INV-9
- **Préconditions** : 2 écrans
- **Action** :
  ```bash
  WID=$(./.build/debug/roadie windows list 2>&1 | grep "focused" | awk '{print $1}')
  cliclick -e 200 kd:cmd kd:alt kd:ctrl kp:2 ku:ctrl ku:alt ku:cmd ; sleep 0.5
  ./.build/debug/roadie windows list 2>&1 | grep "^$WID"
  ```
- **Attendu** : la wid a une frame sur le 2e display (lire roadie display list pour frame attendue).

---

### Classe TC-400 — Stage × renderer (multi-chemins)

> Hotkeys BTT stage : `⌥+1` `⌥+2` → `roadie stage 1/2`. `⌥+⇧+1` `⌥+⇧+2` → `roadie stage assign 1/2`.

#### TC-401 — Halo conditionnel sur stage active

- **Chemin** : [NAV] observation
- **Invariants** : INV-2
- **Action** :
  ```bash
  ./.build/debug/roadie rail renderer stacked-previews 2>&1 ; sleep 1
  ./.build/debug/roadie stage 1 2>&1 ; sleep 0.5
  cliclick -e 600 m:0,500 ; sleep 2
  screencapture -x -R0,0,400,1280 /tmp/hui-tc-401-stage1.png
  ./.build/debug/roadie stage 2 2>&1 ; sleep 0.5
  cliclick -e 600 m:0,500 ; sleep 2
  screencapture -x -R0,0,400,1280 /tmp/hui-tc-401-stage2.png
  ```
- **Attendu** : halo coloré sur la cellule active uniquement (différent entre les 2 captures).

#### TC-402a — Switch stage via [CLI] hide les wids du stage quitté

- **Chemin** : [CLI]
- **Invariants** : INV-2, INV-6
- **Action** :
  ```bash
  ./.build/debug/roadie stage 2 2>&1 ; sleep 0.5
  ./.build/debug/roadie windows list 2>&1 | grep "stage=2" | head -3 > /tmp/hui-tc-402a-on.txt
  ./.build/debug/roadie stage 1 2>&1 ; sleep 0.5
  ./.build/debug/roadie windows list 2>&1 | grep "stage=2" | head -3 > /tmp/hui-tc-402a-off.txt
  ```
- **Attendu** : `on.txt` frames `x ≥ 0`, `off.txt` frames `x < -1000`.

#### TC-402b — Switch stage via [BTT] (`⌥+1`, `⌥+2`)

- **Chemin** : [BTT]
- **Invariants** : INV-9
- **Action** :
  ```bash
  cliclick -e 200 kd:alt kp:2 ku:alt ; sleep 0.5
  ./.build/debug/roadie daemon status 2>&1 | grep current_stage > /tmp/hui-tc-402b-1.txt
  cliclick -e 200 kd:alt kp:1 ku:alt ; sleep 0.5
  ./.build/debug/roadie daemon status 2>&1 | grep current_stage > /tmp/hui-tc-402b-2.txt
  ```
- **Attendu** : `1.txt` contient `current_stage: 2`, `2.txt` contient `current_stage: 1`.

#### TC-402c — Switch stage via [NAV] (clic sur cellule)

- **Chemin** : [NAV]
- **Invariants** : INV-8, INV-9
- **Action** :
  ```bash
  ./.build/debug/roadie stage 1 2>&1 ; sleep 0.5
  cliclick -e 600 m:0,500 ; sleep 2
  # Cellule stage 2 typiquement à y ≈ 600 (cascade verticale)
  cliclick c:160,600 ; sleep 1
  ./.build/debug/roadie daemon status 2>&1 | grep current_stage
  ```
- **Attendu** : `current_stage: 2`.

#### TC-403 — Hot-swap renderer change visuel sans toucher state

- **Chemin** : [CLI]
- **Invariants** : INV-2 (state immuable)
- **Action** :
  ```bash
  ./.build/debug/roadie rail renderer stacked-previews 2>&1 ; sleep 1
  ./.build/debug/roadie stage list 2>&1 > /tmp/hui-tc-403-before.txt
  cliclick -e 600 m:0,500 ; sleep 2 ; screencapture -x -R0,0,400,1280 /tmp/hui-tc-403-stacked.png
  ./.build/debug/roadie rail renderer icons-only 2>&1 ; sleep 2
  cliclick -e 600 m:0,500 ; sleep 2 ; screencapture -x -R0,0,400,1280 /tmp/hui-tc-403-icons.png
  ./.build/debug/roadie stage list 2>&1 > /tmp/hui-tc-403-after.txt
  diff /tmp/hui-tc-403-before.txt /tmp/hui-tc-403-after.txt
  ```
- **Attendu** : diff vide. `stacked.png` ≠ `icons.png` visuellement.

#### TC-404 — Renderer inconnu fallback default

- **Chemin** : [CLI]
- **Invariants** : INV-3
- **Action** :
  ```bash
  ./.build/debug/roadie rail renderer parallax-99 ; echo "exit=$?"
  ```
- **Attendu** : exit code ≠ 0.

#### TC-405a — Stage assign via [CLI]

- **Chemin** : [CLI]
- **Invariants** : INV-4
- **Action** :
  ```bash
  WID=$(./.build/debug/roadie windows list 2>&1 | grep "focused" | awk '{print $1}')
  ./.build/debug/roadie stage assign 2 ; sleep 0.5
  ./.build/debug/roadie windows list 2>&1 | grep "^$WID" | grep "stage=2"
  ```
- **Attendu** : la wid focused est dans stage 2.

#### TC-405b — Stage assign via [BTT] (`⌥+⇧+2`)

- **Chemin** : [BTT]
- **Invariants** : INV-9
- **Action** :
  ```bash
  WID=$(./.build/debug/roadie windows list 2>&1 | grep "focused" | awk '{print $1}')
  cliclick -e 200 kd:alt kd:shift kp:2 ku:shift ku:alt ; sleep 0.5
  ./.build/debug/roadie windows list 2>&1 | grep "^$WID" | grep "stage=2"
  ```
- **Attendu** : identique à TC-405a.

---

### Classe TC-500 — Drag-drop (NAV uniquement)

#### TC-501 — Drag d'une cellule de stage A vers cellule de stage B

- **Chemin** : [NAV]
- **Invariants** : INV-4, INV-8
- **Action** :
  ```bash
  ./.build/debug/roadie stage 1 2>&1 ; sleep 0.5
  cliclick -e 600 m:0,500 ; sleep 2
  cliclick -e 800 dd:160,600 m:160,400 du:160,300 ; sleep 1
  ./.build/debug/roadie windows list 2>&1 | grep "stage=" > /tmp/hui-tc-501-after.txt
  ```
- **Attendu** : nombre de wids stage=1 a augmenté.

---

### Classe TC-600 — Focus directionnel (vim-style et CLI)

> BTT : `⌘+H/J/K/L` → `roadie focus left/down/up/right`.

#### TC-601a — Focus left via [CLI]

- **Chemin** : [CLI]
- **Invariants** : INV-2, INV-10
- **Action** :
  ```bash
  WID_BEFORE=$(./.build/debug/roadie windows list 2>&1 | grep "focused" | awk '{print $1}')
  ./.build/debug/roadie focus left 2>&1 ; sleep 0.3
  WID_AFTER=$(./.build/debug/roadie windows list 2>&1 | grep "focused" | awk '{print $1}')
  echo "before=$WID_BEFORE after=$WID_AFTER"
  ```
- **Attendu** : `WID_BEFORE != WID_AFTER` (sauf bord de tree).

#### TC-601b — Focus left via [BTT] (`⌘+H`)

- **Chemin** : [BTT]
- **Invariants** : INV-9
- **Action** :
  ```bash
  WID_BEFORE=$(./.build/debug/roadie windows list 2>&1 | grep "focused" | awk '{print $1}')
  cliclick -e 100 kd:cmd kp:h ku:cmd ; sleep 0.3
  WID_AFTER=$(./.build/debug/roadie windows list 2>&1 | grep "focused" | awk '{print $1}')
  ```
- **Attendu** : identique à TC-601a.

#### TC-602 — Focus right (CLI + BTT)

Idem TC-601 avec `right` / `⌘+L`. 2 sous-TC : TC-602a [CLI], TC-602b [BTT].

#### TC-603 — Focus up (CLI + BTT)

Idem avec `up` / `⌘+K`. 2 sous-TC.

#### TC-604 — Focus down (CLI + BTT)

Idem avec `down` / `⌘+J`. 2 sous-TC.

---

### Classe TC-700 — Move (swap voisin)

> BTT : `⌘+⌥+H/J/K/L` → `roadie move left/down/up/right`.

#### TC-701a — Move left via [CLI]

- **Chemin** : [CLI]
- **Invariants** : INV-2, INV-10
- **Action** :
  ```bash
  WID=$(./.build/debug/roadie windows list 2>&1 | grep "focused" | awk '{print $1}')
  FRAME_BEFORE=$(./.build/debug/roadie windows list 2>&1 | grep "^$WID" | awk '{print $5}')
  ./.build/debug/roadie move left 2>&1 ; sleep 0.3
  FRAME_AFTER=$(./.build/debug/roadie windows list 2>&1 | grep "^$WID" | awk '{print $5}')
  ```
- **Attendu** : `FRAME_BEFORE != FRAME_AFTER`.

#### TC-701b — Move left via [BTT] (`⌘+⌥+H`)

- **Chemin** : [BTT]
- **Invariants** : INV-9
- **Action** : `cliclick -e 100 kd:cmd kd:alt kp:h ku:alt ku:cmd`. Vérifier frame change identique à 701a.

#### TC-702/703/704 — Move right/up/down (CLI + BTT)

Similaires avec respectivement `⌘+⌥+L`, `⌘+⌥+K`, `⌘+⌥+J`. 6 sous-TC au total.

---

### Classe TC-750 — Warp (split la cellule voisine)

> BTT : `⌘+⇧+H/J/K/L` → `roadie warp left/down/up/right`.

#### TC-751a/b — Warp left (CLI + BTT)

- **Chemin** : [CLI] puis [BTT]
- **Invariants** : INV-10
- **Action CLI** : `./.build/debug/roadie warp left ; sleep 0.3`
- **Action BTT** : `cliclick -e 100 kd:cmd kd:shift kp:h ku:shift ku:cmd`
- **Attendu** : la wid focused a changé de cellule, structure tree valide.

#### TC-752/753/754 — Warp right/up/down (CLI + BTT)

6 sous-TC.

---

### Classe TC-800 — Resize directionnel

> BTT : `⌘+⌃+H/J/K/L` → `roadie resize left/down/up/right 50` (delta 50 par défaut).

#### TC-801a — Resize left via [CLI] delta=0.05

- **Chemin** : [CLI]
- **Invariants** : INV-2
- **Action** :
  ```bash
  WID=$(./.build/debug/roadie windows list 2>&1 | grep "focused" | awk '{print $1}')
  FRAME_BEFORE=$(./.build/debug/roadie windows list 2>&1 | grep "^$WID" | awk '{print $5}')
  ./.build/debug/roadie resize left 0.05 2>&1 ; sleep 0.3
  FRAME_AFTER=$(./.build/debug/roadie windows list 2>&1 | grep "^$WID" | awk '{print $5}')
  ```
- **Attendu** : frame change.

#### TC-801b — Resize left via [BTT] (`⌘+⌃+H`, delta 50px)

- **Chemin** : [BTT]
- **Invariants** : INV-9
- **Action** : `cliclick -e 100 kd:cmd kd:ctrl kp:h ku:ctrl ku:cmd`. Vérifier frame change.

#### TC-802/803/804 — Resize right/up/down (CLI + BTT)

6 sous-TC.

#### TC-805 — Resize cumulatif (4 fois resize left), tree reste valide

- **Chemin** : [CLI]
- **Invariants** : INV-10
- **Action** :
  ```bash
  for i in 1 2 3 4; do ./.build/debug/roadie resize left 0.05 ; sleep 0.2 ; done
  ./.build/debug/roadie windows list 2>&1 | grep tiled  # ne doit pas avoir de frame dégénérée (w<10 ou h<10)
  ```
- **Attendu** : aucune wid avec width < 10 ou height < 10.

---

### Classe TC-900 — Toggle (floating, fullscreen)

> BTT : `⌥+V` floating, `⌥+F` fullscreen, `⌥+⇧+F` native-fullscreen.

#### TC-901a — Toggle floating via [CLI]

- **Chemin** : [CLI]
- **Action** :
  ```bash
  WID=$(./.build/debug/roadie windows list 2>&1 | grep "focused" | awk '{print $1}')
  ./.build/debug/roadie toggle floating 2>&1 ; sleep 0.3
  ./.build/debug/roadie windows list 2>&1 | grep "^$WID"
  ./.build/debug/roadie toggle floating 2>&1 ; sleep 0.3  # restaurer
  ```
- **Attendu** : la wid passe de tiled à float puis revient.

#### TC-901b — Toggle floating via [BTT] (`⌥+V`)

- **Chemin** : [BTT]
- **Action** : `cliclick -e 100 kd:alt kp:v ku:alt`. Vérifier identique 901a.

#### TC-902a/b — Toggle fullscreen (CLI / `⌥+F`)
#### TC-903a/b — Toggle native-fullscreen (CLI / `⌥+⇧+F`)

---

### Classe TC-1000 — Close window

#### TC-1001a — Close via [CLI]

- **Chemin** : [CLI]
- **Invariants** : INV-4 (wid retirée propre)
- **Préconditions** : créer une fenêtre jetable (TextEdit doc) ou skip
- **Action** :
  ```bash
  open -a TextEdit ; sleep 1
  WID=$(./.build/debug/roadie windows list 2>&1 | grep TextEdit | head -1 | awk '{print $1}')
  ./.build/debug/roadie close 2>&1 ; sleep 0.5
  ./.build/debug/roadie windows list 2>&1 | grep "^$WID" | wc -l
  ```
- **Attendu** : 0 (wid retirée).

#### TC-1001b — Close via [BTT] (`⌥+W`)

- **Chemin** : [BTT]
- **Action** : `cliclick -e 100 kd:alt kp:w ku:alt`. Vérifier identique.

---

### Classe TC-1100 — Hot-swap config

#### TC-1101 — Switch tiler bsp ↔ master-stack [CLI]

- **Chemin** : [CLI]
- **Invariants** : INV-10
- **Action** :
  ```bash
  ./.build/debug/roadie tiler master-stack 2>&1 ; sleep 1
  ./.build/debug/roadie daemon status 2>&1 | grep tiler
  ./.build/debug/roadie tiler bsp 2>&1 ; sleep 1
  ./.build/debug/roadie daemon status 2>&1 | grep tiler
  ```
- **Attendu** : strategy correct, daemon vivant après chaque swap.

#### TC-1102 — `daemon reload` préserve les stages

- **Chemin** : [CLI]
- **Invariants** : INV-3, INV-4
- **Action** :
  ```bash
  ./.build/debug/roadie stage list 2>&1 > /tmp/hui-tc-1102-before.txt
  ./.build/debug/roadie daemon reload 2>&1 ; sleep 1
  ./.build/debug/roadie stage list 2>&1 > /tmp/hui-tc-1102-after.txt
  diff /tmp/hui-tc-1102-before.txt /tmp/hui-tc-1102-after.txt
  ```
- **Attendu** : diff vide.

#### TC-1103 — Restart daemon via [BTT] (`⌘+⌃+R`)

- **Chemin** : [BTT]
- **Invariants** : INV-9
- **Action** :
  ```bash
  PID_BEFORE=$(pgrep -f "roadied --daemon")
  cliclick -e 200 kd:cmd kd:ctrl kp:r ku:ctrl ku:cmd ; sleep 5
  PID_AFTER=$(pgrep -f "roadied --daemon")
  echo "before=$PID_BEFORE after=$PID_AFTER"
  ./.build/debug/roadie daemon status 2>&1 | grep version
  ```
- **Attendu** : `PID_BEFORE != PID_AFTER`, daemon répond après restart.

---

### Classe TC-1200 — Edge cases

#### TC-1201 — Stage vide affiche placeholder

- **Chemin** : [CLI + NAV]
- **Invariants** : INV-3
- **Action** :
  ```bash
  ./.build/debug/roadie stage create 9 "EmptyTest" 2>&1
  ./.build/debug/roadie stage 9 2>&1 ; sleep 0.5
  cliclick -e 600 m:0,500 ; sleep 2
  screencapture -x -R0,0,400,1280 /tmp/hui-tc-1201.png
  ./.build/debug/roadie rail status 2>&1 | grep running
  ./.build/debug/roadie stage delete 9 2>&1 || true
  ```
- **Attendu** : rail vivant, placeholder visible (pas de crash).

#### TC-1202 — Stage > maxVisible wids → truncation

- **Chemin** : [NAV]
- **Préconditions** : ≥ 6 wids dans le stage actif (sinon SKIP)
- **Action** :
  ```bash
  cliclick -e 600 m:0,500 ; sleep 2
  screencapture -x -R0,0,400,1280 /tmp/hui-tc-1202.png
  ```
- **Attendu** : visuel correct selon le renderer.

#### TC-1203 — Hover répété ne change pas current_stage

- **Chemin** : [NAV]
- **Invariants** : INV-2
- **Action** :
  ```bash
  ./.build/debug/roadie daemon status 2>&1 | grep current_stage > /tmp/hui-tc-1203-before.txt
  for i in 1 2 3 4 5; do cliclick -e 200 m:0,$((300+i*100)) ; sleep 0.4 ; done
  cliclick m:1500,500 ; sleep 1
  ./.build/debug/roadie daemon status 2>&1 | grep current_stage > /tmp/hui-tc-1203-after.txt
  diff /tmp/hui-tc-1203-before.txt /tmp/hui-tc-1203-after.txt
  ```
- **Attendu** : diff vide.

#### TC-1204 — Daemon offline → rail état cohérent

- **Chemin** : [N/A]
- **Action** :
  ```bash
  pkill -f "roadied --daemon" ; sleep 2
  cliclick -e 600 m:0,500 ; sleep 2
  screencapture -x -R0,0,400,1280 /tmp/hui-tc-1204.png
  ./.build/debug/roadied --daemon > /tmp/roadied.log 2>&1 & sleep 4
  ```
- **Attendu** : rail ne crashe pas. Restaurer en fin de TC.

#### TC-1205 — Voyage display × desktop = état stable

- **Chemin** : [CLI + NAV]
- **Invariants** : INV-7
- **Préconditions** : 2 écrans (sinon SKIP)
- **Action** :
  ```bash
  ./.build/debug/roadie desktop focus 1 2>&1 ; sleep 0.5
  cliclick m:1000,500 ; sleep 1
  STATE_INIT=$(./.build/debug/roadie daemon status 2>&1 | grep current_scope)
  cliclick m:-100,1500 ; sleep 1  # 2nd écran
  ./.build/debug/roadie desktop focus 2 2>&1 ; sleep 0.5
  cliclick m:1000,500 ; sleep 1   # retour primary
  ./.build/debug/roadie desktop focus 1 2>&1 ; sleep 0.5
  STATE_FINAL=$(./.build/debug/roadie daemon status 2>&1 | grep current_scope)
  ```
- **Attendu** : daemon vivant, scope final cohérent (primary, desktop 1).

#### TC-1206 — Wallpaper-click crée une stage [WP]

- **Chemin** : [WP]
- **Invariants** : INV-3
- **Action** :
  ```bash
  STAGES_BEFORE=$(./.build/debug/roadie stage list 2>&1 | wc -l)
  # Click sur le wallpaper visible (zone non couverte par fenêtre)
  cliclick -e 200 c:50,1100 ; sleep 1
  STAGES_AFTER=$(./.build/debug/roadie stage list 2>&1 | wc -l)
  ```
- **Attendu** : nouvelle stage créée OU comportement sans crash si wallpaper-click désactivé.

---

### Classe TC-1300 — Composites multi-chemins

> Vérifient INV-9 (équivalence des chemins) sur des séquences réalistes.

#### TC-1301 — Switch stage [BTT] puis move [BTT] puis resize [CLI] : tree reste valide

- **Chemin** : [BTT]+[CLI]
- **Invariants** : INV-9, INV-10
- **Action** :
  ```bash
  cliclick -e 100 kd:alt kp:1 ku:alt ; sleep 0.3       # Alt+1 stage 1
  cliclick -e 100 kd:cmd kd:alt kp:l ku:alt ku:cmd ; sleep 0.3  # Cmd+Alt+L move right
  ./.build/debug/roadie resize right 0.10 2>&1 ; sleep 0.3
  ./.build/debug/roadie windows list 2>&1 | grep tiled | awk '{print $5}' | grep -E "[0-9]+x[0-9]+" \
    | awk -Fx '{if($1<10 || $2<10) print "DEGENERATE"}'
  ```
- **Attendu** : aucune ligne `DEGENERATE` (toutes les frames > 10×10).

#### TC-1302 — Drag-drop [NAV] puis switch [BTT] : la wid migrée est dans le bon stage

- **Chemin** : [NAV]+[BTT]
- **Invariants** : INV-4, INV-9
- **Action** :
  ```bash
  ./.build/debug/roadie stage 1 2>&1 ; sleep 0.5
  cliclick -e 600 m:0,500 ; sleep 2
  cliclick -e 800 dd:160,600 m:160,400 du:160,300 ; sleep 1
  cliclick -e 100 kd:alt kp:2 ku:alt ; sleep 0.5
  ./.build/debug/roadie windows list 2>&1 | grep "stage=2"
  ```
- **Attendu** : wids attendues dans stage 2 après le drag puis switch.

#### TC-1303 — Cycle complet desktop 1→2→1 [BTT] + stage 1→2→1 [NAV] : mémoire conservée

- **Chemin** : [BTT]+[NAV]
- **Invariants** : INV-7
- **Action** :
  ```bash
  ./.build/debug/roadie desktop focus 1 ; ./.build/debug/roadie stage 2 ; sleep 0.5
  cliclick -e 100 kd:cmd kp:2 ku:cmd ; sleep 0.5  # Cmd+2 desktop 2
  cliclick -e 100 kd:cmd kp:1 ku:cmd ; sleep 0.5  # Cmd+1 desktop 1
  cliclick -e 600 m:0,500 ; sleep 2
  cliclick c:160,300 ; sleep 0.5  # clic stage 1 sur navrail
  cliclick c:160,600 ; sleep 0.5  # clic stage 2 sur navrail
  ./.build/debug/roadie daemon status 2>&1 | grep current_stage
  ```
- **Attendu** : `current_stage: 2` (le NAV a switché à 2 en dernier).

#### TC-1304 — Restart daemon [BTT] pendant rail visible : rail récupère

- **Chemin** : [BTT]+[NAV]
- **Invariants** : INV-3
- **Action** :
  ```bash
  cliclick -e 600 m:0,500 ; sleep 2
  cliclick -e 200 kd:cmd kd:ctrl kp:r ku:ctrl ku:cmd ; sleep 6
  cliclick -e 600 m:0,500 ; sleep 2
  screencapture -x -R0,0,400,1280 /tmp/hui-tc-1304.png
  ./.build/debug/roadie stage list 2>&1 | grep "stage 1\|^\* 1"
  ```
- **Attendu** : rail re-affiche les stages (stage 1 minimum) après restart.

#### TC-1305 — Hot-swap renderer pendant drag-drop : pas de freeze

- **Chemin** : [CLI]+[NAV]
- **Invariants** : INV-3
- **Action** :
  ```bash
  cliclick -e 600 m:0,500 ; sleep 2
  cliclick dd:160,600 m:160,500 ; sleep 0.3  # drag in progress
  ./.build/debug/roadie rail renderer icons-only 2>&1 ; sleep 1
  cliclick du:160,300 ; sleep 1  # release
  ./.build/debug/roadie rail status 2>&1 | grep running
  ./.build/debug/roadie rail renderer stacked-previews 2>&1
  ```
- **Attendu** : rail running après l'opération, pas de freeze.

---

## Section 3 — Grille d'évaluation

Conventions :
- `Status` : `PASS` | `FAIL` | `BLOCKED` (précondition non remplie) | `SKIP` (matériel manquant) | `PENDING` | `DEPRECATED`
- `Fix applied` : commit short + chemin fichier(s) + 1 phrase rationale. Vide si PASS.
- `Post-fix status` : `PASS` après fix, `STILL_FAIL` sinon, `N/A` sinon.
- `Phase 3 status` : à remplir après la passe finale uniquement.
- `Evidence` : chemin PNG ou log extrait.

| TC | Path | Status | Observed | Expected | Gap | Fix applied | Post-fix | Phase 3 | Evidence |
|---|---|---|---|---|---|---|---|---|---|
| TC-101 | CLI | PASS | `* 1 (1) — 4 window(s)` | Stage 1 listée sur primary | — | — | N/A | | /tmp/hui-tc-101.txt |
| TC-102 | CLI | PASS | 1 section (1 écran) avec stage 1 | Stage 1 sur chaque écran | — | — | N/A | | /tmp/hui-tc-102.txt |
| TC-103 | FS | PASS | 0 fichier avec frame 66×20 | Aucun helper 66×20 sur disque | — | — | N/A | | /tmp/hui-tc-103.txt |
| TC-104 | FS | PASS | 0 wid en doublon | Aucune wid double-attribuée | — | — | N/A | | /tmp/hui-tc-104.txt |
| TC-105 | BTT | PASS | 58 hotkeys roadie | ≥ 50 hotkeys roadie configurés | — | — | N/A | | /tmp/btt-roadie-map.txt |
| TC-201 | NAV | PASS | Panel apparaît avec vignette + halo vert au hover x=0,y=640 | Hover gauche fait apparaître panel | — | — | N/A | | /tmp/hui-tc-201-after-fix.png |
| TC-202 | NAV | PASS | 1 stage daemon = 1 cellule rail | Cellules = stages du primary | — | — | N/A | | /tmp/hui-tc-202-state.txt |
| TC-203 | NAV | SKIP | 1 écran seulement | Chaque panel = stages distincts | — | — | N/A | | matériel manquant |
| TC-204 | CLI | PARTIAL_PASS | scope retourné cohérent sur primary | stage list reflète scope curseur | 2nd écran absent → pas de diff cross-display | — | N/A | | /tmp/hui-tc-204-primary.txt |
| TC-205 | CLI | SKIP | 1 écran seulement | display focus N change display courant | — | — | N/A | | matériel manquant |
| TC-301a | CLI | PENDING | | Mémoire stage à l'aller-retour D1↔D2 | | | | | |
| TC-301b | BTT | PENDING | | Idem 301a via Cmd+1/Cmd+2 | | | | | |
| TC-301c | BTT | PENDING | | Alt+Shift+N incrémente desktop | | | | | |
| TC-302 | CLI | PENDING | | Wids D1 hidden offscreen sur D2 | | | | | |
| TC-303 | CLI | PENDING | | Stage 1 auto-créée sur desktop neuf | | | | | |
| TC-304 | BTT | PENDING | | Cycle Cmd+1..0+1 daemon vivant | | | | | |
| TC-305 | BTT | PENDING | | Cmd+Shift+N déplace wid cross-desktop | | | | | |
| TC-306 | BTT | PENDING | | Cmd+Alt+Ctrl+N déplace wid cross-display | | | | | |
| TC-401 | NAV | PENDING | | Halo conditionnel stage active | | | | | |
| TC-402a | CLI | PENDING | | Switch stage hide les wids quittés | | | | | |
| TC-402b | BTT | PENDING | | Idem 402a via Alt+1/Alt+2 | | | | | |
| TC-402c | NAV | PENDING | | Idem 402a via clic cellule | | | | | |
| TC-403 | CLI | PENDING | | Hot-swap renderer ne touche pas state | | | | | |
| TC-404 | CLI | PENDING | | Renderer inconnu = exit ≠ 0 | | | | | |
| TC-405a | CLI | PENDING | | stage assign N déplace wid focused | | | | | |
| TC-405b | BTT | PENDING | | Idem 405a via Alt+Shift+N | | | | | |
| TC-501 | NAV | PENDING | | Drag-drop cellule réassigne wid | | | | | |
| TC-601a | CLI | PENDING | | focus left change wid focused | | | | | |
| TC-601b | BTT | PENDING | | Idem 601a via Cmd+H | | | | | |
| TC-602a | CLI | PENDING | | focus right change wid focused | | | | | |
| TC-602b | BTT | PENDING | | Idem 602a via Cmd+L | | | | | |
| TC-603a | CLI | PENDING | | focus up change wid focused | | | | | |
| TC-603b | BTT | PENDING | | Idem 603a via Cmd+K | | | | | |
| TC-604a | CLI | PENDING | | focus down change wid focused | | | | | |
| TC-604b | BTT | PENDING | | Idem 604a via Cmd+J | | | | | |
| TC-701a | CLI | PENDING | | move left swap voisin | | | | | |
| TC-701b | BTT | PENDING | | Idem 701a via Cmd+Alt+H | | | | | |
| TC-702a | CLI | PENDING | | move right swap | | | | | |
| TC-702b | BTT | PENDING | | Idem via Cmd+Alt+L | | | | | |
| TC-703a | CLI | PENDING | | move up swap | | | | | |
| TC-703b | BTT | PENDING | | Idem via Cmd+Alt+K | | | | | |
| TC-704a | CLI | PENDING | | move down swap | | | | | |
| TC-704b | BTT | PENDING | | Idem via Cmd+Alt+J | | | | | |
| TC-751a | CLI | PENDING | | warp left split voisin | | | | | |
| TC-751b | BTT | PENDING | | Idem via Cmd+Shift+H | | | | | |
| TC-752a | CLI | PENDING | | warp right split | | | | | |
| TC-752b | BTT | PENDING | | Idem via Cmd+Shift+L | | | | | |
| TC-753a | CLI | PENDING | | warp up split | | | | | |
| TC-753b | BTT | PENDING | | Idem via Cmd+Shift+K | | | | | |
| TC-754a | CLI | PENDING | | warp down split | | | | | |
| TC-754b | BTT | PENDING | | Idem via Cmd+Shift+J | | | | | |
| TC-801a | CLI | PENDING | | resize left modifie frame | | | | | |
| TC-801b | BTT | PENDING | | Idem via Cmd+Ctrl+H | | | | | |
| TC-802a | CLI | PENDING | | resize right modifie frame | | | | | |
| TC-802b | BTT | PENDING | | Idem via Cmd+Ctrl+L | | | | | |
| TC-803a | CLI | PENDING | | resize up modifie frame | | | | | |
| TC-803b | BTT | PENDING | | Idem via Cmd+Ctrl+K | | | | | |
| TC-804a | CLI | PENDING | | resize down modifie frame | | | | | |
| TC-804b | BTT | PENDING | | Idem via Cmd+Ctrl+J | | | | | |
| TC-805 | CLI | PENDING | | resize x4 ne dégénère pas le tree | | | | | |
| TC-901a | CLI | PENDING | | toggle floating ↔ tiled | | | | | |
| TC-901b | BTT | PENDING | | Idem via Alt+V | | | | | |
| TC-902a | CLI | PENDING | | toggle fullscreen | | | | | |
| TC-902b | BTT | PENDING | | Idem via Alt+F | | | | | |
| TC-903a | CLI | PENDING | | toggle native-fullscreen | | | | | |
| TC-903b | BTT | PENDING | | Idem via Alt+Shift+F | | | | | |
| TC-1001a | CLI | PENDING | | close retire la wid | | | | | |
| TC-1001b | BTT | PENDING | | Idem via Alt+W | | | | | |
| TC-1101 | CLI | PENDING | | Switch tiler bsp ↔ master-stack | | | | | |
| TC-1102 | CLI | PENDING | | daemon reload préserve stages | | | | | |
| TC-1103 | BTT | PENDING | | Cmd+Ctrl+R restart daemon | | | | | |
| TC-1201 | NAV | PENDING | | Stage vide = placeholder neutre | | | | | |
| TC-1202 | NAV | PENDING | | > maxVisible wids = truncation | | | | | |
| TC-1203 | NAV | PENDING | | Hover répété ne switch pas | | | | | |
| TC-1204 | NAV | PENDING | | Daemon offline = état clair | | | | | |
| TC-1205 | NAV | PENDING | | Voyage display×desktop stable | | | | | |
| TC-1206 | WP | PENDING | | Wallpaper-click crée stage | | | | | |
| TC-1301 | BTT+CLI | PENDING | | Switch+move+resize tree valide | | | | | |
| TC-1302 | NAV+BTT | PENDING | | Drag puis switch wid bon stage | | | | | |
| TC-1303 | BTT+NAV | PENDING | | Cycle desktop+stage mémoire OK | | | | | |
| TC-1304 | BTT+NAV | PENDING | | Restart pendant rail visible récupère | | | | | |
| TC-1305 | CLI+NAV | PENDING | | Swap renderer pendant drag pas freeze | | | | | |

### Synthèse par classe

| Classe | Total | PASS | FAIL | BLOCKED | SKIP | Tag commit |
|---|---|---|---|---|---|---|
| TC-100 boot | 5 | 5 | 0 | 0 | 0 | tc-class-boot-pass |
| TC-200 display | 5 | 3 | 0 | 0 | 2 | tc-class-display-pass |
| TC-300 desktop | 8 | 0 | 0 | 0 | 0 | — |
| TC-400 stage | 9 | 0 | 0 | 0 | 0 | — |
| TC-500 drag-drop | 1 | 0 | 0 | 0 | 0 | — |
| TC-600 focus | 8 | 0 | 0 | 0 | 0 | — |
| TC-700 move | 8 | 0 | 0 | 0 | 0 | — |
| TC-750 warp | 8 | 0 | 0 | 0 | 0 | — |
| TC-800 resize | 9 | 0 | 0 | 0 | 0 | — |
| TC-900 toggle | 6 | 0 | 0 | 0 | 0 | — |
| TC-1000 close | 2 | 0 | 0 | 0 | 0 | — |
| TC-1100 hot-swap | 3 | 0 | 0 | 0 | 0 | — |
| TC-1200 edge | 6 | 0 | 0 | 0 | 0 | — |
| TC-1300 composites | 5 | 0 | 0 | 0 | 0 | — |
| **Total** | **83** | **0** | **0** | **0** | **0** | — |

### Combinatoires hors-périmètre (cf. ADR-007)

| Combinatoire | Statut | Cause |
|---|---|---|
| Mode `global` × 2 displays | OUT_OF_SCOPE | Le rail n'expose qu'un panel sur primary par construction |
| Renderer `mosaic`/`hero-preview`/`parallax-45` | DEFERRED | US3-US5 SPEC-019 non livrés |
| Tiler ≠ BSP/Master-Stack | OUT_OF_SCOPE | Aucun autre tiler |
| Multi-utilisateurs simultanés | OUT_OF_SCOPE | PID-lock SPEC-001 |
| Permissions Accessibility absentes | OUT_OF_SCOPE | Prérequis daemon |

### Estimation temps de passage

- Phase 1 Setup : 5 min
- Phase 2 par TC (moyenne) : 2 min × 83 = **~3 h** sans fix
- Phase 3 régression : ~45 min
- Avec fixes (3-5 cycles typiques) : **+45-90 min**
- **Total estimé : 4 à 5h pour une passe complète sur 83 TC**

L'agent peut paralléliser au sein d'une même classe quand les TC sont indépendants. L'ordre **inter-classes** doit être respecté (boot avant display avant desktop avant stage, etc.).
