#!/usr/bin/env python3
"""CE-X Part 2 tables: bytes moved per pattern (VP3's rules, ce.py) for VP3, CE-A final, CE-B
final and the merged compiler (tag `final`), per corpus; the highlights; the top functions
still copying. Writes analysis/tables.json and prints Markdown."""
import collections, json, pathlib, sys
sys.path.insert(0, str(pathlib.Path(__file__).parent))
import ce

TAGS = ["vp3", "ce-a", "ce-b", "final"]
NAMES = {"vp3": "VP3 (base)", "ce-a": "CE-A final", "ce-b": "CE-B final", "final": "merged (CE-X)"}
NBODY_STEPS = 5_000_000


def site_bytes(site):
    return site["extra"] if site["kind"] == "list_push" else site["bytes"]


def corpus_totals(tag):
    corpora, _ = ce.totals(ce.raw_dir(tag))
    if tag == "ce-a":   # CE-A counted the rows separately, with a compiler of the same emission
        rows, _ = ce.totals(ce.raw_dir("ce-a-rows"))
        corpora["rows"] = rows["rows"]
    return {c: dict(v) for c, v in corpora.items()}


def moved(data, function=None):
    total = 0
    for s in data["sites"]:
        if ce.pattern(s) is None or (function and s["function"] != function):
            continue
        total += site_bytes(s)
    for r in data["functions"]:
        if function and r["name"] != function:
            continue
        total += r["dict_grow_bytes"] + r["buffer_grow_bytes"] + r["text_grow_bytes"]
    return total


def p9(data):
    return sum(s["bytes"] for s in data["sites"] if s["kind"] == "list_copy")


def load(tag, label):
    d = ce.raw_dir("ce-a-rows") if tag == "ce-a" and label.startswith("row-") else ce.raw_dir(tag)
    return ce.load_counts(d, label)


def highlights(tag):
    h = {}
    fib = load(tag, "lox-vm-fib-27")
    n = ce.dispatches(tag, "lox-vm-fib-27") if tag != "ce-a" or fib else None
    pats = ce.by_pattern(fib)
    h["lox_vm_fib27_dispatches"] = n
    h["lox_vm_fib27_bytes_per_dispatch"] = sum(pats.values()) / n
    h["lox_vm_fib27_record_bytes_per_dispatch"] = sum(pats.get(p, 0) for p in ("P1", "P2", "P7", "P8")) / n
    h["lox_vm_fib27_element_bytes_per_dispatch"] = sum(pats.get(p, 0) for p in ("P3", "P4", "P5")) / n
    nb = load(tag, "parity-nbody")
    h["nbody_bytes_per_step"] = moved(nb) / NBODY_STEPS
    h["nbody_P3P4_bytes_per_step"] = sum(site_bytes(s) for s in nb["sites"] if s["kind"] == "record_copy" and s["detail"] in ("list_get", "list_set")) / NBODY_STEPS
    flat = load(tag, "eda-rds3+flat")
    fp = ce.by_pattern(flat)
    h["eda_rds3_flat_bytes"] = sum(fp.values())
    h["eda_rds3_flat_by_pattern"] = dict(fp)
    h["eda_rds3_flat_overlaps_of_bytes"] = moved(flat, "kicad_sch_textbox::overlaps_of")
    for engine, small, big in (("tree", 5000, 10000), ("vm", 200, 400)):
        a, b = load(tag, f"lox-{engine}-instantiation-{small}"), load(tag, f"lox-{engine}-instantiation-{big}")
        h[f"lox_{engine}_instantiation"] = {"n": [small, big], "bytes": [moved(a), moved(b)], "ratio": moved(b) / moved(a) if moved(a) else None,
                                            "p9": [p9(a), p9(b)], "p9_ratio": p9(b) / p9(a) if p9(a) else None}
    sb = load(tag, "parity-str_build")
    h["str_build_out_of_line_buffer_appends"] = sb["totals"].get("buffer_appends")
    return h


