#!/usr/bin/env python3
"""Record zig cc's effective optimization flags and compare identical LLVM at O2/O3."""
import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import platform
import shlex
import shutil
import subprocess

from benchmark_debug_runtime import SOURCES


FLAGS = ["-target", "x86_64-linux-gnu.2.31", "-march=native",
         "-mllvm", "-x86-experimental-pref-innermost-loop-alignment=6"]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--compiler", type=Path, required=True)
    parser.add_argument("--zig", type=Path, default=shutil.which("zig"))
    parser.add_argument("--output", type=Path, required=True, help="new artifact directory")
    args = parser.parse_args()
    compiler = args.compiler.resolve(strict=True)
    zig = args.zig.resolve(strict=True)
    root = args.output.resolve()
    root.mkdir(parents=True, exist_ok=False)
    environment = {k: v for k, v in os.environ.items()
                   if not k.startswith(("SELKA_", "SELKA_CORE_"))}
    environment.update(SELKA_CORE_RUNTIME_CACHE=str(root / "native"), SELKA_JOBS="2")

    def run(argv):
        result = subprocess.run([str(x) for x in argv], capture_output=True,
                                env=environment, timeout=180)
        if result.returncode:
            raise RuntimeError(f"{argv}: {result.stderr.decode()}")
        return result

    report = {
        "captured_utc": datetime.now(timezone.utc).isoformat(),
        "host": platform.platform(),
        "compiler_sha256": hashlib.sha256(compiler.read_bytes()).hexdigest(),
        "zig_version": run([zig, "version"]).stdout.decode().strip(),
        "target_flags": FLAGS,
        "scope": "Same Release-generated LLVM, runtime objects, target and linker; "
                 "only the requested zig cc -O2/-O3 flag changes. No timing claims.",
        "driver": {}, "cases": {},
    }
    for extension, content in [("ll", "define i32 @main() { ret i32 0 }\n"),
                               ("c", "int main(void) { return 0; }\n")]:
        source = root / ("driver." + extension)
        source.write_text(content)
        report["driver"][extension] = {"source": content, "levels": {}}
        for level in ["-O0", "-O1", "-O2", "-O3"]:
            command = [str(zig), "cc", "-###", "-c", level, *FLAGS,
                       str(source), "-o", str(root / "driver.o")]
            trace = run(command).stderr.decode()
            tokens = shlex.split(trace)
            if "-cc1" not in tokens:
                raise RuntimeError(f"missing Clang driver invocation: {trace}")
            report["driver"][extension]["levels"][level] = {
                "command": command, "clang_version": trace.splitlines()[0],
                "effective_flags": [token for token in tokens if token.startswith("-O")],
            }
            (root / (f"driver-{extension}{level}.txt")).write_text(trace)
    for source in SOURCES:
        directory = root / source.stem
        directory.mkdir()
        llvm = directory / "program.ll"
        run([compiler, "build", source, "--release", "--zig", zig, "--emit-llvm", llvm,
             "--cache-dir", directory / "cache", "-o", directory / "reference"])
        runtime = sorted((root / "native").glob("*.o"))
        if not runtime:
            raise RuntimeError("build published no runtime objects")
        expected = source.with_suffix(".expected").read_bytes()
        case = {"source_sha256": hashlib.sha256(source.read_bytes()).hexdigest(),
                "llvm_sha256": hashlib.sha256(llvm.read_bytes()).hexdigest(),
                "expected_stdout": expected.decode()}
        for level in ["O2", "O3"]:
            binary = directory / level
            obj = directory / (level + ".o")
            run([zig, "cc", "-c", "-" + level, *FLAGS, "-Wno-override-module", "-o", obj, llvm])
            run([zig, "cc", "-" + level, *FLAGS, "-pthread", "-o", binary, obj, *runtime, "-lm"])
            result = run([binary])
            if result.stdout != expected or result.stderr:
                raise RuntimeError(f"{source.stem}/{level}: incorrect output")
            section = directory / (level + ".text")
            run(["objcopy", "--dump-section", ".text=" + str(section), binary])
            code = section.read_bytes()
            case[level] = {"text_bytes": len(code), "text_sha256": hashlib.sha256(code).hexdigest()}
        case["identical_text"] = case["O2"]["text_sha256"] == case["O3"]["text_sha256"]
        report["cases"][source.stem] = case
        print(source.stem, "identical .text:", case["identical_text"], flush=True)
    (root / "results.json").write_text(json.dumps(report, indent=2) + "\n")
    print(root / "results.json")


if __name__ == "__main__":
    main()
