# S2-F: functions, fixed arrays and stable sort

Qualified source commit: **`3465f4236f3661d70af469ed0ceb865c6aca0e09`**,
on `codex/new-core-s2-functions`, cut from accepted integration `72eaae74`.
Every final result below qualifies that source commit. The following evidence
commit contains this README and the retained logs. No integration or main merge
was performed by this lane.

The implementation uses the frozen S2-0 IR, direct ABI copy-in/copy-out for
callbacks with a u64 owned-argument mask, constant-target folding and existing
loop unswitching, aggregate fixed-array updates, and an independent stable
powersort/keyed-sort runtime. Keyed sort passes exact source/key strides and
gathers into an owning source copy, preserving source snapshots and managed
child counts. The as-built contract is design note §17 and NEW-CORE-SORT-1.

## Commands and final results

Commands run from the locked F worktree. Shared build/gate admission waiting is
excluded from the measured command times. Compiler/runtime caches are private
to this worktree; the global Zig cache is the machine's accepted shared cache.

```sh
export ZIG_GLOBAL_CACHE_DIR=/home/epentland/ai/canopy/.zig-global-cache
export TMPDIR="$PWD/.mylang-cache/s2-f/tmp"
F_EVIDENCE=experiments/new-core-s2-20261005/wave-b/s2-f
F_ORACLE=/home/epentland/ai/canopy/mylang-worktrees/codex-new-core-s2-integration/zig-out/bin/mylang
F_CORE="$PWD/zig-out/bin/mylang-core"
```

The old oracle is the installed compiler at accepted source `72eaae74`, with
adjacent QBE. The Wave A baseline compiler predates the accepted language
changes and was not used as the final oracle. The private Wave A `.ll` baselines
remain the correct code-identity reference.

| Check | Final result at source `3465f423` | Evidence |
|---|---|---|
| Core rebuild | 3/3 steps; 2.41 s, compile 1 s, MaxRSS 321M | [build-gather.log](build-gather.log) |
| Held lane gate | 5/5 steps, 189/189 tests; 294.04 s; test MaxRSS 189M, compile MaxRSS 324M | [test-core-qualified.log](test-core-qualified.log) |
| Guardian whole tree | 88 checks pass | [guardian-qualified.log](guardian-qualified.log) |
| Full conformance | Debug and release each 919 matching, 0 mismatching, 621 unsupported / 1540 | [conformance-final.log](conformance-final.log) |
| Owned leak and facts sweep | Debug and release each 294 matching, 0 mismatching, 75 unsupported / 369 | [own-leak-verify-final.log](own-leak-verify-final.log) |
| F ownership fixtures | All 5 match in both modes with leak checking and fact verification | [own-leak-verify-final.log](own-leak-verify-final.log) |
| Feature fuzz | 50/50 accepted, 750/750 comparisons, 1000 native runs; all error counters zero; complete and qualified; 181.74 s | [fuzz/summary.json](fuzz/summary.json), [fuzz.log](fuzz.log) |
| S0/S1 code identity | All 20 definitions identical | [code-identity.log](code-identity.log) |
| Checked coverage | Four children exit 0; qualified; 2557/3627 functions accepted (70%); 2964 checks proven, 2653 still exact in 2452 accepted functions | [coverage-checked.log](coverage-checked.log), [coverage-checked/summary.json](coverage-checked/summary.json) |

The lane gate's 250 s admission wait is separate from its 294.04 s execution.
The gate remained held during execution: a parent shell retains descriptor 9
while the nested build wrapper opens its own lock. The five-minute and 2.5G
unit-shard limits pass. The expected missing-source diagnostics in the green
gate log belong to negative unit fixtures; the Build Summary is authoritative.

```sh
scripts/build-slot.sh build -- /usr/bin/time -f 'command_seconds=%e' \
  zig build core --summary all

scripts/build-slot.sh gate -- bash -c '"$@"; result=$?; exit "$result"' -- \
  scripts/build-slot.sh build -- /usr/bin/time -f 'command_seconds=%e' \
  zig build test-core --summary all

scripts/build-slot.sh gate -- \
  /home/epentland/ai/canopy/guardian-zig/zig-out/bin/guardian-check all . --gate

scripts/build-slot.sh build -- python3 \
  experiments/new-core-s1-20261005/conformance.py \
  --set all --jobs 4 --why --mylang "$F_ORACLE"
```

