# Plain-result read-only helper composition

This is a focused production experiment, not the complete Stage 4 corpus.
The source extends the existing read-only grammar only across direct helpers
which independently prove a plain, count-free, unique-free return. Managed
returns still refuse; no borrowed-result routing is changed.

The Debug compiler before is the frozen joined ownership compiler from
`e5d47d20`, byte-identical to the corrected `c90c84be` gate compiler.
The candidate starts from `f9a895c8` and adds the archived patch and new files.
`identity.json` records exact compiler/source/guest identities. The sibling
integration branch also has separate improvements; the ratios here do not
claim to describe that newer combined build.

`schematic.json.gz` and `lox.json.gz` retain alternating median-three raw
instruction observations on CPU2. Guest commands and workload sizes come from
the unchanged accepted corpus. LLVM manifests require O3 and full LTO. Counted
runs are separate from timing; no RSS or full-corpus acceptance is claimed.
Accepted GC medians come from the previously archived comparison, not a newly
interleaved GC measurement. `accepted-gc.json.gz` preserves those receipts.

Only `layout::nearest` changes among 129 schematic functions. `table::get` and
`resolver::resolve_local` change among 405 Lox functions, so the unchanged full
N10 Lox program is measured as a control. Complete before/after emissions and
their hashes are retained under `emissions/`.

Correctness evidence contains six guest assertions in eight before/after ×
QBE/LLVM × GC-stress/RC configurations, sixteen exact Debug bounds/overflow/
step/frame traps, and a three-state transitive body-edit cache check. Warm and
cold IL agree for both admitted bodies and the allocating-helper refusal;
both actual native backends also agree on the final result and balanced counts.
The GC guest executables are byte-identical before and after.

The first trap harness used an unsupported integer entry parameter and was
rejected with `E_MAIN` after the eight guest configurations had passed.
The replacement ReleaseFast harness correctly refused finite step accounting
with `R_NO_STEP_ACCOUNTING`. Both unsuccessful receipts are retained; the final
Debug trap harness passes. These are harness corrections, not production fixes.
The first unit compile used removed Zig array repetition syntax; the corrected
focused run passes 22 tests. The harmless exit-zero `failed command` stanza is
preserved in the raw successful log.

Run `python3 experiments/d9-rc-readonly-calls-20260927/verify.py`; add `--live`
while the immutable local compiler and guest files remain available. The
verifier reparses raw instruction counts, recomputes medians/ratios and checks
trap equality, ownership balances, actual backend flags, source identities and
archive hashes. The complete integration gate is reported separately.
