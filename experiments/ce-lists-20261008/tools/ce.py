#!/usr/bin/env python3
"""CE-B harness: VP3's programs, sizes and pattern rules, run with a chosen compiler.

  ce.py build GROUP --stage S [--compiler PATH]   ordinary + counting binaries (lox, eda, parity, rows)
  ce.py run GROUP --stage S                       counting run + ordinary run, outputs compared
  ce.py summary --stage S                         bytes moved per pattern per corpus vs VP3

Everything heavy (binaries, raw counts) lives under .mylang-cache/ce; this directory keeps
the per-stage results and summaries (and, for the final stage, gzipped raw counts).
Builds go through scripts/build-slot.sh; runs avoid the timing CPUs 2, 3, 10, 11. Counts only.
"""
import argparse, collections, concurrent.futures, gzip, hashlib, importlib.util, json, os, pathlib, shutil, subprocess, sys

ROOT = pathlib.Path(__file__).resolve().parents[3]
AREA = pathlib.Path(__file__).resolve().parents[1]
VP3 = ROOT / "experiments/vk-vp3-20261008"
CACHE = ROOT / ".mylang-cache/ce"
SLOT = ROOT / "scripts/build-slot.sh"
CPUS = "0,1,4-9,12-19"
LOX_SRC = ROOT / ".mylang-cache/lox/ports/mylang"
LOX_SCRIPTS = pathlib.Path("/home/epentland/ai/canopy/mylang-worktrees/claude-bench-newcore/.mylang-cache/bench/lox/bench")
EDA = pathlib.Path("/home/epentland/ai/canopy/eda-bench-wt/claude-eda-bench-newcore")
PARITY = {"nbody": ("suite/nbody", 5_000_000, "steps"), "str_build": ("micro/str_build", 16_000_000, "appends"),
          "matmul": ("suite/matmul", 500 ** 3, "multiply-adds"), "knucleotide": ("suite/knucleotide", 1_000_000, "sequence bytes")}

spec = importlib.util.spec_from_file_location("vp3_analyze", VP3 / "tools/analyze.py")
analyze = importlib.util.module_from_spec(spec)
spec.loader.exec_module(analyze)


def env():
    e = dict(os.environ)
    e["TMPDIR"] = str(ROOT / ".tmp")
    e["MYLANG_CORE_RUNTIME_CACHE"] = str(ROOT / ".mylang-cache/core-runtime")
    return e


def digest_bytes(data):
    return hashlib.sha256(data).hexdigest()


def run(argv, cwd, extra_env=None, slot=False, timeout=3600):
    full = [str(SLOT), "build", *map(str, argv)] if slot else ["taskset", "-c", CPUS, *map(str, argv)]
    e = env()
    e.update(extra_env or {})
    try:
        done = subprocess.run(full, cwd=cwd, env=e, capture_output=True, timeout=timeout)
        return done.returncode, done.stdout, done.stderr
    except subprocess.TimeoutExpired as expired:
        return "timeout", expired.stdout or b"", expired.stderr or b""


def bins(stage):
    d = CACHE / "bin" / stage
    d.mkdir(parents=True, exist_ok=True)
    return d


def build_one(compiler, source, output, cwd, counting, links=()):
    argv = [compiler, "build", source, "-o", output, "--cache-dir", CACHE / "cache", "--release"]
    if counting:
        argv.append("--counters")
    for link in links:
        argv += ["--link", link]
    status, out, err = run(argv, cwd, slot=True)
    if status != 0:
        raise SystemExit(f"build failed: {output}\n{err.decode(errors='replace')[-3000:]}")


def row_registry():
    path = ROOT / "experiments/new-core-s4-20261006/integration/measure_all46.py"
    s = importlib.util.spec_from_file_location("ce_rows", path)
    registry = importlib.util.module_from_spec(s)
    s.loader.exec_module(registry)
    return registry.rows


def row_sources():
    rows = row_registry()
    return {name: ROOT / "test/core" / (rows.stem(name) + ".my") for name in rows.UNITS}


def build_group(group, stage, compiler):
    out = bins(stage)
    jobs = []
    if group == "lox":
        for c in (False, True):
            jobs.append((LOX_SRC / "main.my", out / f"lox-{'count' if c else 'plain'}", LOX_SRC, c, ()))
    elif group == "eda":
        for c in (False, True):
            jobs.append(("src/main.my", out / f"eda-{'count' if c else 'plain'}", EDA / "mylang", c, ()))
    elif group == "parity":
        for name, (path, _, _) in PARITY.items():
            for c in (False, True):
                jobs.append((ROOT / f"bench/parity/{path}.my", out / f"parity-{name}-{'count' if c else 'plain'}", ROOT, c, ()))
    elif group == "rows":
        clock = ROOT / "benchmarks/runtime/ports/native_clock.c"
        for name, path in row_sources().items():
            for c in (False, True):
                jobs.append((path, out / f"row-{name}-{'count' if c else 'plain'}", ROOT, c, (clock,)))
    with concurrent.futures.ThreadPoolExecutor(max_workers=3) as pool:
        list(pool.map(lambda j: build_one(compiler, *j), jobs))


