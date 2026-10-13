# Lox/EDA individual Zig parity work

Implementation and qualification are in progress. The first combined candidate
has passed the application correctness matrices, but its completed runtime cases
remain slower than Zig. A second candidate includes measured follow-up changes;
it has been built and is undergoing application qualification. Individual parity
and the final complete verification gate are still open.

The target is each of the existing 60 cases at or below Zig ReleaseFast runtime:
13 Lox tree cases, 13 Lox VM cases and 34 EDA cases. A favorable aggregate does
not close a slower individual case. Inputs, outputs, interpreter GC behavior,
error paths and checked ownership remain part of the contract.

The integration branch is `codex/lox-eda-parity-20261013`, starting from
`53dd221c3ccd6f1b69fae75a08873fc381fe0012`. Commit
`2525a66f61838086f5327d74db7412926ce4a221` froze the prior checked application
sources into this directory. Historical results remain under
`../lox-eda-improvements-20261012`; they are controls, not new measurements.

Implementation priorities are Lox payload updates and fresh construction,
VM execution overhead, EDA scanning/parsing intermediates, tree environment
construction, and the remaining EDA routing/layout costs. Workers P1–P5 own
these source areas. P6 prepared the measurement harness, then took the P7
compiler assignment for a bounded list-element exchange operation. Workers use
separate worktrees, shared build admission and the requested Sol 6.1 low effort.

`run.json` records current milestone status. Worker handoffs preserve exact
source/compiler identities, commands, successful and failed checks, and pending
measurements. The integrated compiler still requires qualification; worker
passes do not replace the combined application matrices or full gate.

Integrated source changes include borrowed EDA parsing and routing inputs,
fresh Lox constructors, and owned payload exchange in the heap setters. The
bounded mutation probe removes 300 list copies (14,745,600 bytes). The parser
probe reduces allocations from 46,000 to 18,000 and allocation traffic from
4,288,000 to 2,432,000 bytes. These instrumented probes do not establish
full-application runtime or RSS savings. Exact identities and raw counters are
in P1 and P3.

The immutable first candidate is `source/`, built by compiler
`955f311e1dbf65b55f4c148ab03cdcb4881bc5668289aea93336dbfd7985206a`
from revision `be33ce79b5b58c3e254e73709c9dd7eb97e5a849`.
It passed 93 Lox tests and 325 EDA tests in each of five modes, 2,922 Lox
conformance executions across three source/mode controls, 102 EDA golden output
sets and nine error cases. Its selected guest LLVM and native symbol audits
also passed. Its full verification run failed on fixture formatting, a diagnostic
oracle spelling list and a counted-test output escaping its temporary directory.
Those fixes are integrated; a fresh complete gate remains required.

The second frozen source snapshot is `source-002/`. It adds scalar-IP VM readers,
fresh call-environment construction, simpler checked getter control flow,
discarded-local-expression evaluation without a transient push/pop, and borrowed
EDA composition/textbox inputs. Its compiler also skips primitive-field copy
work after an aggregate has already been initialized by `memcpy`. The separately
tested pointer-destruction and bulk-list-copy experiments were not adopted.
`coordinator/source-002/assembly.json` records the individual decisions and
provenance. Compiler
`9bedb835438615d79ed8f2985352877a8c844eebeb74cd95a1d276332b6b0c6a`
comes from revision `fbeba4eed7b549a3feef14c8b8dd620e41494139`;
both complete application builds are recorded under `attempts/native-002/`.

Diagnostic follow-ups show consistent improvements for individual changes:
scalar-IP readers reduce VM Fibonacci time by 9.9% and closures by 9.0%; the
discarded-local-expression change reduces tree string-equality time by 14.8%.
Each uses nine matched pairs against its recorded control. These results are
not added together or relabeled as measurements of the combined second candidate.
Further bounded VM-inlining and EDA-copy/scanner experiments remain isolated
until their correctness and performance evidence is reviewed. The numeric
dispatch prototype removed a native helper call but showed no reliable runtime
benefit in nine matched pairs on each of three workloads; it is not adopted.

The first candidate's complete runtime/RSS sweep is recorded in
`coordinator/progress-003.json`. All 60 cases remain in the denominator: 59
finished and VM string equality hit the three-times-Zig cutoff. None reached
individual parity. Geometric mean runtime ratios against Zig are 1.415 for EDA
(34 cases), 1.267 for tree Lox (13) and 2.208 for VM Lox (12 completed).
Matched ratios against the freshly measured previous version are 0.849, 0.783
and 0.929 respectively, using 33, 13 and 11 completed pairs. Counter collection
and final identity validation remain pending; these are C1 results, not C2.

Both C2 applications have passed primary qualification. EDA additionally passed
all five build modes with 328 tests each, 102 golden output sets and nine error
cases. Lox has 103 passing tests, all three conformance controls and the GC/CLI
checks; its five-mode matrix is still running. The selected C2 guest LLVM and
native symbol audits pass. The full compiler verification gate remains open.

## Reproduction and measurement

Source `/home/epentland/.config/mylang/dev-env.sh`. `native.py` takes explicit
compiler installation, source and receipt arguments and builds isolated original,
migrated and checked source controls, plus counted binaries. It also builds the
previous checked source with the new compiler to separate compiler and source
effects. Qualification uses current test declaration counts, all five ownership
build modes, Lox conformance/GC stress and EDA golden/error outputs.

After both builds, `audit_guests.py --output REPORT BUILD_LOX BUILD_EDA`
checks the recorded guest LLVM and the timed and counted native binaries for
legacy RC helpers. It also checks emitted managed-count loads and initializers.
The audit is scoped to those guests; it does not establish package retirement.
Its positive and negative smoke controls use the previous checked and RC
artifacts, with results recorded in `P6/guest-audit-validation.json`.

Finished attempt evidence is preserved with `archive_attempt.py`. Each archive
has a per-file SHA-256 inventory and is verified byte for byte before publication.
`archives/native-001.tar.xz` contains the first complete application qualification;
its raw attempt directory is retained locally. Compiler installations and guest
binaries are separately pinned by the archived receipts.

`fixtures/lox/recovery.json` pins the recovered historical Lox harness and
corpus. All 254 corpus files match the previous qualification identities; the
harness is recovered from its exact historical Git revision. Pass its
`harness/lox_bench.py` path explicitly to Lox qualification.

`pipeline.py` prepares all 60 cases and freezes inputs, installations and
binaries. Use a distinct attempt name for native builds and runtime preparation.
Full timing requires a coordinator freeze matching `pins.json`; selected cases
are diagnostic runs. Five fresh Zig calibration samples after two warmups set
the checked-program deadline to `min(120 seconds, 3 × Zig median)`. Each runtime
case has two warmup rounds, nine alternating measured rounds and three separate
RSS rounds. A censored program remains in the denominator and has no invented
runtime ratio. Timing admission wait is excluded.

Managed allocation traffic, cumulative bytes, peak live bytes, exit-live bytes
and RC events come from separate instrumented runs. Runtime and process RSS use
uninstrumented binaries. `compile_measure.py` records three alternating
cold-guest-cache/warm-replay observations for previous compiler/source, new
compiler/previous source and the candidate. Build RSS uses GNU time and does
not represent summed simultaneous process-tree memory. OS and host-tool caches
are not flushed.

The eight deadline tests pass. `P6/harness-audit-001.tar.gz` preserves a
60-case preparation smoke check using prior artifacts; it contains no runtime
measurements and is not a candidate qualification. Other sessions' admitted
jobs are left running, including their exclusive timing windows.
