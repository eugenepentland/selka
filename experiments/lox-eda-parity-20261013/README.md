# Lox/EDA individual Zig parity work

The implementation passes the complete verification gate and both application
qualification matrices. The final 60-case comparison is validated. Runtime is
19.2% lower for EDA, 26.7% lower for tree Lox and 23.8% lower for VM Lox than
the freshly measured previous checked version, using completed matched cases.
Individual Zig parity remains open: one of 60 application cases reaches parity,
58 finish above Zig and VM string equality reaches the three-times-Zig cutoff.
All six text microbenchmarks remain below Zig ReleaseFast.

| Group | Complete / total | Runtime / Zig | Runtime change from previous | RSS / Zig | RSS change from previous |
| --- | ---: | ---: | ---: | ---: | ---: |
| EDA | 34/34 | 1.336× | −19.2% | 0.444× | −0.4% |
| Tree Lox | 13/13 | 1.175× | −26.7% | 2.225× | −7.1% |
| VM Lox | 12/13 | 1.806× | −23.8% | 3.025× | −2.1% |

These are geometric means of ratios of per-case medians, with nine alternating
runtime rounds and three separate RSS rounds. They describe the combined compiler
and application changes. The censored case has no invented runtime ratio.
Tree invocation is the sole application parity pass. All 59 candidate and 59
previous-version counted executions have zero RC events and zero exit-live
managed bytes. RSS is process memory; it is not managed peak memory.

[Every application case](coordinator/runtime-004-summary/cases.md),
[machine-readable results](coordinator/runtime-004-summary/cases.csv),
[microbenchmarks versus Zig/Rust/Go](P7-micro-final-004/REPORT.md), and
[validation receipt](coordinator/report-validation-004/validation.json)
preserve the individual results and their identities. Background analysis and
filesystem work overlapped some application measurements; the explicit bounds
are recorded in [measurement context](coordinator/measurement-context-004.json).
These are observations from one host, not a claim of a completely quiescent system.
The [paired regression review](P1/runtime-004-regression-screen/handoff.md)
finds that all 531 completed candidate/previous pairs favor the candidate.
Five cases have possible background-work overlap; exact effect sizes remain
subject to the recorded sample ranges. No sample was excluded or rerun.
The complete 4,002-file runtime attempt is preserved and verified in
`archives/runtime-004.tar.xz`; `archives/runtime-004.json` pins every member.

Separate instrumented managed-memory changes from the previous checked version:

| Group | Matched cases | Allocation count | Cumulative allocated bytes | Peak live managed bytes |
| --- | ---: | ---: | ---: | ---: |
| EDA | 34 | −43.3% | −30.8% | −1.8% |
| Tree Lox | 13 | −59.3% | −66.8% | −8.1% |
| VM Lox | 12 | −62.9% | −62.5% | −2.4% |

These are geometric means of positive per-case ratios, not total-byte savings.
The [final evidence synthesis](P7-final-synthesis/handoff-004.md) retains copy
traffic, allocator movement, raw counters and compilation observations separately.
Three cold/warm compilation pairs were collected for each application. Median
cold build times were about 2.95 seconds for Lox and 12.13 seconds for EDA,
against 2.88 and 12.22 seconds previously. Warm replay was about 10–22 ms and
is too small and noisy for a speedup claim. Compilation RSS is GNU time's maximum
for the command and its waited children, not a summed simultaneous process-tree
peak. The production changes, qualification and evidence remain on the local
integration branch; this batch does not advance or push main/development.

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
measurements. C4 has passed the combined application matrices and full gate;
the final performance results above show the remaining parity gaps.

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
Those fixes are integrated and covered by the passing C4 gate.

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
The third source snapshot, `source-003/`, is now frozen with additional borrowed
EDA decision and construction helpers. The bounded VM inliner, compact aligned
return transport and worklist initialization changes are integrated and qualified
on C4, including the return-construction correction described below. The numeric
dispatch prototype removed a native helper call but showed no reliable runtime
benefit in nine matched pairs on each of three workloads; it is not adopted.
The scalar scanner prototype also remains out: despite passing differential
and overflow checks and reducing instrumented helper calls, it increased runtime
by about 1.1% and 2.3% in two nine-pair comparisons against C2.
The atom-operand experiment is also rejected: it improved tree string equality
by 2.2%, but slowed Fibonacci and binary trees by 2.0% and 4.4% and increased
RSS in all three cases. Each comparison includes nine matched pairs.
The IP-only frame publication experiment is also excluded: its small Fibonacci
gain did not produce a reliable improvement in invocation, and both string-equality
variants still hit the cutoff. A borrowed EDA gangable helper is accepted for
37,926 fewer allocations and 2,811,312 fewer traffic bytes in the flat design;
nine-pair runtime comparisons are approximately neutral.

Coordinator review found missing alignment between mixed-width transported
fields in the first compact return-buffer version. That version was not timed.
The corrected version passed ABI, ownership, mode, indirect/split-unit and
application checks before its diagnostic comparison and adoption. It reduces
the evaluator stack frame from 1,208 to 488 bytes while growing its code by
34.4%; binary trees improved 1.68%, string equality slowed 0.61%, and the fib
gain remains uncertain. The bounded inliner improved VM fib and closures by
10.7% and 8.8% in nine matched pairs each, with a larger dispatch function.
These are isolated C2 comparisons, not combined C3 results. Full decisions and
limits are recorded in `coordinator/integration-003/decisions.json`.

