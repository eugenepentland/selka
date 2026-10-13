# P5 remaining EDA copies

Source and qualification commit: `f5c2be1ee18a1cf6a8c58101d6b7364709b4ea3d`. Normal Guardian passed all 88 checks.
Base: `2525a66f61838086f5327d74db7412926ce4a221`.
`commit-receipt.json` records commit/source/test/log digests; raw gate output is
in `guardian-source-commit.log`.

The candidate caches the target pin side and edge coordinate in `edge_spacing`
and reads candidate pins without copying their pad/name text. Empty units still
return `None`; duplicate edge positions and pins on other sides are still
ignored. A focused regression covers empty units, duplicate coordinates,
negative top-edge coordinates, and the separate bottom edge.

`route_parts` receives scoped borrowed obstacle arrays. Existing `route(Field)`
delegates to it, preserving the existing route candidate sequence, legality
checks, crossing/tee/overlap/body policy, and owned successful `Path` result.
`join_sites` uses this entry point without constructing an owned obstacle
snapshot and appends segments directly into their owner. The successful path
still enters retained storage through its existing explicit copy. `add_wire`
also appends segments directly.
`pad_of` reads integer shape/unit selectors without copying the parent Part;
the returned pad bytes remain an independent owner.

Dense text overlap remains unchanged, including strict ten-unit boundaries,
stable ties, first-pair selection, and report order. No compiler/runtime change,
arena, RC fallback, escaped borrowed view, historical evidence edit, peer merge,
push, or Guardian feedback entry is involved.

`identity.json` verifies the exact compiler and baseline executable against the
historical EDA build receipt. `source-manifest.json` pins the first copy-phase EDA module
bytes. `baseline-copy-calls.json` records direct static copy calls from the
pinned baseline LLVM, with its digest. It is not CPU attribution or timing.

Verified checked-release emit (8/8), wire (6/6), and corrected compose (2/2)
tests passed through shared build admission, with failed/skipped/unsupported
all zero. Exact commands use the pinned compiler,
`--release --verify-facts --experimental-zero-rc`, and private P5 caches.
Their raw output is in `emit-tests.log`, `compose-tests.log`, `wire-tests.log`.

The initial compose build rejected attempted `self.paths.append(path)` at
`kicad_sch_compose.my:578` with `E_SINGLE_OWNER_BORROW`: the narrowed optional
path is borrowed. The final source retains `path.copy()` and the failed raw log
is preserved as `compose-tests-path-borrow-rejected.log`. There is no compiler
workaround. The compose rerun enables `MYL_CORE_LEAKCHECK=1` and passed.
`test-commands.json` and `test-receipt.json` retain exact commands, statuses,
raw-log digests, source-manifest digest, and compiler identity.

The bounded CPU profile is diagnostic only. `profile.py` uses two existing full
inputs, twelve repetitions per cell, `cycles:u` at 499 Hz, and DWARF call stacks.
Each perf invocation is bounded at 23 seconds and each guest at three seconds.
The coordinator initially authorized an outer lease of at most 60 seconds after
P2 and pending builds. P2 cancelled its queued request before any profile ran;
the coordinator then consolidated baseline profiling. P5 never queued a timing
request during that first window and its runner did not run. Command JSON files pin input argv
and redirect output into this worker's private temporary tree.

The coordinator later authorized a CPU-8 lease after P2 timing ticket 937.
P5 queued ticket 938, then cancelled only its still-waiting wrapper PID 1249455
at the coordinator's request (exit 143). The external gate remained untouched;
no perf process or workload ran. `profile-cancellation.json` hashes the preserved
`profile-admission-cancelled938.log`; `profile-availability-cancelled938.json`
records installed perf and paranoid level 1, without asserting event access.
The prepared runner records admitted affinity and its own hash, and kills its
own perf process group on its 23-second timeout. It will only be enqueued again
after the coordinator confirms gate locks are free.

## Admitted CPU diagnostic and selected verification follow-up

