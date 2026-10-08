"""Build the exact production C units with live assertions in both RC modes."""
import argparse
from pathlib import Path
import re
import subprocess

parser = argparse.ArgumentParser()
parser.add_argument("--output", type=Path, required=True)
options = parser.parse_args()
options.output.mkdir(parents=True, exist_ok=True)
root = Path(__file__).resolve().parents[2]
source = root / "src/qbe_build.zig"
units = source.read_text().split("const runtime_units =", 1)[1].split("};", 1)[0]
c_files = [str(root / "src" / name) for name in re.findall(r'"([^"]+\.c)"', units)]
for name, rc, counting in (
    ("cache-ticket", 1, 0), ("cache-ticket", 1, 1),
    ("encode-borrow", 1, 0), ("encode-borrow", 0, 0),
):
    proof = Path(__file__).with_name(f"{name}-proof.c")
    executable = options.output / f"{name}-{rc}-{counting}"
    subprocess.run([
        "zig", "cc", "-O3", "-UNDEBUG", "-std=c11", "-Wall", "-Wextra", "-Werror",
        "-ffunction-sections", "-fdata-sections", "-Wl,--gc-sections",
        *(["-DMYL_NATIVE_RC=1"] if rc else []),
        f"-DMYL_NATIVE_RC_COUNTING={counting}", "-I", str(root / "src"),
        *(["-DMYL_RC_CONTRACT_LIBRARY"] if not rc else []),
        str(proof), *c_files, "-lm", "-o", str(executable),
    ], check=True)
    subprocess.run([str(executable)], check=True)
