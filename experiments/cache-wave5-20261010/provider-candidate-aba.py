#!/usr/bin/env python3
"""Reproduce a skipped-provider ABA with system ldd; never invoke guest main.

Only temporary data files are written. The three ldd traces use the same search
symlink and external target inode. An incompatible ELF32 class is skipped, but
the otherwise identical ELF64 bytes temporarily select that candidate.
"""
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile


def main():
    libc = Path("/usr/lib/x86_64-linux-gnu/libc.so.6")
    with libc.open("rb") as stream:
        actual = stream.read(16 * 1024 * 1024 + 1)
    if len(actual) > 16 * 1024 * 1024 or actual[:5] != b"\x7fELF\x02":
        raise ValueError("probe requires bounded system ELF64 glibc")
    wrong = bytearray(actual)
    wrong[4] = 1
    with tempfile.TemporaryDirectory(prefix="provider-symlink-probe-") as area:
        root = Path(area)
        search, outside = root / "search", root / "outside"
        search.mkdir()
        outside.mkdir()
        target = outside / "candidate.so"
        target.write_bytes(wrong)
        link = search / "libc.so.6"
        link.symlink_to(target)
        before = link.lstat()
        before_target = target.stat()
        env = {"PATH": "/bin:/usr/bin", "LC_ALL": "C", "LANG": "C",
               "LD_LIBRARY_PATH": str(search)}
        statuses = []

        def selected():
            run = subprocess.run(["/usr/bin/ldd", "/usr/bin/true"], env=env,
                                 capture_output=True, timeout=15)
            statuses.append(run.returncode)
            if run.returncode:
                raise RuntimeError(run.stderr.decode(errors="replace"))
            value = next(line.split("=>", 1)[1].split()[0]
                         for line in run.stdout.decode().splitlines()
                         if "libc.so.6 =>" in line)
            return value.replace(str(root), "<temp>")

        baseline = selected()
        target.write_bytes(actual)
        transient = selected()
        target.write_bytes(wrong)
        restored = selected()
        evidence = {"version": "juice-provider-candidate-aba-v1",
                    "scope": "ldd resolution traces; no guest main or compiler execution",
                    "command": ["/usr/bin/ldd", "/usr/bin/true"],
                    "candidate": "<temp>/search/libc.so.6",
                    "target": "<temp>/outside/candidate.so",
                    "mutations": ["ELF class 32", "ELF class 64", "ELF class 32"],
                    "original_libc_sha256": hashlib.sha256(actual).hexdigest(),
                    "statuses": statuses, "baseline": baseline,
                    "transient": transient, "restored": restored,
                    "symlink_identity_unchanged": before == link.lstat(),
                    "target_inode_unchanged": before_target.st_ino == target.stat().st_ino,
                    "passed": baseline == restored and baseline != transient
                              and before == link.lstat()}
        print(json.dumps(evidence, sort_keys=True, indent=2))
        if not evidence["passed"]:
            raise RuntimeError("expected skipped-provider ABA was not reproduced")


if __name__ == "__main__":
    main()
