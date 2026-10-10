# First source-shaped typed construct — October 9, 2026

Phase 5 introduces one source-shaped checked family, `range_loop`, for source
`for ... in range(...)`. Its owned plan keeps binding/source endpoint spans,
checked endpoint stores, runtime stride setup, condition/body/step and target
identity together. Previously the checker returned a synthetic block containing
two synthetic endpoint initialization statements and a synthetic generic loop.
Core now directly lowers the range endpoint stores and setup in their previous
order, then invokes the unchanged loop lowering. Checked stepped-range sign,
zero-step and wrapping-overflow plans, exit targets, integer type/endpoint checks,
induction facts and ownership obligations stay intact. Core IR schema is unchanged.

The tagged payload owns one slice element; ordinary and specialization persisted
validation reject any other cardinality. All live typed consumers were audited:
ordered walking, Core lowering, readable role-labeled dump, duplicate fingerprints,
origin propagation, effects/freshness facts, synthetic-local stores, navigation
write edges, quality decision tracking and lint traversal/conditions/sentinel facts.
Generic slice-based persistence/copy/remap already traverses the plan recursively.
Semantic durable schema is bumped once, v3 to v4; active cache docs and CLI test
constants are reconciled. Historical evidence namespaces are untouched.

The size probe copies the prior `Statement` schema from starting HEAD cf7c620dc
and measures both with pinned Zig. Initial naive by-value storage would grow every
statement; an intermediate partial boxing still grew 80 to 88 bytes. Both were
rejected during development. Final boxing keeps `typed.Statement` at **80 bytes**;
one `RangeParts` is **120 bytes**, and its tagged payload is **16 bytes**. Each range
removes **three 80-byte synthetic statements** plus its old children slice. Ignoring
allocator growth buffers, that saves at least **144 bytes** for an implicit or
constant stride and **160 bytes** for a runtime stride (two setup statements).
Other synthetic expressions/checked step statements remain for the preserved
normalized plan; this is the first construct family, not a full typed-IR rewrite.

There is also a concrete duplicate-validator removal. Concrete
`sema_calls.scopedDirectoryPath` and abstract `generic_bodies.scopedDirectoryPath`
contained the same byte predicate. Both now use `scoped_directory.valid`.
The predicate permits the empty scoped root and UTF-8 components and refuses
traversal/dot/empty components, NUL and backslash. Call-site error codes, messages
and source spans are unchanged. New regressions exercise concrete and unused
generic contexts with empty roots, Unicode, traversal, dot, double slash and
absolute paths. The old predicate tests remain. Symbolic range compatibility,
integer requirements and ownership checks cannot be deleted: unused templates
must still validate without concrete instantiation, and concrete lowering adds
integer-width, induction, zero-stride and overflow facts. Keeping those distinct
obligations is a semantic requirement; the shared directory rule removes actual
duplicated validation without weakening either stage.

Focused validation through build-slot/pinned Zig:

- `0bbfeb740:experiments/frontend-closeout-20261009/range/initial.log`: first compile waited 180 seconds for shared slots, then hit a
  coordinator's concurrent developerFailure error-set syntax edit; corrected
  separately by the coordinator.
- `0bbfeb740:experiments/frontend-closeout-20261009/range/second.log`: 31/33 tests passed. Two existing byte-range noalloc tests failed
  because the new Core allocation bridge classified intrinsic calls as unresolved;
  the effects package corrected the audited allocation-free helper list.
- `0bbfeb740:experiments/frontend-closeout-20261009/range/third.log`: 39/39 range/shared-dir/recovery tests passed, including source spans,
  endpoint/stride walking order, native results and a bounded nested-token mutation
  regression checking every diagnostic span and no published partial AST.
- `0bbfeb740:experiments/frontend-closeout-20261009/range/final-focused.log`: **210/210** range/shared-dir/recovery/semantic/navigation/
  quality/duplicate tests passed after final boxing; 17.98 seconds test wall,
  exit status 0. Includes cached/fresh agreement, relocation, independent ownership,
  allocation failure, generic publication rollback and durable header corruption.
- `0bbfeb740:experiments/frontend-closeout-20261009/range/sizes-final.log`: actual final before/after size proof, exit 0.

The durable corruption regression writes deliberately malformed payloads with valid
checksums. Empty and multiple owned plans become damaged misses; one plan succeeds.
Normal entries and concrete specializations both apply the invariant before any
consumer invokes the exact-one accessor. SPEC primary is `TYPED-RANGE-1`.

