#!/usr/bin/env python3
"""Check the S1 row programs (test/core/row_*.my) against the benchmark programs they were split from.

Each row program is the kernel of one row of benchmarks/runtime/{ports,expanded/compute,
expanded/collections}/main.my with the other rows' setup removed. For every row and several
argument sets this builds, with the old core (`mylang build --release --link native_clock.c`),
the original program and the row program, and requires the same checksum (the first field of
the output; the second is a time). It then tries the new core at debug and release and reports,
per row, whether it builds (its checksum must then match too) or the first construct it refuses.

usage: verify_rows.py [--rows a,b] [--mylang P] [--core P] [--keep DIR]
"""
import argparse, os, re, subprocess, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
CLOCK = os.path.join(ROOT, "benchmarks/runtime/ports/native_clock.c")

# row -> the benchmark program (relative to benchmarks/runtime) holding the original.
ROWS = {
    "record_reads": "ports", "tagged_stack": "ports", "mutate_unique": "ports", "mutate_shared": "ports",
    "record_construct": "expanded/compute", "record_update": "expanded/compute",
    "option_handle": "expanded/compute", "result_propagate": "expanded/compute",
    "list_scan": "expanded/collections", "list_append": "expanded/collections", "list_filter": "expanded/collections",
    "alloc_short": "expanded/collections", "alloc_retained": "expanded/collections", "mutate_nested": "expanded/collections",
}
# size, iterations, seed: small and large element counts, several seeds, an iteration count
# that makes `phase` and `batch` wrap.
CASES = [("64", "300", "7"), ("4096", "40", "7"), ("100", "37", "999983"), ("2", "5", "1"), ("513", "19", "12345")]


def sh(argv, timeout=600):
    done = subprocess.run(argv, capture_output=True, text=True, timeout=timeout, cwd=ROOT)
    return done.returncode, done.stdout, done.stderr


def checksum(output):
    fields = output.split()
    return fields[0] if fields else ""


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--rows", default=",".join(ROWS))
    ap.add_argument("--mylang", default=os.path.join(ROOT, "zig-out/bin/mylang"))
    ap.add_argument("--core", default=os.path.join(ROOT, "zig-out/bin/mylang-core"))
    ap.add_argument("--keep", default=None)
    args = ap.parse_args()
    work = args.keep or tempfile.mkdtemp(prefix="rows.")
    os.makedirs(work, exist_ok=True)
    cache_old = os.path.join(work, "cache-old")
    cache_core = os.path.join(work, "cache-core")
    originals = {}
    for suite in sorted(set(ROWS.values())):
        exe = os.path.join(work, suite.replace("/", "_") + "_original")
        code, out, err = sh([args.mylang, "build", os.path.join(ROOT, "benchmarks/runtime", suite, "main.my"), "-o", exe, "--release", "--link", CLOCK, "--cache-dir", cache_old])
        if code != 0:
            sys.exit("cannot build the original %s:\n%s" % (suite, err))
        originals[suite] = exe
    failures = 0
    print("%-18s %-24s %-12s %s" % ("row", "old core", "new core", "new core status"))
    for row in args.rows.split(","):
        source = os.path.join(ROOT, "test/core/row_%s.my" % row)
        old_exe = os.path.join(work, "row_%s_old" % row)
        code, out, err = sh([args.mylang, "build", source, "-o", old_exe, "--release", "--link", CLOCK, "--cache-dir", cache_old])
        if code != 0:
            print("%-18s the old core cannot build the row program:\n%s" % (row, err[:800]))
            failures += 1
            continue
        same = 0
        for size, iterations, seed in CASES:
            want = checksum(sh([originals[ROWS[row]], row, size, iterations, seed])[1])
            got = checksum(sh([old_exe, size, iterations, seed])[1])
            if want and want == got:
                same += 1
            else:
                failures += 1
                print("%-18s MISMATCH at %s %s %s: original %r, row program %r" % (row, size, iterations, seed, want, got))
        status = []
        for mode, flags in (("debug", []), ("release", ["--release"])):
            new_exe = os.path.join(work, "row_%s_new_%s" % (row, mode))
            code, out, err = sh([args.core, "build", source, "-o", new_exe, "--link", CLOCK, "--cache-dir", cache_core] + flags)
            if code != 0:
                reason = re.search(r"does not support (.*?) yet", err)
                status.append("%s: refused (%s)" % (mode, reason.group(1) if reason else err.strip().splitlines()[-1][:80]))
                continue
            agree = all(checksum(sh([new_exe, s, i, d])[1]) == checksum(sh([originals[ROWS[row]], row, s, i, d])[1]) for s, i, d in CASES)
            failures += 0 if agree else 1
            status.append("%s: %s" % (mode, "same checksums" if agree else "DIFFERENT"))
        print("%-18s %-24s %s" % (row, "%d/%d checksums equal" % (same, len(CASES)), "; ".join(status)))
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
