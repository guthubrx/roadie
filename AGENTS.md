## Nettoyage obligatoire après livraison

Demande utilisateur du 31 octobre 2026 : ne pas clôturer par le seul commit, la fusion et le push. Après vérification du code actif et du commit distant, supprimer les branches intégrées, worktrees libérés, caches et binaires temporaires devenus inutiles dans le périmètre du travail. Vérifier leur provenance, leur intégration et leur absence d'utilisation avant suppression. Conserver le worktree d'un fil actif, les changements non intégrés, les preuves originales, les exécutables installés et le retour arrière utile ; expliquer ces exceptions dans le bilan. Toute modification publiable du périmètre doit être commitée et poussée ; ne pas ajouter les données privées, preuves brutes ou caches dans Git.

<!-- SPECKIT START -->
Session 029 implémentée le 2026-10-14 : fermeture confirmée propagée au StageStore,
grâce transitoire de 15 secondes conservée, cible p95 inférieure à 400 ms.
Tests ciblés : 117 succès. Suite complète : 1466 succès. Revue finale approuvée.
Audit v14 : A, aucun finding, validateur conforme. Build Release installé et signé.
Runtime Roadie actif sur le PID 93111. Une fermeture réelle a produit le marqueur
`confirmedClosedAt` et un rafraîchissement du rail 90 ms après la détection.
Source 94e15e7cc6d5b682329a5efb9fe697f1ed938db9 intégrée par
4b1f4171564997355c99f09bf659b405cf12c09e et poussée sur origin/main.
Artefacts : specs/029-navrail-fermeture/. Reçu :
specs/029-navrail-fermeture/validation/livraison029.md.
Session 030 implémentée et installée : récupération des fenêtres sur écran absent au démarrage.
1471 tests isolés et 1527 tests combinés réussis. Redémarrage vérifié, quatre contrôles santé OK.
Session 031 implémentée et installée : numéro et nom temporaires ; Alt gauche grille, Alt droite libellés.
1 540 tests combinés réussis, captures avant/après et expiration vérifiées, santé OK.
Les repères des stages vides suivent aussi la visibilité temporaire des noms.
Session 032 implémentée et installée : avant des vignettes aligné, hauteur des emplacements réglable,
repère de dépôt et géométrie stable pendant le glisser. Hauteur installée 120 points, gap 13 conservé.
1477 tests isolés et 1544 tests combinés réussis. Deux rails vérifiés, dix scopes conservés.
Session 033 implémentée et installée : légendes compactes sous les aperçus, perspective optionnelle.
14 points, écart 4, emplacement 112 points ; visibilité temporaire et raccourcis conservés.
Dépôt Outlook corrigé : deux gestes complets et six cycles de maintien rejoués en test isolé.
Échec sans correctif, succès avec correctif. 1550 tests combinés réussis en mode séquentiel.
Sources de production installées inchangées, UUID vérifié. PID 34131, quatre contrôles santé OK.
Session 034 implémentée et installée : une fenêtre encore illisible sur un autre écran
ne fait plus réduire les voisines. Reprise automatique dès lecture AX valide, budget conservé.
1484 tests isolés et 1551 tests combinés réussis. Contrôle réel avec disponibilité retardée
3 secondes : voisines stables, placement sans échec, cadres restaurés après fermeture.
UUID 2B510D42-C812-384F-952E-59E17AA95A6C, PID 15020, quatre contrôles santé OK.
Session 036 implémentée et installée : présence CG ID/PID distincte du placement,
conservation des groupes et du rail pendant le plein écran natif. 1490 tests isolés et
1557 combinés réussis. Reproduction réelle avant/après à 22 s ; huit affectations conservées.
Outlook récupéré dans une stage séparée après perte antérieure à l’installation.
PID 53642, signature stable, quatre contrôles santé OK ; diaporama de preuves vérifié.
Session 037 implémentée et installée : inventaire transmis au tiler, attente AX sur
le même écran, observations par lot, feuilles XPC exclues et glisser partagé verrouillé.
Sept mécanismes corrigés de 035 intégrés. 1587 tests dans 183 suites réussis ;
278 empreintes Sources/Tests inchangées. UUID 795C9759-EE86-3D9C-B720-0BCB7430213F.
PID 62842, signature stable, quatre contrôles santé OK. Dépôts natifs et plein écran
35 s vérifiés sur l'écran interne. Stage 4 restaurée, tests temporaires retirés.
Limites et preuves : specs/037-fiabilite-placement/validation/livraison037.md.
Session 038 implémentée et installée : champ de saisie AppKit, édition macOS,
sélection des suggestions par Haut/Bas et clic, validation du choix par Retour.
127 tests ciblés et 1597 tests / 185 suites réussis. Parcours natifs vérifiés.
PID 96284, signature stable, quatre contrôles santé OK ; T3 conservé.
Preuves et limites : specs/038-saisie-native/validation/livraison038.md.
Session 040 implémentée et installée : watcher du statut d'enregistrement filtré,
rappel poursuivi sur les autres membres, fenêtres réduites restaurées avant focus,
arrêt AX après délai dépassé et échecs de masquage détaillés.
1 612 tests / 188 suites et 26 tests de scripts réussis. Revue traitée.
UUID EAC639A1-B54B-339F-98AD-950C4D5F0F3E, PID 46802, quatre contrôles santé OK.
Preuves visuelles indisponibles ; limites : specs/040-reactivite-rappel/validation/validation.md.
Session 041 implémentée et installée : aperçu translucide du réordonnancement à la
future place des cartes, trait bleu retiré, destinations fixes et aimantation réglable
0–100 % dans Paramètres > Rail (défaut 50). 1 616 tests / 189 suites réussis,
puis 22 tests ciblés après revue ; deux revues traitées. UUID
3533388F-83B1-3F5A-995C-B525D7656291, PID 83654, quatre contrôles santé OK.
Preuves visuelles incomplètes : bureau inaccessible. Validation :
specs/041-apercu-reordonnancement/validation/validation.md.
Session 042 implémentée et installée : acquisitions des lecteurs hors fil principal,
cache du rail par écran, lectures AX de secours mutualisées, mutations BSP linéaires,
textes de recherche préparés et copies de réordonnancement réutilisées.
Générations des caches AX vérifiées après revue. 1 628 tests / 192 suites réussis,
sans benchmark. UUID 7C7282EB-E1CB-3F6A-8AE6-0974BEA2DAF5, PID 8095,
signature conservée et quatre contrôles santé OK. Deuxième passage de revue
indisponible (transport Bridget) ; limites dans specs/042-couts-traitement/validation/validation.md.
Session 043 implémentée et installée : poignées des séparations spatialBsp réglables
dans Tuilage, historique AX borné et priorité des gestes récents face aux refus de taille.
1 685 tests / 199 suites et 26 tests de scripts réussis ; deuxième revue T3 favorable.
UUID C17A941A-2EAE-3084-BA67-E379185E9EA9, PID 89776, quatre contrôles santé OK.
Signature et configuration conservées. Preuves incomplètes : bureau inaccessible ;
gestes natifs à vérifier. Détail : specs/043-redimensionnement-fiable/validation/validation.md.
Trois sous-agents T3 avec fichiers exclusifs ; intégration et validation par le parent.
Session 044 implémentée et installée : fenêtres décoratives JankyBorders exclues du
masquage des poignées ; repère contrasté 4 × 32 points, réglage existant conservé.
1 689 tests / 199 suites réussis, comparaison logicielle à deux/quatre fenêtres et
revue indépendante favorable bornée. Aucun gain de latence réelle revendiqué.
UUID DEA0CA0C-6175-35D6-8A08-68473D919EC1, PID 54197, quatre contrôles santé OK.
macOS confirme un panneau de poignée pour les deux fenêtres de l'écran externe.
Signature/configuration conservées. Geste réel et capture non vérifiés : bureau
inaccessible. Reçu : specs/044-poignees-visibles/validation/validation.md.
Session 045 implémentée et installée : capture des bords conservée malgré la zone géométrique
des poignées et les décorations ; seule une poignée acceptée reprend le geste.
1 693 tests / 199 suites réussis ; revue traitée et enchaînement natif/poignée vérifié.
UUID 60B2AD40-0F27-3EB6-BA6D-08570FEF5290, PID 65772, quatre contrôles santé OK.
Configuration et certificat conservés. Parcours réel assisté : gestes reconnus et taille
conservée, confirmation utilisateur. Preuves visuelles incomplètes : bureau inaccessible.
Reçu : specs/045-capture-redimensionnement/validation.md.
Session 046 implémentée et installée : écran actif par défaut pour les nouvelles
fenêtres, choix français et aide dans Tuilage, choix explicites conservés et repli
sur l'écran de la fenêtre si aucun écran actif n'est connu. Docs FR/EN alignées.
1 696 tests / 199 suites réussis, revue traitée. UUID
90FAA3EE-A562-3103-8953-A520E2A0AE62, PID 83745, quatre contrôles santé OK.
Complément d'aide : effet possible sur la réactivité expliqué, sans gain garanti.
Configuration et certificat conservés. Preuves visuelles incomplètes : bureau
inaccessible. Reçu : specs/046-placement-ecran-actif/validation.md.
Session 047 implémentée et installée : `roadie toggle floating` fait flotter la fenêtre
active dans sa stage, puis la remet au tuilage (épinglage de portée stage, lisible par
les versions antérieures). Menu « Fenêtre » aligné, commande routée vers le daemon.
1 707 tests / 200 suites réussis ; revue traitée. UUID 7DE5FFC6-67B3-3CD2-A7B3-3C4CB9A1694E,
PID 64518, quatre contrôles santé OK. Aller-retour réel vérifié sur Firefox.
Reçu : specs/047-fenetre-flottante/validation.md.
Sessions 048, 051, 049 et 050 implémentées et installées (pipeline du 18 octobre) :
consommation au repos 11,45 % → 2,34 % d'un cœur (ADR 015), constats HIGH de l'audit
performance corrigés sauf D-02 (décision utilisateur), santé `macos-window-settings`,
double-clic de barre de titre désactivé par défaut. 1 744 tests / 208 suites.
Audits V15 inconclusive : historique Git analysé seulement depuis v0.4.0 (option A,
sans fuite), adaptateur V15 sans arguments. UUID 7FAEFA94-B08E-3C14-B9B4-852B532C97E3.
Reçus : specs/048-consommation-repos/, 051-constats-high/, 049-reglages-macos/, 050-double-clic-titre/.
Session 052 implémentée et installée : nettoyage autorisé des douze stages vides,
stages occupées prioritaires, rail défilable et fantôme aligné avec les destinations.
Parking réutilisant les emplacements vides compatibles ; homonymes ambigus préservés.
A-11 : ancrage mémorisé au clic, acquisition au premier glisser avec cible gérée.
Revue traitée : réordonnancement par groupe, case vide active protégée, ancrage
invalidé abandonné et hauteur de défilement limitée à la zone utilisable.
1 754 tests / 209 suites réussis. UUID DFB9822B-301D-38BE-85FB-5586254D4370,
PID 25248, cinq contrôles santé OK. Quatre stages occupées et dix membres conservés.
V15 : historique borné explicite, 63 tests courants/39 isolés, commit 744f30b dans
00.Generic. Preuves visuelles incomplètes : bureau inaccessible. Reçu :
specs/052-rail-reconnexions/validation.md.
Session 053 implémentée et installée : ordre choisi conservé, création d'une stage
en haut, entre deux cartes ou en bas à l'emplacement du dépôt. Ancre stable résolue
dans la transaction, cartes figées pendant le geste, conflits refusés sans mutation.
Repère « Nouvelle stage », aucun repli sur le rail source. 1 758 tests / 210 suites,
revue indépendante traitée. UUID 458CF5AB-3B7E-3F5A-9B09-656E7B0FF331, PID 81466,
cinq contrôles santé OK. Configuration/certificat conservés. Bureau inaccessible ;
essai utilisateur proposé. Reçu : specs/053-depot-rail/validation.md.
Complément 053 installé après essai utilisateur : stage nommée vide identifiable
avec contour/nom/numéro et « Vide » permanents ; stages anonymes vides masquées.
1 760 tests / 210 suites réussis, revue traitée. UUID
DAF8ED16-F7D6-30AE-A800-A338ACEF5027, PID 27951, cinq contrôles santé OK.
Configuration et signature conservées ; nouveau rendu réel non capturé, CUA inaccessible.
Session 054 : version mineure 0.6.0 publiée avec README, notes FR/EN et changelog
regroupé. 1 760 tests / 210 suites et 26 scripts réussis ; revue traitée. DMG arm64
vérifié et signé ad hoc. Installation locale 0.6.0, PID 95762, santé 5/5 ; certificat
et configuration conservés. UUID F48FF668-E529-395C-ADD8-DA3D0CD1E2F0.
Release https://github.com/guthubrx/roadie/releases/tag/v0.6.0 (Latest), DMG/SHA-256
retéléchargés et identiques. Tag d78fe561 ; branche supprimée, builds/temporaires
nettoyés, worktree de conversation actif conservé détaché.
Reçu : specs/054-release-060/validation.md.
Session 055 installée : toggle fullscreen masque le rail, même au survol, sans
plein écran natif. Une fenêtre déjà grande entre aussi dans le mode explicite.
Ctrl gauche + Alt gauche + F configuré dans BTT et relu ; pin conservé.
1 761 tests / 211 suites réussis, revue traitée ; UUID
E2CE37E8-CD10-3D53-978A-95F10F997E47, PID17507, cinq contrôles santé OK.
Docs FR/EN et changelog Non publié à jour. CUA inaccessible, essai utilisateur
proposé. Code b92dc331 intégré/poussé, branche et build nettoyés.
Reçu : specs/055-fullscreen-sans-rail/validation.md.
Session 056 installée : sélecteur de fenêtres intégré aux bureaux/stages/écrans,
recherche, profils, styles et grille à côté du grand aperçu. Raccourcis internes
facultatifs ; Cmd+Tab et Cmd+Maj+Tab configurés dans BTT par commandes CLI.
1 849 tests / 222 suites, puis 88 tests ciblés après le dernier ajustement ;
28 tests de scripts réussis. Trois revues traitées. UUID
E71B3887-DD49-3060-87CA-162E9307A4F5, PID 8089, santé 5/5.
Configuration et certificat conservés. Parcours initial confirmé par l'utilisateur,
capture finale vérifiée ; Cmd+Tab externe et validation au relâchement confirmés
après correction BTT. Preuve complète des interactions non enregistrée.
Reçu : specs/056-selecteur-fenetres/validation.md.
Session 057 installée : paramètres regroupés par usage, profils dédiés et capture
native des raccourcis. Gestionnaire Roadie/BTT/externe, trois modes au relâchement,
recherche/actions contextuelles et apparence par profil. Flèches acceptées avec
les modificateurs maintenus, survol sélectionne et clic active.
1 869 tests / 227 suites et 28 scripts réussis ; revue indépendante traitée.
UUID 20584940-BB44-3A34-8DE1-EFC0D35D6159, PID 84023, santé 5/5.
Navigation réelle aux quatre flèches avec Commande maintenue après Cmd+Tab
confirmée par l'utilisateur le 23 octobre 2026.
Configuration et certificat conservés. Captures de la fenêtre installée vérifiées,
parcours complet de capture des touches et liaison BTT non enregistré.
Reçu : specs/057-parametres-raccourcis/validation.md.
Session 058 installée : formulaires compacts alignés dans les douze catégories,
règles repliables et aides défilables. Onglets du sélecteur sur toute la largeur,
segments égaux et sélection visible ; deux rangées à grande police.
Configuration/raccourcis conservés. 1 876 tests / 231 suites et 28 scripts réussis.
UUID final 7993A537-B6B2-3509-A069-FA1854E802C7, PID 11485, santé 5/5.
Deux revues traitées. Captures réelles initiales vérifiées ; dernier rendu des
onglets contrôlé en test natif, parcours complet des aides non enregistré.
Reçu : specs/058-coherence-parametres/validation.md.
Session 059 : 0.7.0 publiée, notes et documentation FR/EN à jour. Changelog
regroupé depuis 0.6.0 ; revue traitée. 1 876 tests / 231 suites et 28 scripts OK.
DMG arm64 et SHA-256 vérifiés après téléchargement GitHub. Tag 808ba047,
release Latest : https://github.com/guthubrx/roadie/releases/tag/v0.7.0.
Installation locale 0.7.0, UUID 35F47682-FF59-3D44-86B2-6345129B5B81,
PID 60119, santé 5/5 ; certificat et configuration conservés. Branche supprimée,
builds et temporaires nettoyés ; worktree actif conservé détaché.
Reçu : specs/059-release-070/validation.md.
Session 060 installée : cinq organisations du sélecteur, choix commun et par profil,
sans nouveau raccourci ni changement d'affectation. Fidélité des cartes et du détail
corrigée ; taille automatique cherchant une page et colonnes de bureaux si besoin.
1 900 tests / 235 suites et 28 scripts réussis. UUID
E367325B-3C1D-3958-B982-886E7E2BD915, PID 21019, santé 5/5.
Certificat et configuration conservés à la dernière installation. Onze fenêtres,
quatre bureaux et sept stages sans défilement : tests natifs 120/220/400 points,
écrans 1920×1080 et 3840×2160. Ouverture installée capturée en grille classique ;
parcours complet des paramètres et capture finale par sections non enregistrés.
Revue indépendante non démarrée : admission Bridget auto_admission_invalid.
Reçu : specs/060-presentations-selecteur/validation.md.
Session 061 : vue globale Archipel/Baies avec loupe de fenêtre au survol, grossissement
100–250%, CLI overview et raccourci interne facultatif. Geste BTT trois doigts haut
confirmé ; conflit Mission Control natif désactivé après sauvegarde et relecture.
Port graphique fidèle à la référence, bandeau épuré sans logo/compteurs ni pied.
Overlay couvrant NSScreen.frame, sans Space dédié, fermeture Échap vérifiée.
1918 tests /238 suites et28 scripts réussis. UUID DFD88CB9-B19B-3164-94C7-31CF4550EBDC,
PID46329, santé5/5 ; certificat et choix utilisateur160% conservés. Preuves natives
actualisées ; clics finaux, menu ouvert et geste après correction partiellement vérifiés.
Revue de code distante indisponible, sans verdict favorable inventé.
Reçu : specs/061-vue-ensemble/validation.md ; clôture Git/audit dans les notes de l’audit final.
Session 062 installée : fenêtres des stages masquées rétrécies par Mission Control. Pause de la
disposition et relevés provisoires pendant Mission Control, masquage en position seule, écriture
sans réponse (−25204) reprise au lieu d'être acceptée. ADR 019. 1 928 tests / 240 suites ;
Mission Control réel sans changement de taille. PID 94362, santé 5/5.
Reçu : specs/062-fenetres-mission-control/validation.md.
Session 063 : 0.8.0 publiée (Latest), tag 7b64afe2, DMG/SHA-256 retéléchargés identiques ;
installation locale 0.8.0, UUID F5122397-3E44-3F71-8172-5D668E435652, santé 5/5. Branches,
worktree d'audit et builds nettoyés. Revue indépendante non admise (Bridget permissions_changed).
Reçu : specs/063-release-080/validation.md. Session 064 abandonnée : film et captures retirés (contenus privés lisibles),
commit remplacé sur main ; README et guides inchangés depuis 0.8.0.
Session 065 installée : fenêtres fermées mais gardées en mémoire par leur application
(AlDente) écartées du sélecteur et de la vue d'ensemble : non listées par AX, application
visible, aucun bureau SkyLight. 1 934 tests / 241 suites. PID 62987, santé 5/5.
Contrôle réel sans AlDente ; diaporama non produit (contenu privé). Reçu :
specs/065-fenetres-conservees/validation.md.
Sessions 066, 067, 068 et 070 installées puis publiées en 0.9.0 (session 069) : bureaux
réordonnés et déplacés entre écrans, stages et fenêtres glissées dans la vue d'ensemble,
noms de stage uniques (doublons nettoyés, écran branché prioritaire), refus de taille
durable contre l'oscillation des fenêtres à format imposé. 1 954 tests / 248 suites.
Reçus : specs/066-reordonner-bureaux/, 067-deplacer-stages/, 068-tailles-imposees/,
070-glisser-entre-ecrans/, 069-release-090/validation.md.
Session 071 publiée en 0.10.0 (session 072) : aperçu en direct des déplacements avec
fantômes, création d'une stage ou d'un bureau en déposant dans le vide, centrage vertical,
visée sur la disposition affichée, contour bleu unique de la stage qui reçoit une fenêtre.
Complément 068 : refus de taille conservé quand l'application revient d'elle-même.
Reçus : specs/071-apercu-direct/, 072-release-0100/validation.md.
Sessions 073 et 074 installées : lanceur dans la barre Capslock+F (applications, fenêtres,
stages, bureaux, cibles), classement appris, verbes et destinations par Tab, liste à la
manière d'Alfred. 1 976 tests, santé 5/5. Référence : docs/analyses/2026-10-25-reference-alfred.html.
Session 075 installée : variantes ⌘/⌥/⌃ + Retour annoncées sur la ligne, ⌘1 à ⌘9, → pour
les verbes, Capslock + Maj + F et `roadie targets actions`, flotter ou tuiler cette fenêtre ou
toujours l'application (règle `affinity-app-…` unique). 1 983 tests, santé 5/5.
Session 076 installée : classement du lanceur selon la stage active, vignettes réelles des
fenêtres avec pastille. 1 989 tests, santé 5/5.
Session 077 installée : fichiers dans le lanceur (Spotlight), fichier déjà ouvert → sa fenêtre,
stage du dossier, Finder, Quick Look, ⌘C, `roadie launch`. 1 997 tests, santé 5/5.
Session 078 installée : aperçu actif du lanceur (vraies fenêtres déplacées, fantôme, Échap
restaure, disposition suspendue au plus 1,5 s sans renouvellement). 2 001 tests, santé 5/5.
Session 083 installée : fenêtre neuve gardée sur l'écran actif (rattachement physique après
5 s seulement), refus de taille répété durable (T3 Code), écriture annulée deux fois retenue
(émulateur), fenêtres retirées par leur application marquées fermées (AlDente 781).
2 006 tests / 269 suites, santé 5/5. Reçu : specs/083-stabilite-placement/validation.md.
Session 079 installée : phrase complète FR/EN (`fire perso gauche`), ⌘S garde une action
(abréviation, commande `roadie launch … --position …`). 2 008 tests, santé 5/5.
Session 080 installée : projets de stage (enregistrer, rouvrir aux mêmes cadres, même après
redémarrage), `roadie project save|open|list|delete`. 2 017 tests, santé 5/5.
Session 081 installée : barre vide utile, `roadie undo`, règles proposées avec chip. Les
fichiers du lanceur suivent `TestEnvironment.launcherFile`. 2 024 tests, santé 5/5.
Session 082 installée : documents et onglets ouverts dans la recherche (Firefox non couvert),
diagnostic `roadie launch --open-items`. 2 028 tests, santé 5/5.
Session 086 installée : échec d'écriture identique répété gardé durable (boucle T3 Code à 31 s
en `bsp`), applications lentes nommées dans `live_tick.axSlowApps` pour les passes d'au moins 1 s.
2 037 tests / 280 suites, santé 5/5. Reçu : specs/086-echecs-durables/validation.md.
Session 096 installée : « Souvent ici » et « Recherches récentes » de la barre vide réglables
(`idle_frequent_*`, `idle_recent_searches_*`, Paramètres > Recherche). 2 119 tests, santé 5/5.
Session 097 installée : « Revenir » saute la fenêtre en cours ; après Échap, la fenêtre et l'élément
qui avaient le clavier le retrouvent (AX). Essai réel dans T3 Code à confirmer (`launcher.focus_restore`).
2 121 tests, santé 5/5. Reçus : specs/096-barre-vide-reglages/, specs/097-focus-apres-barre/validation.md.
Sessions 100 à 105 installées : tilde et accents par touche morte gardés ; thèmes d'Alfred (thème sombre,
nombre de résultats) ; barre déplaçable, place retenue ; `> commande` dans le terminal choisi ; signets de
Firefox (profils, étiquettes, mots-clés, icônes), Safari, Chrome et onglets Firefox ; commandes système, ⌘L,
⌫ dossier, tri, `roadie launcher reset`. 2 158 tests / 305 suites, PID 33419, santé 5/5. Reçus : specs/100 à 105.
Session 106 installée : Cmd+Tab entre un plein écran natif et le bureau ordinaire, dans les deux sens
(ouverture LaunchServices puis élément AX par jeton distant, ADR 020) ; liste relue au lieu d'être vide.
Réglage macOS « passer à un espace avec des fenêtres ouvertes » requis. Aller-retour confirmé par l'utilisateur.
Reçu : specs/106-cmdtab-plein-ecran/validation.md.
Sessions 107 et 108 : recherche des paramètres qui filtre la colonne de gauche (index des valeurs, résultats
paresseux : « p » 4,6 s → 0,2 s) ; Paramètres > Raccourcis réunit toutes les touches réglées par appui, les
commandes `roadie` de BTT avec leur gestionnaire (BTT, Roadie `[[shortcuts]]`, personne) et les conflits.
⌘L était pris par BTT (`roadie focus right`) : `btt_pause_keys` met BTT en pause pendant la barre.
2 170 tests / 308 suites. Reçus : specs/107-recherche-parametres/, specs/108-raccourcis-reunis/.
Session 093 (audit V15 de la base de code, specs/093-audit-codebase/) et session 098 (focus clavier après
Échap) intégrées dans main le 28 octobre 2026 : 2 205 tests / 312 suites et 28 tests de scripts réussis.
Fusion préparée par Codex conservée sous l'étiquette `archive/093-fusion-preparee-20261027`. Le numéro 093
reste partagé avec specs/093-ordres-alfred.
Session 109 installée : clic droit sur une stage du rail > « Supprimer la stage », nommée ou non, si elle n'a plus
de fenêtre (stage active et écran absent exclus, raison affichée). 2 208 tests / 313 suites, PID 16562, santé 5/5.
Reçu : specs/109-supprimer-stage/validation.md.
Session 110 installée : Retour sur un calcul copie toujours et ouvre aussi Calculette si `calc_opens_calculator`
(Paramètres > Recherche, désactivé par défaut). 2 212 tests / 314 suites, PID 39168, santé 5/5.
Reçu : specs/110-calc-calculette/validation.md.
Sessions 111 à 120 installées (reprise d'Alfred terminée) : ordre appris des verbes, forme des tuiles, `in` et `tags`,
historique des navigateurs, réglages dans la barre et ⌘,, documents récents (macOS et Office), vues Texte, Image et PDF
des workflows, petites reprises (open, find, types, calcul, défilement, recherches web, Spotlight), boutons Remote et
cache des Script Filters. 2 252 tests / 324 suites, PID 18000, santé 5/5. Corpus : 92 workflows sur 102 complets.
Reçus : specs/111-ordre-verbes/ à specs/120-remote-cache/.
Session 121 installée : icône de l'application à gauche du titre dans le sélecteur (`switcher.app_icon`, activée
par défaut), taille automatique selon le texte ou 12 à 64 points (`switcher.app_icon_size`). 2 257 tests / 325 suites.
Reçu : specs/121-icone-selecteur/validation.md.
Session 122 installée : sélecteur réduit aux fenêtres (ni « Roadie », ni résumé, ni aide des touches ou du relâchement). 2 259 tests / 326 suites.
Reçu : specs/122-selecteur-epure/validation.md.
Session 123 installée : barre rapide sous charge (fil principal bloqué 1,2 s → 0,26 s au plus, historique 1 à 9 ms par
touche, fichiers ouverts en 50 ms et gardés devant ceux de Spotlight, ADR 021). 2 264 tests / 329 suites.
Reçu : specs/123-barre-rapide/validation.md.
Session 124 : README FR/EN, guides docs/*/launcher.md et About GitHub mis à jour ; captures sans donnée privée générées par
`ROADIE_DOC_SHOTS_DIR=… scripts/test --filter Spec124` dans docs/assets/screenshots/. Reçu : specs/124-doc-lanceur/validation.md.
Session 125 installée : fenêtres toujours flottantes par application et titre (`[[exclusions.floating_windows]]`, `#` nombre,
`*` texte, priorité 9 100), menu Fenêtre et Paramètres > Règles, `roadie window explain`, premier cadre. Rappels de
Thunderbird confirmés par l'utilisateur. 2 272 tests / 331 suites. Reçu : specs/125-fenetres-appoint/validation.md.
Session 126 installée : barre, sélecteur et vue d'ensemble en anglais ou en français selon macOS (`tr(fr, en)`,
`UILanguage`, `ROADIE_LANGUAGE`, français fixé par `scripts/test`), verbes et bureaux trouvés dans les deux langues.
Captures EN par défaut, FR dans `docs/assets/screenshots/fr/`. 2 276 tests / 332 suites. Reçu : specs/126-interface-anglaise/.
Session 127 installée : interface entièrement traduite (`tr(fr, en)`, ~1 300 textes), réglage `[interface] language`
(`auto` par défaut, `fr`, `en`, relance de Roadie). Poste de l'utilisateur en `en-US` : Roadie s'y affiche en anglais,
choix confirmé. 2 278 tests / 333 suites. Reçu : specs/127-traduction-complete/validation.md.
Session 128 : 0.11.0 publiée (sessions 073 à 127 : lanceur, workflows d'Alfred, interface EN/FR). Notes
docs/releases/v0.11.0*.md, reçu specs/128-release-0110/validation.md.
Audit V15 du 29 octobre 2026 (audits/2026-10-29/session-2026-10-29-codebase-01) : inconclusive, aucun défaut grave.
Session 129 installée : ses six constats corrigés (actions de workflow sans délai comme Alfred, commandes système
attendues 600 s avec notification d'échec, index des littéraux, parcours Firefox O(n)), code mort retiré.
2 272 tests / 332 suites, PID 79678, santé 5/5. Reçu : specs/129-corrections-audit/validation.md.
Session 130 : 0.11.1 publiée (corrections de l'audit). Notes docs/releases/v0.11.1*.md, reçu
specs/130-release-0111/validation.md.
Session 131 installée : actions d'Alfred dans la barre (verbes de fichiers, texte, onglets, applications ; Informations =
fenêtre ⌘I du Finder), ⌘/⌥/⌃ + Retour réglables, menus de l'application active, commandes système et Musique,
nouveautés d'Alfred 6 (grille `apps`, `symbols`, thèmes en verre, tableaux Markdown). Vue Texte sans champ de saisie
qui plantait Roadie corrigée. Audit V15 A/pass. Reçu : specs/131-actions-alfred/validation.md.
Session 132 installée : fenêtres flottantes décalées hors du rail à l'ouverture (`floating_avoid_rail`), place retenue
par règle (`remember_frame`, `~/.roadies/floating-frames.json`). Reçu : specs/132-place-fenetres-flottantes/.
Session 133 installée : recherche à l'écran séparée du lanceur (`screen_search_hotkey`, Capslock + F chez
l'utilisateur ; `roadie targets screen`). Session 134 installée : fautes de frappe rattrapées (`typo_max_errors`),
clic à l'écran fiable juste après la barre, Maj + étiquette qui clique sans Maj, `launcher_on_screen`.
`pick_modifier = control` chez l'utilisateur (Maj + chiffre tape en AZERTY). 2 335 tests / 347 suites.
Reçus : specs/133-recherche-ecran/, specs/134-fautes-de-frappe/validation.md.
Sessions 135 à 137 installées : zones récentes (endroits cliqués par la recherche à l'écran et par les clics, avec
photo) dans un profil du sélecteur `source = "zones"` (Option+Tab chez l'utilisateur), même comportement que Cmd+Tab,
retour et clic, aller-retour, bordure jaune sur l'application, photos reprises en quittant une fenêtre, 20 zones,
24 h, 3 zones de clics par fenêtre ; icônes des cartes (× et sens interdit). Reçus : specs/135 à 137.
Session 138 : 0.12.0 publiée (sessions 131 à 137). Reçu : specs/138-release-0120/validation.md.
Current SpecKit feature: `147-placement-initial-stable`.

Contexte :
- `specs/143-glisser-direct/spec.md`
- `specs/143-glisser-direct/plan.md`
- `specs/143-glisser-direct/tasks.md`
<!-- SPECKIT END -->

## Revues indépendantes

Autorisation permanente donnée le 21 octobre 2026 : lancer les revues indépendantes
sans nouvelle demande de confirmation. Le responsable traite leurs constats et
poursuit les tests et la livraison autorisés.

<!-- SPECKIT-USER START -->
# Couche utilisateur SpecKit

- Source de verite utilisateur: `~/.speckit/`.
- Avant une feature/refactor structurel: executer ou appliquer `/speckit.sync`.
- Charger `.specify/memory/constitution.md` pour les gates projet.
- Charger `.specify/memory/standards.md` pour retrouver les refs et baselines research.
- Ne pas modifier directement `.agents/skills/speckit-*`, `.specify/templates/*`, `.specify/scripts/*` ou `.specify/workflows/*`.
- Les commandes utilisateur canoniques vivent dans `~/.speckit/commands/` et sont publiees vers Codex/Claude/Gemini par `~/.speckit/scripts/sync-agent-adapters.py`.
<!-- SPECKIT-USER END -->
Session 139 installée : Maj seule recule dans Cmd+Tab et Option+Tab (`SwitcherShiftTap`), images de zones réalistes.
Session 140 installée : zones de clics par application (`[[switcher.zone_clicks_per_app]]`, valeur globale sinon).
Session 141 : 0.13.0 publiée (Latest), tag 57fe791e. Reçu : specs/141-release-0130/validation.md.
Session 142 implémentée et installée : suivi des voisines pendant un redimensionnement natif
en spatialBsp, écriture asynchrone coalescée et proportions finales enregistrées une fois.
2 375 tests / 355 suites et 28 tests de scripts réussis ; première revue traitée,
seconde non admise par Bridget. UUID 4ED973A1-25AE-39EA-86B7-DA47F3FC7E6D,
PID 81878, santé 5/5 ; certificat et configuration conservés. Commit local,
sans release. Preuves partielles : Mac verrouillé avant l’essai après installation ;
aucun gain de latence native revendiqué. Reçu : specs/142-redimensionnement-natif/validation.md.

Session 143 installée : voisines réelles pendant le glisser, option immédiate live_drag_preview
dans Tuilage. 2 383 tests / 356 suites et 28 scripts réussis ; santé 5/5, certificat/configuration
conservés. Geste natif observé et usage confirmé par l’utilisateur. Preuves partielles :
réglage et Échap non enregistrés en natif ; revue non admise par Bridget. Commit local.
Reçu : specs/143-glisser-direct/validation.md.

Session144 : effets réglables indépendants de macOS et aperçu réel de destination, code intégré, poussé, installé et activé. Huit glissers Chrome normaux réussis, source stable et restauration8/8. Qualification de titre44 points, groupe racine Electron et bande Chrome sans action/enfant ; aucun geste natif repris tardivement. Suite2416 tests/360 suites et28 scripts réussis. Audit V15 révision1 pass/release_blocked=false ; revue indépendante non admise. Stabilité Firefox confirmée par l’utilisateur ; repli contour entre écrans explicite. UUID76B3E44F-DB41-3DF5-BECE-7849353D4880, PID30412, santé5/5,28 affectations et configuration conservées. Aucune nouvelle release. Reçu : specs/144-effets-reglables/livraison.md.

Session145 installée : vraie destination entre écrans après fin native marquée, maintien logique du geste et restauration au clavier. Masquage des fenêtres déjà parkées corrigé.2420tests/362suites et28scripts réussis, huit parcours natifs. UUID833B2A78-2083-37FB-9355-4F14B488010F, PID85334, santé5/5 ; codeedd99a41 intégré/poussé. Revue distante refusée ; limites et preuves : specs/145-apercu-entre-ecrans/livraison.md.

Session146 installée : premier placement tuilé direct et découverte transitoire bornée.2425tests/363suites et28scripts réussis ; iTerm observé sans trajet animé, ajustements natifs AppKit explicités. UUID758AD9DB-B909-3E17-80FC-512675038D50, PID23980, santé5/5 ; sourceee218ff0 intégrée/poussée. Revue distante refusée. Reçu : specs/146-placement-initial/livraison.md.

Session147 installée : intermittence iTerm2 reproduite malgré la politique directe146 ; position avant taille au premier placement. Dix CmdN vérifiés, aucune variation de taille observée à l'origine, cibles exactes et stables au moins7,308s.2431tests/364suites et28scripts réussis. UUID703A4229-EBC7-3114-A08F-8A998776135E, PID90574, santé5/5 ; source6423057b intégrée/poussée. Premières surfaces macOS et ajustements à destination restent possibles. Revue distante refusée ; preuves et limites : specs/147-placement-initial-stable/livraison.md.
