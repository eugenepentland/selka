# Lox scalar lookup and read probes, 2026-10-02

The overlay starts from the unchanged `apply-lox.sh --optimized` port at
`bbefb77f`. It builds with the frozen audited ReleaseFast main compiler
`45d05b55…`, without compiler or runtime changes.

`heap.instance_member` reads an instance's field and, when absent, its class's
method while the runtime remains read-only. Its result contains only Lox
values or tag-only failure cases. VM invocation/property reads and tree
property reads receive that scalar result before performing any mutation or
allocation, so no instance/table snapshot spans the call or binding operation.
The helper shares the one name hash across field and method probes. Fields,
including nil and false, continue to shadow methods. Inherited methods remain
in the existing class table.

The tree setter uses the existing indexed heap setter after evaluating the
RHS. Its initial instance check returns an object reference, and its second
check reads the original stack receiver after the RHS; neither retains stale
fields. Tree `super` and initializer reads use the already-established scalar
class reader. Existing `class_method` checking order is retained, including
its internal class-kind assertion before reading the name's hash.

`table.get` uses a read-only probe that skips tombstones and returns the
matching value directly. Insert/delete still use the existing insertion probe
and its first-tombstone rule. Bounds, overflow, and type checks remain enabled.
The new table regression covers a colliding chain that wraps from the final
slot, deleted slots, nil and false values, missing keys, overwrite and reuse.
Two driver regressions cover field shadowing an inherited method, saved
receiver identity, later mutations, allocations, and Lox collection stress.
Existing RHS mutation/rebinding regressions continue to cover the setter.

## Qualification

The final overlay replays byte for byte onto a freshly copied unchanged
optimized port. All **68/68 port tests pass on each backend** with native GC
stress, LLVM O3/full LTO or QBE ReleaseFast. This includes the baseline's 65
tests and three additions. The preexisting Lox stress test and the new stressed
receiver test exceed the test runner's default step budget; the successful
runs use `--max-steps 1000000000 --timeout-ms 120000`. No semantic/check limit
is relaxed in performance builds.

The initial variant also passed all **104 smoke executions with exact stdout
and matching Lox allocation/collection/freed/live statistics**. A completed
120-run median-three CPU16 instruction diagnostic found these ratios against
the unchanged port at calibrated tree input sizes:

| Engine/case | LLVM candidate/control | QBE candidate/control |
|---|---:|---:|
| VM binary_trees | 0.956× | 0.974× |
| VM fib | 0.979× | 0.994× |
| VM invocation | 0.848× | 0.910× |
| VM method_call | 0.874× | 0.931× |
| VM properties | 0.822× | 0.898× |
| Tree binary_trees | 0.868× | 0.923× |
| Tree fib | 0.998× | 0.999× |
| Tree invocation | 0.960× | 0.964× |
| Tree method_call | 0.889× | 0.923× |
| Tree properties | 0.956× | 0.958× |

These are preliminary instruction diagnostics, not final acceptance or wall
time claims. They measure the initial wrapper variant, before restoring the
existing class-kind check order. Its binaries remain immutable for the root
audit's central comparison. Final binaries use separate `final-*` filenames;
the parent task qualifies the combined final overlay on its reserved CPUs.
An additional final-only counter sweep was stopped because the central
qualification supersedes it; its partial receipt is not acceptance evidence.

The complete final RC/Lox-GC-stress and native-GC-stress replay of all 13 smoke
scripts and all 23 historical diagnostics per engine is running separately.
Its receipt records full stdout/stderr/status and checks executable hashes.
Guardian was not invoked by these frozen-compiler source-only builds; the
parent task records its compiler/gate runs in consolidated Guardian feedback.

## Reproduction

Use a new private work directory; neither script replaces existing binaries:

```bash
repo=/absolute/path/to/worktree
work=/absolute/path/to/fresh-scratch
compiler=/absolute/path/to/frozen/mylang
"$repo/docs/audits/d9-stage3d-migrations/apply-lox.sh" "$work/control" --optimized
cp -a "$work/control" "$work/candidate"
patch --batch -d "$work/candidate/lox/benchmarks/lox/ports/mylang" -p1 \
  < "$repo/experiments/lox-perf-improvements-20261002/lookup.patch"
mkdir -p "$work/tmp" "$work/bin" "$work/reference/benchmarks/lox"
cp -a "$work/control/lox/bench" "$work/reference/benchmarks/lox/bench"
python3 "$repo/experiments/lox-perf-improvements-20261002/lookup-build.py" \
  --work "$work" --compiler "$compiler" --runtime rc
python3 "$repo/experiments/lox-perf-improvements-20261002/lookup-build.py" \
  --work "$work" --compiler "$compiler" --runtime gc
TMPDIR="$work/tmp" "$repo/scripts/build-slot.sh" build python3 \
  "$repo/experiments/lox-perf-improvements-20261002/lookup-validate.py" \
  --work "$work" --out "$work/validation.json"
```

Native GC stress is selected through `MYLANG_OPTIONS=--gc-stress` on artifacts
built with `--gc-runtime`; the Lox stress flag remains a guest argument.
Reference-counted artifacts exercise Lox stress with their normal checked RC
runtime. The build script records exact commands, compiler/executable hashes,
source hashes, separate caches/logs, and slot admission. Measurements use the
existing `experiments/lox-performance-audit-20261002/audit.py` harness with
explicit control/candidate arms, uninstrumented RC artifacts and exact-output
checks.
