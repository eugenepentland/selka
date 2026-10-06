# S2-X replay after the dictionary fact repair

Frozen integration source: `996d9baad0e00ef98b4d3e7b59dc3616809fa013`, including
repair source `0c6029d7`. All original `090dabd5` failure and coverage artifacts
are preserved unchanged. This replay changes no compiler source or index and
makes no commits.

The strict full leak/verify sweep passes at both debug and release:
1224 matching, 0 mismatching, 316 precise refusals out of 1540 tests. The outer
process exits 0 in 49.99 seconds, peak RSS 325508 KiB; wall time including
admission is 50.03 seconds. No abnormal compiler exit, empty stdout, failed
native JSON comparison, leak, fact failure or crash is reported. Native compiler
statuses, parsed `native-tests-v1` reports and test verdicts are checked by
`conformance_checked.py` and the inherited conformance/test runners.

The exact source, private cache environment, build-slot command and full stdout
and stderr are retained in `s2-x-leak-verify-after-fact.txt`. The protected
accepted-72 old oracle and adjacent qbe are used; the repaired installed core
is the tested compiler. The first conformance file is processed serially before
the four-way sweep to initialize its runtime-object cache. The native sweep's
build slot is released.

Standard coverage also passes: all four child processes exit 0, every child
stderr is empty, and complete child reports are retained in
`coverage-standard-after-fact/`. The command runs at nice 10 on CPUs excluding
2, 3, 10 and 11; it performs read-only frontend work. The exact command and
output are in `s2-x-coverage-standard-after-fact.txt`. Command time is 2.64
seconds, peak RSS 39300 KiB.

| Count | Frozen 090 | Repaired final |
|---|---:|---:|
| Accepted qualified function names, per-corpus deduplication | 3185 / 3627 | 3185 / 3627 |
| Proven checks in accepted functions | 4757 | 4757 |
| Exact checks in accepted functions | 3764 | 3764 |
| Qualified names contributing check metrics | 3017 | 3017 |

The comparison script and its checked results are retained as
`coverage-standard-after-fact/compare_admissions.py`, `admission-proof.txt` and
`admission-proof.json`. It verifies every one of 4253 ordered raw function
occurrences, all acceptance/first-refusal results, all 11 frontend rejection
diagnostics and all four compiler input lists. Only the private temporary
directory prefix is normalized. All results agree, and individual check metrics
also agree. Every one of the 71 remaining observed refusal reasons is retained
in the final `all-reasons.json`, matching the original complete reason table.

The source diff over the compiler and all four coverage cohorts contains only
`src/core/facts.zig` and `src/core/dict_test.zig`; frontend, typed source and
coverage cohort source are unchanged. Identical admissions and first refusals
therefore preserve every typed loop's count and attribution. The original
`coverage-loops.json` remains valid on the repaired final source without
repeating its 312.48-second sweep:

| Before 72 / final repaired | Before accepted | Final accepted | Total |
|---|---:|---:|---:|
| Per-file function instances | 2756 | 3687 | 4250 |
| Checked loop instances in accepted functions | 607 | 1260 | 1539 |

Raw ordered occurrences and per-file deduplicated function instances are
different count definitions. A refused whole function attributes its loops to
the function's first refusal, including when that construct lies outside the
loop; this is not independent fragment admission. The original full before/after
loop and refusal table is preserved, with its final-source reuse proof in the
new admission artifact. The seven example and four language frontend rejections
remain unchanged.
