# Validation 061 - Historique et reçu final

Début : 2026-10-24 09:11:48 CEST. Base 821a9c369e2f634a956eab5167da9c5b5da18aa2, branche session-061-vue-ensemble.

- Synchronisation SpecKit sans changement ; spécification, plan, recherche, modèle, contrat, audit de réutilisation PASS et Analyze exécutés.
- Première suite ciblée : 8 tests / 3 suites réussis. Première suite complète : 1908 tests / 238 suites réussis en 55,482 s. Scripts : 28 réussis en 17,735 s. La géométrie a ensuite été rapprochée des maquettes par regroupement des stages en colonnes ; revalidation en cours.
- Compilation initiale : nom toolbar en conflit NSWindow corrigé ; helper de normalisation exige fallback explicite ; assertions mutantes sorties des macros Swift Testing. Un build a été invalidé par édition du fichier pendant compilation : les relances suivantes ont été séquencées. Aucun résultat de ce build n’est compté.
- Revue de plan Claude : APPROVE_WITH_CHANGES, constats traités dans adversarial-review-plan.md. Revue de code 3ffe09ba-6c2c-443e-8894-a60e920a813d : mission_reply_timeout, aucun verdict disponible. Ne vaut pas une approbation.
- CUA natif indisponible : CUA_REPL_ENABLED_SURFACES is required. Capture macOS disponible ; cliclick installé, accès natif à vérifier par observation des actions.
- BTT actif, aucun geste type102 existant. Backup SQLite cohérent via connexion source mode=ro, sauvegarde dans /Users/moi/.roadies/diagnostics/2026-10-24-session061/btt-backup.sqlite. API seulement pour les mutations. Aucun geste encore ajouté.

Installation, parcours, audit, convergence, Git et nettoyage restent à compléter.

## Résultats consolidés avant installation
Suite complète après la géométrie adaptative et le registre du récepteur : 1909 tests / 238 suites réussis en 34,114 s. Le récepteur est déclaré par ComponentLockFile existant ; une CLI neuve refuse un démon ancien sans overview. Test de cycle start/stop et refus sans récepteur réussi. Images entières, présence de toutes les cartes et rectangles disjoints : matrice 11/32/64 × deux dispositions × loupe on/off × 100/150/250 % × trois tailles.

Dernier ajustement : acceptsMouseMovedEvents explicite et loupe initiale sur le bureau de la fenêtre active ; revalidation ciblée avant installation. Le survol ne journalise pas sur disque. Docs FR/EN et README rédigés. Réservation interne RDOV distincte de RDSR/RDSW.

Revalidation ciblée avant installation : 9 tests / 3 suites réussis en 0,221 s. Construction release avec ROADIE_BUILD_JOBS=2 et scripts/install en cours ; le processus utilisateur est encore celui de 060 tant que la relance n’a pas eu lieu.

## Installation et première observation
Release installée par scripts/install, certificat roadied-cert conservé, empreinte 78a75e8032f190a20072eb91cc2919aac344ef78. UUID B14760A5-D23F-3FAC-8CF3-42703492506D, PID70463 ; cinq contrôles santé OK après fin de relance. Une sonde faite pendant l’arrêt a correctement signalé récepteur absent ; elle ne représente pas l’état après démarrage.
Vue installée ouverte via CLI : 11 fenêtres observées, capture native locale. Cette observation a révélé l’inclusion des bureaux vides à cause des noms Work/Perso/Com prévus par défaut. Correction conforme au contrat : bureau occupé/nommé/actif seulement, stages vides compactes. Nouveau test de non-création de bureau à partir d’un nom de stage. Recompilation et revalidation nécessaires.

## BTT
Geste 102 créé dans Global / Francois par API officielle, UUID 7E04C058-17CD-4C36-8388-F44C49911744. Readback exact de type, classe, UUID, script brut /Users/moi/.local/bin/roadie overview toggle et wrapper /bin/bash:::-c:::-:::. Aucun geste102 préexistant. Sauvegarde conservée hors Git. Les deux déclencheurs Cmd+Tab antérieurs restent présents.
Cliclick ne possède pas l’accessibilité dans ce contexte ; aucune nouvelle autorisation demandée. L’action souris153 de BTT déplace réellement le pointeur (position relue), ce qui permet de poursuivre le parcours natif. Le signe Y du schéma récent BTT a été vérifié par la position réelle plutôt que supposé.

