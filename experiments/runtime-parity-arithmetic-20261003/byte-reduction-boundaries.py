"""Untimed QBE/LLVM trap and prefix-output oracle; run in a build slot."""
import hashlib
import json
import os
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
TEMP = Path(os.environ["TMPDIR"])
COMPILER = ROOT / os.environ.get("P9_COMPILER", "zig-out/bin/mylang")
QBE = ROOT / "zig-out/focus/qbe"
CASES = [(-1, -(1 << 63)), (256, (1 << 63) - 2),
         ((1 << 63) - 1, 0), (-(1 << 63), 0), (0, (1 << 63) - 2)]


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


results = []
for index, (mask, seed) in enumerate(CASES):
    source = TEMP / f"byte-reduction-trap-{index}.my"
    source.write_text(
        "def reduce(raw: bytes, mask: int, seed: int) -> int:\n"
        "    total = seed\n    for value in raw:\n"
        "        total += value ^ mask\n    return total\n\n"
        "def main(out: Stream) -> int:\n"
        "    raw = bytes([(i * 37) % 256 for i in range(32)])\n"
        f"    out.print(\"before\")\n    result = reduce(raw, {mask}, {seed})\n"
        "    out.print(\"after\")\n    return result\n")
    observed = {}
    for backend in ("qbe", "llvm"):
        exe = TEMP / f"byte-reduction-trap-{index}-{backend}"
        flags = ["--qbe", str(QBE)] if backend == "qbe" else ["--release"]
        command = [str(COMPILER), "build", str(source), *flags, "-o", str(exe)]
        subprocess.run(command, check=True, cwd=ROOT)
        run = subprocess.run([str(exe)], text=True, capture_output=True)
        observed[backend] = {"command": command, "executable_sha256": digest(exe),
                             "returncode": run.returncode, "stdout": run.stdout,
                             "stderr": run.stderr}
        assert run.returncode != 0 and "R_OVERFLOW" in run.stderr
        assert "before" in run.stdout and "after" not in run.stdout
    for field in ("returncode", "stdout", "stderr"):
        assert observed["qbe"][field] == observed["llvm"][field], (index, field)
    results.append({"mask": mask, "seed": seed, "source_sha256": digest(source),
                    "observed": observed})

receipt = {"kind": "untimed-fast-native-boundary-diagnostic",
           "compiler_sha256": digest(COMPILER), "qbe_sha256": digest(QBE),
           "zig_version": subprocess.check_output(["zig", "version"], text=True).strip(),
           "cases": results}
(HERE / "p9-byte-reduction-boundaries.json").write_text(json.dumps(receipt, indent=2) + "\n")
print(f"{len(results)} exact QBE/LLVM arithmetic traps and prefix outputs matched")
