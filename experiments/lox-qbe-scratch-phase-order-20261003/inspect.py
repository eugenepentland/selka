#!/usr/bin/env python3
"""Inspect frozen prior IL/dumps only; never emit code or execute a guest."""
import base64
import gzip
import hashlib
import json
import re
import subprocess
from pathlib import Path

BASE = "3b33df52044a10cb84b908f8b1641af439e8c729"
HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
PRIOR = HERE.parent / "lox-qbe-private-alias-ablation-20261003"
ARCHIVE_SHA = "970dad759be9cf2ef2b64a2b768e913346e41ab3ef2579235263971a831152d2"


def sha(data):
    return hashlib.sha256(data).hexdigest()


def archived():
    raw = (PRIOR / "originals.json.gz").read_bytes()
    assert sha(raw) == ARCHIVE_SHA
    manifest = json.loads((PRIOR / "archive-manifest.json").read_text())
    files = {name: base64.b64decode(value) for name, value in
             json.loads(gzip.decompress(raw))["files"].items()}
    assert files.keys() == manifest["files"].keys()
    for name, data in files.items():
        assert sha(data) == manifest["files"][name]["sha256"]
        assert len(data) == manifest["files"][name]["bytes"]
    return files


def stages(text):
    headings = list(re.finditer(r"^> ([^\n]+)\n", text, re.M))
    result = []
    for index, heading in enumerate(headings):
        end = headings[index + 1].start() if index + 1 < len(headings) else len(text)
        result.append((heading.group(1), text[heading.end():end]))
    assert len(result) == 6
    return result


def cell_counts(text, cell):
    lines = [line.strip() for line in text.splitlines()
             if re.search(r"%" + cell + r"\b", line) and not line.strip().startswith("kill [")]
    return {
        "references": len(lines),
        "allocations": sum("alloc8" in line for line in lines),
        "storel": sum(line.startswith("storel ") for line in lines),
        "direct_loadl": sum(bool(re.search(r"=l load %" + cell + r"$", line)) for line in lines),
    }


def definition(text, name):
    return next((line.strip() for line in text.splitlines()
                 if re.match(r"\s*%" + re.escape(name) + r" =", line)), None)


def original_blocks(text):
    blocks = {}
    current = None
    for line in text.splitlines():
        if line.startswith("@"):
            current = line.strip()
            blocks[current] = []
        elif current is not None:
            blocks[current].append(line.strip())
    return blocks


def last_store(lines):
    return next((line for line in reversed(lines)
                 if re.fullmatch(r"storel .+, %s0", line)), None)


def sites(text):
    blocks = original_blocks(text)
    rows = []
    for alias, value in (("v624", "v627"), ("v779", "v782"),
                         ("v2791", "v2794"), ("v3393", "v3396")):
        label, lines = next((label, lines) for label, lines in blocks.items()
                            if "%" + alias + " =l copy %s0" in lines)
        at = lines.index("%" + alias + " =l copy %s0")
        incoming = []
        for predecessor, source in blocks.items():
            if any(re.search(r"(?:jmp|jnz) .*" + re.escape(label) + r"(?:,|$)", line)
                   for line in source):
                incoming.append({"block": predecessor, "last_s0_store": last_store(source)})
        rows.append({"alias": alias, "load": value, "block": label,
                     "load_instruction": definition("\n".join(lines), value),
                     "same_block_prior_store": last_store(lines[:at]),
                     "incoming_blocks": incoming})
    assert [row["same_block_prior_store"] for row in rows] == [
        "storel 1, %s0", "storel 0, %s0", None, None]
    assert [len(row["incoming_blocks"]) for row in rows[2:]] == [16, 4]
    return rows


def excerpt(text, first, last):
    lines = text.splitlines()
    start = next(index for index, line in enumerate(lines) if first in line)
    end = next(index for index in range(start, len(lines)) if last in lines[index])
    return {"first_line": start + 1, "last_line": end + 1,
            "text": "\n".join(lines[start:end + 1])}


