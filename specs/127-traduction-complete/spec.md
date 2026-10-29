# Spécification 127 - Interface entièrement traduite, langue réglable

Demande du 29 octobre 2026 : « il faut tout traduire, il faut que ça soit anglais ou français, mais complètement
traduit ». Puis : « je veux que ça soit paramétrable au travers des paramètres de l'application avec un défaut vers
la langue de l'OS, et moi je reste par défaut ».

## Constat
- Après la session 126, la fenêtre des paramètres, le rail, les menus de la barre de titre, les messages de
  validation et de santé restaient en français.
- La première langue de macOS de ce poste est `en-US` (région France) : depuis la session 126, Roadie s'y affiche
  en anglais. Le bilan 126 affirmait à tort l'inverse.

## Exigences
- **FR-001 Traduction.** Tout texte lu par un humain passe par `tr(fr, en)` : paramètres (libellés, aides, groupes,
  choix, listes, messages), rail, menus de la barre de titre et du rail, sélecteur, vue d'ensemble, messages de
  validation de la configuration, santé `macos-window-settings`, raisons de `roadie window explain`, sorties
  humaines de `roadie workflow`, `roadie project list`, `roadie launcher`.
- **FR-002 Réglage.** `[interface] language` : `auto` (défaut, première langue de macOS), `fr` ou `en`, dans
  Paramètres > Général. Ordre : `ROADIE_LANGUAGE`, puis le réglage, puis macOS. Un changement relance Roadie.
- **FR-003 Défauts traduits.** Modèle d'en-tête du rail par défaut `Bureau {desktop}` / `Desktop {desktop}`, noms de
  bureau des menus et des cibles de la barre.

## Hors périmètre
Sorties techniques de la ligne de commande déjà en anglais (`No displays found.`, `clé=valeur`), journaux et
identifiants. Valeurs déjà écrites par l'utilisateur dans `roadies.toml` (par exemple un modèle `Desktop {desktop}`).
