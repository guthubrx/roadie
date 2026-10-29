# Validation 131 - Actions d'Alfred et nouveautés d'Alfred 6

## Périmètre
Lignes « En partie » de la référence Alfred et nouveautés annoncées d'Alfred 6, hors Snippet, Contacts, IA et
transformation de texte (choix de l'utilisateur, 29 octobre 2026). 26 tâches, toutes cochées (T026 ajoutée par
Converge).

## Tests
- Suite Swift complète : 2 318 tests dans 343 suites réussis (`scripts/test --no-parallel`, aucune suite exclue),
  avant la tâche T026 ; tests ciblés après T026 : `Spec131TextTests` 6/6.
- Tests de scripts : 28 réussis.
- Nouveaux tests : `Spec131FileOperationsTests` (opérations sur dossiers temporaires, corbeille simulée),
  `Spec131TextTests`, `Spec131ReturnModifiersTests`, `Spec131WorkflowObjectsTests`, `Spec131BarCommandsTests`,
  `Spec131MarkdownTableTests` (mise en page réelle TextKit 1), `Spec131ThemeTests`, `Spec131AppsGridTests`,
  `Spec131SymbolsTests` (données réelles de macOS : plus de 9 000 symboles).
- Quatre anciens tests mis à jour : listes de verbes agrandies volontairement (074, 077, 090, 091) ; comptages du
  catalogue des paramètres (+4 réglages).

## Défauts trouvés pendant l'implémentation
- Grille des symboles : le rectangle de dessin infini (dessin par couche) arrêtait le processus à sa conversion en
  entier (rapport de plantage lu, hypothèse initiale réfutée) ; rectangle borné à la vue. Aucune autre conversion
  de ce type dans le code.
- Tableaux Markdown : TextKit 2, utilisé par défaut, ignore `NSTextTable` (cellules en escalier, vu sur le rendu
  hors écran) ; la vue Texte passe en TextKit 1. Le test vérifie maintenant la mise en page.

## Rendus vérifiés
Rendus hors écran regardés : grille SF Symbols (6 colonnes, sélection turquoise) et tableau Markdown (en-tête,
filets, alignements). Images non conservées dans le dépôt (contrôle local).

## Installation
Roadie installé, signé `roadied-cert`, PID 65429, santé 5/5, UUID 7A80EA05-6ABB-3822-A501-C52F59FD3137,
configuration identique avant et après (empreinte 166624a713447bc4).

## Non vérifié
- SC-003 (menus lus en moins de 1 s) : pas d'ouverture de la barre sur l'écran de l'utilisateur ; la durée réelle
  est écrite dans `~/.roadies/events.jsonl` (`launcher.menus`, champ `ms`) au premier `menu …`.
- Parcours réels des verbes (Mail, onglets, captures, mode sombre, styles en verre sur le fond d'écran) : clics
  simulés refusés sur ce poste ; essai utilisateur proposé.
- Numéros d'Alfred déduits et non confirmés par un workflow réel : commandes système 3, 4, 10, 12 à 14 ; Musique
  4, 6, 7, 9 à 12 (research R2, R3).

## Revue indépendante
Indisponible : `bridget_auto_delegate` absent du catalogue Bridget (incident remis à bridge1016, sans réponse).

## Preuves visuelles
Pas de diaporama : clics simulés refusés sur ce poste.
