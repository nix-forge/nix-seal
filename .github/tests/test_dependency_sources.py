"""Check the reviewed dependency surface and local source provenance offline."""

import hashlib
import json
import secrets
import subprocess
import tempfile
import tomllib
import unittest
from pathlib import Path

PROJECT = Path(__file__).resolve().parents[2]


class DependencySourceTests(unittest.TestCase):
    def test_git_preserves_upstream_wire_fixture_bytes(self):
        fixture = "vendor/age/tests/testdata/testkit/armor_crlf"
        payload = (PROJECT / fixture).read_bytes()
        self.assertIn(b"\r\n", payload)
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / ".gitattributes").write_bytes(
                (PROJECT / ".gitattributes").read_bytes()
            )
            subprocess.run(["git", "init", "-q"], cwd=root, check=True)
            original = subprocess.check_output(
                ["git", "hash-object", "--no-filters", "--stdin"],
                cwd=root,
                input=payload,
            )
            staged = subprocess.check_output(
                ["git", "hash-object", f"--path={fixture}", "--stdin"],
                cwd=root,
                input=payload,
            )
            self.assertEqual(staged, original)

    def test_public_fixture_exceptions_still_detect_unknown_credentials(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            key = root / "vendor/age/src/ssh/identity.rs"
            key.parent.mkdir(parents=True)
            # Scanner canaries only: these bytes are not valid private keys.
            delimiter = "-" * 5
            kind = "PRIVATE" + " KEY"
            key.write_text(
                f"{delimiter}BEGIN {kind}{delimiter}\n"
                f"{secrets.token_hex(48)}\n"
                f"{delimiter}END {kind}{delimiter}\n",
            )
            identity = root / "vendor/age/src/identity.rs"
            alphabet = "QPZRY9X8GF2TVDW0S3JN54KHCE6MUA7L"
            identity.write_text(
                "AGE-SECRET-KEY-1"
                + "".join(secrets.choice(alphabet) for _ in range(59))
                + "\n",
            )
            provenance = root / "security/age-source.json"
            provenance.parent.mkdir()
            provenance.write_text(json.dumps({"api_key": secrets.token_hex(32)}))
            report = root / "result.json"
            result = subprocess.run(
                [
                    "gitleaks",
                    "dir",
                    "--redact",
                    "--no-banner",
                    "--exit-code=1",
                    "--config",
                    str(PROJECT / ".gitleaks.toml"),
                    "--report-format=json",
                    "--report-path",
                    str(report),
                    str(root),
                ],
                capture_output=True,
                check=False,
            )
            self.assertEqual(result.returncode, 1, result.stderr.decode())
            findings = {
                (row["File"], row["RuleID"]) for row in json.loads(report.read_text())
            }
            for path, rule in [
                (key, "private-key"),
                (identity, "age-secret-key"),
                (provenance, "generic-api-key"),
            ]:
                self.assertTrue(
                    any(
                        name.endswith(path.relative_to(root).as_posix())
                        and kind == rule
                        for name, kind in findings
                    ),
                    rule,
                )

    def test_upstream_license_notices(self):
        record = json.loads((PROJECT / "security/age-source.json").read_text())
        revision = json.loads(
            (PROJECT / "vendor/age/.cargo_vcs_info.json").read_text()
        )["git"]["sha1"]
        self.assertEqual(
            set(record["supplementalFiles"]),
            {"vendor/LICENSE-MIT", "vendor/LICENSE-APACHE"},
        )
        for name, provenance in record["supplementalFiles"].items():
            payload = (PROJECT / name).read_bytes()
            self.assertEqual(hashlib.sha256(payload).hexdigest(), provenance["sha256"])
            self.assertEqual(
                provenance["url"],
                f"https://raw.githubusercontent.com/str4d/rage/{revision}/{Path(name).name}",
            )
        self.assertIn(
            "Copyright (c) 2019 Jack Grigg",
            (PROJECT / "vendor/LICENSE-MIT").read_text(),
        )
        self.assertIn(
            "Version 2.0, January 2004", (PROJECT / "vendor/LICENSE-APACHE").read_text()
        )

    def test_age_source_inventory(self):
        record = json.loads((PROJECT / "security/age-source.json").read_text())
        self.assertEqual(record["format"], "nix-seal.vendored-source.v1")
        self.assertEqual(record["package"], "age")
        self.assertEqual(record["version"], "0.12.1")
        self.assertEqual(
            set(record["modifiedFiles"]),
            {
                "Cargo.toml",
                "src/lib.rs",
                "src/native.rs",
                "src/cli_common/recipients.rs",
                "src/error.rs",
                "src/ssh.rs",
                "src/ssh/identity.rs",
                "src/ssh/recipient.rs",
            },
        )
        expected = record["upstreamFiles"] | record["modifiedFiles"]
        for name in record["removedFiles"]:
            del expected[name]
        vendor = PROJECT / "vendor/age"
        actual = {}
        for path in vendor.rglob("*"):
            self.assertFalse(path.is_symlink(), path)
            if path.is_file():
                actual[path.relative_to(vendor).as_posix()] = hashlib.sha256(
                    path.read_bytes(),
                ).hexdigest()
        self.assertEqual(actual, expected)

    def test_both_workspaces_exclude_removed_dependencies(self):
        for directory in [PROJECT, PROJECT / "fuzz"]:
            with self.subTest(workspace=directory.name):
                lock = tomllib.loads((directory / "Cargo.lock").read_text())
                packages = lock["package"]
                names = {package["name"] for package in packages}
                self.assertFalse(names & {"crypto-bigint", "basic-toml", "p256", "rsa"})
                age = next(package for package in packages if package["name"] == "age")
                self.assertNotIn("source", age)
                config = next(
                    package for package in packages if package["name"] == "i18n-config"
                )
                self.assertTrue(
                    config["source"].endswith(
                        "#2ce7b1dfe9a8cc224288bf50cbc2a67a6de863c4",
                    ),
                )

    def test_legacy_workspace_contract(self):
        root = tomllib.loads((PROJECT / "Cargo.toml").read_text())
        cli = tomllib.loads((PROJECT / "crates/nix-seal-cli/Cargo.toml").read_text())
        legacy = tomllib.loads((PROJECT / "legacy/Cargo.toml").read_text())
        self.assertIn("legacy", root["workspace"]["exclude"])
        self.assertEqual(
            legacy["package"]["version"], root["workspace"]["package"]["version"]
        )
        self.assertEqual(legacy["profile"], root["profile"])
        for field in ["edition", "rust-version", "license", "repository"]:
            self.assertEqual(
                legacy["package"][field], root["workspace"]["package"][field]
            )
        self.assertEqual(legacy["lints"], root["workspace"]["lints"])
        dependencies = legacy["dependencies"].copy()
        age = dependencies.pop("age")
        self.assertEqual(age["features"], ["ssh-rsa"])
        self.assertEqual(
            age["version"], root["workspace"]["dependencies"]["age"]["version"]
        )
        expected = {
            name: root["workspace"]["dependencies"][name]
            for name in cli["dependencies"]
        }
        for specification in dependencies.values():
            if isinstance(specification, dict) and "path" in specification:
                specification["path"] = specification["path"].removeprefix("../")
        self.assertEqual(dependencies, expected)
        self.assertEqual(
            set(legacy["patch"]["crates-io"]), set(root["patch"]["crates-io"])
        )
        for name, specification in legacy["patch"]["crates-io"].items():
            if "path" in specification:
                specification["path"] = specification["path"].removeprefix("../")
            self.assertEqual(specification, root["patch"]["crates-io"][name])
        lock = tomllib.loads((PROJECT / "legacy/Cargo.lock").read_text())
        self.assertIn("rsa", {package["name"] for package in lock["package"]})

    def test_rsa_exception_is_scoped_to_legacy(self):
        normal = tomllib.loads((PROJECT / "deny.toml").read_text())
        legacy = tomllib.loads((PROJECT / "legacy/deny.toml").read_text())
        self.assertEqual(normal["advisories"]["ignore"], [])
        self.assertEqual(legacy["advisories"]["ignore"], ["RUSTSEC-2023-0071"])
        self.assertNotIn(
            "IgnoredVulns", tomllib.loads((PROJECT / "osv-scanner.toml").read_text())
        )
        legacy_osv = tomllib.loads((PROJECT / "legacy/osv-scanner.toml").read_text())
        self.assertEqual(len(legacy_osv["IgnoredVulns"]), 1)
        self.assertEqual(legacy_osv["IgnoredVulns"][0]["id"], "RUSTSEC-2023-0071")
        workflow = (PROJECT / ".github/workflows/ci.yml").read_text()
        # OSV's explicit --config overrides every nested policy. Auto-discovery
        # confines the legacy exception to lockfiles in that directory.
        self.assertIn("osv-scanner scan source --recursive .", workflow)
        self.assertNotIn("--config osv-scanner.toml", workflow)
