#!/usr/bin/env python3
"""CE2-X harness (from CE-X's): CE-A's ce.py (adapted from VP3's tools/vp3.py) with CE-X's paths. Build ordinary and counting
(`--counters`) binaries with one compiler, run VP3's cells, check that both builds
print the same and that the outputs are right, and keep the counters JSON gzipped
under raw/<tag>/.

  ce.py --compiler PATH --tag TAG build GROUP     GROUP: lox, eda, parity, rows, all
  ce.py --compiler PATH --tag TAG run GROUP
  ce.py --tag TAG summary [--against TAG]          bytes moved per pattern and corpus

Runs are pinned off the timing CPUs 2, 3, 10, 11. Counts only: no timing is taken.
"""
import argparse, collections, concurrent.futures, gzip, hashlib, importlib.util, json, os, pathlib, shutil, subprocess, sys

ROOT = pathlib.Path(__file__).resolve().parents[3]
AREA = pathlib.Path(__file__).resolve().parents[1]
CACHE = ROOT / ".mylang-cache/rp3/ce"
SLOT = ROOT / "scripts/build-slot.sh"
CPUS = "0,1,4-9,12-19"
LOX = ROOT / ".mylang-cache/lox"
LOX_SRC = LOX / "ports/mylang"
LOX_SCRIPTS = LOX / "bench"
EDA = pathlib.Path("/home/epentland/ai/canopy/eda-bench-wt/claude-eda-bench-newcore")
EDA_SRC = ROOT / ".mylang-cache/eda-src"   # a copy of the read-only EDA tree's mylang/
VP3 = ROOT / "experiments/vk-vp3-20261008"
from outputs import parity_programs
_PARITY_PROGRAMS = parity_programs()
PARITY = {path.stem: str(path.relative_to(ROOT / "bench/parity").with_suffix(""))
          for _, path, _ in _PARITY_PROGRAMS}
PARITY_EXPECTED = {path.stem: expected for _, path, expected in _PARITY_PROGRAMS}


def env():
    e = dict(os.environ)
    e["TMPDIR"] = str(ROOT / ".tmp/rp3")
    e.setdefault("MYLANG_CORE_RUNTIME_CACHE", str(ROOT / ".mylang-cache/runtime-rp3-base"))
    return e


def digest_bytes(data):
    return hashlib.sha256(data).hexdigest()


def digest(path):
    return digest_bytes(pathlib.Path(path).read_bytes())


def run(argv, cwd=ROOT, extra_env=None, slot=False, timeout=3600):
    full = [str(SLOT), "build", *map(str, argv)] if slot else ["taskset", "-c", CPUS, *map(str, argv)]
    e = env()
    e.update(extra_env or {})
    try:
        done = subprocess.run(full, cwd=cwd, env=e, capture_output=True, timeout=timeout)
        return done.returncode, done.stdout, done.stderr
    except subprocess.TimeoutExpired as expired:
        return "timeout", expired.stdout or b"", expired.stderr or b""


class Lane:
    def __init__(self, compiler, tag):
        self.compiler = pathlib.Path(compiler).resolve() if compiler else None
        self.tag = tag
        self.bins = CACHE / "bin" / tag
        self.raw = CACHE / "raw" / tag
        self.cache = CACHE / "cache" / tag

    def build(self, label, source, output, cwd, counting, links=()):
        argv = [self.compiler, "build", source, "-o", output, "--cache-dir", self.cache, "--release"]
        if counting:
            argv.append("--counters")
        for link in links:
            argv += ["--link", link]
        status, _, err = run(argv, cwd=cwd, slot=True)
        if status != 0:
            raise SystemExit(f"build failed: {label}\n{err.decode(errors='replace')[-3000:]}")

    def build_group(self, group):
        self.bins.mkdir(parents=True, exist_ok=True)
        kinds = (("plain", False), ("count", True))
        if group == "lox":
            for kind, counting in kinds:
                self.build(f"lox-{kind}", LOX_SRC / "main.my", self.bins / f"lox-{kind}", LOX_SRC, counting)
        elif group == "eda":
            for kind, counting in kinds:
                self.build(f"eda-{kind}", "src/main.my", self.bins / f"eda-{kind}", EDA_SRC, counting)
        elif group == "parity":
            for name, path in PARITY.items():
                for kind, counting in kinds:
                    self.build(f"parity-{name}-{kind}", ROOT / f"bench/parity/{path}.my", self.bins / f"parity-{name}-{kind}", ROOT, counting)
        elif group == "rows":
            clock = ROOT / "benchmarks/runtime/ports/native_clock.c"
            jobs = []
            with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
                for name, path in row_sources().items():
                    for kind, counting in kinds:
                        jobs.append(pool.submit(self.build, f"row-{name}-{kind}", path, self.bins / f"row-{name}-{kind}", ROOT, counting, (clock,)))
                for job in jobs:
                    job.result()

    def counted_run(self, label, args, cwd, timeout, normalize=lambda out: out, compare=None):
        counts = CACHE / "counts" / self.tag / f"{label}.json"
        counts.parent.mkdir(parents=True, exist_ok=True)
        counts.unlink(missing_ok=True)
        sc, oc, ec = run([self.bins / f"{label.split(':')[0]}-count", *args(True)], cwd=cwd, extra_env={"MYLANG_COUNTERS": str(counts)}, timeout=timeout)
        sp, op, ep = run([self.bins / f"{label.split(':')[0]}-plain", *args(False)], cwd=cwd, timeout=timeout)
        same = sc == sp and normalize(oc) == normalize(op) and ec == ep
        detail = compare() if compare else {}
        name = label.replace(":", "-")
        if counts.exists():
            self.raw.mkdir(parents=True, exist_ok=True)
            with gzip.open(self.raw / f"{name}.json.gz", "wb", compresslevel=9) as f:
                f.write(counts.read_bytes())
        return {"label": name, "status": sc, "plain_status": sp, "same_output": same, "stdout_sha256": digest_bytes(op),
                "stdout": op.decode(errors="replace")[:2000], "stderr": ep.decode(errors="replace")[-2000:], "counts": counts.exists(), **detail}


