# Quickstart : vérifier les lettres dans Bluejay

1. Construire Bluejay avec `pr/029-macos-renderer-accessibility` (`build-bluejay-with-prs.sh`, voir `AGENTS.md` du dépôt Grayjay), puis lancer Bluejay depuis le Dock.
2. Vérifier l'option : `ps -o args= -p $(pgrep -f 'BlueJay.app/Contents/MacOS/dotcefnative' | head -1) | grep -o force-renderer-accessibility`
3. Installer Roadie (`make install && make restart`), Bluejay au premier plan, double Commande.
4. Attendu : lettres sur les entrées de la barre latérale et les cartes vidéo ; `grep '"targets.app_scan"' ~/.roadies/events.jsonl | tail -1` donne `sawWebArea=true`, `candidates` ≥ 20, `focusableAdded` > 0.
5. Contrôles : Finder et T3 Code, `candidates` inchangé (58 et 150).
