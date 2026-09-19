#!/usr/bin/env python3
"""Stage 1b counterfactual: replace the remaining operand-slot address-takes.

Every `%vN =l copy %sK` in an emitted unit passes the *address* of operand slot
`%sK` to a runtime helper (`myl_native_equal`, `myl_native_list_append`, a
record constructor's store barrier, a renderer). Taking that address is what
keeps `%sK` in memory: QBE promotes a slot only when every use is a load or a
store of it (`vendor/qbe/mem.c:9-50`), and the operand slots are shared by stack
height, so one address-take pins a slot for scalars everywhere in the function.

The rewrite gives each site its own eight-byte scratch word, declared in the
entry block, and passes that word's address instead:

    %tmp =l loadl %sK
    storel %tmp, %psJ
    %vN =l copy %psJ

Two things this script exists to record, both measured on the 927,415 byte EDA
census with byte-identical output:

  * The scratch *must* be declared in the entry block. An `alloc8` anywhere else
    is not removed by `seladdr`, which only walks the start block
    (`vendor/qbe/amd64/isel.c:893-905`), so it reaches `salloc`
    (`vendor/qbe/util.c:542-565`) and lowers to a dynamic `subq %rsp`: the slot
    address changes on every iteration and the stack walks down until it faults.
    A first version of this script emitted the alloc at the site and segfaulted
    on the census.
  * The rewrite is a measured loss on this workload: 164.31 M instructions
    against 163.40 M for the landed compiler, +0.6 %, because it adds a load and
    a store per site while the operand slots it unpins are not hot. It was not
    landed; the finding is in `docs/audits/hot-loops-landed-2026-09-19.md`.

Usage: operand_scratch.py <input manifest> <output manifest>
"""
import json, re, sys

src, dst = sys.argv[1], sys.argv[2]
data = json.load(open(src))
replaced = 0
for function in data["functions"]:
    lines = function["il"].split("\n")
    sites = [i for i, line in enumerate(lines) if re.match(r"^ %v\d+ =l copy %s\d+$", line)]
    if not sites:
        continue
    # The entry block ends at its first terminator; the frame protocol's labels
    # come after it, and a declaration past them would not be promoted.
    entry_end = next((i for i, line in enumerate(lines) if line.startswith((" jmp ", " jnz ", " ret "))), len(lines) - 1)
    declarations = [f" %ps{n} =l alloc8 8" for n in range(len(sites))]
    out = []
    site_index = 0
    for index, line in enumerate(lines):
        if index == entry_end:
            out.extend(declarations)
        match = re.match(r"^ (%v\d+) =l copy (%s\d+)$", line)
        if match:
            pointer, slot = match.groups()
            out.append(f" %v{pointer[2:]}_v =l loadl {slot}")
            out.append(f" storel %v{pointer[2:]}_v, %ps{site_index}")
            out.append(f" {pointer} =l copy %ps{site_index}")
            site_index += 1
            replaced += 1
            continue
        out.append(line)
    function["il"] = "\n".join(out)
json.dump(data, open(dst, "w"))
print(f"operand address-takes replaced: {replaced}")
