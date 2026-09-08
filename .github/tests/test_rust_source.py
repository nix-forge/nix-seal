"""Keep metadata-only changes from rebuilding Rust while retaining real inputs."""

import io
import os
import subprocess
import tarfile
import tempfile
import unittest
from pathlib import Path

PROJECT = Path(__file__).resolve().parents[2]


class RustSourceTests(unittest.TestCase):
    def test_source_boundary(self):
        archive = subprocess.check_output(["git", "archive", "HEAD"], cwd=PROJECT)
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            with tarfile.open(fileobj=io.BytesIO(archive)) as contents:
                contents.extractall(root, filter="data")
            env = os.environ | {
                "PROJECT_FLAKE": str(PROJECT),
                "SOURCE_FILTER": str(PROJECT / "flake/rust-source.nix"),
                "TEST_REPO": str(root),
            }
            expression = """let
              flake = builtins.getFlake (builtins.getEnv "PROJECT_FLAKE");
              lib = flake.inputs.nixpkgs.lib;
            in toString (import (builtins.toPath (builtins.getEnv "SOURCE_FILTER")) {
              inherit lib;
              root = /. + builtins.getEnv "TEST_REPO";
            })"""

            def source():
                return subprocess.check_output(
                    ["nix", "eval", "--impure", "--raw", "--expr", expression],
                    env=env,
                    cwd=PROJECT,
                    text=True,
                ).strip()

            before = source()
            for filename in [
                ".github/workflows/ci.yml",
                "README.md",
                "docs/runbooks.md",
            ]:
                with self.subTest(metadata=filename):
                    path = root / filename
                    original = path.read_bytes()
                    path.write_bytes(original + b"\n# Metadata change\n")
                    try:
                        self.assertEqual(source(), before)
                    finally:
                        path.write_bytes(original)
            for filename in [
                "Cargo.toml",
                "Cargo.lock",
                "rust-toolchain.toml",
                "LICENSE-MIT",
                "crates/nix-seal-cli/src/main.rs",
                "schemas/plan-v2.schema.json",
            ]:
                with self.subTest(build_input=filename):
                    path = root / filename
                    original = path.read_bytes()
                    path.write_bytes(original + b"\n# Build input change\n")
                    try:
                        self.assertNotEqual(source(), before)
                    finally:
                        path.write_bytes(original)
            fixture = root / "crates/nix-seal-cli/tests/fixtures/source-boundary.txt"
            fixture.write_text("new test fixture\n")
            self.assertNotEqual(source(), before)
            fixture.unlink()
            config = root / ".cargo/config.toml"
            config.parent.mkdir(exist_ok=True)
            config.write_text("[build]\njobs = 1\n")
            self.assertNotEqual(source(), before)