def row_registry():
    path = ROOT / "experiments/new-core-s4-20261006/integration/measure_all46.py"
    spec = importlib.util.spec_from_file_location("ce_rows", path)
    registry = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(registry)
    assert len(registry.rows.UNITS) == 46
    return registry.rows


def row_sources():
    rows = row_registry()
    sources = {name: ROOT / "test/core" / (rows.stem(name) + ".my") for name in rows.UNITS}
    for name in ("json_transform", "union_find"):
        sources[name] = AREA / "M0/row-sources" / ("row_" + name + ".my")
    return sources


def vp3_cells(group):
    """VP3's cells: the same scripts, sizes and arguments."""
    return json.loads((VP3 / "results" / f"{group}.json").read_text())


def lox_script(name, n):
    text = (LOX_SCRIPTS / "scripts" / f"{name}.lox").read_text()
    first, rest = text.split("\n", 1)
    assert first.startswith("var N = "), first
    directory = CACHE / "lox-scripts"
    directory.mkdir(parents=True, exist_ok=True)
    path = directory / f"{name}-{n}.lox"
    path.write_text(f"var N = {n};\n{rest}")
    return path


def run_lox(lane):
    results = {}
    cells = [(v["engine"], v["script"], v["n"]) for v in vp3_cells("lox").values()]
    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
        jobs = []
        for engine, name, n in cells:
            script = lox_script(name, n)
            label = f"lox:{engine}-{name}-{n}"
            jobs.append((engine, name, n, pool.submit(lane.counted_run, label, lambda counting, engine=engine, script=script: [f"--engine={engine}", script], CACHE, 1800)))
        for engine, name, n, job in jobs:
            result = job.result()
            result.update(engine=engine, script=name, n=n)
            results[result["label"]] = result
    return results


def run_eda(lane):
    cases = json.loads((EDA / "golden/manifest.json").read_text())["cases"]
    outputs = CACHE / "eda-out" / lane.tag

    def one(case):
        def args(counting):
            directory = outputs / ("count" if counting else "plain") / case["id"]
            if directory.exists():
                shutil.rmtree(directory)
            directory.mkdir(parents=True)
            return ["--model", f"golden/cases/{case['id']}/model.sexp", "--project-dir", f"golden/projects/{case['project']}", "--out-dir", directory, *case["flags"]]

        def compare():
            mismatched = []
            for kind in ("count", "plain"):
                directory = outputs / kind / case["id"]
                produced = {str(p.relative_to(directory)): digest(p) for p in directory.rglob("*") if p.is_file()}
                expected = {name: meta["sha256"] for name, meta in case["outputs"].items()}
                if produced != expected:
                    mismatched.append(kind)
            return {"golden_mismatch": mismatched}

        result = lane.counted_run(f"eda:{case['id']}", args, EDA, 900, compare=compare)
        result["same_output"] = result["same_output"] and not result["golden_mismatch"]
        return result

    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
        return {r["label"]: r for r in pool.map(one, cases)}


def run_parity(lane):
    results = {}
    for name, path in PARITY.items():
        expected = PARITY_EXPECTED[name]
        result = lane.counted_run(f"parity-{name}", lambda counting: [], CACHE, 1800)
        result["matches_expected"] = result["stdout_sha256"] == digest_bytes(expected)
        result["same_output"] = result["same_output"] and result["matches_expected"]
        results[result["label"]] = result
    return results


