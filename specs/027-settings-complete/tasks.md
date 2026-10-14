# Tâches — session 027

- [x] T001 Clôturer la session 026 validée, préparer la branche et le diagnostic.
- [x] T002 Fixer le contrat des collections et les garanties d'édition.
- [x] T003 Implémenter la lecture, l'écriture et le catalogue des douze entrées.
- [x] T004 Appliquer les champs valides pendant la saisie et fournir les éditeurs.
- [x] T005 Appliquer les changements effectifs au daemon et au tuilage.
- [x] T006 Ajouter les familles de police Caps+F et leur changement immédiat.
- [x] T007 Intégrer, tester, inspecter les rendus et traiter la revue.
- [x] T008 Installer, redémarrer et vérifier la santé.
- [x] T009 Recueillir le test manuel, documenter, committer et fusionner.

## Point de validation

T007 : 1 440 tests dans 154 suites passent en 6,943 s, dont le transport IPC réel,
les gardes de redimensionnement, les transitions entre stages et la validation
sémantique des règles. Vingt rendus hors écran sont inspectés. Les constats des
trois premières revues sont traités. Le scénario du tour 4 est reproduit, corrigé
et testé dans les deux moteurs, avec reprise au retour et borne conservée.

T008 : version finale installée et redémarrée, PID 47508, quatre contrôles de
santé OK. Certificat et permissions macOS conservés.
T009 : test utilisateur confirmé (« Oui, tout fonctionne »). Commit `6190f4de`
fusionné dans `main`, branches 026 et 027 supprimées. Le worktree de cette
conversation est conservé, avec sa branche 025 alignée sur `main`.

## Suivi de publication demandé après clôture

- [x] T010 Publier v0.5.0, actualiser les README et les guides, réécrire les notes
  0.4.0, vérifier le DMG et contrôler les notes et fichiers publiés sur GitHub.

La publication et ses preuves sont consignées dans release-0.5.0.md.
