#!/usr/bin/env bash
# Installateur 1-clic / 1-ligne de Roadie pour macOS 14+ (Spec 166, sans notarisation Apple).
#
# Exemple distant :
#   curl -fsSL https://raw.githubusercontent.com/guthubrx/roadie/main/scripts/install-release.sh | bash
# Exemple local depuis un DMG :
#   ./scripts/install-release.sh --dmg dist/Roadie.dmg --preset standard
set -euo pipefail

repo="guthubrx/roadie"
version="latest"
dmg_local=""
preset="standard"
install_dir="$HOME/Applications"
bin_dir="$HOME/.local/bin"
no_start=0
dry_run=0

usage() {
  cat <<'EOF'
Usage: install-release.sh [options]

Options:
  --version <latest|vX.Y.Z>      Version GitHub Release à installer (défaut : latest)
  --dmg <chemin/Roadie.dmg>      Installer depuis un DMG local au lieu de télécharger
  --repo <owner/repo>            Dépôt GitHub (défaut : guthubrx/roadie)
  --preset <standard|vim|minimal|none>
                                 Préréglage de raccourcis autonomes si config.toml est absent (défaut : standard)
  --install-dir <dossier>        Dossier cible pour Roadie.app (défaut : ~/Applications)
  --bin-dir <dossier>            Dossier cible pour la CLI roadie (défaut : ~/.local/bin)
  --no-start                     Installer sans démarrer le LaunchAgent
  --dry-run                      Afficher le plan d'installation sans modifier le système
  -h, --help                     Afficher cette aide
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version)
      [[ $# -ge 2 ]] || { echo "Option --version incomplète." >&2; exit 64; }
      version="$2"; shift 2 ;;
    --dmg)
      [[ $# -ge 2 ]] || { echo "Option --dmg incomplète." >&2; exit 64; }
      dmg_local="$2"; shift 2 ;;
    --repo)
      [[ $# -ge 2 ]] || { echo "Option --repo incomplète." >&2; exit 64; }
      repo="$2"; shift 2 ;;
    --preset)
      [[ $# -ge 2 ]] || { echo "Option --preset incomplète." >&2; exit 64; }
      preset="$2"; shift 2 ;;
    --install-dir)
      [[ $# -ge 2 ]] || { echo "Option --install-dir incomplète." >&2; exit 64; }
      install_dir="$2"; shift 2 ;;
    --bin-dir)
      [[ $# -ge 2 ]] || { echo "Option --bin-dir incomplète." >&2; exit 64; }
      bin_dir="$2"; shift 2 ;;
    --no-start)
      no_start=1; shift ;;
    --dry-run)
      dry_run=1; shift ;;
    -h|--help)
      usage; exit 0 ;;
    *)
      echo "Option inconnue : $1" >&2
      usage >&2
      exit 64 ;;
  esac
done

case "$preset" in
  standard|vim|minimal|none) ;;
  *)
    echo "Préréglage invalide : $preset (attendu : standard, vim, minimal ou none)." >&2
    exit 64 ;;
esac

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "Roadie fonctionne uniquement sur macOS 14 ou plus récent." >&2
  exit 1
fi

macos_major="$(sw_vers -productVersion | awk -F. '{print $1}')"
if [[ -z "$macos_major" || "$macos_major" -lt 14 ]]; then
  echo "macOS 14 (Sonoma) ou plus récent est requis (détecté : $(sw_vers -productVersion))." >&2
  exit 1
fi

if [[ "$version" == "latest" ]]; then
  dmg_url="https://github.com/$repo/releases/latest/download/Roadie.dmg"
  sha_url="https://github.com/$repo/releases/latest/download/Roadie.dmg.sha256"
else
  tag="${version#v}"
  dmg_url="https://github.com/$repo/releases/download/v$tag/Roadie.dmg"
  sha_url="https://github.com/$repo/releases/download/v$tag/Roadie.dmg.sha256"
fi

app_target="$install_dir/Roadie.app"
cli_target="$bin_dir/roadie"
daemon_link="$bin_dir/roadied"
config_file="$HOME/.config/roadie/config.toml"
plist_file="$HOME/Library/LaunchAgents/com.roadie.roadied.plist"
log_dir="$HOME/.roadies"

if [[ "$dry_run" -eq 1 ]]; then
  echo "[dry-run] macOS $(sw_vers -productVersion) ($(uname -m))"
  if [[ -n "$dmg_local" ]]; then
    echo "[dry-run] source DMG local : $dmg_local"
  else
    echo "[dry-run] téléchargement : $dmg_url"
    echo "[dry-run] vérification SHA-256 : $sha_url"
  fi
  echo "[dry-run] application : $app_target (xattr -dr com.apple.quarantine)"
  echo "[dry-run] CLI : $cli_target et lien $daemon_link"
  echo "[dry-run] configuration : $config_file (init preset=$preset seulement si absent)"
  echo "[dry-run] LaunchAgent : $plist_file (start=$([[ "$no_start" -eq 0 ]] && echo yes || echo no))"
  exit 0
fi

tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/roadie-install.XXXXXX")"
mount_point="$tmp_dir/mount"
cleanup() {
  if mount | grep -Fq "on $mount_point "; then
    hdiutil detach "$mount_point" -quiet >/dev/null 2>&1 || true
  fi
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

dmg_path=""
if [[ -n "$dmg_local" ]]; then
  [[ -f "$dmg_local" ]] || { echo "DMG introuvable : $dmg_local" >&2; exit 1; }
  dmg_path="$dmg_local"
  if [[ -f "$dmg_local.sha256" ]]; then
    expected_sha="$(awk '{print $1}' "$dmg_local.sha256")"
    actual_sha="$(shasum -a 256 "$dmg_path" | awk '{print $1}')"
    if [[ "$expected_sha" != "$actual_sha" ]]; then
      echo "Empreinte SHA-256 invalide pour $dmg_path (attendu $expected_sha, obtenu $actual_sha)." >&2
      exit 1
    fi
  fi
else
  dmg_path="$tmp_dir/Roadie.dmg"
  sha_path="$tmp_dir/Roadie.dmg.sha256"
  echo "Téléchargement de Roadie ($version) depuis $repo..."
  curl -fsSL "$dmg_url" -o "$dmg_path"
  curl -fsSL "$sha_url" -o "$sha_path"
  expected_sha="$(awk '{print $1}' "$sha_path")"
  actual_sha="$(shasum -a 256 "$dmg_path" | awk '{print $1}')"
  if [[ -z "$expected_sha" || "$expected_sha" != "$actual_sha" ]]; then
    echo "Vérification SHA-256 échouée (attendu $expected_sha, obtenu $actual_sha)." >&2
    exit 1
  fi
  echo "Empreinte SHA-256 vérifiée ($actual_sha)."
fi

mkdir -p "$mount_point" "$install_dir" "$bin_dir" "$HOME/Library/LaunchAgents" "$log_dir"
hdiutil attach "$dmg_path" -nobrowse -readonly -mountpoint "$mount_point" -quiet

source_app="$mount_point/Roadie.app"
[[ -d "$source_app" ]] || { echo "Roadie.app introuvable dans le DMG." >&2; exit 1; }

tmp_app="$app_target.tmp"
rm -rf "$tmp_app"
ditto "$source_app" "$tmp_app"
# Build non notarisé par Apple : suppression explicite de la quarantaine locale.
xattr -dr com.apple.quarantine "$tmp_app" >/dev/null 2>&1 || true
rm -rf "$app_target"
mv "$tmp_app" "$app_target"

source_cli="$app_target/Contents/Resources/roadie"
if [[ -x "$source_cli" ]]; then
  ln -sfn "$source_cli" "$cli_target"
fi
ln -sfn "$app_target/Contents/MacOS/roadied" "$daemon_link"

if [[ ! -f "$config_file" ]] && [[ -x "$cli_target" ]]; then
  echo "Initialisation de $config_file (préréglage : $preset)..."
  "$cli_target" config init --preset "$preset"
else
  echo "Configuration existante conservée : $config_file"
fi

cat > "$plist_file" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>com.roadie.roadied</string>
  <key>ProgramArguments</key>
  <array>
    <string>$app_target/Contents/MacOS/roadied</string>
    <string>run</string>
    <string>--yes</string>
  </array>
  <key>WorkingDirectory</key>
  <string>$HOME</string>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>StandardOutPath</key>
  <string>$log_dir/roadied.stdout.log</string>
  <key>StandardErrorPath</key>
  <string>$log_dir/roadied.stderr.log</string>
</dict>
</plist>
PLIST

if [[ "$no_start" -eq 0 ]]; then
  uid="$(id -u)"
  launchctl bootout "gui/$uid/com.roadie.roadied" >/dev/null 2>&1 || true
  launchctl bootstrap "gui/$uid" "$plist_file" >/dev/null 2>&1 || true
  launchctl kickstart -k "gui/$uid/com.roadie.roadied" >/dev/null 2>&1 || true
fi

echo ""
echo "Roadie installé avec succès :"
echo "  Application : $app_target"
echo "  CLI         : $cli_target"
echo "  LaunchAgent : $plist_file"
echo ""
echo "Étapes suivantes :"
echo "  1. Ajoutez $bin_dir à votre PATH si nécessaire."
echo "  2. Accordez Accessibilité à Roadie dans Réglages Système > Confidentialité et sécurité > Accessibilité."
echo "  3. Vérifiez l'état : $cli_target daemon health"