def run_rows(lane):
    rows = row_registry()
    cells = vp3_cells("rows")

    def one(name):
        cell = cells[f"row-{name}"]
        args = [str(cell["size"]), str(cell["iterations"]), "7"]
        return lane.counted_run(f"row-{name}", lambda counting: args, CACHE, 900, normalize=lambda text: text.split()[:1])

    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
        return {r["label"]: r for r in pool.map(one, list(rows.UNITS))}


# ---- summary -------------------------------------------------------------------------

def pattern(site):
    kind, detail = site["kind"], site["detail"]
    if kind == "record_copy":
        return {"jump": "P1", "branch": "P1", "record_set": "P2", "list_get": "P3", "list_set": "P4", "list_set.old": "P5", "list_push": "P6", "ret": "P7"}.get(detail, "P8")
    return {"list_copy": "P9", "dict_copy": "P10", "text_copy": "P11", "buffer_copy": "P12", "list_push": "P13"}.get(kind)


def load_counts(directory, label):
    path = directory / f"{label}.json.gz"
    return json.load(gzip.open(path)) if path.exists() else None


def by_pattern(data):
    """Bytes moved per pattern in one counters document (VP3's analyze.py rules)."""
    out = collections.Counter()
    for site in data["sites"]:
        name = pattern(site)
        if name is None:
            continue
        moved = site["extra"] if site["kind"] == "list_push" else site["bytes"]
        if moved:
            out[name] += moved
    for row in data["functions"]:
        out["P14"] += row["dict_grow_bytes"] + row["buffer_grow_bytes"] + row["text_grow_bytes"]
    return out


def corpus_of(label):
    return label.split("-", 1)[0]


def primary_labels():
    """VP3's primary cells: the larger N of each Lox cell, every EDA, parity and row cell."""
    labels = []
    lox = vp3_cells("lox")
    for label, v in lox.items():
        if v["n"] == max(w["n"] for w in lox.values() if w["engine"] == v["engine"] and w["script"] == v["script"]):
            labels.append(label)
    labels += ["parity-" + name for name in PARITY]
    for group in ("eda", "rows"):
        labels += list(vp3_cells(group))
    return labels


def totals(directory):
    corpora = collections.defaultdict(collections.Counter)
    per_label = {}
    for label in primary_labels():
        data = load_counts(directory, label)
        if data is None:
            continue
        moved = by_pattern(data)
        per_label[label] = moved
        corpora[{"row": "rows"}.get(corpus_of(label), corpus_of(label))].update(moved)
    return corpora, per_label


def human(value):
    for unit, size in (("T", 1e12), ("G", 1e9), ("M", 1e6), ("k", 1e3)):
        if abs(value) >= size:
            return f"{value / size:.2f} {unit}"
    return f"{value:.0f}"


def summary(tag, against):
    names = ["P1", "P2", "P7", "P8", "P3", "P4", "P5", "P6", "P9", "P13", "P14", "P10", "P11", "P12"]
    raw = raw_dir
    after, _ = totals(raw(tag))
    before, _ = totals(raw(against)) if against else (None, None)
    lines = [f"bytes moved per pattern: {tag}" + (f" against {against}" if against else "")]
    for corpus in ("lox", "eda", "parity", "rows"):
        if corpus not in after:
            continue
        lines.append(f"\n{corpus}: | pattern | before | after | change |")
        target_b = target_a = 0
        for name in names:
            a = after[corpus].get(name, 0)
            b = before[corpus].get(name, 0) if before else 0
            if not a and not b:
                continue
            if name in ("P1", "P2", "P7", "P8"):
                target_a += a
                target_b += b
            change = f"{100 * (a - b) / b:+.1f}%" if b else ("new" if a else "")
            lines.append(f"| {name} | {human(b)} | {human(a)} | {change} |")
        change = f"{100 * (target_a - target_b) / target_b:+.1f}%" if target_b else ""
        lines.append(f"| P1+P2+P7+P8 | {human(target_b)} | {human(target_a)} | {change} |")
        lines.append(f"| all | {human(sum(before[corpus].values())) if before else ''} | {human(sum(after[corpus].values()))} | |")
    print("\n".join(lines))


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("command")
    parser.add_argument("group", nargs="?")
    parser.add_argument("--compiler")
    parser.add_argument("--tag", required=True)
    parser.add_argument("--against")
    args = parser.parse_args()
    lane = Lane(args.compiler, args.tag)
    groups = ["lox", "eda", "parity", "rows"] if args.group == "all" else [args.group]
    if args.command == "build":
        for group in groups:
            lane.build_group(group)
            print(f"built {group}", flush=True)
        return
    if args.command == "run":
        for group in groups:
            results = {"lox": run_lox, "eda": run_eda, "parity": run_parity, "rows": run_rows}[group](lane)
            directory = AREA / "results" / args.tag
            directory.mkdir(parents=True, exist_ok=True)
            (directory / f"{group}.json").write_text(json.dumps(results, indent=1) + "\n")
            bad = [label for label, r in results.items() if r["status"] != 0 or not r["same_output"] or not r["counts"]]
            print(f"{group}: {len(results)} cells, {len(bad)} not identical or uncounted: {bad}", flush=True)
            if bad:
                raise SystemExit(1)
        return
    if args.command == "summary":
        return summary(args.tag, args.against)
    if args.command == "tables":
        tags = args.group.split(",")
        print(json.dumps(tables(tags), indent=1))
        return
    raise SystemExit("unknown command")



