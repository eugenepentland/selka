# Ownership as the default: coordinator plus ten workers (2026-10-15)

Prepared 15 October 2026 as the execution handoff for one coordinator and ten
workers, W01 to W10. The program makes checked ownership (today
`--experimental-zero-rc`) the only memory model and removes reference counting.
It supersedes the
[12 October plan](zero-rc-closeout-10-agent-plan-2026-10-12.md), whose first
milestone Codex ran as `codex/memory-closeout-20261012`. That work is merged; its
ledger (`experiments/memory-closeout-20261012/ledger.json`) records the default
and the retirement as deferred by the user. Both are now the goal.

Three milestones, reported separately:

1. **M1, qualified implementation.** Every corpus root passes under
   `--experimental-zero-rc`, while reference counting is still the default.
2. **M2, the default.** Plain `mylang check`, `run`, `build` and `test` use
   checked ownership with no flag.
3. **M3, retirement.** No reference counting or copy-on-write remains in the
   compiler, the IR, the runtime or the block header.

Out of scope:

- Wave 3 (proposal 16, `str` as bytes; proposal 17, slices as views); see D1.
- The parity lanes. This program removes their ownership causes C6 and C7, and
  parity cause C1 stays in the parity program.
- Self-hosting, apart from the component seed (D8).

## What changed since 12 October

- **Language wave 1 made several 12 October items moot:**
  - tuple staging and unpack fixes;
  - generator and comprehension copies;
  - sequence repetition;
  - negative-index wrapping;
  - storage for conditional and `match` expressions;
  - captured closures (lambdas are gone);
  - the effect-docs migration;
  - copied Host adapters.

  `.snapshot()` has no use in any `.my` file.
- **Lox and EDA are migrated to checked ownership.** In the parity campaign
  (`codex/lox-eda-parity-20261013`, merged) all 59 counted runs had zero RC
  events. Against Zig they run 1.336× (EDA), 1.175× (tree) and 1.806× (VM). The
  default does not wait for further application work.
- **Shipped from the 12 October run:**
  - A01, parallel map;
  - A02, capacity, measured, with the existing policy kept;
  - A03, the census (stale);
  - A04, the text, JSON and codec classification (80 functions);
  - A06, the applications, since overtaken by Lox and EDA;
  - guest `test` under zero-RC (NEW-CORE-ZERO-RC-TEST-1).

  Its rollout patches in `experiments/memory-closeout-20261012/A10/rollout/`
  (`C2-default.patch`, 104 lines; `C3-cli-selector-retirement.patch`, 337;
  `C3-component-retirement.patch`, 284) are unapplied and stale.

## Current state

- **Modes** (`src/core/cli_args.zig:172-177`). `--experimental-single-owner` is
  a hybrid: RC stays, and `.snapshot()` opts back into copy-on-write
  (`single_owner.zig:1205`). `--experimental-zero-rc` sets both modes and:
  - runs the eager, uncached whole-program checker (`single_owner.validateMode`,
    called from `pipeline.zig:254`, `check_command.zig:57`, `frontend.zig:288`);
  - turns off demand-driven lowering (`pipeline.zig:157`, `useDemandBodies` at
    `:265`);
  - drops the header's count field (`driver.zig:384` prepends
    `#define MYL_ZERO_RC`);
  - rewrites the RC prelude by string replacement (`zero_rc.zig:4-31`).
- **Refusals.** `single_owner.zig` has 74 `reject(` sites. By code:
  - `E_SINGLE_OWNER_BORROW` 37, `E_SINGLE_OWNER_OVERLAP` 35,
    `E_SINGLE_OWNER_MOVED` 17;
  - `E_ZERO_RC_VIEW_INVALIDATED` 12, `E_ZERO_RC_UNSUPPORTED` 7,
    `E_ZERO_RC_RESOURCE_ESCAPE` 6.

  None carries a machine-applicable fix.
- **Corpus.** No gate step runs the corpus under zero-RC. The last survey, on
  12 October and before wave 1, admitted 179 of 356 `tests/lang` and
  `tests/value_semantics` files and refused 177. `test/core`, `test/fixtures`,
  `examples`, `bench`, `selfhost` and the doc examples were never surveyed.
