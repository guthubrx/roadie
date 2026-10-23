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
sans nouveau raccourci ni changement d'affectation. Grille classique conservée.
1 893 tests / 234 suites et 28 scripts réussis. UUID
92CDDB8A-E428-3103-ADAE-7E1901FBC770, PID 11924, santé 5/5.
Certificat/configuration conservés. Ouverture réelle du sélecteur observée ;
parcours des paramètres non capturé (saisie automatisée annulant la barre).
Revue indépendante non démarrée : admission Bridget auto_admission_invalid.
Reçu : specs/060-presentations-selecteur/validation.md.
Current SpecKit feature: `060-presentations-selecteur`.

Contexte :
- `specs/060-presentations-selecteur/spec.md`
- `specs/060-presentations-selecteur/plan.md`
- `specs/060-presentations-selecteur/tasks.md`
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
