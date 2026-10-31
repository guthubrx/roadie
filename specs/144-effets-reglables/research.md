# Recherche et prototype — Session 144

## Clarification du besoin
L'utilisateur veut le vrai contenu réorganisé dans le cadre de destination. Une capture 16:9 étirée dans un cadre 9:16 ne convient pas. Le mode retenu à prototyper est donc un placement provisoire de la vraie source, avec sa future taille, et une prise en charge exclusive du geste. Le pointeur continue de choisir la destination ; la source peut se trouver directement dans celle-ci. Pas de mutation d'affectation/arbre avant le dépôt.

## Réutilisation
DropPreviewEngine connaît déjà le cadre final et utilise une visée figée. LiveDropPreview déplace les voisines sans persistance, via InteractiveFrameDispatcher et un permis révocable. L'ancien glisser source reste piloté par AppKit, avec des moniteurs NSEvent d'observation. Les poignées disposent d'une prise en charge explicite, mais celle-ci ne prouve pas que l'on sache encore transférer sans conflit un glisser de titre démarré dans une application tierce.

## Premier essai natif : dimensions et conflit de position
Fenêtre AppKit fictive, aucun changement du code Roadie. Demande de frame traitée par l'application de test pendant le bouton enfoncé. Large fenêtre au départ (3690 × 2122). Cadre demandé et observé : x=1912, y=-567, largeur=450, hauteur=800. Après un mouvement supplémentaire de la souris, le cadre observé est x=1982, y=-467, largeur=450, hauteur=800. La vraie taille est donc acceptée ; le glisser natif continue ensuite à changer la position. Cela justifie le prototype de transfert du geste, plutôt qu'un writer source ajouté au moniteur existant.

Limites : cet essai utilise NSWindow.setFrame dans l'application fictive, pas encore AX sur une application tierce. Le placement/taille sont prouvés par ses observations ; le premier rendu du texte du double était mal cadré, donc aucune preuve de remise en page de navigateur n'en est déduite. Le second essai a lu la frame avant stabilisation du placement Roadie et visé un autre écran : il est exclu des conclusions. Sa capture n'est pas publiée. Ne pas empiler un troisième essai identique ; le prochain protocole devra attendre stabilité de frame ET appartenance à la stage/écran avant tout appui.

Les deux applications de test se sont arrêtées normalement, les fenêtres ont disparu et validation144 a été supprimée sur l'écran concerné. La stage initiale 4-restored-2 est rétablie. Aucun moteur d'effet de production modifié.

## Coût attendu, non mesuré
Une vraie remise en page sollicite l'application cible. Le coût est donc plus élevé qu'une transformation d'image, surtout pour un navigateur ou un éditeur chargé. Réduire ce coût en envoyant la taille seulement au changement de candidat, et non à chaque image ni à chaque pixel du pointeur. Les mises en attente anciennes sont remplacées par la dernière cible. Aucune estimation CPU/GPU chiffrée avant comparaison sur applications représentatives.

## Choix avant code
Ne pas implémenter l'ancienne proposition de photo comme aperçu réel. Prochaine expérience : propriétaire du geste identifié avant toute écriture source, clic simple préservé, contrôles de titre exclus, annulation/nouveau geste testés ; puis reformatage AX sur navigateur et éditeur. Évaluer la nécessité d'un mécanisme d'interception au début du geste. Garder le rectangle actuel tant que le prototype n'est pas concluant.

## Décision expérimentale — prototype vérifié
Le prototype hors dépôt lancé par LaunchServices et signé avec le certificat déjà utilisé par Roadie obtient AX=true et tap=true. Même binaire lancé directement depuis le terminal : AX=false, tap=false. Aucun droit n’a été changé. Le test arme le tap uniquement pour la fenêtre fictive et vérifie sa frame stable et sa stage avant le clic.
Résultat : frame initiale (1662,-767,3690,1749), frame pendant appui (1912,-567,450,800), identique après second mouvement. Trois écritures AX : succès (0,0,0). 21 mouvements captés. Capture du texte réorganisé vérifiée visuellement. Le mouseUp laissé à son point physique produit un dernier delta ; neutralisé au point initial, ce delta disparaît. La passe normale remet ensuite le tuilage puisque le prototype ne valide aucun dépôt : cela ne prouve pas encore la fin de geste de production.
Observations : /private/tmp/roadie144-real-preview/owned-result.json et samples.json. La première exécution a manqué le nettoyage à chaud d’une stage encore non réconciliée ; elle a été supprimée après observation, pas par édition de store. Le second protocole attend le retrait confirmé. Fenêtres fictives et sonde arrêtées normalement.