- **Known defects:**
  - `frontend_mut.my` returns a wrong mutable-writeback result;
  - recursive structural equality is unfinished (parked patch in
    `experiments/memory-closeout-20261012/A10/equality/`);
  - the recursive canonical shadow defect;
  - `value_equality.my` generated helpers;
  - the text cursor cache writes into text blocks (`core_text.c:120-140`,
    `core_text_can_cache` in `core_rt.c`), which is a race once text is borrowed
    across parallel tasks.

## Base and constraints

`C0` is local `main` after the
[wave 1 cleanup](language-wave1-cleanup-plan-2026-10-15.md) has landed. It must
contain language wave 1 and the caching follow-up with a passing complete
verification. Recheck before starting.

- **Disk.** Ten worktrees at 4–8 GB each plus gates need at least 100 GB free
  on `/home/epentland/ai` before R0. If it is short, stop and ask the user. Do
  not delete other sessions' worktrees or caches.
- Source `~/.config/mylang/dev-env.sh` in each worktree. Builds go through
  `scripts/build-slot.sh build`; `scripts/verify_cache.py` owns its own
  admission. No timing admission and no load-qualification windows. Record
  dev-loop numbers once each at R0, R2 and R4, with the load average beside
  them.
- **Evidence budget.**
  - Each worker writes one handoff per round, at most a page, in
    `experiments/ownership-default-20261015/WNN.md`.
  - The coordinator keeps one ledger, `status.md`.
  - Do not commit logs, receipts, archives, hash manifests or review records.
    The one review relationship is W05's adversarial tests for W04's checker
    changes.
- No pushes, no shared-cache clearing, no edits in other sessions' worktrees.

## Decisions this plan takes

The user approves these by approving the plan:

- **D1. Wave 3 follows this program, not inside it.** Proposal 16 changes the
  meaning of every text program, and proposal 17 is a new Core representation;
  each needs its own migration. The default does not depend on either. Lox and
  EDA already run without RC.
- **D2. Ownership refusals carry a certain `.copy()` fix where a copy is the
  repair.** Under value semantics an inserted copy never changes behaviour, only
  cost. `mylang fix --experimental-zero-rc` migrates the corpus mechanically;
  libraries, examples and benchmarks then get a hand review of hot paths. A
  refusal with no copy repair (a resource escaping its scope, a view
  invalidated) keeps a plain diagnostic.
- **D3. Flags.** After M2, `--experimental-zero-rc` and
  `--experimental-single-owner` are accepted with a warning that they have no
  effect. At M3 both are rejected with exit status 2 and a message saying
  reference counting was removed. The roughly 2,100 files under `experiments/`
  that pass the flag are historical records and are not rewritten.
- **D4.** `.snapshot()` and the hybrid single-owner mode are deleted at M3.
- **D5.** `@noalloc` becomes a build error at M2. It is checked on the
  ownership-expanded Core, so its allocation sites stop depending on reference
  counting.
- **D6.** M3 removes the header's count field. Any further header or list
  layout work stays with the parity program (its decision D5).
- **D7. Two full cache invalidations are accepted:** the flip at M2 and the
  runtime ABI change at M3. Keep the hashed mode fields as a constant
  (`"zero-rc"`) rather than deleting them, so M3's compiler deletions do not
  cause a third.
- **D8. The component seed moves to a zero-RC compiler at M2.** The coordinator
  qualifies the flipped compiler as the new seed in
  `selfhost/component-seed.json`, then removes the owned-pin route. The
  self-hosting work is paused, so the coordinator owns this.
- **D9. The default must not slow the development loop.** At R2 and R4, these
  stay within 10 % of the R0 numbers measured under reference counting on this
  machine:
  - a cold complete verification;
  - a one-line compiler edit to green;
  - `mylang check` on the largest project.

  Demand lowering must work under ownership before the flip.

## Ownership and operating rules

