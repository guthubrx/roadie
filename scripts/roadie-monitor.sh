#!/usr/bin/env bash
# roadie-monitor.sh — observabilité auto-pilotée du daemon roadied.
#
# Parse ~/.local/state/roadies/daemon.log sur la fenêtre des 5 dernières
# minutes, calcule 5 métriques produit, compare à une baseline auto-apprise
# (médiane + 2*MAD sur les 6 derniers ticks de metrics-history.jsonl),
# émet un verdict JSON sur stdout et append au history.
#
# Sortie stdout (1 ligne JSON) :
#   {"tick":N,"ts":"...","metrics":{...},"baseline":{...},"anomaly":bool,
#    "axis":"...","reason":"...","anti_flap_ok":bool}
#
# Codes retour :
#   0 = tick OK ou anomalie détectée (cas normal)
#   2 = daemon log absent (probable daemon down)
#   3 = parsing impossible (logs corrompus)

set -uo pipefail
export LC_NUMERIC=C

DAEMON_LOG="${DAEMON_LOG:-$HOME/.local/state/roadies/daemon.log}"
HIST_FILE="${HIST_FILE:-$HOME/.local/state/roadies/metrics-history.jsonl}"
WINDOW_SECONDS="${WINDOW_SECONDS:-300}"  # 5 min

mkdir -p "$(dirname "$HIST_FILE")"
touch "$HIST_FILE"

if [ ! -f "$DAEMON_LOG" ]; then
    echo '{"error":"daemon_log_absent","path":"'"$DAEMON_LOG"'"}'
    exit 2
fi

python3 - "$DAEMON_LOG" "$HIST_FILE" "$WINDOW_SECONDS" <<'PY'
import json, sys, os, datetime, statistics

daemon_log = sys.argv[1]
hist_file = sys.argv[2]
window_s = int(sys.argv[3])

now = datetime.datetime.now(datetime.timezone.utc)
window_start = now - datetime.timedelta(seconds=window_s)

# Whitelist messages warn benins (bruit normal au boot ou transient).
# /skill-improve étendra cette liste au fil des cycles.
WARN_WHITELIST = {
    "deprecated_active_toml_present",  # corrigé mais filet de secours
    "migration_v1v2_dst_already_populated_v1_backed_up",  # boot transient
}

errors_5m = 0
warns_5m_filtered = 0
drifts_5m = 0
boot_health_last = None
applyall_starts = []
applyall_durations_ms = []
# SPEC-025 amend — métriques observabilité point-mort (gestures + rail).
gestures_no_op_5m = 0  # desktop_focus_unresolved + desktop_focus_noop
rail_panels_count_last = None  # dernière valeur de count loggée par rail_panels_built
rail_screens_count_last = None  # screens_count attendu (même log)
rail_panel_missing_5m = 0  # rail_panel_missing événements
# Tiler invariants (BSP / master-stack).
tiler_invariant_violations_5m = 0  # tiler_invariant_violation
tiler_inserts_5m = 0  # tiler_insert (volume baseline pour ratio)
# Crash-loop detection : count des "roadied ready" qui apparaissent dans la
# fenêtre 5 min. > 1 = redémarrage anormal (crash-loop possible).
roadied_starts_5m = 0
# Layout policy compliance.
tiler_policy_unrespected_5m = 0  # warn level, count
tree_flatten_events_5m = 0       # warn level, count
tree_depth_min_5m = None         # min observée parmi les tiler_insert (= worst case)

