# Stage 1 devspeed continuation, 2026-09-29

This continues WP-A4 of `next-work-plan-2026-09-29.md` from
`claude/devspeed-fidelity` at `a48b62f5`, in the isolated worktree
`mylang-worktrees/codex-next-stage1-20260929`, branch
`codex/next-stage1-20260929`. Source worktrees were read only. The compiler
changes were already committed; this continuation verifies them and records
the result for integration. No merge to `main` is authorized by this report.

## Committed implementation being verified

| Commit | Rule and spec tags | Direct coverage / before and after |
|---|---|---|
| `d17eea10` | Comparison chains, lexicographic text order, repetition, stepped ranges, formatting specs and decimal rounding: PY-CHAIN-1, PY-TEXT-ORDER-1, PY-REPEAT-1, PY-RANGE-STEP-1, PY-FSTRING-SPEC-1/2, PRELUDE-ROUND-2 | `tests/lang/python_expressions.my`, `format_specs.my`, and `src/python_expressions_test.zig`; previously missing Python forms now have CPython-derived expected values. `**` remains rejected. |
| `a1f8bedf` | Comprehensions and generator arguments, dictionary-key iteration and integer bitwise operations: PY-GATHER-1, PY-GENERATOR-1/2, PRELUDE-KEYS-1, PY-SET-OPS-1 | `tests/lang/dict_comprehensions.my`, `generator_arguments.my`, `sets.my`, and `src/collections_fidelity_test.zig`; missing collection forms now lower through the existing value-semantic collections. Main's set implementation and precedence remain authoritative. |
| `3928e4ab` | Structured fix producers, complete marker diagnostics and test diagnostic forwarding: DIAGNOSTIC-FIX-2, MUT-PARAM-8, NATIVE-TEST-DIAGNOSTICS-1, FIX-MIGRATION-2 | `src/diagnostic_fix_test.zig`, `test/fix_cli_test.zig`; one check reports all repairable markers rather than stopping at the first; pinned nine-module Lox migration restores all 91 markers. |
| `ee908d43` | Test-file private access, per-entry cases and one-diff affected planning: TEST-PRIVATE-ACCESS-1, DIRECTORY-CASES-1, AFFECTED-TEST-2 | `src/interfaces_test.zig`, `affected_tests_test.zig`, `test/integration.zig`; matching unimported test modules may access their own module's private declarations, entry-local case files are applied, and affected planning uses one source diff. |
| `5f3decd0` | Development-velocity trial harness | Developer experiment port; no compiler behavior change. |
| `88082112` | Original lane reports annotated with actual port scope | Documentation only. |
| `a48b62f5` | NUM-LITERAL-4 hint-pass invariant | Identical patch to integration's `3e946072`: name inference resolves only a known constant, preventing module-qualified enum comparisons from accumulating a spurious project error. Lox is the integration regression check. |

## Preserved lane-gate evidence

Read from `claude-devspeed-fidelity/.tmp/gate2/` and `.tmp/lang/`;
the summaries were copied into this worktree's `.tmp/a4/prior/`.
These are prior lane results, not fresh results from this continuation.

| Check | Preserved result |
|---|---|
| Build | Exit 0; Guardian 88 checks passed |
| Zig full test | 96/96 steps; 2603 tests passed (remaining shard selections reported skipped) |
| QBE | 51/51 steps; 473/473 tests passed |
| QBE-build | 29/29 steps; cached test verdict |
| Format | Exit 0 |
| Native memory | 23/23 steps; cached test verdict |
| Native heap | 10/10 steps; cached test verdicts |
| Guest tests: RC, release, stats, GC, GC-stress | Each 1372 passed across 211 programs; no cached, failed, skipped or dropped results |

## Continuation evidence

Fresh logs and artifacts live inside this worktree:
`.tmp/a4/`, `.tmp-rc-quick/` and `experiments/rc-fuzz/out/`.
Builds and heavy test commands use `scripts/build-slot.sh`;
`TMPDIR`, `ZIG_GLOBAL_CACHE_DIR` and the local Zig cache stay in this worktree.

The fresh build passed, including Guardian's 88 checks.

| Fresh continuation check | Result |
|---|---|
| Build | Exit 0; Guardian 88 checks, diff-scoped to 90 of 678 source files |
| `test-rc-fuzz -Dfuzz-seeds=100 -- --jobs 2`, warm cache | Exit 0; 98 ok, 0 invalid, 2 report-only GC-stress findings, **0 RC divergences** |
| Corpus build | 58/58 distinct binaries, 43 programs on QBE and LLVM |
| Corpus output checks, dev | 86/86 match the accepted GC output, including schematic SVG hashes |
| Corpus output checks, smoke | 86/86 match the accepted GC output, including schematic SVG hashes |
| Lox project build, default RC / GC | Both exit 0 |
| Lox directory tests, default RC / GC | Each 65 passed across 10 programs; no cached, failed, skipped or dropped results |
| Lox driver cases, default RC / GC | Each 13 passed; no cached, failed or skipped results |

