# Effets Wayland et adaptation à Roadie

Recherche du 31 octobre 2026. Mise à jour de la décision : la session 144 retient des animations indépendantes de macOS, selon la clarification de l’utilisateur. La proposition initiale ci-dessous est historique ; son conseil de suivre Réduire les animations est remplacé. La réalisation et ses limites sont décrites dans specs/144-effets-reglables/. Demande : étudier le compositeur Wayland probablement Hyprland, puis proposer des effets paramétrables dans Roadie. Ce document ne valide pas une implémentation ni une nouvelle session.

## Identification et sources lues
- Hyprland : https://wiki.hypr.land/configuring/core/animations/ et https://wiki.hypr.land/configuring/core/config-options/ (documentation de développement, pas garantie d'une release stable).
- Sources Hyprland examinées au commit 4b9ac40d71ceeeb027cfa06992c9212e3c3077b6 : src/animation/AnimationManager.cpp (tick, lignes 153–335 ; ordonnancement 339–390), src/animation/WorkspaceAnimationController.cpp, src/render/Renderer.cpp (rendu, snapshots lignes 3362 et suivantes).
- Sources hyprutils examinées au commit 7e1f69209cd910615d0573a93fa970408f643539 : include/hyprutils/animation/AnimatedVariable.hpp (changement de cible 225–249 ; mise à jour 274–291), src/animation/Spring.cpp et AnimationManager.cpp.
- niri : https://niri-wm.github.io/niri/Configuration:-Animations.html ; https://niri-wm.github.io/niri/Development:-Animation-Timing.html ; https://niri-wm.github.io/niri/Window-Effects.html. Sources au commit 8e7b5745407294ed37b4b4d8ff4cf4574d45686b : src/animation/mod.rs, src/render_helpers/shaders/resize.frag.
- Wayfire : https://wayfire.org/ ; https://github.com/WayfireWM/wayfire/wiki/Configuration#wobbly.
- Architecture Wayland : https://wayland.freedesktop.org/architecture.html.
- Capture macOS : https://developer.apple.com/documentation/screencapturekit (version Markdown lue également).

## Comment ils font
Le compositeur reçoit les images des applications et dessine l'écran. Une fenêtre est donc aussi une texture transformable, indépendamment de sa taille logique. Hyprland anime des valeurs : position, dimensions, opacité, couleur. Le moteur calcule une valeur intermédiaire entre départ et cible selon une courbe. Un changement de destination repart de la valeur affichée ; le code des ressorts cherche aussi à conserver la dynamique. Le rendu ne repeint que les zones concernées, regroupe les changements par propriétaire et programme les écrans concernés. Une liste vide d'animations actives termine la passe.

Hyprland propose des familles héritées : fenêtres, ouvertures, fermetures, mouvements, fondus, bureaux et décorations. Les styles comprennent notamment glissement et apparition par agrandissement. Courbes Bézier ou ressorts nommés dans la documentation de développement consultée. Décorations séparées : arrondis, ombres, opacité, flou.

niri ajoute une horloge cohérente par événement et rend l'animation pour l'instant prévu de présentation à l'écran. Son moteur sépare interpolation à durée fixée et ressort avec vitesse initiale. Le ressort n'a pas une durée fixe directement réglable : amortissement et raideur déterminent son arrêt. Des shaders personnalisés existent pour ouverture, fermeture et redimensionnement. Les effets de fond récents incluent flou, saturation, bruit et xray ; leur coût dépend des images à recalculer.

Wayfire dispose d'un plugin de fenêtres élastiques : friction, constante du ressort et résolution de la grille de déformation. C'est une transformation de la représentation graphique, pas une succession de redimensionnements de l'application.

## Existant Roadie vérifié
- /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/025-settings-readability/Sources/RoadieDaemon/OverviewPanel.swift : interpolation des cartes à 150 ms, ralentissement cubique, timer limité à l'animation.
- /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/025-settings-readability/Sources/RoadieDaemon/RailPanel.swift : NSAnimationContext pour l'ouverture/fermeture du rail ; durée issue de la configuration.
- /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/025-settings-readability/Sources/RoadieCore/Config.swift : bordures, couleur active/inactive et pulseOnFocus déjà paramétrables ; pas de moteur global d'animation des fenêtres.
- /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/025-settings-readability/Sources/RoadieDaemon/RailThumbnailStore.swift : captures ScreenCaptureKit asynchrones, cache existant.
- Aucun usage de SLSSetWindowTransform ou SLSSetWindowAlpha trouvé dans Sources. Les usages SkyLight présents portent sur le focus et les Spaces, pas sur un moteur d'effets.

## Faisabilité macOS
1. Rail, lanceur, sélecteur, vue d'ensemble et bordures Roadie : contrôle direct du rendu ; fondus, glissement, zoom, ombre et surbrillance sont des extensions réalistes de l'existant.
2. Déplacements/redimensionnements de vraies fenêtres : interpolation des commandes AX possible, mais chaque taille peut faire recalculer l'application. À comparer à un aperçu visuel temporaire animé par Core Animation/Metal, obtenu depuis ScreenCaptureKit, puis relayé par la vraie fenêtre. Cette deuxième piste est une hypothèse à éprouver : synchronisation, qualité du texte, contenu vidéo et interruption par clic ne sont pas validés.
3. Transitions de stages : possible piste d'animation des représentations de groupes, avec placement final autoritaire ; prototype requis pour éviter flash et capture ancienne.
4. Flou arbitraire de fenêtres tierces, déformation élastique interactive, cube 3D : pas de contrôle public équivalent à un compositeur Wayland dans l'existant Roadie. Simulation sur une image envisageable ; aucune parité ni compatibilité générale promise.

## Proposition utilisateur
Page Paramètres > Effets. Interrupteur général et profils Aucun / Sobre / Souple / Expressif. Réglages par action : réorganisation, changement de stage, ouverture/fermeture, rail, lanceur, sélecteur et vue d'ensemble.

Chaque famille : activé, style (fondu, glissement, zoom selon pertinence), durée en millisecondes pour les courbes temporelles, courbe et intensité. En mode ressort, afficher raideur/amortissement ou une commande simple « rebond », sans promettre une durée physique indépendante. Aperçu immédiat et retour au défaut.

Proposition de défaut : sobre, 150–180 ms, sans rebond ; suivi sous la souris immédiat. L'amorti des voisines pendant le glisser reste un choix séparé et ne doit pas créer une file de mouvements anciens. Respecter Réduire les animations de macOS et ne pas entretenir de boucle de rendu quand rien ne bouge.

## Suite proposée, non commencée
Session 144 « Effets réglables ». D'abord prototype borné sur vraies fenêtres et stages (environ 1–2 h), puis moteur commun et page de réglages si le prototype respecte l'usage (environ 2–4 h supplémentaires). Estimations, pas engagement de résultat avant mesure. Vérifier Finder, navigateur, éditeur et fenêtre à taille imposée, plusieurs écrans, interruption/nouvelle destination, CPU au repos et pendant geste. Aucun changement des réglages système ou des protections n'est autorisé ou nécessaire à cette étude.

Le fichier apercu.html est une simulation d'intention dans le navigateur. Il n'exécute aucun effet dans Roadie.
