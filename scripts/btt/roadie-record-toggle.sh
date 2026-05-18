#!/usr/bin/env zsh
set -euo pipefail

project="/path/to/roadie"
state_dir="${TMPDIR:-/tmp}/roadie-record-toggle"
pid_file="$state_dir/pid"
stop_file="$state_dir/stop"
name_file="$state_dir/name"
log_file="/tmp/roadie-record-toggle.log"

mkdir -p "$state_dir"

if [[ -s "$pid_file" ]]; then
  pid="$(cat "$pid_file" 2>/dev/null || true)"
  if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
    : > "$stop_file"
    exit 0
  fi
fi

rm -f "$stop_file"
name="btt-$(date +%Y%m%d-%H%M%S)"
print -r -- "$name" > "$name_file"

(
  cd "$project"
  PATH="/opt/homebrew/bin:$HOME/.local/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
  ./scripts/roadie record start "$name" --duration 3600 --stop-file "$stop_file"
) >> "$log_file" 2>&1 &

print -r -- "$!" > "$pid_file"
