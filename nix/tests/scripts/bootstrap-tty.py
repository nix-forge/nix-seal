"""Exercise hidden bootstrap input through a real controlling terminal."""

import errno
import json
import os
import pty
import secrets
import select
import signal
import subprocess
import sys
import tempfile
import termios
import time
from pathlib import Path

CLI = str(Path(sys.argv[1]).resolve())


def run(*args, **kwargs):
    return subprocess.run(
        [CLI, *map(str, args)], capture_output=True, check=True, **kwargs
    )


def terminal(args, value):
    pid, fd = pty.fork()
    if pid == 0:
        os.execv(CLI, [CLI, *map(str, args)])
    output = bytearray()
    sent = False
    waited = False
    try:
        deadline = time.monotonic() + 15
        while time.monotonic() < deadline:
            if select.select([fd], [], [], 0.1)[0]:
                try:
                    data = os.read(fd, 4096)
                except OSError as error:
                    if error.errno != errno.EIO:
                        raise
                    break
                if not data:
                    break
                output.extend(data)
            # Wait for echo suppression as well as the public prompt. This
            # catches the Enter-at-end-of-read regression without another line.
            if (
                not sent
                and b": " in output
                and not termios.tcgetattr(fd)[3] & termios.ECHO
            ):
                os.write(fd, value + b"\n")
                sent = True
        else:
            raise AssertionError("bootstrap did not finish after Enter")
        assert sent, "bootstrap never requested hidden input"
        assert termios.tcgetattr(fd)[3] & termios.ECHO, "terminal echo was not restored"
        _, status = os.waitpid(pid, 0)
        waited = True
        assert os.waitstatus_to_exitcode(status) == 0, "terminal bootstrap failed"
        assert value not in output, "terminal echoed the secret"
    finally:
        if not waited:
            os.kill(pid, signal.SIGKILL)
            os.waitpid(pid, 0)
        os.close(fd)


with tempfile.TemporaryDirectory() as directory:
    root = Path(directory).resolve()
    identity = root / "administrator.key"
    authorizer = root / "authorizer.key"
    recipient = (
        run("key", "generate", "--identity-out", identity).stdout.decode().strip()
    )
    public = (
        run("key", "generate-signing", "--key-out", authorizer).stdout.decode().strip()
    )
    signer = (
        run("key", "generate-signing", "--key-out", root / "signer.key")
        .stdout.decode()
        .strip()
    )
    secret = {"source": "secrets/token.age", "sourceCiphertextHash": "0" * 64}
    plan = {
        "schema": "nix-seal.bootstrap-create-plan.v1",
        "identities": {
            "admin": {"kind": "administrator", "public": recipient},
            "authorizer": {"kind": "authorizer", "public": public},
            "signer": {"kind": "signer", "public": signer},
        },
        "secrets": {"host/example/token": secret},
    }
    path = root / "bootstrap.json"
    path.write_text(json.dumps(plan))
    args = [
        "secret",
        "bootstrap",
        "complete",
        "--bootstrap-plan",
        path,
        "--repository-root",
        root,
        "--secret",
        "token",
        "--authorizer-key",
        authorizer,
    ]
    # Duplicate local names must fail before reading private input.
    plan["secrets"]["host/second/token"] = {**secret, "source": "secrets/second.age"}
    path.write_text(json.dumps(plan))
    denied = subprocess.run([CLI, *map(str, args)], input=b"", capture_output=True)
    assert denied.returncode != 0 and b"ambiguous" in denied.stderr
    assert not (root / "secrets").exists()
    del plan["secrets"]["host/second/token"]
    path.write_text(json.dumps(plan))

    value = secrets.token_hex(32).encode()
    terminal([*args, "--interactive"], value)
    # Read back with the administrator identity; plaintext never enters argv,
    # the repository's source tree, or a Nix derivation.
    plan["schema"] = "nix-seal.plan.v2"
    del plan["identities"]["authorizer"]
    path.write_text(json.dumps(plan))
    revealed = run(
        "secret",
        "reveal",
        "--plan",
        path,
        "--repository-root",
        root,
        "--secret",
        "host/example/token",
        "--identity",
        identity,
    )
    assert revealed.stdout == value, "bootstrap changed the entered bytes"

print(
    "hidden bootstrap input, terminal restoration, local names and ambiguity checks passed"
)
