# Validation de la session 056

## Sources et périmètre

Implémentation originale du sélecteur pour les fenêtres gérées par Roadie.
Sources AltTab et choix de périmètre : `research.md`, `spec.md` et `contracts.md`.
Trois lots séparés intégrés : réglages, modèle/navigation/AX et interface/clavier.
Contrats puis intégration et tests sur le Mac. Aucun code AltTab importé.

## Vérifications du 23 octobre 2026

- Source compilée : `ce58c06d61af4ea412e2e5b846ed47b32919779e`.
- Tests ciblés : 135 tests dans 15 suites, succès.
- Suite complète : 1 845 tests dans 222 suites, succès (22,626 s).
- Scripts : 26 tests, succès.
- Aucun benchmark : machine chargée. Ces durées ne sont pas une mesure de performance produit.
- Rendus AppKit hors écran : vignettes, icônes et liste ; sélection, taille de police
  et hauteur bornée contrôlées. Ce sont des fixtures, pas des captures du bureau.

## Revue indépendante

Première revue sur `83019d7d`, lecture du diff depuis `40aa7519` :

1. `--no-target-mode` : démarrage du sélecteur désormais séparé en mode standard.
   Le processus modulaire `target-mode` conserve les deux interfaces.
2. Limite de seize applications : supprimée. Toutes sont consultées, avec au plus
   quatre acquisitions AX simultanées ; test sur dix-sept applications.
3. Fenêtre absente du relevé : restauration avant disposition, nouveau relevé,
   puis cadre mémorisé si AX reste indisponible. Deux variantes couvertes.
4. Observation synthétique : aucune mise à jour de signet depuis la carte.
   L'appartenance est revérifiée sous verrou ; une sélection périmée échoue.
5. Lecture : copie du SnapshotService sans écriture d'observation. La navigation
   ne réaffecte pas les membres. Erreurs de placement rapportées.
6. MRU : observation du focus publié et diffusion entre processus modulaires.
   Les changements réels par clic ou Cmd+Tab restent à confirmer au bureau.
7. Actions AX : délais et quarantaine existants conservés ; aucune mesure de
   latence revendiquée. Les collisions Carbon sont journalisées.

Deuxième revue ciblée sur `ce58c06d` : quatre premiers points confirmés corrigés.
Compléments traités : erreur visible après action ou activation refusée, panneau
conservé pour réessayer ; rechargement annulé et génération vérifiée ; restauration
refusée avec retour d'état conditionnel si aucun autre écrivain n'a modifié le
store ; démasquage après transaction ; focus confirmé après placement.
Tests ajoutés : refus de restauration, concurrence pendant l'échec, refus de
cadre distinct de l'échec de focus, retour de la session en mode persistant.

L'utilisateur confirme le parcours Ctrl+Alt+Tab installé, puis demande la grille
latérale et un raccourci externe Cmd+Tab. Ce changement est dans la même session.
Les raccourcis internes restent facultatifs et vides par défaut.

## Installation et essai réel

À compléter après compilation et installation.
Configuration avant installation : SHA-256
`ca42b5c670755e1b39371b1157c116c31e0754930800ad2551841fe5a3f05629`.
Certificat à conserver : `78a75e8032f190a20072eb91cc2919aac344ef78`.

Preuves visuelles incomplètes : CUA retourne
`CUA_REPL_ENABLED_SURFACES is required`. Aucun clic physique ni relâchement
clavier n'est attesté par les rendus hors écran. Ne pas redemander les permissions
macOS déjà accordées. Essai assisté sur la version installée nécessaire pour
valider Ctrl+Alt+Tab, Maj inverse, recherche, autre stage/bureau et annulation.
