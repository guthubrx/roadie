# Quickstart : valider la stabilisation

## Automatique

```bash
./scripts/with-xcode swift build
./scripts/test
grep -rn "/Users/" Sources scripts   # doit être vide
./bin/roadie --help; echo $?          # 0
./bin/roadie --version
```

## Manuel (bureau réel)

1. **Stage à une fenêtre** : stage avec un Terminal seul, ouvrir un second Terminal → les deux sont tilés, aucune bordure `maximized` dans le rail.
2. **Plein écran natif** : passer Safari en plein écran natif sur l'écran 1, ouvrir une fenêtre sur l'écran 2 → elle est tilée.
3. **Application gelée** : `kill -STOP <pid>` d'une app, puis `roadie focus left` et survol du rail → réponse en moins d'1 s. `kill -CONT <pid>` ensuite.
4. **Arrêt** : stage 2 masquée, `make stop` → toutes les fenêtres reviennent à l'écran. Idem après `kill -9` du daemon (restore-watch).
5. **Récupération** : `roadie restore unhide-all`.
6. **Redimensionnement par bord** : tirer lentement le bord droit d'une fenêtre pendant 3 s → aucun saut avant le relâchement.
7. **Focus système** : fermer la dernière fenêtre d'une app dont une autre fenêtre est dans une stage cachée → la stage active ne change pas.
8. **Config** : ajouter `gap_innner = 4` → `roadie config validate` nomme la clé et suggère `gaps_inner` ; le daemon garde la config précédente si le TOML est cassé.
9. **Doctor** : `roadie doctor` affiche daemon, Accessibility, Screen Recording, config.
10. **Deux daemons** : lancer `roadied run --yes` deux fois → le second refuse.
11. **Désinstallation** : `make uninstall` → fenêtres restaurées, LaunchAgent retiré.