## Complément de qualification des entrées
Les clics BTT simples n’ont pas changé le contrôle visé lors de deux essais. Les coordonnées réelles et les captures du bandeau ont été relues avant toute nouvelle tentative. Un événement overview.input limité aux clics (type de cible et coordonnées locales, aucun texte saisi) permet de distinguer une entrée absente d’une action refusée. Le survol reste sans écriture disque. Le bureau de la loupe est indiqué dans le pied de fenêtre par mise à jour en mémoire seulement. Un test natif AppKit hors écran exerce mouseMoved, le délai, l’arrêt de la souris, la reprise après clavier et l’absence d’activation.
Le rendu gris du matériau système a été remplacé par le fond sombre du concept, limité à cette vue. Aucune apparence globale de Roadie n’est changée.

## Parcours natif final
UUID 647B8FB3-ABC8-321B-8925-A8AD80EC87F3, PID99083, certificat stable inchangé et santé5/5. Suite finale :1910 tests /238 suites,33,376s ; scripts28/28. Le test nativeMouseMovementChangesLoupeWithoutActivationOrOscillation passe en0,576s.

Le contrôle NSSegmentedControl reçoit le clic réel BTT à(222,120) : passage Baies, écriture settings.changed et reload confirmé. Les premiers essais ày104 touchaient NSView : la barre de titre native était plus haute que l’hypothèse initiale. Les coordonnées ont été corrigées après lecture des événements réels. Aucun correctif de routage des clics n’était nécessaire.
Quatre combinaisons réelles vérifiées. Menu natif de grossissement :250%, puis100%, puis150% restauré. La vue est laissée par défaut en Archipel+loupe150%.
Survol BTT réel vers Bureau4 LG HDR4K puis Bureau1 intégré : pied de fenêtre actualisé. Les JSON normalisés des bureaux/stages actifs avant/après sont identiques (une comparaison initiale tuple/liste était invalide, corrigée sans changement produit). Les captures du contenu réel restent locales ; le diaporama versionné montre les bandeaux et pieds réels, sans données des fenêtres.
Le déclencheur BTT est exécuté via execute_assigned_actions_for_trigger : aperçu ouvert vérifié dans CGWindowList. Échap ferme le panneau. Entrée produit window.switcher_focused pour la fenêtre Chrome324491 dans sa stage2, bureau1, écran intégré, puis ferme le panneau. Aucun test du balayage physique au trackpad n’est revendiqué.

## Limite des adaptateurs d’audit et remède
Semgrep examine17 fichiers, aucun candidat. Gitleaks standard a annoncé0 octet scanné car sa règle exclut .worktrees dans le chemin absolu. OSV récursif n’a trouvé aucune source à cause du chemin ignoré ; le contrôle n’est pas passé. Le scan explicite de Package.resolved trouve1 paquet sans vulnérabilité, et l’export de990 fichiers (empreintes vérifiées) permet un vrai scan de9,68Mo sans fuite. Ces compléments ne transforment pas l’adaptateur en succès. La gate finale est reprise dans un worktree temporaire hors de .worktrees, avec comparaison des empreintes des mêmes fichiers. La copie temporaire sera supprimée après intégration et vérification sur main.

## Preuves et conservation
Diaporama natif : preuves-corrections/2026-10-24-vue-ensemble061/preuves.html,9 étapes,2 clics associés aux événements AppKit et captures avant action. Premier curseur/cercle orange vu au bon endroit. Bandeaux et pieds réels uniquement ; les captures complètes contenant les fenêtres ne sont pas publiées. Originaux et manifestes sous /Users/moi/.roadies/diagnostics/2026-10-24-session061/. Les155 déclencheurs BTT initiaux sont conservés,156 après ajout ; les champs des deux Cmd+Tab sont identiques.
Après essais, Archipel+loupe150% est restauré et la vue est fermée. Tests/scripts complets sont réussis ; pas de benchmark. Revue de code distante indisponible après deux tentatives, consignée sans troisième relance. Convergence finale :CONVERGED,1 passage sur le code final.

## Convergence de complexité et correction
La relecture Article XVIII a trouvé des recherches linéaires répétées (scopes.first, stages.first, stageIDs.contains et recherches de labels dans les boucles) dans la projection initiale. Classification HIGH imposée par la constitution, chemin d’ouverture et non survol. Le code précédent est conservé dans l’audit02/repro. Correction : index bureaux/stages/libellés et Set des identités ; parcours O(w+s+b log b+t log t), sans benchmark ni gain temporel affirmé. Nouveau test de conservation de l’ordre des stages et du bureau nommé vide.
T012 ajoutée à la convergence puis exécutée. Suite finale après correction :1911 tests /238 suites en31,530s, tous réussis. La géométrie et les événements visibles sont inchangés ; les preuves natives restent applicables. Recompilation Release installée, relance et santé finales en cours. Les tests ne seront pas relancés pour les seuls reçus/documentations si les empreintes Sources/Tests sont identiques.


