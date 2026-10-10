# Frontend adoption: cache identity, consumers and qualification

Date: 10 October 2026. Integration branch:
`codex/selka-frontend-adoption-20261010`.
Worktree: `/home/epentland/.codex/worktrees/selka-selfhost-pilots/mylang`.
Three Sol agents continued the preceding frontend pilots in separate worktrees.
The committed cache work at `1d202d41b` is merged; the active original checkout
was not modified.

## Implemented stages

1. **Bind frontend identities to reuse.** Both selected producers are verified
   before retained syntax, persistent frontend or semantic state, executable
   replay and test receipts are consulted. Identities include selected mode,
   schema and artifact bytes. Source path/content, grammar mode and intrinsic
   authority remain explicit cache inputs. Single-unit and module grammar keys
   are distinct even when both start at byte zero. Shadow mode bypasses reuse
   so a warm hit cannot suppress comparison. Captured producer identities are
   checked again before publishing reusable results.
2. **Route ordinary compiler consumers.** Compilation, project/interface loads,
   Core frontend sessions, formatting, declarations and whole-source auxiliary
   scans use the selected boundary. Host deployment/transport failures retain
   status 2 instead of becoming source diagnostics or empty navigation results.
   Explicit `component` mode uses validated component tokens and syntax. Lexer
   failures still use the native diagnostic renderer after validating the
   component's error code, span and location; successful component lexing does
   not repeat the native lexer. Internal format-hole and name-fragment parsing
   remains part of its enclosing implementation profile.
3. **Qualify workflows and measure adoption.** The registered
   `test-selfhost-frontend` target covers normal and release/fact/leak workflows,
   warm deployment failures, live sessions and a real coordinator parser edit.
   It is part of the full gate. Its seed/deployment checks always run, including
   when other verification receipts are reused. Verification cache inputs now
   include all four component packages. The isolated measurement driver records
   parser command, application build and native coordinator costs separately.

## Execution evidence

The full repository gate on code commit `2b33d2112` passed **120/120 steps**.
Guardian's 29 selected native verdicts total **2,644 passed, zero failed, zero
skipped**; two additional ordinary Zig tests bring the build aggregate to 2,646
passes. Its 24,069 skipped slots belong to other shards, not omitted selected
tests. All 88 blocking Guardian checks passed. The complete log and machine
readable totals are preserved in [gate evidence](evidence/selka-frontend-adoption-20261010/gate-summary.json)
and the [compressed full log](evidence/selka-frontend-adoption-20261010/full-gate.log.gz).

| Frontend lane | Workflows | Comparisons | Warm deployment failures | Live-session checks |
| --- | ---: | ---: | ---: | ---: |
| Normal, including parser-only coordinator edit | 29 | 116 | 60 | 8 |
| Release, fact verification and leak checks | 29 | 58 | 60 | 8 |

Both lanes report zero failures or skips. Cache-enabled test probes confirmed
two cached component-mode verdicts and two executed shadow-mode verdicts, using
the same deployment paths before and after mutation. The coordinator edit
changed the parser recipe key and executable digest, while the other three
packages and host executable stayed unchanged. Ten adversarial harness tests
also passed.

The three earlier pilot lanes passed in this same gate: 17 lexer, 86 parser and
11 probe pure tests in each mode. Lexer comparisons cover 79 fixtures and 1,714
token/error rows. Both parser corpus runs selected 379 files: 378 exact AST
matches and the previously pinned lexical exclusion, with zero mismatches.
The historical lexer driver retains three exclusions; the documentation runner
retains 23 explicitly skipped examples. These are not counted as current
frontend parity. The full log records the other historical golden exclusions.

The ReleaseFast installation passed 12/12 steps. Production sources stayed
unchanged during measurement. The measurement-only follow-up at `499b713aa`
replaced Python's timed polling wait with a blocking wait and deadline watchdog;
its output/status/deadline checks and all ten harness self-tests passed. The
earlier polling measurements were discarded.

The final combined `test-docs fmt-check` run passed **21/21 steps** after the
report and usage guide were written. Documentation counted 221 executed and
62 checked examples, with 23 declared skips and no failures or mistagged blocks;
unchanged live-source formatting checks reused their valid results. Its
[complete log](evidence/selka-frontend-adoption-20261010/docs-fmt.log.gz) is archived.
No Guardian feedback file was modified.

## Isolated measurements