# ---- report tables -------------------------------------------------------------------

PATTERNS = ["P1", "P2", "P7", "P8", "P3", "P4", "P5", "P6", "P9", "P13", "P14", "P10", "P11", "P12"]


LANES = {"vp3": VP3 / "raw",
         "ce-a": ROOT / "experiments/ce-records-20261008/raw/final",
         "ce-a-rows": ROOT / "experiments/ce-records-20261008/raw/rows-final",
         "ce-b": ROOT / "experiments/ce-lists-20261008/raw-final",
         "cex": ROOT / "experiments/ce-x-20261008/raw/final",
         "ce2a": ROOT / "experiments/ce2-effects-20261008/raw/final",
         "ce2b": ROOT / "experiments/ce2-results-20261008/raw/final"}


def raw_dir(tag):
    return LANES.get(tag, CACHE / "raw" / tag)


def function_bytes(tag, label, predicate):
    """Bytes moved (every pattern) by the sites of functions `predicate` accepts, in one cell."""
    data = load_counts(raw_dir(tag), label)
    total = 0
    for site in data["sites"]:
        name = pattern(site)
        if name is None or not predicate(site["function"]):
            continue
        total += site["extra"] if site["kind"] == "list_push" else site["bytes"]
    for row in data["functions"]:
        if predicate(row["name"]):
            total += row["dict_grow_bytes"] + row["buffer_grow_bytes"] + row["text_grow_bytes"]
    return total


def dispatches(tag, label):
    """VM dispatches of one Lox VM cell: executions of the uniqueness test at vm.my:433, once per instruction."""
    data = load_counts(raw_dir(tag), label)
    n = sum(s["count"] for s in data["sites"] if s["path"].endswith("vm.my") and s["line"] == 433 and s["kind"] == "unique_test")
    if not n:
        data = load_counts(raw_dir("vp3"), label)
        n = sum(s["count"] for s in data["sites"] if s["path"].endswith("vm.my") and s["line"] == 433 and s["kind"] == "unique_test")
    return n


def tables(tags):
    """The per-pattern tables and highlights of `tags` (the first is the reference), as JSON."""
    out = {"tags": tags, "corpora": {}, "highlights": {}}
    for tag in tags:
        corpora, per_label = totals(raw_dir(tag))
        out["corpora"][tag] = {corpus: dict(counter) for corpus, counter in corpora.items()}
    highlights = out["highlights"]
    for tag in tags:
        h = highlights.setdefault(tag, {})
        moved = sum(by_pattern(load_counts(raw_dir(tag), "lox-vm-fib-27")).values())
        record = sum(by_pattern(load_counts(raw_dir(tag), "lox-vm-fib-27")).get(p, 0) for p in ("P1", "P2", "P7", "P8"))
        n = dispatches(tag, "lox-vm-fib-27")
        h["lox_vm_fib_dispatches"] = n
        h["lox_vm_fib_bytes_per_dispatch"] = moved / n if n else None
        h["lox_vm_fib_record_bytes_per_dispatch"] = record / n if n else None
        h["lox_vm_run_fib_bytes"] = function_bytes(tag, "lox-vm-fib-27", lambda f: f == "vm::run")
        flat = by_pattern(load_counts(raw_dir(tag), "eda-rds3+flat"))
        h["eda_rds3_flat_bytes"] = sum(flat.values())
        h["eda_rds3_flat_record_bytes"] = sum(flat.get(p, 0) for p in ("P1", "P2", "P7", "P8"))
        sexpr = collections.Counter()
        for label in primary_labels():
            if label.startswith("eda-"):
                data = load_counts(raw_dir(tag), label)
                for site in data["sites"]:
                    name = pattern(site)
                    if name and site["function"].startswith("sexpr_"):
                        sexpr[site["function"]] += site["extra"] if site["kind"] == "list_push" else site["bytes"]
        h["eda_sexpr_functions_bytes"] = dict(sexpr.most_common())
        h["rows_record_pass_bytes"] = sum(by_pattern(load_counts(raw_dir(tag), "row-record_pass")).values()) if load_counts(raw_dir(tag), "row-record_pass") else None
    return out


if __name__ == "__main__":
    main()
