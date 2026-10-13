# Contre-revue adverse - 018-electron-app-hints

- **Date** : 2026-10-12
- **Agent** : sous-agent T3 Codex, modèle GPT-6.1-Sol (effort medium), fournisseur OpenAI
- **Round 1** (plan) : annulé. Lancé en mode « approbation requise », bloqué sur la lecture d'un fichier ; aucune réponse.
- **Round 2** (plan + implémentation, lecture seule) : question sur la règle de relance, le filtre visible, le nouveau parcours, les régressions et le minimalisme.
- **Verdict** : APPROVE_WITH_CHANGES

| Objection | Vérifiée comment | Retenue | Raison |
|---|---|---|---|
| P1 : un élément à cheval passe le filtre, le clic vise le centre du cadre entier, hors fenêtre | lecture de `click` (centre de `frame`) et du test : fenêtre 100-500 × 100-400, élément 480-540 × 380-440, centre (510, 410) dehors | oui | cadre rogné à la partie visible (`visibleFrame`), test du point de clic |
| P2 : chaque relance reçoit un budget complet ; le surcoût total n'est pas borné | lecture du code ; mesure réelle à 1 064 ms le 2026-10-12 | oui | échéance commune `timeout_ms` + 300 ms |
| P2 : un appel AX synchrone lent dépasse le budget | lecture : contrôle du temps entre éléments seulement | noté | limite antérieure ; délai AX de la demande borné à 0,5 s ; documenté dans le commentaire |
| P3 : `atMaxDepth` compte les feuilles et peut empêcher une relance utile | lecture | non | cas d'un arbre déjà profond, donc publié ; pas d'effet mesuré |
| P3 : une fenêtre Electron sans zone web attend à chaque session | lecture | noté | borné par l'échéance commune ; cas non observé |
| Popover ou menu hors du cadre principal écarté | lecture | noté | conforme à FR-005 ; limite documentée |
| Sommeil sur le fil principal (`TargetModeRuntimeController.swift:131`) | lecture | noté | seulement dans le cas d'échec, borné à 300 ms ; le parcours était déjà synchrone |
| VS Code/Cursor : mode lecteur d'écran, CPU, attribut non remis à faux quand on coupe le boost | lecture | noté | non mesuré ; documenté comme risque |
| `plan.md` conserve des décisions abandonnées | lecture de `plan.md:12` | oui | plan corrigé |
| Compteurs de la dernière passe vs `elapsedMs` total | lecture | oui | précisé dans le contrat |
| Minimalisme : ~0 ligne de production suppressible | - | accord | - |
