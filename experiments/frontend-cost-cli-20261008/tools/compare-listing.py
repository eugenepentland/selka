#!/usr/bin/env python3
"""Compare default interface bytes against the immutable FB1 compiler."""
import hashlib
import json
import pathlib
import re
import subprocess
import sys

root = pathlib.Path(__file__).resolve().parents[1]
worktree = root.parents[1]
timer = root / "tools" / "time-command.py"
base = pathlib.Path(sys.argv[1]).resolve()
candidate = pathlib.Path(sys.argv[2]).resolve()
run_label = sys.argv[3]
cases = {
    "reachable": {
        "input.my": "module input\npublic def changed(xs: list[int]) -> list[int]:\n    ys = xs\n    ys[0] = 4\n    return ys\npublic def unused() -> int:\n    return 9\ndef main(out: Stream) -> int:\n    xs = [1]\n    out.print(changed(xs))\n    return 0\n",
    },
    "library": {"input.my": "module input\npublic def answer() -> int:\n    return 42\n"},
    "bad-body": {"input.my": "module input\npublic def main() -> int:\n    return unknown()\n"},
    "bad-signature": {"input.my": "module input\npublic def answer(value: Unknown) -> int:\n    return 42\n"},
    "imported": {
        "input.my": "module input\nimport helper\ndef main(out: Stream) -> int:\n    out.print(helper.answer())\n    return 0\n",
        "helper.my": "module helper\npublic def answer() -> int:\n    return 42\n",
    },
}
summary = {
    "base": str(base), "candidate": str(candidate),
    "base_sha256": hashlib.sha256(base.read_bytes()).hexdigest(),
    "candidate_sha256": hashlib.sha256(candidate.read_bytes()).hexdigest(),
    "inputs": cases, "comparisons": [],
}


def invoke(label, binary, *args):
    label = run_label + "-" + label
    subprocess.run([sys.executable, str(timer), label, "--", str(binary), *args],
                   cwd=worktree, capture_output=True, check=False)
    receipt = json.loads((root / "logs" / (label + ".json")).read_text())
    return (receipt["exit_code"], (root / "logs" / (label + ".stdout")).read_bytes(),
            (root / "logs" / (label + ".stderr")).read_bytes())


for case, files in cases.items():
    directory = worktree / ".mylang-cache" / "frontend-cost-cli" / "listing" / case
    directory.mkdir(parents=True, exist_ok=True)
    for name, source in files.items():
        (directory / name).write_text(source)
    entry = str(directory / "input.my")
    for mode in ("plain", "contracts"):
        args = ("list-interfaces", entry) + (("--contracts",) if mode == "contracts" else ())
        old = invoke("listing-" + case + "-" + mode + "-base", base, *args)
        new = invoke("listing-" + case + "-" + mode + "-candidate", candidate, *args)
        assert old == new, (case, mode, old, new)
        summary["comparisons"].append({"case": case, "mode": mode,
                                       "exit_code": new[0], "identical": True})
    if case in ("reachable", "imported"):
        plain = invoke("listing-" + case + "-prefix", candidate, "list-interfaces", entry)
        cost = invoke("listing-" + case + "-cost", candidate, "cost", entry)
        listed = invoke("listing-" + case + "-appended", candidate, "list-interfaces", entry, "--cost")
        assert plain[0] == cost[0] == listed[0] == 0, (case, plain, cost, listed)
        assert listed[1] == plain[1] + cost[1], case
        assert plain[2] == b"", case
        # The shared collector reports its elapsed nanoseconds on stderr.
        # Keep the raw diagnostics; compare every other byte, including verdicts.
        strip_timing = lambda data: re.sub(rb"in [0-9]+ ns\n$", b"in TIMED ns\n", data)
        assert strip_timing(cost[2]) == strip_timing(listed[2]), case
        summary["comparisons"].append({"case": case, "mode": "cost-appended",
                                       "exit_code": 0, "identical": True})
summary["passed"] = len(summary["comparisons"])
(root / "listing-comparison.json").write_text(json.dumps(summary, indent=2) + "\n")
print(json.dumps({"passed": summary["passed"], "default_comparisons": 10,
                  "exact_cost_append_comparisons": 2}))
