# Contre-revue adverse - 020-cef-web-hints

- **Agent** : sous-agent T3 Codex, GPT-6.1-Sol (effort medium), fournisseur OpenAI, `runtimeMode: auto`
- **Données transmises** : artefacts de spec et code ; aucun relevé brut (données personnelles supprimées)

## Round 1 (plan) - 2026-10-13

**Verdict** : BLOCKED

| Objection | Vérifiée comment | Retenue | Raison |
|---|---|---|---|
| Les `AXGroup` sans action sont éliminés par `targets(from:)` | lecture `AppTargetQueryService.swift:146` (filtre rôle ou action) | oui | marqueur `isFocusableLeaf`, test « feuille jusqu'aux cibles finales » |
| Élément interrompu retiré de la pile avant l'arrêt | lecture du code implémenté | déjà traité | l'élément est remis dans la pile avant `break` |
| Descendant coupé à `max_depth` sous un ancêtre | lecture | oui | marqueur « inconnu » `path.?`, test |
| Erreur de lecture des enfants assimilée à « aucun enfant » | lecture `copyChildren` | oui | `unreadable` si `AXChildren` échoue hors `noValue`/`attributeUnsupported` |
| Alias boost et collisions `CFHash` | lecture | noté | comportement antérieur ; règle documentée comme heuristique |
| Focalisables hors fenêtre exclus des marqueurs | lecture | déjà traité | marqueurs ajoutés avant le filtre visible ; test |
| Priorité des cibles historiques à la limite (T3 Code) | lecture | oui | historiques d'abord, limite sur elles seules |
| Contrôle T3 Code trop faible | - | oui | T009 compare `stopReason`, `visited`, `elapsedMs` |
| Lettre en double sous une cible déjà retenue | lecture | oui | `inCandidate` le long de la pile |
| Élément décoratif sans mécanisme | lecture de la spec | oui | cas limite reformulé (critère = focalisabilité) |
| Bluejay : condition macOS à la ligne 394 correcte | - | accord | - |

## Round 2 (implémentation) - 2026-10-13

**Verdict** : BLOCKED. Corrections du round 1 jugées correctes, sauf `inCandidate`.

| Objection | Vérifiée comment | Retenue | Raison |
|---|---|---|---|
| `inCandidate` propagé même si le parent n'a pas été ajouté (cadre illisible ou hors fenêtre) : feuille visible perdue | lecture `scan` : propagation sur `isCandidate` | oui | propagation sur `retained` (ajout effectif) |
| `rejectedRoles` oublie les candidats sans cadre visible | lecture : compteur sur `!isCandidate` | oui | compteur sur `!retained` |
| Tests de production des marqueurs | - | partiel | cas purs ajoutés (enfants illisibles, boost, interruption avant le premier enfant) ; production réelle vérifiée par mesure T009 |
| `stack.map(\.path)` suffit | lecture : pile vide après parcours complet | oui | condition retirée |
| Minimalisme ~0 ligne | - | accord | - |

## Round 3 (corrections du round 2) - 2026-10-13

**Verdict** : APPROVE. `retained` et le décompte `rejectedRoles` jugés justes.

## Round 4 (anti-doublon par comptage, boost hors zone web) - 2026-10-13

**Verdict** : BLOCKED

| Objection | Vérifiée comment | Retenue | Raison |
|---|---|---|---|
| Comptage par plus proche ancêtre : A ⊃ B ⊃ X et A ⊃ Y donne (X,B) et (Y,A), chacun à 1 : X et Y écartées, Y à tort | lecture `leavesKeptUnderCandidates` | oui | règle remplacée par une comparaison de surfaces locale |
| Parcours coupé : une seule feuille observée sous A n'en prouve pas une seule | lecture | oui | la nouvelle règle ne compte plus rien |
| Enfants accessibles seulement par un attribut boost en zone web | lecture `copyChildren` | noté | Chromium et WebKit exposent toujours `AXChildren` ; aucune perte observée ; limite documentée |
| Vue web intégrée à une app native : nouveau comportement | lecture | noté | voulu (règle « zone web ») |

## Round 5 (T012) - 2026-10-13

**Verdict** : BLOCKED. Objections du round 4 jugées levées.

| Objection | Vérifiée comment | Retenue | Raison |
|---|---|---|---|
| P1 : retrait des protections plein écran (`SystemSnapshotProvider`, `RestoreSafetyService`) et du zoom (`LayoutMaintainer`) | `git log 1bdd65e..main` : `675cb9f` d'une autre session ; `git diff merge-base` : la branche ne touche que 3 fichiers | non | artefact de comparaison avec un `main` qui a avancé ; résolu par rebase |
| P2 : élaguer sous 4 points peut cacher un enfant qui déborde | essai : descente dans les éléments fins, élagage seulement si caché | non (après essai) | régression mesurée : plus aucune lettre sur les cartes de Bluejay (validation utilisateur) ; retour à la version validée ; limite documentée dans le code |
| P2 : `retainedFrame` n'enveloppe pas forcément la feuille (cible dans un coin) | lecture, contre-exemple 10×10 dans 80×80 | oui | recouvrement exigé dans les deux sens (≥ 80 % de chaque surface), test ajouté |
| `CFIdentitySet` : test sans collision | audit 02 TEST-001 | oui (audit) | paire de `CFString` de même hash ajoutée |
