#!/usr/bin/env python3
"""Time the edit ladder on one generated tier in every language.

usage: run_scale.py TIER_DIR [--langs mylang,go,rust,zig] [--samples 3] [--skip-cold]

Steps per language (toolchain/std caches primed, project caches empty at the start):
  cold_build      first build of the project
  noop_build      rebuild with nothing changed
  edit_check      body edit in the middle module, then the check-only command
  edit_build      body edit, then build
  edit_test       body edit, then the full test command (the tool's own caching applies)
  iface_build     append a new public function to the middle module, then build
Each edit step writes a fresh constant so no sample can be satisfied by the previous one.
Results: JSON on stdout (min and all samples, max RSS in KB from /usr/bin/time).
"""
import argparse
import json
import os
import re
import shutil
import subprocess
import time
from pathlib import Path

MYLANG = os.environ["MYLANG_BIN"]
GO = "/home/epentland/.local/bin/go"
CARGO = "/home/epentland/.cargo/bin/cargo"
ZIG = "/home/epentland/.local/bin/zig"
TIME = "/usr/bin/time"


def run(cmd, cwd, env):
    wrapped = ["taskset", "-c", os.environ.get("SCALE_CPUS", "0-11")] + ([TIME, "-f", "__RSS__ %M"] + cmd if os.path.exists(TIME) else cmd)
    t = time.perf_counter()
    p = subprocess.run(wrapped, cwd=cwd, env=env, capture_output=True, text=True)
    dt = time.perf_counter() - t
    rss = None
    m = re.search(r"__RSS__ (\d+)", p.stderr)
    if m:
        rss = int(m.group(1))
    ok = p.returncode == 0
    return {"s": round(dt, 3), "rss_kb": rss, "ok": ok, "tail": "" if ok else (p.stdout + p.stderr)[-1500:]}


def base(lang):
    return "mylang" if lang.startswith("mylang") else lang


def middle_file(lang, root, M):
    lang = base(lang)
    mid = M // 2
    return {"mylang": root / f"m{mid:03d}.my", "go": root / f"m{mid:03d}" / f"m{mid:03d}.go",
            "rust": root / "src" / f"m{mid:03d}.rs", "zig": root / f"m{mid:03d}.zig"}[lang], mid


def body_edit(path, token):
    s = path.read_text()
    s2, n = re.subn(r"(\+ ?)(\d+)(\)[^\n]*EDIT_BODY)", lambda m: f"{m.group(1)}{token}{m.group(3)}", s, count=1)
    assert n == 1, path
    path.write_text(s2)


def iface_edit(lang, path, mid, token):
    lang = base(lang)
    extra = {
        "mylang": f"\n\npublic def extra_{token}(n: int) -> int:\n    return n + {token}\n",
        "go": f"\nfunc Extra{token}(n int) int {{\n\treturn n + {token}\n}}\n",
        "rust": f"\npub fn extra_{token}(n: i64) -> i64 {{\n    n + {token}\n}}\n",
        "zig": f"\npub fn extra_{token}(n: i64) i64 {{\n    return n + {token};\n}}\n",
    }[lang]
    with path.open("a") as f:
        f.write(extra)


def commands(lang, root, cache):
    out = cache / "bin" / "big"
    (cache / "bin").mkdir(parents=True, exist_ok=True)
    if lang.startswith("mylang"):
        c = f"--cache-dir={cache / 'mylang'}"
        # `mylang build` defaults to ReleaseFast (LLVM -O3 + LTO); `mylang-debug`
        # measures the Debug/QBE build that corresponds to the other languages' dev builds.
        mode = ["--mode", "Debug"] if lang == "mylang-debug" else []
        return {"check": [MYLANG, "check", "main.my"],
                "build": [MYLANG, "build", "main.my", "--project", "-o", str(out), c] + mode,
                "test": [MYLANG, "test", "main.my", "--cache-dir", str(cache / "mytest")],
                "prime": None}
    if lang == "go":
        return {"check": [GO, "vet", "./..."], "build": [GO, "build", "-o", str(out), "./cmd"],
                "test": [GO, "test", "./..."], "prime": None}
    if lang == "rust":
        return {"check": [CARGO, "check", "-q"], "build": [CARGO, "build", "-q"],
                "test": [CARGO, "test", "-q"], "prime": None}
    if lang == "zig":
        c = ["--cache-dir", str(cache / "zig-local")]
        return {"check": [ZIG, "build-exe", "main.zig", "-fno-emit-bin"] + c,
                "build": [ZIG, "build-exe", "main.zig", "-O", "Debug", f"-femit-bin={out}"] + c,
                "test": [ZIG, "test", "main.zig"] + c, "prime": None}


