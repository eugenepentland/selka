# EDA friction repair plan for mylang

Prepared 2026-09-30. This is a proposed implementation plan, not a record of
completed repairs. It covers every finding in the completed EDA port's
[friction report](/home/epentland/ai/canopy/eda-bench-wt/codex-next-eda-integration-20260930/mylang/FRICTION.md), including the smaller naming,
array-inference and cache-projection findings. The aim is to remove repeated
application plumbing while preserving independent values, explicit capabilities,
checked errors and predictable evaluation order.

The completed application passes 319 fresh tests, including all 279 original
obligations, and matches 34 reference cases. Its compiler source is `e88fcf3c`;
its existing timing evidence uses Debug. Compiler review branch
`codex/next-eda-compiler-20260930` was at `c06f56bd`; EDA review branch
`codex/next-eda-integration-20260930` was at `c7e119c`. Compiler main was observed
at concurrent `5041d690`; Phase C is not merged into main. These are starting
snapshots, not a claim that their combined source has passed a gate.

## Priorities and order

| Order | Work package | User benefit | Main risk |
| --- | --- | --- | --- |
| 0 | Establish a qualified ReleaseFast baseline | Measure normal compiler use and preserve concurrent work | Comparing different sources or cache states |
| 1 | Diagnostics and name resolution | Invalid source gives an actionable located error | Accidentally masking real compiler defects |
| 2 | Record defaults | Remove repetitive default factories | Shared mutable defaults and stale cached constructors |
| 3 | Option and literal inference | Remove typed-temporary and append-loop workarounds | Unsound narrowing or changed evaluation order |
| 4 | Mutation of nested values | Replace copy/mutate/store-back with one call | Ownership, overlapping arguments and invariant handling |
| 5 | Callbacks with explicit state | Replace application-specific context sorts | Effect checking and stable ordering |
| 6 | Standard-library support | Reuse formatting, parsing, hashes and bit conversions | Silently changing Python or source-Zig semantics |
| 7 | Filesystem operations | Enforce read limits and implement real file operations | Grant escape, races and partial publication |
| 8 | Concurrency and read tracing | Restore the remaining source-runtime guarantees | New runtime ownership and task lifetime rules |
| 9 | General intrinsic projection | Make future standard wrappers cache-safe | Trusting user-authored cache text |
| 10 | Reduce measured compiler overhead | Shorten check and cached-test turnaround | Unsound reuse and misleading measurements |
| 11 | Simplify EDA and qualify the combined result | Prove the improvements work in a real application | Losing coverage while removing helpers |

Work packages 2, 3 and 4 change language behavior and require updated specification
rules. Their semantics below are proposals. Noncapturing lambdas, active-name
shadowing rejection, value semantics and explicit authority remain the starting
design. The callback work supplies explicit state, as the accepted lambda ADR
already recommends. Filesystem concurrency is a separate substantial milestone.

## 0 Establish the source and ReleaseFast baseline

Prepare an owned candidate branch from current main and the completed Phase C
repairs, preserving concurrent cache work. Qualify that exact combined source
before using it as the repair baseline; the e88 receipt cannot qualify a merge.
Keep the original dirty checkout untouched. Installing or testing a new compiler
uses `-Doptimize=ReleaseFast`, an immutable prefix, owned cache/temp paths and the
absolute build-slot wrapper. Guest `--release` remains a separate setting.

Record the same 12 EDA development-loop metrics, plus a focused module check and
an unchanged cached-test command. Retain compiler/QBE/runtime hashes, commands,
cache-hit counts, fresh test names, CPU affinity, SMT activity, admission delay,
package temperature and machine load. Use repeated baseline/candidate samples
under comparable conditions; at least three per metric to expose variance,
with more when the claimed improvement is within the observed noise. If machine
load is uncontrolled, label results descriptive and reserve comparisons for a
suitable run. Never reinterpret the earlier Debug sample as ReleaseFast.

Done when correctness passes on one frozen source and a repeatable ReleaseFast
baseline exists. Its profile and variance determine the subsequent speed targets.