Fuzz coverage includes 100 normal GC baselines, 100 default-RC runs, 100
stats runs with balanced owner/hold counts, 100 GC-stress runs and 12
`--release` runs (every eighth seed). The first cold-cache sweep reported
one RC-DIFF at seed 2 solely because the first GC native link printed Zig's
`ar rcs ...libcompiler_rt.a` command on stderr; stdout and exit status matched.
The identical 100-seed sweep passed with the warm cache. Both summaries are
preserved, rather than rewriting the cold result.

The two collector findings reproduce in the warm sweep: seed 19 aborts with
`a descriptor's scan plan disagrees with its fields` (exit 134), and seed 87
segfaults (exit 139). Normal GC and the RC modes agree for both seeds. These
match the already-open GC-only categories in
`rc-future-performance-2026-09-28.md`; this continuation did not establish a
new minimized cause or run these exact seeds on a pre-RC compiler. Repros
remain under `experiments/rc-fuzz/out/found/s19.my` and `s87.my`, and can be
regenerated with `experiments/rc-fuzz/gen2.py` using the corresponding seed.

The tested compiler SHA-256 remained
`5bd4f48956fadcec3f9091c6ae032eca5e64dcbf28717536d2bfa20826c154c3` throughout
corpus and Lox verification. No compiler or runtime source fixes were needed.

## Performance against the original m14 dev baseline

Instruction ratios below compare RC with the accepted GC. Deltas compare
absolute RC instructions with the original
`claude-rc-perf/.tmp-rc-quick/results-m14-dev.json`, copied without modification
into the evidence directory. Every row is present on both backends.

| Dev corpus | QBE | LLVM |
|---|---:|---:|
| m14 geomean | 1.074153 | 1.085282 |
| Stage 1 geomean | 1.065172 | 1.070388 |
| Rows at or below 1.3x | 43/43 | 43/43 |
| Worst ratio | 1.281561 | 1.256195 |
| Largest instruction regression | +0.3043% (`knucleotide`) | +0.1832% (`fannkuch_redux`) |

This branch includes the earlier pin elision, fresh-buffer classification,
exit skip, literal payload and text-index lanes. It predates rc-typeids.
The nbody and sort_quick improvements are the documented COW-PIN-ELIDE-1
benefits. `bytes_scan` constructs its buffer through `byte_buffer(list)`, so
VALUE-BUFFER-FRESH-1 lets existing unique-buffer loop proofs apply. The smaller
text-heavy gains (`scan_split` and LLVM `knucleotide`) are consistent with the
inherited ASCII constructor/publish/index work; this is an inference from the
changed paths, not an individually isolated profile. All other changes are
within 1%, with no acceptance-breaking regression. These measurements cover
the combined inherited batch and stage-1 ports.

Smoke measurements are differential correctness evidence. Short Lox programs
still show the documented RC-startup overhead: QBE geomean
1.105754, 38/43 rows at or below 1.3x (worst
1.520132); LLVM geomean
1.141967, 35/43 (worst
2.382314). The dev-row acceptance cap is met.

