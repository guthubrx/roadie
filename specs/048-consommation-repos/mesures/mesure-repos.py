#!/usr/bin/env python3
"""Mesure du coût de roadied au repos (SPEC-048, constitution XXII).

Attend une inactivité clavier/souris d'au moins 60 s, mesure le temps CPU du daemon
pendant WINDOW secondes, puis échantillonne sa pile 30 s (`sample_idle` indique si
l'utilisateur est resté inactif pendant l'échantillon). Une fenêtre où l'utilisateur
a touché la machine est rejetée et recommencée. Sortie : JSON sur stdout.

Usage : mesure-repos.py <etiquette> [window_s] [max_wait_s]
"""
import json
import re
import subprocess
import sys
import time
from datetime import datetime, timezone

LABEL = sys.argv[1] if len(sys.argv) > 1 else "mesure"
WINDOW = int(sys.argv[2]) if len(sys.argv) > 2 else 120
MAX_WAIT = int(sys.argv[3]) if len(sys.argv) > 3 else 3600
MIN_IDLE = 60
FRAMES = {
    "releve_ax_complet": "LiveSystemSnapshotProvider.windows()",
    "bordure": "BorderController.refresh()",
    "rail_refresh": "RailController.rebuildPanels",
    "screencapturekit_enumeration": "SCShareableContent",
    "config_courante": "ConfigReloadService.currentConfig()",
    "focus_souris": "FocusFollowsMouseController.tick()",
}


def idle_seconds() -> float:
    out = subprocess.run(["ioreg", "-c", "IOHIDSystem"], capture_output=True, text=True).stdout
    match = re.search(r'"HIDIdleTime" = (\d+)', out)
    return int(match.group(1)) / 1e9 if match else 0.0


def daemon_pid() -> int:
    out = subprocess.run(["pgrep", "-f", "roadied run"], capture_output=True, text=True).stdout.split()
    return int(out[0])


def cpu_seconds(pid: int) -> float:
    raw = subprocess.run(["ps", "-o", "time=", "-p", str(pid)], capture_output=True, text=True).stdout.strip()
    parts = [float(p) for p in raw.replace("-", ":").split(":")]
    total = 0.0
    for value in parts:
        total = total * 60 + value
    return total


SAMPLE_S = 30


def sample_counts(pid: int) -> dict:
    path = f"/tmp/roadie-048-{LABEL}-sample.txt"
    idle_before = idle_seconds()
    subprocess.run(["sample", str(pid), str(SAMPLE_S), "-file", path], capture_output=True)
    sample_idle = idle_seconds() >= idle_before + SAMPLE_S - 2
    counts = {key: 0 for key in FRAMES}
    with open(path, encoding="utf-8", errors="replace") as handle:
        in_graph = False
        for line in handle:
            if line.startswith("Call graph:"):
                in_graph = True
                continue
            if line.startswith("Total number in stack"):
                break
            if not in_graph:
                continue
            match = re.match(r"^[\s+!:|]*(\d+)\s+(.*)$", line)
            if not match:
                continue
            frame = match.group(2)
            for key, needle in FRAMES.items():
                # Cadre exact (pas les fermetures internes) ; ObjC : préfixe +[/-[ de la classe.
                if frame.startswith(needle) or frame.startswith(("+[" + needle, "-[" + needle)):
                    counts[key] += int(match.group(1))
    return {"sample_file": path, "sample_s": SAMPLE_S, "sample_idle": sample_idle, "frames": counts}


def main() -> None:
    deadline = time.time() + MAX_WAIT
    attempts = 0
    while time.time() < deadline:
        if idle_seconds() < MIN_IDLE:
            time.sleep(5)
            continue
        attempts += 1
        pid = daemon_pid()
        idle_start = idle_seconds()
        cpu_start = cpu_seconds(pid)
        time.sleep(WINDOW)
        cpu_end = cpu_seconds(pid)
        idle_end = idle_seconds()
        if idle_end < idle_start + WINDOW - 2 or daemon_pid() != pid:
            continue  # saisie utilisateur ou redémarrage pendant la fenêtre : rejetée
        rss = int(subprocess.run(["ps", "-o", "rss=", "-p", str(pid)], capture_output=True, text=True).stdout.strip())
        result = {
            "label": LABEL,
            "captured_at": datetime.now(timezone.utc).isoformat(),
            "pid": pid,
            "window_s": WINDOW,
            "idle_at_start_s": round(idle_start, 1),
            "cpu_s": round(cpu_end - cpu_start, 2),
            "cpu_percent_of_core": round(100 * (cpu_end - cpu_start) / WINDOW, 2),
            "rss_kb": rss,
            "rejected_windows": attempts - 1,
        }
        result.update(sample_counts(pid))
        print(json.dumps(result, ensure_ascii=False, indent=2))
        return
    print(json.dumps({"label": LABEL, "error": "pas de fenêtre de repos dans le délai", "attempts": attempts}))
    sys.exit(2)


if __name__ == "__main__":
    main()
