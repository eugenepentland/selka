#!/usr/bin/env python3
"""VP3 analysis: per-program totals, bytes copied per unit of work, top functions and
sites by bytes copied, copy patterns and their shares, and the static-ownership estimate.

Reads results/*.json and raw/*.json.gz; writes analysis/*.json and analysis/*.md.
"""
import collections, gzip, json, math, pathlib, re

AREA = pathlib.Path(__file__).resolve().parents[1]
ROOT = AREA.parents[1]
SOURCES = {"lox": ROOT / ".mylang-cache/vp3/src/lox", "eda": ROOT / ".mylang-cache/vp3/src/eda/src"}

# Copy classes: every byte moved by a copy, by where it comes from.
COPY_KINDS = ("list_copy", "dict_copy", "buffer_copy", "text_copy", "record_copy")
GROWTH = ("list_grow_bytes", "realloc_moved_bytes", "dict_grow_bytes", "buffer_grow_bytes", "text_grow_bytes")

# Instruction estimates per operation, from the emitted sequences (emit_llvm.countBlock,
# isUnique) and the runtime (myl_core_free_block's child walk): x86 instructions retired.
COST = {"retain": 5, "release": 7, "unique_test": 3, "runtime_count": 6, "copy_fixed": 60, "bytes_per_instr": 16}


def load(group):
    path = AREA / "results" / f"{group}.json"
    return json.loads(path.read_text()) if path.exists() else {}


def counts(label):
    return json.load(gzip.open(AREA / "raw" / f"{label}.json.gz"))


def pattern(site):
    """The copy pattern behind one site."""
    kind, detail = site["kind"], site["detail"]
    if kind == "record_copy":
        return {
            "jump": "P1 record moved into a phi slot at a join", "branch": "P1 record moved into a phi slot at a join",
            "record_set": "P2 whole-record copy before a field store", "list_get": "P3 element copied out of a list",
            "list_set": "P4 record written back into a list element", "list_set.old": "P5 old element copied out to release it",
            "list_push": "P6 record pushed into a list", "ret": "P7 record returned through sret",
        }.get(detail, f"P8 other record copy ({detail})")
    if kind == "list_copy":
        return "P9 copy-on-write of a whole list"
    if kind == "dict_copy":
        return "P10 dictionary copy"
    if kind == "text_copy":
        return "P11 text copy / view materialized"
    if kind == "buffer_copy":
        return "P12 byte-buffer copy"
    if kind == "list_push":
        return "P13 list growth (class move or realloc)"
    raise ValueError(kind)


def site_bytes(site):
    return site["extra"] if site["kind"] == "list_push" else site["bytes"]


def summarize(label, data, work, unit, instructions):
    t, k = data["totals"], data["kinds"]
    copied = {kind: k[kind]["bytes"] for kind in COPY_KINDS}
    copies = {kind: k[kind]["count"] for kind in COPY_KINDS}
    growth = {name: t[name] for name in GROWTH}
    total_copied = sum(copied.values())
    total_growth = sum(growth.values())
    rc = {"retains": k["retain"]["count"], "retained_bytes": k["retain"]["bytes"], "releases": k["release"]["count"], "release_unique": k["release_unique"]["count"],
          "unique_tests": k["unique_test"]["count"], "unique_found": k["unique_test"]["extra"], "runtime_retains": t["runtime_retains"], "runtime_releases": t["runtime_releases"]}
    # Static ownership (plan §3.8): counts, tests and the count word go; every retain (a second
    # owner of a value that stays live) becomes a copy of the shared block's data.
    removed = COST["retain"] * rc["retains"] + COST["release"] * rc["releases"] + COST["unique_test"] * rc["unique_tests"] + COST["runtime_count"] * (rc["runtime_retains"] + rc["runtime_releases"])
    added = COST["copy_fixed"] * rc["retains"] + rc["retained_bytes"] / COST["bytes_per_instr"]
    return {
        "label": label, "work": work, "unit": unit, "instructions": instructions,
        "calls": t["calls"], "allocs": t["allocs"], "alloc_bytes": t["alloc_bytes"], "frees": t["frees"], "free_bytes": t["free_bytes"], "peak_live_bytes": t["peak_live_bytes"],
        "copies": copies, "copied_bytes": copied, "copied_total": total_copied, "growth_bytes": growth, "growth_total": total_growth,
        "pushes": k["list_push"]["count"], "push_bytes": k["list_push"]["bytes"], "element_load_bytes": k["element_load"]["bytes"], "element_store_bytes": k["element_store"]["bytes"],
        "buffer_appends": t.get("buffer_appends", 0), "buffer_append_bytes": t.get("buffer_append_bytes", 0), "text_appends": t["text_appends"],
        "rc": rc, "copied_per_unit": (total_copied + total_growth) / work if work else None,
        "static_ownership": {"removed_instr": removed, "added_instr": added, "net_saving_pct": 100.0 * (removed - added) / instructions if instructions else None,
                             "removal_only_pct": 100.0 * removed / instructions if instructions else None},
    }


