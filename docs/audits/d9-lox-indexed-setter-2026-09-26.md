# D9 Lox instance field updates, 2026-09-26

The optimized VM now passes property updates through `heap.set_instance_field`.
That helper extracts the runtime's object table, calls a private helper with
a mutable list parameter, and stores the list back. The private helper reads
the instance's class id, updates its fields table, and replaces the same
object slot. The VM still evaluates the name, hash and assigned value before
the update, then performs the same stack pops and push.

This source shape lets the guarded indexed-transfer proof use the mutable
list call's existing detachment and pin. It can move the fields table through
the update without retaining an observable snapshot of the old instance.
The compiler proof rejects prior list aliases and alternate entry paths;
the source helper alone is not the optimization.

The source starts at `dd130a99`; it includes the scalar instance reads,
receiver/RHS correctness fix and class-method accessor. The independent
late-closure source change is not included in this isolated measurement.

## Matched measurement

Both sources use the frozen Debug indexed-proof compiler `aa2fcbc6`, based
on `f6b5de09`,
SHA `6e82c879fdeb5a8c1cb337291f444e4a32027ddddaf18b7f61aba4aeaeae3993`.
The evidence records every changed compiler source hash as well as the binary
hash. Guests use ReleaseFast; LLVM additionally uses optimization level 3
and full LTO. The mandated `pc.py` harness checks exact output and takes
median-three instruction samples on CPU 3 at its calibrated Lox sizes.

| VM case | Helper / before QBE | Helper / before LLVM |
| --- | ---: | ---: |
| binary_trees | 0.8892× | 0.7993× |
| closures | 1.0000× | 1.0065× |
| fib | 1.0000× | 1.0175× |
| method_call | 0.9436× | 0.8923× |
| trees | 0.9760× | 0.9562× |

The small LLVM regressions on closures and Fibonacci remain part of the
result. These five cases do not establish the full D9 performance gate.
[Raw measurements](evidence/d9-lox-indexed-setter-perf.json) preserve all
samples and source, compiler, binary, harness and script identities.

On VM binary_trees N10, copies fall from 1,063,200 to 266,502 and copied bytes
from 273,336,509 to 69,381,821. Sharing marks fall from 4,789,583 to 3,727,319.
Checks rise from 16,836,929 to 17,899,193; pins rise from zero to 1,062,264,
one per property update. There are no pinned copies.

An [earlier-compiler control](evidence/d9-lox-indexed-setter-control.json)
uses `5bdd99ea` for both sources. Without the indexed proof, the same helper
preserves copy counts and costs 1.0222× QBE / 1.0113× LLVM instructions on
binary_trees. That compiler also predates the pure-box change, so this is
not a compiler-only attribution across those two compiler snapshots.

## Validation and reproduction

The helper passes all 65 port tests in value mode with the guarded compiler,
and all 65 in compatibility mode with the prepared compiler's explicit
`--legacy-sharing`. All 104 smoke runs cover both engines, backends and
modes. All 184 VM error-trace comparisons cover both backends and modes,
with native GC stress throughout and both Lox GC settings. Value-mode runs
were repeated with the guarded compiler; compatibility evidence retains
the unchanged frozen compiler and binaries.
[Validation evidence](evidence/d9-lox-indexed-setter-runs.json.gz) includes
exact outputs, test summaries and compiler identities. Patch replay
reconstructs every measured `.my` and `.json` file byte for byte. Compiler prerequisite `aa2fcbc6` passes its full gate: 93/93 main steps,
2,116 executed tests, 428 QBE tests, 29 build steps and 2 formatting steps.
It also passes 28 focused tests, 20 snapshot/control guests per backend
under GC stress, and all 44 compatibility IL comparisons. See its
[indexed-transfer audit](d9-indexed-return-2026-09-26.md). The joined
compiler/source full gate remains the integration task.

Reproduction scripts and logs are in `d9-lox-indexed-setter/.tmp-setter/`.
`build.py` and `validate-value.py` run through `scripts/build-slot.sh build
env TMPDIR="$PWD/.tmp-setter" python3 ...`. `measure.py` invokes `pc.py` on
CPU 3. `check-runs-value.py` performs fresh value-mode comparisons and
retains the earlier compatibility observations. `old5bdd/` preserves the
earlier binaries, identity and test/trace results; `measure-old.py` records
the control. `MYLANG_COW_COUNTING=1` is set only when building counter
binaries. Both measured sources are frozen under `before/` and `port/`.
