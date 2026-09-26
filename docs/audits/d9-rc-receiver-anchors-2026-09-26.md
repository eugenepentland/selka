# RC receiver anchors after temporary cleanup

The fresh `39f75f3f` sweep exposed eight failures, all involving `sorted()`.
The smallest reproducer is `source: list[int] = []; ordered = sorted(source)`.
The compiler builds a list in temporary local 4, borrows it in receiver local 2,
and pins that receiver for sorting. Early edge cleanup released local 4's owner
immediately after the receiver store. Sorting then ended the receiver hold,
retiring the list before the later load of local 2 published the sorted result.
This is missing physical alias liveness, not missing runtime child ownership.

Edge cleanup now follows live receiver aliases and projection parents before
releasing a candidate owner. Traversal is bounded by the number of locals;
a cycle conservatively prevents release. This preserves the physical owner
while a borrowed receiver can still be read after its mutation scope. A skipped
release retains the existing frame-cleanup fallback. Unrelated dead collection
temporaries still retire early; no runtime or general receiver lowering changed.

Three new guest regressions cover an empty sorted result, a text result retained
after its source is cleared, and sorting a list-producing method chain. The
expanded run executes 45 unchanged/new assertions, including all eight sweep
failures (the property regression uses its failing empty input). QBE and actual
LLVM `-O3 --lto` both pass with identical balanced counts: 91,979 heap allocations
and retirements, 544,524 owner acquisitions, 636,503 releases and 88,861 holds in
each direction. Arena allocations total 129.

The n=12 matrix control still prints exactly `41383` and `485891` on both
backends, with one clone, 132 allocations/retirements, 9,345 acquisitions,
9,477 releases and 10,368 balanced holds. These counts exactly match the prior
temporary-cleanup diagnostic; this is not a timing acceptance claim.

Validation uses Debug compiler SHA256
`6a6f47f01e0f6ec6f67d0d54b73d797ad80364ddddafb2dea946554774fe5280`.
LLVM commands omit `--qbe`, which otherwise overrides the preceding backend
selection. Raw reproducer, before failures, commands and results are in
[compressed evidence](evidence/d9-rc-receiver-anchors.json.gz). Integration owns
the combined full gate.

The mandated `parity/suite/knucleotide` workload also passes `pc.check` on both
actual backends after this fix. Its output SHA256 is
`85ef61714a76ad7ce4c0b54cc49ec081c54c2966978de102da6a53e2d208c0bb`.
Both count 7,000,284 heap allocations/retirements, 9,283,306 owner acquisitions,
16,283,590 owner releases and 27,999,838 balanced holds, with no clones. Exact
commands and checks are in [evidence](evidence/d9-rc-knucleotide-anchors.json).
