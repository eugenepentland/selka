#!/usr/bin/env python3
"""Check bound layout evidence and actual caller disassembly without execution."""
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
TREE = ROOT.parent / "goal110-dict-word-integrated-20261004"
REPORT = TREE / ".mylang-cache/goal110-dict-word/static/layout/report.json"


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def walk(value):
    count = 0
    if isinstance(value, dict):
        if "path" in value and "sha256" in value:
            assert sha(value["path"]) == value["sha256"]
            count += 1
        for item in value.values():
            count += walk(item)
    elif isinstance(value, list):
        for item in value:
            count += walk(item)
    return count


def normalized(assembly, symbol, symbols):
    lines, inside = [], False
    for line in assembly.splitlines():
        head = re.match(r"^[0-9a-f]+ <([^>]+)>:$", line)
        if head:
            inside = head[1] == symbol
            continue
        if not inside:
            continue
        instruction = re.match(r"^\s*[0-9a-f]+:\s+(.*)$", line)
        if not instruction:
            continue
        text = re.sub(r"\b[0-9a-f]+ <([^>]+)>", r"<\1>", instruction[1])
        # objdump's retained target comment names RIP-relative referents.
        text = re.sub(r"-?0x[0-9a-f]+\(%rip\)", "(%rip)", text)
        def relocate(match):
            address = int(match[1], 16)
            for name, (start, size) in symbols.items():
                if start <= address < start + size:
                    suffix = "+" + hex(address - start) if address != start else ""
                    return "$<" + name + suffix + ">"
            return match[0]
        lines.append(re.sub(r"\$0x([0-9a-f]+)", relocate, text))
    return lines


def main():
    doc = json.loads(REPORT.read_text())
    assert doc["status"] == "complete" and doc["read_only"] and not doc["timing"]
    bindings = walk(doc)
    rows = []
    for backend, data in doc["backends"].items():
        caller = data["batch"]["symbol"]
        actual = []
        positions = []
        for arm in ("before", "after"):
            bound = data["artifacts"][arm]
            binary = bound["binary"]["path"]
            asm = subprocess.check_output(["objdump", "-d", "--no-show-raw-insn", binary], text=True)
            assert asm == Path(bound["assembly"]["path"]).read_text()
            nm = subprocess.check_output(["nm", "-S", "--defined-only", "--numeric-sort", binary], text=True)
            symbols = {parts[3]: (int(parts[0], 16), int(parts[1], 16))
                       for line in nm.splitlines() if len(parts := line.split()) == 4}
            positions.append(symbols[caller])
            actual.append(normalized(asm, caller, symbols))
        assert positions[1][0] - positions[0][0] == 48
        assert positions[0][1] == positions[1][1] == data["batch"]["before_symbol"][1]
        assert sum("<myl_native_dictionary_read_word>" in line for line in actual[1]) == 2
        assert actual[0] == [line.replace("<myl_native_dictionary_read_word>", "<myl_native_dictionary_read>") for line in actual[1]]
        assert [len(lines) for lines in actual] == data["batch"]["instruction_count"]
        rows.append(dict(backend=backend, function_bytes=positions[0][1],
                         instructions=len(actual[0]), address_shift=48,
                         equal_after_exact_two_callee_substitutions=True))
    result = dict(status="pass", reviewed_utc=datetime.now(timezone.utc).isoformat(),
                  bindings=bindings, callers=rows, raw_sha256=sha(REPORT),
                  script_sha256=sha(__file__),
                  limitations=["Read-only static evidence; no guest execution or timing.",
                               "Address operands are normalized to symbolic referents; placement changes remain.",
                               "Placement is a plausible explanation for unchanged-path costs, not an isolated cache/branch causal experiment."])
    with Path(sys.argv[1]).open("x") as out:
        out.write(json.dumps(result, indent=2) + "\n")
    print("PASS layout bindings, exact actual disassemblies and both unchanged caller instruction streams")


if __name__ == "__main__":
    main()
