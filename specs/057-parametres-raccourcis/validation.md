# Validation de la session 057
Date : 23 octobre 2026.

## Livré
Pages de paramètres regroupées par usage. Profils du sélecteur avec création,
duplication, renommage, suppression et onglets dédiés. Gestionnaire Roadie,
BetterTouchTool ou commande externe. Enregistrement direct des touches et
annulation par Échap. Modes activer, rester ouvert et rechercher au relâchement.
Recherche et actions contextuelles. Quatre flèches, sélection au survol et
activation au clic. Apparence commune ou propre au profil. Les modificateurs
du raccourci restent acceptés pendant la navigation aux flèches.

La parité complète avec AltTab reste distincte : voir le rapport de comparaison
archivé dans docs/analyses/2026-10-23-parite-alttab.md.

## Tests et revue
- Suite initiale : 1 863 tests, 225 suites, réussis.
- Suite finale après correction des modificateurs maintenus : 1 869 tests,
  227 suites, réussis (21,742 s). 60 tests ciblés du sélecteur réussis avant
  cette dernière suite complète.
- Scripts : 28 tests réussis.
- Revue indépendante Bridget, tâche d7f8cfc9-839b-4c96-a143-30098c82bccf,
  source 0b5f65b0. Lecture des fichiers ; Git et Mac indisponibles au relecteur.
- Corrections après revue : état BTT sans combinaison annoncé comme en attente ;
  échec ou ambiguïté d'import propagé ; réponse d'activation identifiée ; erreur
  initiale conservée si le retour arrière échoue ; brouillon restauré après
  refus ; suppression en un geste des profils et de leurs liaisons reconnues.
  Baseline obligatoire pour toute écriture de collection.
- Contrôle natif de BTT : les champs BTTEnabled/BTTEnabled2 sont absents quand
  actifs et valent 0 quand désactivés. La vérification respecte ce format et
  exige BTTUUID. L'exigence de présence des champs proposée par la revue aurait
  rejeté les activations valides. Déclencheur de contrôle supprimé ensuite.
- Le signalement utilisateur « les flèches ne fonctionnent pas » concernait
  encore le premier build actif. Le filtre exigeait des flèches sans modificateur.
  Le correctif transmet les modificateurs réels du déclencheur au panneau,
  y compris pour la commande externe BTT. Aucune règle Karabiner sur les flèches
  ni combinaison Cmd+flèche BTT globale concurrente trouvée.
- Tests du panneau AppKit : événements des quatre flèches avec Commande maintenue, survol, pointeur
  immobile après une flèche, clic et désactivation par profil ; succès.

## Architecture et coût
Partition du catalogue en O(n), navigation et survol en O(f), f nombre de cartes.
Aucun relevé AX ajouté par déplacement de souris. Liaison BTT hors fil principal,
au plus deux déclencheurs par profil ; neuf profils au maximum. Pas de dépendance
ajoutée. Codec et persistance existants conservés. La frontière BTT porte les
contrôles d'identité et le retour arrière. Pas de nouvelle couche générique.
Le volume ajouté couvre les formulaires, la capture et les trois gestionnaires.
Potentiel minimalisme retenu : aucune suppression supplémentaire à comportement
constant identifiée après ce passage. Aucun benchmark ni gain mesuré annoncé.

## Installation et preuves
Première installation : UUID 1D1FF7E7-0CC0-3F7B-A4A8-533B5069B4F1, PID 54495,
santé 5/5. Configuration inchangée à cette installation ; certificat conservé.
La configuration a ensuite changé pendant l'utilisation du bureau : ces valeurs
sont conservées, sans restauration globale du fichier sauvegardé.

Parcours graphique observé : commande clavier /settings selecteur via les actions
natives BTT ; captures de la fenêtre réelle avant et après installation.
CUA indisponible ; cliclick ne peut pas injecter d'événements depuis le terminal.
Les actions clavier natives BTT fonctionnent. Un essai souris exploratoire a été
interrompu après observation d'une position différente de la cible. Aucun clic
supposé n'est présenté comme preuve. L'utilisation concurrente du bureau empêche
un parcours graphique complet fiable dans ce passage.

Preuves incomplètes : saisie physique de combinaison, transfert complet Roadie/BTT
et relâchements non attestés dans un parcours utilisateur enregistré. Les tests
AppKit complètent les captures ; ils ne remplacent pas cet essai.
Diaporama : preuves-corrections/2026-10-23-parametres-057/preuves.html.
Diaporama contrôlé : navigation, pause, zoom, captures et limite non vérifiée.
Captures originales et journaux conservés hors Git dans le dossier local de
diagnostics 2026-10-23-session057.

## Installation finale
Build Release terminé ; UUID 20584940-BB44-3A34-8DE1-EFC0D35D6159 (arm64).
Daemon relancé, PID 84023, santé 5/5. Signature vérifiée ; certificat
78a75e8032f190a20072eb91cc2919aac344ef78 conservé. Configuration identique
avant/après cette installation (SHA-256 e1c7dadf176ce2afcd4e39097c0b3d890892fcc7a672f1d4ca38943671092f9a).
Les deux entrées BTT Cmd+Tab/Cmd+Maj+Tab ont été relues : keycode 48,
caractère tabulation réel, actions CLI existantes conservées. Aucun raccourci
utilisateur réécrit pendant les essais de schéma. Les déclencheurs de contrôle
ont tous été supprimés. Essai des flèches avec Commande proposé à l'utilisateur
sur ce build final, sans attendre pour achever l'intégration autorisée.
