#!/usr/bin/env python3
"""CE-A report tables: bytes moved per pattern for base, each step and the final compiler,
per corpus, and the highlights. Writes analysis/tables.json and prints Markdown."""
import json, pathlib, sys
sys.path.insert(0, str(pathlib.Path(__file__).parent))
import ce

TAGS = ["base", "step1", "step2", "step3", "final"]
ROWS_TAG = {"base": "base", "final": "rows-final"}   # the rows were counted with a compiler of the same emission as final


def main():
    out = {}
    for tag in TAGS:
        corpora, _ = ce.totals(ce.raw_dir(tag))
        out[tag] = {c: dict(v) for c, v in corpora.items()}
    for tag, source in ROWS_TAG.items():
        corpora, _ = ce.totals(ce.raw_dir(source))
        if "rows" in corpora:
            out[tag]["rows"] = dict(corpora["rows"])
    highlights = ce.tables(TAGS)["highlights"]
    rows = ce.tables(["rows-final"])["highlights"]["rows-final"]["rows_record_pass_bytes"]
    highlights["final"]["rows_record_pass_bytes"] = rows
    area = ce.AREA / "analysis"
    area.mkdir(exist_ok=True)
    (area / "tables.json").write_text(json.dumps({"patterns": out, "highlights": highlights}, indent=1) + "\n")
    lines = []
    for corpus in ("lox", "eda", "parity", "rows"):
        lines += [f"\n### {corpus}\n", "| pattern | " + " | ".join(t for t in TAGS if corpus in out[t]) + " | final vs base |", "|---|" + "---:|" * (sum(corpus in out[t] for t in TAGS) + 1)]
        tags = [t for t in TAGS if corpus in out[t]]
        for name in ce.PATTERNS + ["P1+P2+P7+P8", "all"]:
            values = []
            for t in tags:
                d = out[t][corpus]
                v = sum(d.get(p, 0) for p in ("P1", "P2", "P7", "P8")) if name == "P1+P2+P7+P8" else sum(d.values()) if name == "all" else d.get(name, 0)
                values.append(v)
            if not any(values):
                continue
            change = f"{100 * (values[-1] - values[0]) / values[0]:+.1f}%" if values[0] else ""
            label = f"**{name}**" if name in ("P1+P2+P7+P8", "all") else name
            lines.append(f"| {label} | " + " | ".join(ce.human(v) for v in values) + f" | {change} |")
    print("\n".join(lines))
    print("\n```json\n" + json.dumps(highlights, indent=1) + "\n```")


if __name__ == "__main__":
    main()
