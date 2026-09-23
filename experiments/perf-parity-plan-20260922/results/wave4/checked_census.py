#!/usr/bin/env python3
"""Census of checked-arithmetic sites and what the LLVM adapter lowers them to.

usage: checked_census.py MYLANG ADAPTER_DIR PROGRAM.my [PROGRAM.my ...]

Emits each program's fast-protocol IL (`emit-qbe --drop-step-checks
--drop-frame-checks`, the protocol `mylang build` ReleaseFast uses), finds every
`jnz` into a block whose first call is `myl_qbe_fail_overflow_op(ctx, OP, a, b,
WIDTH)`, and classifies the flag feeding it:

* `intrinsic:<stem>` — `llvm_emit.OverflowChecks` matched it (LLVM-OVERFLOW-INTRINSIC-1);
* `literal` — the one-compare test against a literal operand;
* `range<W>` — a narrower width's range test over the exact 64-bit result;
* `divide` — the signed `MIN // -1` guard, which reports through the same helper;
* `other` — anything else (none expected).
"""
import collections
import json
import os
import subprocess
import sys

OPS = {0: "add", 1: "sub", 2: "mul"}


def main():
    mylang, adapter = sys.argv[1], sys.argv[2]
    sys.path.insert(0, adapter)
    from qbe_llvm import parse_unit  # noqa: E402
    from llvm_emit import OverflowChecks  # noqa: E402
    total = collections.Counter()
    for program in sys.argv[3:]:
        run = subprocess.run([mylang, "emit-qbe", program, "--drop-step-checks",
                              "--drop-frame-checks"], capture_output=True, text=True)
        if run.returncode != 0:
            print(f"{os.path.basename(program):28s} skipped: {run.stderr.splitlines()[0]}")
            continue
        emitted = run.stdout
        counts = collections.Counter()
        for function in json.loads(emitted)["functions"]:
            unit = parse_unit(function["il"], function["name"])
            checks = OverflowChecks(unit.function)
            definitions = {}
            for block in unit.function.blocks:
                for instruction in block.instructions:
                    if instruction.dest is not None:
                        definitions[instruction.dest.name] = instruction
            blocks = {block.label: block for block in unit.function.blocks}
            for block in unit.function.blocks:
                branch = block.terminator()
                if branch is None or branch.opcode != "jnz":
                    continue
                target = blocks.get(branch.extra[0])
                calls = [i for i in (target.instructions if target else []) if i.opcode == "call"]
                if not calls or calls[0].extra != "myl_qbe_fail_overflow_op":
                    continue
                width = int(calls[0].args[4].text)
                flag = definitions.get(branch.args[0].name)
                matched = checks.flags.get(id(flag)) if flag is not None else None
                if matched is not None:
                    kind = f"intrinsic:{matched[1]}"
                elif flag is not None and flag.opcode in ("or", "cugtl"):
                    kind = f"range{width}"
                elif flag is not None and flag.opcode in ("csgtl", "csltl") and \
                        not any(getattr(a, "name", None) for a in flag.args[1:]):
                    kind = "literal"
                elif flag is not None and flag.opcode == "and":
                    kind = "divide"
                else:
                    kind = "other"
                counts[kind] += 1
        total.update(counts)
        print(f"{os.path.basename(program):28s} " + ", ".join(f"{k} {v}" for k, v in sorted(counts.items())))
    print(f"{'TOTAL':28s} " + ", ".join(f"{k} {v}" for k, v in sorted(total.items())))


if __name__ == "__main__":
    main()
