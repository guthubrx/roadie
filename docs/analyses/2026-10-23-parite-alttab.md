# Vérification de parité du sélecteur Roadie avec AltTab

Date : 23 octobre 2026.
Roadie examiné : 4e506c7c8c563c069f63ebf5543e4b54ee16b382. AltTab examiné : 2d4f4c8fab1eeb3ec08f32abdf541713b68d89d0, même révision que l'étude initiale.
Méthode : pages officielles, préférences et chemins d'exécution du code source ; comparaison directe avec la configuration et le code installés de Roadie. Aucune nouvelle modification du code, de BTT ou de la configuration utilisateur. Aucun benchmark.

## Réponse au besoin immédiat

Paramètres > Sélecteur > Profils de raccourcis > Action au relâchement possède déjà deux choix : « Activer la fenêtre choisie » et « Garder le sélecteur ouvert ». Le profil réel `all` est en mode `focus`. La commande BTT `switcher cycle --hold cmd` utilise ce profil par défaut.

Le champ de recherche et le menu Actions sont toujours présents. Le champ reçoit le focus dès l'ouverture. Une recherche non vide maintient automatiquement le panneau ouvert, même avec release_action=focus. Il n'existe pas de réglage pour masquer ces éléments par profil. AltTab sépare trois modes : Focus, Hold et Search ; Search au relâchement relève de Pro. Roadie fusionne actuellement Hold et l'entrée en recherche.

Conclusion : nous avons repris des fonctions de base et les quatre grandes familles mises en avant dans l'offre Pro, mais pas toutes leurs variantes. « Parité complète » serait inexact. Les intitulés Présent/Partiel/Absent décrivent les capacités ; ils ne garantissent pas une parité de fiabilité, de performances ou d'accessibilité.

## Inventaire des fonctions de sélection

