# Proposition de session 057 - Paramètres structurés et raccourcis directs

Statut: proposition à valider avant modification du code. Dernière session livrée: 056.
Date: 23 octobre 2026.
Estimation du lot proposé: 4 à 6 heures, tests, revue, installation et essai compris.
Cette estimation est un ordre de grandeur, pas un engagement de délai.

## Demande reformulée

Refondre toute la fenêtre des paramètres Roadie pour qu'un utilisateur puisse trouver, comprendre et modifier un réglage sans connaître le fichier de configuration. Conserver la colonne de catégories à gauche. Réorganiser la partie droite en sections cohérentes, avec une hiérarchie visuelle commune et des contrôles adaptés aux usages. Les réglages continuent de s'appliquer immédiatement lorsque la valeur est valide.

Traiter le sélecteur comme un cas complet de cette nouvelle organisation: profils lisibles, mode au relâchement explicite, apparence, fenêtres proposées et navigation. Pour chaque profil, l'utilisateur choisit entre Roadie et BetterTouchTool comme gestionnaire du raccourci. Un bouton d'enregistrement reçoit une combinaison réellement pressée et affiche les symboles macOS. Aucun texte du type alt+tab à composer manuellement. Le même composant sert aux autres raccourcis déjà exposés dans la fenêtre, notamment la recherche.

Dans le sélecteur, les quatre flèches déplacent la sélection selon la géométrie de la grille. Le survol d'une vignette la sélectionne; le clic l'active. Le clavier et la souris ne doivent pas se reprendre mutuellement la sélection sans une action réelle.

## Acquis à conserver

- Navigation de catégories, recherche globale, valeurs et polices réglables existantes.
- Application immédiate des réglages, traitement des saisies intermédiaires invalides.
- Configuration existante, valeurs inconnues préservées et protection contre les écritures concurrentes.
- Commandes CLI, profils existants, raccourci Cmd+Tab BTT déjà validé et propriété des fenêtres Roadie.
- AppKit/SwiftUI natifs, couleurs système, accessibilité et tailles de texte choisies par l'utilisateur.

## Organisation proposée

Chaque page a un titre, une phrase d'aide et des sections de réglages liées à un usage. Les aides longues sont accessibles à la demande. Une ligne simple place le libellé et le contrôle ensemble; un contrôle complexe a sa propre zone. « Avancé » reste accessible sans encombrer les réglages courants. Un résultat de recherche garde le nom de sa catégorie et de sa section.

| Page | Sections principales proposées |
|---|---|
| Général | Interface, texte et accessibilité, état de la configuration |
| Tuilage | Disposition, marges et espaces, nouvelles fenêtres, redimensionnement, exceptions par écran |
| Stages et bureaux | Organisation, noms et destinations, comportement au changement |
| Mode lettres | Activation, affichage des repères, navigation, texte |
| Grille | Activation et structure, navigation et actions, apparence, texte, avancé |
| Recherche | Raccourci, saisie et comportement, apparence et texte |
| Rail | Visibilité et position, cartes et aperçus, noms et numéros, glisser-déposer, apparence, avancé |
| Bordures | Activation, apparence, variantes par stage |
| Focus et souris | Changement de focus, déplacements de stage, suivi de la souris |
| Sélecteur | Profils et raccourcis, fenêtres proposées, navigation, apparence, avancé |
| Règles | Règles de placement, exceptions, automatisations avancées |
| Avancé | Composants, captures et diagnostics, macros, compatibilité |

Le découpage final est déterminé à partir du catalogue réel. Aucune clé ne doit disparaître ou se retrouver sans section. Les couleurs et détails décoratifs restent sobres et suivent macOS.

## Profils du sélecteur

Un profil représente un usage, par exemple « Basculer vite » ou « Explorer les fenêtres ». La liste montre son nom, sa combinaison, son gestionnaire et son mode. Création, duplication, activation et suppression sont directes. L'identifiant technique reste géré par Roadie.

Trois comportements indépendants de la combinaison:
1. Activer la fenêtre choisie au relâchement.
2. Rester ouvert pour naviguer et utiliser les actions.
3. Passer en recherche au relâchement.

Le champ de recherche et les actions peuvent être affichés selon le mode ou explicitement selon le profil. Modifier le mode ne doit pas forcer un nouvel enregistrement de touches. Un aperçu montre le résultat, avec des données de démonstration identifiées.

### Qui gère le raccourci

- Roadie: enregistre et déclenche la combinaison avec ses services clavier.
- BetterTouchTool: Roadie prépare ou met à jour seulement les entrées BTT liées à ce profil, avec la bonne commande CLI et le bon identifiant de profil.
- Un lien existant externe ou Karabiner reste utilisable. Le passage à un autre gestionnaire n'efface pas silencieusement les réglages d'un outil tiers.

Le profil actif a un seul gestionnaire d'ouverture. Un transfert entre gestionnaires prépare la nouvelle liaison, vérifie son activation, puis retire l'ancienne liaison propre à ce profil. Un échec garde ou restaure la liaison fonctionnelle et affiche un message. La présence d'une entrée dans BTT n'est pas une preuve de déclenchement physique; l'essai réel et la trace de commande restent la validation de référence.

