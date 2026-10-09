#!/usr/bin/env python3
"""Build and run every shapes/*.my in debug, release and release --verify-facts under
the leak check; compare stdout with the file's `# expect:` lines. Prints one row per
shape and mode; exits 1 when any differs."""
import os, subprocess, sys, pathlib, concurrent.futures as cf

here = pathlib.Path(__file__).resolve().parent.parent
root = here.parent.parent
compiler = sys.argv[1] if len(sys.argv) > 1 else str(root / "zig-out/bin/mylang")
out_dir = pathlib.Path(sys.argv[2] if len(sys.argv) > 2 else root / ".tmp/shapes")
out_dir.mkdir(parents=True, exist_ok=True)
modes = {"debug": [], "release": ["--release"], "verify": ["--release", "--verify-facts"]}

def one(path, mode):
    want = [l[len("# expect: "):] for l in path.read_text().splitlines() if l.startswith("# expect: ")]
    exe = out_dir / f"{path.stem}-{mode}"
    b = subprocess.run([compiler, "build", str(path), "-o", str(exe), "--cache-dir", str(root / ".mylang-cache/shapes"), *modes[mode]], capture_output=True, text=True)
    if b.returncode != 0:
        return path.stem, mode, "BUILD-FAIL", b.stderr.strip().splitlines()[-1:] 
    env = dict(os.environ, MYL_CORE_LEAKCHECK="1")
    r = subprocess.run([str(exe)], capture_output=True, text=True, env=env)
    got = r.stdout.strip().splitlines()
    ok = got == want and r.returncode == 0
    return path.stem, mode, "ok" if ok else "WRONG", ([] if ok else [f"got={got} want={want} rc={r.returncode} err={r.stderr.strip()[-200:]}"])

paths = sorted((here / "shapes").glob("*.my"))
jobs = [(p, m) for p in paths for m in modes]
bad = 0
with cf.ThreadPoolExecutor(int(os.environ.get("JOBS", "4"))) as pool:
    for stem, mode, verdict, detail in pool.map(lambda a: one(*a), jobs):
        bad += verdict != "ok"
        print(f"{stem:28} {mode:8} {verdict}", *detail)
print(f"{len(jobs) - bad}/{len(jobs)} ok")
sys.exit(1 if bad else 0)
