# Exact empty dictionary cleanup checks

The unchanged two-million-update `dict_count` workload removes five proved-false
cleanup guards per iteration. Median retired instructions fall 5.04% on QBE
and 4.57% on LLVM O3/full LTO. Every ownership counter and output is unchanged.
This row still exceeds the Stage4 per-program limit; this is no corpus, RSS or
default-transition acceptance claim.

| Backend | Accepted GC | Joined before | Candidate | After / before | After / GC |
| --- | ---: | ---: | ---: | ---: | ---: |
| QBE | 661,305,008 | 913,581,120 | 867,572,589 | 0.949639359 | 1.311909903 |
| LLVM O3/full LTO | 441,034,621 | 612,392,336 | 584,393,308 | 0.954279265 | 1.325050869 |

Reaching 1.3 still requires approximately 7,876,079 QBE instructions (0.9078%
of current RC work) and 11,048,301 LLVM instructions (1.8906%). Measurements use
CPU11, unchanged source/accepted-GC binaries, three interleaved production runs
per side/backend, and separate counted executables. All18 quantitative perf
observations have exactly one active instruction event at100.00% running.
There is no sampled-profile attribution in this result.

All four before/after counted executions report O acquire/release2,001/4,030,
H2,001 balanced pairs,2,029 allocations/retirements,1,001 uniqueness checks,
zero clones/arena allocations/limits and no saturation. The source stdout is
identical across all22 full-size executions. The runtime/descriptor/cache
implementation remains the ordinary-find path from `0efd82ad`; its rejected
repeat-cache experiment and receipts remain intact.

## Source and exact proof boundary

The working branch starts with explicit two-parent merge
`0f5e4d0f9b68bfb21b18cf1f0a0c286d5fbe2411` of `0efd82ad` and joined `c07016f3`.
The matched before is c070 Debug compiler SHA256
`db9d8791fb56a9c07e5db529b5abe54b2689966364095de89e2abcaca4409b2b`, installed
in integration's `.tmp-rc/install-helpers-word/bin/mylang`. The candidate Debug
compiler is immutable at this tree's `.tmp-rc/install-dict-empty-final/bin/mylang`,
SHA256 `c5728347215d670d510ecbe198986d4373f4da5bfd31f9b414f603a638f5f10d`.
Full absolute paths, source hashes, manifests and binaries are in the archive.

The [reviewed design](d9-rc-dictionary-empty-drops-design-2026-09-27.md) reuses
successful late dictionary-loop and anchored-key proofs. An additional optional
check identifies the canonical empty-dictionary constructor/store, whose actual
ordinary successful transfer clears operand0 before local publication. It
checks every operand type through the complete store-to-backedge corridor.
Only the previously certified raw list/key/dictionary inputs can carry managed
bits; all other inputs are counted-edge-free and nonunique. This includes the
preheader corridor, not only the loop body. Existing whole-local proofs cover
the captured list and dictionary receiver across all definitions/backedges.

The finalized tail already refuses type-wide mayHold/iteration dictionary roots;
its successful late lifetime scan checks the reset store's interception and
release hooks. These facts are reused without repeating their larger scans.
The shared262,144 allowance now charges each additional PC and actual stack
element before inspecting it, plus borrowed-store metadata rows. It is a
candidate/metadata/stack-row allowance, not a primitive-operation bound on shape
resolution or inherited analyses. Code<=4096 and loop<=1024 remain. Shape OOM
propagates; other unsupported shape results refuse the optional annotation.

Only exact five `(PC, logical journal)` consumers are suppressed. Setup and
later uses keep their original behavior. `frame.initialized(true)` rejects an
unexpected certified publication; `frame.guard` rejects a runtime operand-guard
address within the closed corridor. These checks enforce completed preflight
invariants, rather than replacing conservative admission with runtime failure.
No state/layout/ABI change or loop-version eligibility expansion is involved.
All journals, guards, linked frame, ordinary uniqueness, native GET/WRITE,
status handling, growth, finalizer/drain and region checks remain.

## Emission and validation

Exact full benchmark IL has23→18 slot-drop calls and exactly five certificate
markers. Both static uniqueness calls remain. The416-byte entries and104-byte
guards remain, as do real setup cleanup and later list iterator H acquisition
and cleanup. QBE guest native drop sites are21→16. LLVM LTO folds the guest into
`entry_run`; its sites are23→18. Archived native code confirms both changes.
The preliminary false-branch static estimate was30M/20M instructions; measured
savings are46,008,531/27,999,028. Additional scheduling/register effects are not
separately attributed and are not presented as a new semantic optimization.

- Focused dictionary units:25/25, including exact benchmark structure, source
  ownership/ref/callback/entry refusals and actual frame publication/guard
  address rejection before any instructions are emitted.
- Actual QBE and LLVM:64 guest assertions total, including inherited arenas,
  empty loops, live snapshots, callback/rebind fallbacks, view-backed strings,
  growth, real iterators and later owning publications. GC stress was run only
  on the seven established loop controls per backend; the previously known
  broad GC-stress timeout was not repeated.
- Forty paired Debug controls preserve exact status/stdout/non-counter trace
  and counter dictionaries: step50/100, bounds, overflow, zero-iteration
  low-budget refusal/success, heap growth refusal/success, inherited-arena
  growth. All ownership/hold/retirement totals balance.
- Four public embedding runs cover actual queued-finalizer guest reentry on
  both backends and both compilers: phase2 observes old bytes once, returns10,
  and reports no bad observation. The removed guard paths never released or
  drained, including under an active outer drain.
- Whole-tree Guardian88, focused source formatting and `git diff --check` pass.
  Initial test-fixture compile errors and Guardian findings (duplicate primary
  spec tag and repeated import literal) were corrected without gate exceptions;
  their logs remain archived. Two invalid Guardian invocation attempts also
  remain identifiable in the logs and were not counted as successful gates.

## Reproduction and evidence

Run the read-only archive verifier:

```sh
python3 experiments/d9-rc-dictionary-empty-drops-20260927/verify.py --live
```

The archive contains every raw perf string, all manifests/counter runs, both
emitted bodies/native disassemblies, before/after compiler identities, unchanged
workload/expected output, drivers, control sources, production source snapshots
and logs. Drivers use the normal build-slot wrapper and private caches/TMPDIR;
all compiler binaries were built Debug. The native benchmark modes remain
ReleaseFast QBE and actual LLVM O3/full LTO. Timings, builds and control processes
are terminal; CPU11 was released to the parent before archive preparation.