The owned sweep includes the function/sort/array and relevant ownership files
from the design's S2 matrix, plus the lane's heap-managed fixtures. It verifies
successful status and stdout as well as stderr. Remaining unsupported functions
are reported with their precise reasons in the complete logs.

```sh
scripts/build-slot.sh build -- python3 \
  experiments/new-core-s1-20261005/conformance.py \
  callback_slots callbacks keyed_sorting lambda_sort_keys sorted_keys \
  option_niche rc_borrowed_calls rc_borrowed_loops rc_borrowed_readonly_entries \
  rc_call_lifetimes rc_collection_builtins migrated/structural_constraints \
  aggregate_refs array_negative_index array_places array_writes \
  backlog/const_lengths___one_helper_serves_distinct_nominal_element_t \
  backlog/const_lengths___const_length_function_parameters_specialize \
  dictionary_range_keys expected_type_inference loop_rebinding \
  migrated/generic_arrays migrated/surface_statements mut_argument_places \
  mut_reference_roots nominal_bodies nominal_instances number_literals \
  python_arrays rc_aggregate_values rc_glue_values rc_match_scalars \
  rc_plain_aggregates rc_plain_retains rc_read_loans rc_readonly_managed_calls \
  rc_scalar_replacements value_equality migrated/generic_inference \
  operand_snapshots rc_fresh_loop_roots rc_temporary_lifetimes scalable_sorting \
  generator_arguments test/core/f_features.my \
  --jobs 3 --why --leakcheck --verify --mylang "$F_ORACLE"
```

The generator [fuzz_functions.py](fuzz_functions.py) retains the S1 harness CLI
and exercises callback selection/passing/return, fixed-array live reads and
negative writes, direct managed-array mut calls, legal mut-list callbacks,
managed keyed stable/reverse sort with source copies, tuple/text keys and
plain sort. The qualification wrapper preserves the expected 15 comparisons
per case, native exit/status checks, leak checking and fact checks. This run
was admitted as the second of at most two concurrent qualification jobs.

```sh
scripts/build-slot.sh build -- python3 \
  /home/epentland/ai/canopy/mylang-worktrees/codex-new-core-s2-live-iteration/experiments/new-core-s2-20261005/wave-a/integration/fuzz_qualification.py \
  --kind s1 --harness "$PWD/$F_EVIDENCE/fuzz_functions.py" \
  --mylang "$F_ORACLE" --core "$F_CORE" --cases 50 --seed 202610055 \
  --evidence "$PWD/$F_EVIDENCE/fuzz" \
  --cache-root "$PWD/.mylang-cache/s2-f/fuzz"

scripts/build-slot.sh build -- python3 \
  experiments/new-core-s2-20261005/wave-a/compare_code.py --stage s2-f-final

scripts/build-slot.sh build -- python3 \
  experiments/new-core-s2-20261005/wave-a/qualify_coverage.py \
  --evidence "$F_EVIDENCE/coverage-checked"
```

Coverage by corpus is 178/207 examples, 75/123 parity, 2250/3156 language and
54/141 runtime functions. All per-function outcomes and all refusal occurrences
are retained in the checked children and summary. The earlier coverage.log is
superseded by the checked wrapper, which verifies child status and completeness.
The Wave A report counted 2321/3619 accepted functions; newly reachable bodies
change the denominator. These are coverage counts on their respective heads.

## Owned rows

Each value is user cycles per element, median of seven interleaved rounds on
CPU 10, with one-iteration startup subtracted. Every configuration's checksum
matches at both sizes. Each new-core value is below 1.10× Zig ReleaseSafe.