| Program | QBE m14 | QBE stage 1 | QBE delta | LLVM m14 | LLVM stage 1 | LLVM delta |
|---|---:|---:|---:|---:|---:|---:|
| parity/suite/binary_trees | 1.113250 | 1.111406 | -0.1659% | 1.175735 | 1.172326 | -0.2905% |
| parity/suite/fannkuch_redux | 1.044581 | 1.044580 | -0.0002% | 0.994782 | 0.996608 | +0.1832% |
| parity/suite/knucleotide | 1.110051 | 1.113432 | +0.3043% | 1.116120 | 1.097111 | -1.7036% |
| parity/suite/mandelbrot | 1.000017 | 1.000016 | -0.0003% | 1.000079 | 1.000074 | -0.0015% |
| parity/suite/matmul | 1.010305 | 1.010147 | -0.0159% | 1.130925 | 1.127554 | -0.3036% |
| parity/suite/nbody | 1.061232 | 1.015310 | -4.3273% | 1.254523 | 0.974984 | -22.2827% |
| parity/suite/raytrace | 1.057227 | 1.057227 | -0.0002% | 1.053388 | 1.053386 | -0.0009% |
| parity/suite/sieve | 1.024404 | 1.024398 | -0.0015% | 1.000281 | 1.000267 | -0.0051% |
| parity/suite/sort_builtin | 1.124009 | 1.124005 | -0.0012% | 1.054300 | 1.054296 | -0.0015% |
| parity/suite/sort_quick | 1.046213 | 0.863849 | -17.4311% | 1.277313 | 0.987276 | -22.7073% |
| parity/suite/sort_records | 1.281572 | 1.281561 | -0.0035% | 1.196861 | 1.196846 | -0.0065% |
| parity/suite/spectral_norm | 1.013902 | 1.013900 | -0.0003% | 1.000059 | 1.000049 | -0.0014% |
| parity/suite/text_ops | 1.111404 | 1.106174 | -0.4710% | 0.976446 | 0.972568 | -0.3977% |
| parity/lib/scan_count | 1.001087 | 1.001140 | +0.0046% | 1.000590 | 1.000638 | +0.0040% |
| parity/lib/scan_replace | 1.001518 | 1.001517 | -0.0013% | 1.000754 | 0.996390 | -0.4372% |
| parity/lib/scan_split | 0.708838 | 0.686518 | -3.1493% | 0.648986 | 0.631810 | -2.6471% |
| parity/micro/alloc_churn | 1.097091 | 1.093822 | -0.2982% | 1.124002 | 1.118874 | -0.4567% |
| parity/micro/bytes_scan | 1.078047 | 0.999940 | -7.2458% | 1.001615 | 1.001591 | -0.0066% |
| parity/micro/calls | 1.000037 | 1.000034 | -0.0007% | 1.000110 | 1.000106 | -0.0019% |
| parity/micro/dict_count | 1.127252 | 1.127036 | -0.0204% | 1.163332 | 1.153935 | -0.8096% |
| parity/micro/fib | 1.000039 | 1.000037 | -0.0008% | 1.000063 | 1.000061 | -0.0011% |
| parity/micro/float_loop | 1.079402 | 1.079399 | -0.0009% | 1.000355 | 1.000340 | -0.0064% |
| parity/micro/intloop | 1.000050 | 1.000047 | -0.0010% | 1.000092 | 1.000088 | -0.0016% |
| parity/micro/list_append_sum | 1.135104 | 1.135097 | -0.0019% | 1.195040 | 1.195034 | -0.0039% |
| parity/micro/list_records | 1.059080 | 1.059071 | -0.0024% | 1.096770 | 1.096749 | -0.0099% |
| parity/micro/records | 1.000033 | 1.000031 | -0.0006% | 1.000099 | 1.000095 | -0.0017% |
| parity/micro/str_build | 0.988218 | 0.988212 | -0.0014% | 1.124468 | 1.124453 | -0.0045% |
| schematic/fixture | 1.225464 | 1.222584 | -0.2896% | 1.187369 | 1.181796 | -0.5806% |
| schematic/changed-net | 1.225476 | 1.222515 | -0.2891% | 1.187298 | 1.181486 | -0.5826% |
| schematic/changed-value | 1.225481 | 1.222507 | -0.2899% | 1.187374 | 1.181609 | -0.5819% |
| lox/vm/binary_trees | 1.166998 | 1.166289 | -0.0613% | 1.170460 | 1.170450 | -0.0021% |
| lox/vm/closures | 1.160092 | 1.159730 | -0.0316% | 1.161679 | 1.161671 | -0.0016% |
| lox/vm/equality | 0.876162 | 0.876148 | -0.0019% | 0.972825 | 0.972812 | -0.0024% |
| lox/vm/fib | 1.087239 | 1.087228 | -0.0016% | 1.071167 | 1.071147 | -0.0035% |
| lox/vm/instantiation | 1.265358 | 1.263422 | -0.1535% | 1.203956 | 1.203939 | -0.0025% |
| lox/vm/invocation | 1.190478 | 1.190465 | -0.0013% | 1.166215 | 1.166210 | -0.0011% |
| lox/vm/method_call | 1.189007 | 1.188994 | -0.0013% | 1.256200 | 1.256195 | -0.0011% |
| lox/vm/properties | 1.184853 | 1.184830 | -0.0023% | 1.186132 | 1.186129 | -0.0010% |
| lox/vm/string_equality | 0.968485 | 0.968229 | -0.0261% | 1.251615 | 1.251744 | +0.0117% |
| lox/vm/strings | 1.002868 | 1.001660 | -0.1209% | 1.037892 | 1.036956 | -0.0912% |
| lox/vm/trees | 1.118978 | 1.118746 | -0.0210% | 1.086715 | 1.086711 | -0.0008% |
| lox/vm/zoo | 1.129912 | 1.129906 | -0.0008% | 1.109775 | 1.109769 | -0.0011% |
| lox/vm/zoo_batch | 1.132499 | 1.132489 | -0.0011% | 1.126094 | 1.126087 | -0.0013% |

## Handoff and limits

WP-A4 continuation is complete. The source implementation is unchanged from
`a48b62f5`; this continuation adds the audit and checked-in evidence only.
Merge the stage-1 branch through the integrator and reconcile the identical
NUM-LITERAL-4 hint patch once. The complete merged integration gate belongs
to WP-A5. This continuation used the requested dev comparison and added smoke
output checks; it did not repeat the frozen full-size acceptance protocol.

Raw logs remain in `.tmp/a4/`; checked-in summaries, full performance rows and
cold/warm fuzz findings are in
`docs/audits/evidence/codex-next-stage1-20260929/`. No action was refused and
no merge to `main` was performed. The parent integrator is coordinating the
required append-and-commit Guardian feedback entry to avoid sibling writes.
