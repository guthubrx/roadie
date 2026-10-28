# Session 115 : réglages trouvables dans la barre

## Besoin

Reprise d'Alfred (« Essentiels : Réglages Système », ⌘, pour les préférences) : taper « rail » ouvre
Paramètres > Rail, « clavier » le panneau Clavier des Réglages Système.

## Règle

- Section « Réglages » après les sections principales, 4 lignes au plus, dès deux lettres. À score égal,
  le titre le plus court.
- Paramètres de Roadie : les 14 catégories (détail « Paramètres de Roadie ») et chaque réglage du catalogue
  (détail « Paramètres de Roadie › catégorie »), trouvé par son libellé ou sa clé TOML. Retour sur un
  réglage ouvre sa catégorie avec la recherche des Paramètres remplie de son libellé (session 107).
- Réglages Système : extensions `com.apple.Settings.extension.ui` de `/System/Library/ExtensionKit/Extensions`,
  nommées par `InfoPlist.loctable` dans la langue de l'utilisateur ; le nom anglais sert aussi de mot-clé.
  Retour ouvre `x-apple.systempreferences:<identifiant>`. Batterie n'a pas de nom traduit : nom fixe.
- Réglage `settings_in_search` (actif par défaut). Touche `settings_key` (⌘,) : ferme la barre et ouvre
  les Paramètres de Roadie.

## Mesures (ce poste, macOS 26)

- 51 panneaux parmi 228 extensions ; 50 noms français dans leur table, Batterie sans nom.
- Lecture : 20 ms, une fois par lancement de Roadie.
