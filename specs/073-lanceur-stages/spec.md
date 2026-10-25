# Spécification 073 - Lanceur intégré aux stages

Demande du 25 octobre 2026 : faire le tour des lanceurs (Alfred, Raycast, LaunchBar,
Spotlight de macOS 26, Quicksilver, Tuna, Leader Key, Tinycast, Sol, Vicinae, PowerToys
Command Palette, intégrations AeroSpace) et mettre en place dans Roadie les fonctions à
retenir, en réutilisant la barre du mode recherche (`targets search`).

## Objectif
Un lanceur qui sait **où** ranger ce qu'il ouvre. Grammaire de Quicksilver :
**objet → verbe → destination**. Objet : application, fenêtre, stage, bureau, écran.
Destination : stage, bureau ou écran, existant ou à créer.

## Critères de réussite
- Ouvrir Firefox dans la stage Perso : objet, destination, Retour (trois gestes) après le
  raccourci. Sans destination, Retour fait l'action par défaut.
- Liste affichée en moins de 100 ms après chaque touche ; index des applications construit
  hors du fil principal.
- Aucune fenêtre ne se perd : une ouverture dont la fenêtre n'apparaît pas dans le délai
  abandonne l'intention sans effet.
- Le classement appris reste sur la machine et se remet à zéro.

## Fonctions retenues

### Lot 1 - Lanceur de base
- **F1 Catalogue** : applications installées (dossiers d'applications, un niveau de
  sous-dossier, Finder), avec nom affiché localisé, nom anglais et nom de fichier ;
  fenêtres ouvertes, stages, bureaux, écrans (déjà connus de Roadie). Source : catalogue
  Quicksilver, index Tinycast.
- **F2 Correspondance** : approximative, sans casse ni accents, points pour la première
  lettre, les débuts de mots et les majuscules internes (`ps` trouve Photoshop), pénalité
  pour les trous. Idée du scoreur Tinycast et des abréviations LaunchBar, réécrite.
- **F3 Classement appris** : abréviation tapée → objet choisi (mnémoniques Quicksilver),
  fréquence-récence à demi-vie de 10 jours. Stocké dans `~/.roadies/launcher-ranking.json`.
- **F4 Verbe par défaut selon l'objet** : application fermée → l'ouvrir dans la stage
  active, ou là où une règle `assign_stage` l'envoie ; application ouverte → aller à sa
  fenêtre la plus récente, dans sa stage et son bureau ; fenêtre → y aller ; stage →
  basculer ; bureau → l'afficher.
- **F5 Intention de placement** : nouveau mécanisme Roadie. La prochaine fenêtre de
  l'application lancée (même bundle, 10 s au plus) rejoint la stage visée, une seule fois.

### Lot 2 - Verbes et destinations
- **F6 Panneau des verbes** (Tab) filtré selon l'objet : ouvrir ici, ouvrir dans…, nouvelle
  fenêtre, aller à, envoyer vers une stage, un bureau ou un écran, faire flotter, plein écran,
  masquer, fermer, quitter, réunir toutes les fenêtres de l'application dans une stage.
  Sources : panneau d'actions Raycast, Universal Actions Alfred, second panneau Quicksilver.
- **F7 Destination** : stages, bureaux et écrans ; un nom inconnu propose « Nouvelle stage
  “…” » (idée Aerospace.spoon), en respectant l'unicité des noms (SPEC-067).
- **F8 Variantes** : ⌘ Retour ouvre dans une nouvelle stage ; ⌥ Retour agit sans changer
  de stage affichée (actions alternatives Quicksilver).
- **F9 Sélection multiple** : virgule pour ajouter un objet ; plusieurs applications vers
  une même stage (virgule Quicksilver, Staging LaunchBar, File Buffer Alfred).

### Lot 3 - Raccourcis personnels
- **F10 Alias** de 12 caractères au plus vers un objet ou une commande (Quick Keys Spotlight,
  alias Raycast), prioritaires sur la correspondance.
- **F11 Liste vide utile** : favoris épinglés avec ⌘1 à ⌘9, puis récents (Tinycast, Raycast).
- **F12 Mode séquence** : séquences de touches fixes vers des commandes Roadie (Leader Key,
  mode Leader de Tuna), configurées dans le TOML ; import du `config.json` de Leader Key.

### Lot 4 - Espaces prêts et menus
- **F13 Recettes** : un nom ouvre plusieurs applications, chacune dans sa stage et son
  bureau, en créant les stages manquantes (Rooms Tinycast, dispositions Raycast).
- **F14 Recherche dans les menus** de l'application active : lecture AX des menus sans les
  ouvrir, bornée en profondeur, en nombre et en temps ; activation qui revalide l'élément
  (Search Menu Items Raycast, Menu Search Tinycast).

### Lot 5 - Vers l'extérieur
- **F15 Liens rapides** avec `{argument}` et ligne « Utiliser “…” avec… » en bas de liste ;
  une adresse web tapée s'ouvre dans le navigateur, dans la stage choisie (Quicklinks et
  fallbacks Raycast, Tinycast).
- **F16 Scripts et raccourcis Apple** comme objets (Script Commands Raycast, Shortcuts).
- **F17 Fichiers** : recherche Spotlight à partir de trois caractères, ouverture avec
  l'application voulue dans la stage voulue.
- **F18 Pilotage externe** : `roadie launch OBJET [--stage NOM|--new-stage] [--desktop N]`,
  utilisable depuis BetterTouchTool (schéma d'URL Leader Key, `x-launchbar:`).

## Écartées, et pourquoi
Calculatrice, emojis, presse-papiers, snippets, agenda et réunions, notes, traduction,
dictée, IA, désinstallation, réglages système : hors du rôle d'un gestionnaire de fenêtres,
déjà couverts par Spotlight de macOS 26 ou par Alfred et Raycast, que l'utilisateur peut
garder à côté. Exécution des extensions Raycast : nécessite un moteur JavaScript et une API
de rendu complète, coût sans rapport avec le gain.

## Licences
Tinycast est sous AGPL-3.0 : idées reprises, aucun code copié (Roadie n'a pas de licence
déclarée). Quicksilver (Apache-2.0), Leader Key et Sol (MIT) : idées reprises ; tout code
repris citerait sa source et sa licence.

## Estimation
Lot 1 : 6 à 8 h. Lot 2 : 6 à 8 h. Lot 3 : 4 à 6 h. Lot 4 : 5 à 7 h. Lot 5 : 6 à 8 h.
Total : 27 à 37 h, une session par lot (073 à 077), chacune testée, installée et essayée.

## Décisions de l'utilisateur (25 octobre 2026)
- Même barre que `targets search` (Capslock + F), résultats groupés par sections :
  Applications, Fenêtres, Stages et bureaux, puis À l'écran (cibles actuelles).
- Application déjà ouverte : Retour va à sa fenêtre la plus récente ; « Nouvelle fenêtre
  ici » passe par Tab ou ⌘ Retour.
- Les cinq lots, un par session (073 à 077), chacun testé, installé et montré.
