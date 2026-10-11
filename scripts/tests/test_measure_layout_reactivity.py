"""Test de scripts/measure-layout-reactivity sur un journal de test (SPEC-017 FR-016).

Lancement (depuis la racine du dépôt) :
    python3 -I -B -m unittest discover scripts/tests
Le journal `fixtures/layout-reactivity.jsonl` contient 4 épisodes :
  1. ancien (sans tsMs) : stage_switch + 2 layout_apply, 1 s d'écart ;
  2. ancien (déclencheur sans tsMs) : 1 layout_apply ;
  3. identifié (tsMs + episodeId) : 2 layout_apply avec windowWrites, space_transition_guard, layout_stable ;
  4. identifié : 1 layout_apply + layout_stable.
Plus une ligne corrompue, ignorée et comptée.
"""

import json
import subprocess
import sys
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
SCRIPT = HERE.parent / "measure-layout-reactivity"
JOURNAL = HERE / "fixtures" / "layout-reactivity.jsonl"


class MeasureLayoutReactivityTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        out = subprocess.run([sys.executable, "-I", "-B", str(SCRIPT), "--json", str(JOURNAL)],
                             check=True, capture_output=True, text=True).stdout
        data = json.loads(out)
        cls.summary, cls.episodes = data["summary"], data["episodes"]

    def test_journal_counts(self):
        self.assertEqual(self.summary["invalid_lines"], 1)
        self.assertEqual(len(self.episodes), 4)
        self.assertEqual(self.summary["episodes_identified"], 2)

    def test_passes_per_episode(self):
        self.assertEqual([e["passes"] for e in self.episodes], [2, 1, 2, 1])

    def test_time_to_stable(self):
        stable = [e["time_to_stable_s"] for e in self.episodes]
        for got, want in zip(stable, [1.0, 0.0, 0.7, 0.1]):
            self.assertAlmostEqual(got, want, places=3)

    def test_old_episodes_are_second_resolution(self):
        self.assertEqual([e["precise"] for e in self.episodes], [False, False, True, True])
        self.assertIsNone(self.episodes[0]["episode_id"])
        self.assertEqual(self.episodes[2]["episode_id"], "ep_1791626460000")
        self.assertEqual(self.summary["timestamp_resolution_s"], 1)

    def test_layout_stable_wins_over_last_apply(self):
        ep = self.episodes[2]  # dernier layout_apply à 0,3 s, layout_stable à 0,7 s
        self.assertAlmostEqual(ep["time_to_write_end_s"], 0.3, places=3)
        self.assertAlmostEqual(ep["time_to_stable_s"], 0.7, places=3)

    def test_space_transition_guard(self):
        ep = self.episodes[2]
        self.assertAlmostEqual(ep["time_to_guard_end_s"], 0.6, places=3)
        self.assertEqual(ep["guard_held_ms"], 500.0)
        self.assertEqual(ep["guard_closed_by"], "stable")
        self.assertIsNone(self.episodes[0]["time_to_guard_end_s"])

    def test_max_writes_per_window(self):
        # Épisode 3 : fenêtre 11 écrite 2 + 1 = 3 fois (budget 2 dépassé) ; fenêtre 12 : 2 fois.
        self.assertEqual([e["max_writes_per_window"] for e in self.episodes], [None, None, 3, 1])
        self.assertEqual([e["windows_over_budget"] for e in self.episodes], [0, 0, 1, 0])
        self.assertEqual(self.summary["episodes_over_write_budget"], 1)
        self.assertEqual(self.episodes[2]["scans"], 2)
        self.assertEqual(self.episodes[2]["ax_writes"], 5)


if __name__ == "__main__":
    unittest.main()