def source_line(path, line):
    for base in SOURCES.values():
        candidate = base / path
        if candidate.exists():
            lines = candidate.read_text().splitlines()
            return lines[line - 1].strip() if 0 < line <= len(lines) else ""
    candidate = pathlib.Path(path)
    if candidate.is_absolute() and candidate.exists():
        lines = candidate.read_text().splitlines()
        return lines[line - 1].strip() if 0 < line <= len(lines) else ""
    return ""


def short(path):
    return re.sub(r".*/bench/parity/", "bench/parity/", path)


def main():
    out = AREA / "analysis"
    out.mkdir(exist_ok=True)
    rows = {}
    function_bytes = collections.defaultdict(lambda: collections.Counter())   # (group, function) -> pattern -> bytes
    site_table = collections.defaultdict(lambda: {"count": 0, "bytes": 0})       # (group, function, path, line, column, kind, detail, pattern)
    pattern_share = collections.defaultdict(lambda: collections.Counter())      # program -> pattern -> bytes
    for group in ("lox", "eda", "parity", "rows"):
        for label, result in load(group).items():
            data = counts(label)
            if group == "lox":
                work, unit = result["n"], f"N ({result['script']})"
            elif group == "eda":
                work, unit = 1, "design run"
            elif group == "parity":
                work, unit = result["units"], result["unit"]
            else:
                work, unit = result["work"], result["unit"]
            summary = summarize(label, data, work, unit, result.get("instructions"))
            summary.update(group=group, same_output=result["same_output"], status=result["status"])
            if group == "lox":
                summary.update(engine=result["engine"], script=result["script"], primary=result["n"] == max(r["n"] for r in load("lox").values() if r["engine"] == result["engine"] and r["script"] == result["script"]))
                if not summary["primary"]:
                    rows[label] = summary
                    continue
            rows[label] = summary
            for site in data["sites"]:
                if site["kind"] not in COPY_KINDS and site["kind"] != "list_push":
                    continue
                moved = site_bytes(site)
                if not moved:
                    continue
                name = pattern(site)
                function_bytes[(group, site["function"])][name] += moved
                key = (group, site["function"], short(site["path"]), site["line"], site["column"], site["kind"], site["detail"], name)
                site_table[key]["count"] += site["count"] if site["kind"] != "list_push" else 0
                site_table[key]["bytes"] += moved
                pattern_share[label][name] += moved
            # Growth the runtime did outside any emitted push (dict, buffer, text growth).
            for row in data["functions"]:
                other = row["dict_grow_bytes"] + row["buffer_grow_bytes"] + row["text_grow_bytes"]
                if other:
                    pattern_share[label]["P14 dictionary, buffer or text growth"] += other
                    function_bytes[(group, row["name"])]["P14 dictionary, buffer or text growth"] += other
    (out / "programs.json").write_text(json.dumps(rows, indent=1) + "\n")
    # Pattern shares: per program the fraction of its bytes; averaged over the programs of each
    # corpus (so a long run does not dominate), and over all programs.
    shares = {}
    for label, by_pattern in pattern_share.items():
        total = sum(by_pattern.values())
        shares[label] = {name: value / total for name, value in by_pattern.items()} if total else {}
    corpora = collections.defaultdict(list)
    for label in rows:
        if rows[label].get("primary", True):
            corpora[rows[label]["group"]].append(label)
    pattern_names = sorted({name for s in shares.values() for name in s})
    corpus_share, corpus_bytes = {}, {}
    for group, labels in corpora.items():
        summed = collections.Counter()
        for label in labels:
            summed.update(pattern_share[label])
        total = sum(summed.values()) or 1
        corpus_bytes[group] = dict(summed)
        corpus_share[group] = {name: summed[name] / total for name in pattern_names}
    corpus_share["all (mean of corpora)"] = {name: sum(corpus_share[g][name] for g in corpora) / len(corpora) for name in pattern_names}
    total_bytes = collections.Counter()
    for by_pattern in pattern_share.values():
        total_bytes.update(by_pattern)
    (out / "patterns.json").write_text(json.dumps({"corpus_share": corpus_share, "corpus_bytes": corpus_bytes, "program_share": shares}, indent=1) + "\n")
    # Top functions by bytes copied: per corpus (bytes summed over its runs) and over all four
    # corpora, ranked by the function's share of its corpus's bytes (each corpus weighs the same).
    corpus_total = {group: sum(corpus_bytes[group].values()) or 1 for group in corpus_bytes}
    tops = {}
    for scope in ("lox", "eda", "parity", "rows", "all"):
        ranking = collections.Counter()
        for (group, function), by_pattern in function_bytes.items():
            if scope == group:
                ranking[(group, function)] = sum(by_pattern.values())
            elif scope == "all":
                ranking[(group, function)] = sum(by_pattern.values()) / corpus_total[group] / len(corpus_total)
        entries = []
        for (group, function), weight in ranking.most_common(20):
            moved = sum(function_bytes[(group, function)].values())
            sites = sorted(((key, value) for key, value in site_table.items() if key[0] == group and key[1] == function), key=lambda kv: -kv[1]["bytes"])[:8]
            entries.append({"group": group, "function": function, "bytes": moved, "corpus_share": moved / corpus_total[group],
                            "patterns": dict(function_bytes[(group, function)].most_common()),
                            "sites": [{"path": key[2], "line": key[3], "column": key[4], "kind": key[5], "detail": key[6], "pattern": key[7], "count": value["count"], "bytes": value["bytes"],
                                       "source": source_line(key[2], key[3])} for key, value in sites]})
        tops[scope] = entries
    (out / "top-functions.json").write_text(json.dumps(tops, indent=1) + "\n")
    # Static ownership: geomean of instruction ratios over the 46 rows; rows above 10%.
    verdict = {}
    for group, labels in corpora.items():
        ratios, removal = [], []
        for label in labels:
            so = rows[label]["static_ownership"]
            if so["net_saving_pct"] is None:
                continue
            ratios.append(1.0 - so["net_saving_pct"] / 100.0)
            removal.append(1.0 - so["removal_only_pct"] / 100.0)
        if not ratios:
            continue
        geomean = math.exp(sum(math.log(max(r, 1e-9)) for r in ratios) / len(ratios))
        geomean_removal = math.exp(sum(math.log(max(r, 1e-9)) for r in removal) / len(removal))
        verdict[group] = {"programs": len(ratios), "geomean_ratio": geomean, "geomean_saving_pct": 100 * (1 - geomean),
                          "geomean_removal_only_pct": 100 * (1 - geomean_removal),
                          "programs_net_saving_ge_10pct": [l for l in labels if (rows[l]["static_ownership"]["net_saving_pct"] or 0) >= 10],
                          "programs_removal_only_ge_10pct": [l for l in labels if (rows[l]["static_ownership"]["removal_only_pct"] or 0) >= 10]}
    (out / "static-ownership.json").write_text(json.dumps({"cost_model": COST, "by_corpus": verdict}, indent=1) + "\n")
    print(json.dumps({g: {k: v for k, v in d.items() if not isinstance(v, list)} for g, d in verdict.items()}, indent=1))
    tables(out, rows, corpora, corpus_share, corpus_bytes, tops, verdict)