Differential evidence compares the qualified immutable compiler SHA
5e072ee17b825cfbd40ed5533c3bce9f166ce4ae576395020cd5e435cc45ed11 to
source-bound closeout candidates. `0bbfeb740:experiments/frontend-closeout-20261009/range/compare.py` enumerates all 86 original
`tests/lang` sources containing ` in range(` and retains every raw Core/facts
command/output, source SHA, compiler SHA, exit and elapsed time. Baseline has
**100 accepted commands and 72 rejected commands** (mostly library sources with
no standalone main); `0bbfeb740:experiments/frontend-closeout-20261009/range/baseline-rejections.json` explicitly preserves rejections.
Against candidate 1, **92 accepted outputs are byte-identical** and eight commands
were newly rejected by allocation contracts, with no different successful output.
Those eight belong to four files: keyed_sorting, stable_sorting,
python_collections and rc_capability_values. Their contract/intrinsic interpretation
was reviewed by the effects package. Final enforcement preserves guest effect
scopes and reverts the attempted generalized allocation ceilings; audited
allocation-free intrinsic classification is corrected. No guest wrapper effect
contracts were widened. Initial rejection evidence remains intact.
Final comparison against immutable SHA
aca89445a3f2d4f2dddbf68b6441c3473374cd37b2e6cde68929e0690def737f
has **100/100 accepted outputs byte-identical** and **72/72 baseline rejection
statuses preserved**, with the same main-source byte hashes in each pair.
`0bbfeb740:experiments/frontend-closeout-20261009/range/comparison-final.json` binds every comparison, including final baseline receipts;
no output text normalization is applied.

`0bbfeb740:experiments/frontend-closeout-20261009/range/llvm_compare.py` compares raw Core, optimized facts and release LLVM plus native
stdout/stderr/exit for loop_rebinding, bounded_loop_ranges, array_negative_index,
rc_scalar_loops and an exact-copy Python-expression library driver. Candidate1
matches all five byte for byte, including stepped directions/overflow, nested
exits, bounds and generic/induction behavior. A sixth explicit probe was rejected
by both compilers for an immutable iteration assignment; its source/commands are
retained. `range_semantics_v2.my` corrects that probe to an explicit mutable copy,
covering side-effecting endpoints, dynamic/descending strides, continue/break,
generic range, u8 overflow and nesting. Both immutable compilers accept its raw Core but reject release facts/build with
`E_CORE_INVALID_IR`: main b7 has predecessor b8 that does not branch to it. This is
an existing release CFG defect, retained in `native-final` evidence and excluded
from successful-probe counts. No Core repair was attempted in this package.

A smaller accepted `range_endpoint_probe.my` retains side-effecting endpoints and
runtime stride, plus ascending/descending generic ranges. Both compilers emit
byte-identical raw Core, facts and release LLVM, and both executables return the
expected **249**: concrete sum16 + generic ascending16 + descending25 + encoded
endpoint log192. Thus **six accepted representative probes** have exact Core,
LLVM and native equality. `native-final` proves the five existing probes against
the final compiler; `native-endpoints` proves the sixth. The original immutable
iteration-assignment and later CFG-rejected attempts remain separate evidence.

`0bbfeb740:experiments/frontend-closeout-20261009/range/dwarf-old-size.log` additionally corroborates the qualified old binary's actual
80-byte typed.Statement debug record at old source line634.

The integrated full gate/source gate and final immutable candidate qualification
belong to the coordinator. Other iteration families remain deferred as required
by the one-family-at-a-time plan. No guest/Core schema, nominality or generic
acceptance rule is changed by this range lowering family.

## Corrected qualified compiler replay

After the integrated gate exposed unrelated UTF-8 cold-diagnostic allocation and
resource-contract issues, the corrected frozen compiler was replayed separately:
`artifacts/mylang-qualified`, SHA256
`21319448ba51241f917c040004d1a3c7123e5516d5f0a766d7cff557294793f2`.
The preceding checkpoint and its receipts remain unchanged. `0bbfeb740:experiments/frontend-closeout-20261009/range/final2.json` and
`0bbfeb740:experiments/frontend-closeout-20261009/range/comparison-final2.json` again prove all 100 accepted Core/facts outputs exact
against old5e and preserve all 72 baseline rejection statuses (172 commands).
`native-final2` and `native-endpoints-final2` again prove exact Core, release LLVM
and native outputs for the six accepted probes. The custom v2 release CFG
rejection remains in both compilers and is still excluded from success counts.
External replay and the corrected 614-file source guard are recorded separately
under `0bbfeb740:experiments/frontend-closeout-20261009/external-final2`.

## Archived full evidence

Full captures and the original version of this report remain in commit `0bbfeb740`,
reachable from `main` and `codex/frontend-followthrough-20261009`.
Retrieve any archived path with `git show 0bbfeb740:PATH` (paths are repository-relative).
