#!/usr/bin/env python3
"""Execute existing collection guest bodies through the opt-in counted RC CLI."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
GROUPS = {
    "basic": [f"tests/guest/{name}.my" for name in ("lists", "dicts", "text", "bytes")],
    "views": [f"tests/lang/{name}.my" for name in ("byte_views", "text_views")],
    "wide": [f"tests/lang/{name}.my" for name in ("python_bytes", "byte_buffer", "keyed_sorting")],
    "regression": ["tests/lang/rc_collection_builtins.my"],
}


def prepare(directory, sources):
    imports, cases, identities = [], [], {}
    for source in sources:
        path = ROOT / source
        original = path.read_text()
        text = original
        # Arena escape belongs to its separate, unfinished integration workstream.
        if path.stem == "text_views":
            text = text[:text.index("\ndef inner_piece")]
        name = "rc_probe_" + path.stem
        text = re.sub(r"^module \w+", "module " + name, text, count=1)
        (directory / (name + ".my")).write_text(text)
        imports.append(name)
        cases.extend(name + "." + function for function in re.findall(r"public def (test_\w+)\(", text))
        identities[source] = hashlib.sha256(original.encode()).hexdigest()
    body = "module rc_probe_driver\n" + "".join("import " + name + "\n" for name in imports)
    body += "\ndef main(out: Stream) -> int:\n    failures = 0\n"
    for index, case in enumerate(cases):
        body += f"    if not {case}():\n        failures += {1 << index}\n"
    body += "    out.print(failures)\n    return 0\n"
    entry = directory / "rc_probe_driver.my"
    entry.write_text(body)
    return entry, cases, identities


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--compiler", type=Path, required=True)
    parser.add_argument("--qbe", type=Path, required=True)
    parser.add_argument("--backend", choices=("qbe", "llvm"), required=True)
    parser.add_argument("--workspace", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    args.workspace.mkdir(parents=True, exist_ok=True)
    compiler = args.compiler.resolve()
    result = {"source_commit": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip(),
              "compiler_sha256": hashlib.sha256(compiler.read_bytes()).hexdigest(),
              "backend": args.backend, "guest_mode": "ReleaseFast", "runtime": "stats", "groups": {}}
    for group, sources in GROUPS.items():
        with tempfile.TemporaryDirectory(prefix="rc-" + group + "-", dir=args.workspace.resolve()) as temporary:
            entry, cases, identities = prepare(Path(temporary), sources)
            command = [str(ROOT / "scripts/build-slot.sh"), "build", str(compiler), "build", str(entry),
                       "--rc-runtime=stats", "--backend", args.backend, "--mode", "ReleaseFast",
                       "--qbe=" + str(args.qbe.resolve()),
                       "--cache-dir=" + str(args.workspace.resolve() / ("cache-" + args.backend)),
                       "--max-memory=512M", "--run"]
            run = subprocess.run(command, cwd=ROOT, capture_output=True, text=True)
            records = [json.loads(line.removeprefix("MYLANG_RC_COUNTS "))
                       for line in run.stderr.splitlines() if line.startswith("MYLANG_RC_COUNTS ")]
            assert run.returncode == 0 and run.stdout.strip() == "0", (group, run.returncode, run.stdout, run.stderr)
            assert len(records) == 1, (group, run.stderr)
            counts = records[0]
            assert not counts["saturated"] and counts["heap_allocate"] == counts["retire"], (group, counts)
            assert counts["heap_allocate"] + counts["owner_acquire"] == counts["owner_release"], (group, counts)
            result["groups"][group] = {"cases": cases, "source_sha256": identities, "counts": counts,
                                        "exit": run.returncode, "stdout": run.stdout, "stderr": run.stderr}
            print(f"{args.backend}: {group}: {len(cases)} passed, {counts['retire']} allocations retired", flush=True)
    args.output.write_text(json.dumps(result, indent=2) + "\n")


if __name__ == "__main__":
    main()
