# Validation 083

## Diagnostic sur les données réelles
- Journaux `~/.roadies/events.jsonl`, `.1`, `.2` (20 au 25 octobre), comptés par type et par heure.
- Fenêtres neuves : neuf `window.scope_reconciled_to_physical_display` le 25 octobre, 0 à 3 s
  après l'apparition (exemple iTerm2 66328 : 35 ms). Stage du LG `7-restored-2` en mode `bsp`,
  relue dans `~/.roadies/stages.json` ; une fenêtre Finder ouverte en essai dans une stage
  `spatialBsp` s'est placée normalement, ce qui confirme la condition.
- T3 Code 223 : `layout_clamped` 817 → 840 toutes les 32 s environ (223 intervalles de 30 à
  120 s), cause `safety`, puis `layout_clamped_scope_repaired` de Chrome 31794.
- Émulateur 62824 : `layout_apply` `safety` toutes les 4 s, `external_geometry_snapped_to_layout_model`
  après chacune ; cadre réel 403 × 933 pour une cible de 673 × 934.
- AlDente 781 : membre de la stage « Perso » (pid 61329 vivant), absent du relevé ; 82
  `restore.unhide_all_failed` le 25 octobre.

## Tests
- Chaque test ajouté échoue sans sa correction et réussit avec elle :
  `newWindowOpenedOnAnotherDisplayStaysOnTheFocusedDisplay`, `identicalClampAfterExpiryBecomesLasting`,
  `acceptedThenRevertedFrameIsNotRewrittenByEverySafetyPass` (12 écritures sans, au plus 3 avec).
- `Spec083RetiredMembersTests` : membre retiré marqué fermé, membre d'un autre bureau conservé,
  une seule lecture par période de 30 s.
- Le délai des fenêtres neuves ne vaut que pour une fenêtre ouverte hors de l'écran de son scope
  et encore présente (sinon une passe de plus était armée, `schedulerRunsMaintainerBurstEndAtItsDeadline`).
- Suite complète `scripts/test --no-parallel` après rebase sur 078 : 2 006 tests / 269 suites
  réussis. En parallèle, seul `daemonListeningOnSocketIsUsedEvenWithoutPidFile` échoue (délai
  de socket sous charge, déjà connu) ; il réussit relancé seul.

## Installation et contrôle réel
- `make install && make restart` : santé 5/5, signature `roadied-cert`, configuration
  `~/.config/roadies/roadies.toml` identique à sa copie d'avant installation.
- Une seconde après le démarrage : `window.retired_members_closed` (781), puis
  `windows.missing_reconciled` marque 781 absente ; la stage Perso la retirera après le délai.

## Limites
- Revue indépendante non admise : Bridget a refusé deux demandes (`origin_request_invalid`).
  Relecture du diff faite par le responsable.
- Preuves visuelles non produites : les trois autres défauts dépendent de conditions réelles
  (stage bsp, fenêtre ouverte par macOS sur l'autre écran, émulateur actif) non reproductibles
  sur commande, et les captures montreraient des contenus privés. Vérification par les tests
  qui échouent sans correction et par les journaux après installation.
- Après un redémarrage, la mémoire des refus est vide : une fenêtre peut encore bouger une ou
  deux fois avant que le refus devienne durable.
