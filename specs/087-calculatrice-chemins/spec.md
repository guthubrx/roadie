# Spécification 087 - Calculatrice et chemins tapés dans le lanceur

Demande du 26 octobre 2026 (`/my.specify-all 086 a 091`) : « je voudrais bien déjà la
calculatrice et la capacité d'ouvrir un fichier ou un dossier en mettant son adresse, son chemin
complet ». La référence Alfred (`docs/analyses/2026-10-25-reference-alfred.html`) avait écarté la
calculatrice ; l'utilisateur la demande, ce choix est donc revu. La navigation dans les dossiers
était en priorité 3.

## Demande reformulée
Dans Capslock + F, un calcul tapé affiche son résultat en première ligne ; Retour le copie.
Une saisie qui commence par `~`, ou par `/` suivi d'un dossier qui existe, liste le contenu de
ce dossier filtré par la suite tapée ; Tab complète le nom choisi comme le Terminal, Retour ouvre
le fichier ou le dossier comme un fichier trouvé par Spotlight (stage du dossier, verbes, Finder,
Quick Look, ⌘C). Le mode commande `/` reste intact.

## Dépendances
SPEC-077 (fichiers, verbes et ouverture d'un fichier), SPEC-023 (mode commande `/`),
SPEC-075 (variantes et raccourcis 1 à 9), SPEC-085 (touche des raccourcis).

## Exigences
- **FR-001 Reconnaissance d'un calcul.** Une saisie est un calcul si elle contient au moins un
  opérateur entre deux nombres (`+ - * / ^ × ÷ %`), ou commence par `=`. Nombres décimaux avec
  `,` ou `.`. Parenthèses. Après `=` : `pi`, `e` et les fonctions `sqrt abs round floor ceil
  exp ln log log2 sin cos tan asin acos atan`. Un nombre seul n'est pas un calcul.
- **FR-002 Ligne Calcul.** En tête, sous l'en-tête « Calcul » : le résultat, avec en détail le
  calcul relu et « Retour copie ». Elle est choisie par défaut. Une saisie incomplète (`12*`), une
  division par zéro ou un résultat non fini ne montrent pas de ligne et ne font jamais planter.
- **FR-003 Résultat.** Au plus 12 chiffres significatifs, séparateur décimal de la langue du
  système, sans séparateur de milliers. Retour et ⌘C copient ce texte ; la barre se ferme sur
  Retour. Priorités : `^` (de droite à gauche) puis `* / %` puis `+ -` (de gauche à
  droite) ; moins unaire, plus faible que `^` (`-2^2` = -4).
- **FR-004 Mode chemin.** La saisie est un chemin si elle commence par `~`, ou par `/` et que :
  elle contient un second `/`, ou son premier nom est le début d'un élément de `/` (casse
  ignorée) sans être le début d'une commande ni d'un alias du mode commande. Sinon `/` ouvre le
  mode commande comme avant.
- **FR-005 Liste d'un dossier.** Le dossier est la partie avant le dernier `/` (`~` = dossier
  personnel) ; la suite filtre ses éléments par l'appariement du lanceur. Si le chemin tapé
  désigne lui-même un élément existant, il vient en premier. Dossiers puis fichiers, par nom ;
  éléments cachés seulement si la suite commence par `.` ; 200 éléments lus au plus. Section
  « Chemin » ; la liste défile avec la sélection. Lecture hors du fil principal ; une réponse périmée est ignorée.
- **FR-006 Tab complète.** En mode chemin, Tab remplace la saisie par le chemin de la ligne
  choisie (`~` gardé), suivi de `/` pour un dossier ; → ouvre ses verbes. Hors mode chemin, Tab
  garde son rôle.
- **FR-009 Chiffres et touche Maj.** Avec `pick_modifier = "shift"` (réglage de l'utilisateur,
  085), Maj + chiffre de la rangée du haut écrit le chiffre quand la saisie est vide ou n'est
  faite que de caractères de calcul (chiffres, espaces, `+ - * / ^ % , . ( ) = × ÷`), ou commence
  par `=` (calcul avancé, `=sqrt(2)`, correction du 27 octobre) : en AZERTY,
  les chiffres se tapent avec Maj. Ailleurs, Maj + chiffre reste le raccourci de la ligne.
- **FR-007 Ouvrir.** Retour, les verbes, ⌘C, ⌘Y et les variantes ⌘/⌥/⌃ se comportent comme pour un
  fichier trouvé par Spotlight (SPEC-077). Un dossier s'ouvre dans le Finder.
- **FR-008 Rien d'autre en mode chemin.** Applications, fenêtres, Spotlight et cibles ne sont pas
  cherchés tant que la saisie est un chemin.

## Critères de réussite
- `12*4,5` → `54` ; `2^3^2` → `512` ; `-(3+4)*2` → `-14` ; `=sqrt(2)` → `1,41421356237` (langue
  française) ; `12*` et `1/0` → aucune ligne ; aucun plantage sur 10 000 saisies aléatoires.
- `~/Doc` liste `Documents` en premier ; Tab donne `~/Documents/`.
- `/Us` → mode chemin ; `/set` et `/s` → mode commande ; `/Users/` → mode chemin.
- Liste mise à jour en moins de 50 ms par frappe pour un dossier de 200 éléments.

## Analyse (phase 4)
- A1 (élevé, corrigé par FR-009) : avec Maj pour les raccourcis, un calcul ne se tapait qu'au pavé
  numérique en AZERTY.

## Hors périmètre
Unités et devises, historique des calculs, conversion de bases ; navigation par ⌫ qui remonte
d'un dossier, tri par date, aperçu automatique (la référence Alfred les garde en priorité 3).
