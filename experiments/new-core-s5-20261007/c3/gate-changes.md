# S5-C3: `zig build test` on the new core (2026-10-07)

Lane S5-C3 of plan S5-C "Gate steps" (`docs/audits/new-core-s5-plan-2026-10-07.md`).
Branch `claude/s5-c3` from `claude/new-core-s5-integration` at `4b30862f`.

Every driver was first run by hand against the new `zig-out/bin/mylang` (S5-A: the
`mylang` executable runs the new core for `build`, `run` and `test`), then the gate.

## Steps of `zig build test`

| Step | Decision | Reason |
|---|---|---|
| Guardian whole-tree checks | kept | |
| `test-memory-budget` (`src/memory_budget.zig`) | kept, passes | the new core's runner and test runner import `memory_budget` |
| `src/root_test.zig`, 12 shards | kept | lane C1 retargets it |
| `test/integration.zig`, 6 shards | kept | lane C2 retargets it |
| `test-core`, 8 shards | **added**, passes 413/413 | plan S5-C |
| `test-lang` | **retargeted**, passes | see below |
| `test-lang-gc` | **removed** | `--gc-runtime --gc-stress` retired (S5-D4) |
| `test-value-semantics` (RC and GC runs) | **removed**, folded into `test-lang` | `--value-semantics` retired; the programs are valid under the default semantics |
| `test-legacy-sharing` | **removed** | `--legacy-sharing` and builtin `Cell` retired (S5-D4, front-end A8) |
| `test-guest` (`tests/guest`) | kept, passes 42/42 | already runs through the new `mylang test` |
| `test-docs` (`mylang doctest .`) | kept, passes | |
| `test-doc-coverage` | kept, passes | |
| `test-idioms`: `--self-test` | kept, passes | |
| `test-idioms`: `--compiler` | kept, **fails** | new-core bug, see "Failures that are not this lane's" |
| `test-incremental` (2 runs) | kept, driver fixed, passes | `incremental_diff.py` dropped every source when `TMPDIR` lay under a `.mylang-cache`; it now tests the path inside the copied project |
| `test-interfaces` (3 runs) | kept, passes | front end only |
| `test-agent-usefulness` (3 runs) | kept, passes | |
| `test-cache-isolation` | kept, **retargeted**, fails until S5-B | the build-cache assertion looked for `*.o` files (old cache layout); it now asks for any published file. Its first command, `test --no-cache`, is refused until S5-B ports `--no-cache` (S5-D6). With `--no-cache` stripped, every other assertion passes on the new core |
| `test-selfhost-numeric` | kept, **retargeted**, passes | `run_lexer_diff.py` built with `--backend qbe`, a retired build control; it now names no back end |
| `test-spec-merge` | kept, passes | |
| `test-runtime-identity` | kept, passes | `build_qbe_assets.zig` still supplies the compiler identity `src/core/frontend_reuse.zig` reads, until S5-D |
| `test-affected-selection` | kept, **retargeted**, passes | `scripts/affected_tests.py` ran a `tests/lang` entry under `--gc-runtime --gc-stress`; it now runs it at debug and at release with `--verify-facts` and `MYL_CORE_LEAKCHECK=1`, like `test-lang`; the `test-native-boundary` mappings went |
| `test-inputs-coverage` (3 runs) | kept, passes | |
| `test-module-compile` (7 runs) | **removed** (step deleted) | `module_compile_oracle.py` (debug, release), `module_build_oracle.py`, `module_check_oracle.py`, `module_test_oracle.py` and `module_build_diff.py` (2 runs) compare the old back end's per-module `compile-module` records, builds and checks, under the retired runtime flags, with its whole-program build. Every program's reference fails on the new `mylang` (`reference_failed` 339 of 339). S5-D deletes the drivers |
| `test-native-boundary` (2 runs) | **removed** (step deleted) | runs every shape through `mylang invoke` on QBE and LLVM; `invoke` is retired (S5-D5) |
| `test-llvm-adapter` | removed from `test`, named step kept | passes, but tests only the old QBE-to-LLVM translator |
| `test-native-memory` | removed from `test`, named step kept | passes, but tests only the old C runtime (GC, two-count RC, arenas) |
| C harnesses `native-heap-test`, `native-arena-chunks-test`, `native-cow-test`, `error-trace-abi-test` | removed from `test` | old C runtime only; they stay in `test-qbe` (and `test-native-heap`, `test-error-trace-abi`) until S5-D |
| `test-byte-io`, `test-board-trial`, `test-schematic` roots | removed from `test`, named steps kept | host applications retired (S5-D5) |

Counts (top-level groups of `test`, Guardian counted once): before, 32; after, 19.
Kept 18, retargeted 4 of them (`test-lang`, `test-cache-isolation`,
`test-selfhost-numeric`, `test-affected-selection`) plus one driver fix
(`test-incremental`), added 1 (`test-core`), removed 14 (5 deleted outright:
`test-lang-gc`, `test-value-semantics`, `test-legacy-sharing`, `test-module-compile`,
`test-native-boundary`; 9 detached and kept as named or `test-qbe` steps).

## `test-lang`

Four runs, each a `mylang test DIR` with its own result cache:

