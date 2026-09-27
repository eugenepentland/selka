#!/usr/bin/env python3
"""Replay the private-field loan regression matrix with an installed compiler."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("compiler", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    compiler = args.compiler.resolve()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    receipt = {"compiler_sha256": hashlib.sha256(compiler.read_bytes()).hexdigest(), "runs": []}
    names = ["field_augmented", "rc_semantic_publication", "rc_semantic_history",
             "rc_aggregate_values", "rc_box_writeback", "mut_argument_places",
             "mut_dictionary_arguments", "rc_view_receivers", "array_places"]
    for backend in ("qbe", "llvm"):
        for mode in ("rc", "gc"):
            for name in names + ["iteration"]:
                source = root / "tests/lang" / (name + ".my")
                action = "test"
                if name == "iteration":
                    source = Path(__file__).parent / "iteration.my"
                    action = "run"
                command = [str(compiler), action, str(source), "--cache-dir=" + str(output / "cache")]
                if action == "test":
                    command += ["--force", "--json", "--jobs", "2"]
                command += ["--rc-runtime=stats"] if mode == "rc" else ["--gc-stress"]
                if backend == "llvm":
                    command += ["--release"]
                run = subprocess.run(command, text=True, capture_output=True)
                receipt["runs"].append(dict(backend=backend, mode=mode, name=name, command=command,
                                            status=run.returncode, stdout=run.stdout, stderr=run.stderr))
                (output / "results.json").write_text(json.dumps(receipt, indent=2) + "\n")
                if action == "run":
                    assert run.returncode == 1 and run.stdout == "7\n", receipt["runs"][-1]
                    assert "R_LIST_ITERATION_MUTATION" in run.stderr, receipt["runs"][-1]
                else:
                    assert run.returncode == 0, receipt["runs"][-1]
                    result = json.loads(run.stdout)
                    assert result["failed"] == 0 and result["passed"] > 0, result
                print(backend, mode, name, "PASS", flush=True)


if __name__ == "__main__":
    main()
