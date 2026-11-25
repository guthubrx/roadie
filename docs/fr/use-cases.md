# Cas d'usage

## 1. Poste de developpement quotidien

Objectif : garder le code, les terminaux et la documentation organises sans manipuler les fenetres a la souris.

Setup conseille :

- Desktop `1` : developpement.
- Stage `dev` : editeur + terminal principal.
- Stage `docs` : navigateur/documentation.
- Stage `comms` : messagerie.

Commandes :

```bash
roadie desktop label 1 Dev
roadie stage rename 1 Dev
roadie stage create docs
roadie stage create comms
roadie mode masterStack
```

Rule typique :

```toml
[[rules]]
id = "docs-browser"
priority = 10

[rules.match]
app_regex = "Safari|Firefox|Chrome"
title_regex = "Docs|Documentation|README"

[rules.action]
assign_stage = "docs"
scratchpad = "research"
emit_event = true
```

## 2. Operations multi-ecran

Objectif : garder un ecran principal pour le travail actif et deplacer une stage complete vers un ecran secondaire.

```bash
roadie display list
roadie stage move-to-display 2
roadie desktop summon 2
```

Cas concret :

- ecran 1 : incident actif;
- ecran 2 : logs, dashboards, documentation;
- `stage move-to-display` deplace le contexte sans recreer les fenetres.

## 3. Workflow recherche/documentation

Objectif : grouper plusieurs fenetres de documentation et les retrouver via queries.

```bash
roadie windows list
roadie group create research 12345 67890
roadie group focus research 67890
roadie query groups
```

Integration possible :

```bash
roadie query groups | jq '.data'
```

## 4. Barre de statut locale

Objectif : afficher la fenetre active, la stage et les evenements importants.

```bash
roadie events subscribe --from-now --initial-state --scope window --scope stage
```

Le consommateur doit :

- ignorer les champs inconnus;
- utiliser `type`, `scope`, `subject` et `payload`;
- tolerer les nouveaux evenements.

## 5. Validation avant changement de config

Objectif : eviter qu'une rule TOML cassee perturbe la session.

```bash
roadie rules validate --config ~/.config/roadies/roadies.toml
roadie rules explain --app Terminal --title roadie --role AXWindow --stage dev --json
```

Workflow recommande :

1. modifier `roadies.toml`;
2. lancer `rules validate`;
3. tester une fenetre representative avec `rules explain`;
4. redemarrer Roadie si necessaire.

## 6. Recuperation apres incoherence d'etat

Objectif : reparer l'etat local sans supprimer toute la configuration.

```bash
roadie state audit
roadie state heal
roadie daemon heal
roadie daemon health
```

Utiliser cette sequence apres :

- deconnexion/reconnexion d'ecran;
- fermeture brutale d'apps;
- changement de branche ou rebuild.

## 7. Avant une operation risquee

Objectif : garder une porte de retour explicite et verifier le snapshot utilise aussi par le watcher crash.

```bash
roadie config reload --json
roadie restore snapshot --json
roadie restore status
```

Si les frames doivent etre restaurees explicitement :

```bash
roadie restore apply --yes
```

Ce restore matche les fenetres par ID courant. Le watcher crash utilise le meme mecanisme seulement si le daemon disparait sans sortie propre; il ne tourne pas dans le chemin focus/bordure.

## 8. Administration locale raisonnable

Objectif : eviter l'accumulation de logs et backups.

```bash
roadie cleanup --dry-run
roadie cleanup --apply
```

Commencer par `--dry-run` permet de voir les fichiers candidats avant suppression ou rotation.

## 9. Navigation clavier avec labels

Objectif : sauter vers une fenetre, une stage, un ecran, un desktop ou un
bookmark sans memoriser les IDs internes.

```bash
roadie targets interactive --source all
roadie targets pick work --action switch
roadie targets inspect A --json
```

A utiliser quand :

- le navrail est visible mais la cible est plus simple a taper qu'a cliquer;
- un script ou un agent a besoin d'une liste structuree de destinations;
- une recherche ambigue doit echouer proprement au lieu de deplacer des fenetres.

## 10. Ciblage spatial quand Accessibility ne voit pas un controle

Objectif : cibler une zone visuelle meme quand l'application n'expose pas
d'element Accessibility utile.

```bash
roadie grid interactive --scope display --duration 10
roadie grid interactive --scope focused_window --duration 10
```

Utilise **Grille Ecran** pour cibler un ecran complet ou changer de zone entre
ecrans. Utilise **Grille Fenetre** quand l'interaction reste dans la fenetre
focussee : lecteur video, canvas, webview ou panneau applicatif dense.

## 11. Capture de macros courtes

Objectif : enregistrer une courte manipulation souris avec coordonnees et
contexte semantique de cible.

```bash
roadie record start demo --duration 10
roadie record inspect demo --json
roadie record replay demo
```

Les recordings gardent une meilleure cible Roadie ou Accessibility quand elle
existe, plus un fallback grille. Le replay peut donc preferer les cibles stables
et n'utiliser les coordonnees qu'en dernier recours.

## 12. Travailler en onglets ou en ruban défilant

Objectif : passer une stage de veille ou d'écriture en mode plein cadre avec barre d'onglets (`tabbed`) ou en ruban horizontal centré (`scrolling`), sans toucher aux autres stages en `spatialBsp`.