def human(value):
    for unit, size in (("T", 1e12), ("G", 1e9), ("M", 1e6), ("k", 1e3)):
        if abs(value) >= size:
            return f"{value / size:.2f} {unit}"
    return f"{value:.0f}"


SLOWEST = ["rds3+flat", "rds3", "cyclops-digital-pcb", "labstation", "straps-base", "cyclops-kband-pcb"]


def program_row(name, r, extra=""):
    rc = r["rc"]
    shared = rc["unique_tests"] - rc["unique_found"]
    bytes_all = r["copied_total"] + r["growth_total"]
    per_instr = bytes_all / r["instructions"] if r["instructions"] else 0
    return (f"| {name}{extra} | {human(r['instructions'])} | {human(rc['retains'])} | {human(rc['releases'] + rc['release_unique'])} | {human(rc['runtime_retains'] + rc['runtime_releases'])} | "
            f"{human(rc['unique_tests'])} ({human(shared)}) | {human(sum(r['copies'].values()))} | {human(r['copied_bytes']['record_copy'])} | "
            f"{human(r['copied_bytes']['list_copy'] + r['copied_bytes']['dict_copy'] + r['copied_bytes']['buffer_copy'] + r['copied_bytes']['text_copy'])} | {human(r['growth_total'])} | "
            f"{human(r['allocs'])} | {human(r['peak_live_bytes'])} | {human(bytes_all / r['work']) if r['work'] else ''} | {per_instr:.2f} |")


