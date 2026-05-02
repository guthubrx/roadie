# Research — SPEC-013 Desktop par Display

**Date** : 2026-05-02
**Phase** : 0 (technique uniquement, business done in /speckit.specify)

## Décisions techniques

### R1 — Identifiant stable du display physique

**Decision** : utiliser `CGDisplayCreateUUIDFromDisplayID(_:)?.takeRetainedValue()` (Core Graphics public API) pour obtenir un UUID String stable par écran physique.

**Rationale** :
- `CGDirectDisplayID` (UInt32) **change** entre branchements/redémarrages (alloué dynamiquement par l'OS).
- L'UUID retourné par CG est dérivé du serial number du panel + ID physique → stable tant que l'écran n'est pas reflashé.
- Déjà utilisé dans SPEC-012 (`Display.uuid`) pour l'identification cross-session.
- Disponible sur macOS 10.6+ (largement compatible).

**Alternatives considered** :
- `IOServiceMatching("IODisplayConnect")` IORegistry — plus compliqué, pas plus stable, nécessite plus de plomberie.
- `kCGDisplayProductName` + `kCGDisplaySerialNumber` concat — parfois absent sur certains écrans génériques (renvoient nil).
- ID matching par dimensions+position — instable (l'écran peut être déplacé en config Réglages Système).

**Sources** :
- Apple CGDirectDisplay docs : `https://developer.apple.com/documentation/coregraphics/1455727-cgdisplaycreateuuidfromdisplayid`
- AeroSpace fait pareil (`Sources/AppBundle/desktop/MonitorTracker.swift`) → battle-tested.

---

### R2 — Sérialisation TOML per-display

**Decision** : un dossier par UUID `~/.config/roadies/displays/<displayUUID>/` contenant :
- `current.toml` — `current_desktop_id = N`
- `desktops/<id>/state.toml` — fenêtres assignées au desktop N de cet écran (format identique à SPEC-011)

**Rationale** :
- Granularité par display × desktop = un seul fichier mute par focus → atomicité simple.
- Format TOML déjà utilisé partout (Config, SPEC-011 state). Pas de nouvelle dépendance.
- Un `cat ~/.config/roadies/displays/*/desktops/*/state.toml` dump tout l'état pour debug.
- Le dossier d'un écran absent reste sur disque → ré-utilisé au rebranchement.

**Alternatives considered** :
- Un seul big TOML `~/.config/roadies/state.toml` avec sections par display × desktop : meilleur en perf (1 fichier mute) mais plus complexe à manipuler à la main, et un crash en cours d'écriture peut corrompre tout.
- SQLite : casse principe E (TOML/texte plat).
- JSON par fichier : casse principe E aussi (TOML imposé pour cohérence avec config).

**Sources** :
- TOMLKit Swift package (déjà utilisé)
- AeroSpace structure persistance : `~/.config/aerospace/state-v1` plat → leur layout est plus monolithique mais ils ne supportent pas le rebranchement avec restoration (différence de scope).

---

### R3 — Détection branchement/débranchement

**Decision** : observer `NSApplication.didChangeScreenParametersNotification` sur le main run loop, comparer la liste actuelle des `Display.id` avec le snapshot précédent, déclencher la logique recovery (déjà implémentée en SPEC-012 T026/T029) + nouvelle logique restoration (T028 SPEC-013).

**Rationale** :
- Notification système native macOS, fire dans 1-3 s après plug/unplug physique.
- Déjà observée dans `roadied/main.swift` ligne 386-401 → on étend simplement le handler `handleDisplayConfigurationChange`.
- Pas besoin de polling ni IOKit hotplug listener.

**Alternatives considered** :
- `IOPMScheduleRepowerOnWake` notifications : trop bas niveau, non requis ici.
- Polling NSScreen.screens chaque 5 s : coût CPU + délai perçu.

**Sources** :
- `NSApplication.didChangeScreenParametersNotification` docs Apple
- SPEC-012 implémentation actuelle (validée en run-time)

---

### R4 — Matching de fenêtres au rebranchement

**Decision** : matching à 2 niveaux :
1. **Niveau 1 — `cgWindowID`** : si la fenêtre persistée (cgwid X) est encore dans le `WindowRegistry` au moment du rebranchement, on matche directement et on restore la frame.
2. **Niveau 2 — `bundleID + title (prefix N chars)`** : si cgwid n'est plus connu (process redémarré), on cherche la première fenêtre du registry vivante dont `bundleID == persisted.bundleID` ET `title.hasPrefix(persisted.titlePrefix)`. Si match unique → restore. Si ambiguë (≥ 2 candidats) → log debug + skip (cas rare).

**Rationale** :
- `cgWindowID` est le clé canonique du projet (constitution C). Niveau 1 couvre le cas commun (daemon reste up, écran rebranche).
- Niveau 2 est un fallback pragmatique pour la résilience cross-session (daemon redémarre puis utilisateur rebranche écran). Pas de violation de constitution C — on ne fait PAS un matching purement basé sur `(bundle, title)` comme clé primaire ; c'est un fallback explicit, loggué et limité au scope recovery.

**Alternatives considered** :
- Matching uniquement par cgwid : perd la restoration cross-session.
- Matching par AX `kAXDocumentAttribute` : non supporté par toutes les apps.

**Sources** :
- Constitution principe C (négociation : fallback explicite OK, clé primaire interdite)
- Patterns AeroSpace `WindowMatcher.swift`

---

### R5 — Migration V2 → V3 idempotente

**Decision** : au boot du daemon, vérifier la présence de `~/.config/roadies/desktops/` (legacy V2). Si présent ET `~/.config/roadies/displays/` n'existe pas ou est vide → exécuter migration :
1. Récupérer `primaryUUID` depuis `DisplayRegistry.displays.first(where: { $0.isMain })`.
2. `mv ~/.config/roadies/desktops ~/.config/roadies/displays/<primaryUUID>/desktops`
3. Créer `~/.config/roadies/displays/<primaryUUID>/current.toml` avec le current global lu depuis l'ancien `desktops/state-current.toml` ou défaut `1`.
4. Logger `migration v2->v3 completed` avec count de desktops migrés.

**Rationale** :
- One-shot via `FileManager.moveItem` — atomique sur même volume.
- Idempotent : si `desktops/` legacy a déjà été migré (= n'existe plus), aucune action.
- Aucune perte de données : opération `move`, pas `copy`+`delete`.
- Permet à l'utilisateur de revenir en V2 en faisant l'inverse manuellement (pas de format breaking).

**Alternatives considered** :
- Lecture+ré-écriture (parser et regénérer) : fragile + risque de perte si crash entre les deux.
- Migration via script externe : casse principe ergonomique (l'utilisateur ne doit rien faire).

**Sources** :
- Pattern POSIX `rename(2)` atomique sur même filesystem.
- Constitution principe E (TOML plat, donc une migration = juste un déplacement de dossier).

---

### R6 — Switch de mode global ↔ per_display à chaud

**Decision** : `daemon reload` re-lit la config, détecte le changement de `mode`, et applique :
- `global → per_display` : `currentByDisplay` est conservé tel quel (chaque display avait déjà la même valeur globale, ils gardent cette valeur indépendamment).
- `per_display → global` : on prend le `currentByDisplay[primaryID]` comme nouvelle valeur globale, on synchronise toutes les autres entries dessus, on bascule visuellement les fenêtres des autres écrans pour matcher.

**Rationale** :
- Préserve le state de l'utilisateur dans les deux directions.
- En `per_display → global`, l'utilisateur voit possiblement basculer ses fenêtres : c'est attendu (il a demandé le mode global qui synchronise les écrans).
- Ne nécessite aucune migration disque (le format persistance est identique dans les deux modes).

**Alternatives considered** :
- Ne pas supporter le switch à chaud, exiger un restart : moins UX-friendly.
- En `per_display → global`, garder le current du primary mais cacher les autres fenêtres sans les afficher : laisse l'utilisateur perdu.

**Sources** :
- Pattern `reload-config` yabai et hyprland (les deux supportent le hot-reload).

---

### R7 — Coût implémentation et risque

**Estimation** :
- Code Swift à ajouter : ~600 LOC effectives (cf. plan).
- Tests : 6 fichiers nouveaux (~400 LOC).
- Touche surface : 5 fichiers existants modifiés + 2 nouveaux fichiers (DesktopMigration.swift, possibility 1 helper).
- Risque principal : régressions sur le mode `global` (= V2 actuel). Mitigation : tests d'acceptance dédiés (US-1 scenario 3, US-2 scenario 3, US-3 scenario 4) + le défaut `mode = "global"` garantit que les utilisateurs existants ne ressentent rien.

**Rationale** : pas de NEEDS CLARIFICATION restant ; pas de risque architectural majeur (extension propre du modèle SPEC-011). Plan prêt pour Phase 1 (data-model + contracts + tasks).
