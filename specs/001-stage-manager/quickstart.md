# Quickstart — Stage Manager Suckless

**Feature** : 001-stage-manager | **Phase** : 1 | **Date** : 2026-05-01

Guide minimal d'installation et de premier usage. Cible : utilisateur déjà à l'aise en terminal. Lecture intégrale : 5 minutes.

---

## Prérequis

- macOS 11 Big Sur ou ultérieur (testé sur 14+)
- Toolchain Xcode (`swiftc` disponible) : `xcode-select --install` si pas déjà fait
- Permission Accessibility (à accorder une fois après build)

---

## Build

```bash
cd <path-to-roadie>   # racine du repo cloné
make
```

Produit le binaire `./stage` (binaire universel x86_64 + arm64, ~200 KB attendu).

---

## Installation

```bash
make install        # installe dans ~/.local/bin/stage
```

Assurez-vous que `~/.local/bin` est dans votre `PATH` :

```bash
echo $PATH | grep -q ".local/bin" || echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc
```

---

## Permission Accessibility

Au premier lancement, le binaire vous dira sur stderr exactement quoi faire :

```bash
stage 1
# stage : permission Accessibility manquante.
# Ouvre Réglages Système → Confidentialité et sécurité → Accessibilité,
# ajoute le binaire (chemin : ~/.local/bin/stage) et coche-le.
```

Faites-le, puis relancez. La permission est mémorisée — à faire une seule fois.

---

## Usage de base

### Configurer ses 2 stages

1. Ouvrez votre **stage 1** (par exemple : un terminal pour coder).
2. Cliquez sur la fenêtre pour qu'elle devienne frontmost.
3. Tapez :
   ```bash
   stage assign 1
   ```
4. Répétez pour chaque fenêtre du stage 1 (éditeur, navigateur de doc, etc.).

5. Maintenant **stage 2** (par exemple : email + chat) :
   ```bash
   # mettre Mail au premier plan, puis :
   stage assign 2
   # mettre Slack au premier plan, puis :
   stage assign 2
   ```

### Basculer

```bash
stage 1   # affiche stage 1, masque stage 2
stage 2   # inverse
```

### Vérifier l'état

```bash
cat ~/.stage/1            # liste des fenêtres assignées au stage 1
cat ~/.stage/2            # idem stage 2
cat ~/.stage/current      # stage actuellement actif
```

---

## Câbler une hotkey (optionnel)

Hors scope de cet outil mais voici 3 chemins courants :

### skhd

```skhd
# ~/.config/skhd/skhdrc
alt - 1 : stage 1
alt - 2 : stage 2
```

### BetterTouchTool

Créer 2 raccourcis clavier exécutant la commande shell `stage 1` et `stage 2`.

### Karabiner-Elements

Mapper deux key codes vers `shell_command : stage 1` et `stage 2`.

---

## Désinstallation

```bash
rm ~/.local/bin/stage
rm -rf ~/.stage
```

Et retirer le binaire des autorisations Accessibility dans les Réglages Système.

---

## Dépannage

### Une fenêtre que je viens de fermer apparaît encore dans `cat ~/.stage/1`

Normal. L'auto-GC se déclenche au prochain `stage 1` ou `stage 2`. Vous pouvez aussi éditer le fichier à la main.

### Une fenêtre ne se minimise pas

Vérifier que la permission Accessibility est bien accordée pour `stage` (pas pour Terminal). Si oui, essayer :
```bash
stage 1 2>&1   # voir les erreurs sur stderr
```

### Les fichiers `~/.stage/*` ont disparu

Ils sont recréés au prochain `assign`. Pas de panique. Si vous les vouliez, désolé, c'est sur disque local non synchronisé.

### Je veux 3 stages

Hors scope V1. Rouvrez une nouvelle spec SpecKit.

---

## Validation rapide

Pour vérifier que l'installation fonctionne :

```bash
# 1. Ouvrir 2 fenêtres Terminal (cmd+N)
# 2. Dans la première (T1) :
stage assign 1
# 3. Dans la deuxième (T2) :
stage assign 2
# 4. Vérifier les fichiers :
cat ~/.stage/1   # doit contenir 1 ligne avec pid de T1
cat ~/.stage/2   # doit contenir 1 ligne avec pid de T2
# 5. Bascule :
stage 1          # T2 disparaît (minimisée)
stage 2          # T1 disparaît, T2 réapparaît
```

Si tout est OK : c'est gagné. Sinon, voir Dépannage.
