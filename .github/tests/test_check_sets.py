"""Verify native CI retains added checks while portable lint has one owner."""

import json
import subprocess
import unittest
from pathlib import Path

MODULE = Path(__file__).resolve().parents[2] / "flake/ci-checks.nix"


class CheckSetTests(unittest.TestCase):
    def test_native_checks_follow_additions_and_deletions(self):
        for names in [["package"], ["package", "new-runtime"], ["new-runtime"]]:
            with self.subTest(names=names):
                expression = """
                    let
                        names = builtins.fromJSON NAMES;
                        native = builtins.listToAttrs (map (name: {
                            inherit name;
                            value = "native";
                        }) names);
                        self = { checks.fixture = native // {
                            pre-commit = "hooks";
                            treefmt = "formatter";
                        }; } // result;
                        result = (import MODULE { inherit self; }).flake;
                    in {
                        native = builtins.attrNames result.ciChecks.fixture;
                        lint = builtins.attrNames result.lintChecks.fixture;
                    }
                """.replace("NAMES", json.dumps(json.dumps(names))).replace(
                    "MODULE", json.dumps(str(MODULE))
                )
                result = subprocess.run(
                    ["nix", "eval", "--impure", "--json", "--expr", expression],
                    capture_output=True,
                    text=True,
                    check=True,
                    timeout=30,
                )
                sets = json.loads(result.stdout)
                self.assertEqual(sets["native"], sorted(names))
                self.assertEqual(sets["lint"], ["pre-commit", "treefmt"])


if __name__ == "__main__":
    unittest.main()