| Row | Size | Old release | New release | Rust | Zig ReleaseSafe | New / Zig |
|---|---:|---:|---:|---:|---:|---:|
| call_indirect | 4096 | 5.020 | 0.301 | 7.204 | 9.015 | 0.0334 |
| call_indirect | 64 | 5.094 | 0.313 | 7.690 | 9.507 | 0.0329 |
| sort_int | 4096 | 45.508 | 46.803 | 69.993 | 67.530 | 0.6931 |
| sort_int | 64 | 11.758 | 9.660 | 15.419 | 17.651 | 0.5473 |
| sort_records | 4096 | 54.488 | 31.086 | 41.029 | 117.620 | 0.2643 |
| sort_records | 64 | 66.591 | 39.806 | 45.204 | 51.026 | 0.7801 |

The runner extension [measure.py](measure.py) uses the accepted S1 timing and
checksum code unchanged. Its mappings are `call_indirect: compute, element,
4000/250000 iterations` and `sort_int`, `sort_records: collections, element,
400/25000 iterations` at sizes 4096/64. New guests preserve the original runner
formula and update counts inside their loops.

```sh
scripts/build-slot.sh build -- flock /run/user/1000/mylang-s2-cpu10.lock \
  python3 "$F_EVIDENCE/measure.py" \
  --build --rows call_indirect,sort_int,sort_records \
  --bin "$PWD/.mylang-cache/s2-f/rows" \
  --mylang "$F_ORACLE" --core "$F_CORE" \
  --runner /home/epentland/ai/canopy/mylang-worktrees/runtime-baseline-20261003/.mylang-cache/runtime-expanded/runner/bin \
  --rounds 7 --cpu 10
```

The timed run held `/run/user/1000/mylang-s2-cpu10.lock`; its perf children use
`taskset -c 10`. The initial results are [rows.log](rows.log). The size-64
record row initially missed the gate (1.223×), triggering the documented
profile and sorted-copy repair. Only that changed row was rebuilt and remeasured:

```sh
scripts/build-slot.sh build -- "$F_CORE" build \
  test/core/row_sort_records.my --release \
  --link benchmarks/runtime/ports/native_clock.c \
  --cache-dir "$PWD/.mylang-cache/s2-f/rows-gather-cache" \
  -o "$PWD/.mylang-cache/s2-f/rows/row_sort_records_new"

flock /run/user/1000/mylang-s2-cpu10.lock python3 "$F_EVIDENCE/measure.py" \
  --rows sort_records --bin "$PWD/.mylang-cache/s2-f/rows" \
  --mylang "$F_ORACLE" --core "$F_CORE" \
  --runner /home/epentland/ai/canopy/mylang-worktrees/runtime-baseline-20261003/.mylang-cache/runtime-expanded/runner/bin \
  --rounds 7 --cpu 10
```

[row-sort-records-gather.log](row-sort-records-gather.log) is the final record
row. [row-sort-records-profile.log](row-sort-records-profile.log) records the
611-sample profile explaining the repair. The 20 identical S0/S1 definitions
satisfy the accepted preservation rule; those unchanged rows were not remeasured.

## Repairs and scope

[REPAIRS.md](REPAIRS.md) records the exact causes and validations of the
implementation failures, the coordinator's stop/resume decisions, obsolete
hand-built fixtures, and the performance repair. Failed logs are retained
where they explain these changes. Final sweeps were repeated after the runtime
repair and heap-managed fixture strengthening; no passing gate was rerun on
unchanged source.

The source scope is `src/core/`, `test/core/`, its reproducible experiment
drivers, and required SPEC/design documentation. The coordinator confirmed
that the core-only Wave B exit applies: the old-core gate, 200-case matrix and
35-row table belong to S2-X. No shared frontend, old core, IR, ownership pass,
persisted format, `tests/lang/`, or external Lox checkout was changed. Guardian
feedback was sent to the coordinator for the required shared log commit.

Both source and evidence commits use `scripts/build-slot.sh gate -- git commit`;
the pre-commit Guardian gate passes. No unresolved F mismatch or requested
language change remains. Integration owns the semantic reconciliation with
the dictionary/text dispatch and live-iteration paths.
