#!/usr/bin/env python3
"""Runtime and actual pinned-Clang discovery receipts; run under build admission."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bundle", type=Path, required=True)
    parser.add_argument("--zig", type=Path, required=True)
    parser.add_argument("--work", type=Path, required=True)
    parser.add_argument("--evidence", type=Path, required=True)
    args = parser.parse_args()
    root = args.bundle.resolve() / "rootfs"
    work = args.work.resolve()
    evidence = args.evidence.resolve()
    work.mkdir(parents=True, exist_ok=True)
    evidence.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(Path(__file__).with_name("runtime_probe.c"), work / "runtime_probe.c")
    for directory in ("tmp", "zig-global", "zig-local"):
        (work / directory).mkdir(exist_ok=True)
    prefix = ["bwrap", "--unshare-user", "--ro-bind", str(root), "/", "--ro-bind",
              str(args.zig.resolve().parent), "/opt/selka/toolchain", "--bind", str(work), "/work",
              "--chdir", "/work", "--proc", "/proc", "--dev", "/dev",
              "--setenv", "ZIG_GLOBAL_CACHE_DIR", "/work/zig-global",
              "--setenv", "ZIG_LOCAL_CACHE_DIR", "/work/zig-local", "--setenv", "TMPDIR", "/work/tmp"]
    report = {"bundle": str(args.bundle), "commands": [], "files": []}

    def run(argv):
        result = subprocess.run(argv, text=True, capture_output=True)
        report["commands"].append({"argv": argv, "status": result.returncode,
                                   "stdout": result.stdout, "stderr": result.stderr})
        (evidence / "runtime.json").write_text(json.dumps(report, indent=2) + "\n")
        if result.returncode:
            raise RuntimeError(f"command failed ({result.returncode}): {argv}: {result.stderr}")
        return result

    for name in ("ld-linux-x86-64.so.2", "libc.so.6", "libm.so.6", "libgcc_s.so.1", "libpthread.so.0"):
        path = root / "usr/lib/x86_64-linux-gnu" / name
        report["files"].append({"path": str(path.relative_to(root)), "sha256": hashlib.sha256(path.read_bytes()).hexdigest()})
        dynamic = run(["readelf", "-d", str(path)]).stdout
        assert "RPATH" not in dynamic and "RUNPATH" not in dynamic
    run(prefix + ["--", "/usr/sbin/ldconfig", "-p"])
    for mode, opt in (("debug", "-O0"), ("release", "-O3")):
        argv = prefix + ["--", "/opt/selka/toolchain/zig", "cc", "-target", "x86_64-linux-gnu.2.31",
                         "-march=native", opt, "/work/runtime_probe.c", "-pthread", "-lm", "-o", "/work/" + mode]
        run(["strace", "-f", "-qq", "-e", "trace=%file", "-o", str(evidence / (mode + ".trace"))] + argv)
        dynamic = run(["readelf", "-d", str(work / mode)]).stdout
        assert "RPATH" not in dynamic and "RUNPATH" not in dynamic
        run(prefix + ["--", "/lib64/ld-linux-x86-64.so.2", "--list", "/work/" + mode])
        output = run(prefix + ["--setenv", "LD_DEBUG", "libs,files", "--", "/work/" + mode, "0.5"])
        assert output.stdout == "trace=yes sine=0.479426\n"
        assert "libgcc_s.so.1" in output.stderr
        report[mode + "_sha256"] = hashlib.sha256((work / mode).read_bytes()).hexdigest()
    (evidence / "runtime.json").write_text(json.dumps(report, indent=2) + "\n")
    print("Debug and release pthread/backtrace/math and loader closure passed")


if __name__ == "__main__":
    main()