The first candidate's complete runtime/RSS sweep is recorded in
`coordinator/progress-003.json`. All 60 cases remain in the denominator: 59
finished and VM string equality hit the three-times-Zig cutoff. None reached
individual parity. Geometric mean runtime ratios against Zig are 1.415 for EDA
(34 cases), 1.267 for tree Lox (13) and 2.208 for VM Lox (12 completed).
Matched ratios against the freshly measured previous version are 0.849, 0.783
and 0.929 respectively, using 33, 13 and 11 completed pairs. All runtime,
identity and counter checks passed. There are 59 completed candidate and 57
previous-version instrumented runs; every one has zero RC events and zero
exit-live managed bytes. Readable case rows and separate managed-memory
comparisons are in `coordinator/runtime-001-summary/`; these are C1 results, not C2.

Both C2 applications have passed primary qualification. EDA additionally passed
all five build modes with 328 tests each, 102 golden output sets and nine error
cases. Lox has 103 passing tests, all three conformance controls and the GC/CLI
checks; all five modes also passed with 103 tests each. The selected C2 guest LLVM and
native symbol audits pass. C4 subsequently passed the full compiler verification gate.

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
`archives/native-001.tar.xz` and `archives/native-002.tar.xz` contain the two
complete application qualifications. `archives/runtime-001.tar.xz` preserves
all C1 runtime, RSS and counter evidence with a verified file manifest.
Raw attempt directories are retained locally. Compiler installations and guest
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

`report_verified.py --output NEW_DIRECTORY -- report PIPELINE_ARGS` runs the
same frozen report assertions while checking every expected identity for
agreement and hashing each distinct artifact on first use and after reporting.
The wrapper also pins its own source. Its `validation.json` is the completion
marker. Eight guard tests pass, and both archived wrapper revisions reproduced
the complete C1 report byte for byte; see `coordinator/report-validation-001/`.
No timing, counters, ratios or case inclusion rules change.

## C3 gate and measurement hold

The combined C3 compiler is revision `91f5b5d3010893e7642a8fbee90fa910aa7fabab`,
binary SHA-256 `6842cc711ca6f6eadf2967a76ca60f57044ec06e0c9c2cf15b2834fd3cdebbaf`.
It passed 103 Lox and 328 EDA tests in each of five modes, all three Lox
conformance/GC controls, 102 EDA golden sets, nine error cases and 50 additional
private EDA helper checks. `archives/native-003.json` preserves that evidence.
The full gate had stable inputs, 12 reused and 34 selected actions, with two
failed steps: fixture formatting and one CE2 zero-copy return-construction
regression. The latter is a real preservation requirement, not an assertion to
weaken. No C3 runtime or compilation measurement started; the queued requests
were cancelled and their preparation is retained under `attempts/runtime-003/`.

## Qualified C4 implementation

The measured compiler source revision is
`42a93ae15b0990778379066475d3b803a596cf07`; its binary SHA-256 is
`6c3e20ff94dcfdbe6c47e8d8bd5ec14b6a32cf3d35e9c3be17c253db1626d9df`.
Application sources are the unchanged `source-003/` snapshot. The complete
installed compiler and component identities are recorded in
`coordinator/common-004/build-receipt.json`.

The C3 return-construction regression is fixed by retaining nominal return
layout when a transported field needs a memory home. Small eligible returns
still use compact transport. The original CE2 zero-copy assertions are preserved;
the three affected helpers return to zero intermediate copies. Direct, indirect,
non-fused, narrow and managed return paths have focused regression coverage.

The complete registered verification gate passed: 127/127 steps, 3,140 tests
passed and zero failed, with 12 reused and 34 selected actions. Its 27,250 shard
skips are test partitioning. Inputs remained stable. Gate and Guardian evidence
is in `coordinator/gate-003/`.

Both applications passed again on this exact compiler: 103 Lox tests and 328
EDA tests in each of five modes, all three Lox conformance controls, GC/CLI
checks, 102 EDA golden output sets, nine EDA error cases and 50 additional
fresh EDA helper checks. The selected guest LLVM/native/counting audits also
passed. See `coordinator/native-004/` and the verified
`archives/native-004.tar.xz`. These guest audits do not claim that the entire
installed package or its historical bootstrap boundary is RC-free.

The final campaign uses `attempts/runtime-004/`: all 60 application cases, separate
instrumented counters, three cold/warm compilation pairs per application and
six text microbenchmarks. Report validation passed all 5,340,213 expected identity
checks across 1,882 distinct artifacts. The wrapper intentionally published its
report into its own output directory; the coordinator corrected a summary-path
assumption by copying that validated report byte for byte into the attempt.
The initial failed summary command and successful recovery are preserved in
`coordinator/runtime-004-finalization/`; no measurement was rerun or replaced.
The earlier C1 and isolated experiment results below the final table
remain historical comparisons and are never relabeled as C4 measurements.
