#!/usr/bin/env bash
# uninstall.sh — désinstallation propre de roadie (V1 ou V2).
# Idempotent : tourne sans erreur même si certains artefacts sont déjà absents.

set -uo pipefail

echo "==> stop running instances"
launchctl bootout "gui/$(id -u)/com.roadie.roadie"      2>/dev/null || true
launchctl bootout "gui/$(id -u)/com.roadie.roadie-rail" 2>/dev/null || true  # héritage V1
pkill -f roadied      2>/dev/null || true
pkill -f roadie-rail  2>/dev/null || true  # héritage V1
pkill -f "roadie events" 2>/dev/null || true
sleep 1

echo "==> remove app bundles"
[[ -d "$HOME/Applications/roadied.app" ]]    && rm -rf "$HOME/Applications/roadied.app"    && echo "    removed ~/Applications/roadied.app"
[[ -d "$HOME/Applications/roadie-rail.app" ]] && rm -rf "$HOME/Applications/roadie-rail.app" && echo "    removed ~/Applications/roadie-rail.app"

echo "==> remove CLI binaries / symlinks"
for f in "$HOME/.local/bin/roadie" "$HOME/.local/bin/roadied" "$HOME/.local/bin/roadie-rail"; do
  [[ -e "$f" || -L "$f" ]] && rm -f "$f" && echo "    removed $f"
done

echo "==> remove launchd plists"
[[ -f "$HOME/Library/LaunchAgents/com.roadie.roadie.plist" ]]      && rm -f "$HOME/Library/LaunchAgents/com.roadie.roadie.plist"      && echo "    removed com.roadie.roadie.plist"
[[ -f "$HOME/Library/LaunchAgents/com.roadie.roadie-rail.plist" ]] && rm -f "$HOME/Library/LaunchAgents/com.roadie.roadie-rail.plist" && echo "    removed com.roadie.roadie-rail.plist (héritage V1)"

echo "==> remove runtime sockets / lockfiles"
rm -f "$HOME/.roadies/daemon.sock" 2>/dev/null
rm -f "$HOME/.roadies/rail.pid"    2>/dev/null

echo "==> reset TCC grants (best-effort, peut nécessiter sudo selon macOS)"
tccutil reset Accessibility com.roadie.roadied      >/dev/null 2>&1 || true
tccutil reset ScreenCapture com.roadie.roadied      >/dev/null 2>&1 || true
tccutil reset Accessibility com.roadie.roadie-rail  >/dev/null 2>&1 || true
tccutil reset ScreenCapture com.roadie.roadie-rail  >/dev/null 2>&1 || true

echo
echo "==> Données utilisateur PRÉSERVÉES (ne supprime pas les configs / stages persistés) :"
echo "    ~/.config/roadies/roadies.toml   (config TOML utilisateur)"
echo "    ~/.config/roadies/stages/         (stages persistés)"
echo "    ~/.local/state/roadies/daemon.log (logs JSON-lines)"
echo
echo "    Pour tout supprimer aussi : rm -rf ~/.config/roadies ~/.local/state/roadies"
echo
echo "Done."
