import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


class FastHelpersTests(unittest.TestCase):
    def test_run_fast_defaults_are_short_and_safe(self):
        script = (ROOT / "run_fast.sh").read_text()

        self.assertIn("DecisionTree", script)
        self.assertIn("Cmdenv", script)
        self.assertIn("25s", script)
        self.assertIn("-r 0", script)
        self.assertIn("exit 1", script)

    def test_smoke_config_is_present_and_short(self):
        ini = (ROOT / "simulations" / "omnetpp.ini").read_text()

        self.assertIn("[Config Smoke]", ini)
        self.assertIn("sim-time-limit = 25s", ini)
        self.assertIn("repeat = 1", ini)
        self.assertIn("**.attacker[*].udpApp[0].startTime = uniform(8s, 10s)", ini)

    def test_quick_compare_uses_short_defaults(self):
        script = (ROOT / "quick_compare.sh").read_text()

        self.assertIn('LIMIT="${1:-15s}"', script)
        self.assertIn('bash "$PROJ/run.sh" "$2" Cmdenv "$LIMIT" -r 0', script)
        self.assertIn("NoProtection", script)
        self.assertIn("DecisionTree", script)
        self.assertIn("KMeans", script)

    def test_readme_lists_fast_commands(self):
        readme = (ROOT / "README.md").read_text()

        self.assertIn("bash run_fast.sh", readme)
        self.assertIn("bash quick_compare.sh", readme)
        self.assertIn("Smoke test", readme)


if __name__ == "__main__":
    unittest.main()