Enregistrement direct: attendre un appui, capturer la touche et les modificateurs, afficher ⌘/⌥/⌃/⇧, détecter les collisions connues, Échap annule, effacer désactive. Le traitement conserve le code de touche et sa représentation; il distingue une touche Tab du texte « Tab ». Les collisions inconnues dans d'autres logiciels sont signalées comme non vérifiables, pas comme absentes.

## Navigation clavier et souris du sélecteur

- Gauche/Droite: vignette voisine sur la même ligne.
- Haut/Bas: vignette alignée dans la ligne précédente/suivante; dernière ligne incomplète couverte.
- En liste: Haut/Bas; comportement horizontal cohérent sans sélection arbitraire.
- Le survol modifie la sélection après un vrai mouvement de souris. Un curseur immobile au-dessus d'une carte ne reprend pas la sélection après une flèche.
- Clic valide; survol seul ne donne pas le focus à une application.
- En édition de recherche, les flèches de navigation, le curseur de texte, la sélection du texte et la composition IME ont une règle explicite. Prévoir une navigation de résultats indépendante de l'édition, sans confisquer les commandes macOS de texte.
- Un menu Actions ouvert conserve ses propres commandes clavier.
- L'aperçu peut se rafraîchir sans reconstruire toute la liste ni refaire un relevé AX à chaque mouvement.

## Critères de réussite

1. Toutes les clés exposées avant refonte restent accessibles et recherchables, avec une section définie.
2. L'utilisateur crée deux profils et choisit leur gestionnaire sans écrire une combinaison en texte.
3. Une touche réellement pressée s'affiche correctement, y compris Tab, flèches, accents/layouts usuels et modificateurs. Cmd+Tab est essayé réellement avec le gestionnaire choisi.
4. Changer de gestionnaire ne produit pas un double déclenchement. Un échec de BTT ne supprime pas un raccourci encore fonctionnel.
5. Chaque mode au relâchement a un parcours testé; la recherche et les actions ont une présentation cohérente avec ce mode.
6. Les quatre flèches sélectionnent les bonnes cartes; un survol sélectionne, un clic valide; clavier puis souris fonctionnent dans les deux sens.
7. Les réglages s'appliquent immédiatement. Les polices et les valeurs existantes restent conservées.
8. Tests ciblés puis suite complète sur Mac, revue indépendante si la liaison Bridget est disponible, installation et santé; preuve des parcours visibles ou limites explicites.

## Découpage d'exécution proposé

- Lot A: regroupement de toutes les pages et composants communs des réglages.
- Lot B: profils du sélecteur, trois modes, présentations contextuelles et aperçu.
- Lot C: enregistrement natif des touches, choix du gestionnaire, liaison BTT et transfert sûr.
- Lot D: navigation géométrique, survol et arbitrage clavier/souris.
- Lot E: migration/rétrocompatibilité, tests, documentation FR/EN, revue, installation, validation et nettoyage autorisés.

Un responsable mène l'intégration. Les délégations restent limitées aux livrables distincts autorisés. La revue indépendante conserve l'autorisation permanente.

## Place de la parité complète avec AltTab

Le rapport de comparaison reste la référence:
/Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/025-settings-readability/docs/analyses/2026-10-23-parite-alttab.md

Cette refonte traite l'organisation et les interactions demandées. Les écarts de filtres combinés, recherche approchée, applications sans fenêtre, onglets et Spaces natifs restent visibles dans le plan de parité; ils ne sont pas déclarés livrés par une nouvelle interface. Leur réalisation nécessite les lots fonctionnels suivants. Aucun objectif déjà demandé n'est annulé.

## Vocabulaire utile

- Profil: un ensemble de choix pour un usage précis du sélecteur.
- Gestionnaire du raccourci: logiciel qui reçoit la combinaison et lance l'action.
- Enregistrement: appuyer sur les vraies touches, au lieu de les écrire.
- Sélection: vignette visée dans le sélecteur. Activation: donner le focus à sa vraie fenêtre.

## Sources et limites

- Analyse de l'interface actuelle: SettingsView.swift affiche une seule carte par catégorie, sauf Général. SettingsCollectionEditor.swift affiche un formulaire générique de lignes. La navigation à gauche et les services de persistance sont réutilisables.
- https://developer.apple.com/design/human-interface-guidelines/settings : groupes cohérents, contexte et conventions de paramètres.
- https://developer.apple.com/documentation/appkit/nsevent : code de touche, modificateurs et événements clavier natifs.
- Comparaison AltTab et Roadie conservée dans le rapport cité.
- La maquette HTML n'est pas installée. La capture d'un raccourci dans un navigateur ne valide pas la capture des combinaisons réservées par macOS; cette dernière doit être testée dans le composant AppKit.


Vérification de la maquette: rendus 728 et 375 pixels examinés. Aucun débordement horizontal. Quatre flèches, sélection au survol et réception d’une combinaison simulées par événements JavaScript et contrôlées; aucune preuve d’appui physique macOS ni de liaison BTT réelle dans la maquette.
