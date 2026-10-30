# Spécification : reprise des fonctions d'Alfred restées « En partie » et des nouveautés d'Alfred 6

**Branche** : `131-actions-alfred`
**Créée** : 2026-10-29
**Statut** : Brouillon
**Demande initiale** : « implémenter toutes les choses qui sont en partie dans
docs/analyses/2026-10-25-reference-alfred.html, à part le truc avec l'intelligence artificielle et la
transformation ». Précisions de l'utilisateur le 29 octobre 2026 :
- Snippet (déclencheur par mot tapé partout) et Contacts (recherche et Contact Action) : écartés.
- Nouveautés annoncées d'Alfred 6 : reprises, sauf l'IA avec clé personnelle et la transformation de texte.
- Styles d'Alfred 6 : décrits d'après les images de la page officielle, regardées le 29 octobre 2026.

## Cadrage (Phase 0)

**Demande reformulée.** Faire passer à « Déjà dans Roadie » les lignes « En partie » de la référence Alfred,
sauf les deux morceaux écartés, et reprendre les nouveautés annoncées d'Alfred 6 hors IA et transformation de
texte. Chaque ajout marche depuis la barre, en français et en anglais, est testé, et la référence est mise à
jour honnêtement : une ligne garde « En partie » si un morceau est volontairement laissé de côté.

**Ce que cela apporte.** Une liste fermée de résultats vérifiables, ligne par ligne, au lieu d'un « tout »
sans fin ; les choix écartés restent visibles avec leur raison.

**Critères de réussite.** Chaque exigence ci-dessous a un test ; la page de référence montre au plus deux lignes
« En partie » (Snippet, Contact Action), avec la raison ; la suite complète réussit ; Roadie installé est sain.

## Scénarios utilisateur et tests

### Histoire 1 - Agir sur un fichier depuis la barre (P1)

L'utilisateur trouve un fichier, ouvre ses verbes (Tab ou →) et peut : le copier dans le presse-papiers (collable
dans le Finder), le copier ou le déplacer vers un dossier choisi à l'étape suivante (en remplaçant si un fichier
du même nom existe, après confirmation), l'ouvrir avec une application choisie, l'envoyer par e-mail en pièce
jointe, le mettre à la corbeille, créer un alias à côté, ouvrir sa fenêtre « Lire les informations » du Finder (⌘I ;
décision du 30 octobre 2026, une fiche Roadie faisait moins bien), ajouter ou retirer une étiquette du Finder, parcourir un dossier dans la barre, ouvrir un
terminal dans son dossier, montrer le contenu d'un paquet. Les verbes s'appliquent aussi à une sélection
multiple de fichiers.

**Test indépendant** : sur des fichiers temporaires, chaque verbe produit l'effet attendu sur le disque, dans le
presse-papiers ou dans l'application choisie.

**Scénarios** :
1. **Étant donné** un fichier trouvé, **quand** l'utilisateur choisit « Déplacer vers… » puis un dossier, **alors**
   le fichier est dans ce dossier et n'est plus à l'ancien emplacement.
2. **Étant donné** un fichier du même nom dans le dossier choisi, **quand** l'utilisateur copie, **alors** rien
   n'est écrasé sans le choix explicite « en remplaçant ».
3. **Étant donné** trois fichiers sélectionnés, **quand** l'utilisateur choisit « Mettre à la corbeille »,
   **alors** les trois sont dans la corbeille, récupérables.

### Histoire 2 - Agir sur un texte ou une adresse (P1)

Un texte tapé, ou le texte sélectionné dans l'application active (ouverture des verbes par Capslock + Maj + F
quand une sélection existe), devient un objet de la barre avec ses verbes : copier, chercher sur le web, ouvrir
l'adresse (si c'en est une), extraire les adresses web et e-mail qu'il contient, l'envoyer par e-mail, l'afficher
en grand. Les actions universelles des workflows qui acceptent du texte ou des adresses y figurent comme verbes.

**Scénarios** :
1. **Étant donné** un texte contenant deux adresses web et un e-mail, **quand** l'utilisateur choisit « Extraire
   les adresses », **alors** la barre liste les trois, chacune avec ses propres verbes.
