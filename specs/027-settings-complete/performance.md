# Mesure des écritures immédiates — session 027

Date : 2026-10-14. Configuration mesurée : **29 293 octets**.

La mesure finale, après l'ajout de la validation sémantique, donne une médiane
d'environ **61 ms par modification valide**. Son maximum observé est de **69 ms**.
Toutes les écritures et tous les rechargements ont réussi. Une première mesure
avait observé un maximum de 89 ms ; cette variation ne prouve pas un gain causé
par les changements de code.

## Méthode

Le programme de mesure lit le fichier réel puis crée une copie UTF-8 isolée pour
chaque lot. Il modifie seulement ces copies. Le service de configuration et le
journal sont injectés vers le dossier temporaire ; les réglages actifs ne sont
jamais écrits.

Source lue : /Users/moi/.config/roadies/roadies.toml

Quatre lots mesurent chacun 50 changements effectifs. La marge alterne entre 6 et
7 ; la couleur alterne entre deux valeurs hexadécimales valides. Chaque lot repart
du contenu original. Le chargement initial et la première sauvegarde précèdent la
mesure. Les temps utilisent l'horloge monotone ; le p95 correspond au 48e temps
trié sur 50.

Le programme est lié aux objets de compilation de développement. Les résultats
ne sont donc pas une mesure du binaire de production installé.

## Résultats

| Parcours | Modifications | Médiane | p95 | Maximum |
|---|---:|---:|---:|---:|
| `SettingsService.set`, marge | 50 | 60,66 ms | 62,18 ms | 69,03 ms |
| `SettingsService.set`, couleur | 50 | 60,90 ms | 61,59 ms | 65,35 ms |
| `SettingsViewModel.editText`, marge | 50 | 60,77 ms | 61,56 ms | 61,90 ms |
| `SettingsViewModel.setColor`, couleur | 50 | 60,43 ms | 65,95 ms | 68,96 ms |

## Limites et décision

La mesure couvre le travail synchrone : conversion, validation du fichier
candidat, écriture atomique, rechargement et, pour la fenêtre, mise à jour du cache.
Elle exclut le retuilage du daemon, le redessin AppKit et les notifications traitées
de façon asynchrone. Elle ne mesure pas le délai complet entre une frappe et son
résultat visible.

Ce coût peut s'accumuler pendant une saisie rapide ou le déplacement continu d'un
curseur. Il signale un risque, sans confirmer un défaut de fluidité. Le test manuel
sur la version installée vérifiera la sensation de fluidité. Cette mesure ne
justifie ni un retour à la validation manuelle ni l'ajout d'un délai fixe : les
valeurs valides restent appliquées dès leur modification, conformément au besoin.

Programme de mesure : /private/tmp/roadie-027-benchmark.swift

Programme de liaison et d'exécution : /private/tmp/roadie-027-benchmark.py

Résultats conservés : /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/025-settings-readability/specs/027-settings-complete/benchmark.json