# Parse log avec tolérance : skip lignes invalides JSON.
parse_failures = 0
try:
    with open(daemon_log, "r", encoding="utf-8", errors="replace") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                e = json.loads(line)
            except Exception:
                parse_failures += 1
                continue
            ts_raw = e.get("ts", "")
            try:
                # Format: 2026-05-04T13:52:31.235Z
                ts = datetime.datetime.fromisoformat(ts_raw.replace("Z", "+00:00"))
            except Exception:
                continue
            if ts < window_start:
                continue
            level = e.get("level", "")
            msg = e.get("msg", "")

            if level == "error":
                errors_5m += 1
            if level == "warn" and msg not in WARN_WHITELIST:
                warns_5m_filtered += 1
            if msg.startswith("integrity_drift_"):
                drifts_5m += 1
            if msg == "boot_state_health":
                boot_health_last = e.get("verdict", "unknown")
            if msg == "applyAll start":
                applyall_starts.append(ts)
            elif msg == "applyAll done" and applyall_starts:
                start = applyall_starts.pop(0)
                applyall_durations_ms.append((ts - start).total_seconds() * 1000.0)
            # Gestures silent / unresolved.
            if msg in ("desktop_focus_unresolved", "desktop_focus_noop"):
                gestures_no_op_5m += 1
            # Rail observability.
            if msg == "rail_panels_built":
                try:
                    rail_panels_count_last = int(e.get("count", "0"))
                    rail_screens_count_last = int(e.get("screens_count", "0"))
                except Exception:
                    pass
            if msg == "rail_panel_missing":
                rail_panel_missing_5m += 1
            # Tiler invariants.
            if msg == "tiler_insert":
                tiler_inserts_5m += 1
            if msg == "tiler_invariant_violation":
                tiler_invariant_violations_5m += 1
            # Crash-loop : daemon redémarrages.
            if msg == "roadied ready":
                roadied_starts_5m += 1
            # Layout policy compliance.
            if msg == "tiler_policy_unrespected":
                tiler_policy_unrespected_5m += 1
            if msg == "tree_flatten_event":
                tree_flatten_events_5m += 1
            if msg == "tiler_insert":
                try:
                    d = int(e.get("tree_depth_after", "-1"))
                    if d >= 0:
                        if tree_depth_min_5m is None or d < tree_depth_min_5m:
                            tree_depth_min_5m = d
                except Exception:
                    pass
except Exception as ex:
    print(json.dumps({"error": "log_parse_failed", "detail": str(ex)}))
    sys.exit(3)

# p95 applyAll
def percentile(values, p):
    if not values:
        return 0.0
    s = sorted(values)
    k = (len(s) - 1) * p
    f = int(k)
    c = min(f + 1, len(s) - 1)
    return s[f] + (s[c] - s[f]) * (k - f)

applyall_p95_5m = round(percentile(applyall_durations_ms, 0.95), 1)

metrics = {
    "errors_5m": errors_5m,
    "warns_5m_filtered": warns_5m_filtered,
    "drifts_5m": drifts_5m,
    "boot_health_last": boot_health_last or "unknown",
    "applyall_p95_5m_ms": applyall_p95_5m,
    "gestures_no_op_5m": gestures_no_op_5m,
    "rail_panels_count_last": rail_panels_count_last if rail_panels_count_last is not None else -1,
    "rail_screens_count_last": rail_screens_count_last if rail_screens_count_last is not None else -1,
    "rail_panel_missing_5m": rail_panel_missing_5m,
    "tiler_invariant_violations_5m": tiler_invariant_violations_5m,
    "tiler_inserts_5m": tiler_inserts_5m,
    "roadied_starts_5m": roadied_starts_5m,
    "tiler_policy_unrespected_5m": tiler_policy_unrespected_5m,
    "tree_flatten_events_5m": tree_flatten_events_5m,
    "tree_depth_min_5m": tree_depth_min_5m if tree_depth_min_5m is not None else -1,
}

