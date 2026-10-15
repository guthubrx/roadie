# Livraison 037 — fiabilité du placement

Installée le 15 octobre 2026 à 20 h 09, puis redémarrée une seule fois.
Processus vérifié : 62842. UUID : 795C9759-EE86-3D9C-B720-0BCB7430213F.
Certificat existant conservé : 78a75e8032f190a20072eb91cc2919aac344ef78.
Quatre relevés successifs des quatre contrôles santé : tous OK.

## Résultat

Les sept mécanismes corrigés de 035 sont livrés. Les cinq autres mécanismes de
placement, présence, observation, panneaux attachés et concurrence de glisser sont
corrigés. Dix-huit sites de constat au total ; onze fichiers produit différents de
la version combinée précédemment installée. Les changements déjà installés de 029
sont conservés, sans modification de son worktree.

Tests : 1 587 réussis dans 183 suites. Les 278 empreintes Sources/Tests sont identiques
entre cette suite, la compilation Release et la vérification de livraison.
Avant correction, les reproductions de présence et de disponibilité échouent sur
18 assertions. Le test de lot donne les mêmes résultats que la boucle précédente ;
à 1 600 fenêtres synthétiques, médianes 177,008 ms et 1,622 ms en Debug.

## Parcours réels

- Fenêtre AX retardée de trois secondes sur le même écran : deux échecs avant,
  aucun après ; attente puis reprise automatique. Six cadres et appartenances
  communs inchangés après fermeture du témoin.
- Panneau de fichier natif : le contenu XPC est rattaché à AXSheet et exclu du
  tiling. La fenêtre principale reste gérée. Le dossier ne contient qu'exemple.txt.
- Plein écran natif pendant 35,12 secondes : six appartenances conservées.
- Dépôt réel d'une fenêtre vers le bas de sa voisine : insertDown appliqué et
  position conservée. Dépôt réel de vignette dans la stage témoin B : destination
  exacte, deux autres fenêtres conservées dans A. Vérification différée réussie.
- Nettoyage : deux stages temporaires et 14 références de fenêtres témoins retirées
  sous verrou. Stage 4 restaurée. Noms, ordre et membres utilisateur inchangés.

Configuration active inchangée, SHA-256 :
301d7d43737c1deb31d2acaa3146ca5b285450a1bad65d27bd8cd095e19a3d77.
Sauvegarde avant installation et preuves brutes :
/private/tmp/roadie037-evidence/pre-install
/private/tmp/roadie037-evidence

## Limites précises

L'écran externe est absent lors des essais natifs de cette livraison. Les variantes
croisées sont testées automatiquement. La conservation au-delà de 30 minutes est
vérifiée avec une horloge contrôlée dans l'assemblage du tiler. Le geste de
réordonnancement d'une stage au bouton droit n'a pas été rejoué physiquement ; ses
tests existants passent. Le lien entre la course du fichier de glisser et l'incident
Outlook de 10 h 28 n'est pas établi. Aucune affirmation de ce lien n'est faite.

La contre-lecture est locale et non indépendante. Les scanners globaux de sécurité
et d'historique ne sont pas relancés dans cette correction ciblée. Le rapport V15
conserve ces contrôles non vérifiés ; il ne vaut pas certification globale de Roadie.

Preuves : diaporama vérifié, onze étapes ; images, précédent/suivant, sélection,
lecture/pause à deux secondes, zoom et plein écran vérifiés dans le navigateur T3.
/Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/037-fiabilite-placement/preuves-corrections/2026-10-15-037-fiabilite-placement/preuves.html
