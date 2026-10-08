# S2-D qualification

Base: `72eaae74`; accepted S2-I was incorporated at `0563edd6` before final
qualification. Implementation commit: `89f65316`. Every compiler check below
qualifies that source; this evidence follow-up changes no compiler source.
Frozen `ir.zig` is unchanged. No shared frontend, old-core source, language
fixture or external Lox checkout was edited.

The oracle is the accepted integration worktree's `zig-out/bin/mylang`, from
Wave A's current installation, with its adjacent `qbe`. Its earlier cached
baseline binary predates accepted language changes and was not used to grade
these results. The 20 baseline LLVM files were copied into this worktree's
private `.mylang-cache/wave-a/baseline` for code comparison. Frontend caches,
native outputs and fuzz temporary files belong to this locked worktree.
Build admission excludes CPUs 2, 3, 10 and 11. CPU-10 measurements hold
`/run/user/1000/mylang-s2-cpu10.lock`.

S2-T1's published `myl_core_span_hash` and `myl_core_str_hash` implementations
are copied unchanged into the foundational `core_text.c` for standalone D
qualification. The coordinator approved this dependency; T1's final complete
text implementation replaces that file when the two packages are integrated.
The ABI is the published 32-byte header, hash flag 512, cached hash in the low
32 bits of metadata, bytes kind 3 and dictionary kind 4. Saturated constants
are never modified. No old runtime implements the new dictionary.

In commands below, `E=experiments/new-core-s2-20261005/wave-b/s2-d`,
`C=.mylang-cache/wave-b/s2-d`, and `ORACLE` is the absolute accepted integration
binary. Every compiling command runs through the build-slot wrapper.

| Check | Command | Result / evidence |
|---|---|---|
| Rebuild | `scripts/build-slot.sh build -- zig build core --summary all` | `rebuild-alias.txt`; 2.75 s; compiler 2 s, MaxRSS 322 M |
| Core gate | `scripts/build-slot.sh gate -- bash -c '"$@"; result=$?; exit "$result"' -- scripts/build-slot.sh build -- /usr/bin/time -f 'elapsed=%e rss_kib=%M' zig build test-core --summary all` | `test-core.txt`; 192/192; 168.20 s; test RSS 137 M, compile RSS 328 M |
| Full comparison | `scripts/build-slot.sh build -- python3 experiments/new-core-s1-20261005/conformance.py --set all --jobs 4 --why --mylang "$ORACLE" --cache-dir "$C/conformance-final"` | `conformance-final.txt`; 919 matching, 0 mismatches, 621 precise refusals / 1540 tests in each mode |
| Own leak + verify | same runner with the 37 dict/set files of design §6, `operand_snapshots test/core/d_collections.my test/core/d_view_identity.my --jobs 4 --why --leakcheck --verify` | `own-final.txt`; 220 matching, 0 mismatches, 121 precise refusals / 341 tests in each mode; no leak/fact failures |
| Own fuzz | `scripts/build-slot.sh build -- python3 experiments/new-core-s2-20261005/wave-a/integration/fuzz_qualification.py --kind dict --cases 50 --seed 202610052 --mylang "$ORACLE" --core zig-out/bin/mylang-core --evidence "$E/fuzz-final" --cache-root "$C/fuzz-identity"` | `fuzz-final.txt`, `fuzz-final/summary.json`; 50 accepted, 750/750 comparisons, no mismatches, refusals, leaks, fact failures or crashes; 390.30 s |
| Earlier code | `scripts/build-slot.sh build -- python3 experiments/new-core-s2-20261005/wave-a/compare_code.py --stage s2-d` | `code.txt`; all 20 S0/S1 function definitions identical |
| Coverage | `scripts/build-slot.sh build -- python3 experiments/new-core-s2-20261005/wave-a/qualify_coverage.py --evidence "$C/coverage"` | `coverage.txt`; 2620/3627 functions accepted (72%); checked four child exits and complete reports |
| Own rows | `scripts/build-slot.sh build -- flock /run/user/1000/mylang-s2-cpu10.lock python3 "$E/measure_dict.py" --rows dict_lookup,dict_lookup_str,dict_update,dict_update_str,set_dedup --build --bin "$C/rows-final" --rounds 7 --cpu 10 --mylang "$ORACLE"` | `rows-final.txt`; all five rows build, match checksums and pass both sizes |
| Rows after identity repair | `scripts/build-slot.sh build -- python3 "$E/row_code_identity.py"` | `row-code-identity.txt`; all five rebuilt row binaries have identical `.text`, so the passing measurements remain valid |
| Identity fixture oracle | `scripts/build-slot.sh build -- "$ORACLE" test test/core/d_view_identity.my --json --cache-dir "$C/identity-oracle"` | `identity-oracle.json`; all nine tests pass on the accepted old core |
| Real probe layout | `scripts/build-slot.sh build -- flock /run/user/1000/mylang-s2-cpu10.lock python3 "$E/layout_real.py" 3` | `layout-real.txt`; all dense, sparse, miss, churn and word-count controls match; hybrid retained, numbers in design §18 |
| Guardian | `guardian-check all . --full` and normal commit hook | `guardian-final.txt`; all 88 checks pass |