2. **Étant donné** un workflow avec une action universelle sur texte, **quand** l'utilisateur ouvre les verbes
   d'un texte, **alors** « Workflow : <nom> » est proposé et lance le workflow avec ce texte.

### Histoire 3 - Agir sur un onglet de navigateur (P2)

Un onglet ouvert trouvé dans la barre propose : y aller (existant), fermer l'onglet, copier son adresse, l'ouvrir
dans une nouvelle fenêtre. Safari, Chrome, Brave, Edge et Firefox.

### Histoire 4 - Choisir ce que font ⌘, ⌥ et ⌃ + Retour (P2)

Paramètres > Recherche propose une liste pour chaque touche, comme les listes d'Alfred : ouvrir dans une nouvelle
stage, amener ici, envoyer sans suivre, chercher sur le web, copier, montrer dans le Finder, aperçu, verbes.
Les valeurs par défaut gardent le comportement actuel. La ligne choisie annonce l'effet réglé.

### Histoire 5 - Briques de workflow manquantes (P2)

Les workflows qui utilisent Commande système, Commande Musique, Recherche dans le dictionnaire ou Filtre des
applications ouvertes tournent en entier : commandes système d'Alfred (dont masquer, quitter, forcer à quitter
l'application active, tout quitter, éjecter), commandes de Musique (lecture/pause, suivant, précédent, etc.),
définitions du dictionnaire de macOS dans la barre, applications ouvertes filtrées par la saisie.

### Histoire 6 - Commandes de la barre sans workflow (P2)

Depuis la barre seule : chercher un élément des menus de l'application active et le choisir ; basculer le mode
sombre ; prendre une capture d'écran (écran, zone, fenêtre) ; lancer un raccourci de l'app Raccourcis ;
relancer une application ; quitter toutes les autres applications. Une tâche d'automatisation officielle absente
est téléchargée à sa première utilisation, comme le fait Alfred qui les embarque.

### Histoire 7 - Nouveautés annoncées d'Alfred 6 (P3)

- **Apps** (« Launchpad ») : toutes les applications en grille, rangées par catégorie de macOS, filtrées par la
  saisie, lancées par Retour ; l'utilisateur peut en épingler en tête.
- **Navigateur SF Symbols** : recherche par nom et mots-clés, grille de 6 colonnes, nom et catégories sous la
  sélection, aperçu en plusieurs tailles et version minimale par système, copie du nom par Retour.
- **Styles des vues de workflow** : Glassy Dark (verre sombre, boutons en verre), Flat Dark (même fond, boutons
  pleins sans verre), Glassy Light (verre clair, accent de macOS), plus « votre thème ».
- **Thème de barre en verre** : verre sombre laissant voir le fond d'écran, champ de recherche plus foncé et
  arrondi, sélection turquoise ; variante claire.
- **Tableaux Markdown** dans la vue Texte : colonnes alignées, en-tête distinct, alignement `:---:` respecté.

### Cas limites

- Fichier déplacé ou supprimé entre la recherche et le verbe : message d'échec, aucune autre action.
- Dossier de destination en lecture seule : refus explicite, fichier source intact.
- Sélection vide (Capslock + Maj + F sans texte sélectionné) : comportement actuel (verbes de la fenêtre).
- Menus d'une application qui ne répond pas à l'accessibilité : liste vide après un délai borné, sans blocage.
- Pas de réseau pour une tâche absente : message clair, le workflow s'arrête comme aujourd'hui.
- macOS sans matériau de verre récent : les styles « Glassy » retombent sur le flou standard de macOS.

## Exigences

### Fonctionnelles

- **FR-001** Verbes de fichier : copier, copier vers, déplacer vers, copier en remplaçant, déplacer en remplaçant,
  ouvrir avec, envoyer par e-mail, mettre à la corbeille, créer un alias, informations, étiquettes, parcourir dans
  la barre, ouvrir un terminal ici, montrer le contenu du paquet ; sur un ou plusieurs fichiers.
- **FR-002** Aucun verbe n'écrase un fichier sans le choix « en remplaçant » ; la corbeille est la seule
  suppression proposée.
- **FR-003** Sujet « texte » : texte tapé ou sélection de l'application active, avec copier, chercher sur le web,
  ouvrir l'adresse, extraire les adresses, envoyer par e-mail, afficher en grand.
