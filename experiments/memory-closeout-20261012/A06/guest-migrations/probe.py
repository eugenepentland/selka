#!/usr/bin/env python3
"""Check a bounded batch of reserved guest sources and preserve every refusal."""
import argparse
import hashlib
import json
import re
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[4]
HERE = Path(__file__).resolve().parent


def certain_copy(source, stderr):
    diagnostic = re.search(r"([^ /]+\.my):(\d+):(\d+): error\[(\w+)\]: ([^\n]+)", stderr)
    if not diagnostic or diagnostic[1] != source.name:
        return None
    lines = source.read_text().splitlines()
    number, column = int(diagnostic[2]) - 1, int(diagnostic[3]) - 1
    line = lines[number]
    if diagnostic[4] == "E_SINGLE_OWNER_BORROW":
        if line.lstrip().startswith(("for ", "assert ", "func ", "public ")):
            return None
        if re.match(r"\s*(?:mut|const) [^=]+$", line[:column]):
            return None
        # The borrow must occur in a value position, never an assignment target.
        if not re.search(r"(?:return\s+|=\s*|\(\s*|,\s*)$", line[:column]):
            return None
        tail = line[column:]
        token = re.match(r"[A-Za-z_]\w*(?:\.[A-Za-z_]\w*|\[[^\[\]]+\])*", tail)
        if not token or tail[len(token[0]):].startswith(("(", ".")):
            return None
        before = line
        after = line[:column] + token[0] + ".copy()" + tail[len(token[0]):]
    elif diagnostic[4] == "E_SINGLE_OWNER_MOVED":
        moved = re.search(r"'([A-Za-z_]\w*)'", diagnostic[5])
        if not moved:
            return None
        start = max([i for i in range(number) if re.match(r"(?:public )?func ", lines[i])] + [0])
        candidates = [i for i in range(start, number) if re.search(
            r"\b(?:mut|const) \w+(?::[^=]+)?\s*=\s*" + re.escape(moved[1]) + r"\s*$", lines[i])]
        if not candidates:
            return None
        number = candidates[-1]
        before, after = lines[number], lines[number] + ".copy()"
    else:
        return None
    lines[number] = after
    source.write_text("\n".join(lines) + "\n")
    return {"line": number + 1, "before": before, "after": after, "diagnostic": diagnostic[4]}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--compiler", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--start", type=int, default=0)
    parser.add_argument("--limit", type=int, default=10)
    parser.add_argument("--migrate-copies", action="store_true")
    parser.add_argument("--sources", help="comma-separated source stems for focused followups")
    parser.add_argument("--ownership", choices=("zero", "default"), default="zero")
    args = parser.parse_args()
    manifest = json.loads((HERE / "originals.json").read_text())
    manifest = [entry for entry in manifest if entry["source"] != "tests/lang/frontend_type_helpers.my"]
    if args.sources:
        names = set(args.sources.split(","))
        manifest = [entry for entry in manifest if Path(entry["source"]).stem in names]
    args.output.mkdir(parents=True, exist_ok=True)
    report = {"compiler_sha256": hashlib.sha256(args.compiler.read_bytes()).hexdigest(),
              "harness_sha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
              "ownership": args.ownership, "cases": []}
    for entry in manifest[args.start:args.start + args.limit]:
        source = ROOT / entry["source"]
        command = [str(args.compiler), "check", str(source), "--no-cache"]
        if args.ownership == "zero":
            command.append("--experimental-zero-rc")
        changes = []
        for attempt in range(40):
            ran = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, timeout=120)
            if not ran.returncode or not args.migrate_copies:
                break
            change = certain_copy(source, ran.stderr)
            if change is None:
                break
            changes.append(change)
        else:
            raise RuntimeError("copy-migration iteration budget exceeded: " + str(source))
        row = {"source": entry["source"], "command": command, "source_sha256": hashlib.sha256(source.read_bytes()).hexdigest(),
               "status": ran.returncode, "stdout": ran.stdout, "stderr": ran.stderr, "copy_changes": changes}
        report["cases"].append(row)
        (args.output / f"batch-{args.start}.json").write_text(json.dumps(report, indent=2) + "\n")
        print(entry["source"], ran.returncode, ran.stderr[:220].replace("\n", " "), flush=True)


if __name__ == "__main__":
    main()
