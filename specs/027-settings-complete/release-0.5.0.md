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

Publication et contrôle distant restent à faire. Les vérifications préalables
et la relecture sont terminées.
