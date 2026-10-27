from pathlib import Path
import subprocess

root = Path("/Users/moi/Nextcloud/10.Scripts/39.roadie")
notes = root / "audits/2026-10-27/session-2026-10-27-codebase-01/notes"
launcher = root / "scripts/with-xcode"
for script, args in [("repro-replacement.swift", [str(notes)]), ("repro-anchor.swift", [])]:
    result = subprocess.run([str(launcher), "swift", str(notes / script), *args], capture_output=True, text=True)
    print(f"{script}: returncode={result.returncode}")
    print(result.stdout.strip())
    if result.stderr:
        print(result.stderr[:1000])
