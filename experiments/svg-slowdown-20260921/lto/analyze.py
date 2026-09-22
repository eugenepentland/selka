#!/usr/bin/env python3
"""Report the retained O3/LTO section and layout::partPin code-generation deltas."""
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[3]
FUNCTION = "myl_f_df62a071388119a62cbc34c6626eed2a8ad7467e943cef57b27b0db9bf24e6cd"
BINARIES = {
    "o3": ROOT / ".tmp/full-svg-benchmark-20260921/mylang-o3",
    "lto": ROOT / ".tmp/full-svg-benchmark-20260921/mylang-o3-lto",
    "lto-partpin-avx2": ROOT / ".tmp/svg-slowdown-20260921/lto/lto-partpin-avx2",
    "lto-guest-avx2": ROOT / ".tmp/svg-slowdown-20260921/lto/lto-guest-avx2",
}


def output(*args: str) -> str:
    return subprocess.check_output(args, text=True, errors="replace")


for name, binary in BINARIES.items():
    sections = output("readelf", "-SW", str(binary))
    wanted = {}
    for section in (".text", ".rodata", ".data"):
        match = re.search(rf"\] {re.escape(section)}\s+PROGBITS\s+\S+\s+\S+\s+([0-9a-f]+)", sections)
        wanted[section] = int(match.group(1), 16) if match else None
    disassembly = output("objdump", "-d", "--no-show-raw-insn", str(binary))
    function = output("objdump", "-d", "--no-show-raw-insn", f"--disassemble={FUNCTION}", str(binary))
    symbol = next(line for line in output("nm", "-S", str(binary)).splitlines() if line.endswith(FUNCTION))
    size = int(symbol.split()[1], 16)
    print(name, wanted, "partPin_bytes", size,
          "vex_instructions", len(re.findall(r"^ .*:\s+v[a-z]", disassembly, re.M)),
          "partPin_rep_movsq", function.count("rep movsq"),
          "partPin_vmov", len(re.findall(r"\bvmov", function)))
