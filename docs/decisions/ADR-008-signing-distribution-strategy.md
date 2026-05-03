# ADR-008 — Stratégie signature de code, permissions Accessibility et distribution

**Date** : 2026-05-03 | **Statut** : Accepté pour la phase dev. Ouvert pour les phases beta/release.

## Contexte

Le développement de roadie a fait apparaître un problème récurrent : à chaque rebuild du daemon, la permission **Accessibility** (TCC) est silencieusement révoquée par macOS, ce qui empêche le daemon de démarrer (`AXIsProcessTrusted` retourne false → exit 2). Le launchd `KeepAlive` re-spawn en boucle, log `permission Accessibility manquante`, sans solution évidente côté UI Réglages Système puisque sur macOS Sonoma+ le Prefpane refuse l'ajout d'un binaire qui n'est pas dans une `.app`.

Trois sous-problèmes distincts à clarifier en une seule décision :

1. **Le binaire doit être dans une `.app` bundle.** Sur Sonoma/Sequoia, le panneau Accessibility refuse les binaires nus (drag-and-drop ou `+` rejetés). Apple DTS (Quinn the Eskimo) a confirmé publiquement que faire tourner un daemon « comme un user » est non-supporté ; la pattern officielle est de wrapper le binaire dans un bundle.
2. **TCC ancre la permission à la signature de code, pas au chemin.** À chaque `swift build`, la signature ad-hoc change → TCC traite le binaire comme un nouveau programme et drop la grant existante. Solution canonique (yabai + AeroSpace + d'autres) : signer avec un certificat self-signed stable, identique à chaque rebuild, ce qui maintient l'identité TCC.
3. **Au moins deux installs de roadie coexistaient sur la machine dev** (`/Applications/Roadie.app` + `~/Applications/roadied.app`), avec des binaires différents pointés par un launchd plist d'un côté et un symlink `~/.local/bin/roadied` de l'autre. Quand un crash survenait, l'auto-restart launchd redémarrait l'ancienne build pendant que les `cp` du workflow dev modifiaient l'autre. Source de désync persistance disque ↔ binaire en mémoire.

## Décision

### 1. Architecture d'installation **dev** (machine du mainteneur)

Une seule install canonique :

| Élément | Chemin | Rôle |
|---|---|---|
| Binaire daemon (réel, fichier) | `~/Applications/roadied.app/Contents/MacOS/roadied` | Seul exécutable lancé. TCC ancré ici. |
| Symlink dev | `~/.local/bin/roadied` → bundle ci-dessus | Pour `cp .build/debug/roadied ~/.local/bin/` qui dérefère et MAJ le bundle. Sécurise le workflow dev existant. |
| Binaire CLI client | `~/.local/bin/roadie` (fichier réel) | Client IPC. Signé aussi pour cohérence. |
| Binaire rail | `~/.local/bin/roadie-rail` (fichier réel) | Lancé manuellement par `install-dev.sh`, pas par launchd. |
| LaunchAgent | `~/Library/LaunchAgents/com.roadie.roadie.plist` | `RunAtLoad=true`, `KeepAlive.Crashed=true`, pointe vers `~/Applications/roadied.app/Contents/MacOS/roadied`. |
| Certificat dev | `roadied-cert` (login keychain, type Code Signing, Self Signed Root) | Identité stable. Créé une fois via Keychain Access > Certificate Assistant. |

Tout autre `.app` de roadie est interdit (les bundles `/Applications/Roadie.app` orphelins doivent être supprimés à la première détection).

### 2. Workflow dev unique : `scripts/install-dev.sh`

Ce script est **le seul** point d'entrée pour propager une nouvelle build vers le système :

1. `swift build` (PATH override anaconda — règle MEMORY.md projet).
2. `launchctl bootout` du daemon courant + `pkill` sur rail et events --follow zombies.
3. `cp .build/debug/{roadied,roadie-rail,roadie}` aux 3 cibles.
4. Crée le `Info.plist` du bundle si absent (CFBundleExecutable=roadied, LSUIElement=true).
5. **`codesign -fs roadied-cert`** sur chacun des 3 binaires (préserve la grant Accessibility).
6. `launchctl bootstrap` du LaunchAgent + relance manuelle de roadie-rail.

Toute autre méthode de mise à jour des binaires (édition manuelle, `cp` direct, `brew install`, etc.) est interdite tant qu'on est en phase dev — elle invaliderait soit le path stable, soit la signature TCC, soit les deux.

### 3. Identité TCC pérenne

Le certificat `roadied-cert` est self-signed root, type Code Signing, dans le login keychain. Il est partagé entre les 3 binaires (daemon, rail, CLI). Il ne contient **aucune information personnelle** (juste un nom de cert), n'est jamais commité dans le repo. Il est créé manuellement par chaque développeur du projet — son contenu n'a pas besoin d'être identique entre développeurs, c'est une convention de nom uniquement.

Conséquences :
- Permission Accessibility donnée **une seule fois** au binaire `~/Applications/roadied.app/Contents/MacOS/roadied`. Elle survit à tous les rebuilds.
- Si le cert est supprimé du keychain ou expiré, il faut en re-générer un (même nom) et re-cocher la grant. C'est un événement rare (cert sans expiration explicite par défaut).
- Si un développeur change le nom du cert (`ROADIE_CERT=foo ./scripts/install-dev.sh`), il devra re-cocher la grant pour ce nouvel identifiant TCC.

### 4. Stratégie de distribution **end-user** (phase ultérieure, non immédiate)

Trois chemins possibles, choix à figer plus tard :

| Chemin | Coût mainteneur | Friction utilisateur | Compatible HypRoadie SIP-off (SPEC-004+) ? |
|---|---|---|---|
| **A. Notarization Apple** | 99 $/an Apple Developer Program + soumission notarization à chaque release | Zéro warning, seule la perm Accessibility reste manuelle | **Non** — Apple refuse de notariser le code qui touche au Dock |
| **B. Developer ID signé non-notarisé** (modèle AeroSpace) | 99 $/an Apple Developer Program (cert renouvelé à expiration) | Faible : Homebrew cask strip auto le `com.apple.quarantine` xattr ; utilisateur coche Accessibility une fois | **Oui** pour le core, en gardant les modules SIP-off dans une distribution séparée |
| **C. Self-sign user-side** (modèle yabai) | 0 $ | **Élevée** : chaque utilisateur génère son cert local, exécute `codesign -fs` après chaque upgrade brew | **Oui** sans contrainte |

Décision pour roadie :

- **Core roadie** (SPEC-001/002/003 et famille) → cible chemin B (Developer ID + Homebrew cask). Public visé : tous utilisateurs macOS, friction quasi-nulle. Active à partir du moment où le projet a son premier release publique.
- **HypRoadie modules opt-in** (SPEC-004+) → chemin C (self-sign user-side) avec un script séparé `install-fx.sh`. Public visé : power-users qui ont volontairement désactivé SIP. Conforme à la position non-négociable de l'utilisateur (« compartimentation totale », plan SIP-off § P1).

Le chemin A est **explicitement rejeté** dès le départ : il interdirait toute évolution future vers HypRoadie, ce qui est non négociable.

## Conséquences

### Positives

- **Plus de pertes de grant Accessibility entre rebuilds** : la signature stable garantit l'identité TCC. Le mainteneur ne re-coche jamais.
- **Workflow dev déterministe** : `./scripts/install-dev.sh` est le seul point d'entrée, le résultat est reproductible.
- **Élimination du désync « 2 installs roadie »** : un seul .app, un seul launchd, un seul cert.
- **Distribution future préparée sans dette technique** : le bundle structure est déjà conforme à Developer ID / Homebrew cask. Le jour où on switch vers le programme Apple, il suffit de remplacer `roadied-cert` par le Developer ID dans le script.
- **HypRoadie SIP-off resté possible** : la décision n'enferme pas le projet dans la notarization.

### Négatives

- **Création manuelle du cert** : chaque développeur (et chaque user yabai-style si chemin C activé pour le core) doit exécuter une démarche GUI dans Keychain Access pour créer le cert. Pas automatisable. Documenté dans le README dev.
- **Accessibility manuelle reste obligatoire** : l'API TCC ne permet PAS d'ajouter programmatiquement un binaire à la liste Accessibility (Apple DTS confirmé). C'est une limite OS, pas du projet.
- **Le cert dev expirera un jour** (par défaut Self Signed Root sans validité explicite = ~365 jours selon Keychain Access). À ce moment, re-création + re-grant. Acceptable pour un solo dev, à documenter pour la phase équipe.
- **`scripts/install-dev.sh` doit rester maintenu en miroir de la convention bundle** : si on déplace le path du bundle, ou si on renomme le cert, ou si on touche à la structure Info.plist, le script doit suivre — c'est la single source of truth de l'install dev.

### Neutres

- Pas d'impact sur les SPECs en cours (SPEC-014/018/019). C'est une couche infra orthogonale.
- Pas d'impact sur la roadmap HypRoadie (SPEC-004+). Au contraire, la décision la prépare proprement.

## Alternatives considérées

1. **Signer avec `codesign --force --sign -`** (signature ad-hoc explicite, pas de cert). Rejeté : produit une signature aléatoire à chaque rebuild → identique au comportement non-signé, drop TCC.
2. **Désactiver TCC partiellement via `tccutil`**. Rejeté : nécessite SIP off complet, hors scope core, atteint la posture sécurité de la machine bien au-delà du nécessaire.
3. **Faire tourner le daemon comme `LaunchDaemon` system (root)** au lieu de `LaunchAgent` user. Rejeté : Apple DTS explicitement déconseille la pattern « daemon root + UserName=user pour faire semblant d'être en session », et `roadied` a besoin de l'AX API qui requiert une session GUI.
4. **Embarquer le daemon dans un `.xpc` service signé par la `.app` GUI**. Rejeté : roadie n'a pas (encore) d'app GUI propriétaire, et ce serait sur-architecturer pour un outil CLI.
5. **Distribuer en chemin A direct (notarization Apple)**. Rejeté : interdit l'évolution HypRoadie, c'est dealbreaker per la position utilisateur.

## Sources

- [Apple Developer Forums — daemons are unable to access files (Quinn the Eskimo, DTS)](https://developer.apple.com/forums/thread/118508)
- [Chris Paynter — *What to do when your macOS daemon gets blocked by TCC dialogues*](https://chrispaynter.medium.com/what-to-do-when-your-macos-daemon-gets-blocked-by-tcc-dialogues-d3a1b991151f)
- [yabai wiki — *Installing yabai (from HEAD)*](https://github.com/koekeishiya/yabai/wiki/Installing-yabai-(from-HEAD)) (workflow `codesign -fs yabai-cert` qui inspire `roadied-cert`)
- [AeroSpace README](https://github.com/nikitabobko/AeroSpace) (modèle Developer ID non-notarisé + Homebrew cask qui strip quarantine)
- [Apple Developer — Signing Mac Software with Developer ID](https://developer.apple.com/developer-id/)
- [Apple Developer — Developer ID](https://developer.apple.com/support/developer-id/) (programme 99 $/an)
- [rsms — *macOS distribution gist*](https://gist.github.com/rsms/929c9c2fec231f0cf843a1a746a416f5) (vue panoramique signing/notarization/quarantine)
- [Apple Developer Forums — *Add application to accessibility list*](https://developer.apple.com/forums/thread/119373) (impossibilité d'automatiser l'ajout Accessibility)
