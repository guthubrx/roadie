# Validation 039

## Reproductions avant correction

- Cache partagé : un relevé injecté de 2 s entraîne un nouveau relevé dès la lecture suivante. Six assertions en échec pour lecteur/producteur.
- Fenêtres attachées : un contrôle enfant est lu inutilement alors que la cible est déjà connue. Une assertion en échec ; les panneaux manquants restent résolus.
- Coordonnées : quatre types d'événements, deux écrans. Huit assertions en échec avec la souris actuelle ; réussite avec la position de l'événement.
- Redimensionnement : 500→700 annulé à 500 par un scan de 3 s. Six assertions en échec sur la première observation et le poll suivant.
- Santé : daemon health hors routage malgré permissions propres au daemon. Test rouge ; constat runtime CLI faux échec, query health quatre OK.

## Tests ciblés après correction

30 tests de snapshots et fenêtres attachées réussis. 44 tests de coordonnées, dépôts,
glissements et menus réussis. 21 tests de redimensionnement réussis, dont expiration
réelle des gestes anciens, plein écran, changement d'identité/scope, bords extérieurs,
bouton encore maintenu et dépôt reconnu. Suite complète : **1 603 tests / 185 suites réussis en 35,290 s**, exécution séquentielle.

## Relecture locale

Changements ciblés dans les mécanismes existants ; aucune dépendance, aucun format
persistant, aucun changement de configuration utilisateur. Les identités CG nécessaires
sont regroupées en O(n) avant le parcours AX. Le cache conserve ses plafonds et invalidations.
Les coordonnées utilisent la conversion multi-écran existante. Le budget temporel du geste
exclut uniquement le scan commencé à temps ; les attentes trop anciennes restent rejetées.
Le contrôle santé utilise le routage explicite existant, sans router heal/restart.

Revue indépendante indisponible : Bridget t3_session_unavailable,
attestation_transport_unavailable ; request_id roadie039-review-20261017-1.
Aucun résultat indépendant prétendu.

## Preuves visibles

Preuves incomplètes : screencapture échoue avec « could not create image from display » ;
CUA échoue avec « CUA_REPL_ENABLED_SURFACES is required ». Aucun geste envoyé à l'aveugle.
Les parcours synthétiques ne sont pas présentés comme des parcours UI réels.


## Mesure avant installation

Requête identique `query windows` via le socket du daemon, six tours, premier tour
écarté pour l'amorçage. 17 fenêtres à chaque tour. Durées retenues : 1996,52 ; 1670,10 ;
2178,84 ; 2163,89 ; 909,58 ms. Médiane : 1996,52 ms. Mesure de temps de réponse global,
avec les files du daemon et le bureau réellement ouvert ; pas une mesure isolée CPU.
Source : /Users/moi/.roadies/diagnostics/2026-10-17-session039/measure-before.json.

Les 276 empreintes des sources et tests sont enregistrées après la suite complète.
La compilation Release utilise exactement ces fichiers. Aucun test script relancé :
aucun script modifié dans cette correction.

## Installation et vérification après redémarrage

Installation Release réussie le 17 octobre à 19:43 CEST, puis redémarrage du daemon
(PID 56895) et du gardien (56908). Application installée : /Users/moi/Applications/Roadie.app.
CLI installée : /Users/moi/.local/bin/roadie. Version conservée : 0.5.0, aucune release publiée.
Signature vérifiée ; certificat existant conservé (78a75e8032f190a20072eb91cc2919aac344ef78).
UUID du binaire Release et du binaire installé identiques : E9C6B7F7-EEDA-30FB-84D8-DE4F5CC08155.
Configuration utilisateur inchangée (SHA-256 301d7d43737c1deb31d2acaa3146ca5b285450a1bad65d27bd8cd095e19a3d77).

À 19:45:24, les quatre contrôles `daemon health` sont OK : processus, état du daemon,
autotest et cohérence de l'état. Les 20 événements depuis le démarrage ne contiennent
aucun échec de placement ni restauration externe. Quatre passes de tuilage sont journalisées,
entre 18,9 et 77,6 ms. Cette observation courte ne remplace pas un essai de redimensionnement réel.

La même requête `query windows` donne une médiane de 16,39 ms immédiatement après installation,
puis 35,92 ms à 19:45, hors premier tour. Les six tours de chaque série réussissent.
Il reste 16 fenêtres, contre 17 avant le redémarrage : bureau et caches non identiques.
Ces mesures montrent le temps de réponse observé, sans établir un facteur d'accélération contrôlé
ni mesurer la latence complète d'un geste visible.

## Conservation

Archive privée durable : /Users/moi/.roadies/diagnostics/2026-10-17-session039.
Elle contient les traces originales, leurs empreintes, la sauvegarde de l'application précédente,
les états avant/après, les tests rouges puis verts et les mesures. Le sous-dossier post-install
conserve les relevés après livraison. archive-manifest.json recense les empreintes de l'archive.
Les données brutes restent hors Git ; les journaux d'origine n'ont pas été supprimés.

Preuves visuelles incomplètes : accès natif à l'écran indisponible. Aucun diaporama de parcours
réel ne peut être attesté. La revue indépendante reste indisponible pour la raison indiquée plus haut.