- **FR-004** Actions universelles des workflows proposées sur les textes (acceptstext), adresses (acceptsurls) et
  fichiers (acceptsfiles), avec un ou plusieurs éléments.
- **FR-005** Verbes d'onglet : fermer, copier l'adresse, ouvrir dans une nouvelle fenêtre, pour les cinq navigateurs.
- **FR-006** Effet de ⌘, ⌥ et ⌃ + Retour réglable dans les Paramètres ; défauts identiques à aujourd'hui.
- **FR-007** Briques `action.systemcommand`, `action.itunescommand`, `input.dictionaryfilter`,
  `input.runningappsfilter` exécutées, avec leurs réglages d'Alfred.
- **FR-008** Recherche dans les menus de l'application active et choix d'un élément, depuis la barre.
- **FR-009** Commandes de barre : mode sombre, captures d'écran (écran, zone, fenêtre), raccourcis Apple, relancer
  une application, quitter les autres.
- **FR-010** Tâche d'automatisation officielle absente téléchargée à la première utilisation.
- **FR-011** Grille Apps par catégorie, filtrée, avec épinglage.
- **FR-012** Navigateur SF Symbols conforme au modèle d'Alfred 6.
- **FR-013** Trois styles des vues de workflow et thème de barre en verre (sombre et clair).
- **FR-014** Tableaux Markdown rendus dans la vue Texte.
- **FR-015** Tous les textes ajoutés existent en français et en anglais ; les mots tapés sont compris dans les deux.
- **FR-016** Référence Alfred mise à jour : lignes passées à « Déjà dans Roadie », ou gardées « En partie » avec la
  raison (Snippet, Contact Action), ligne Alfred 6 sans IA ni transformation de texte.

### Entités

- **Sujet texte** : texte d'origine, adresses détectées.
- **Réglage des modificateurs** : touche, effet choisi.
- **Symbole** : nom, catégories, mots-clés, année d'apparition et versions minimales par système.
- **Application épinglée** : identifiant, rang.

## Critères de succès

- **SC-001** Chaque verbe de fichier est vérifié sur des fichiers temporaires par un test automatique.
- **SC-002** Une sélection de 3 fichiers est traitée en une seule action pour copier, déplacer et corbeille.
- **SC-003** La liste des menus de l'application active apparaît en moins de 1 s pour une application ordinaire.
- **SC-004** Le navigateur SF Symbols trouve un symbole par son nom ou un mot-clé parmi plus de 9 000.
- **SC-005** Les quatre briques de workflow ajoutées ont chacune un test d'exécution.
- **SC-006** La suite complète réussit ; Roadie installé est sain (5/5).
- **SC-007** La référence Alfred n'a plus que deux lignes « En partie », avec leur raison.

## Hors périmètre

Snippet, Contacts et Contact Action ; IA avec clé personnelle ; transformation de texte ; presse-papiers et
snippets (choix antérieur maintenu) ; éditeur visuel de workflows.
Boîte à outils Alfred UI elle-même (fenêtres décrites en JSON par les workflows d'Alfred 6) : Alfred 6 n'est pas
sorti et son format n'est pas publié ; seuls ses exemples (Launchpad, SF Symbols) et ses trois styles sont repris,
les styles s'appliquant aux fenêtres de workflow (Texte, Image, PDF) et au panneau SF Symbols ; la Grille
s'affiche dans la barre et suit le thème de la barre.

## Hypothèses

- Les données SF Symbols lues sont celles de macOS (CoreGlyphs), vérifiées présentes sur ce Mac.
- Les commandes Musique visent l'application Musique d'Apple.
- Les styles d'Alfred 6 sont interprétés d'après les images publiques : verre et flou natifs de macOS.
- Les tâches d'automatisation viennent du dépôt public déjà utilisé (`roadie workflow tasks update`).

## Dépendances

SPEC-074 (verbes), 077 (fichiers), 082 et 104 (onglets), 085 (touche des chiffres), 088 à 093 (workflows),
091 (sélection multiple), 101 (thèmes), 105 (commandes système), 117 et 118 (vues Texte, Image, PDF), 126 et
127 (langue), 129 (actions sans délai).
