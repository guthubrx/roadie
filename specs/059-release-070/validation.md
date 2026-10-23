# Validation de Roadie 0.7.0

## Périmètre
Version mineure depuis v0.6.0, sessions 055 à 058. Publication explicitement
demandée. Version applicative et défaut du script DMG alignés à 0.7.0 ; dépendance
TOMLKit inchangée. README, guides, index et notes FR/EN synchronisés.
Cette session ne change pas le comportement de l'interface et n'ajoute pas de
nouvelle preuve visuelle. Les limites de la session 058 restent applicables.

## Vérifications
La suite 0.7.0 réussit : 1 876 tests Swift dans 231 suites, 31,315 secondes,
à deux tâches et en mode séquentiel. Les 28 tests de scripts réussissent aussi.
Les deux binaires debug affichent 0.7.0. Syntaxe du script de paquet contrôlée.
70 liens de fichiers vérifiés dans les README, index, guides et notes.
Les contrôles du DMG et de la publication sont consignés après exécution.

## Distribution
Compilation sur macOS 26.2, arm64. Cible : macOS 14 et ultérieur, Apple Silicon.
Pas d'essai sur Intel ou macOS 14 dans cette livraison. Paquet signé ad hoc,
non notarisé. Une recette temporaire hors dépôt, dérivée de scripts/package-dmg,
ajoute --jobs 2 et --skip-jenkins pour éviter les actions Finder indisponibles.
Le script versionné n'est pas modifié pour ce mode ; les fichiers et le lien Applications sont
conservés, sans présentation Finder personnalisée. Installation locale avec
le certificat existant, distinct de la signature du paquet public.

## Paquet vérifié
DMG de 9 961 434 octets vérifié par hdiutil, monté en lecture seule puis démonté.
Roadie.app, icône et lien Applications présents. Bundle : version publique 0.7.0,
numéro interne de build 1 (convention existante), minimum macOS 14.0.
Daemon et CLI : 0.7.0, architecture arm64. Signature ad hoc contrôlée par
codesign --verify --deep --strict. UUID du daemon :
35F47682-FF59-3D44-86B2-6345129B5B81.

```text
7cb8f90a9362a2f3561eecaadb3dc7bfbe1ff73c4ab94f9926505863af1131e2  Roadie.dmg
```

Le fichier SHA-256 généré est vérifié. Les 336 empreintes Sources/Tests sont
identiques entre les tests et la construction. La première assertion du contrôle
de bundle supposait à tort que CFBundleVersion portait aussi la version publique ;
le script existant fixe ce numéro interne à 1. Contrôle corrigé après lecture du
script et du manifeste, sans changement du paquet ni du code applicatif.

## Installation locale
Application et CLI installées en version 0.7.0. UUID identique au paquet :
35F47682-FF59-3D44-86B2-6345129B5B81. Daemon relancé, PID 60119 ; cinq contrôles
de santé OK. Signature locale vérifiée, certificat
78a75e8032f190a20072eb91cc2919aac344ef78 conservé. Configuration identique avant
et après installation (SHA-256
8dfcd92534c87350adcf423e75b6b468befdac038a78eaed2a855451a32d0f8c).

## Revue indépendante
Tâche Bridget 4bce6aad-d088-4845-8c7f-3fa4a6a54209, source 2e6a539f.
Relecture sans shell/diff, compilation ni exécution chez le réviseur. Versions
et nouveautés jugées cohérentes ; les contrôles Mac sont faits par le responsable.
Reçu complété avant le tag. Recette temporaire de paquet explicitée. Chemins
de navigation harmonisés avec le titre réel « Réglages Roadie », accents corrigés
et détails d'installation alignés dans les README. Le type debug désigne la
compilation des binaires testés avec --version, pas une commande CLI.
Les formulations usuelles « garder ouvert » ou « reste disponible » restent
des descriptions du comportement, pas de nouveaux libellés d'interface.
Les libellés littéraux des modes sont déjà donnés dans les guides. Aucun changement
applicatif ou de schéma n'est ajouté pour une variante de formulation.
