# Lox/EDA individual Zig parity work

Implementation is in progress. No fresh full-application runtime or parity
result has been published for this candidate.

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
exchange source depends on the new compiler helper, whose final qualification
is still pending. Its provisional worker build passed 84 tests and removed
300 list copies (14,745,600 bytes) in the bounded mutation probe. The parser
probe reduced allocations from 46,000 to 18,000 and allocation traffic from
4,288,000 to 2,432,000 bytes. These are separate instrumented probes, not
full-application runtime or RSS measurements. Exact identities and raw counters
are in P1 and P3.

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
