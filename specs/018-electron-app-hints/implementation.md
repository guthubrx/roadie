# Journal d'Implémentation - Lettres d'accès dans les applications Electron

## Métadonnées
- **Spec** : 018-electron-app-hints
- **Branche** : 018-electron-app-hints (worktree `.worktrees/018-electron-app-hints`)
- **Démarré** : 2026-10-12
- **Terminé** : 2026-10-13

## Preuve initiale

`~/.roadies/events.jsonl`, 2026-10-12 18:37 UTC, T3 Code (pid 60116) : une seule cible applicative, `app:60116/0` (la fenêtre), `partial=false`.

## Mesures réelles (événement `targets.app_scan`, 2026-10-12)

| Moment | Application | Réglage | Résultat |
|---|---|---|---|
| 21:01:24Z | Firefox (témoin) | depth 8, 120 ms | `skipped`/`unsupported`, 1 élément lu, 0 relance, 2 ms |
| 21:01:36Z | T3 Code, juste après la 1re demande | depth 8, 120 ms | 4 candidats, 13 lus, profondeur 6, complet, 0 relance (règle v1 « ≤ 1 candidat » ratée) |
| 21:01:48Z | T3 Code | depth 8, 120 ms | 5 candidats, profondeur 8 atteinte, 1 élément non exploré |
| 21:02:09Z | T3 Code | depth 30, 120 ms | 87 candidats, profondeur 15, `timeout` à 122 ms, 215 lus (~0,6 ms par élément) |
| 21:02:21Z | T3 Code | depth 30, 400 ms | 150 candidats (`limit`), profondeur 18, 178 ms |
| 21:06:42Z | draw.io, 1re demande | depth 30, 400 ms | zone web absente, 2 relances, 452 ms |
| 21:06:50Z | draw.io, 8 s après | depth 30, 400 ms | 138 candidats, zone web, 119 ms, 0 relance |
| série | draw.io relancé, attente 10 s, 1re demande | idem | zone web absente à t0 ; présente à t0 + 2,9 s (2e demande) |
| série | draw.io, demandes toutes les ~0,8 s | idem | zone web absente jusqu'à 4,6 s au moins |
| série | draw.io, demande à l'activation au lancement puis aucune redemande | idem | zone web absente à 3, 6, 10 et 15 s |
| final | T3 Code | depth 30, 250 ms | 150 candidats (`limit`), 125 ms, 0 relance |
| final | Finder | depth 30, 250 ms | `skipped`, 58 candidats, `timeout` à 253 ms, 0 relance |

## Progression

### T001-T002 : politique de relance et détection Electron
- **Statut** : ✅ Complété. Règle corrigée après mesure : `isElectron && !sawWebArea && exploredFully && retries < 2`.
- **Tests** : `AppTargetQueryServiceTests` OK.

### T003 : demande de publication et relance
- **Statut** : ✅ Complété. Demande `AXManualAccessibility` à chaque parcours d'une application Electron, délai AX 0,5 s. Lecture préalable retirée : T3 Code répond « inactif » à la lecture même une fois actif.
- **Tentative retirée (disjoncteur, Article IV)** : demande à l'activation de l'application + une seule demande par processus. Mesure : une demande faite au lancement de draw.io n'a jamais pris effet (15 s), et l'absence de redemande bloquait l'application. Régression mesurée, gain non mesuré : code retiré.

### T004-T005 : filtre visible
- **Statut** : ✅ Complété. `offscreen=0` dans toutes les mesures T3 Code (liste virtualisée).

### T006-T008 : événement `targets.app_scan`
- **Statut** : ✅ Complété. Test `appScanStatisticsAreLoggedOnlyWhenTheProviderReportsThem`.

### T009 : documentation FR/EN
- **Statut** : ✅ Complété, corrigée après mesure (première session).

### T010 : suite complète
- **Statut** : ✅ 810 tests Swift Testing OK, build OK (avant la correction de règle ; relancée en Phase 7).

### T011 : installation et mesure
- **Statut** : ✅ Mesures ci-dessus. SC-001 atteint (150 cibles contre 1). SC-003 atteint (natif : 0 relance, durée dans le budget). SC-002 : validé par l'utilisateur le 2026-10-13 (la lettre d'un fil de la barre latérale ouvre ce fil).
- **Limite mesurée** : la toute première session après le lancement d'une application Electron peut ne montrer que la fenêtre. Le délai de publication observé sur draw.io va de moins de 3 s à plus de 15 s. SC-004 (première session) non atteint pour ce cas.

### T012 : réglage de la configuration utilisateur
- **Statut** : ✅ `~/.config/roadies/roadies.toml` : `max_depth` 8 → 30 (profondeur réelle 15-18 dans T3 Code), `timeout_ms` 120 → 250 (T3 Code : 150 cibles en 119-178 ms ; 400 ms rallongeait Finder sans gain). Sauvegarde : `~/.config/roadies/roadies.toml.bak-018-*`.

### Contre-revue adverse (Codex GPT-6.1-Sol, round 2)
- **Verdict** : APPROVE_WITH_CHANGES. Retenues : cadre rogné à la partie visible (point de clic dans la fenêtre), échéance commune des relances, plan corrigé, contrat précisé. Détail : `adversarial-review-codex.md`.

### Convergence
- **Passage 1** : 1 tâche ajoutée (T013, écart AS1.1/SC-004). Décision utilisateur : limite acceptée, spec amendée.
- **Passage 2** : CONVERGED (toutes les exigences ont une preuve code, test ou mesure).

### Audit v14 (mode fix, 1 cycle)
- **Note** : A (99,7/100). Session : `audits/2026-10-12/session-2026-10-12-018-electron-app-hints-01/`.
- **Correction** : PERF-001 (rôles autorisés en `Set` hors boucle).
- **Ouverts (faible)** : REL-001 (une relance tardive peut remplacer une passe complète par une passe partielle, cas théorique), TEST-001 (compteurs et boucle de relance couverts par mesures seulement), QUAL-001 (chaînes libres pour `stopReason`), MIN-001 (décodeur de test à usage unique).

### T013 : première session
- **Statut** : ✅ Décision utilisateur 2026-10-13 : limite acceptée, AS1.1 et SC-004 amendés.