| Run | Tests | Result |
|---|---|---|
| `tests/lang`, debug | 1,524 | pass |
| `tests/lang`, `--release --verify-facts`, `MYL_CORE_LEAKCHECK=1` | 1,524 | pass |
| `tests/value_semantics`, debug | 140 | pass |
| `tests/value_semantics`, release, verify, leak check | 140 | pass |

Before the arena retirement the new core already passed all 1,623 `tests/lang`
tests (arena tests included) and all 145 `tests/value_semantics` tests in both modes.

## Arena tests (S5-D3)

`retire_arena_tests.py` deletes the set conformance has excluded since S1: test names
matching `*arena*` and the files `arena_class_escape`, `rc_arena_values` (and
`gc_arena_root_lifetimes`, whose module name matches), in `tests/lang` and
`tests/value_semantics`. The list with each test's spec tags is
`arena-tests-deleted.json`.

- **Deleted: 104** — 99 of the 118 in `tests/lang` (3 whole files, 17 tests) and 5 in
  `tests/value_semantics`. A file's own `main()` calls of a deleted test went too.
- **SPEC bullets deleted with them** (they had no other test): `ARENA-CHUNKS-1`,
  `ARENA-ESCAPE-VALUE-1`, `GC-ARENA-LOCAL-LIFETIME-1`, `RC-ARENA-FRAME-1`.
- **Kept for S5-D: 19** — they pass on the new core, where `with arena():` is a plain
  block:
  - `arena_managed` (9), `arena_scopes` (4), `arena_regions` (5): each holds the only
    primary tag of `ARENA-MANAGED-1/2/5/6/10/11`, whose other tags are `spec-case`
    lines in `src/arena_managed_test.zig` (lane C1) and `test/integration.zig:419`
    (lane C2). Deleting the primaries here fails Guardian unless those lanes' files
    change, so the bullets, these files and those tags go together in S5-D.
  - `rc_dictionary_text_loops::test_owned_text_keys_in_arena`:
    `src/qbe_rc_dictionary_loop_test.zig` (lane C1) asserts the QBE body of
    `frequencies`, which loses its text-slice call without this, its only non-ASCII
    caller (the first gate run caught it).

## `tests/legacy`

`managed_cell.my` uses builtin `Cell`, which the default semantics refuses
(`E_VALUE_CELL`), so it cannot run on the new core; its step is gone. The files stay
on disk for S5-D: `managed_cell.my` holds the only primary tag of `MANAGED-CELL-1`,
which also has a `spec-case` in `src/managed_cell_test.zig` (lane C1).

## Install graph

`board-trial`, `schematic-svg` and `mylang-io` are no longer installed by `zig build`;
`zig build host-apps` installs them until S5-D deletes them. `-Dcompiler-only` is
still accepted (benchmark scripts pass it) and does nothing.

## Failures that are not this lane's

- **`test-idioms --compiler`: a new-core bug.** `ctl_dict_keys` (`return
  len(d.keys()) + len(d.values())`) stops with `internal error[E_CORE_INVALID_IR]:
  invalid Core IR in main b6 %31: ret does not match its signature`; the old core
  returns 4. Reduced: `def main() -> int:\n    d = {"a": 1, "b": 2}\n    return
  len(d.keys())` fails the same way (also `d.values()`). Class 1, for S5-B.
- **`test-cache-isolation`:** waits for S5-B's `--no-cache` (above).
- **`src/root_test.zig` shards (C1)** and **`test/integration.zig` shards (C2)**: see
  the lane report for the failing tests.
- **`test-qbe`, `test-qbe-build`:** fail on S5-A's retirements, not on this lane:
  `golden_parity` replays through the new `mylang` (34 mismatches, C2 retargets it),
  `host_native` calls the retired `emit-project-qbe`, and `qbe_build_test` /
  `qbe_environment_names_test` (C1) expect the old build driver and runtime archive.

## The gate on `claude/s5-c3`

`scripts/build-slot.sh gate -- zig build test --summary all`, final run on the lane
head (build summary in `gate-02-summary.txt`):

- **Wall time 360 s** (no slot wait; a first run before the last fix took 417 s).
  The plan's figure for the old gate is 878 s on `34c73982`. The unit and CLI roots
  still run their old-back-end tests here, so their share will move with C1 and C2.
- 69 of 88 steps succeeded, 16 failed:
  - 8 of 12 `src/root_test.zig` shards: 31 failing tests, all in C1's files
    (`invoke_test`, `qbe_build_test`, `qbe_environment_names_test`,
    `native_variant_policy`, `rc_teardown_test`, `fix_cli_test`):
    `gate-02-unit-failures.txt`.
  - all 6 `test/integration.zig` shards: 128 failing tests (C2):
    `gate-02-cli-failures.txt`.
  - `test-idioms --compiler` (new-core bug) and `test-cache-isolation` (S5-B
    `--no-cache`), above.
- Everything else passed: Guardian, `test-memory-budget`, `test-core` (413/413),
  `test-lang` (four runs), `test-guest`, `test-docs`, `test-doc-coverage`, and the
  incremental, interface, usefulness, selfhost, SPEC-merge, runtime-identity,
  affected-selection and inputs-coverage drivers.
