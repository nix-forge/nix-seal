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
            root = Path(directory).resolve()
            with tarfile.open(fileobj=io.BytesIO(archive)) as contents:
                contents.extractall(root, filter="data")
            env = os.environ | {
                "PROJECT_FLAKE": str(PROJECT),
                "SOURCE_FILTER": str(PROJECT / "flake/rust-source.nix"),
                "TEST_REPO": str(root),
            }
            expression = (
                Path(__file__).with_name("fixtures") / "rust-source-filter.nix.in"
            ).read_text(encoding="utf-8")

            def source(*, legacy=False):
                return subprocess.check_output(
                    ["nix", "eval", "--impure", "--raw", "--expr", expression],
                    env=env | {"LEGACY_MODE": "1" if legacy else "0"},
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
            for filename in ["vendor/source-boundary.txt", "security/age-source.json"]:
                with self.subTest(new_build_input=filename):
                    path = root / filename
                    path.parent.mkdir(exist_ok=True)
                    original = path.read_bytes() if path.exists() else None
                    path.write_bytes(b"source boundary change\n")
                    try:
                        self.assertNotEqual(source(), before)
                    finally:
                        if original is None:
                            path.unlink()
                        else:
                            path.write_bytes(original)
            config = root / ".cargo/config.toml"
            self._check_legacy_boundary(root, source, before)
            config.parent.mkdir(exist_ok=True)
            config.write_text("[build]\njobs = 1\n")
            self.assertNotEqual(source(), before)

    def _check_legacy_boundary(self, root, source, before):
        legacy_manifest = root / "legacy/Cargo.toml"
        legacy_manifest.parent.mkdir(exist_ok=True)
        original = legacy_manifest.read_bytes() if legacy_manifest.exists() else None
        legacy_manifest.write_bytes(b"# legacy source boundary fixture\n")
        legacy_before = source(legacy=True)
        legacy_manifest.write_bytes(b"# changed legacy source boundary fixture\n")
        legacy_changed = source(legacy=True)
        self.assertNotEqual(legacy_changed, legacy_before)
        self.assertEqual(source(), before)
        ignored = root / "legacy/target/source-boundary.txt"
        ignored.parent.mkdir(exist_ok=True)
        ignored.write_text("generated build artifact\n")
        try:
            self.assertEqual(source(legacy=True), legacy_changed)
        finally:
            ignored.unlink()
        if original is None:
            legacy_manifest.unlink()
        else:
            legacy_manifest.write_bytes(original)
