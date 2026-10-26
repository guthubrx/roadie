# Validation 086

## Diagnostic sur les données réelles
- Journaux `~/.roadies/events.jsonl`, `.1`, `.2` (20 au 26 octobre), `layout_failed` regroupés par
  fenêtre avec l'intervalle entre deux échecs. Seule boucle à 30 s : T3 Code 223, le 25 octobre,
  28 échecs identiques (`977,46 817x1115`), intervalles de 30 à 33 s, cause `safety`. Les autres
  rafales (Outlook 209827, Chrome 505501) ont des intervalles de 0 à 2 s et datent d'avant 068.
- Passes lentes du 26 octobre : 56 de plus de 3 s (9 h 00 à 9 h 07 sans écriture, 19 h 54 à
  20 h 03 au réveil). Les longues retenues `heldByGestureMs` correspondent aux mises en veille.
- Firefox 498, 20 h 00 : aucun `window_gesture_target` entre 19 h 50 et 20 h 02 ; deux
  déplacements traités comme externes, une écriture de 13,2 s. Cause non établie, pas de correction.

## Tests
- `identicalFailureAfterExpiryBecomesLasting(mode:)`, en `bsp` et `spatialBsp`. En `bsp`, il
  échoue sans la correction (6 tentatives au lieu de 2) et réussit avec. En `spatialBsp`, Roadie
  s'arrêtait déjà après deux tentatives : le cas est gardé contre une régression.
- `Spec086AXCallTimingsTests` : application la plus lente en tête, seuil appliqué, remise à zéro.
- Suite complète `scripts/test --no-parallel` : 2 037 tests / 280 suites réussis.

## Installation et contrôle réel
- `make install && make restart` : PID 6036, santé 5/5, signature `roadied-cert`, configuration
  `~/.config/roadies/roadies.toml` identique à sa copie d'avant installation.
- Cinq minutes après le démarrage : aucun `layout_failed`, aucune passe de plus d'une seconde,
  donc pas encore de champ `axSlowApps` observé en réel.

## Limites
- Revue indépendante non admise : Bridget a refusé la demande (`origin_request_invalid`).
  Relecture du diff faite par le responsable.
- Correction purement technique, sans effet visible à montrer : pas de diaporama.
- Un échec durable n'est plus retenté tant que la fenêtre garde son cadre et la même demande.
  Une application lente un instant (-25204) peut donc rester mal placée jusqu'au prochain
  changement (geste, bascule, écran, autre disposition).
- `axSlowApps` compte aussi les appels AX faits pendant la passe par d'autres fils du daemon.
