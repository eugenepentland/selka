#!/usr/bin/env python3
"""Qualify resolved LLVM target attributes through real bitcode and execution."""

import hashlib
import json
import os
from pathlib import Path
import shlex
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
ADAPTER = ROOT / "experiments/llvm-backend/qbe_llvm.py"
ZIG = Path(os.environ.get("MYLANG_ZIG", "zig"))
OUT = ROOT / ".tmp/svg-fixes-20260921/llvm-target-qualification"


def run(argv, **kwargs):
    return subprocess.run([str(x) for x in argv], check=True, text=True,
                          capture_output=True, **kwargs)


def policy(extra):
    trace = run([ZIG, "cc", "-###", "-S", *extra, "-x", "c", "/dev/null",
                 "-o", "/dev/null"]).stderr
    command = shlex.split(trace.splitlines()[-1])
    cpu = command[command.index("-target-cpu") + 1]
    features = [command[index + 1] for index, value in enumerate(command[:-1])
                if value == "-target-feature"]
    triple = command[command.index("-triple") + 1]
    return {"triple": triple, "cpu": cpu, "features": features}


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def build(name, selected):
    directory = OUT / name
    directory.mkdir(parents=True, exist_ok=True)
    qbe = directory / "copy.ssa"
    obj = directory / "copy.o"
    ir = directory / "copy.ll"
    source = directory / "main.c"
    binary = directory / "copy-check"
    # A non-export QBE definition still has external linkage in the adapter, and
    # carries its qualified noinline attribute so final-LTO disassembly survives.
    qbe.write_text("""function $copy112(l %src, l %dst) {
@entry
 blit %src, %dst, 112
 ret
}
""")
    source.write_text("""#include <stdint.h>
#include <stdio.h>
#include <string.h>
extern void copy112(intptr_t, intptr_t);
int main(void) {
  unsigned char source[112], destination[112];
  for (int i = 0; i < 112; ++i) source[i] = (unsigned char)(i * 17 + 3);
  memset(destination, 0, sizeof destination);
  copy112((intptr_t)source, (intptr_t)destination);
  if (memcmp(source, destination, sizeof source) != 0) return 2;
  puts("ok");
  return 0;
}
""")
    environment = dict(os.environ,
        MYLANG_QBE_LLVM_ZIG=str(ZIG),
        MYLANG_QBE_LLVM_OPT="-O3",
        MYLANG_QBE_LLVM_EMIT_LTO_OBJECT="1",
        MYLANG_QBE_LLVM_KEEP_IR=str(ir),
        MYLANG_QBE_LLVM_TARGET_CPU=selected["cpu"],
        MYLANG_QBE_LLVM_TARGET_FEATURES=",".join(selected["features"]))
    run([ADAPTER, "-t", "amd64_sysv", "-o", obj, qbe], env=environment)
    run([ZIG, "cc", "-O3", "-flto", obj, source, "-o", binary])
    execution = run([binary]).stdout.strip()
    disassembly = run(["objdump", "-d", "--disassemble=copy112", binary]).stdout
    (directory / "copy.disassembly.txt").write_text(disassembly)
    attributes = [line for line in ir.read_text().splitlines()
                  if line.startswith("attributes #")]
    return {
        "policy": selected,
        "ir_attributes": attributes,
        "bitcode_magic_hex": obj.read_bytes()[:4].hex(),
        "execution": execution,
        "binary_sha256": sha(binary),
        "copy_has_vmov": "vmov" in disassembly,
        "copy_has_rep_movs": "rep movs" in disassembly,
    }


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    native = policy([])
    portable = policy(["-mcpu=baseline"])
    report = {
        "schema": "mylang-llvm-target-qualification-v1",
        "zig": str(ZIG),
        "zig_version": run([ZIG, "version"]).stdout.strip(),
        "adapter": str(ADAPTER.relative_to(ROOT)),
        "adapter_sha256": sha(ADAPTER),
        "native": build("native", native),
        "portable_baseline": build("portable-baseline", portable),
    }
    destination = ROOT / "experiments/svg-fixes-20260921/llvm-target-qualification.json"
    destination.write_text(json.dumps(report, indent=2) + "\n")
    print(destination)


if __name__ == "__main__":
    main()
