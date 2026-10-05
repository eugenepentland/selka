# S2-0 Wave A evidence, 2026-10-05

Base: `9ee2a484`. Package branch: `codex/new-core-s2-ir`.
This lane implements the frozen IR foundation and dispatch stubs; the coordinator
grades conformance, unchanged S0 kernels/S1 rows, fuzz and coverage after the two
Wave A language packages merge.

All Zig builds used this worktree's `.zig-cache`, disk `.tmp`, the shared global
cache `/home/epentland/ai/canopy/.zig-global-cache`, and `scripts/build-slot.sh`.
The wrapper excluded CPUs 2, 3, 10 and 11. No guest benchmark timings were taken.

## Checks

- `op-tests.log`: 25/25 hand-built operation tests, including LLVM compilation,
  execution of array/function/character operations, precise placeholder traps,
  and invalid operand/result rejection. Test execution: 19 s; compiler rebuild:
  1 s; test binary compilation: 520 ms.
- `array-tests.log`: 2/2 managed-array/owned-indirect-call tests, in debug and
  release with fact verification and leak checks. Both register and `sret`
  results execute correctly. Test execution: 3 s; compiler rebuild: 1 s.
- `array-release-pipeline.log` additionally runs the full release pass pipeline
  in verify mode before compiling the managed indirect-call examples at `-O3`:
  2/2 pass, 14.05 s command wall, 11 s test execution and 2 s test compilation.
- `core-rebuild-final.log`: rebuild after the final source documentation edit,
  4 s core compilation and 4.96 s command wall, including installation, under
  the concurrent old-core gate. `core-install-final.log` shows the cached install
  separately: 24 ms compile-cache check and 0.27 s command wall.
- `test-core-second.log`: 183/183 green at 316.82 s command wall time, while a
  full old-core gate and the coordinator's baseline core suite ran concurrently.
  This exceeds the five-minute limit and is **contention evidence only**, not an
  accepted exit gate. The unchanged baseline also rose from 85 s to about 4 min.
  Compiler/test compilation each took 4 s; admission time is outside the timed
  command. An isolated rerun supplies the exit gate below.
- `test-core-isolated.log`: accepted exit gate, **183/183 pass in 109.55 s**
  command wall after admissions; 140 s gate queue excluded. Test compilation:
  1 s; cached compiler check: 5 ms. Printed missing-file diagnostics are the
  existing negative runner tests and are expected.
- `source-refusals.log`: five CLI builds each exit 1 with the expected
  `E_CORE_UNSUPPORTED` reason and produce no binary; sources are in `refusals/`.
- `guardian-3.log`: whole-tree Guardian all 88 checks pass. The preceding
  1,033 s gate-slot queue is reported separately from the gate's work.

The final core-suite command takes the gate slot as well as the build slot:

```sh
export ZIG_LOCAL_CACHE_DIR="$PWD/.zig-cache"
export ZIG_GLOBAL_CACHE_DIR=/home/epentland/ai/canopy/.zig-global-cache
export TMPDIR="$PWD/.tmp"
scripts/build-slot.sh gate -- bash -c '"$@"; result=$?; exit "$result"' -- \
  scripts/build-slot.sh build -- /usr/bin/time -f 'command_wall_seconds=%e' zig build test-core --summary all
```

Focused tests use `zig build test-core -Dtest-filter='S2 ' --summary all` through
the build wrapper. Guardian uses the gate wrapper. Initial compile/gate and
intermediate test logs are retained to show the development failures and fixes:
allocator-backed signature parameters replaced an escaping temporary; test
expectations retain the existing source refusal reasons; block uniqueness is
limited to block types so value-record updates retain the S1 ownership behavior.
`test-core-first.log` records the record-uniqueness regression before that fix.

## Printed IR and LLVM

`ir-evidence.log` records a successful hand-built evidence run. The `ir/` files
were emitted by the same constructors as `src/core/s2_ir_test.zig`; the LLVM was
compiled and executed before saving. The temporary evidence test root was removed.

| stem | behavior |
|---|---|
| `dict_insert` | layout-independent probe/insert shape; precise unsupported trap |
| `str_char` | ASCII character result |
| `str_view_of` | SSA byte-span construction |
| `array_set` | fixed-array update and readback |
| `call_indirect` | internal function reference and integer call |
| `array_owned_sret` | consumed managed array, independent retained source, aggregate return, nested list cleanup |
| `span_lifetime` | a source consumed before its view's last use, explicit extern span helper, multibyte characters |

Each stem has a `.ir` file and a `.ll` file. The managed examples enable ownership
and emission verification and `MYL_CORE_LEAKCHECK=1`; unit tests compile them at
both `-O0` and `-O3`. Managed-array release tests also run `passes.run(.verify)`;
the saved snapshots use the hand-built helper's ownership pass.
The unit suite also covers copied/tested dictionary probes, view escape/storage
rejections, full function-signature metadata, and array constructor arity/types.

## Scope and refusal contract

Source dicts, byte buffers, fixed arrays, function values and text indexing keep
their prior `E_CORE_UNSUPPORTED` reasons through new builder dispatch modules.
The simple hand-built IR operations execute. Other newly declared operations emit
valid LLVM that calls a runtime placeholder and exits 1 with
`E_CORE_UNSUPPORTED` before any result is observable. Complete dictionary, text,
sort and source-function/array lowering remain Wave B work.

The exact as-built shape and extern-C span admission are documented in
`docs/design/new-core-s2.md` §13. General source string-parameter view ABI remains
subject to user decision 4; it is not enabled here. `ir.zig` freezes only after
coordinator acceptance.

The coordinator discovered that direct nesting of the original wrappers reused
descriptor 9 and dropped the outer gate lease. The command above retains a
waiting parent; explicit scheduling isolated the historical accepted run.
Final aggregate qualification is recorded in `../REPORT.md` and `../integration/`.
