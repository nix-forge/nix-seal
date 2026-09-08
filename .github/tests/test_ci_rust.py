"""Verify CI follows changed manifests and never hides a failed fuzz target."""

import importlib.util
import os
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

spec = importlib.util.spec_from_file_location(
    "ci_rust", Path(__file__).parents[1] / "scripts/ci-rust.py"
)
ci_rust = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ci_rust)


class RustInputsTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        (self.root / "fuzz").mkdir()
        (self.root / "rust-toolchain.toml").write_text(
            '[toolchain]\nchannel="1.100.2"\nprofile="minimal"\n'
            'components=["rustfmt", "clippy"]\ntargets=["wasm32-unknown-unknown"]\n'
        )
        (self.root / "Cargo.toml").write_text(
            '[workspace.package]\nrust-version="1.95"\n'
        )

    def test_toolchain_and_msrv_follow_their_manifests(self):
        for msrv, channel in [(False, "1.100.2"), (True, "1.95.0")]:
            with (
                self.subTest(msrv=msrv),
                patch.dict(os.environ, {"GITHUB_ENV": str(self.root / "environment")}),
                patch.object(ci_rust.subprocess, "run") as run,
            ):
                ci_rust.toolchain(self.root, msrv=msrv)
                self.assertEqual(run.call_args.args[0][3], channel)
                self.assertIn("--component", run.call_args.args[0])
                self.assertIn(
                    f"RUSTUP_TOOLCHAIN={channel}\n",
                    (self.root / "environment").read_text(),
                )
                self.assertEqual("--target" in run.call_args.args[0], not msrv)

    def manifest(self, targets):
        (self.root / "fuzz/Cargo.toml").write_text(
            "\n".join(f'[[bin]]\nname="{target}"' for target in targets)
        )

    def test_fuzz_additions_deletions_and_failures(self):
        for targets in [["first"], ["first", "new"], ["new"]]:
            self.manifest(targets)
            with patch.object(ci_rust.subprocess, "run") as run:
                run.return_value = subprocess.CompletedProcess([], 0)
                self.assertEqual(ci_rust.fuzz(self.root), 0)
                self.assertEqual(
                    [c.args[0][3] for c in run.call_args_list], sorted(targets)
                )
        self.manifest(["first", "last"])
        with patch.object(ci_rust.subprocess, "run") as run:
            run.side_effect = [
                subprocess.CompletedProcess([], 1),
                subprocess.CompletedProcess([], 0),
            ]
            self.assertEqual(ci_rust.fuzz(self.root), 1)
            self.assertEqual(run.call_count, 2)

    def test_empty_manifest_cannot_pass(self):
        self.manifest([])
        with patch.object(ci_rust.subprocess, "run") as run:
            with self.assertRaises(ValueError):
                ci_rust.fuzz(self.root)
            run.assert_not_called()

    def test_invalid_channel_cannot_write_environment(self):
        (self.root / "rust-toolchain.toml").write_text(
            '[toolchain]\nchannel="bad\\nINJECTED=value"'
        )
        with patch.object(ci_rust.subprocess, "run") as run:
            with self.assertRaises(ValueError):
                ci_rust.toolchain(self.root)
            run.assert_not_called()


if __name__ == "__main__":
    unittest.main()
