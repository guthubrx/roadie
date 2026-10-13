# Quickstart : vérifier les lettres dans T3 Code

1. Installer et relancer : `make install && make restart` (Roadie.app signée, voir mémoire projet).
2. Mettre T3 Code au premier plan, puis double Commande.
3. Attendu : des lettres sur les fils de la barre latérale, les boutons et le champ de saisie.
4. Lire la mesure :
   ```bash
   grep '"targets.app_scan"' ~/.roadies/events.jsonl | tail -3
   ```
   Attendu pour T3 Code : `isElectron=true`, `candidates` > 10, `retries` 1 ou 2 à la première session, 0 ensuite.
5. Contrôle natif : même geste dans Finder. Attendu : `isElectron=false`, `retries=0`.
6. Réglage : si `atMaxDepth` est grand et que des éléments visibles manquent, augmenter `max_depth` dans `~/.config/roadies/roadies.toml`. Si `stopReason=timeout`, augmenter `timeout_ms`.
