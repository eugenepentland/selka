"""Execute unchanged direct/callback consumers across a producer ABI edit."""
import argparse
import ast
import hashlib
import json
from pathlib import Path
import re
import subprocess


def sources(root):
    text = (root / "test/fix_cli_test.zig").read_text()
    values = {}
    for name in ("abi_append_producer", "abi_rebind_producer"):
        literal = re.search(r"const " + name + r" = (\"(?:[^\"\\]|\\.)*\");", text).group(1)
        values[name] = ast.literal_eval(literal)
    block = text.split("const abi_consumer =\n", 1)[1].split("\n;", 1)[0]
    values["abi_consumer"] = "\n".join(line.split("\\\\", 1)[1] for line in block.splitlines()) + "\n"
    return values


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--compiler", required=True)
    parser.add_argument("--root", default=".")
    options = parser.parse_args()
    root = Path(options.root).resolve()
    compiler = str(Path(options.compiler).resolve())
    evidence = root / "experiments/new-core-s2-20261005/wave-a/s2-la"
    fixture = root / ".tmp/warm-abi-modes-final"
    values = sources(root)
    answers = []
    modes = {"rc": ["--rc-runtime"], "gc-stress": ["--gc-runtime", "--gc-stress"], "release": ["--release"]}
    for mode, flags in modes.items():
        project = fixture / mode
        project.mkdir(parents=True, exist_ok=True)
        consumer = project / "main.my"
        consumer.write_text(values["abi_consumer"])
        digest = hashlib.sha256(consumer.read_bytes()).hexdigest()
        for phase, producer in (("append-cold", "abi_append_producer"), ("append-warm", "abi_append_producer"), ("rebind-edited", "abi_rebind_producer"), ("rebind-warm", "abi_rebind_producer")):
            (project / "lib.my").write_text(values[producer])
            argv = [compiler, "run", "main.my", "--print-result", "--report", "--cache-dir=" + str(project / "cache"), *flags]
            result = subprocess.run(argv, cwd=project, capture_output=True, text=True, timeout=300)
            (evidence / f"warm-abi-{mode}-{phase}.log").write_text(f"argv: {json.dumps(argv)}\nexit: {result.returncode}\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}")
            assert result.returncode == 1 and result.stdout == "1\n", (mode, phase, result.returncode, result.stderr)
            assert "work-report-v1" in result.stderr, (mode, phase)
            assert hashlib.sha256(consumer.read_bytes()).hexdigest() == digest
            answers.append({"mode": mode, "phase": phase, "value": 1, "consumer_sha256": digest})
    report = {"runs": len(answers), "passed": len(answers), "producer_signature_unchanged": True, "results": answers}
    (evidence / "warm-abi-modes-final.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