def counted_run(stage, label, count_bin, plain_bin, args, cwd, timeout, compare=None, normalize=lambda o: o):
    counts = CACHE / "counts" / stage / f"{label}.json"
    counts.parent.mkdir(parents=True, exist_ok=True)
    counts.unlink(missing_ok=True)
    sc, oc, ec = run([count_bin, *args(True)], cwd, {"MYLANG_COUNTERS": str(counts)}, timeout=timeout)
    sp, op, ep = run([plain_bin, *args(False)], cwd, timeout=timeout)
    same = sc == sp and normalize(oc) == normalize(op) and ec == ep
    detail = compare() if compare else {}
    same = same and detail.get("same", True)
    raw = CACHE / "raw" / stage
    raw.mkdir(parents=True, exist_ok=True)
    if counts.exists():
        with gzip.open(raw / f"{label}.json.gz", "wb", compresslevel=9) as f:
            f.write(counts.read_bytes())
    return {"label": label, "status": sc, "plain_status": sp, "same_output": same, "stdout_sha256": digest_bytes(op), "outputs": detail, "counts": counts.exists()}


def lox_cells():
    r = json.loads((VP3 / "results/lox.json").read_text())
    return sorted((v["engine"], v["script"], v["n"]) for v in r.values())


def lox_script(name, n):
    text = (LOX_SCRIPTS / "scripts" / f"{name}.lox").read_text()
    first, rest = text.split("\n", 1)
    d = CACHE / "lox-scripts"
    d.mkdir(parents=True, exist_ok=True)
    p = d / f"{name}-{n}.lox"
    p.write_text(f"var N = {n};\n{rest}")
    return p


def run_group(group, stage, only=None):
    out = bins(stage)
    results = {}
    jobs = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
        if group == "lox":
            for engine, name, n in lox_cells():
                if only and only not in f"{engine}-{name}":
                    continue
                script = lox_script(name, n)
                label = f"lox-{engine}-{name}-{n}"
                jobs.append((label, {"engine": engine, "script": name, "n": n}, pool.submit(counted_run, stage, label, out / "lox-count", out / "lox-plain",
                                                                                            lambda c, engine=engine, script=script: [f"--engine={engine}", script], CACHE, 1800)))
        elif group == "eda":
            cases = json.loads((EDA / "golden/manifest.json").read_text())["cases"]
            for case in cases:
                label = f"eda-{case['id']}"
                outdir = CACHE / "eda-out" / stage

                def args(c, case=case, outdir=outdir):
                    d = outdir / ("count" if c else "plain") / case["id"]
                    if d.exists():
                        shutil.rmtree(d)
                    d.mkdir(parents=True)
                    return ["--model", f"golden/cases/{case['id']}/model.sexp", "--project-dir", f"golden/projects/{case['project']}", "--out-dir", d, *case["flags"]]

                def compare(case=case, outdir=outdir):
                    bad = []
                    for kind in ("count", "plain"):
                        d = outdir / kind / case["id"]
                        produced = {str(p.relative_to(d)): hashlib.sha256(p.read_bytes()).hexdigest() for p in d.rglob("*") if p.is_file()}
                        if produced != {k: m["sha256"] for k, m in case["outputs"].items()}:
                            bad.append(kind)
                    return {"same": not bad, "golden_mismatch": bad}
                jobs.append((label, {"case": case["id"]}, pool.submit(counted_run, stage, label, out / "eda-count", out / "eda-plain", args, EDA, 900, compare)))
        elif group == "parity":
            for name, (path, units, unit) in PARITY.items():
                label = f"parity-{name}"
                expected = (ROOT / f"bench/parity/{path}.expected").read_bytes()
                jobs.append((label, {"program": name, "units": units, "unit": unit, "expected_sha256": digest_bytes(expected)},
                             pool.submit(counted_run, stage, label, out / f"parity-{name}-count", out / f"parity-{name}-plain", lambda c: [], CACHE, 1800)))
        elif group == "rows":
            rows = row_registry()
            vp3 = json.loads((VP3 / "results/rows.json").read_text())
            for name in rows.UNITS:
                label = f"row-{name}"
                base = vp3[label]
                jobs.append((label, {"row": name, "unit": base["unit"], "work": base["work"], "size": base["size"], "iterations": base["iterations"]},
                             pool.submit(counted_run, stage, label, out / f"row-{name}-count", out / f"row-{name}-plain", lambda c, b=base: [str(b["size"]), str(b["iterations"]), "7"], CACHE, 900,
                                         None, lambda t: t.split()[:1])))
        for label, meta, job in jobs:
            r = job.result()
            r.update(meta)
            if group == "parity":
                r["matches_expected"] = r["stdout_sha256"] == meta["expected_sha256"]
            results[label] = r
            print(json.dumps({k: r.get(k) for k in ("label", "status", "same_output", "matches_expected", "outputs")}), flush=True)
    d = AREA / "results"
    d.mkdir(exist_ok=True)
    path = d / f"{stage}-{group}.json"
    old = json.loads(path.read_text()) if (only and path.exists()) else {}
    old.update(results)
    path.write_text(json.dumps(old, indent=1) + "\n")
    bad = [k for k, v in results.items() if not v["same_output"] or v["status"] != 0 or v.get("matches_expected") is False]
    print("BAD:" if bad else "all same", bad)