- The coordinator alone edits `build.zig`, `build_test_inputs.zig`, `SPEC.md`,
  `CLAUDE.md`, `guardian.toml`, `src/features.json`,
  `selfhost/component-seed.json` and the cache format versions. Workers send
  SPEC text and build wiring as patch requests in their handoff.
- Each worker's tests go in its own new files, registered by the coordinator.
- Shared files are split by function:
  - `src/core/own.zig`: W06 owns the elision functions; W08 owns phases A and B
    and the R-2 peephole, and lands only at R4, after W06.
  - `single_owner.zig`: W04 owns it until R3; W08 then removes the hybrid-mode
    refusals (`:243-259`) and the snapshot path (`:1205`).
  - `src/core/runtime/core_text.c`: W09 owns the cursor cache and the RC blocks;
    W06 owns nothing there.
- A test whose subject is reference counting or copy-on-write is deleted with
  that code in R4, not migrated.

## Ten workers

| Worker | Scope | Owns |
| --- | --- | --- |
| W01 | Corpus A: survey, then migrate | `tests/lang`, `tests/value_semantics` |
| W02 | Corpus B: survey, then migrate | `test/core`, `test/fixtures`, `tests/ported`, `tests/guest`, Selka sources embedded in Zig tests |
| W03 | Corpus C: survey, then migrate; rebaseline benchmarks at R3 | `src/stdlib`, `examples`, `bench`, `benchmarks`, `selfhost/components`, doc examples |
| W04 | `.copy()` fix payloads (R0), then checker gaps | `single_owner*.zig`, `borrow_*.zig`, `borrowed_provider.zig` |
| W05 | Correctness defects; adversarial tests for W04 | The defect sites listed under W05; its own test files |
| W06 | Copy cost (parity C6, C7) | `emit_release.zig`, `core_owned_copy.c`, the copy paths in `core_values.c`, the elision functions in `own.zig` |
| W07 | Compile time and caches | The demand path in `pipeline.zig`, `lowering_*`, `canonical_ir.zig`, `emission_key.zig`, `emission_cache.zig`, the driver keys |
| W08 | Compiler RC retirement (prepared from R0, lands at R4) | `own.zig` phases A and B and R-2, the RC ops in `ir.zig`, counting in `emit_llvm.zig`, `zero_rc.zig`, `emit_count.zig`, `count_runtime.zig`, `verify_ir.zig`, the hybrid mode, the mode plumbing |
| W09 | Runtime RC retirement and the text cursor cache | The `#ifndef MYL_ZERO_RC` blocks in `src/core/runtime/*.c`, `core_count.*`, `driver.zig:384`, the cursor cache in `core_text.c` and `core_rt.c` |
| W10 | Commands, the default, flags, components, docs | `cli*.zig`, `main.zig`, `check_command.zig`, `selfhost/components.zig`, `docs/managed-memory.md`, `docs/tooling/ownership.md`, `docs/value-semantics.md`, `docs/tooling/counters.md` |

### W01, W02, W03: the corpus

**R0 survey.** Run every file in your roots under `--experimental-zero-rc` and
list each refusal by code and site. For each one, mark whether D2's copy fix
repairs it or whether it needs a checker gap fixed (W04) or a defect fixed
(W05).

**R1 migration.** Use W04's fixes as they land. Migrated code must pass in both
modes, so it can integrate while reference counting is still the default.

- **W02:** the embedded Zig sources go through `scripts/migrate_embedded.py`
  with the zero-RC flag.
- **W03:**
  - review every copy the fixer inserts in `src/stdlib` and `bench/parity`, and
    restructure the hot ones (a move, a borrow, a narrower copy) instead of
    keeping the copy;
  - rerun the Lox/EDA 60 cases in both modes at R2;
  - rebaseline `bench/parity` and `benchmarks/runtime` under zero-RC at R3.

### W04: fixes and checker gaps

**R0.** Add certain `.copy()` fix payloads to `E_SINGLE_OWNER_BORROW`,
`E_SINGLE_OWNER_OVERLAP` and `E_SINGLE_OWNER_MOVED` where a copy at the reported
use is the repair. Each fix gets a test in the existing fix-migration style:
diagnostic, preview, exact fix, a clean check afterwards, and idempotence.