## 1 Diagnostics and name resolution

Reduce `set[bytes]()` and the adjacent unsupported typed-constructor forms to
regressions. Reject them with a source span, a stable diagnostic code and the
valid typed-local/`set()` spelling. Exercise `check`, `check-module`, build, native
test and generic/module-cache paths. Keep genuine internal invariant failures
visible; a blanket catch-and-relabel of `InternalError` is not a repair.

Fix the private `str` writer collision by making ordinary callable lookup honor
a valid lexical declaration before dispatching a shadowable prelude conversion.
Keep type-annotation lookup distinct. Audit the corresponding bytes/repr and
other prelude routes for a consistent documented rule; genuinely reserved names
must be rejected at declaration, rather than accepted and later called as an
unrelated builtin. Preserve normal unshadowed conversion behavior.

For E_SHADOWING, identify both declarations and offer a valid rename. Verify
loop/comprehension bindings leave scope correctly; correct stale-scope false
positives while retaining rejection of a genuinely active name. The plan does
not make binding behavior depend on an optimizer's liveness analysis.

Done when the G25/G26 repros have predictable behavior in every checking route,
valid constructors still work, and the remaining deliberate naming rule has
precise diagnostics and documentation.

## 2 Record defaults

First repair immutable literal defaults: bytes and float literals, including
negative zero, and then support typed enum/module constants. The current parser
accepts only integer/bool/unit/text and negated integer defaults, while the
record guide advertises byte literals; reconcile implementation and examples.

Add record-field initializer recipes for empty lists/dicts/sets, arrays and
pure value-record construction. Each omitted field produces an independent
value per construction; no shared writable default, captured caller local,
ambient I/O, authority-bearing resource or arbitrary effectful call is allowed.
Check every initializer against its declared field type and retain invariant
checks. This proposal expands record defaults; it does not silently adopt
Python's shared mutable function-default behavior.

Permit required record fields after defaulted fields for named construction.
Positional arguments still bind a declaration-order prefix, without skipping
fields; unsupplied required fields remain errors. Preserve the record layout.
Carry default recipes in interfaces and cache identities so changing a default
invalidates dependent constructor uses.

Done when representative EDA factories for byte strings, enum choices and empty
collections become direct construction, and two independently constructed
records stay independent after mutation under RC, GC and both backends.

## 3 Option and literal inference

Propagate an expected element type into collection literals and comprehensions,
including `list[Option[int]]` with a None-only body. Context-type a literal
compared with a fixed array in either operand order, without checking or
evaluating either expression twice. Retain clear errors for genuinely ambiguous
expressions and incompatible lengths or payloads.

Allow `assert local is not None` to refine its normal continuation. Extend
presence facts to stable field paths rooted in value-record locals. Facts must
be invalidated by replacing the root, writing the path or its ancestors,
relevant mut calls, loop writes and control-flow joins. Keep mutable heap aliases
and unstable indexed paths conservative. Ordinary and symbolic generic checking
must share these rules; Result handling and owned-payload obligations remain.

Done when the actual None comprehension, array comparison, assertion and
record-field guard repros compile directly, while mutation/alias counterexamples
still reject unsafe payload reads or retain checked wrapper access.

## 4 Mutation of nested values

Support `callee(mut state.child)` and provably stable indexed value slots,
including records and fixed arrays. Use the existing place/rebuild machinery
rather than passing an untracked interior pointer. Implement correct
copy/call/write-back lowering first; optimize copies only with a separate proof.

Evaluate receivers and indices exactly once in source order. Preserve by-value
snapshots held by other arguments and locals, runtime lifetime/trap cleanup,
parent and child invariants, and write-back to the original assignable place.
Reject paths invalidated by later argument evaluation. Extend MUT-EXCLUSIVE
place checks to reject parent/child and uncertain same-container overlaps;
provably disjoint fields may be passed together. Do not weaken exclusivity.

Test nested records with managed fields, list/dict slots, arrays, two disjoint
fields, overlapping paths, later side effects, snapshots, invariants and arena
escapes under RC/GC and QBE/LLVM, including cached cross-module calls.