## Reçu final du 24 octobre, après T016/T017
Ce paragraphe remplace les états intermédiaires ci-dessus. Choix utilisateur : vue globale à la Mission Control, sans obligation de plein écran natif. Panneau sans bord couvrant NSScreen.frame, niveau25, sans nouveau Space. Logo, nom, compteurs globaux et ligne d’état retirés. Les compteurs locaux de contexte sont conservés.

Suite finale :1918 tests /238 suites, tous réussis en32,863s. Scripts :28/28, exécutés plus tôt, aucun script changé. Rendu AppKit comparatif sur les32 fenêtres fictives de la référence : deux dispositions vérifiées. Les tests couvrent aussi indexation, densité11/32/64, loupe dans la stage, absence de chevauchement et fermeture Échap.

Installation finale : UUID DFD88CB9-B19B-3164-94C7-31CF4550EBDC, PID46329, arm64, santé5/5. Certificat leaf78a75e8032f190a20072eb91cc2919aac344ef78 inchangé. Build et runtime distincts vérifiés ; logs conservés sous /Users/moi/.roadies/diagnostics/2026-10-24-session061/.
CGWindowList : vue1512×982 à(0,0), niveau25. Échap envoyé par BTT retire la vue (zéro panneau correspondant après touche). Une ouverture sur l’écran externe couvre3840×2160 à(1512,-797). Le grossissement utilisateur est passé de210 à160% pendant les essais, choix160% conservé ; aucun retour forcé au défaut150%.

Preuves : diaporama natif actualisé à six étapes, dont deux rendus AppKit sur jeu fictif clairement identifiés. Couverture souris finale incomplète : un clic annulé après mouvement concurrent du pointeur ; un autre visait le mauvais écran. Aucune annotation inventée. Fermeture depuis un menu ouvert et geste physique après retrait du conflit macOS non enregistrés. Les clics intermédiaires ne sont pas présentés comme preuve du dernier bandeau.

Revue indépendante : plan disponible et traité ; code distant indisponible (timeout, erreur de transport, puis sources non montées côté Linux). Aucun avis favorable inventé. Relecture locale et tests ne remplacent pas cette contre-revue. Aucun benchmark demandé ni gain chiffré affirmé.

Git, audit final et nettoyage : reçus de clôture conservés dans les notes de l’audit final. Les audits01/02 gardent leur historique et leurs limites ; seule la décision finale explicitement validée sert de gate.

## Retour utilisateur du 24 octobre (T018)

- Causes constatées : document de 1440 points agrandi à la largeur de l’écran (titres de 17 à environ 30 points), grille supposant des fenêtres paysage 480×300 (une colonne pour des fenêtres portrait), hauteur minimale fixe par bureau qui imposait le défilement.
- Correction : `Sources/RoadieDaemon/OverviewModel.swift` (flux à hauteur de carte uniforme, largeurs mesurées, dichotomie), `Sources/RoadieDaemon/OverviewPanel.swift` (tailles fixes, barre compacte).
- Tests : 20 tests Spec061 réussis ; suite complète 1 920 tests / 238 suites, un échec du test IPC instable connu, réussi seul.
- Rendus natifs du cas réel contrôlés en Archipel et Baies (1728×1117) : tout tient sans défilement.
- Installé : PID 94961, santé 5/5, signature roadied-cert conservée. Ouverture réelle de la vue journalisée (10 fenêtres). La capture de l’écran réel n’a pas montré la vue (ouverte sur l’autre écran) et contenait des codes d’authentification : supprimée, non conservée.

## Retour du 24 octobre, rendu jugé loin de la maquette (T019)

