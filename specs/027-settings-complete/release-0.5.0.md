# Publication 0.5.0

Demande du 14 octobre 2026 : publier les nouveautés validées des sessions 025 à
027, actualiser les README et la documentation, et supprimer les répétitions
des notes 0.4.0. Publication autorisée explicitement par l'utilisateur.

## Documentation

- Changelog organisé par version et par changement visible.
- Pages de release françaises et anglaises séparées.
- Notes 0.4.0 raccourcies, avec migration et référence d'intégrité conservées.
- README, index des guides et référence de configuration alignés sur 0.5.0.
- Ancienne release : seul le texte est à mettre à jour ; tag et pièces jointes
  restent inchangés.

## Preuves de validation

- Suite avec la version 0.5.0 : **1 440 tests Swift dans 154 suites**, en 5,668 s.
  Journal : /private/tmp/roadie-050-tests.log.
  Ce passage après le changement de version est distinct du tour 4 de la session
  027, dont la suite avait passé en 6,943 s.
- Scripts : **26 tests réussis**, en 9,565 s.
  Journal distinct : /private/tmp/roadie-050-script-tests.log.
- Essai utilisateur des fonctions 025, 026 et 027 déjà confirmé ; aucun
  comportement applicatif modifié depuis ce test, hors numéro de version.
- Liens locaux : 56 liens vérifiés dans 11 documents, aucun lien absent.

Les revues distinctes des corrections sont consignées dans review.md.
Les tests aSavedScalarShowsAnExternalEditAndDoesNotWriteItBackOnBlur et
blurringASavedScalarDoesNotOverwriteAnExternalEditBeforeTheWatcher vérifient la
protection du changement externe. onePointSettingsWriteUsesBoundedRetryAndRealFrameProof
vérifie le pas d'un point et les reprises bornées. SettingsViewModelTests vérifie
la présence et la conservation de balanced. Ces faits ne sont pas déduits des
seuls titres de commits.

La première relecture des notes a demandé la preuve du résultat des scripts,
la référence des corrections et le rétablissement des informations de migration
et d'intégrité de 0.4.0. Ces points sont traités. La seconde relecture est favorable ;
sa réserve de formulation anglaise est corrigée pour rester alignée sur le français.

## Paquet vérifié

- Compilation release réussie.
- Application, CLI et daemon embarqués : **0.5.0**.
- Montage en lecture seule ; application et lien Applications vérifiés.
- Signatures ad hoc de l'application et du DMG vérifiées.
- hdiutil verify et contrôle SHA-256 réussis.
- DMG : **8 612 144 octets**.
- SHA-256 : `826d653fb30724f38e3749ff694725a7ac048c67952f2b7f5efaf8846ca63b4a`.
- Aucun daemon de travail utilisé pour les tests ou le packaging.

## Installation locale

Version 0.5.0 installée et redémarrée : PID 85924, quatre contrôles de santé OK,
configuration valide et permissions Accessibilité et capture d'écran conservées.
Certificat habituel conservé : `78a75e8032f190a20072eb91cc2919aac344ef78`.

## Publication vérifiée

Release v0.5.0 publiée le 14 octobre 2026 à 05:52:19 UTC, au commit
`7c61ef7a6fc57faecf1616c1c3e722eed18d6f6a`, après fusion et push de main.
URL : https://github.com/guthubrx/roadie/releases/tag/v0.5.0

Le DMG et son fichier SHA-256 sont joints. Un nouveau téléchargement depuis
GitHub passe le contrôle d'intégrité ; taille et empreinte distantes correspondent
au paquet vérifié. La version 0.5.0 est déclarée comme dernière release.

Le corps de la release v0.4.0 est actualisé et correspond au texte français
réécrit. Son tag reste `5ab0ab9544de68edbd6642f58ac6140ef8a07f1e` et ses pièces
jointes gardent leurs identifiants, leur taille et leur empreinte d'origine.

## Correction de présentation

À la demande de l'utilisateur, le raccourci personnel ne sert plus de nom public.
Le terme retenu est « barre de recherche et de commandes » ; la documentation
précise que le raccourci est personnalisable.

Les introductions des README français et anglais présentent les usages :
organisation par activité, plusieurs écrans, recherche, commandes et réglages.
Les fonctions disponibles sont décrites comme des outils à activer, avec leurs
conditions de compatibilité dans les guides. Les noms des clés TOML sont conservés.

Relecture éditoriale favorable. Les liens et ancres des textes corrigés sont
vérifiés. Cette correction concerne uniquement la documentation et les notes
publiées ; le tag et les fichiers de téléchargement restent ceux de la 0.5.0.