**R1.** Close the unsupported shapes the corpus survey ranks highest. The known
ones, by `single_owner.zig` line:

| Shape | Line |
| --- | --- |
| Moving a field out of a record | `:655` |
| Indexed reads that are only borrowed | `:661`, `:967` |
| Arguments that need evaluation temporaries | `:686` |
| Unbound callback arguments | `:691` |
| Nested element-field writes | — |
| `Option` lazy fields | — |
| Views stored in aggregates | `:235` |

Every accepted shape needs a soundness argument in the handoff. It also needs
W05's adversarial tests passing under the leak checker and AddressSanitizer.

### W05: correctness

- Fix the `frontend_mut.my` writeback result.
- Finish recursive structural equality from the parked patch.
- Fix the canonical shadow defect, coordinating with W07 on `canonical_ir.zig`.
- Fix the `value_equality.my` generated helpers.

For each W04 change, write tests that try to break it: aliasing through a
borrowed index, moving a field that is later read, a callback argument that
outlives its source. Run them under the leak checker and AddressSanitizer.

### W06: copy cost

- Generated copy and drop functions instead of descriptor walking.
- Inline allocation and free on the hot paths.
- Empty lists that do not allocate.
- `.copy()` elision where the source is dead.
- Field, element and `match`-scrutinee moves in lowering (parity C7).
- The dictionary update that copies its key (5.35×).
- The owned-slice deep copy (OWNED-LIST-COPYING-1) when the source dies.

Measure each change on the Lox/EDA cases and the word-count micro benchmark
under zero-RC.

### W07: compile time

- Make the ownership check cached and incremental: per function, keyed like the
  semantic cache, instead of an eager pass over the whole program.
- Make demand-driven lowering work under ownership (`pipeline.zig:157`,
  `:265`).
- Measure `check` and build time against program size in both modes at R0 and
  R2.
- Add invalidation tests for the mode field in every key (`canonical_ir.zig`,
  `lowering_cache.zig`, `emission_key.zig`, `emission_cache.zig`,
  `emit_units.zig`, `driver.zig:405`, the test receipts).

W07 meets D9 or reports exactly why not.

### W08: compiler retirement

From R0, prepare on its branch, rebased each round:

- delete `own.zig` phase A (copy-on-write, about lines 912–1488), phase B
  (retain placement, 2189–2377; releases become direct destruction) and the R-2
  pair peephole (2378–2422);
- delete the retain, release and `is_unique` ops (`ir.zig:340-344`) and their
  emission in `emit_llvm.zig`:
  - `Counting` and the `counted*` functions;
  - the RC arms near 2178–2215;
  - the prelude declarations;
- delete the legacy branch of `emit_release.zig`, the string rewrite in
  `zero_rc.zig`, and the RC kinds in `emit_count.zig` and `count_runtime.zig`;
- delete the hybrid mode and `.snapshot()`;
- collapse the mode plumbing (about 221 `single_owner` references in about 40
  files) to the one mode, keeping the hashed constant (D7).

It lands at R4 together with W09 and W10's retirement patch.

### W09: runtime

**R1.** Make the text cursor cache safe for text borrowed across tasks: no
writes into a shared block, or a cache that is task-local.

**From R0, on its branch:** delete every `#ifndef MYL_ZERO_RC` block and the
define itself (`core_rt.c` 161 lines, `core_tasks.c` 13, `core_text.c` 9,
`core_dict.c` 8, `core_io.c` 7, `core_bytes.c` 4, `core_sort.c` 1). That removes:

- the header's `count` field, `MYL_SHARED` and `MYL_SATURATED`;
- the retain and release atomics;
- the child retains in `list_copy`;
- the share and release paths;
- the RC counters in `core_count.*`.

It lands at R4.

### W10: commands and the default

1. **R0:** rebase the three rollout patches onto `C0`.
2. **R3:** land the flip as one commit:
   - the default mode becomes zero-RC;
   - D3's warning on the flags;
   - D5's `@noalloc` error;
   - the `cli.zig:27` message;
   - the docs that describe reference counting as the model.