After the coordinator confirmed free gates, timing ticket 942 admitted the
prepared CPU-8 probe after P2 ticket 941. User-only cycle recording succeeded
for all twelve RDS3 flat invocations: 679 native-comm samples, zero lost samples.
Installed perf event access is available at paranoid level 1. The initial report
decode hit its five-second timeout, so the driver exited 1 before recording
Cyclops. This is a partial diagnostic, not a completed two-cell profile or a
runtime comparison. Offline report decoding succeeded through ordinary build
admission with `DEBUGINFOD_URLS=''` and a private perf build-ID directory.

Self samples: block allocation 14.32%, boxed-value copy 9.63%, owned drop 9.07%,
owned-child access 9.00%, parser `parse_node` 5.48%, parser `next_token` 5.17%,
wire `join_sites` 4.95%, verification `check` 4.78%, and `grid_scan` 1.99%.
Caller chains were not reconstructable (Children equals Self); shared runtime
helper costs cannot be assigned precisely to verification or parsing. Parser
modules remain P3-owned. Static inspection also showed grid/pin foreach loops
already borrowed values, so no indexed-loop rewrite was made.

`profile-result.json` retains statuses, sample counts, actual CPU affinity,
executed-driver/input/binary/log hashes, and exact decode commands. The original
report timeout and cancelled 938 attempt remain preserved. Committed raw samples
are `rds3+flat.perf.data.gz`; decompression is byte-identical to the raw digest.
The uncompressed file remains in private `.tmp/lox-eda-parity/P5/profile942`.

The coordinator reserved `kicad_sch_verify.my` and its test module for the next
narrow source change. `grid_form_kind` selects a scalar class through one scoped
head match, replacing repeated form-head queries. Graphics retain their recursive
exemption, only atom heads classify forms, and traversal/error order is unchanged.
`check` reads the selected library-ID bytes without an extra snapshot. Label
and rail Multiset updates mutate their owned fields directly. Those two source
snapshots were already compiler-elided: they produce no observed traffic saving.
Owned text/accessor return contracts remain unchanged.

All ten verification tests passed checked, verified release with leak checking;
new cases cover duplicate label/rail multiplicities, grid errors before UUID
errors, quoted heads, and empty lists. `verify-test-receipt.json` pins commands,
raw log and `verify-source-manifest.json` for this follow-up.

### Same-code bounded counters

`verify_probe.py` snapshots immutable baseline and candidate sources. Baseline
verification is from `5a8bc86c67287a92219e28ea4287af80a86d8cc4`; only
`kicad_sch_verify.my` differs between the successful v2 module manifests.
Both execute the same ten correctness fixtures plus 16/64 unique net labels.
Those minimal labels omit font effects, so the correct textbox report is 0/0.
The initial probes wrongly asserted drawn texts equal labels; both failed
identically, and their snapshots/manifests/logs/counters remain excluded evidence.

| Labels | Baseline allocated bytes | Candidate allocated bytes | Peak live bytes, both | Baseline is_form calls | Candidate is_form calls |
| --- | ---: | ---: | ---: | ---: | ---: |
| 16 | 1,031,160 | 1,029,752 | 38,000 | 18,515 | 3,501 |
| 64 | 1,176,160 | 1,174,752 | 105,896 | 21,347 | 4,173 |

Reallocation added bytes are unchanged (0 / 4,608). The only allocation reduction
is 22 removed library-ID buffer copies (1,408 bytes). Label/rail function traffic
and peak storage are unchanged. Bounds checks decrease 54,008 → 49,038 and
62,168 → 56,574; total counted calls decrease 129,594 → 114,033 and
150,426 → 132,609. These are instrumented structural counters, not runtime claims.
All four successful runs have identical expected stdout, zero RC/sharing events,
zero uniqueness-test events, and zero managed bytes at exit.

Reproduce after the dev environment and private P5 TMP/cache setup:
`python3 P5/verify_probe.py baseline-v2`, then `candidate-v2`, then
`python3 P5/summarize_verify.py`. Existing immutable target directories must be
preserved; use a fresh worktree for replay. Each native build/run uses shared
build admission, and each guest invocation has a 30-second bound. Raw counters,
phase/compiler/binary/source/command receipts, failed harness evidence, and
`verify-counter-summary.json` retain each measurement separately.

All 34 goldens, full 60-case runtime qualification, 3x fresh Zig cutoffs, 120-second
absolute bounds, and counted integrated candidate receipts remain coordinator
work. No runtime/RSS or managed-memory improvement claim is made here.
