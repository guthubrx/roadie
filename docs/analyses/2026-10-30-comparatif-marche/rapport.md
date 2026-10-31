# Roadie face aux gestionnaires de fenêtres et lanceurs

**Comparaison du 30 octobre 2026. Roadie 0.13.0, base b223718ff9bedc101035cfd5fb0edc0d8704763f.**

47 références documentées. Tour large, sans exhaustivité revendiquée ni classement de parts de marché.

Roadie a déjà une couverture fonctionnelle étendue. Les écarts utiles portent sur les conversions, les dialogues de fichiers, le repli OCR, les modèles visuels, les modes de disposition et les intégrations prêtes à l’emploi. OmniWM démontre que l’association gestionnaire et palette de commandes existe aussi ailleurs.

Ce document confronte les fonctions documentées des concurrents à des lectures ciblées du code Roadie. Aucun concurrent n’a été installé ou mesuré. Les priorités sont des propositions.

## Pistes classées

### 1. Convertir unités, durées, dates et fuseaux dans la barre

**Absence confirmée du moteur natif. Effort relatif : Moyen.**

La calculatrice traite les nombres et les fonctions. Elle ne comprend pas les unités ni les dates. Un workflow peut compléter cela, sans offrir le même parcours direct.

Taper « 90 min en heures », « 12 pouces en cm » ou « 17h Paris à Tokyo ».

Proposition : Commencer par unités, durées et dates locales. Ajouter les devises ensuite avec date du taux et indication de la source.

Limite : Ne pas confondre cette grammaire déterministe avec une fonction d’IA. Les devises demandent des données externes.

Validation attendue : Expressions FR/EN, virgule décimale, heure d’été, calcul partiel et résultat copiable vérifiés.