## Décisions de rendu
La transformation/opacity des fenêtres tierces via injection Dock est exclue (SIP et permissions inchangés). Les API de yabai le confirment : https://github.com/asmvik/yabai/blob/master/doc/yabai.asciidoc . Les animations de frames passent par AX asynchrone ; les panneaux Roadie utilisent leurs vraies surfaces AppKit. Les snapshots étirés sont rejetés pour l’aperçu réel. Aucun flux ScreenCaptureKit nouveau.
Les appels synchrones existants ne peuvent pas déclarer une animation achevée avant sa fin. Introduire le statut différé explicite et adapter les consommateurs, plutôt que masquer ce changement derrière un writer synchrone. Refuser les étapes anciennes par génération. Les paramètres ne déclenchent aucun retuilage à eux seuls.

## Alternatives et charge future
- Conserver AppKit et réécrire la source à chaque mouvement : rejeté, conflit observé.
- Intercepter le clic et le rejouer pour un clic simple : rejeté, trop de risques sur double clic et contrôles.
- Capturer seulement les mouvements, transmettre mouseUp sans delta natif : retenu sur preuve du prototype ; qualification sémantique obligatoire avant capture.
- Animation AX synchrone avec sleep sur MainActor : rejetée, bloquerait le clavier.
- Second pipeline de capture/animation : rejeté ; réutiliser le dispatcher et le moteur de paramètres.

## Observation de l’environnement — 11:09 CET
La préférence macOS com.apple.universalaccess reduceMotion vaut 1. Les tests de transitions injectent un environnement déterministe ou mettent respect_reduce_motion=false dans leur fichier temporaire. La préférence système reste intacte. Le runtime la respecte et termine une transition en cours à la cible si elle devient active.

Le chargeur possède déjà decodeFlexibleDouble dans Config.swift ; la lecture numérique de Motion réutilise ce helper. Les bornes d’effets sont strictes (rejet), contrairement aux anciens paramètres bornés silencieusement ; le test générique de catalogue distingue ces deux contrats.

## Propriétaire de l’animation et commandes locales
Le canal CLI est servi par run/tiler. Ces composants activent explicitement le runtime de frames. Une CLI locale sans daemon et un composant lecteur séparé gardent des écritures immédiates : ils ne peuvent pas rendre une commande différée puis quitter sans boucle d’événements. En mode modulaire, les dépôts exécutés directement par le rail restent immédiats, les commandes du writer gardent les effets. Les aperçus réels gardent leur dispatcher/suspension existants. Aucun faux glisser partagé n’est créé pour simuler un verrou d’animation entre processus.
La page Effets réutilise SettingsDisclosureSection : les sept surcharges par action sont repliées. Cela évite de créer 42 contrôles natifs avant leur usage. Le callback de capture conserve aussi la hauteur principale du clic : aucune lecture de NSScreen par mouvement.

## Arbitrage utilisateur — animations indépendantes de macOS
L’utilisateur précise que l’interrupteur Roadie doit faire seul autorité. L’hypothèse précédente de respect automatique de Reduce Motion est donc abandonnée. Suppression du champ, du contrôle UI et des lectures NSWorkspace pour cette politique. Le réglage système reste inchangé. Mise à jour spec/plan/contrat/tests/guide. Les anciennes observations restent historiques, pas la décision courante.

Qualification native du 31 octobre : pendant un glisser possédé entre écrans à Spaces séparés, le cadre AX rejoint la cible, mais WindowServer masque le contenu jusqu’au relâchement. La vraie source reste donc sur son écran initial lorsque le pointeur vise un autre écran ; le contour de destination est affiché et le dépôt reste fonctionnel. Aucun transfert de Space non réversible ni injection n’est ajouté. Limite explicite de l’aperçu réel : même écran.

Recherche Wayland de la conversation conservée : docs/analyses/2026-10-31-effets-wayland/analyse.md et aperçu HTML d’intention. Sa proposition initiale de suivre Réduire les animations est historique et remplacée par la décision explicite d’indépendance.
