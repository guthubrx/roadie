"""Exécute les copies figées dans des sous-processus isolés et rapporte leurs sorties."""
from pathlib import Path
import subprocess

root = Path("/Users/moi/Nextcloud/10.Scripts/39.roadie")
notes = root / "audits/2026-10-27/session-2026-10-27-codebase-01/notes"
launcher = root / "scripts/with-xcode"
for script, args in [
    ("repro-plist-number.swift", []),
    ("repro-keycode.swift", []),
    ("repro-calculator-depth.swift", ["32"]),
    ("repro-calculator-depth.swift", ["5000"]),
    ("repro-calculator-depth.swift", ["50000"]),
]:
    result = subprocess.run([str(launcher), "swift", str(notes / script), *args], capture_output=True, text=True)
    print(f"{script} {' '.join(args)}: returncode={result.returncode}")
    print("stdout:", result.stdout[:1000].strip())
    print("stderr:", result.stderr[:1000].strip())
