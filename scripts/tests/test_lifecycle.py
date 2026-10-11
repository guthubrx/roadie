"""Arrêt, redémarrage et signature avec des commandes simulées, sans signal réel."""

import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]

# Chaque commande lit le même état de test. Le builtin kill est remplacé via BASH_ENV.
FAKE_COMMAND = r'''
import json
import os
import shutil
import sys
from pathlib import Path

state_path = Path(os.environ["ROADIE_TEST_STATE"])
state = json.loads(state_path.read_text())
command = Path(sys.argv[0]).name
args = sys.argv[1:]
if command == "fake-command":
    command = args.pop(0)
state["calls"].append([command, *args])
result = 0

if command == "ps":
    if len(args) != 4 or args[0] != "-p" or args[2:] != ["-o", "comm="]:
        raise RuntimeError("ps doit inspecter seulement l'exécutable du PID ciblé")
    process = state["processes"].get(args[1])
    if process:
        print(process["executable"])
    else:
        result = 1
elif command == "kill":
    if len(args) != 2 or args[0] != "-TERM":
        raise RuntimeError("seul SIGTERM sur un PID est autorisé")
    process = state["processes"].get(args[1])
    if not process:
        result = 1
    elif not process.get("persistent"):
        del state["processes"][args[1]]
elif command == "launchctl":
    if args[0] == "print":
        result = 0 if state["loaded"] else 1
        if state["loaded"] and state.get("service_pid"):
            print("    pid = " + state["service_pid"])
    elif args[0] == "bootout":
        state["loaded"] = False
        state["service_pid"] = None
    elif args[0] == "bootstrap":
        state["loaded"] = True
    elif args[0] == "kickstart":
        # Une instance autonome empêche launchd de démarrer son propre daemon.
        if state["processes"]:
            state["service_pid"] = None
        else:
            state["service_pid"] = "9002"
            if state.get("startup_live", True):
                state["processes"]["9002"] = {"executable": state["app_executable"]}
            pidfile = Path(os.environ["HOME"], ".roadies", "roadied.pid")
            pidfile_mode = state.get("startup_pidfile", "matching")
            if pidfile_mode == "absent":
                pidfile.unlink(missing_ok=True)
            else:
                pidfile.write_text("9002\n" if pidfile_mode == "matching" else "9003\n")
    elif args[0] != "enable":
        raise RuntimeError("launchctl inattendu: " + repr(args))
elif command == "tmux":
    result = 0 if state.get("tmux") else 1
elif command == "plutil":
    if args[:5] != ["-extract", "pid", "raw", "-o", "-"]:
        raise RuntimeError("plutil inattendu: " + repr(args))
    print(json.loads(Path(args[5]).read_text())["pid"])
elif command == "security":
    if args != ["find-identity", "-v", "-p", "codesigning"]:
        raise RuntimeError("security inattendu: " + repr(args))
    for number, identity in enumerate(state["identities"], 1):
        fingerprint = identity["hash"] if isinstance(identity, dict) else f"{number:040X}"
        name = identity["name"] if isinstance(identity, dict) else identity
        print(f'  {number}) {fingerprint} "{name}"')
    print(f'     {len(state["identities"])} valid identities found')
elif command == "codesign":
    if args[0] == "--display":
        if state.get("authority"):
            print("Authority=" + state["authority"], file=sys.stderr)
            print("Authority=Certificat intermédiaire", file=sys.stderr)
        else:
            print("Signature=adhoc", file=sys.stderr)
        if "-r-" in args and state.get("leaf_hash"):
            print('designated => identifier "com.roadie.roadied" and certificate leaf = H"'
                  + state["leaf_hash"] + '"')
elif command == "with-xcode":
    if "--show-bin-path" in args:
        print(state["build_dir"])
elif command == "build-app-bundle":
    target = Path(args[1], "Contents", "MacOS", "roadied")
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(args[0], target)
elif command != "sleep":
    raise RuntimeError("commande inattendue: " + command)

state_path.write_text(json.dumps(state))
sys.exit(result)
'''


class LifecycleTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="roadie-lifecycle-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name).resolve()
        self.home = self.root / "home"
        self.repo = self.root / "repo"
        self.scripts = self.repo / "scripts"
        self.commands = self.root / "commands"
        self.scripts.mkdir(parents=True)
        self.commands.mkdir()
        (self.home / ".roadies").mkdir(parents=True)
        for name in ("stop", "install", "roadiedctl"):
            shutil.copyfile(REPO / "scripts" / name, self.scripts / name)
            (self.scripts / name).chmod(0o755)
        shutil.copyfile(REPO / "Makefile", self.repo / "Makefile")
        self.fake = self.root / "fake-command"
        self.fake.write_text(f"#!{sys.executable}\n" + FAKE_COMMAND)
        self.fake.chmod(0o755)
        for command in ("ps", "launchctl", "tmux", "plutil", "security", "codesign", "sleep"):
            (self.commands / command).symlink_to(self.fake)
        for command in ("with-xcode", "build-app-bundle"):
            (self.scripts / command).symlink_to(self.fake)
        bash_env = self.root / "bash-env"
        bash_env.write_text('kill() { "$ROADIE_TEST_FAKE" kill "$@"; }\n')
        self.env = dict(os.environ, HOME=str(self.home),
                        PATH=str(self.commands) + os.pathsep + os.environ["PATH"],
                        BASH_ENV=str(bash_env), ROADIE_TEST_FAKE=str(self.fake),
                        ROADIE_TEST_STATE=str(self.root / "state.json"),
                        ROADIE_INSTALL_NO_START="1")
        self.env.pop("ROADIE_CODESIGN_IDENTITY", None)
        self.app = self.home / "Applications" / "Roadie.app"
        self.app_executable = self.app / "Contents" / "MacOS" / "roadied"
        self.pidfile = self.home / ".roadies" / "roadied.pid"
        self.statusfile = self.home / ".roadies" / "daemon-status.json"
        self.lockfile = self.home / ".roadies" / "roadied.lock"
        self.lockfile.write_text("lock conservé")
        self.build = self.repo / ".build" / "release"
        self.build.mkdir(parents=True)
        for binary in ("roadied", "roadie"):
            path = self.build / binary
            path.write_text("nouveau " + binary)
            path.chmod(0o755)
        source = self.repo / "Sources" / "RoadieDaemon" / "DaemonHealth.swift"
        source.parent.mkdir(parents=True)
        source.write_text('static let current = "1.0.0"\n')
        self.state = {"calls": [], "processes": {}, "loaded": False, "identities": [],
                      "app_executable": str(self.app_executable), "build_dir": str(self.build)}

    def run_script(self, name, *args):
        self.save_state()
        result = subprocess.run([str(self.scripts / name), *args], env=self.env,
                                cwd=self.repo, capture_output=True, text=True, timeout=10)
        self.load_state()
        return result

    def save_state(self):
        Path(self.env["ROADIE_TEST_STATE"]).write_text(json.dumps(self.state))

    def load_state(self):
        self.state = json.loads(Path(self.env["ROADIE_TEST_STATE"]).read_text())

    def process(self, executable=None, *, persistent=False, pidfile=True):
        self.state["processes"]["9001"] = {
            "executable": str(executable or self.app_executable), "persistent": persistent}
        if pidfile:
            self.pidfile.write_text("9001\n")
        else:
            self.statusfile.write_text(json.dumps({"pid": 9001, "components": {"pid": 8000}}))

    def installed_app(self, authority):
        self.app_executable.parent.mkdir(parents=True)
        self.app_executable.write_text("ancienne app")
        self.state["authority"] = authority

    def signed_identities(self):
        return [call[3] for call in self.state["calls"]
                if call[:3] == ["codesign", "--force", "--sign"]]

    def test_stop_app_opened_without_arguments(self):
        self.process()
        self.state["loaded"] = True
        result = self.run_script("stop")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn("9001", self.state["processes"])
        self.assertFalse(self.pidfile.exists())
        self.assertTrue(self.lockfile.exists())
        calls = self.state["calls"]
        bootout_index = next(i for i, call in enumerate(calls)
                             if call[:2] == ["launchctl", "bootout"])
        self.assertLess(bootout_index, calls.index(["kill", "-TERM", "9001"]))
        self.assertLess(calls.index(["ps", "-p", "9001", "-o", "comm="]),
                        calls.index(["kill", "-TERM", "9001"]))
        self.assertIn(["sleep", "3"], self.state["calls"])

    def test_stop_uses_root_status_pid_when_pidfile_is_missing(self):
        self.process(pidfile=False)
        result = self.run_script("stop")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn("9001", self.state["processes"])
        self.assertIn(["kill", "-TERM", "9001"], self.state["calls"])

    def test_stop_preserves_unrecognized_live_pid(self):
        for executable in ("/Applications/Firefox.app/Contents/MacOS/firefox", "/usr/bin/python3"):
            with self.subTest(executable=executable):
                self.state["calls"] = []
                self.process(executable)
                result = self.run_script("stop")
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(self.pidfile.read_text(), "9001\n")
                self.assertIn("9001", self.state["processes"])
                self.assertFalse(any(call[0] == "kill" for call in self.state["calls"]))

    def test_stop_preserves_pidfile_when_daemon_does_not_exit(self):
        self.process(persistent=True)
        result = self.run_script("stop")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("encore vivant", result.stderr)
        self.assertTrue(self.pidfile.exists())
        self.assertTrue(self.lockfile.exists())

    def test_stop_cleans_stale_pidfile_without_signal(self):
        self.pidfile.write_text("9001\n")
        result = self.run_script("stop")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(self.pidfile.exists())
        self.assertFalse(any(call[0] == "kill" for call in self.state["calls"]))

    def test_stop_rejects_invalid_pid_without_process_lookup(self):
        for pid in ("0", "-1", "9001 9002", "abc"):
            with self.subTest(pid=pid):
                self.state["calls"] = []
                self.pidfile.write_text(pid)
                result = self.run_script("stop")
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(self.pidfile.read_text(), pid)
                self.assertFalse(any(call[0] in ("ps", "kill") for call in self.state["calls"]))

    def test_stop_accepts_legacy_and_development_executables(self):
        for executable in (self.home / ".local" / "bin" / "roadied", self.repo / "bin" / "roadied",
                           self.repo / ".build" / "arm64-apple-macosx" / "debug" / "roadied"):
            with self.subTest(executable=executable):
                self.process(executable)
                result = self.run_script("stop")
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertNotIn("9001", self.state["processes"])

    def restart(self):
        plist = self.home / "Library" / "LaunchAgents" / "com.roadie.roadied.plist"
        plist.parent.mkdir(parents=True, exist_ok=True)
        plist.write_text("plist de test")
        self.save_state()
        result = subprocess.run(["make", "restart"], env=self.env, cwd=self.repo,
                                capture_output=True, text=True, timeout=10)
        self.load_state()
        return result

    def test_restart_stops_orphan_before_start_even_when_service_is_loaded(self):
        for loaded in (True, False):
            with self.subTest(loaded=loaded):
                self.state["calls"] = []
                self.state["processes"] = {}
                self.state["loaded"] = loaded
                self.process()
                result = self.restart()
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertNotIn("9001", self.state["processes"])
                self.assertEqual(self.state["service_pid"], "9002")
                calls = self.state["calls"]
                kill_index = calls.index(["kill", "-TERM", "9001"])
                bootstrap_index = next(i for i, call in enumerate(calls)
                                       if call[:2] == ["launchctl", "bootstrap"])
                self.assertLess(kill_index, bootstrap_index)

    def test_restart_does_not_start_after_stop_failure(self):
        self.process(persistent=True)
        result = self.restart()
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(any(call[:2] == ["launchctl", "kickstart"] for call in self.state["calls"]))

    def test_restart_keeps_tmux_guard(self):
        self.process()
        self.state["tmux"] = True
        result = self.restart()
        self.assertNotEqual(result.returncode, 0)
        self.assertTrue(self.pidfile.exists())
        self.assertFalse(any(call[0] in ("launchctl", "kill") for call in self.state["calls"]))

    def test_start_accepts_only_live_launchctl_pid_that_owns_pidfile(self):
        plist = self.home / "Library" / "LaunchAgents" / "com.roadie.roadied.plist"
        plist.parent.mkdir(parents=True)
        plist.write_text("plist de test")
        result = self.run_script("roadiedctl", "start")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.state["service_pid"], self.pidfile.read_text().strip())
        self.assertIn(["ps", "-p", "9002", "-o", "comm="], self.state["calls"])

    def test_start_rejects_launchctl_pid_without_live_pidfile_owner(self):
        plist = self.home / "Library" / "LaunchAgents" / "com.roadie.roadied.plist"
        plist.parent.mkdir(parents=True)
        plist.write_text("plist de test")
        for mode, live in (("absent", True), ("different", True), ("matching", False)):
            with self.subTest(pidfile=mode, live=live):
                self.state["calls"] = []
                self.state["processes"] = {}
                self.state["startup_pidfile"] = mode
                self.state["startup_live"] = live
                result = self.run_script("roadiedctl", "start")
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(self.state["service_pid"], "9002")
                self.assertIn("aucun PID vivant", result.stderr)
                self.assertNotIn("active et demarre", result.stdout)
                self.assertLessEqual(self.state["calls"].count(["sleep", "0.1"]), 30)

    def test_install_reuses_existing_leaf_identity_without_environment(self):
        self.installed_app("Identité existante")
        self.state["identities"] = ["roadied-cert", "Identité existante"]
        result = self.run_script("install")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.signed_identities(), ["Identité existante"] * 2)
        self.assertEqual(self.app_executable.read_text(), "nouveau roadied")

    def test_install_reuses_exact_existing_leaf_fingerprint(self):
        self.installed_app("roadied-cert")
        self.state["leaf_hash"] = "abcdef12" * 5
        self.state["identities"] = [{"name": "roadied-cert", "hash": "ABCDEF12" * 5}]
        result = self.run_script("install")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.signed_identities(), ["abcdef12" * 5] * 2)

    def test_first_install_uses_available_roadied_certificate(self):
        self.state["identities"] = ["roadied-cert"]
        result = self.run_script("install")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.signed_identities(), ["roadied-cert"] * 2)

    def test_install_explicit_identity_has_priority(self):
        self.installed_app("Identité précédente")
        self.state["leaf_hash"] = "abcdef12" * 5
        self.env["ROADIE_CODESIGN_IDENTITY"] = "Identité demandée"
        self.state["identities"] = ["roadied-cert", "Identité demandée"]
        result = self.run_script("install")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.signed_identities(), ["Identité demandée"] * 2)

    def test_missing_previous_identity_prevents_replacement(self):
        self.installed_app("Identité disparue")
        self.state["identities"] = ["roadied-cert", "Autre Identité disparue"]
        result = self.run_script("install")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.app_executable.read_text(), "ancienne app")
        self.assertFalse(self.signed_identities())
        self.assertFalse(any(call[0] == "with-xcode" for call in self.state["calls"]))

    def test_recreated_certificate_with_same_name_prevents_replacement(self):
        self.installed_app("roadied-cert")
        self.state["leaf_hash"] = "abcdef12" * 5
        self.state["identities"] = [{"name": "roadied-cert", "hash": "1234abcd" * 5}]
        result = self.run_script("install")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.app_executable.read_text(), "ancienne app")
        self.assertFalse(self.signed_identities())
        self.assertFalse(any(call[0] == "with-xcode" for call in self.state["calls"]))

    def test_new_install_without_certificate_warns_and_uses_ad_hoc(self):
        result = self.run_script("install")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("signature ad hoc", result.stderr)
        self.assertEqual(self.signed_identities(), ["-"] * 2)


if __name__ == "__main__":
    unittest.main()