Own row costs are user cycles per element, medians of seven interleaved rounds
on CPU 10. Each cell lists new core / accepted old core / Zig ReleaseSafe;
Rust timings and all matching checksums are retained in the complete log.

| Row | 4096 | 64 |
|---|---:|---:|
| dict_lookup | 15.677 / 31.031 / 52.256 | 15.210 / 16.942 / 31.061 |
| dict_lookup_str | 22.620 / 61.557 / 62.553 | 19.885 / 28.917 / 31.866 |
| dict_update | 199.720 / 829.381 / 550.250 | 202.974 / 733.449 / 312.223 |
| dict_update_str | 284.508 / 1015.588 / 731.157 | 263.692 / 854.181 / 405.386 |
| set_dedup | 24.520 / 175.304 / 81.144 | 29.895 / 168.472 / 37.615 |

The layout control links the production C runtime and the verbatim emitted LLVM
first-group probe into the reference workload with LTO. The C control still
shows dense-update and tiny-word costs, while the five language rows all pass
the required Zig gate. Literal/comprehension capacity hints and scalar rebuilds
are present. No hash tuning or dense-integer specialization was added; counted
fill-loop capacity inference and the CPython fallback were not needed to pass
the dense row gate. Complete control measurements, including size 64 and
candidate table shapes, are recorded in `layout-real.txt` and design §18.

Persistent view identity has a precise support boundary. Fresh unshared local
root views, direct temporary views and explicit `list(view)` snapshots match
the oracle. Interior, escaping, list/dictionary/aggregate-stored, mut-argument,
explicitly rebound and ordinary-snapshot-combined persistent views are refused.
Unproved origins and opaque captures are also refused. An identity analysis
after SSA construction follows source ancestors, copy/phi aliases, marked view
wrappers and mapping projections; it checks exposures before and after binding.
The nine new identity fixtures all pass on the accepted old core and receive
precise new-core refusals, including
record, tuple copy, union, list, nested dict, returned capture and unknown producer
cases. The fixed-array case is initially blocked by the package's array type;
its storage instruction is covered by the same alias analysis after F integrates.
`identity-focused.txt` and the complete own sweep have zero mismatches in both
leak/verify modes. Frozen IR cannot express every old-core held edge; source-place
refresh must not replace child identity.

The final audit reproduced an aggregate alias hole (`view-aggregate.txt`):
`holder = Holder(d); view = d.values(); d[1] = 9` printed `7 9 7` on the oracle
and `9 9 7` on the then-candidate core. The identity analysis now refuses that
case. Full comparison, own leak/verify, D50, code identity and the held gate were
rerun on the repaired compiler source. The runtime and emitter were unchanged;
five identical row machine-code sections prove the measured hot paths unchanged.

The first full comparison found an explained `VALUE-SEMANTICS-14` receiver
snapshot bug: `d.get(key, side_effect())` captured its dictionary after the
default expression. The receiver is now captured before evaluating arguments;
the focused 55-test operand sweep has 45 matches, 0 mismatches and 10 refusals
with leak and verification enabled (`operand-fixed.txt`).

The first fuzz attempt was rejected by the old checker because a generated
iteration binding shadowed a local name. Renaming those bindings repaired the
generator (`fuzz-generator-failure.txt`). The first core gate used the S2-0
undefined dictionary placeholders and still expected runtime unsupported
errors, plus a builder fixture that refused dictionaries. The foundational
tests now allocate and populate valid tables and check each operation's result;
the generic refusal fixture uses an interior live view. The retained
`test-core-fixture-failure.txt` explains this test-only repair.
A second stale format assertion still expected an undefined dictionary operand;
`test-core-format-failure.txt` explains its change to a valid SSA operand.

Gate admission waiting is outside the measured command time. The outer shell
stays alive to hold the gate descriptor while the inner wrapper holds its
build descriptor. The reusable fuzz wrapper checks child status, stdout and
stderr, rejects crashes, leaks and fact failures, and requires all 50 cases
and 750 comparisons. D and F use the two qualification slots by coordinator
admission. Full old-core gates, the 200-case matrix and all 35 rows are reserved
for S2-X under the Wave B pace rules.
