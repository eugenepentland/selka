# Registered-release combined performance — 2026-09-30

Composed source `5347c9c0d1c63965b687561a11f458c1ecc3361c` passes preliminary
performance acceptance after integrating the canonical registered collection
release helper and the first test-only gate repairs. The final complete gate,
module matrix, fuzz and runtime sweeps remain required. Phase B stays outside
`main`; its approved tip remains `80dd5190`.

The frozen Debug compiler is SHA256
`85fcf4408832492a601306f2ed5453595770fbb681081192d26b99935e0fc255`;
QBE is `90e368d62b838c41cd2ba4bc68ec5d33843ebc661014d2ad40c835dded900d95`.
The fresh tag builds all 58 distinct binaries in 365 seconds. All 258 dev/full/smoke
output pairs match the unchanged accepted GC binaries. All 58 candidate ELF
hashes are recorded in the comparison; the approved GC binary hashes, build
manifest and measurement cache remain unchanged. Source and compiler identities
are frozen throughout the run. The runner explicitly exports
`RC_QUICK_CPUS=2,3,10,11`; root held that pool during measurement.

## Results and controls

| Size | Exact outputs | Rows above 1% versus either A5 control | QBE / LLVM cap passes | New smoke cap misses |
| --- | ---: | ---: | --- | ---: |
| dev | 86/86 | 0 | 43/43 / 43/43 | — |
| full | 86/86 | 0 | 43/43 / 43/43 | — |
| smoke | 86/86 | 6 diagnostic rows | 39/43 / 37/43 | 0 |

Both the original approved A5 rows and the new explicitly pinned A5 replay are
checked. Dev/full enforce the 1% regression limit and 1.3x RC/GC cap on every
backend row. Smoke follows the approved A5 differential-output use, reports all
movements and permits no new cap miss. Maximum dev/full increase is LLVM Lox
instantiation at +0.792444%/+0.887008%. Dev geomeans are QBE 1.051430 and LLVM
1.051728; full geomeans are QBE 1.049719 and LLVM 1.047553.

The formerly rejected full LLVM text-operations row falls from +1.167106% to
+0.572385% versus approved A5 (+0.572377% versus the pinned control). Its three
new fixed-program samples are 1,352,857,110 / 1,352,857,077 / 1,352,857,054
instructions at dev/full/smoke. QBE full text operations improves by 1.790452%.
These are the initial samples of the new source, not selected replacements for
any rejected source measurement. The old rejected receipts remain unchanged.

The helper removes the redundant identity probe only for the collection caller
whose registered binding already holds a retained canonical shape. The public
source-shape lookup and all walker guards, slot clearing, O/H accounting and
traversal/death order remain intact. The [source and native receipt](wp-b3-registered-release-2026-09-30.md)
records the proof and executable coverage. Address-dependent occupied lookup
misses were demonstrated in the previous source; attribution of its entire
2–4 million-instruction variation remains explicitly unproven.

The six smoke increases remain visible: LLVM invocation +1.870899%, properties
+2.554368%, string equality +2.475680%, trees +2.917837%, zoo +2.172518%, and QBE
string equality +1.252704%. The same six rows exceed 1% in the previous
composed checkpoint; this helper does not resolve those movements. All 86 rows, including improvements and smaller
movements, are retained for each size in the comparison.

## Durable evidence and outstanding validation

The [receipt](evidence/codex-next-runtime-20260929/registered-release-combined/receipt.json)
records 28 copied raw artifacts with byte lengths and SHA256 digests, including
all candidate measurements, exact runner/comparator, frozen binary digests,
original A5 rows, pinned A5 replay and its runner, accepted GC verification and
the root's 40-member/39-pin-run test-repair archive verification. Every copied
artifact and all 58 measured candidate hashes were rechecked by root.

The source helper's 106-member raw package is also verified independently by
root. The first gate repair fixes the original 14 assertions, and the independent
native review executes 15 cases in each control/candidate under Zig-Clang and
GCC UBSan (60 executions). Final integration must still include the strengthened
SSA/journal assertions, the complete 27-step gate, fresh full measurement,
100-seed fuzz, four Lox project builds, 29-program byte oracle and four runtime
module matrices on one frozen source. This preliminary pass does not close
Phase B or authorize a main merge.
