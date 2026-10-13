Arithmetic-inline is rejected for adoption: removing the native helper call did
not establish a runtime benefit in the approved paired diagnostic campaign.
Coordinator explicitly accepted that decision; no application source was changed.

This isolated experiment copies frozen coordinator source-002/lox into baseline
and candidate snapshots. Their only difference is interpreter.my: the existing
numeric operator match moves from arithmetic into binary's already checked
numeric branch. Numeric tag checks, operators, error order/messages/lines, the
string path and operand GC roots retain their original source behavior. The
untouched control and prototype use identical release/checked flags with compiler
9bedb835438615d79ed8f2985352877a8c844eebeb74cd95a1d276332b6b0c6a.
Source/compiler identities, exact commands, patch and all raw output are retained.

Both canonical verified suites passed all 103 tests with failed/skipped/unsupported
and cached zero. Twenty bounded correctness controls passed across both arms,
normal and GC stress: every numeric operator, NaN and signed-zero comparisons,
RHS evaluation/error order, operator lines, string concatenation rooting under GC,
closures and nested scopes. Root source-002 and both snapshot byte hashes remained
unchanged after build/tests/native inspection and through measurements.

Actual native inspection confirms baseline evaluate contains the arithmetic call
and its 90-byte helper. Candidate has neither the helper symbol nor call site.
The native evaluator grows 8,636 -> 8,672 bytes (+36); evaluator plus helper drops
54 bytes overall. This proves emitted/native call removal, not a runtime gain.
Both evaluator disassemblies and native/LLVM hashes are retained.

Coordinator-approved timing used exact existing fib.tree.28, binary_trees.tree.10
and string_equality.tree.10000 inputs, unchanged pinned Zig, untouched C2 and the
one-change prototype. Each case used CPU8, two warmups and nine forward/reversed
paired rounds in three separately admitted chunks. Fresh Zig calibration sets
the unchanged 3x cutoff with an absolute 120-second ceiling; later chunks preserve
that case's exact calibration/identities through prior receipts. All 81 wall
samples completed with matching outputs and identities; no samples were excluded.
Every calibration, warmup, progress journal and receipt is retained. RSS and
managed allocation traffic were not measured in this runtime-only diagnostic.

Paired candidate/control medians (10,000 bootstrap resamples, seed42, 95% median
interval; these are small diagnostic samples, not full benchmark cells):

| Case | Candidate / C2 | 95% interval | Candidate / Zig |
| --- | ---: | --- | ---: |
| fib | 1.00164 | 0.99570–1.02201 | 1.13083 |
| binary_trees | 1.00142 | 0.98504–1.01765 | 1.31393 |
| string_equality | 0.99241 | 0.98897–1.01076 | 1.40351 |

Every candidate/control interval includes one. Neither direct paired numeric
cases nor the local-read control supports adoption. Benefits are not combined
with any other prototype. The later atom-operand experiment is independent and
has its own untouched C2 control; arithmetic snapshots remain immutable.
No production/coordinator/peer source edits, historical evidence overwrites,
RC fallback, stored views, new arena, nested agents, pushes or feedback-log writes.
