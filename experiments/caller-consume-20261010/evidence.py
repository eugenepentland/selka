#!/usr/bin/env python3
"""Extract exact Core and LLVM function fragments from completed captures."""
import argparse
import hashlib
import json
from pathlib import Path
import re


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def fragments(text, names, kind):
    result = []
    for name in names:
        if kind == "core":
            pattern = rf"^fn {re.escape(name)}\([^\n]*\n(?:(?!^(?:fn |facts |list )).|\n)*"
        else:
            pattern = rf'^define [^\n]*@"my\.{re.escape(name)}"\([^\n]*\n.*?^}}'
        match = re.search(pattern, text, re.MULTILINE | re.DOTALL)
        if match is None:
            raise ValueError(f"missing {kind} function {name}")
        result.append(match.group(0).rstrip())
    return "\n\n".join(result) + "\n"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--baseline", type=Path, required=True)
    parser.add_argument("--candidate", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    index = {"scope": "Exact selected function fragments; LLVM declarations and metadata are omitted.",
             "script_sha256": sha(Path(__file__)), "files": {}}
    for label, capture in (("baseline", args.baseline), ("candidate", args.candidate)):
        manifest = json.loads((capture / "results.json").read_text())
        for sample, functions in (("04_returned_list", ("probe", "make_values")),
                                  ("20_loop_carried", ("probe", "append_batch"))):
            for kind, file in (("core", "core.ir"), ("llvm", "plain.ll")):
                raw = capture / sample / file
                name = f"{label}-{sample}.{kind}"
                target = args.output / name
                target.write_text(fragments(raw.read_text(), functions, kind))
                index["files"][name] = {"compiler_sha256": manifest["compiler_sha256"],
                    "raw_path": str(raw), "raw_sha256": sha(raw), "functions": functions,
                    "fragment_sha256": sha(target)}
    (args.output / "index.json").write_text(json.dumps(index, indent=2) + "\n")


if __name__ == "__main__":
    main()