Done when real EDA builder/state calls use one marked call and the former
three-statement workaround can be removed with identical output and ownership.

## 5 Callbacks with explicit state

Add stable standard-library sort functions that take a context value and a
named callback, matching the actual `support_sort.sort_by_ctx` use case.
Provide comparison and ordered-key variants; compute keys once per element in
input order. Context is an ordinary explicitly passed value, with enforced
callback effects and ordinary value semantics. Retain noncapturing lambdas and
avoid introducing hidden closure environments.

Test equal-key stability, byte/str/float keys, the existing NaN policy, managed
context, generic callers, effect rejection and module/interface cache reuse.
Use native sort support where its contract fits; benchmark any guest fallback.

Done when EDA's context-dependent sorts use supported APIs and the application
can drop its bespoke sorting implementation without changing ties or results.

## 6 Standard-library formatting parsing hashes and bits

Provide reusable APIs for SHA-256, explicitly specified CRC-32 and signed/unsigned
bit-preserving conversions. Validate hashes against independent published
vectors and boundary inputs, not only against the ported implementation. Cover
empty, large, invalid UTF-8 and NUL-containing byte payloads.

Add explicit formatting policies and hexadecimal-float parsing. Preserve normal
Python-style formatting and correctly rounded parsing. Put exact pinned-Zig
formatting/parser behavior, including its observed rounding quirks, behind a
clearly named compatibility API/module. Source-language compatibility is not a
reason to silently change the language's ordinary conversion semantics.

Keep the existing 300,012-value float-format corpus and 564-input hex differential
as compatibility witnesses, with independent edge cases for signed zero,
subnormals, overflow, ties and invalid input. Decide policy names and failure
contracts before adding public APIs.

Done when EDA imports supported modules through small adapters; handwritten
hash/format/parse algorithms disappear from application production code while
all original assertions and support-test coverage remain.

## 7 Filesystem operations and safe publication

Start with bounded reads that enforce the byte ceiling while reading, before
allocating the complete file. Cover changing/unknown size, exact limits and
streaming inputs. Add stat and entry-kind results, explicit follow/no-follow
policies, rename and atomic file replacement through existing Filesystem grants.
Read-only attenuation, cross-directory permissions, cleanup on refusal and
provider/ABI versioning must be part of each operation, including memory-provider
behavior and an explicit Unsupported result where a provider lacks a guarantee.

Define atomic replacement and crash durability separately. Implement an explicit
transaction with finish/cancel semantics, flush/sync policy and cleanup of
abandoned temporary files. Add symlink inspection/creation only through explicit
authority; directory traversal must stay anchored to the granted root through
concurrent replacement, rather than relying only on string-prefix checks.

Use the original source-Zig filesystem assertions as a behavior inventory.
Restore entry-kind filtering, real bounded reads, secure traversal and atomic
publication in EDA as the relevant APIs arrive. Add denial, failure-injection,
symlink-retarget and race tests with controlled synchronization.

Done when those D4 operations execute and test their actual guarantees instead
of returning Unsupported or checking an already allocated whole-file buffer.

## 8 Concurrency and read tracing

Specify the task model before adding spawn, Mutex or Condition methods. The
proposal is explicit task authority, per-worker runtime ownership and explicit
transfers of permitted values. Ordinary RC/GC/COW state must not cross a thread
boundary as unsynchronized shared storage. Resource/capability transfers need
an explicit rule; arena-bound values cannot escape. Shared synchronization
handles need defined ownership, shutdown and error behavior.

Implement actual wait/signal/broadcast semantics and task-scoped read-trace and
cache-probe sessions with owner checks. Bind traces to the bytes and filesystem
identities actually consumed, including negative dependencies and directory
observations. Validate the original child-directory, ABA, symlink-retarget and
wrong-owner scenarios; a later metadata comparison alone is not evidence of
what was read earlier.

Done when EDA's bookkeeping placeholders can become real synchronization and
trace operations and the corresponding original scenarios pass faithfully.
This is a runtime architecture milestone, not a small filesystem wrapper.

