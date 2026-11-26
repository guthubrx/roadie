# Comparatif : Roadie face aux gestionnaires de fenêtres, lanceurs et sélecteurs macOS

*Comparatif factuel établi en novembre 2026 à partir de la documentation publique des projets cités et du code source de Roadie (`main`). Aucun concurrent n’est présenté de manière exhaustive ; si un projet a ajouté une fonctionnalité ou modifié son modèle depuis cette date, une issue ou une PR de correction est bienvenue.*

[English version](../en/comparison.md) · [Documentation française](README.md) · [README principal](../../README.fr.md)

---

## Positionnement en une phrase

La plupart des utilisateurs macOS avancés combinent **3 à 5 outils distincts** : un gestionnaire de fenêtres (AeroSpace, yabai, OmniWM, Rift…), un lanceur (Raycast ou Alfred), un sélecteur de fenêtres (AltTab) et souvent un gestionnaire de raccourcis/gestes (skhd, BetterTouchTool, Karabiner).

**Roadie réunit cet ensemble dans une seule application macOS locale, gratuite et open source (Apache-2.0)**, sans désactiver SIP, sans compte, sans abonnement et sans télémétrie — tout en restant compatible avec BetterTouchTool et Karabiner si tu préfères les garder.

---

## 1. Gestionnaires de fenêtres (Window Managers macOS)

| Critère | **Roadie** | **AeroSpace** | **yabai** | **OmniWM** | **Rift** | **Amethyst** |
|---|---|---|---|---|---|---|
| **Licence & modèle** | Apache-2.0 (gratuit) | MIT (gratuit) | MIT (gratuit) | GPL-2.0 (gratuit) | Open source / MIT (gratuit, Rust) | MIT (gratuit) |
| **SIP reste activé** | Oui (toujours) | Oui (toujours) | Partiel *(SIP partiellement désactivé pour la scripting addition : Spaces instantanés, ombres, opacité)* | Oui (toujours) | Oui (toujours) | Oui (toujours) |
| **Prérequis macOS** | macOS 14+ | macOS 13+ | macOS récents | Apple Silicon, macOS 26+ | macOS récents | macOS récents |
| **Dispositions (layouts)** | `spatialBsp` (arbre persistant), `bsp`, `masterStack`, `tabbed`, `scrolling` (ruban Niri), `float` | Arbre i3 (`tiles`, `accordion`), `float` | `bsp`, `stack`, `float` | `scrolling` (Niri), `dwindle` BSP, `float` | i3, `bsp`, `scrolling` (Niri), `masterStack`, `stack`, `float` | xmonad (`tall`, `wide`, `bsp`, plein écran, etc.) |
| **Onglets intégrés par tuile / colonne** | **Oui, dans tous les modes tuilés** (`spatialBsp`, `scrolling`, `masterStack`, `bsp`) : barre flottante, `⌥ Option` + glisser, glisser-sortir, CLI | Non *(mode `accordion` ; onglets visuels via outils tiers)* | Non *(mode `stack` sans barre d’onglets native)* | Non | Oui *(barres d’onglets sur piles)* | Non |
| **Ruban défilant (`scrolling`) + confinement multi-écrans** | Oui : 120 Hz ProMotion, balayage trackpad 3/4 doigts, `⌥ + molette`, bornage strict aux jointures inter-écrans | Non | Non | Oui : animations synchronisées écran + balayage trackpad | Oui : colonnes défilantes + animations fluides | Non |
| **Espaces virtuels / Stages** | Stages nommées + bureaux virtuels par écran (indépendants des Spaces macOS) + **NavRail 3D** | Workspaces virtuels émulés instantanés (par écran) | Spaces natifs macOS | Workspaces virtuels | Spaces par écran | Spaces natifs macOS |
| **Vue d’ensemble (Overview)** | Oui (miniatures live, geste 4 doigts haut/bas) | Non | Non *(Mission Control macOS)* | Oui (miniatures live) | Oui (style Niri, glisser-déposer) | Non |
| **Scratchpad flottant** | Oui (nommés, barre de titre, survie au reboot configurable) | Non natif *(scriptable via workspace dédié)* | Non natif *(scriptable)* | Oui (jusqu’à 10 emplacements + terminal Quake) | Non natif | Non |
| **Raccourcis & gestes intégrés** | Oui (préréglages AZERTY/QWERTY, trackpad natif ; BTT/Karabiner optionnels) | Oui (`aerospace.toml`) | Non *(nécessite `skhd` ou équivalent)* | Oui | Oui (TOML + gestes trackpad) | Oui |
| **Réglages & automatisation** | Fenêtre de réglages temps réel + TOML + CLI + API JSON + règles | TOML + CLI | Script shell + CLI + signaux | Interface + CLI `omniwmctl` | GUI + menu bar + TOML + CLI/IPC | GUI simple + JSON |
| **Lanceur & sélecteur intégrés** | **Oui** *(lanceur complet + workflows Alfred + sélecteur `⌘ Tab` + sélecteur de zones)* | Non | Non | Palette de commandes (fenêtres/actions) | Non | Non |

---

## 2. Lanceurs, presse-papiers et sélecteurs de fenêtres