3. **R3, with the coordinator:** move the component seed (D8).
4. **R4:** land the retirement of the flag selector and the component route.

## Rounds

| Round | Work | Verification |
| --- | --- | --- |
| R0 | Corpus surveys (W01–W03); W04's fixes; W07's baselines; W08 and W09 inventories and branches; W10's rebased patches. The coordinator adds a non-blocking gate step that runs every corpus root under zero-RC and reports counts | One complete verification; dev-loop baselines |
| R1 | W04 checker gaps, W05 defects and adversarial tests, W06 copy cost, W07 compile time, W09 cursor cache; W01–W03 migrate | One complete verification; the corpus step's counts |
| R2 (M1) | The corpus step becomes blocking: zero refusals and zero failures under zero-RC, with reference counting still the default; Lox/EDA in both modes; the census rerun | One complete verification; D9 numbers |
| R3 (M2) | W10's flip; W03's rebaseline; the new component seed | One cold complete verification (expect 10–17 minutes) |
| R4 (M3) | W08, W09 and W10's retirement as one integration; flags rejected; a guard test proving no RC remains | One cold complete verification; Lox/EDA; D9 numbers; fast-forward `main` |

If a round's complete verification fails, fix the failures with focused tests
and carry the fixes into the next round's verification. Do not rerun the round.

**Riskiest work:**
- **W04's soundness:** a wrongly accepted borrow is a memory error once there is
  no reference count behind it.
- **W07's compile time:** a default that slows every check costs the whole
  development loop.

## Done criteria

| Id | Criterion |
| --- | --- |
| O1 | Every corpus root passes under zero-RC (R2) and by default (R3–R4); the corpus step is blocking |
| O2 | The four known defects are fixed with tests; W05's adversarial tests pass under the leak checker and AddressSanitizer |
| O3 | Plain commands use checked ownership; the component build uses a zero-RC seed; `@noalloc` violations fail the build |
| O4 | The guard test finds no retain, release or `is_unique` op in the IR or emitted LLVM, no `count` header field, no `MYL_ZERO_RC` in the runtime and no hybrid mode; the flags exit 2 |
| O5 | Lox/EDA: all counted runs complete with zero RC events, and none is more than 5 % slower than the parity campaign's figures; benchmarks are rebaselined |
| O6 | D9 holds at R2 and R4, or the shortfall is reported with its cause |
| O7 | SPEC and the docs describe ownership as the only model; the RC rules are retired with a dated history note |
| O8 | The final commit passes complete verification, `fmt-check`, `doctest .` and `doc-coverage .` |

## Copy-and-paste instruction for the coordinator

```text
Use docs/audits/ownership-default-10-agent-plan-2026-10-15.md as the execution
plan. C0 is local main after the wave 1 cleanup has landed; it must contain
language wave 1 and the caching follow-up with a passing complete verification.
Before R0, confirm at least 100 GB free on /home/epentland/ai; if not, stop and
ask the user. Do not delete other sessions' worktrees or caches.

Run one coordinator and workers W01-W10, each in its own worktree and branch
from C0 (codex/ownership-default-20261015-wNN), integrating on
codex/ownership-default-20261015-integration. Keep the evidence small: one
handoff of at most a page per worker per round and one ledger; do not commit
logs, receipts, archives, hash manifests or review records. Do not take timing
admission or run load-qualification windows; record dev-loop numbers once at
R0, R2 and R4 with the load average.

Enforce the ownership rules: the coordinator alone edits build.zig,
build_test_inputs.zig, SPEC.md, CLAUDE.md, guardian.toml, src/features.json,
selfhost/component-seed.json and the cache format versions; own.zig,
single_owner.zig and core_text.c are split by function as listed. W08 and W09
prepare on their branches from R0 and land only at R4, together with W10's
retirement patch.

Integrate in rounds R0-R4 with one complete verification each: R2 is milestone
M1, R3 the default (M2), R4 retirement (M3). At R4, fast-forward main to the
integration commit if its complete verification passes and main has not moved.
Report each done criterion O1-O8 as passed or failed with the command and
result. Do not push, do not clear shared caches, and do not edit other sessions'
worktrees.
```