def load_raw(stage, label):
    p = (VP3 / "raw" / f"{label}.json.gz") if stage == "vp3" else (CACHE / "raw" / stage / f"{label}.json.gz")
    return json.load(gzip.open(p))


def patterns_of(data):
    by = collections.Counter()
    sites = collections.Counter()
    for site in data["sites"]:
        if site["kind"] not in analyze.COPY_KINDS and site["kind"] != "list_push":
            continue
        moved = analyze.site_bytes(site)
        if not moved:
            continue
        name = analyze.pattern(site).split(" ", 1)[0]
        by[name] += moved
        sites[(site["function"], site["path"].split("/")[-1], site["line"], site["kind"], site["detail"], name)] += moved
    for row in data["functions"]:
        other = row["dict_grow_bytes"] + row["buffer_grow_bytes"] + row["text_grow_bytes"]
        if other:
            by["P14"] += other
    return by, sites


def labels_for(group, stage):
    if group == "lox":
        cells = lox_cells()
        bigger = {}
        for e, s, n in cells:
            bigger[(e, s)] = max(bigger.get((e, s), 0), n)
        return [f"lox-{e}-{s}-{n}" for (e, s), n in sorted(bigger.items())]
    r = json.loads((VP3 / "results" / f"{group}.json").read_text())
    return sorted(r)


def summary(stage, top=0):
    out = {}
    for group in ("lox", "eda", "parity", "rows"):
        before, after = collections.Counter(), collections.Counter()
        site_before, site_after = collections.Counter(), collections.Counter()
        missing = []
        for label in labels_for(group, stage):
            try:
                a = load_raw(stage, label)
            except FileNotFoundError:
                missing.append(label)
                continue
            b = load_raw("vp3", label)
            pb, sb = patterns_of(b)
            pa, sa = patterns_of(a)
            before.update(pb)
            after.update(pa)
            site_before.update(sb)
            site_after.update(sa)
        names = sorted(set(before) | set(after), key=lambda n: int(n[1:]))
        out[group] = {"before": dict(before), "after": dict(after), "missing": missing}
        print(f"\n== {group} ({stage} vs VP3){' missing ' + str(len(missing)) if missing else ''}")
        print(f"{'pattern':8} {'VP3':>16} {'now':>16} {'change':>8}")
        for n in names:
            b, a = before[n], after[n]
            ch = f"{100 * (a - b) / b:+.1f}%" if b else ("new" if a else "")
            print(f"{n:8} {b:16,} {a:16,} {ch:>8}")
        tb, ta = sum(before.values()), sum(after.values())
        print(f"{'total':8} {tb:16,} {ta:16,} {100 * (ta - tb) / tb if tb else 0:+.1f}%")
        if top:
            print("  top sites now:")
            for key, v in site_after.most_common(top):
                print(f"   {v:15,} (VP3 {site_before.get(key, 0):15,}) {key}")
    d = AREA / "analysis"
    d.mkdir(exist_ok=True)
    (d / f"{stage}-patterns.json").write_text(json.dumps(out, indent=1) + "\n")


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("command")
    p.add_argument("group", nargs="?")
    p.add_argument("--stage", required=True)
    p.add_argument("--compiler", default=str(ROOT / "zig-out/bin/mylang"))
    p.add_argument("--only")
    p.add_argument("--top", type=int, default=0)
    a = p.parse_args()
    if a.command == "build":
        groups = ["lox", "eda", "parity", "rows"] if a.group == "all" else [a.group]
        for g in groups:
            build_group(g, a.stage, str(pathlib.Path(a.compiler).resolve()))
    elif a.command == "run":
        groups = ["lox", "eda", "parity", "rows"] if a.group == "all" else [a.group]
        for g in groups:
            run_group(g, a.stage, a.only)
    elif a.command == "summary":
        summary(a.stage, a.top)
    else:
        raise SystemExit("unknown command")


if __name__ == "__main__":
    main()