- Constat : la version T018 (rangement en lignes) avait abandonné la composition de /tmp/roadie-archipel-cinq-propositions.html. Retour au port fidèle de split()/grid() et des styles CSS de la maquette, sans agrandir le texte.
- Écarts voulus : format réel des fenêtres dans la grille, aperçu plafonné à 240 points, fond flou macOS sous un voile.
- Rendus natifs comparés à la maquette avec ses 11 images fictives exportées : Archipel et Baies à 32 fenêtres, cas réel à 10 fenêtres.
- Tests : 20 tests Spec061 réussis ; suite complète 1 920 tests / 238 suites, deux échecs connus instables (IPC 027, socket 022), réussis relancés seuls.
- Installé : PID 31219, santé 5/5, signature roadied-cert conservée. Rendu réel installé et flou non vérifiés visuellement par l’agent.
- Complément T019 après essai utilisateur (trop de vide, trait droit, rendu jugé sans caractère) : plafond de 240 points retiré, cartes remplissant leur case comme la maquette (au plus 1,5 fois le format de l’aperçu), trait oblique proportionnel à la hauteur, facteur d’échelle racine du rapport de largeur (1 à 1,5), halo des îles renforcé. Maquette à 11 fenêtres rendue et comparée. 20 tests 061 ; suite 1 920 tests, un échec instable connu (socket 022) réussi seul. Installé PID 78349, santé 5/5, signature conservée.
- Reprise après le retour « très loin de la maquette, trous, traits dans le texte » : comparaison directe avec /tmp/roadie-explorations.html (direction retenue, /tmp/roadie-archipel-baies-loupe.html). Les vraies données (`roadie query displays|stages|windows`, 2 écrans, 3 bureaux, 8 stages occupées, 9 fenêtres) ont été injectées dans la maquette HTML, rendue par Chrome à 1440×900, et le rendu natif équivalent a été produit par le test `nativePanelRendersRealExport` (variables ROADIE_OVERVIEW_REAL_JSON et ROADIE_OVERVIEW_REFERENCE_ASSETS). Côte à côte : même composition, mêmes titres, mêmes traits ; écarts restants voulus : fond flou sous un voile bleu nuit (0,8), cartes bornées à 2,5 fois le format réel de l’aperçu puis centrées dans leur case (la maquette étire sans limite), stages vides nommées affichées en étiquettes.
- Loupe de la maquette reprise : écran consulté 1,65 part, bureau consulté avec contour, halo, barre bleue et étiquette « Loupe » (Archipel : poids doublé + 3 ; Baies : 2,25 parts), plus la fenêtre survolée en carte principale (T014).
- Échelle : puissance 0,7 du rapport de largeur, plafond 2 (LG 3840 points → 2 ; écran intégré 1512 → 1,03). Barre de commandes à la même échelle. Écart entre écrans et pente des traits proportionnels à la hauteur, pente bornée à la marge des bureaux pour ne plus couper les titres.
- Capture réelle de l’écran LG à 3840×2160 avec la vue ouverte (10 fenêtres) contrôlée par l’agent puis supprimée : composition conforme, traits visibles hors des titres, barre à l’échelle. Aperçus en icônes juste après le redémarrage (cache des captures en cours de remplissage).
- T021 : contrôle sur l’écran LG (3840×2160) avec la vue ouverte, capture réduite puis détail à l’échelle 1 vérifiés par l’agent et supprimés : captures nettes à la taille des cartes (T3 Code, Word, Firefox), petites fenêtres réelles (Thunderbird 203×116, iTerm2 276×158 points) agrandies donc moins nettes par nature, plus de stages vides ni de compteurs, cartes alignées en haut de leur stage. 21 tests Spec061 ; suite complète 1 921 tests, deux échecs instables connus. Installé PID 54609, santé 5/5, signature roadied-cert.
- T022 : cause mesurée avant correction. CGWindowList et `roadie query windows` : fenêtres des stages masquées garées en x = 5351 sur l’écran LG ; Thunderbird 203×116 pixels réels capturé dans un tampon de 406×232 (contenu dans un quart) ; X noté 500×375 par Roadie pour 1837×2114 réels. Après correction, capture réelle de l’écran LG vue ouverte : Thunderbird et X complets, format unique, plus de cadres. 21 tests Spec061 ; suite complète 1 921 tests, seul échec le test de socket instable connu. Installé PID 93860, santé 5/5, signature roadied-cert. Captures d’écran supprimées.
- T023 : rendus natifs (données réelles et référence 32 fenêtres) puis capture réelle de l’écran LG contrôlés et supprimés : une seule taille de carte, puces de stage lisibles, stage sélectionnée en bleu, écran intégré plus étroit au profit du LG. 21 tests Spec061 ; suite complète 1 921 tests, deux tests instables connus (IPC 027, socket 022) réussis relancés seuls. Installé PID 52109, santé 5/5, signature roadied-cert.
- T024 : capture réelle de l’écran LG vue ouverte contrôlée et supprimée : fond d’écran flouté visible, icônes du bureau masquées, aucune barre, puces de bureau et de stage. Fenêtre Firefox 150 mesurée à 599×120 points (garée au bord), d’où l’affichage entier des formats extrêmes. 40 tests Spec061/SettingsCatalog ; suite complète 1 921 tests, seul échec le test de socket instable connu, réussi seul. Installé PID 79762, santé 5/5, signature roadied-cert.
- T025 : capture réelle LG contrôlée et supprimée (fond reconnaissable, tout sur une page). Test de densité : 11/32/64 fenêtres en 1000×650, 1850×980 et 3750×2000, taille du plan égale à l’écran, cartes d’au moins 20 points. 21 tests Spec061 ; suite complète 1 921 tests, seul échec le test de socket instable connu. Installé, santé 5/5, signature roadied-cert.
