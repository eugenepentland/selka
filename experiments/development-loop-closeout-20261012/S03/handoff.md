# S03: independent scalar text boundary

C0: `fbfcaa7a923186a8e773c3760f81c10aa345a432`.
Implementation SHA: `250fce286ed802739549b189ea5378aaa6d6b9b4`. Normal commit hooks passed all 88 Guardian checks.

## Owned files and integration

New native root: `src/text_scalar_root_test.zig`. Existing production modules,
test modules and oracle files are byte-for-byte unchanged. Exact claimed test
imports are `src/number_text_test.zig` and `src/format_spec_test.zig`; communicated
to coordinator, S07, S04 and S10 before moving. Coordinator authored the two
`guardian.toml` root additions in this worktree after the normal commit hook
rejected the initially unregistered root. No Guardian feedback was requested or
written. Shared build/root/selector changes are in `coordinator-wiring.patch`,
not applied here. `make_patch.py` regenerates that patch against C0.

Apply the patch serially after cherry-picking implementation. It registers
`text_scalar_unit`, provider `text-scalar-units`, and focused target
`test-text-scalar-units`; removes exactly the claimed imports from the broad root;
adds the root to input coverage; maps every closure path (including both oracle
files) to the new target in affected-tests; and adds focused wrapper target
`text-scalar`. Existing tooling root and filtered unit-root behavior remain.
Unfiltered units, sharded units, runtime audit, full gate and test-compile include
the new executable. The new run uses its own artifact plus declared input and
live-environment manifests, avoiding cached()/bounded() compiler/component
inheritance. Final shared configuration fingerprint review belongs coordinator
and S04; no automatic qualification update is proposed.

## Closure and inventory

`inventory.json` exports each native root's direct imports, named tests and
embedded files: broad units, Core, CLI, existing pure tooling and new scalar text.
The existing broad roots are deliberately retained: unit fixtures include guest
runtime/compiler, selfhost seeds/components, repository fixture trees, docs and
velocity; Core inherits units plus test/tests/examples/bench/selfhost/velocity;
CLI imports compiler options/components and reads src/examples/guest/fixtures.
Their broad closures are not falsely narrowed by this change. Core IR/runtime
splitting and CLI extraction would duplicate compiler compilation or cross
active ownership, so no additional tiny executables were created.

The proven independent closure is exactly seven repository files:

- `src/text_scalar_root_test.zig`
- `src/number_text.zig`
- `src/number_text_test.zig`
- `src/number_grammar.txt` (embedded)
- `src/format_spec.zig`
- `src/format_spec_test.zig`
- `src/format_spec_cases.tsv` (embedded)

Every import in that closure is std or one of those source files. There are no
subprocesses, guest builds, runtime sources, ABI/seed imports, generated options,
or live repository reads. Pinned Zig/std, target ABI, optimization mode,
Guardian runner/diagnostics implementation and the shared build recipe remain
execution/producer inputs. A filename does not substitute for authenticated
producer identity: S04 owns its qualified contract and broad fallback.

There are eight named tests, exactly the existing three number grammar tests and
five format tests, plus one unnamed import-root test. Named test inventories,
source hashes and the unchanged 115 grammar/7,754 format oracle rows are exported
in `inventory.json` and `oracle-counts.json`. Removing the existing number import
wrapper and introducing the new wrapper preserves total wrapper count. Modules
have no inline tests in production implementations. Final runtime inventory
parity across all integrated binaries remains S10/coordinator qualification.

## Commands and observed results

All native execution used pinned Zig `0.17.0-dev.1683+5ceec001b`, default Debug,
no explicit CPU pinning, private `$PWD/.zig-cache`, disk
`$PWD/.mylang-cache/s03-tmp`, shared global cache
`/home/epentland/ai/canopy/.zig-global-cache`, and `scripts/build-slot.sh build`.

1. `python3 experiments/development-loop-closeout-20261012/S03/audit_boundary.py`
   exited 0; exact seven-file closure and eight named tests asserted. Source
   SHA-256 hashes in `inventory.json`.
2. `scripts/build-slot.sh build zig test src/text_scalar_root_test.zig`
   exited 0; all 9 selected tests executed, 9 passed, no reused/partial tests.
   Raw output: `focused-native.log`.
3. `scripts/build-slot.sh build zig test src/text_scalar_root_test.zig --test-no-exec -femit-bin=.mylang-cache/s03-text-scalar-tests`
   exited 0; emitted direct std-runner Debug artifact size 20,840,376 bytes.
   Raw admission output: `compile.log`. This is operational artifact evidence,
   not the integrated Guardian-runner size or cold timing.
4. `zig fmt --check src/text_scalar_root_test.zig` and Python py_compile of audit
   and patch generator exited 0.
5. `git apply --check experiments/development-loop-closeout-20261012/S03/coordinator-wiring.patch`
   exited 0 against this C0-based tree; patch was not applied.
6. `python3 experiments/development-loop-closeout-20261012/S03/check_fixture_failure.py`
   exited 0. Copied the complete closure to private disk scratch, changed one
   embedded oracle from `int|42|42` to `int|42|43`, and executed via build admission.
   Inner test exit 1: 8 passed, 1 failed with `expected 43, found 42`.
   Raw output/status: `mutated-oracle.log`, `mutated-oracle.json`. The octet test
   asserts Unicode/octet implementation parity, so it correctly still passes.

Artifact SHA-256: `c1b71eb6d6eabab0091c106c7ac58f581f6118c9df020e2c8024fe8b430f75cf`.
Pinned Zig executable SHA-256: `1d314883fd8cf4490c1c29dd73ad8b64e319a8a53c4d9087d1135b52977df37f`.

## Qualification still required

S10 owns paired cold compile/link/RSS, warm and oracle/source/compiler edit
measurements, cache tiers and exact final full gate. None of those timings or
memory comparisons is qualified here. No latency savings or oversplitting
acceptance is claimed from the direct pass. S10 received the exact command,
artifact size, named inventory and fixture row counts. Compiler edits are absent
from the static closure, but producer-level responsible-only reuse requires
S04/coordinator integrated authentication and final configuration review.

After shared wiring: run the Guardian-supported new focused target with full,
matching and no-match filters; ensure no-match fails. Check missing/deleted/renamed
oracle files fail closed (fixed exact manifest entries), fixture changes invalidate
the new group, and added files do not become undeclared runtime inputs. Run input
coverage and focused selector regressions; enforce final 8-name parity and total
wrapper count; repeat complete gate/formatting on frozen candidate. No install,
compiler ownership/lifetime/default-mode or bootstrap changes were made.
