# ADR-011 : Mode commande dans la boîte de recherche et fenêtre de réglages

## Statut

Accepté. Mis en oeuvre par la SPEC-023 (`specs/023-command-box-settings/research.md`, décisions R1, R2, R5, R6, R7 et R8).

## Contexte

La boîte de Caps Lock + F (SPEC-021) cherche seulement du texte parmi les cibles à l'écran. Elle ne lance aucune action. Roadie sait déjà faire ce que la ligne de commande `roadie` fait, mais l'utilisateur doit se souvenir de raccourcis ou ouvrir un terminal.

Les réglages vivent dans un seul fichier, `roadies.toml` (774 lignes, environ 50 tables). Rien ne les montre à l'écran. Aucun code n'écrit ce fichier : TOMLKit sert uniquement à le lire. La taille des étiquettes (13 pt) est fixée dans le code.

Le daemon `roadied` est un processus `accessory` sans menu. Tous ses panneaux sont des `NSPanel` non activants dessinés à la main. Il n'a ni vraie fenêtre avec contrôles, ni SwiftUI.

## Décision

1. **Mode commande dans la boîte existante.** Un `/` en premier caractère fait passer la boîte de la SPEC-021 en mode commande. Sans `/`, le mode recherche reste inchangé. L'aiguillage se fait avant le modèle de recherche : une seule session de saisie, un seul tap clavier. Les commandes s'exécutent **en process** par `CLICommandRouter().run(argv)`, le routeur que le serveur de socket appelle déjà (R1). Aucune action nouvelle n'est créée. Une action qui ouvre une autre session (`/grid`, `/letters`) ou qui tue le daemon (`/restart`) est différée : la session se termine, le contrôleur remet son état à zéro, puis le lanceur exécute l'action au tour suivant de la boucle principale (R2).

2. **Première fenêtre SwiftUI du daemon.** La fenêtre de réglages est un `NSPanel` non activant et flottant qui héberge une vue SwiftUI par `NSHostingController` (R7). Elle est unique et conservée par un contrôleur statique. La politique `accessory` est conservée et le daemon ne s'active jamais : depuis macOS 14, un processus d'arrière-plan ne peut pas prendre le premier plan, et une `NSWindow` ordinaire restait invisible derrière les fenêtres de l'application active (constaté, correctif T041). Le panneau se place devant les autres fenêtres (`orderFrontRegardless`), reçoit le clavier (`makeKey`) et s'ouvre sur l'écran du pointeur. La fenêtre utilise `.moveToActiveSpace` et `.fullScreenAuxiliary`. Elle suit le fichier avec `RailFileWatcher`. Justification : 167 réglages typés demandent des contrôles standard ; une fenêtre AppKit pure coûterait environ trois fois plus de code.

3. **Éditeur de texte à automate pour `roadies.toml`.** Un petit automate lit le fichier ligne à ligne et ne remplace que la ligne de la clé, avec son indentation et son commentaire de fin de ligne (R5). Il ne ré-encode pas le fichier. Il ne touche que les couples (table, clé) du catalogue. Il refuse les cas ambigus (valeur multi-lignes, clé en double, table en ligne) et laisse alors le fichier intact. Le texte candidat est validé par `RoadieConfigLoader.validate(path:)` avant l'écriture. Juste avant le remplacement atomique, Roadie relit le fichier et compare son contenu : une reprise au plus en cas de changement concurrent, puis refus. Une copie `roadies.toml.bak-<horodatage>` est faite à la première écriture de la session.

4. **Identifiant de réglage `table.clé`.** Le nom est le chemin de la table sans le préfixe `experimental.` ni `fx.`, puis la clé (`target_grid.rows`, `rail.header.display.font_size`). La catégorie de la fenêtre est une donnée séparée du descripteur (R6). Un test de dérive compare le catalogue aux clés connues du validateur.

5. **Taille d'étiquette par facteur d'échelle.** `TargetOverlayStyle` gagne `labelFontSize` (défaut 13). Un facteur `scale = labelFontSize / 13` s'applique à la police, au badge, aux marges et aux pas de placement. Les épaisseurs de trait ne changent pas. Deux clés : `experimental.target_mode.label_font_size` et `experimental.target_grid.label_font_size`, plage 8 à 48 (R8).

## Conséquences positives

- L'utilisateur lance les actions et règle Roadie au clavier, sans terminal ni édition manuelle du fichier.
- Les commandes ont exactement l'effet de la ligne de commande : une seule implémentation à maintenir.
- Le fichier de configuration garde ses commentaires, son ordre et ses clés inconnues. Une écriture refusée ne change rien.
- Avec le facteur 13 pt, l'aspect sans réglage reste identique à l'actuel.
- Des noms uniques (`table.clé`) servent à la fenêtre, à `/set` et à la complétion.

## Conséquences négatives

- Première fenêtre à contrôles dans un daemon `accessory` : risques d'activation, de focus clavier, de Spaces plein écran et de tuilage de la fenêtre de Roadie elle-même. Le filtre de pid protège du tuilage, mais l'ensemble ne se vérifie qu'à l'écran (quickstart §3).
- L'éditeur de texte est une pièce de code à maintenir, avec ses refus explicites. Les constructions TOML qu'il ne reconnaît pas ne se modifient pas par la fenêtre ni par `/set`.
- Le catalogue de 167 réglages (libellés français, plages, défauts) est écrit à la main. Il peut dériver du code ; un test de dérive le détecte, mais ne remplace pas la relecture.
- Les listes et les tableaux de tables (règles, stages nommés, hooks) restent en lecture seule : leur édition reste manuelle.
- Le mode commande exige que le daemon tourne, et les actions différées (`/grid`, `/letters`, `/restart`) ne rendent pas de résultat dans la boîte.
- Un nom `table.clé` est moins court qu'un nom par catégorie ; c'est le prix d'un nom sans collision.

## Alternatives rejetées

- Appeler chaque service à la main ou passer par le socket (R1) : duplication du routeur, ou délai inutile dans le même processus.
- Une seconde session de saisie pour les commandes (R3) : duplique la barre et le tap clavier.
- Ré-encoder le fichier avec TOMLKit, ou ajouter une bibliothèque d'édition TOML (R5) : risque de perdre commentaires, ordre et tables inconnues, ou dépendance non justifiée.
- Une fenêtre AppKit pure, ou une fenêtre HTML (R7) : trop de code pour 167 contrôles, ou nouvelle dépendance web.
- Des noms `catégorie.clé` (R6) : collisions entre tables (`enabled`, `font_size`).
- Une taille de police seule, sans facteur (R8) : le badge et les marges ne suivraient pas le texte.
