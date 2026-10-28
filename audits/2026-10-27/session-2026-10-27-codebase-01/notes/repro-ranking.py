from pathlib import Path
import subprocess

root = Path("/Users/moi/Nextcloud/10.Scripts/39.roadie")
script = root / "audits/2026-10-27/session-2026-10-27-codebase-01/notes/repro-ranking.swift"
for case in ("increment", "prefix"):
    result = subprocess.run([str(root / "scripts/with-xcode"), "swift", str(script), case], capture_output=True, text=True)
    print(f"{case}: returncode={result.returncode}")
    print("stdout:", result.stdout[:500].strip())
    print("stderr:", result.stderr[:500].strip())