| Famille | Fonction AltTab | Offre | État Roadie | Constat |
|---|---|---|---|---|
| Modes et profils | Valider au relâchement | Gratuit | Présent | Le profil choisit « Activer la fenêtre choisie ». Ton profil actuel utilise ce mode. |
| Modes et profils | Rester ouvert au relâchement | Gratuit | Présent | Option « Garder le sélecteur ouvert » déjà disponible dans les profils. |
| Modes et profils | Passer en recherche au relâchement | Pro | Partiel | Pas de troisième mode distinct : le champ est déjà actif dès l’ouverture et « rester ouvert » permet de saisir. |
| Modes et profils | Entrer/sortir de recherche par une touche ; Échap en deux étapes | Pro | Absent | Roadie garde la recherche visible. Échap ferme tout, au lieu de quitter d’abord une recherche entrée en cours de session. |
| Modes et profils | Jusqu’à neuf profils | Pro | Présent | Filtres, tri et relâchement propres à chaque profil ; déclenchement CLI/BTT possible. |
| Modes et profils | Style, taille, thème et aperçu propres à un profil | Selon option | Absent | Ces réglages sont globaux dans Roadie. AltTab propose des valeurs différentes par raccourci. |
| Recherche | Application et titre ; tolérance aux accents | Pro | Présent | Roadie cherche aussi la stage, le bureau et l’écran. |
| Recherche | Acronymes, petites fautes et surlignage des correspondances | Pro | Absent | Roadie exige les fragments saisis ; pas de recherche approchée ni de surlignage. |
| Navigation et actions | Tab, Maj+Tab, Retour, Échap et clic | Gratuit | Présent | Ouverture et validation par ⌘ Tab confirmées sur ton Mac. |
| Navigation et actions | Quatre flèches selon la grille, touches Vim, sélection au survol | Gratuit | Partiel | Haut/Bas parcourent la liste ; Gauche/Droite éditent la recherche. Pas de Vim ni de survol réglable. |
| Navigation et actions | Touches d’action configurables dans le sélecteur | Gratuit | Absent | Les actions Roadie passent par un menu ; pas de touches personnalisables pour fermer, réduire, masquer ou quitter la sélection. |
| Navigation et actions | Boutons fermer/réduire/plein écran sur la vignette survolée | Gratuit | Absent | Menu d’actions commun seulement. |
| Navigation et actions | Fermer, réduire/restaurer et quitter normalement | Gratuit | Présent | Actions sur l’identité de la fenêtre sélectionnée. |
| Navigation et actions | Masquer / réafficher une application sans ouvrir sa fenêtre | Gratuit | Partiel | Masquer existe ; réafficher passe par l’activation, pas par une bascule dédiée. |
| Navigation et actions | Plein écran natif depuis le sélecteur | Gratuit | Partiel | Roadie propose son plein écran et sa maximisation ; ce n’est pas l’action native Spaces d’AltTab. |
| Navigation et actions | Glisser un fichier sur une vignette pour ouvrir son application | Gratuit | Absent | Aucune destination de dépôt dans le panneau Roadie. |
| Navigation et actions | Gestes 3/4 doigts et retour haptique | Gratuit | Partiel | BTT peut lancer les commandes ; pas de navigation gestuelle continue ni d’haptique intégrée au sélecteur. |
| Fenêtres et filtres | Toutes les fenêtres du Mac, même hors gestion Roadie | Gratuit | Partiel | Seules les fenêtres rattachées à une stage Roadie sont listées. |
| Fenêtres et filtres | Fenêtres réduites, applications masquées et plein écran | Gratuit | Présent | Inclusion/exclusion par profil ; les états non vérifiés sont signalés. |
| Fenêtres et filtres | Mettre les fenêtres réduites/masquées en fin de liste | Gratuit | Absent | Roadie offre seulement inclure ou exclure. |
| Fenêtres et filtres | Combiner application + écran + espace dans un même profil | Gratuit | Partiel | Un seul filtre de portée Roadie à la fois : application, écran, bureau, stage ou tout. |
| Fenêtres et filtres | Applications non actives ; fenêtre/application sous la souris | Gratuit | Absent | Ces portées ne figurent pas dans les profils Roadie. |
| Fenêtres et filtres | Une fenêtre par application | Gratuit | Présent | Option déjà disponible dans les profils. |
| Fenêtres et filtres | Tri par récence, titre et espace | Gratuit | Partiel | Récence/titre/stage Roadie présents ; tri par création récente manquant. |
| Fenêtres et filtres | Applications ouvertes sans fenêtre | Gratuit | Absent | Le modèle Roadie exige une fenêtre et sa stage. |
| Fenêtres et filtres | Onglets macOS présentés séparément | Gratuit | Absent | Pas d’inventaire ni d’activation des onglets natifs. |
| Fenêtres et filtres | Spaces macOS visibles ou non visibles | Gratuit | Partiel | Bureaux/stages Roadie pris en compte ; aucun équivalent complet des Spaces natifs. |
| Fenêtres et filtres | Exclusions simples par application | Gratuit | Présent | Liste globale d’identifiants d’applications. |
| Fenêtres et filtres | Exceptions par titre ; suspendre un raccourci selon l’application/plein écran | Gratuit | Absent | Pas de règles équivalentes dans le sélecteur. BTT peut gérer une partie des exceptions de raccourcis. |
| Apparence | Vignettes, icônes, liste et dimensionnement automatique | Pro pour styles supplémentaires et automatique | Présent | Réglages globaux ; police et taille du texte également modifiables. |
| Apparence | Aperçu à la taille de la fenêtre, au-dessus du bureau | Gratuit | Partiel | Roadie affiche un grand aperçu dans le panneau, issu du cache partagé. |
| Apparence | Cadence et politique de captures en arrière-plan | Gratuit | Partiel | Captures demandées à l’ouverture ; pas de réglage équivalent au suivi permanent d’AltTab. Fraîcheur non comparée. |
| Apparence | Choisir l’écran : actif, souris ou barre des menus | Gratuit | Absent | Roadie ouvre le panneau sur l’écran de la souris. |
| Apparence | Thème clair/sombre forcé ou système | Gratuit | Partiel | Aspect système suivi ; pas de choix propre au sélecteur ni au profil. |
| Apparence | Afficher/masquer titres, badges, numéros et boutons ; troncature du titre | Gratuit | Partiel | Titres et badges existent ; personnalisation fine absente. |
| Apparence | Délai d’apparition et animations réglables | Gratuit | Absent | Temporisation interne fixe ; aucun réglage utilisateur équivalent. |
| Accessibilité | Souris qui suit le focus | Gratuit | Partiel | Réglage global Roadie oui/non ; pas du choix « seulement vers un autre écran ». |
| Accessibilité | VoiceOver, touches rémanentes et transparence réduite | Gratuit | À vérifier | Libellés et activation d’accessibilité présents ; parcours assisté et parité complète non testés. |
| Accessibilité | Interface en plusieurs langues | Gratuit | Partiel | Interface Sélecteur en français ; documentation FR/EN. Pas de sélection de langue équivalente. |

## Compléments nécessaires

