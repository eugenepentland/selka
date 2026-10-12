# A01 common Support7 qualification

All requested A01 lanes passed on the common installed compiler built from
`bed11cf3bf3102ffec44487e431a1573fdf02ad5`, SHA256
`540283317dab8009ba38f7bc13a521b1b5048cff99701498acd56da7902259ef`.
This is A01 qualification of Support7, not a declaration that the complete release
passed every team's gate, changed its default, or retired legacy RC.

| Lane | Fresh result |
| --- | --- |
| Counted source matrix | 30 builds, 90 executions, eight required refusal controls; all pass. |
| Source ThreadSanitizer | Four builds, 12 executions at 1/2/8 workers; all pass, no TSan reports. |
| Owned native scheduler | Two builds, 12 executions including TSan at 8 workers; all pass. |
| Temporary ordinary RC tuple control | Passes with exact output, input independence and live0; records 2 retains / 6 releases, excluded from zero-RC results. |

The counted source matrix covers release, unoptimized debug, verified release,
optimized debug and release without facts. Its six frozen cases are the combined
managed/nested/discarded map application, Result lists, direct Result-returning map,
complete tuple/provider/Result unpack, copy-generic tuple extraction, and deliberate
item17 traps. Every case runs at 1/2/8 workers. The combined map includes 0/1/many
inputs, uneven ranges, cheap/expensive callbacks, managed records/unions, nested
maps and discarded output. The full tuple oracle includes the independently read
provider checksum 56 and retained pending-Result obligations.

All 75 successful counted executions have zero emitted/runtime RC events and zero
managed bytes live at exit. The 15 deliberately trapping executions are diagnostic
checks, not leak-free successful runs. LLVM/symbol audits pass for all source builds.
Eight exact refusal controls include pending Result-list abandonment and seven tuple
borrow/move/handling/overwrite cases. All failures remain in the denominators;
there were none in this run.

The source TSan lane runs combined map, Result list, direct Result map and item17
trap at 1/2/8 workers. Both generated LLVM and C runtime are instrumented through
the supported compiler path. Native scheduler stress separately uses the exact
counted/uncounted C runtime text emitted by this same common compiler into its
private runtime cache, with the frozen `a01_owned_scheduler_fixture.c` C-thunk
bridge. It does not rebuild a private compiler or substitute a runtime draft.

The scheduler executes 1,010,002 counted increment callbacks per stress run, plus
a nested binary tree of depth 12 and a chain of depth 2048. Counted stress, lazy
startup and take-twice refusal pass at 1/2/8 workers; the same three checks pass
under TSan at 8 workers. Successful counted stress/lazy runs have RC0/live0 and
linked-symbol audits pass. The source map lane covers the generated fastcc bridge;
the native fixture is explicitly a C-bridge scheduler test.

The ordinary-mode control is temporary compatibility evidence while both modes
exist. Repeated borrowed tuple destructuring and local list mutation leave the
caller's tuple unchanged, with `ordinary-borrow 2` output. Its observed RC proves
that this run must not be relabeled as default promotion or legacy retirement.

## Reproduction and identities

`inputs.json` pins the frozen source/harness hashes. `installation.json` copies
the coordinator's common installation identity, including actual owned libexec
component manifests and their source pin. `summary.json` records lane totals;
`release-managed-metrics.json` records fresh whole-program managed allocation,
reallocation, cumulative-byte, peak-live and exit-live observations. These counters
are not RSS or uninstrumented runtime, and this report makes no paired saving or
speedup claim. A09 owns those measurements.

The counted/TSan commands used frozen source `experiments/memory-closeout-20261012/A01/qualify.py`
from `bed11`, with the compiler path in `inputs.json`, explicit `--source-revision`,
private `--output`, and:

```text
--cases combined result_list result_direct tuple_unpack tuple_generic trap
--modes release debug verify optimized_debug no_facts

--cases combined result_list result_direct trap --modes tsan
```

The harness owns its shared build admission. Do not wrap it in another admission
lease. `scheduler.py` and `ordinary_control.py` use one external build-slot lease;
their exact native/compiler commands are in their raw result JSON. The private
`MYLANG_CORE_RUNTIME_CACHE` is recorded in `inputs.json`; it is not a private
admission directory. Queue waits are preserved with admission tickets 976/995/1007/1012 and are preserved in
logs, never counted as runtime or compiler measurements.

`raw/` preserves compressed results, counters, build/run output, symbol listings
and both exact emitted runtime source texts. `sources/` freezes the executed source
and negative fixtures. `frozen-qualify.py` and `frozen-audit.py` preserve the exact
bed11 scripts for inspection; run the original paths in the frozen checkout because
their repository-relative imports depend on that location. `sha256.json` hashes
archived inputs and evidence. Compiler identity was rechecked after all lanes.

No production code changed during qualification. C2/C3 must rerun affected paths
with ordinary commands and the exact then-final artifact; prepared retirement
patches remain unapplied.
