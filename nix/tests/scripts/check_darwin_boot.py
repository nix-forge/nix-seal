"""Exercise generated launchd arguments with a blocking wait4path adapter."""

import json
import subprocess
import sys
import tempfile
from pathlib import Path


def check(arguments: list[str], directory: Path) -> None:
    assert arguments[:2] == ["/bin/sh", "-c"], arguments
    adapter = directory / "wait4path"
    adapter.write_text(
        '#!/bin/sh\nprintf "%s\\n" "$1"\nread -r result\nexit "$result"\n',
        encoding="utf-8",
    )
    adapter.chmod(0o700)
    script = arguments[2].replace("/bin/wait4path", str(adapter))
    assert script != arguments[2]
    assert arguments[4].startswith("/nix/store/")
    assert arguments[4].endswith("/bin/nix-seal")
    assert arguments[5:]
    probe = directory / "probe"
    probe.write_text('#!/bin/sh\nprintf "%s\\n" "$@"\nexit 17\n', encoding="utf-8")
    probe.chmod(0o700)
    payload = "spaces ' quotes $literal; untouched"
    for wait_status in (0, 1):
        # Replace only the unavailable platform binary. Retain every generated
        # argument, including its spec and identity paths, through the probe.
        command = [
            *arguments[:2],
            script,
            arguments[3],
            str(probe),
            *arguments[5:],
            payload,
        ]
        with subprocess.Popen(
            command,
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        ) as process:
            assert process.stdout is not None
            assert process.stdout.readline() == str(probe) + "\n"
            assert process.poll() is None, "execution did not wait for readiness"
            stdout, stderr = process.communicate(f"{wait_status}\n", timeout=10)
            assert not stderr, stderr
            assert process.returncode == (17 if wait_status == 0 else 1)
            expected = "\n".join([*arguments[5:], payload]) + "\n"
            assert stdout == (expected if wait_status == 0 else "")


with tempfile.TemporaryDirectory() as temporary:
    for name, argv in json.loads(Path(sys.argv[1]).read_text(encoding="utf-8")).items():
        check(argv, Path(temporary))
        print(f"{name}: wait, argument preservation, and failure propagation passed")
