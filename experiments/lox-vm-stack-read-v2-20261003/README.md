# Readonly VM stack equality, V2 (2026-10-03)

This unselected source experiment replaces the V1 helper's call to
`value.values_equal` with that function's existing match body. The selected
control is canonical AST source commit
`37df3ffbfab1f2ea4f269c769eb5b013c5270be3`, using compiler
`d14a704083bcc5f5174932a751f7d9dda73100dbd62403626b42b52436cad040`
and QBE `99ad919d70ad582dee6202b045bd53e1ab18fec356de98849610f49983756d63`.
There are no compiler, native runtime, algorithm, opcode, layout or check changes.
Reference benchmark architecture remains SPEC commit
`4e48a09220c2e018eba8c4b1eb3fe1137a3dae73`.

V1 is frozen in commit `f4d3fbcced87816210732a200aa765366a0ff8cf`.
Root's completed diagnostic screen reported VM instruction counts 0.316509%
lower for LLVM and 0.1494% higher for QBE. It contains 156 behavior/stat
observations and 104 counter cells, with all 416 PMU rates 100%; it has no full
wall matrix and did not select V1. `v1-central-screen.json` retains root's exact
receipt and immutable archive reference. These rows are not additional V2 tests.
V1's mislabeled initial GC build and three-row partial failed native matrix
remain preserved in its own experiment; they are not silently recounted here.

## Source mechanism and semantics

V1 moves the two plain Value reads into `equal_stack(readonly_list, top)` to
give the compiler a readonly list anchor. QBE then calls the helper and the
helper calls `values_equal`. V2 still calls `equal_stack`, but directly matches
its two operands. `package.py` asserts the match equals the `values_equal`
body, changing only operand names and qualifying `value.Value` in module vm.
The public `values_equal` function and its other callers are unchanged.

Both versions read right `stack[top-1]`, then left `stack[top-2]`, through the
existing checked subtraction, negative normalization and bounds checks. The
left tag is matched first after both reads. Nested right tag matches, boolean
comparison, IEEE number equality (including NaN and signed zero), and object
identity remain exact. Interned strings still use identity. The helper has no
allocation, callback or mutation, and the Runtime and stack stay rooted while
it executes. Caller IP publication is unchanged. The caller retires the right
stack root and performs its existing checked/COW boolean write afterward.
Runtime and list snapshots still use their normal ownership and COW protocol.

As in V1, equality is evaluated before right-root retirement. Pure equality
does not expose that move for valid checked Values; the same retirement
subtraction already succeeded during the first read and the helper cannot
change top. Forged invalid union tags are outside checked source/Lox input;
the emitted match defaults return the existing failure value, but private
malformed-state equivalence around retirement is not claimed. Accounted
step-budget traps can occur at different helper PCs before retirement.
Artificially tight native frame/step limits and native source-expanded trace
names are not claimed identical. Removing the nested call also makes this a
leaf helper under the existing compiler rules: QBE no longer emits its
nonleaf native frame-admission test. No admission rule or safety attribute
was changed. Normal Lox error protocol is checked exactly by the native matrix.

## Static evidence, not performance results

Actual checked RC ELF disassembly shows LLVM inlining the helper. Its run
function changes from V1's 5555 instructions/488 call sites to 5549/487.
QBE run stays 8373/433; the standalone helper changes from 126 instructions/
10 call sites to 219/8. All 8 V2 call sites are cold overflow, cast or bounds
failures. There is no successful-path call from the V2 helper.

The new helper conservatively copies both 16-byte plain operands; V1 copied
only the right operand. This materialization is included in the manual static
assembly walks, which use the normal nonnegative/in-range read branches and
each same valid tag:

| Same tag | V1 helper plus nested equality | V2 helper |
| --- | ---: | ---: |
| nil | 51 | 47 |
| boolean | 63 | 59 |
| number | 72 | 68 |
| object | 71 | 67 |

These are traversed machine instruction counts from static disassembly, not
executed instructions, PMUs or wall timings. `static.py` reproduces the
explicit branch choices and instruction addresses in `static-replay.json`.
Diagnostic IL also shows only 8 failure calls and no helper dependencies. It
has two blits, compared with V1's one. IL emission alone uses dropped frame/
step accounting flags; actual qualification builds retain native checks.
The lane ran no performance measurements. Root owns candidate selection.

## Bounded correctness qualification

The frozen source has 37 files and 86 public tests: V1's two new equality/host
snapshot regressions are retained byte-for-byte. The standalone patch changes
only vm.my, driver_tests.my and its two driver provider entries relative to
selected AST control. Only vm.my changes relative to qualified V1.

Four fresh public runs pass 344 tests, with zero cached, failed, skipped or
dropped tests. LLVM uses `mylang test --release`; QBE uses `--mode ReleaseFast`.
Each backend has RC and native GC-stress test modes. These accounted tests
use the established 1e9-step/120000ms limits and private caches.

Distinct actual native builds select `--rc-runtime` or `--gc-runtime`
explicitly. LLVM release guests use O3/full LTO. Native qualification has 348
exact VM comparisons: all 23 historical diagnostic/error cases, four bounded
corpus smokes, and the two equality regression programs, across both backends
and RC/ordinary GC/native GC stress, each with Lox GC normal/stress. All
status codes, complete stdout/stderr and collector stats equal the selected
AST control. Full raw observations are retained compressed. This is not a
full thirteen-case native corpus/tree matrix or RC-stress refusal suite.
The host snapshot fixture runs in the public suite; its standalone Lox
comparison/allocations are also covered natively. The combined completed
coverage is 692 checks. No cached or historical failure rows are included.

The initial V2 match copy omitted the `value.` namespace in its case type;
diagnostic emission failed with `E_UNKNOWN_SYMBOL` before any guest build.
Its exact 37 hash map, rejected vm.my, stdout/stderr and status1 receipt are
retained. Corrected source and emission have distinct metadata and paths.
The first source's original directory was relocated to `namespace-rejected`;
`emission-receipt.json` records original and current paths explicitly.

## Reproduction and immutable paths

Read `source-hashes.json`, `builds.json`, `qualification.json`, and
`static-evidence.json` for exact source/compiler/QBE/guest/runtime-object and
sidecar identities. Working sources/guests live under
`/home/epentland/ai/canopy/mylang-worktrees/codex-lox-vm-stack-read-20261003/.tmp-lox-vm-stack-read-v2-20261003`.
Final source is `inline-qualified`. Actual guests are
`qualified-inline-{llvm,qbe}-{rc,gc}`. Earlier V1 artifacts remain untouched.

Reconstruct the selected control using `apply-lox.sh PRIVATE_DIR --optimized`
in a baseline worktree pinned to `37df3ffbfab1f2ea4f269c769eb5b013c5270be3`;
current canonical worktrees may contain later overlays. Then run
`python3 -B prepare.py BASELINE_PORT EMPTY_DESTINATION`. It applies the
standalone patch and verifies all 37 final hashes. Recipes `build.py`,
`test.py` and `validate.py` run through shared build slots or a CPU16 host
launcher with private caches/TMPDIR, excluding reserved timing cores. For a
fresh replay, change their private work prefix rather than overwrite the
frozen receipts or ELFs. `package.py` performs host-only identity/assertion
checks and packs evidence; it does not launch compiler/guest tests or timings.