# --- Baseline depuis history -------------------------------------------------
hist = []
if os.path.exists(hist_file):
    with open(hist_file, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                hist.append(json.loads(line))
            except Exception:
                continue

# Tick number
tick_num = (hist[-1]["tick"] + 1) if hist else 1

baseline = None
anomaly = False
axis = None
reason = None
anti_flap_ok = False

# Pour calculer baseline, il faut au moins 6 ticks précédents stables.
# Stable = sans intervention de fix (skip ticks marked as fix/revert sur
# skill-runs.jsonl — ici on simplifie en prenant tous les derniers 6 ticks).
NUMERIC_AXES = ["errors_5m", "warns_5m_filtered", "drifts_5m", "applyall_p95_5m_ms",
                "gestures_no_op_5m", "rail_panel_missing_5m",
                "tiler_invariant_violations_5m", "roadied_starts_5m",
                "tiler_policy_unrespected_5m", "tree_flatten_events_5m"]

if len(hist) >= 6:
    last6 = hist[-6:]
    baseline = {}
    threshold = {}
    for axisName in NUMERIC_AXES:
        vals = [h["metrics"].get(axisName, 0) for h in last6]
        med = statistics.median(vals)
        mad = statistics.median([abs(v - med) for v in vals])
        # Plancher minimum pour éviter baseline trop serrée sur métriques
        # majoritairement à 0 (errors_5m typically).
        thr = med + 2 * mad
        if axisName == "errors_5m":
            thr = max(thr, 1)  # tout error > 0 déjà suspect
        elif axisName == "drifts_5m":
            thr = max(thr, 3)  # tolère 3 drifts/5min de bruit transient
        elif axisName == "warns_5m_filtered":
            thr = max(thr, 5)  # 5 warns/5min plancher
        elif axisName == "applyall_p95_5m_ms":
            thr = max(thr, 250)  # 250ms plancher
        elif axisName == "gestures_no_op_5m":
            thr = max(thr, 3)  # 3 gestes perdus/5min plancher (= signal user)
        elif axisName == "rail_panel_missing_5m":
            thr = max(thr, 1)  # tout missing déjà suspect
        elif axisName == "tiler_invariant_violations_5m":
            thr = max(thr, 1)  # tout violation = signal direct
        elif axisName == "roadied_starts_5m":
            thr = max(thr, 1)  # 1 boot/5min = OK ; >1 = crash-loop suspect
        elif axisName == "tiler_policy_unrespected_5m":
            thr = max(thr, 1)  # tout tree plat avec >2 leaves = signal direct
        elif axisName == "tree_flatten_events_5m":
            thr = max(thr, 1)  # toute diminution de profondeur entre 2 inserts = bug
        baseline[axisName] = {"median": round(med, 2), "mad": round(mad, 2),
                              "threshold": round(thr, 2)}
        threshold[axisName] = thr

    # Détection anomalie sur axes numériques
    for axisName in NUMERIC_AXES:
        cur = metrics[axisName]
        if cur > threshold[axisName]:
            anomaly = True
            axis = axisName
            reason = (f"{axisName}={cur} > threshold "
                      f"{threshold[axisName]:.2f} (med={baseline[axisName]['median']}, "
                      f"mad={baseline[axisName]['mad']})")
            break

    # Anomalie boot_health (catégorielle)
    if not anomaly and metrics["boot_health_last"] not in ("healthy", "unknown"):
        anomaly = True
        axis = "boot_health_last"
        reason = f"boot_health={metrics['boot_health_last']}"

    # Anomalie rail panels manquants : count_last < screens_count_last.
    # Catégorielle : un déficit d'un panel suffit même sans baseline historique.
    if not anomaly and rail_panels_count_last is not None \
            and rail_screens_count_last is not None \
            and rail_panels_count_last >= 0 \
            and rail_screens_count_last > 0 \
            and rail_panels_count_last < rail_screens_count_last:
        anomaly = True
        axis = "rail_panels_count_last"
        reason = (f"rail_panels_count={rail_panels_count_last} < "
                  f"screens_count={rail_screens_count_last} "
                  f"(panel manquant sur au moins 1 display)")

    # Anti-flap : exiger 2 ticks consécutifs sur le même axe pour déclencher.
    if anomaly and len(hist) >= 1:
        prev = hist[-1]
        if prev.get("anomaly") and prev.get("axis") == axis:
            anti_flap_ok = True
        else:
            anti_flap_ok = False
    else:
        anti_flap_ok = anomaly  # rien à confirmer si pas d'anomalie

result = {
    "tick": tick_num,
    "ts": now.strftime("%Y-%m-%dT%H:%M:%SZ"),
    "metrics": metrics,
    "baseline": baseline,
    "anomaly": anomaly,
    "axis": axis,
    "reason": reason,
    "anti_flap_ok": anti_flap_ok,
    "parse_failures": parse_failures,
    "history_size": len(hist),
}

# Append au history (uniquement les champs utiles pour baseline future).
hist_entry = {
    "tick": tick_num,
    "ts": result["ts"],
    "metrics": metrics,
    "anomaly": anomaly,
    "axis": axis,
}
with open(hist_file, "a", encoding="utf-8") as f:
    f.write(json.dumps(hist_entry) + "\n")

print(json.dumps(result, indent=None))
PY