Sources : [Documentation](https://manual.raycast.com/calculator), [Documentation](https://www.monarchlauncher.com/).

Preuves Roadie :

- /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/025-settings-readability/Sources/RoadieDaemon/LauncherCalculator.swift

### 2. Choisir un dossier depuis Ouvrir ou Enregistrer

**Parcours dédié non repéré ; faisabilité à éprouver. Effort relatif : Élevé.**

Roadie ouvre déjà des fichiers et des dossiers. Il ne propose pas un parcours documenté qui change le dossier du dialogue de l’application active.

Dans « Enregistrer sous », chercher « budget Maya » ; le dialogue se place dans ce dossier sans ouvrir le Finder.

Proposition : Ajouter le verbe « Utiliser dans ce dialogue ». Proposer aussi les dossiers du projet de la stage.

Limite : Listary démontre l’idée sur Windows. Sur macOS, il faut distinguer dialogues standard et dialogues propres aux applications.

Validation attendue : Parcours sur TextEdit, navigateur et Office ; nom du fichier conservé ; abandon sans effet ; refus expliqué si dialogue incompatible.

Sources : [Documentation](https://www.listary.com/feature/quick-save-and-open).

Preuves Roadie :

- /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/025-settings-readability/docs/fr/launcher.md
- /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/025-settings-readability/Sources/RoadieDaemon/LauncherFiles.swift

### 3. Trouver aussi le texte visible mais inaccessible aux API

**Repli OCR non repéré dans les sources consultées. Effort relatif : Élevé.**

La recherche à l’écran de Roadie lit l’arbre Accessibilité. Elle peut manquer un texte dessiné dans une image ou une interface qui ne publie pas ses éléments.

Capslock + F retrouve un mot dans une capture ou une interface distante ; une étiquette permet de cliquer à sa place.

Proposition : Garder la lecture Accessibilité en premier. Proposer une reconnaissance locale des caractères (OCR) en repli explicite lorsque rien n’est trouvé.

Limite : Un mot reconnu n’est pas forcément un bouton. Petits caractères, contenu qui bouge et permissions de capture demandent une validation ; aucune capture envoyée à un service par défaut.

Validation attendue : Comparer texte natif, image, PDF scanné et interface distante ; vérifier clic, coordonnées Retina, plusieurs écrans et refus de capture.

Sources : [Documentation](https://superkey.app/), [Documentation](https://manual.raycast.com/screenshots).

Preuves Roadie :

- /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/025-settings-readability/docs/fr/launcher.md
- /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/025-settings-readability/Sources/RoadieDaemon/AppTargetQueryService.swift

### 4. Créer des modèles de placement avec une palette visuelle

**Fonctions de base présentes ; éditeur visuel non repéré. Effort relatif : Élevé.**

Arbre BSP, projets, aperçu et glisser existent. Ce qui manque est un modèle de zones lisible, réutilisable avec d’autres fenêtres et facile à appliquer.

Choisir « 50 % éditeur, 25 % navigateur, 25 % terminal », puis déposer les fenêtres dans le dessin.

Proposition : Une palette de modèles par écran et par stage. En tuilage, modifier l’arbre ; en flottant, appliquer des cadres.

Limite : Les « zones » de placement sont distinctes des zones de clics récentes. Le tiler ne doit pas annuler le placement juste après le geste.

Validation attendue : Aperçu fidèle, Échap restaure, ratios conservés, tailles minimales respectées et résultat stable après plusieurs passes du tiler.

Sources : [Documentation](https://learn.microsoft.com/en-us/windows/powertoys/fancyzones), [Documentation](https://manytricks.com/moom/help/whatsnew.html), [Documentation](https://rectangleapp.com/pro/).

Preuves Roadie :

- /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/025-settings-readability/Sources/RoadieCore/WindowManagementMode.swift
- /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/025-settings-readability/Sources/RoadieDaemon/StageProjects.swift

### 5. Essayer un mode à colonnes défilantes

**Absence confirmée des moteurs. Effort relatif : Très élevé.**

Roadie répartit les fenêtres dans l’espace disponible. Il ne possède pas de ruban dont on déplace la vue pour garder des fenêtres larges.

Ouvrir six fenêtres : chacune garde sa largeur. Passer à la suivante fait glisser la vue au lieu de réduire toutes les autres.

Proposition : Un prototype sur une seule stage, avec largeur par colonne, centrage et navigation clavier. Étendre aux gestes et à plusieurs écrans après validation.

Limite : Les API macOS, le masquage, le plein écran et les bords de moniteurs rendent ce chantier sensible. Le code Wayland n’est pas portable tel quel.

Validation attendue : Largeur stable à l’ajout et au retrait, aucune fuite sur l’écran voisin, rappel et vue d’ensemble cohérents, Échap et redémarrage vérifiés.

Sources : [Documentation](https://github.com/karinushka/paneru), [Documentation](https://acsandmann.github.io/rift-docs/), [Documentation](https://github.com/niri-wm/niri).

Preuves Roadie :

- /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/025-settings-readability/Sources/RoadieCore/WindowManagementMode.swift

### 6. Rendre les extensions faciles à trouver et à entretenir

**Compatibilité et commandes présentes ; expérience à compléter. Effort relatif : Élevé.**

Roadie charge les workflows Alfred. Le chiffre 92/102 vient d’un corpus et d’une classification structurelle ; ce n’est pas une garantie sur tous les workflows ni tous leurs services.

Trouver un workflow, voir ses dépendances et sa compatibilité, le configurer, puis tester une vraie action depuis Roadie.

Proposition : Un petit catalogue vérifié, une page par workflow et un diagnostic utile. Séparer la compatibilité détectée de l’exécution réellement testée.

Limite : Ne pas promettre l’exécution des extensions Raycast : leur API React/Node/TypeScript constitue une autre plateforme. L’éditeur visuel de workflows reste écarté.

Validation attendue : Installation et retrait réversibles ; dépendance manquante nommée ; origine et version visibles ; un parcours réel validé par entrée du catalogue.

Sources : [Documentation](https://manual.raycast.com/extensions), [Documentation](https://developers.raycast.com/), [Documentation](https://github.com/Flow-Launcher/Flow.Launcher).

Preuves Roadie :

- /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/025-settings-readability/Sources/RoadieDaemon/AlfredCompatibility.swift
- /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/025-settings-readability/docs/fr/launcher.md

### 7. Rappeler des modèles selon les écrans et l’activité

**Déjà partiel : projets et parking des écrans. Effort relatif : Moyen à élevé.**

Roadie conserve déjà stages et projets au changement d’écran. L’étape utile est un choix explicite entre Bureau, Portable ou Présentation, appliqué à l’activité.

Rebrancher l’écran du bureau et proposer le modèle « Travail », sans écraser une disposition que l’on vient de modifier.

Proposition : Étendre les projets existants avec des modèles génériques et des conditions simples, plutôt que recréer la restauration.

Limite : Une application peut ne pas exposer son document ou refuser sa taille. Montrer un bilan de restauration et les écarts.

Validation attendue : Fenêtres absentes ou lentes signalées, retour arrière, priorité aux déplacements récents, aucun doublon à la reconnexion.

Sources : [Documentation](https://rectangleapp.com/pro/), [Documentation](https://manytricks.com/moom/help/whatsnew.html), [Documentation](https://www.hammerspoon.org/docs/hs.screen.watcher.html).

Preuves Roadie :

- /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/025-settings-readability/Sources/RoadieDaemon/StageProjects.swift

### 8. Rappeler une fenêtre en tiroir puis la ranger

**Marqueurs scratchpad présents ; parcours complet non repéré. Effort relatif : Moyen à élevé.**

Une règle sait marquer un scratchpad. Ce marqueur seul n’est pas un mécanisme documenté d’apparition/disparition avec retour au contexte précédent.

Une touche fait apparaître le terminal au-dessus de la stage ; la même touche le range et rend le clavier au document précédent.

Proposition : Un tiroir pour une fenêtre existante ou lancée à la demande, sans changer son appartenance par accident.

Limite : Les fenêtres épinglées et le rappel existent déjà. Le gain porte sur le cycle complet, la position et la restauration du clavier.

Validation attendue : Pas de fenêtre dupliquée ; clavier restauré ; règles flottantes conservées ; fermeture et écran retiré traités.

Sources : [Documentation](https://github.com/OmniNull/OmniWM), [Documentation](https://github.com/MrKai77/Loop).

Preuves Roadie :

- /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/025-settings-readability/Sources/RoadieDaemon/WindowRuleEngine.swift
- /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/025-settings-readability/docs/fr/launcher.md

### 9. Ajouter un accordéon et vérifier les onglets natifs

**Accordéon absent ; onglets natifs à vérifier. Effort relatif : Élevé.**

Roadie possède déjà des groupes tabbed/stack. Un accordéon qui laisse dépasser les titres et la gestion des vrais onglets macOS sont deux sujets distincts.

Dans un groupe, une fenêtre reste grande ; les titres des autres restent visibles. Tester aussi plusieurs onglets natifs de Terminal.

Proposition : Valider d’abord si les groupes existants couvrent le besoin. Ajouter seulement la présentation ou le suivi des onglets manquants.

Limite : Ne pas annoncer « groupes absents ». La capacité des concurrents à gérer les onglets ne démontre pas une panne chez Roadie.

Validation attendue : Ordre, sélection, fermeture d’un onglet et changement de groupe sans fenêtre fantôme.

Sources : [Documentation](https://nikitabobko.github.io/AeroSpace/guide), [Documentation](https://acsandmann.github.io/rift-docs/).

Preuves Roadie :

- /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/025-settings-readability/Sources/RoadieDaemon/WindowGroupCommands.swift
- /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/025-settings-readability/Sources/RoadieCore/WindowManagementMode.swift

### 10. Proposer quelques gestes cohérents et un menu radial

**Intégration BTT existante ; parcours à simplifier. Effort relatif : Moyen avec BTT ; élevé en natif.**

Roadie sait déjà recevoir des commandes de BTT. Le manque est un ensemble court de gestes faciles à installer et à comprendre.

Une touche et un mouvement vers la gauche placent la fenêtre ; un geste déplace la stage sur l’autre écran.

Proposition : Commencer par un profil BTT réversible et un aperçu de l’effet. Étudier ensuite un menu radial Roadie.

Limite : Éviter deux moteurs qui déplacent la même fenêtre et les conflits avec Mission Control. Aucun changement de raccourcis sans choix utilisateur.

Validation attendue : Parcours physique clavier/trackpad, annulation, conflit signalé et restauration du profil précédent.

Sources : [Documentation](https://highlyopinionated.co/swish/), [Documentation](https://github.com/MrKai77/Loop), [Documentation](https://folivora.ai/features/window-management/).

Preuves Roadie :

- /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/025-settings-readability/docs/fr/window-switcher.md

### 11. Exporter une configuration portable et restaurable

**Fichiers locaux présents ; parcours global à vérifier. Effort relatif : Moyen.**

Copier le TOML ne suffit pas nécessairement pour retrouver projets, thèmes, workflows et raccourcis sur un autre Mac.

Exporter ses choix ; importer sur un autre Mac avec un aperçu des changements et des réglages propres à la machine.

Proposition : Un export global guidé, avec choix des catégories, aperçu des conflits et séparation des identités d’écran et des chemins locaux.

Limite : Ne pas synchroniser aveuglément les identifiants de fenêtres, les secrets ou les raccourcis BTT. Une sauvegarde guidée peut suffire avant le cloud.

Validation attendue : Aller-retour sur un dossier de test, import partiel, ancienne version et retour arrière.

Sources : [Documentation](https://manual.raycast.com/import-export), [Documentation](https://www.alfredapp.com/help/advanced/sync/).

Preuves Roadie :

- /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/025-settings-readability/Sources/RoadieDaemon/StageProjects.swift
- /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/025-settings-readability/docs/fr/launcher.md

### 12. Faciliter l’installation et le premier usage public

**Écart confirmé de distribution. Effort relatif : Moyen à élevé.**

Le README décrit une version arm64, signée ad hoc et non notarisée. OmniWM annonce déjà une distribution Developer ID et notarisée.

Télécharger, accorder les permissions utiles et réussir trois actions sans commande de terminal.

Proposition : Signature de distribution, notarisation et parcours de prise en main. Tester les autorisations, les mises à jour et la restauration de configuration.

Limite : La notarisation ne prouve pas la qualité du tuilage. Certificat et compte de distribution restent des prérequis distincts.

Validation attendue : Installation sur un profil macOS neuf, permissions refusées puis accordées, configuration conservée après mise à jour.

Sources : [Documentation](https://github.com/OmniNull/OmniWM), [Documentation](https://highlyopinionated.co/swish/).

Preuves Roadie :

- /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/025-settings-readability/README.md

## Références comparées

| Outil | Plateforme et sources | Fonction utile | Analyse pour Roadie |
|---|---|---|---|
| [OmniWM](https://github.com/OmniNull/OmniWM) | macOS. Code public · GPL-2.0-only. | Colonnes défilantes, BSP, palette unifiée, terminal tiroir et distribution signée/notarisée. | Concurrent direct : l’association gestionnaire + palette existe ailleurs. Roadie ne propose pas ces colonnes ; son paquet public est signé ad hoc. |
| [Rift](https://acsandmann.github.io/rift-docs/) | macOS. Code public · Apache-2.0. | Plusieurs moteurs, dont colonnes défilantes et pile, gestes et onglets natifs macOS. | Choix de dispositions plus large. Compatibilité des onglets natifs de Roadie à comparer en situation réelle. |
| [Paneru](https://github.com/karinushka/paneru) | macOS. Code public · MIT annoncée dans le dépôt. | Ruban horizontal par écran ; une nouvelle fenêtre conserve la taille des voisines. | Vrai mode de travail absent du catalogue des moteurs de Roadie. |
| [PaperWM.spoon](https://github.com/mogenson/PaperWM.spoon) | macOS. Code public · licence à vérifier par fichier. | Défilement horizontal dans Hammerspoon, colonnes empilées et gestes. | Référence macOS utile pour éprouver le défilement et ses contraintes. |
| [AeroSpace](https://nikitabobko.github.io/AeroSpace/guide) | macOS. Code public · MIT. | Arbre de conteneurs, accordéon, modes de raccourcis et événements. | Accordéon absent des moteurs Roadie. CLI, événements et bureaux existent déjà chez nous. |
| [yabai](https://github.com/asmvik/yabai) | macOS. Code public · MIT. | Tuilage BSP, commandes, règles et intégration aux Spaces natifs. | Référence de comportement des Spaces. Roadie a déjà BSP, règles et commandes ; pas de supériorité de fiabilité démontrée. |
| [Amethyst](https://ianyh.com/amethyst/) | macOS. Code public · licence à vérifier par fichier. | Nombreuses dispositions et moteurs personnalisés en JavaScript, en bêta. | Plus de choix de dispositions sans modifier le moteur principal. |
| [Rectangle](https://rectangleapp.com/) | macOS. Code public · MIT. | Placement par bords et coins ; répétition des raccourcis pour changer de taille. | Une commande qui fait défiler des proportions serait plus simple à découvrir. Valeur à tester face aux commandes Roadie. |
| [Rectangle Pro](https://rectangleapp.com/pro/) | macOS. Propriétaire. | Cibles personnalisées, panneau de placement, dispositions déclenchées par les écrans. | Modèles visuels réutilisables et rappel par contexte matériel à approfondir. |
| [Moom](https://manytricks.com/moom/help/whatsnew.html) | macOS. Propriétaire. | Palette, zones de dépôt et modèles qui peuvent viser des fenêtres indépendamment de leur application. | Roadie garde déjà des projets. L’apport est le modèle générique, éditable et facile à appliquer. |
| [Magnet](https://magnet.crowdcafe.com/) | macOS. Propriétaire. | Placement simple en moitiés, quarts et tiers depuis les bords. | Référence de simplicité. Aucun manque de moteur automatique établi par rapport à ce produit. |
| [Loop](https://github.com/MrKai77/Loop) | macOS. Code public · GPL-3.0. | Menu radial, aperçu avant placement, cycles et fenêtres rangées au bord. | Le menu radial apporte un geste court. L’aperçu seul existe déjà dans Roadie. |
| [Swish](https://highlyopinionated.co/swish/) | macOS. Propriétaire. | Gestes sur les barres de titre pour placer, fermer et changer d’écran. | Lacune de parcours gestuel prêt à l’emploi. BTT sait déjà déclencher Roadie. |
| [Divvy](https://mizage.com/divvy/) | macOS / Windows. Propriétaire · compatibilité récente non essayée. | Dessin du rectangle de placement sur une grille. | Une grille pour placer une fenêtre serait distincte de la grille Roadie qui sert à cliquer. |
| [Mosaic](https://www.lightpillar.com/mosaic.html) | macOS. Propriétaire. | Dispositions visuelles et groupes de modèles de placement. | Création visuelle de modèles, plutôt que nouvelle fonction de regroupement des fenêtres. |
| [AltTab](https://github.com/lwouis/alt-tab-macos) | macOS. Code public · vérifier la version et la licence ciblées. | Sélecteur de fenêtres avec aperçus, fenêtres cachées ou réduites. | Recouvrement important : Roadie a déjà profils, recherche, styles et Maj seule. Tester les cas difficiles plutôt que recopier les cartes. |
| [Glide](https://github.com/tmandry/glide) | macOS. Code public · MIT / Apache-2.0 annoncées. | Gestionnaire de fenêtres natif, source utile pour l’architecture macOS. | Référence technique complémentaire ; aucun avantage fonctionnel nouveau retenu ici. |
| [GlazeWM](https://github.com/glzr-io/glazewm) | Windows / macOS. Code public · GPL-3.0 annoncée. | Gestionnaire inspiré d’i3, avec configuration et commandes. | À comparer pour la cohérence clavier. Roadie a déjà navigation, bureaux et automatisation. |
| [komorebi](https://github.com/LGUG2Z/komorebi) | Windows. Code visible · licence Komorebi spécifique. | Tuilage, bureaux, écrans et pilotage externe. | Source d’idées pour la configuration et les dispositions ; code visible ne signifie pas licence libre. |
| [komorebi for Mac](https://github.com/LGUG2Z/komorebi-for-mac) | macOS. Code visible · licence Komorebi spécifique. | Port macOS avec CLI ; versions publiques et développement privé sponsorisé. | À suivre dans la concurrence directe ; pas de gain précis non vérifié attribué à ce port. |
| [FancyZones](https://learn.microsoft.com/en-us/windows/powertoys/fancyzones) | Windows. PowerToys · code public. | Éditeur de zones, modèles et affectation d’une fenêtre à plusieurs zones. | Zones de placement visuelles et modèles par écran. Ne pas confondre avec les zones de clics Roadie. |
| [niri](https://github.com/niri-wm/niri) | Linux. Code public · GPL-3.0. | Colonnes sur un ruban défilant ; taille des fenêtres conservée à l’ajout. | Inspiration de modèle d’interaction. Son compositeur Wayland ne se transplante pas sur macOS. |
| [PaperWM](https://github.com/paperwm/PaperWM) | Linux. Code public · licence à vérifier par fichier. | Extension GNOME de tuilage défilant, espaces par écran et navigation continue. | Même piste que niri ; Roadie possède déjà la vue d’ensemble et les bureaux par écran. |
| [i3](https://i3wm.org/docs/userguide.html) | Linux. Code public. | Conteneurs imbriqués, disposition en onglets ou en pile et navigation modale. | Étudier l’édition de l’arbre et sa lisibilité. Roadie possède déjà des groupes tabbed/stack. |
| [Sway](https://swaywm.org/) | Linux. Code public. | Modèle i3 sur Wayland et outils de composition. | Référence clavier ; les fonctions du compositeur ne sont pas des fonctions macOS à porter directement. |
| [Hyprland](https://hypr.land/) | Linux. Code public · détail des modules non audité. | Compositeur Wayland orienté personnalisation et interaction. | Animations et personnalisation à évaluer par usage. Aucun classement de fluidité réalisé. |
| [macOS : tuilage natif](https://support.apple.com/guide/mac-help/tile-app-windows-mchlef287e5d/mac) | macOS. Inclus dans macOS. | Placement de fenêtres intégré au système. | Référence d’installation sans friction et de gestes connus. Roadie offre déjà une organisation plus structurée. |
| [Raycast](https://manual.raycast.com/quickstart) | macOS / Windows. Application propriétaire ; extensions publiques distinctes. | Extensions, calcul de dates et d’unités, presse-papiers, extraits, IA et réglages. | Écart utile : calcul enrichi et intégrations installables. Presse-papiers, extraits et IA restent des choix écartés. |
| [Alfred](https://www.alfredapp.com/help/features/) | macOS. Propriétaire. | Recherche, workflows, actions universelles, extraits et presse-papiers. | Le fonctionnement de base est largement repris. Restent la compatibilité complète et des fonctions volontairement écartées. |
| [LaunchBar](https://www.obdev.at/products/launchbar/features.html) | macOS. Propriétaire. | Envoi de la sélection vers des actions, Services macOS, opérations de fichiers et ClipMerge. | L’envoi de texte et les verbes existent dans Roadie. Étendre aux Services et rendre le parcours plus direct est une piste. |
| [Quicksilver](https://qsapp.com/) | macOS. Code public · licence à vérifier par composant. | Modèle objet/action/destination, catalogue et modules. | Le modèle objet/verbe/destination existe déjà. Le catalogue de modules est la différence à travailler. |
| [Monarch](https://www.monarchlauncher.com/) | macOS. Propriétaire. | Calcul d’unités, dates et devises, notes locales et presse-papiers. | Le calcul enrichi manque. Les notes sont une fonction de confort ; le presse-papiers reste écarté. |
| [PowerToys Command Palette](https://learn.microsoft.com/en-us/windows/powertoys/command-palette/overview) | Windows. PowerToys · code public. | Palette extensible et commandes système dans une interface commune. | Gestion de fournisseurs de résultats et catalogue. Les commandes système existent déjà dans Roadie. |
| [PowerToys Run](https://learn.microsoft.com/en-us/windows/powertoys/run) | Windows. PowerToys · code public. | Recherche et commandes par modules. | Référence complémentaire à Command Palette ; pas une fonction nouvelle de lancement chez Roadie. |
| [Flow Launcher](https://github.com/Flow-Launcher/Flow.Launcher) | Windows. Code public · MIT annoncée. | Recherche de fichiers et applications, modules communautaires. | Écosystème de modules et gestion des sources. Les promesses de rapidité ne sont pas un benchmark comparatif. |
| [Listary](https://www.listary.com/feature/quick-save-and-open) | Windows. Propriétaire. | Recherche d’un dossier depuis les dialogues Ouvrir/Enregistrer. | Piste forte : envoyer un dossier trouvé vers le dialogue courant au lieu d’ouvrir une autre fenêtre. |
| [Wox](https://github.com/Wox-launcher/Wox) | macOS / Windows / Linux. Code public · GPL-3.0 annoncée. | Lanceur multiplateforme avec modules Node.js, Python ou scripts. | API et catalogue de modules. Aucun besoin établi de porter Roadie sur d’autres OS. |
| [ueli](https://github.com/oliverschwendener/ueli) | Multiplateforme. Code public · licence à vérifier par fichier. | Lanceur piloté au clavier et extensions. | Référence d’intégration de fournisseurs ; avantage précis de performance non évalué. |
| [Albert](https://albertlauncher.github.io/) | macOS / Linux. Code public · licence à vérifier par fichier. | Architecture par modules, API C++ et Python, collection maintenue. | Concevoir un contrat simple pour étendre la recherche et les actions. |
| [Ulauncher](https://github.com/Ulauncher/Ulauncher) | Linux. Code public. | Lanceur extensible. | Installation des modules et configuration guidée ; recherche approximative déjà présente dans Roadie. |
| [rofi](https://github.com/davatorium/rofi) | Linux. Code public. | Sélecteur de fenêtres, lanceur et remplacement de dmenu. | Palette réutilisable depuis un script. Roadie a déjà commandes et Script Filters ; étudier une interface universelle plus simple. |
| [KRunner](https://github.com/KDE/krunner) | Linux. Code public. | Cadre de fournisseurs d’actions à partir d’une requête texte. | Modèle de fournisseurs indépendants. Le détail des modules Plasma n’a pas été audité ici. |
| [Hammerspoon](https://www.hammerspoon.org/) | macOS. Code public. | API Lua vers macOS, événements matériels et Spoons. | Roadie a déjà événements, règles et macros. L’écart est la surface d’extension et les exemples réutilisables. |
| [BetterTouchTool](https://folivora.ai/features/window-management/) | macOS. Propriétaire. | Gestes, déplacement, zones personnalisées et commandes. | Mieux exploiter l’intégration existante plutôt que reconstruire tous les déclencheurs. |
| [Keyboard Maestro](https://www.keyboardmaestro.com/main/) | macOS. Propriétaire. | Automatisation par déclencheurs, conditions, boucles et actions. | Roadie possède des macros mais pas cet atelier complet. Son éditeur de workflows a été écarté auparavant. |
| [Superkey](https://superkey.app/) | macOS. Propriétaire · outil voisin. | Recherche du texte visible par reconnaissance de caractères (OCR), avec lecture Accessibilité en option. | Roadie possède déjà la recherche à l’écran ; un repli OCR pourrait couvrir les textes non exposés par l’application. |
| [Homerow](https://www.homerow.app/) | macOS. Propriétaire · outil voisin. | Étiquettes clavier pour atteindre boutons, liens et éléments d’interface. | Recouvrement avec les cibles clavier Roadie. À comparer pour les parcours et les applications difficiles. |

## Choix précédents conservés

- **Presse-papiers et fusion de copies** (Alfred, Raycast, LaunchBar, Monarch). Écart réel, écarté auparavant. À réexaminer seulement si le besoin change.
- **Extraits et expansion de texte** (Alfred, Raycast). Écart volontaire confirmé dans la session 131.
- **Contacts et actions associées** (Alfred, LaunchBar). Écart volontaire confirmé dans la session 131.
- **IA et transformation de texte** (Raycast et annonces Alfred 6). Choix utilisateur conservé. Ne pas présenter une annonce comme une fonction déjà publiée.
- **Éditeur visuel complet de workflows** (Alfred, Keyboard Maestro). Hors périmètre conservé. Un catalogue/configurateur est une autre proposition.

Source de ces choix : /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/025-settings-readability/specs/131-actions-alfred/spec.md

## Limites et interprétation

Une fonction décrite sur une branche principale peut précéder sa publication. Un catalogue de modules ne garantit pas la qualité de chacun. Le diagnostic « complet » des workflows Alfred est fondé sur les briques et dépendances détectées ; il ne garantit pas le succès de tous les scripts et services externes. Le moteur Roadie prend déjà en charge les filtres de fichiers Alfred : cette fonction ne doit pas être présentée comme entièrement absente.

L’absence d’un parcours dédié dans les fichiers consultés est signalée comme « non repéré », distincte d’une absence confirmée dans un moteur. Pas de jugement chiffré sur la fiabilité, la vitesse, la consommation ou la popularité. Les fonctions Wayland ne se transposent pas directement aux API macOS.

Les licences mentionnées désignent les dépôts ou textes consultés. La réutilisation d’un composant doit être examinée au niveau de la version et du fichier retenus. Aucun code concurrent n’a été intégré.

## Livrables

/Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/025-settings-readability/docs/analyses/2026-10-30-comparatif-marche/rapport.html

/Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/025-settings-readability/docs/analyses/2026-10-30-comparatif-marche/rapport.md

/Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/025-settings-readability/docs/analyses/2026-10-30-comparatif-marche/comparaison.json

## Lecture ciblée des sources concurrentes

Quatre points d’entrée figés. Pas d’audit complet ni de code intégré.

- [Paneru](https://github.com/karinushka/paneru/blob/425d37aef53503b05b65c784cb00ba59825ae70b/src/ecs/layout.rs), commit 425d37aef53503b05b65c784cb00ba59825ae70b. Colonnes, ruban et contraintes de placement. Le code décrit le maintien d’une mince partie de la fenêtre sur son écran pour éviter sa réaffectation par macOS.
- [Rift](https://github.com/acsandmann/rift/blob/572b9425ebe3d09196e5db2601ff8bc539ee407c/src/layout_engine/systems/scrolling.rs), commit 572b9425ebe3d09196e5db2601ff8bc539ee407c. Les colonnes ont une identité et une largeur ; le déplacement de la vue est représenté séparément.
- [Rectangle](https://github.com/rxhanson/Rectangle/blob/39466aea1a6c942eb3bbdd4a7b5d6da8662106f5/Rectangle/WindowCalculation/RepeatedExecutionsCalculation.swift), commit 39466aea1a6c942eb3bbdd4a7b5d6da8662106f5. Le calcul parcourt des proportions lorsque la même action se répète.
- [AeroSpace](https://github.com/nikitabobko/AeroSpace/blob/8e7899629c396e2a735c7b5d9950565af239c706/Sources/AppBundle/layout/layoutRecursive.swift), commit 8e7899629c396e2a735c7b5d9950565af239c706. Le conteneur choisit tuiles ou accordéon ; la branche la plus récente intervient dans les marges de l’accordéon.
