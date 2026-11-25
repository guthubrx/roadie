import pathlib
import subprocess
import sys
import tempfile
import unittest

REPO_ROOT = pathlib.Path(__file__).resolve().parents[2]
GENERATE_CASK = REPO_ROOT / "scripts" / "generate-cask"
INSTALL_RELEASE = REPO_ROOT / "scripts" / "install-release.sh"
TRACKED_CASK = REPO_ROOT / "Casks" / "roadie.rb"


class DistributionScriptsTests(unittest.TestCase):
    def test_tracked_cask_exists_and_matches_generator(self) -> None:
        self.assertTrue(TRACKED_CASK.is_file(), "Casks/roadie.rb doit exister")
        with tempfile.TemporaryDirectory() as tmp:
            generated = pathlib.Path(tmp) / "roadie.rb"
            result = subprocess.run(
                [sys.executable, str(GENERATE_CASK), "--output", str(generated)],
                capture_output=True,
                text=True,
                check=False,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(
                TRACKED_CASK.read_text(encoding="utf-8"),
                generated.read_text(encoding="utf-8"),
                "Casks/roadie.rb doit rester synchronisé avec scripts/generate-cask",
            )

    def test_generate_cask_with_sha256_file_and_custom_version(self) -> None:
        sample_sha = "a" * 64
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = pathlib.Path(tmp)
            sha_file = tmp_path / "Roadie.dmg.sha256"
            sha_file.write_text(f"{sample_sha}  Roadie.dmg\n", encoding="utf-8")
            out_file = tmp_path / "roadie.rb"
            result = subprocess.run(
                [
                    sys.executable,
                    str(GENERATE_CASK),
                    "--version",
                    "0.15.0",
                    "--sha256-file",
                    str(sha_file),
                    "--output",
                    str(out_file),
                ],
                capture_output=True,
                text=True,
                check=False,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            text = out_file.read_text(encoding="utf-8")
            self.assertIn('version "0.15.0"', text)
            self.assertIn(f'sha256 "{sample_sha}"', text)
            self.assertIn('app "Roadie.app"', text)
            self.assertIn('binary "#{appdir}/Roadie.app/Contents/Resources/roadie"', text)
            self.assertIn("com.apple.quarantine", text)

    def test_generate_cask_rejects_invalid_sha256(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            out_file = pathlib.Path(tmp) / "roadie.rb"
            result = subprocess.run(
                [
                    sys.executable,
                    str(GENERATE_CASK),
                    "--version",
                    "0.15.0",
                    "--sha256",
                    "not-a-valid-sha",
                    "--output",
                    str(out_file),
                ],
                capture_output=True,
                text=True,
                check=False,
            )
            self.assertNotEqual(result.returncode, 0)

    def test_install_release_script_syntax_and_dry_run(self) -> None:
        syntax = subprocess.run(
            ["bash", "-n", str(INSTALL_RELEASE)],
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertEqual(syntax.returncode, 0, syntax.stderr)

        dry_run = subprocess.run(
            ["bash", str(INSTALL_RELEASE), "--dry-run", "--preset", "vim", "--no-start"],
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertEqual(dry_run.returncode, 0, dry_run.stderr)
        self.assertIn("[dry-run] téléchargement :", dry_run.stdout)
        self.assertIn("preset=vim", dry_run.stdout)
        self.assertIn("start=no", dry_run.stdout)

    def test_install_release_rejects_unknown_preset(self) -> None:
        bad = subprocess.run(
            ["bash", str(INSTALL_RELEASE), "--dry-run", "--preset", "invalid"],
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertEqual(bad.returncode, 64)


if __name__ == "__main__":
    unittest.main()