def top_functions(tag, limit=10):
    table = collections.Counter()
    pats = collections.defaultdict(collections.Counter)
    sites = collections.defaultdict(collections.Counter)
    corpus_total = collections.Counter()
    for label in ce.primary_labels():
        data = load(tag, label)
        if data is None:
            continue
        corpus = {"row": "rows"}.get(ce.corpus_of(label), ce.corpus_of(label))
        for s in data["sites"]:
            name = ce.pattern(s)
            if name is None:
                continue
            b = site_bytes(s)
            if not b:
                continue
            key = (corpus, s["function"])
            table[key] += b
            pats[key][name] += b
            sites[key][(name, s["path"].split("/")[-1], s["line"], s["detail"])] += b
            corpus_total[corpus] += b
        for r in data["functions"]:
            g = r["dict_grow_bytes"] + r["buffer_grow_bytes"] + r["text_grow_bytes"]
            if g:
                key = (corpus, r["name"])
                table[key] += g
                pats[key]["P14"] += g
                corpus_total[corpus] += g
    out = []
    for (corpus, function), b in table.most_common(limit):
        key = (corpus, function)
        out.append({"corpus": corpus, "function": function, "bytes": b, "share_of_corpus": b / corpus_total[corpus],
                    "patterns": dict(pats[key].most_common()),
                    "top_sites": [{"pattern": k[0], "file": k[1], "line": k[2], "detail": k[3], "bytes": v} for k, v in sites[key].most_common(4)]})
    return out, dict(corpus_total)


def main():
    patterns = {tag: corpus_totals(tag) for tag in TAGS}
    hl = {tag: highlights(tag) for tag in TAGS}
    top, totals = top_functions("final")
    top_per_corpus = {}
    for corpus in ("lox", "eda", "parity", "rows"):
        full, _ = top_functions("final", limit=400)
        top_per_corpus[corpus] = [r for r in full if r["corpus"] == corpus][:5]
    area = ce.AREA / "analysis"
    area.mkdir(exist_ok=True)
    (area / "tables.json").write_text(json.dumps({"patterns": patterns, "highlights": hl, "top_functions": top,
                                                   "top_per_corpus": top_per_corpus, "final_corpus_totals": totals}, indent=1) + "\n")
    lines = []
    for corpus in ("lox", "eda", "parity", "rows"):
        lines += [f"\n### {corpus}\n", "| pattern | " + " | ".join(NAMES[t] for t in TAGS) + " | merged vs VP3 |", "|---|" + "---:|" * (len(TAGS) + 1)]
        for name in ce.PATTERNS + ["P1+P2+P7+P8", "P3+P4+P5", "all"]:
            values = []
            for t in TAGS:
                d = patterns[t].get(corpus, {})
                if name == "P1+P2+P7+P8":
                    v = sum(d.get(p, 0) for p in ("P1", "P2", "P7", "P8"))
                elif name == "P3+P4+P5":
                    v = sum(d.get(p, 0) for p in ("P3", "P4", "P5"))
                elif name == "all":
                    v = sum(d.values())
                else:
                    v = d.get(name, 0)
                values.append(v)
            if not any(values):
                continue
            change = f"{100 * (values[-1] - values[0]) / values[0]:+.1f}%" if values[0] else "new"
            label = f"**{name}**" if name in ("P1+P2+P7+P8", "P3+P4+P5", "all") else name
            lines.append(f"| {label} | " + " | ".join(ce.human(v) for v in values) + f" | {change} |")
    lines.append("\n### highlights\n")
    for key in hl["final"]:
        if key == "eda_rds3_flat_by_pattern":
            continue
        lines.append(f"- {key}: " + " | ".join(f"{t}: {json.dumps(hl[t][key]) if isinstance(hl[t][key], dict) else (round(hl[t][key], 2) if isinstance(hl[t][key], float) else hl[t][key])}" for t in TAGS))
    lines.append("\n### top 10 functions still copying (merged compiler, all corpora)\n")
    lines.append("| # | corpus | function | bytes | share of corpus | patterns | top site |")
    lines.append("|---:|---|---|---:|---:|---|---|")
    for i, r in enumerate(top, 1):
        s = r["top_sites"][0] if r["top_sites"] else None
        site = f"{s['pattern']} {s['file']}:{s['line']} {s['detail']} ({ce.human(s['bytes'])})" if s else ""
        pats = ", ".join(f"{p} {ce.human(b)}" for p, b in list(r["patterns"].items())[:3])
        lines.append(f"| {i} | {r['corpus']} | `{r['function']}` | {ce.human(r['bytes'])} | {100 * r['share_of_corpus']:.1f}% | {pats} | {site} |")
    print("\n".join(lines))


if __name__ == "__main__":
    main()
