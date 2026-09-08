"""Read Rust CI inputs from the manifests that own them."""

import argparse
import os
import re
import subprocess
from pathlib import Path

import tomllib


def toolchain(root: Path, *, msrv: bool = False) -> None:
    """Install manifest-selected Rust and select it for subsequent CI steps."""
    config = tomllib.loads((root / "rust-toolchain.toml").read_text())["toolchain"]
    if msrv:
        workspace = tomllib.loads((root / "Cargo.toml").read_text())["workspace"]
        channel = workspace["package"]["rust-version"]
        # Cargo accepts major.minor MSRV; request that exact release's first patch.
        if re.fullmatch(r"\d+\.\d+", channel):
            channel += ".0"
        components = ["clippy"]
        targets = []
        profile = "minimal"
    else:
        channel = config["channel"]
        components = config.get("components", [])
        targets = config.get("targets", [])
        profile = config.get("profile", "minimal")
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_.-]*", channel):
        raise ValueError("CI requires a named Rust channel")
    command = ["rustup", "toolchain", "install", channel, "--profile", profile]
    for component in components:
        command += ["--component", component]
    for target in targets:
        command += ["--target", target]
    subprocess.run(command, check=True)
    with Path(os.environ["GITHUB_ENV"]).open("a") as output:
        output.write(f"RUSTUP_TOOLCHAIN={channel}\n")


def fuzz(root: Path, *, seconds: int = 60) -> int:
    """Run every registered fuzz binary, retaining failures across the campaign."""
    manifest = tomllib.loads((root / "fuzz/Cargo.toml").read_text())
    targets = [entry["name"] for entry in manifest.get("bin", [])]
    if (
        not targets
        or any(not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_-]*", name) for name in targets)
        or len(set(targets)) != len(targets)
    ):
        raise ValueError("Expected a nonempty set of unique Cargo fuzz targets")
    failed = []
    for target in sorted(targets):
        print(f"Fuzzing {target}", flush=True)
        result = subprocess.run(
            ["cargo", "fuzz", "run", target, "--", f"-max_total_time={seconds}"],
            cwd=root / "fuzz",
            check=False,
        )
        if result.returncode:
            failed.append(target)
    if failed:
        print("Failed fuzz targets: " + ", ".join(failed), flush=True)
    return bool(failed)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=["toolchain", "msrv", "fuzz"])
    args = parser.parse_args()
    if args.command == "fuzz":
        raise SystemExit(fuzz(Path.cwd()))
    toolchain(Path.cwd(), msrv=args.command == "msrv")
