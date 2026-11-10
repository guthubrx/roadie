# Contre-revue adverse du plan - 155

- **Date** : 10 novembre 2026
- **Agent interrogé** : codex (fournisseur OpenAI), modèle `gpt-5.6-luna`, effort moyen
- **Canal** : Bridget, délégation automatique, vue en lecture seule du commit
  `8a5c76eeac1c3704747ff8719dc8d972eee29765`
- **Moment** : après la phase Plan, avant `tasks.md`
- **Verdict reçu** : `BLOCKED`
- **Décision du responsable** : verdict non suivi. Son objection bloquante est fausse
  (objection 1). Six objections sur dix sont retenues et corrigées, dont une en partie.

La réponse d'un autre agent est une hypothèse. Chaque objection a été vérifiée contre le
code, un essai ou un fichier avant toute correction.

## Essais

| Essai | Identifiant de demande | Résultat |
|-------|------------------------|----------|
| 01 | `roadie-155-contre-revue-plan-20261110-01` | Non admis : `routing_candidate_unavailable` / `command_execution_unavailable` (dossier partagé + posture de découverte). Incident signalé. |
| 02 | `roadie-155-contre-revue-plan-20261110-02` | Tâche `173b8a7c-32f0-4bde-a2ee-83c7dacedabe`. `BLOCKED` sans objection : la demande interdisait « toute commande », donc aussi la lecture. Erreur de rédaction du demandeur. |
| 03 | `roadie-155-contre-revue-plan-20261110-03` | Tâche `1cfc9838-ed51-44ff-a39d-6da6c5fac2e4`, message `f8c2f00d-0523-4cbe-b7c7-d08a3028ecd7`. `BLOCKED`, dix objections. |

Aucun quatrième essai : la règle de coordination arrête la boucle après deux échanges sans
résultat nouveau, et l'essai 03 a donné un résultat exploitable.

## Question posée (essai 03)

La demande donnait la liste des fichiers à lire (spec, plan, décisions, recherche, modèle de
données, contrats, outils, gabarits et code visé) et sept questions :

1. Défauts logiques : un remplacement ou un gabarit produit-il un code faux, fragile en
   Swift 6 strict, ou contraire à `spec.md` ?
2. Sécurité et concurrence : `gabarits/ReleaseCheck.swift` et les deux gardes `CFGetTypeID`
   de T019 et T020 sont-ils corrects ?
3. Scripts : T009, T010 et `gabarits/coverage` ont-ils un défaut de shell ?
4. Outils : `appliquer.py`, `deplacer_journal.py` et `extraire_fournisseur.py` peuvent-ils
   écrire un résultat partiel ou faux sans le signaler ?
5. Trous de couverture : quelle exigence ou quel critère n'a ni changement ni contrôle ?
6. Pour un modèle moins capable : quelle étape reste ambiguë ?
7. Minimalisme : quel changement est superflu ?

Interdits donnés à l'agent : ne rien écrire, ne rien committer, ne lancer ni build ni test
ni script, aucun appel réseau, aucune dépense, aucune délégation. Borne de temps : 20 minutes.

## Objections

| # | Objection | Vérifiée comment | Retenue | Raison |
|---|-----------|------------------|---------|--------|
| 1 | `LayoutMaintainer.swift` est absent : la tâche T033 est impossible. (Bloquante selon l'agent.) | `git ls-tree 8a5c76ee Sources/RoadieDaemon/LayoutMaintainer.swift` : le fichier existe (4 462 lignes). T033 rejouée sur copie : 69 lignes déplacées, 4 392 restantes. | non | Fausse. Le fichier existe dans le commit. Le verdict `BLOCKED` repose sur elle. |
| 2 | Le marqueur d'idempotence d'`appliquer.py` peut masquer un changement fait à moitié. Les écritures ne sont pas atomiques. | Lecture de `tools/appliquer.py`, puis essai : un changement à moitié présent passait pour « déjà fait ». | oui | Corrigé : l'outil compare le texte ajouté et s'arrête si le changement est incomplet. Chaque fichier est écrit à côté, puis mis en place d'un coup. |
| 3 | `deplacer_journal.py --check --root` lit Git dans le dépôt de l'outil, pas dans la copie. | Lecture du code : le contrôle lit le fichier du commit de base, qui ne change pas. | non | Le commit de base est immuable : le résultat est le même. Un commentaire l'explique. |
| 4 | Le déplacement du journal écrit deux fichiers sans garantie d'atomicité. | Lecture du code. | oui | Corrigé : écriture à côté, puis mise en place. |
| 5 | Le suffixe `-dirty` ignore les fichiers non suivis (`git diff` ne les voit pas). | Essai : un fichier neuf non suivi ne donnait pas `-dirty`. | oui | Corrigé : `git status --porcelain`. Contrat, recherche et modèle de données alignés. Scripts revalidés (`bash -n`, 28 tests de scripts). |
| 6 | `trimmingCharacters` retire la lettre `v` aux deux bouts du numéro de version. | Lecture de `gabarits/ReleaseCheck.swift`. | oui | Corrigé : seul le préfixe `v` est retiré. Une attente de test le prouve (`0.13.5v`). |
| 7 | Le garde-fou des réglages ne couvre pas tous les cas (tableaux, valeurs absentes de la configuration par défaut). | Relecture de FR-009 et du test. | non | FR-009 vise la configuration par défaut. La limite est écrite dans `research.md` (R6). |
| 8 | Les tests de `ReleaseCheck` n'appellent pas le réseau ; il faudrait un transport injectable. | Relecture de l'Article XIX de la constitution. | non | Une abstraction pour un seul usage est interdite. L'appel réel est fait une fois en T040. La limite figure dans « Non vérifié ». |
| 9 | Les tests de complétion sont faibles : ils ne prouvent pas que toutes les commandes sont listées. | Lecture du gabarit de test. | oui, en partie | Ajout d'une égalité d'ensemble entre le script et la table des commandes. Le comportement interactif de Tab reste non testé. |
| 10 | `extraire_fournisseur.py` écrit deux fichiers sans atomicité. | Lecture du code. | oui | Corrigé : écriture à côté, puis mise en place. |

L'agent a aussi confirmé trois points sans objection : les gardes de T019 et T020 sont
correctes, `ResultBox` est protégé, l'attente réseau est bornée.

## Après les corrections

- `./scripts/test --no-parallel --filter Spec155` : 15 tests / 4 suites réussis.
- `./scripts/test --no-parallel` : 2 538 tests / 387 suites réussis, code 0.
- `python3 -I -B -m unittest discover -s scripts/tests` sur une copie avec T009 et T010 : 28 tests, `OK`.

## Limites

- Les corrections n'ont pas été relues par un second agent.
- L'agent n'a lancé ni build, ni test, ni script : ses objections viennent de la lecture seule.
- Le comportement interactif de la complétion et l'appel réseau réel ne sont couverts par
  aucun test automatique.

## Incidents Bridget signalés au mainteneur

| Incident | Reçu |
|----------|------|
| Budget de sortie de `bridget_who` | `912a30ac-964c-4be0-b316-659e51a97101` (enregistré sans réveil) |
| Refus d'admission de l'essai 01 | `mcp-42476-6af31ff4-1` (enregistré sans réveil) |
