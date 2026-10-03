Independent read-only review of checked VM constant reads, 2026-10-03.

No source finding in candidate `58fe1925533ad46e3a8e60af6a9b9632510ee979`
or native followup `0fd93cf35db135872ea2dcc1a248d43e71229429`.
This review executes no guest, test, timing or counter workload and writes
only its own review artifact. It does not select the candidate for integration.

The exact qualified source is
`/home/epentland/ai/canopy/mylang-worktrees/codex-lox-vm-dispatch-20261003/.tmp-lox-vm-dispatch-20261003/constant-readonly-qualified`.
All 37 hashes match qualification.json; all 17 primary experiment files match
the committed Git blobs. Replaying the overlay in memory against accepted
combined84 produces those exact 37 files. Only vm.my and the appended driver
regression/provider change; the other 34 files are identical. The existing
80 and 84 test names are retained, and the original driver source is an exact
prefix of the extended file. Existing provider entries retain their values.

OP_CONSTANT still performs the checked code read, checked IP increment,
checked constant-pool read, checked stack write, then checked stack-top
increment in that order. `read_constant` and its other callers are unchanged.
The new readonly helper receives the caller's still-live ExecFrame after
`read_byte` completes. There is no callback, mutation, allocation or collector
entry between those operations. ExecFrame retains the native list owners;
`rt.frames` retains the executing closure, whose function traces object values
in its constant pool. Value contains only plain scalars/Object-table indices.
The helper's returned element therefore introduces no native managed loan,
list mutation, list owner release or new Lox root obligation. Existing COW
snapshot/list checks and the runtime's root publication remain in place.

Each of four fresh public runs contains exactly the 85 discovered names:
LLVM O3/full LTO and QBE ReleaseFast, each under checked RC and native tracing
GC stress. Every log reports 85 passed, zero cached/failed/skipped/dropped
across ten programs: 340 fresh passes. Compiler d14a7040 and adjacent QBE
99ad919d match current hashes. The new regression emits numeric constants
0..255; unchanged make_constant rejects indices at 256, so it covers the last
legal operand and subsequent opcode alignment. Object constants use the
retained string/closure/root regressions.

The directory commands do not supply --cases driver_cases.json. The automatic
sibling spelling is driver_tests.cases.json, which is absent. All four saved
added-case results have provider="". Consequently the Clock fixture is
preserved structurally and no provider-backed execution is claimed. Ordinary
natives returns zero for a missing Clock capability; the numeric boundary case
does not invoke clock.

The separate native receipt qualifies actual RC and separately built native
tracing GC ELFs from the production-equivalent pre-fixture source. Only its
driver test/provider metadata differs from public85; vm.my and every production
dependency are identical. All 15 followup experiment files match their Git blobs.

| Native mode | Exact candidate/control comparisons |
| --- | ---: |
| Checked RC | 416 |
| Ordinary native tracing GC | 416 |
| Native tracing GC stress | 336 |

All 104 case definitions independently regenerate from 13 pinned smoke scripts,
16 focused programs and 23 historical errors per engine. The 1,168 unique run
identities and 80 disjoint omissions exactly fill the 1,248 intended cells.
Both engines/backends and Lox stress off/on are covered; full status/stdout/
stderr, including Lox collector statistics, match each saved control observation.
The 80 omitted native-stress smoke cells are omissions. Twelve distinct VM
operand-boundary comparisons cover 0..255 on actual ELFs in all runtime modes;
eight RC native-stress comparisons produce the same checked refusal, never a
program pass. Native stress is MYLANG_OPTIONS=--gc-stress; guest --gc-stress is
independent Lox stress. Harness review verifies the environment selection.

Before/after source37, compiler/QBE, every actual ELF/sidecar/runtime archive,
harness, focused/historical/pinned input and generated-script identity matches
the receipts and current files. The pinned bench and SPEC bytes also equal
Git 4e48a09220c2e018eba8c4b1eb3fe1137a3dae73. Runner affinity excludes CPUs
2, 3, 10 and 11. The reviewer performs no new program executions.

Disassembly regenerated from current native ELFs matches the retained assembly.
Whole vm::run counts independently reproduce:

| Backend | Control instructions / calls | Candidate instructions / calls |
| --- | ---: | ---: |
| LLVM O3/full LTO | 5586 / 486 | 5449 / 454 |
| QBE | 8606 / 440 | 8628 / 442 |

Both LLVM opcode dispatch tables have 37 checked entries. QBE retains a
comparison chain. The readonly helper has 129 diagnostic IL lines, three checked
failure calls and two empty-return memsets, without RC glue. This emission uses
--drop-step-checks/--drop-frame-checks; accounted public tests are a distinct
configuration. Control uniqueness sites (LLVM29/QBE22), the linked RC bitcode
archive member and rejected variants' static growth also independently match.
Static counts include cold code/inlining and support no speed claim.

Limits remain explicit: source helper PC attribution for malformed internal
bytecode can differ; source step totals/native helper nesting can alter tight
step/frame-budget boundaries. The accounted suites use a generous one-billion
step budget and establish no identical threshold for tiny quotas. Native fast
ELFs use the compiler's existing accounting policy, unchanged by this overlay.
Published Lox error IP and the Lox 64-frame call guard are unchanged. Valid
compiled Lox behavior is covered by the reviewed suites/matrix; no new malformed
bytecode or quota-boundary execution is claimed.

review.py is the independent read-only checker. Replay with a fresh output:

```bash
python3 experiments/lox-vm-constant-review-20261003/review.py --out /tmp/lox-vm-constant-review-new.json
```

summary.json is compact. review.json.gz preserves exact argv, all discovered
names, source37 and reviewed-file hash maps, native identities and checks.
Original review stages remain in private scratch; no producer receipt was edited.