def inspect():
    files = archived()
    source_paths = ["vendor/qbe/main.c", "vendor/qbe/mem.c", "vendor/qbe/alias.c",
                    "vendor/qbe/load.c", "vendor/qbe/fold.c"]
    sources = {}
    for name in source_paths:
        data = (ROOT / name).read_bytes()
        original = subprocess.run(["git", "show", BASE + ":" + name], cwd=ROOT,
                                  check=True, capture_output=True).stdout
        assert data == original
        if "source/" + name in files:
            assert data == files["source/" + name]
        sources[name] = {"sha256": sha(data), "bytes": len(data), "selected_base_equal": True}
    stage_rows = {}
    for arm in ("control", "s1-one"):
        rows = []
        for name, text in stages(files["scratch/" + arm + ".debug.stderr"].decode()):
            rows.append({"stage": name,
                         "s0": cell_counts(text, "s0"),
                         "s1": cell_counts(text, "s1"),
                         "byte_definitions": {value: definition(text, value)
                                              for value in ("v627", "v782", "v2794", "v3396")},
                         "killed": re.findall(r"^\s*kill \[.*$", text, re.M)})
        assert rows[0]["s0"]["storel"] == 868
        assert rows[0]["s0"]["direct_loadl"] == 676
        assert rows[1]["s0"]["direct_loadl"] == 0
        assert rows[1]["s0"]["storel"] == 868
        assert rows[3]["s0"]["references"] == 0
        assert rows[4]["s0"]["references"] == 0
        assert rows[5]["s0"]["references"] == 0
        stage_rows[arm] = rows
    control = stages(files["scratch/control.debug.stderr"].decode())
    main = (ROOT / "vendor/qbe/main.c").read_text()
    order = re.findall(r"^\s*(promote|ssa|fillalias|loadopt|coalesce|gvn|gcm)\(fn\);", main, re.M)
    assert order == ["promote", "ssa", "fillalias", "loadopt", "fillalias", "loadopt",
                     "fillalias", "coalesce", "gvn", "gcm"]
    joins = []
    for phi in ("ld.1880", "ld.1972"):
        line = definition(control[1][1], phi)
        assert line is not None and " phi " in line
        joins.append(line)
    inputs = {name: {"sha256": sha(files[name]), "bytes": len(files[name])}
              for name in ("scratch/control.ssa", "scratch/control.debug.stderr",
                           "scratch/s1-one.debug.stderr", "scratch/control.s",
                           "scratch/s0-five.s", "scratch/loadub-four.s", "scratch/s1-one.s")}
    assert files["scratch/control.s"] == files["scratch/s0-five.s"]
    assert files["scratch/control.s"] == files["scratch/loadub-four.s"]
    return {
        "scope": "read-only existing IL, pass dumps and selected source; no new emission/guest/perf",
        "conclusion": "no demonstrated bounded same-width forwarding candidate",
        "selected_base": BASE, "prior_archive_sha256": ARCHIVE_SHA,
        "pinned_qbe_sha256": "99ad919d70ad582dee6202b045bd53e1ab18fec356de98849610f49983756d63",
        "inputs": inputs, "sources": sources, "pass_order": order,
        "byte_sites": sites(files["scratch/control.ssa"].decode()),
        "join_phis_from_actual_first_loadopt": joins,
        "stages": stage_rows,
        "source_excerpts": {
            "uniform_width_admission": excerpt((ROOT / "vendor/qbe/mem.c").read_text(),
                                                "s = -1;", "/* get rid of the alloc and replace uses */"),
            "stores_mark_values_escaped": excerpt((ROOT / "vendor/qbe/alias.c").read_text(),
                                                  "if (req(i->to, R) || a->type == AUnk)",
                                                  "if (i->op == Oblit0) {"),
            "dead_store_removal": excerpt((ROOT / "vendor/qbe/mem.c").read_text(),
                                           "/* kill dead stores */", "/* kill slots with an empty live range */"),
        },
        "limits": ["No reaching-definition or all-path initialization certificate is proposed.",
                   "No load width, masking, byte conversion or native ABI is changed.",
                   "Alias reanalysis/recoalescing is a future investigation, not a soundness or ROI claim.",
                   "Pass source matches selected base; prior actual executable dumps establish observed behavior.",
                   "No dynamic frequency or hardware cause is inferred from static counts."]}


if __name__ == "__main__":
    print(json.dumps(inspect(), indent=2, sort_keys=True))
