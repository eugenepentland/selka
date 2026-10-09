#!/usr/bin/env python3
"""CE-X item 8: the final compiler's ordinary (`--release`) binaries print what the base
compiler's print, on VP3's cells: Lox (48 cells; stdout, stderr, status), EDA (34 designs;
both output directories byte-identical to the goldens), parity (4; stdout and status) and
the 46 rows (checksum, the first output field). Uses ce.py's binaries under
.mylang-cache/cex/ce/bin/{base,final}. Runs off the timing CPUs. usage: identity.py OUT.json"""
import concurrent.futures, json, shutil, sys, pathlib
sys.path.insert(0, str(pathlib.Path(__file__).parent))
import ce

BIN = {tag: ce.CACHE / "bin" / tag for tag in ("base", "final")}


def both(label, args, cwd, timeout, normalize=lambda out: out):
    outs = {}
    for tag in ("base", "final"):
        status, out, err = ce.run([BIN[tag] / f"{label}-plain", *args(tag)], cwd=cwd, timeout=timeout)
        outs[tag] = (status, normalize(out), err)
    same = outs["base"] == outs["final"]
    return {"same": same, "status": {t: o[0] for t, o in outs.items()},
            "stdout_sha256": {t: ce.digest_bytes(o[1] if isinstance(o[1], bytes) else repr(o[1]).encode()) for t, o in outs.items()}}


def lox():
    cells = [(v["engine"], v["script"], v["n"]) for v in ce.vp3_cells("lox").values()]
    def one(cell):
        engine, name, n = cell
        script = ce.lox_script(name, n)
        r = both("lox", lambda tag: [f"--engine={engine}", script], ce.CACHE, 3600)
        return f"lox-{engine}-{name}-{n}", r
    with concurrent.futures.ThreadPoolExecutor(4) as pool:
        return dict(pool.map(one, cells))


def eda():
    cases = json.loads((ce.EDA / "golden/manifest.json").read_text())["cases"]
    out_root = ce.CACHE / "identity-eda"
    def one(case):
        dirs = {t: out_root / t / case["id"] for t in ("base", "final")}
        def args(tag):
            d = dirs[tag]
            if d.exists():
                shutil.rmtree(d)
            d.mkdir(parents=True)
            return ["--model", f"golden/cases/{case['id']}/model.sexp", "--project-dir", f"golden/projects/{case['project']}", "--out-dir", d, *case["flags"]]
        r = both("eda", args, ce.EDA, 900)
        expected = {name: meta["sha256"] for name, meta in case["outputs"].items()}
        golden = {t: {str(p.relative_to(d)): ce.digest(p) for p in d.rglob("*") if p.is_file()} == expected for t, d in dirs.items()}
        r["golden"] = golden
        r["same"] = r["same"] and all(golden.values())
        return f"eda-{case['id']}", r
    with concurrent.futures.ThreadPoolExecutor(4) as pool:
        return dict(pool.map(one, cases))


def parity():
    res = {}
    for name, path in ce.PARITY.items():
        expected = (ce.ROOT / f"bench/parity/{path}.expected").read_bytes()
        r = both(f"parity-{name}", lambda tag: [], ce.CACHE, 3600)
        r["expected"] = ce.digest_bytes(expected)
        r["same"] = r["same"] and all(v == r["expected"] for v in r["stdout_sha256"].values())
        res[f"parity-{name}"] = r
    return res


def rows():
    cells = ce.vp3_cells("rows")
    def one(name):
        cell = cells[f"row-{name}"]
        args = [str(cell["size"]), str(cell["iterations"]), "7"]
        return f"row-{name}", both(f"row-{name}", lambda tag: args, ce.CACHE, 900, normalize=lambda text: text.split()[:1])
    with concurrent.futures.ThreadPoolExecutor(4) as pool:
        return dict(pool.map(one, list(ce.row_registry().UNITS)))


def main():
    out = {}
    for group, f in (("parity", parity), ("rows", rows), ("eda", eda), ("lox", lox)):
        out[group] = f()
        bad = [k for k, v in out[group].items() if not v["same"]]
        print(f"{group}: {len(out[group])} cells, {len(out[group]) - len(bad)} identical, differing: {bad}", flush=True)
    pathlib.Path(sys.argv[1]).write_text(json.dumps(out, indent=1) + "\n")


if __name__ == "__main__":
    main()
