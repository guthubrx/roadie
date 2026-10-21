# Validation de Roadie 0.6.0

## Périmètre

Release mineure depuis v0.5.0. README FR/EN et index mis à jour ; notes distinctes
du changelog. Historique des versions conservé. Pas de benchmark.

## Tests

1 760 tests Swift dans 210 suites réussis sur les sources 0.6.0, deux tâches,
exécution séquentielle. 26 tests de scripts réussis. Syntaxe du script de paquet
vérifiée après l'ajout de la génération SHA-256.
Machine de construction : macOS 26.2, arm64 (Apple Silicon). Minimum supporté
par le paquet : macOS 14. Aucun essai de cette livraison sur macOS 14 ou Intel.

## Revue indépendante

Relecture FR/EN et des versions en lecture seule, sans shell/diff ni build chez
le réviseur. Le responsable exécute les validations de livraison.
- Génération SHA-256 ajoutée au script de paquet et pièce jointe prévue.
- Reçu technique créé avant le tag.
- Formules de performance remplacées par les mécanismes constatés, sans chiffre.
- Résumé du rail allégé dans les README avec renvoi aux gestes détaillés.
- Menu exact : « Fenêtre > Flotter dans cette stage », puis « Revenir au tuilage ».
- Architecture réelle consignée et à vérifier dans le paquet monté.

## Préparation des livrables

Recettes temporaires dérivées des scripts existants : compilation à deux tâches
et create-dmg en mode --skip-jenkins pour éviter l'automatisation Finder indisponible.
Ce mode conserve les fichiers du paquet et le lien Applications ; la présentation
Finder personnalisée n'est pas appliquée. DMG distribué signé ad hoc, sans notarisation.
Installation locale prévue avec le certificat existant, indépendamment de la signature
ad hoc du paquet public. Les contrôles finaux figurent ci-dessous après construction.

## Contrôles des livrables

- DMG vérifié par hdiutil et monté en lecture seule, puis démonté.
- Roadie.app, icône du volume et lien Applications présents.
- Info.plist : CFBundleShortVersionString 0.6.0, LSMinimumSystemVersion 14.0.
- Daemon et CLI du volume : version 0.6.0, binaire arm64.
- Signature du paquet contrôlée avec codesign --verify --deep --strict.
- DMG : 9 116 771 octets ; fichier SHA-256 généré et vérifié.

```text
2d5754ce4434a2403f065c04356e68ca899690abd3b5b08d83dc972c822b1503  Roadie.dmg
```

UUID du daemon Release, du paquet et de l'installation :
F48FF668-E529-395C-ADD8-DA3D0CD1E2F0. Les deux exécutables installés et le statut
du daemon indiquent 0.6.0. Redémarrage terminé, PID 95762, cinq contrôles santé OK.
Le certificat local 78a75e8032f190a20072eb91cc2919aac344ef78 et la configuration
sont conservés. Les 303 empreintes Sources/Tests sont inchangées entre tests et
construction/installation.

Le module plistlib de Python Homebrew a rencontré une incompatibilité libexpat
lors de la première lecture du manifeste. Contrôle repris avec plutil natif :
version minimale, version du bundle et lien Applications vérifiés. Aucun changement
de l'environnement Python pour contourner cette erreur.

Les contrôles techniques ne remplacent pas une nouvelle vérification visuelle
des gestes. Les limites de capture des corrections précédentes sont conservées
dans leurs reçus ; cette session n'ajoute aucun nouveau comportement d'interface.

## Publication vérifiée et nettoyage

Release publique publiée le 21 octobre 2026 à 08:43:30Z :
https://github.com/guthubrx/roadie/releases/tag/v0.6.0
Elle est marquée Latest, hors brouillon et hors préversion.
Tag annoté v0.6.0 : commit d78fe5619f9ccd7e4ec7e703c6bde389e932449a,
référence distante contrôlée. Notes FR publiées avec lien EN, sans doublon de titre.
Deux pièces : Roadie.dmg (9 116 771 octets), Roadie.dmg.sha256 (77 octets).
Retéléchargement GitHub : SHA-256 vérifié, comparaison des deux fichiers avec les
originaux identique. Pas de PR créée ; intégration directe demandée sur main.

Recettes temporaires, dossier de compilation, cache Python des tests, bundle
intermédiaire et copie de téléchargement de contrôle supprimés. Le volume de
vérification a été démonté. Une seule paire DMG/SHA-256 est conservée dans
/Users/moi/Nextcloud/10.Scripts/39.roadie/dist/. Diagnostics et reçus conservés hors Git.
Branche de release fusionnée et supprimée ; aucune autre branche locale que main.
Le worktree lié à la conversation est conservé détaché, car il est actif.