1. **Modes explicites et indépendants par profil.** Distinguer validation immédiate, maintien pour navigation/actions, entrée en recherche. Découpler le comportement au relâchement de l'affichage du champ et des actions. Rendre ces choix visibles dans les réglages, sans les enfouir uniquement dans l'éditeur de lignes. Ajouter une action de recherche et un Échap en deux étapes. Conserver l'ouverture externe par CLI/BTT et les choix existants.
2. **Parité des commandes et de la recherche.** Navigation dans la grille, survol facultatif, touches d'action paramétrables, boutons sur les cartes, recherche approchée et surlignage, maintien de l'identité de sélection pendant les actions.
3. **Profils et filtres complets.** Apparence par profil, combinaison des critères, états à la fin de la liste, création récente, exceptions par titre et par application. Ajouter le choix de l'écran d'affichage et les détails d'apparence.
4. **Compatibilité macOS et interactions supplémentaires.** Fenêtres hors gestion Roadie, applications sans fenêtre, onglets et Spaces natifs ; dépôt de fichiers, gestes et accessibilité réelle. Cette partie touche au modèle d'identité et à l'activation. Elle doit préserver l'appartenance Roadie et être validée séparément. Les réglages BTT externes ne constituent pas une reprise du moteur gestuel d'AltTab.

Ordre conseillé : 1, puis 2 et 3 ; 4 nécessite une étude de faisabilité et un prototype macOS. Le tout représente plusieurs sessions. Une seule petite correction de paramètres ne peut pas garantir l'ensemble de cette parité. Les estimations dépendent des choix sur les onglets et les Spaces.

## Périmètre du mot « toutes »

Cet inventaire couvre les fonctions visibles de sélection et leurs réglages. La licence payante, l'activation commerciale, le système de paiement, les statistiques de téléchargement et les canaux de distribution ne sont pas des fonctions de sélection à reproduire. Les mises à jour automatiques, la signature publique/notarisation, les architectures et les traductions relèvent du produit Roadie entier ; leur parité n'est pas attestée par cet inventaire.

## Preuves Roadie

- Sources/RoadieCore/WindowSwitcherConfig.swift : deux actions au relâchement, neuf profils, portée unique, états booléens, styles et aperçu globaux.
- Sources/RoadieDaemon/SettingsCollectionCatalog.swift : réglages par profil et libellés français.
- Sources/RoadieDaemon/WindowSwitcherController.swift : persistance si une recherche non vide est saisie.
- Sources/RoadieDaemon/WindowSwitcherPanel.swift : recherche toujours visible, premier répondant champ, menu Actions, navigation Haut/Bas, écran choisi par souris.
- Sources/RoadieDaemon/WindowSwitcherModel.swift : recherche par fragments, récence/titre/stage, exclusions globales.
- Sources/RoadieDaemon/WindowSwitcherService.swift : entrées avec appartenance à une stage, actions et activation.
- Sources/RoadieAX/WindowSwitcherWindowAccess.swift : réduire/restaurer est bien une bascule ; masquer seul est une action distincte.
- Sources/RoadieDaemon/MouseFollower.swift : suivi du focus global, oui/non.
- Tests/RoadieDaemonTests/Spec056SwitcherUITests.swift : scénarios release/stay/recherche déjà présents. Tests relus, pas relancés pour cette inspection sans modification de code.

Contre-relecture demandée mais non démarrée : `t3_session_unavailable: binding_registration_refused : primary_absent : le lien Bridget du fil est absent`. Aucun autre moteur utilisé en remplacement.

## Sources officielles

- [Fonctions et offre](https://alt-tab.app/features)
- [Gratuit et Pro](https://alt-tab.app/pricing)
- [Modes, filtres, apparence](https://github.com/lwouis/alt-tab-macos/blob/2d4f4c8fab1eeb3ec08f32abdf541713b68d89d0/src/preferences/MacroPreferences.swift)
- [Réglages et exceptions](https://github.com/lwouis/alt-tab-macos/blob/2d4f4c8fab1eeb3ec08f32abdf541713b68d89d0/src/preferences/Preferences.swift)
- [Fonctions réservées à Pro](https://github.com/lwouis/alt-tab-macos/blob/2d4f4c8fab1eeb3ec08f32abdf541713b68d89d0/src/pro/ProFeature.swift)
- [Recherche et Échap](https://github.com/lwouis/alt-tab-macos/blob/2d4f4c8fab1eeb3ec08f32abdf541713b68d89d0/src/switcher/state/SearchModeResolver.swift)
- [Recherche approchée](https://github.com/lwouis/alt-tab-macos/blob/2d4f4c8fab1eeb3ec08f32abdf541713b68d89d0/src/switcher/SearchTestable.swift)
- [Commandes clavier](https://github.com/lwouis/alt-tab-macos/blob/2d4f4c8fab1eeb3ec08f32abdf541713b68d89d0/src/switcher/ShortcutAction.swift)
- [Dépôt de fichiers](https://github.com/lwouis/alt-tab-macos/blob/2d4f4c8fab1eeb3ec08f32abdf541713b68d89d0/src/switcher/main-window/TilesView.swift)