```bash
roadie mode tabbed       # barre d'onglets flottante cliquable (masquée si 1 seule fenêtre)
roadie focus right       # onglet suivant
roadie move left         # réordonner l'onglet vers la gauche

roadie mode scrolling    # colonnes horizontales centrées (largeur 65 % par défaut)
roadie focus right       # faire défiler vers la colonne suivante
roadie layout width next # ajuster la largeur de colonne

# Ou empiler des onglets dans n'importe quelle tuile sans quitter spatialBsp :
roadie tab stack right   # empiler la fenêtre active dans la tuile BSP de droite
roadie tab next          # passer à l'onglet suivant dans la tuile
roadie tab move left     # déplacer l'onglet actif vers la gauche
roadie tab unstack       # détacher l'onglet actif en tuile BSP indépendante
```

Le mode de disposition est aussi sélectionnable par clic droit sur une carte de stage dans le NavRail ou depuis la barre de recherche. Dans tous les modes tuilés à slots (`spatialBsp`, `scrolling`, `masterStack` et `bsp`), maintiens `⌥ Option` lors d'un dépôt au centre d'une tuile ou d'une colonne (ou dépose directement sur une barre d'onglets) pour empiler en onglets, et glisse un onglet hors de sa barre pour le détacher.

## 13. Scratchpad flottant, Dim Inactive et scènes de projet

Objectif : garder un bloc-notes ou un terminal accessible d'une touche au-dessus de n'importe quelle stage, atténuer les fenêtres inactives pour rester concentré, et sauvegarder une scène complète de projet.

```bash
roadie scratchpad assign notes
roadie scratchpad toggle notes

roadie project save Sprint --url https://example.org/board --app com.apple.Terminal --note "Revue hebdo"
roadie project info Sprint
roadie project open Sprint
```

Active `[fx.dim_inactive].enabled = true` dans **Paramètres > Effets** pour poser un voile doux traversant aux clics sur les fenêtres inactives de la stage active.

## 14. Presse-papiers sécurisé et snippets quotidiens

Objectif : retrouver un texte copié plus tôt sans exposer ses mots de passe et réutiliser des modèles dynamiques (`{date}`, `{clipboard}`, `{cursor}`).

- Dans le lanceur : tape `cb` (ou `clipboard`) pour filtrer et recopier une entrée, ou `snip` (ou `snippet`) pour développer un snippet.
- En CLI :

```bash
roadie clipboard list
roadie clipboard search "roadmap"
roadie clipboard pin ID
roadie snippet list
roadie snippet expand !sig --copy
```

Les entrées sensibles (`ConcealedType`, `TransientType`, `AutoGeneratedType`) et les gestionnaires de mots de passe sont automatiquement ignorés ; l'historique reste local dans `~/.roadies/clipboard.json` (`0o600`).

## 15. Outils instantanés du lanceur et triage rapide au sélecteur

Objectif : convertir une unité, lancer un Pomodoro, prélever une couleur ou faire le ménage dans ses fenêtres sans ouvrir d'application dédiée.

- Dans le lanceur : `100 km in mi`, `0xff in dec`, `14:00 NYC in Paris`, `timer 25m focus`, `pomodoro`, `pipette`, `:fusée`.
- Dans le sélecteur (`Cmd+Tab`, hors champ de recherche) : `W` ferme la fenêtre, `Q` quitte l'app, `M` réduit/restaure, `H` masque l'app, `S` rapatrie dans la stage active, `A` filtre sur l'application courante, `D` filtre sur l'écran courant.

## 16. Piloter Roadie en 100 % autonomie (sans BetterTouchTool ni Karabiner)

Objectif : installer Roadie sur un Mac neuf ou alléger une configuration existante en confiant à Roadie ses raccourcis clavier, le `⌘ Tab` natif, les gestes trackpad (ruban `scrolling` et Vue d'ensemble) et la persistance du scratchpad au redémarrage — tout en gardant la liberté d'utiliser BTT ou Karabiner à la carte.

```bash
# Initialiser une configuration complète avec un pack de raccourcis sans collision (compatible AZERTY/QWERTY)
roadie config init --preset standard    # ou : vim | minimal
roadie shortcuts list
roadie shortcuts check
```

- **Sélecteur `⌘ Tab` / `⌘ Maj Tab` natif** : dans **Paramètres > Sélecteur** (ou `[[switcher.shortcuts]]`), régler `hotkey = "command+tab"` et `trigger_source = "roadie"`. Roadie intercepte `⌘ Tab` et `⌘ Maj Tab` directement via `CGEventTap`.
- **Gestes trackpad natifs** : glisse à 3 doigts horizontalement (ou `⌥ Option + molette`) pour faire défiler le ruban `scrolling` à 120 Hz ProMotion ; glisse à 4 doigts vers le haut pour ouvrir la Vue d'ensemble et vers le bas pour la fermer (`overview.trackpad_gesture = true`).
- **Scratchpad en un clic droit** : clic droit sur la barre de titre d'une fenêtre → **Fenêtre → Transformer en scratchpad** (ou **Retirer du scratchpad**). Au redémarrage du Mac, `tiling.scratchpad_reboot_policy = "reattach_or_relaunch"` (défaut) réattache ou relance automatiquement l'application au prochain `toggle` (configurable en `reattach` ou `ephemeral`).
- **Migration depuis BetterTouchTool** : dans **Paramètres > Raccourcis**, clique sur **Importer depuis BetterTouchTool** pour rapatrier tes raccourcis Roadie existants sans modifier ton profil BTT.