The corrected driver held the gate reservation and all three build reservations
through FIFO admission. All measured processes used reserved CPUs `2,3,10,11`.
Every sample checked actual results. The ReleaseFast host SHA-256 was
`51c207cb030c5c5c9cf19ef041d7eeaea3ddb5924c05d991f46a665e06b97b19`.
[Raw samples and cache reports](evidence/selka-frontend-adoption-20261010/timing.json),
[commands and source identity](evidence/selka-frontend-adoption-20261010/measurement-receipt.json)
and the [admission log](evidence/selka-frontend-adoption-20261010/timing-admission.log)
are preserved with this report.

| Complete parser CLI invocation | Reference median | Shadow median | Component median |
| --- | ---: | ---: | ---: |
| 33-byte source | 1.223 ms | 11.680 ms | 11.593 ms |
| 65,533-byte comment source | 1.225 ms | 12.130 ms | 11.595 ms |
| 700 helper declarations, 25,013 bytes | 4.521 ms | 90.443 ms | 87.482 ms |

Each row/mode has 20 samples of `dump-syntax`, with the lexer held in reference
mode. The dense input produces a 1,167,257-byte reply. These are complete
invocations, including launch, authentication, transport, validation and capture;
they do not isolate the parser algorithm.

| Application build | Reference | Shadow | Component |
| --- | ---: | ---: | ---: |
| Empty application cache, one sample | 18.406 ms | 135.685 ms | 141.417 ms |
| Unchanged warm command, median of 20 | 2.132 ms | 107.864 ms | 15.367 ms |
| Imported function edit, median of 5 | 17.971 ms | 126.448 ms | 119.912 ms |

Both frontend modes are selected together for application builds. The native
unit/runtime/toolchain stores were warm: the recorded cold and edit reports
reused all three native units and linked the program, so these are empty
application-cache and source-edit measurements, not cold native compilation.
Reference and component warm commands replayed the executable; shadow kept
running the frontend comparison and reused lower-level native artifacts.
Every edited executable returned the newly requested value.

Test-index and cache-plan modes were held in reference mode, and fact/leak
verification was disabled for these cache measurements. Thus the timings
isolate frontend adoption within complete commands; they do not represent all
production-default component settings. Modes ran in a fixed order on a warm
machine, so these small fixtures are not a general performance forecast.

The native coordinator took **27.378 s** for all four packages in an empty
private artifact store, **0.444 s** warm (median of three), and **8.612 s** for a
parser-only implementation edit (one sample). Its qualified seed was already
provisioned. These costs include seed verification, source snapshots, native
compilation and installation. The changed parser key/artifact and unchanged
host/other three packages were checked again. Cumulative child peak RSS was
399,684 KiB for the entire driver, including coordinator descendants; this is
not per-exchange memory.

The measured component paths cost more than the reference frontend. Reducing
authentication/transport costs and widening the qualified profile are required
before considering a default switch.

## Adoption limits

Native `reference` mode remains the default. `MYLANG_LEXER_MODE` and
`MYLANG_PARSER_MODE` independently accept `reference`, `shadow` or `component`.
Packages are resolved from
the installation or `MYLANG_COMPONENT_DIR`; missing, corrupt or incompatible
selected packages fail rather than silently changing mode.

The qualified whole-source component limit is **262,144 bytes**. The workflow
suite tests the exact limit and requires a bounded host failure one byte beyond
it, while the native frontend accepts that valid source. This narrower profile
prevents a default switch. Corpus equality is evidence for the selected inputs,
not a proof for every possible program. Pure native library callers without
runtime capabilities and internal fragment parsers retain their native APIs.

The current pass does not change either bootstrap seed pin. Contained analyses,
checker/lowering slices, staged self-compilation and reproducibility remain
later milestones. Widening and requalifying the source profile and reviewing
measured overhead come before changing production defaults.

## Reproduction

Use the pinned Zig, a worktree-private disk `TMPDIR` and local Zig cache, and
the shared global cache described in `CLAUDE.md`.

```console
scripts/build-slot.sh build zig build --summary all
scripts/build-slot.sh build zig build test-selfhost-frontend --summary all
scripts/build-slot.sh gate zig build test --summary all -j4 --maxrss 8589934592
scripts/build-slot.sh build zig build fmt-check --summary all
```

The [qualification guide](../tooling/frontend-adoption-qualification.md)
documents direct driver invocation, fixture coverage, cache-failure scenarios
and isolated measurement requirements. Timings require a ReleaseFast host,
reserved timing CPUs and exclusive build/gate reservations obtained through
FIFO admission. Installation and compiler runtime continue to require no Python;
the Python qualification tools belong only to developer verification.