## 9 General projection of private standard intrinsics

Keep the currently repaired sin/cos/sqrt behavior and regression tests. Add a
general route for compiler-authorized standard declarations whose retained
bodies need private operations. Validate projected facts against the exact
embedded standard source/declaration and compiler/interface version, then
resolve intrinsic operations internally. Cached paths, source filenames or
self-declared trust flags alone must never grant private-name authority.

Test ordinary, generic, evaluated and cached routes; source/comment/default
edits; tampered and stale caches; own-module versus whole-program checks; and
native QBE/LLVM execution. Record fallback reasons and ensure unchanged valid
modules do not silently lose incremental reuse.

Done when future small standard wrappers safely resolve private operations
with incremental reuse, and forged user/cache text still receives the private-name
diagnostic.

## 10 Reduce measured check and cached test overhead

Profile the ReleaseFast baseline by discovery, source validation, frontend,
interface/dependency planning, object/link work, test enumeration and result
reuse. First address duplicate project walks, repeated frontend/dependency work
and redundant cached-test preparation where the profile proves they dominate.
Preserve content and transitive dependency validation, embeds, compiler/runtime
identity, effect/ownership facts and test-implementation invalidation.

Measure cold/no-op/clean and leaf/hub/interface edits separately. Publish fresh
versus cached test counts and command overhead alongside wall time. Introduce
an invalidation matrix for source, interface, defaults, assets, missing files,
compiler/runtime changes and damaged cache entries. A stale fast answer is a
failure, not an improvement.

Done when the identified overhead is reduced in repeated ReleaseFast samples,
with unchanged outputs and fresh-test selection. Agree quantitative targets
from the baseline/profile before accepting the optimization; report variance
and any tradeoff instead of assigning Debug cost to normal future use.

## 11 Simplify the application and qualify the result

After each capability ships, simplify representative EDA uses and then the full
port. Keep every 279 original test obligation and the complete previous
support/property/rotation coverage. Replace the D4 tests that only documented
Unsupported with faithful assertions for the now-available operations. Track
which helpers, factories, typed temporaries and copy/store-back sites disappear.
Update the guide, gaps, runnable examples and public feature coverage.

Freeze one combined compiler source and ReleaseFast installation for the final
qualification. Run the required broad compiler targets, affected native/runtime
checks, fresh guest runtime modes, both Lox runtimes and 100-seed fuzz, followed
by the full compiler integration/performance gate for the combined changes.
Keep the existing GC-stress findings explicit; any new divergence is a failure.
Every behavior change carries its spec rule and regression; Guardian exemptions
or snapshots are not a substitute for a repair.

EDA acceptance requires build/check/test/fmt, strict original correspondence,
all 34 byte-identical cases, guide examples, map/counts and the final 12-metric
ReleaseFast record. Retain exact identities, commands, logs, actual named test
outcomes and independent witness review. Commit Guardian feedback in its own
repository after work that exercises the gate. Main integration follows the
existing explicit-approval rule after the concrete result is reviewable.

## Suggested agent ownership

When implementation is requested, use one coordinator plus at most three workers.
The coordinator owns integration, qualified pins, timing CPUs and final evidence.
One compiler worker performs diagnostics/defaults/inference/mutation in sequence;
these overlap parser/checker and ownership files. A library worker owns callbacks
and compatibility APIs. An I/O worker owns capability/provider work, then the
separate concurrency design. Bounded reads and entry-kind APIs can start as
soon as the baseline exists; secure publication and concurrency follow the
basic capability contract. General intrinsic projection needs a scheduled
compiler interval rather than concurrent edits to the same checker/cache files.
Profiling and gates run under the shared admission/CPU rules; independent source
work may proceed while another lane validates its frozen checkpoint.

Each work package reports the before/after EDA expression, remaining workaround
count, specification decisions, negative tests and measured iteration cost.
Concurrency and language-rule changes remain explicit proposals until accepted
as part of implementation; this document itself implements none of them.
