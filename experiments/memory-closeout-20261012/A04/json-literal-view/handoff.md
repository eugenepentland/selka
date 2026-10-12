# JSON helper handoff

Base: `bed11cf3bf3102ffec44487e431a1573fdf02ad5`.
Worker branch: `codex/memory-closeout-20261012-A04-json`.
Owned production file: `src/stdlib/json.my`.
Change: a private scalar-returning helper compares a borrowed byte range before
its caller updates the scanner; the conservative slice optimizer is unchanged.

Qualification: `qualify_helper.py` on the coordinator's immutable Support7 compiler
passes 12/12 native lanes (original and helper sources × five checked modes plus
ordinary release). Exact commands, source/compiler/binary/LLVM hashes, counters
and raw stdout/stderr are under `readonly-helper-01/`. Checked RC0/live0 and
structural audits pass; the same original JSON fixture asserts all outputs.
`comparison.json` records the recovered three optimized temporary allocations and
unchanged managed peaks. No timing/RSS result is claimed.

The earlier explicit view-comparison proposal was refused as unsupported and
remains evidence only. No production helper contract or shared file is needed.
The next integrated candidate must rerun the affected library/application lanes.
Required format/Guardian results are recorded with the feature commit delivery.