HEADER = ("| program | instructions | retains | releases | runtime count ops | unique tests (shared) | copies | record bytes | list/dict/buffer/text bytes | growth bytes | allocs | peak live | bytes copied per unit | bytes per instruction |\n"
          "|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|")


def totals_row(name, members):
    agg = {"instructions": 0, "rc": collections.Counter(), "copies": collections.Counter(), "copied_bytes": collections.Counter(), "growth_total": 0, "copied_total": 0, "allocs": 0, "peak_live_bytes": 0, "work": 0}
    for r in members:
        agg["instructions"] += r["instructions"] or 0
        agg["rc"].update(r["rc"])
        agg["copies"].update(r["copies"])
        agg["copied_bytes"].update(r["copied_bytes"])
        agg["growth_total"] += r["growth_total"]
        agg["copied_total"] += r["copied_total"]
        agg["allocs"] += r["allocs"]
        agg["peak_live_bytes"] = max(agg["peak_live_bytes"], r["peak_live_bytes"])
    return program_row(name, agg)


def tables(out, rows, corpora, corpus_share, corpus_bytes, tops, verdict):
    lines = ["# VP3 generated tables", "", "Every byte figure is bytes moved by copies the core emitted or the runtime made; `growth` is list, dictionary, buffer and text growth that moved contents.", ""]
    lines += ["## Lox (both engines; the larger N of each cell; per unit = per N)", "", HEADER]
    for label in sorted(corpora["lox"], key=lambda l: (rows[l]["engine"], rows[l]["script"])):
        r = rows[label]
        half = [x for x in rows.values() if x["group"] == "lox" and x.get("engine") == r["engine"] and x.get("script") == r["script"] and not x.get("primary", True)]
        ratio = ""
        if half and (half[0]["copied_total"] + half[0]["growth_total"]):
            ratio = f" ×{(r['copied_total'] + r['growth_total']) / (half[0]['copied_total'] + half[0]['growth_total']):.2f} vs N={half[0]['work']}"
        lines.append(program_row(f"{r['engine']} {r['script']} N={r['work']}", r, f" ({ratio.strip()})" if ratio else ""))
    lines.append(totals_row("**Lox total**", [rows[l] for l in corpora["lox"]]))
    lines += ["", "## EDA (34 designs; per unit = per design run)", "", HEADER]
    eda = sorted(corpora["eda"], key=lambda l: -(rows[l]["instructions"] or 0))
    for label in eda:
        lines.append(program_row(label[4:], rows[label], " **(slowest six)**" if label[4:] in SLOWEST else ""))
    lines.append(totals_row("**six slowest**", [rows["eda-" + n] for n in SLOWEST]))
    lines.append(totals_row("**other 28**", [rows[l] for l in eda if l[4:] not in SLOWEST]))
    lines.append(totals_row("**EDA total**", [rows[l] for l in eda]))
    lines += ["", "## Parity programs (per unit as named)", "", HEADER]
    for label in corpora["parity"]:
        lines.append(program_row(f"{label[7:]} (per {rows[label]['unit']})", rows[label]))
    lines += ["", "## The 46 rows (per unit = per element or iteration of the row's timed size)", "", HEADER]
    for label in corpora["rows"]:
        lines.append(program_row(label[4:], rows[label]))
    lines.append(totals_row("**46 rows total**", [rows[l] for l in corpora["rows"]]))
    lines += ["", "## Copy patterns: share of bytes moved, per corpus", "", "| pattern | " + " | ".join(corpus_share) + " |", "|---|" + "---:|" * len(corpus_share)]
    names = sorted({n for d in corpus_share.values() for n in d}, key=lambda n: -corpus_share["all (mean of corpora)"].get(n, 0))
    for name in names:
        if corpus_share["all (mean of corpora)"].get(name, 0) < 0.0005:
            continue
        lines.append(f"| {name} | " + " | ".join(f"{100 * corpus_share[g].get(name, 0):.1f}%" for g in corpus_share) + " |")
    lines.append("| bytes moved (all patterns) | " + " | ".join(human(sum(corpus_bytes[g].values())) if g in corpus_bytes else "" for g in corpus_share) + " |")
    lines += ["", "## Top 20 functions by bytes copied (all corpora; ranked by share of their corpus's bytes)", ""]
    for i, e in enumerate(tops["all"], 1):
        pats = "; ".join(f"{n.split(' ', 1)[0]} {100 * v / e['bytes']:.0f}%" for n, v in list(e["patterns"].items())[:4])
        lines.append(f"{i}. **{e['group']} `{e['function']}`**: {human(e['bytes'])}B, {100 * e['corpus_share']:.1f}% of {e['group']} ({pats})")
        for st in e["sites"][:4]:
            lines.append(f"   - `{st['path']}:{st['line']}:{st['column']}` {st['kind']}/{st['detail']} → {st['pattern']}: {human(st['bytes'])}B" + (f" in {human(st['count'])} copies" if st["count"] else "") + (f" — `{st['source'][:100]}`" if st["source"] else ""))
    lines += ["", "## Static ownership estimate", "", "| corpus | programs | geomean net saving (every retain becomes a copy) | geomean saving if copies were free (upper bound) | programs ≥ 10% net | programs ≥ 10% upper bound |", "|---|---:|---:|---:|---|---|"]
    for group, v in verdict.items():
        lines.append(f"| {group} | {v['programs']} | {v['geomean_saving_pct']:.2f}% | {v['geomean_removal_only_pct']:.2f}% | {len(v['programs_net_saving_ge_10pct'])}: {', '.join(v['programs_net_saving_ge_10pct'][:8])} | {len(v['programs_removal_only_ge_10pct'])}: {', '.join(v['programs_removal_only_ge_10pct'][:8])} |")
    (out / "tables.md").write_text("\n".join(lines) + "\n")


if __name__ == "__main__":
    main()
