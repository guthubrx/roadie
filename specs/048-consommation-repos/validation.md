# Validation - 048 Consommation au repos

Date : 18 octobre 2026. Branche : session-048-consommation-repos, base d32105c8.

## Mesures (constitution XXII)

Script : `specs/048-consommation-repos/mesures/mesure-repos.py`. Fenêtre de 120 s, inactivité
clavier/souris vérifiée au début et à la fin (≥ 60 s au départ), mêmes applications ouvertes.

| Mesure | CPU au repos | RSS | Fichier |
|---|---|---|---|
| Avant | 13,74 s / 120 s = 11,45 % d'un cœur | 112 Mo | `mesures/avant.json` |
| Après A-01 seul | 7,37 s = 6,14 % | 97 Mo | `mesures/apres-a01.json` |
| Après A-01, C-01, C-02, C-03 | 2,81 s = 2,34 % | 92 Mo | `mesures/apres.json` |

Baisse : 80 % du CPU au repos. Décision : conserver.

Limites :
- Les échantillons de pile suivent la fenêtre CPU. Ceux de `apres-a01` (10 s) et `apres` (30 s,
  `sample_idle = false`) contiennent une activité utilisateur : leurs compteurs ne sont pas
  comparables à `avant`. Seule observation nette : aucune énumération ScreenCaptureKit en 30 s
  après correction, contre 298 échantillons en 10 s avant.
- Le CPU au repos dépend des applications ouvertes ; les trois mesures ont été prises le même jour,
  à moins de 30 min d'écart.
- La version mesurée « après » précède les corrections de revue (doublon de dictionnaire, statut
  d'enregistrement extrait en fonction testable) ; elles ne changent pas le chemin au repos.

## Tests

- Rouge A-01 : compilation des tests 048 en échec avant implémentation.
- C-01, C-03 : tests écrits après le code pendant l'attente de mesure ; mutation (énumération
  toujours demandée, redessin toujours demandé) : 3 échecs ; code restauré.
- Suite complète finale : 1 721 tests / 203 suites, verts.

## Revues

Plan : Claude Haiku 5.5 via Bridget (Codex non routable : `routing_candidate_unavailable`).
BLOCKED sur A-01 initial ; corrections retenues : réutilisation activée seulement par le tiler
avec événements en direct, plafond égal au filet (2 s), ADR 015 amendant 013.

Implémentation : Claude Haiku 5.5, APPROVE_WITH_CHANGES.

| Objection | Vérifiée comment | Retenue | Suite |
|---|---|---|---|
| `uniqueKeysWithValues` peut planter sur un doublon | Membres concaténés sur plusieurs écrans | Oui | `uniquingKeysWith` |
| ADR 009 et 013 sans renvoi | Lecture | Oui | Renvois ajoutés |
| Focus-souris sur relevé de 2 s | Par construction | Oui | Limite dans ADR 015 |
| Capture vide garde la fenêtre en cache | Une réénumération ne change rien | Non | Documenté dans ADR 015 |
| Pas de test du statut d'enregistrement | Lecture | Oui | `RailController.recordingStatus` testé |
| `members` ne sert qu'aux tests | Utilisé par `RailPanel.refreshThumbnails` | Non | - |

## Installation

Release installée et redémarrée : UUID 67949B8A-50F8-3684-8D84-A656F055CEDD, PID 50740,
signature `roadied-cert`, quatre contrôles santé OK.

Non vérifié visuellement : suivi de la bordure au changement de focus, rafraîchissement des
vignettes et indicateur d'enregistrement (couverts par tests).

## Audit V15

Session : `audits/2026-10-18/session-2026-10-18-048-consommation-repos-01/` (mode fix, 1 cycle
puis revue readonly, `independent=false`). Décision calculée : **inconclusive**,
`release_blocked = true`, 12 contrôles vérifiés sur 13. Cause unique : analyse Gitleaks de tout
l'historique Git interrompue deux fois à la limite de 300 s du runner. Semgrep, Gitleaks
(fichiers), OSV : aucun constat. Suite complète : 1 721 tests, révisions 0 et 1.

Corrections de l'audit : statut d'enregistrement remis à zéro à l'arrêt du rail ; plan,
tâches et recherche alignés sur le plafond de 2 s.

Constat MEDIUM « le rail redécode `stages.json` chaque seconde » réfuté :
`JSONPersistence` garde la valeur décodée par chemin et par processus et la revalide par
signature (`Sources/RoadieDaemon/JSONPersistence.swift:12`, `:211-216`). Le fichier inchangé est
ouvert et lu par `fstat`, pas relu ni décodé. Constat voisin (poignées, `DividerResizeRuntime`) :
même mécanisme, même réfutation ; hors périmètre de la 048.

Échantillons de pile bruts : `~/.roadies/diagnostics/2026-10-18-session048/`, empreintes dans
`mesures/echantillons.sha256`.
