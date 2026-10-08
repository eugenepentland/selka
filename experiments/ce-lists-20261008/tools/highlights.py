#!/usr/bin/env python3
"""CE-B highlights from the gzipped counters: nbody per step, Lox instantiation scaling,
EDA overlaps_of and rds3+flat, str_build appends. usage: highlights.py STAGE [BASE=vp3]"""
import collections, gzip, json, pathlib, sys
ROOT = pathlib.Path(__file__).resolve().parents[3]
VP3 = ROOT / "experiments/vk-vp3-20261008"
sys.path.insert(0, str(VP3 / "tools"))
import analyze

def raw(stage, label):
    p = VP3 / "raw" / f"{label}.json.gz" if stage == "vp3" else ROOT / ".mylang-cache/ce/raw" / stage / f"{label}.json.gz"
    return json.load(gzip.open(p))

def moved(d, function=None):
    total = 0
    for s in d["sites"]:
        if s["kind"] not in analyze.COPY_KINDS and s["kind"] != "list_push":
            continue
        if function and s["function"] != function:
            continue
        total += analyze.site_bytes(s)
    for r in d["functions"]:
        if function and r["name"] != function:
            continue
        total += r["dict_grow_bytes"] + r["buffer_grow_bytes"] + r["text_grow_bytes"]
    return total

def p9(d):
    return sum(s["bytes"] for s in d["sites"] if s["kind"] == "list_copy")

stage = sys.argv[1]
base = sys.argv[2] if len(sys.argv) > 2 else "vp3"
out = {}
for who in (base, stage):
    n = raw(who, "parity-nbody")
    nb = sum(analyze.site_bytes(s) for s in n["sites"] if s["kind"] == "record_copy" and s["detail"] in ("list_get", "list_set"))
    out.setdefault("nbody P3+P4 bytes per step", {})[who] = nb / 5_000_000
    for engine, small, big in (("tree", 5000, 10000), ("vm", 200, 400)):
        a, b = raw(who, f"lox-{engine}-instantiation-{small}"), raw(who, f"lox-{engine}-instantiation-{big}")
        out.setdefault(f"lox {engine} instantiation bytes N/2 -> N (ratio)", {})[who] = (moved(a), moved(b), round(moved(b) / moved(a), 3))
        out.setdefault(f"lox {engine} instantiation P9 bytes N/2 -> N (ratio)", {})[who] = (p9(a), p9(b), round(p9(b) / p9(a), 3) if p9(a) else None)
    e = raw(who, "eda-rds3+flat")
    out.setdefault("eda rds3+flat bytes moved", {})[who] = moved(e)
    out.setdefault("eda rds3+flat overlaps_of bytes", {})[who] = moved(e, "kicad_sch_textbox::overlaps_of")
    total = 0
    for p in sorted((VP3 / "raw").glob("eda-*.json.gz")):
        total += moved(raw(who, p.name[:-8]), "kicad_sch_textbox::overlaps_of")
    out.setdefault("eda overlaps_of bytes, 34 designs", {})[who] = total
    sb = raw(who, "parity-str_build")
    out.setdefault("str_build out-of-line buffer appends", {})[who] = sb["totals"].get("buffer_appends")
for k, v in out.items():
    print(f"{k}: {v[base]} -> {v[stage]}")
json.dump(out, open(ROOT / f"experiments/ce-lists-20261008/analysis/{stage}-highlights.json", "w"), indent=1)