| Critère | **Roadie** | **Raycast** | **Alfred** | **AltTab** *(open source)* |
|---|---|---|---|---|
| **Modèle & prix** | **Gratuit, open source (Apache-2.0)** | Freemium *(Pro ~8–10 $/mois pour IA, Cloud Sync, historique > 3 mois, thèmes)* | Freemium *(Powerpack payant : 34 £ ou 59 £ à vie pour workflows, presse-papiers, snippets)* | Open source GPL-3.0 *(cœur gratuit)* |
| **100 % local, sans compte ni télémétrie** | Oui *(seul appel réseau optionnel : `roadie update check` manuel)* | Non *(compte/sync cloud & services IA pour Pro)* | Oui (local) | Oui (local) |
| **Workflows / Extensions** | Lit les fichiers **`.alfredworkflow` gratuitement** *(92/102 complets sur corpus réel)* | **Milliers d’extensions React/JS** dans le Raycast Store (gratuit) | Référence native `.alfredworkflow` *(Powerpack requis)* | Non |
| **Historique presse-papiers sécurisé** | Inclus, local `0o600`, exclut mots de passe (`Concealed`/`Transient`/gestionnaires) | Inclus *(limité à 3 mois en gratuit ; illimité en Pro)* | Inclus *(Powerpack requis)* | Non |
| **Snippets / expandeur de texte** | Inclus *(variables `{date}`, `{clipboard}`, `{cursor}`, auto-expansion optionnelle)* | Inclus *(local gratuit ; sync en Pro)* | Inclus *(Powerpack requis)* | Non |
| **Outils cœur hors ligne** | Calculatrice, convertisseur (unités/bases/fuseaux), pipette couleur, émojis FR/EN, minuteur/Pomodoro | Calculatrice riche, convertisseur, émojis, notes, quicklinks, IA (Pro) | Calculatrice ; reste via workflows | Non |
| **Sélecteur de fenêtres (`⌘ Tab`)** | Inclus (`CGEventTap` natif, miniatures, recherche, actions `W/Q/M/H/S/A/D`) | Sélecteur basique dans le lanceur | Non | **Spécialiste dédié** *(très léger, très configurable)* |
| **Sélecteur de zones cliquées (`Option+Tab`)** | **Oui** *(revient à un onglet/bouton/panneau précis, même sur une autre stage)* | Non | Non | Non |
| **Recherche à l’écran par étiquettes** | **Oui** *(Accessibilité + tolérance aux fautes + grilles écran/fenêtre)* | Non | Non | Non |
| **Gestionnaire de fenêtres (tiling)** | **Complet** *(6 modes, onglets par tuile, stages, bureaux virtuels)* | Snapping basique par raccourcis | Non | Non |

---

## 3. Ce que Roadie apporte de singulier

- **Un seul outil cohérent** : le lanceur connaît tes stages, tes bureaux virtuels et tes écrans (`safari perso gauche` ouvre Safari dans la stage *Perso* à gauche avec aperçu en direct).
- **Onglets universels par tuile ou colonne** : tu n’as pas à choisir entre BSP, ruban défilant (`scrolling`) ou onglets — maintiens `⌥ Option` n’importe où sur une tuile ou colonne cible pour empiler des fenêtres en onglets dans `spatialBsp`, `scrolling`, `masterStack` ou `bsp`.
- **Sélecteur de zones (`Option+Tab`) et recherche à l’écran** : revenir directement sur un sous-onglet, un champ ou un bouton précis dans une fenêtre, même cachée sur une autre stage, avec capture locale de la zone.
- **Compatibilité `.alfredworkflow` gratuite** : réutilise tes workflows Alfred existants (et même les thèmes Alfred) sans licence Powerpack.

---

## 4. Quand choisir plutôt un autre outil (limites assumées de Roadie)

Chaque outil répond à une philosophie différente. Un autre choix sera souvent meilleur dans les cas suivants :

- **Choisis yabai** si tu veux piloter directement les **Spaces natifs macOS**, retirer les ombres des fenêtres ou gérer l’opacité système, et que désactiver partiellement SIP ne te dérange pas.
- **Choisis AeroSpace** si tu cherches un gestionnaire **strictement minimaliste, 100 % clavier, inspiré d’i3**, sans rail visuel, sans lanceur ni interface graphique.
- **Choisis OmniWM** si tu es sur **Apple Silicon récent (macOS 26+)** et que tu veux un WM centré sur le scrolling Niri avec un terminal Quake intégré (`libghostty`).
- **Choisis Rift** si tu privilégies un moteur **Rust pur** branché sur les Spaces natifs macOS et une intégration directe à des barres externes comme SketchyBar.
- **Choisis Raycast** si ta priorité est un **écosystème massif d’extensions React/JS** (Linear, Notion, GitHub, Jira…), la synchronisation cloud ou l’IA intégrée au lanceur.
- **Choisis Alfred** si tu utilises intensivement les **Contacts**, l’écosystème Powerpack natif depuis des années ou des workflows AppleScript compilés.
- **Choisis AltTab** si tu ne veux ni tiling ni lanceur, uniquement un **`⌘ Tab` léger et dédié**.

### Limites actuelles assumées de Roadie

- **Pas de contrôle des Spaces natifs macOS** : Roadie garde SIP intact et gère ses propres stages et bureaux virtuels à la place.
- **Distribution non notarisée Apple pour l’instant** : l’installation 1-clic (`scripts/install-release.sh` ou Cask Homebrew) lève localement la quarantaine après vérification SHA-256 ; la compilation locale avec certificat auto-signé `roadied-cert` préserve la permission Accessibilité.
- **Pas de boutique d’extensions JS/React** : Roadie exécute les workflows `.alfredworkflow` existants, les commandes CLI et les règles TOML.
- **Périmètre tout-en-un assumé** : plus riche qu’un utilitaire mono-fonction (même si les modules non utilisés restent inactifs).
