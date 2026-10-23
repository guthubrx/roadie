# Validation 060

## Implémentation
Les cinq organisations utilisent les cartes, le cache, la sélection et les actions
existants. Configuration commune `switcher.presentation`, surcharge facultative
dans chaque profil. Défaut `classic`, valeurs inconnues normalisées sans écriture.
Regroupement par identifiants écran/bureau/stage, ordre du profil conservé.
Le changement de sélection révèle le groupe ; les arrivées de vignettes ne
ramènent pas un défilement manuel vers la sélection.

## Contrôles terminés
- 143 tests ciblés dans 20 suites : réussite, 2,384 s.
- Suite complète : 1 892 tests dans 234 suites, réussite en 57,510 s.
- Scripts : 28 tests, réussite en 20,817 s.
- Géométrie des six organisations et des trois styles, largeurs 220/500/1000,
  polices 10/16/32 : cartes dans le document, aucun chevauchement de cartes.
- Petits panneaux, sélection inter-bureaux, recherche, héritage des profils,
  flèches avec Commande, survol, activation et défilement : tests natifs réussis.
- Détection avant correction d'une navigation Bas vers une grande fenêtre voisine
  dans le plan spatial. Priorité corrigée à la colonne, test de régression réussi.
- 339 fichiers Sources/Tests empreintés ; aucun benchmark réalisé.

## Preuves et limites actuelles
Cinq rendus AppKit du jeu fictif examinés. Les captures brutes et journaux restent
hors Git dans le dossier de diagnostics de la session. Le diaporama signale ces
images comme rendus de test et non comme parcours de la version installée.
CUA indisponible : `CUA_REPL_ENABLED_SURFACES is required`. Le circuit natif BTT
sera utilisé après installation si la fenêtre et le bureau restent disponibles.
Avant non capturé ; aucun pointeur ni clic supposé ajouté aux captures.

Revue, compilation Release, installation et essai installé en cours.
