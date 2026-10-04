# G4 independent review

Two independent ReleaseFast sessions on production `6cf7bdce` confirm ten of
twelve measured LLVM rows at 1.00 relative to the fastest current configuration.
Both sessions satisfy all paired upper-95% comparisons against the other five
arms for those ten rows. Small equality and small integer sorting remain open.
Three QBE rows confirm below 1.10 for information; QBE parity is not required.

[`review.py`](review.py) replays 1,440 qualification outcomes, 516 nearby-input
checks, 192 text oracles, six recorded refusal codes, eleven complete native
outcome pairs and the 42-test focused result. It verifies live source, compiler,
runtime asset, guest and frozen-reference identities. Five prior optimized C
sanitizer suites are reused after matching all 114 native source/test files and
the suite driver against their original Git revision. They are not fresh tests
of the ReleaseFast executable files. Text evidence retains checksums/refusal
codes rather than complete process streams.

[`review-archive.py`](review-archive.py) checks all 47 raw/archive and three
helper bindings against retained original files. Both scripts create new
receipts and refuse to overwrite them; use new output paths for a fresh replay.
The separate remainder review is evidence for an unintegrated candidate.

The [accepted analysis](../../benchmarks/runtime/candidates/goal110-g4-6cf7bdce-rf-20261004-accepted.json)
uses session B medians and session A confirmation. The
[live goal document](../../benchmarks/runtime/RUNTIME_110_GOAL.md) retains all
80 rows and the next work. This milestone is neither full-suite timing nor a
new full-repository correctness gate; final goal acceptance remains outstanding.