def env_for(lang, cache):
    env = dict(os.environ, TMPDIR="/home/epentland/.cache/mylang-tmp")
    if lang == "go":
        env["GOCACHE"] = str(cache / "gocache")
        env["GOFLAGS"] = "-mod=mod"
    if lang == "rust":
        env["CARGO_TARGET_DIR"] = str(cache / "target")
        env["CARGO_INCREMENTAL"] = "1"
    return env


def prime(lang, cache, env):
    """Warm toolchain/std caches with a hello-world in the same cache dirs (untimed)."""
    p = cache / "prime"
    p.mkdir(parents=True, exist_ok=True)
    if lang.startswith("mylang"):
        (p / "hello.my").write_text("def main(out: Stream) -> int:\n    out.print(1)\n    return 0\n")
        subprocess.run([MYLANG, "build", "hello.my", "-o", "hello", f"--cache-dir={cache / 'mylang'}"], cwd=p, env=env, capture_output=True)
        subprocess.run([MYLANG, "build", "hello.my", "-o", "hello", f"--cache-dir={cache / 'mytest'}"], cwd=p, env=env, capture_output=True)
    elif lang == "go":
        (p / "go.mod").write_text("module prime\n\ngo 1.27\n")
        (p / "main.go").write_text('package main\n\nimport "fmt"\n\nfunc main() { fmt.Println(1) }\n')
        (p / "main_test.go").write_text('package main\n\nimport "testing"\n\nfunc TestX(t *testing.T) {}\n')
        subprocess.run([GO, "build", "./..."], cwd=p, env=env, capture_output=True)
        subprocess.run([GO, "test", "./..."], cwd=p, env=env, capture_output=True)
    elif lang == "zig":
        (p / "main.zig").write_text('const std = @import("std");\npub fn main() void { std.debug.print("1\\n", .{}); }\ntest { }\n')
        subprocess.run([ZIG, "build-exe", "main.zig", "--cache-dir", str(cache / "zig-local")], cwd=p, env=env, capture_output=True)
        subprocess.run([ZIG, "test", "main.zig", "--cache-dir", str(cache / "zig-local")], cwd=p, env=env, capture_output=True)


def loc(root):
    n = 0
    for f in root.rglob("*"):
        if f.suffix in (".my", ".go", ".rs", ".zig") and f.is_file() and not any(part.startswith(".") for part in f.relative_to(root).parts):
            n += sum(1 for line in f.read_text().splitlines() if line.strip())
    return n


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("tier")
    ap.add_argument("--langs", default="mylang,go,rust,zig")
    ap.add_argument("--samples", type=int, default=3)
    ap.add_argument("--skip-cold", action="store_true")
    a = ap.parse_args()
    tier = Path(a.tier).resolve()
    M = len(list((tier / "mylang").glob("m*.my")))
    results = {"tier": tier.name, "modules": M, "load_start": os.getloadavg()}
    for lang in a.langs.split(","):
        src = tier / base(lang)
        work = tier / "work" / lang
        cache = tier / "work" / f"{lang}-cache"
        shutil.rmtree(work, ignore_errors=True)
        shutil.rmtree(cache, ignore_errors=True)
        shutil.copytree(src, work)
        cache.mkdir(parents=True)
        env = env_for(lang, cache)
        prime(lang, cache, env)
        cmds = commands(lang, work, cache)
        target, mid = middle_file(lang, work, M)
        r = {"nonblank_lines": loc(work)}
        r["cold_build"] = run(cmds["build"], work, env)
        r["noop_build"] = run(cmds["build"], work, env)
        run(cmds["test"], work, env)  # warm the test cache (untimed)
        run(cmds["check"], work, env)  # warm the check path (untimed)
        steps = {"edit_check": [], "edit_build": [], "edit_test": [], "iface_build": []}
        for s in range(a.samples):
            for step, cmd in (("edit_check", "check"), ("edit_build", "build"), ("edit_test", "test")):
                body_edit(target, 7000 + 10 * s + len(steps[step]) + {"edit_check": 1, "edit_build": 2, "edit_test": 3}[step])
                steps[step].append(run(cmds[cmd], work, env))
            iface_edit(lang, target, mid, 9000 + s)
            steps["iface_build"].append(run(cmds["build"], work, env))
        for step, samples in steps.items():
            good = [x["s"] for x in samples if x["ok"]]
            r[step] = {"min_s": min(good) if good else None, "samples": samples}
        results[lang] = r
        print(json.dumps({lang: {k: (v if not isinstance(v, dict) or "samples" not in v else {"min_s": v["min_s"]}) for k, v in r.items()}}), flush=True)
    results["load_end"] = os.getloadavg()
    (tier / f"results-{a.langs.replace(',', '_')}.json").write_text(json.dumps(results, indent=1))


if __name__ == "__main__":
    main()
