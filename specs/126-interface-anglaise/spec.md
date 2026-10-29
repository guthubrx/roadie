# Spécification 126 - Barre, sélecteur et vue d'ensemble en anglais ou en français

Demande du 29 octobre 2026 : « il faut que le par défaut, ça soit en anglais, donc le texte en anglais et aussi les
images en anglais, si c'est possible ; est-ce que les mots-clés y sont anglais et français ? J'espère que oui. »
Choix de l'utilisateur : traduire l'interface (et non maquiller les captures) ; rendre les verbes bilingues.

## Constat
- La documentation anglaise était déjà celle par défaut, mais ses captures montraient l'interface, écrite seulement
  en français.
- Mots-clés déjà bilingues : phrases, commandes système, noms d'applications, Réglages Système. Seuls les verbes de
  la liste ne trouvaient rien en anglais.

## Exigences
- **FR-001 Langue.** Les textes de la barre, du sélecteur de fenêtres et de la vue d'ensemble suivent la première
  langue de macOS : français si elle est française, anglais sinon. `ROADIE_LANGUAGE` (`fr`, `en`) l'emporte ;
  `scripts/test` fixe le français.
- **FR-002 Mots tapés.** Les deux langues restent acceptées, quelle que soit la langue affichée : verbes
  (`close`/`fermer`), commandes système (les deux noms en mots-clés), bureaux (`desktop 2`/`bureau 2`).
- **FR-003 Captures.** Chaque capture existe en anglais (`docs/assets/screenshots/`, documentation par défaut) et
  en français (`docs/assets/screenshots/fr/`), produites par le vrai rendu.

## Hors périmètre
Fenêtre des paramètres, rail, menus de la barre de titre et messages de la ligne de commande : en français
(paramètres, rail, menus) ou en anglais (ligne de commande), comme avant.
