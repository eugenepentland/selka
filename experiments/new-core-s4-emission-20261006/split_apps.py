#!/usr/bin/env python3
"""Retain real two-module variants of the five unchanged S3 application workloads."""
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CASES = ("packet_decode", "lox_eval", "word_count", "csv_aggregate", "json_transform")
DECL = re.compile(r"^(?:public )?(?P<kind>extern def|def|record|union) (?P<name>[A-Za-z_]\w*)", re.MULTILINE)
TOKEN = re.compile(r'"(?:\\.|[^"\\])*"|\'(?:\\.|[^\'\\])*\'|\#.*|[A-Za-z_]\w*')


def generate(case, directory):
    source = ROOT / f"test/core/row_{case}.my"
    text = source.read_text()
    declarations = list(DECL.finditer(text))
    imports = "\n".join(line for line in text[:declarations[0].start()].splitlines() if line.startswith("import "))
    library, external, main = [], [], None
    names = set()
    for index, declaration in enumerate(declarations):
        end = declarations[index + 1].start() if index + 1 < len(declarations) else len(text)
        body = text[declaration.start():end]
        if declaration["kind"] == "extern def":
            external.append(body)
        elif declaration["name"] == "main":
            main = body
        else:
            names.add(declaration["name"])
            library.append("public " + body if not body.startswith("public ") else body)
    if main is None:
        raise ValueError(f"no main in {source}")
    # These fixed wrappers have no local bindings shadowing a workload declaration.
    # Strings/comments remain byte-for-byte intact, including benchmark inputs.
    main = TOKEN.sub(lambda token: "workload." + token[0] if token[0] in names else token[0], main)
    directory.mkdir(parents=True, exist_ok=False)
    (directory / "workload.my").write_text("module workload\n" + imports + "\n\n" + "\n".join(library))
    (directory / "app.my").write_text("module app\nimport workload\n" + imports + "\n\n" + "\n".join(external) + main)
    return directory / "app.my"


if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory", type=Path)
    args = parser.parse_args()
    for case in CASES:
        print(generate(case, args.directory / case))
