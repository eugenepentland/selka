# Implemented semantics

Status: M0–M5 complete, 2026-09-05. This file describes implemented behavior, while
[plan.md](plan.md) describes the complete target and future experiments.

- A source file contains named functions and exactly one `main` returning i64.
  It accepts no parameters or one explicit `allocator` capability parameter.
  Statements include `let`, `let mut`, assignment (`=`, `+=`, `-=`), nested
  blocks, `if`/`else`, `while`, `discard`, and explicit `return`. A function must structurally return; statements after
  a terminating return or block are rejected.
- Expressions contain decimal `i64` literals, booleans, local references,
  parentheses, unary negation/not, arithmetic `+ - * / %`, short-circuit `&& ||`, and comparisons
  `== != < <= > >=`. Unary operators bind above multiplication, then
  addition/subtraction, ordering, equality, conjunction, and disjunction. Binary operators associate left;
  operands evaluate left to right. Booleans are distinct from integers; ordering
  requires integers and equality requires matching primitive types.
- Literal magnitudes ordinarily range from `0` through `9223372036854775807`.
  Magnitude `9223372036854775808` is allowed only under direct unary negation,
  ignoring parentheses. Negating the resulting minimum again traps.
- Addition, subtraction, multiplication, negation, and division trap on overflow, with a diagnostic at the
  responsible operator. This is independent of the Zig optimization mode.
- `check` parses and type-checks without lowering or execution; an expression
  that would overflow still passes checking. Out-of-range literals do not.
- Whitespace and `//` line comments are accepted. Identifiers are ASCII.
  LF and CRLF produce correct one-based line/byte-column locations.
- The parser limits combined recursive syntax nesting to 256 levels. Semantic conversion
  and lowering do not recursively traverse the potentially deep left-associative
  expression tree. Lowering uses an explicit work stack.
- The instruction stream is an in-memory tagged union with source spans.
  Local slots retain their types and carry an uninitialized sentinel in the VM.
  Arithmetic pops the right operand before the left operand. Validation rejects
  malformed internal stack shapes as host/internal failures rather than guest traps.
- One compilation request owns its copied source/path, line index, AST, typed
  program, and instructions. Runtime operand, local, and frame buffers are separately allocated
  and released on both successful execution and traps.
- `run` prints the integer result followed by a newline and exits 0. A source
  error or runtime trap prints no stdout result and exits 1. Usage, file I/O,
  allocation failure, and internal failures exit 2.
- `dump-bytecode` prints functions and instructions in deterministic order with
  source locations. It does not execute arithmetic.

- Every binding is initialized; an annotation must match the initializer's type.
  `let` is immutable. A name becomes visible after its initializer, and ceases
  to be visible at block exit. Active local/function names cannot be shadowed;
  sibling scopes can reuse names with independent identities.
- `W_UNUSED_BINDING` reports a binding with no resolved read. Plain assignment
  writes but does not read its target. `W_UNNECESSARY_MUT` reports a mutable
  binding with no assignment after initialization. Warnings sort by source
  position then code, appear only after successful checking, and do not change
  exit status or stdout. Initializers still run and can trap.

- Conditions and logical operands require booleans. Logical operators evaluate
  their right operand only when needed, including within `discard`. Bare
  expression statements are rejected; discard evaluates its operand and keeps
  its traps. Compound assignment counts as both a read and a write.
- Division truncates toward zero; remainder has the dividend's sign. Zero
  divisors trap. Minimum integer divided by `-1` traps; its remainder is zero.
- An `if` terminates only when both branches terminate. Loops always may fall
  through for return analysis, even `while true`. All branches are checked and
  counted for binding warnings regardless of constant conditions.
- `run --max-steps=N` accepts a positive decimal u64 budget, default 10,000,000.
  The VM checks the limit before each instruction dispatch. Budget exhaustion
  is a guest trap at the next instruction's source location. Other commands
  reject execution options. Jump validation checks target bounds and matching
  stack heights at control-flow joins.

- Collect signatures before checking any body. Forward calls and mutual
  recursion are supported; every function is checked even when uncalled.
  Functions accept and return `i64` or `bool`. Parameters are immutable, occupy
  the first local slots, and receive the same unused-binding warning as locals.
  Duplicate functions/parameters, function-name shadowing, wrong arity/types,
  and a parameterized or boolean-returning entry point are rejected.
- Calls target top-level names directly. Arguments evaluate left to right.
  Function values, indirect calls, and trailing commas are not accepted.
- The VM uses growable operand, local, and frame buffers. Each frame retains its
  own instruction index, local base, operand base, and entering call span.
  Calls copy arguments into parameter slots in source order; returns remove
  callee locals and leave one value above the caller's existing operands.
  Guest recursion is iterative at the host level.
- `--max-frames=N` sets a positive decimal u64 active-frame limit, default 1,024,
  counting main. The VM checks it at the call instruction after evaluating its
  arguments. Limit exhaustion is a guest trap. Traces include the current
  function and up to 15 callers, newest first, with source locations and an
  explicit count of omitted older frames. Trace data borrows compilation-owned
  function names and is stored by value, requiring no extra runtime cleanup.

The [MVP acceptance audit](mvp-audit.md) records the verification evidence.
Post-MVP feature syntax is not accepted as a placeholder with invented semantics.


The guest has no strings, floats, raw pointers, allocator attenuation,
generics, compile-time execution, modules, globals, closures,
function values, standard library, FFI, exceptions, concurrency,
optimizer, native backend, or self-hosting. The host compiler and VM allocate.
There is no REPL, guest printing, warning suppression, warning-as-error mode,
or project policy file. The CLI prints only main's integer result. The scalar
baseline grammar is in plan section 6; implemented extensions are specified in
the experiment records linked below.


`discover-duplicates` is an optional post-MVP analysis command, not part of
language validity. It fully checks the input first, then reports exact candidates
on stdout, and never lowers or executes the input. Its contract, thresholds,
population labels, recursion normalization, and limits are specified in
[the experiment record](experiments/duplicate-discovery.md).


Record extensions are now implemented: nominal `struct` declarations, explicit
complete `new Type { ... }` construction, `.field` access, preserving
`update(value) { ... }`, and declarative `conversion fn` accounting. Definitions
may refer forward but cannot form recursive by-value layouts. See
[the A1 semantics and restrictions](experiments/aggregates.md) for the grammar,
copy/storage behavior, conversion body restriction, and added-field guarantees.
Fixed arrays, checked indexing, `replace`, and `len` are implemented; see
[array semantics](experiments/arrays.md). Additional integer widths and
checked casts are implemented; see [integer semantics](experiments/integers.md).


The integer extension adds signed/unsigned 8/16/32/64-bit types, suffixed decimal
literals, and `cast<T>(expression)`. Unsuffixed literals retain `i64` semantics.
Operations require matching widths; bounds and signedness conversions are
checked in every host mode. Boolean and record conversions remain separate.


Nominal scalar domains are implemented: `domain Name: Scalar { ... }`, qualified
factory/accessor functions, `private fn`, and owner-restricted `wrap<Domain>` /
`unwrap` operations. Domain values do not implicitly convert to their backing
scalar or other domains. See [domain semantics](experiments/domains.md) for the
representation boundary, visibility, and runtime costs.


Closed `enum` and tagged `union` declarations, explicit `new Type.variant`
construction, and exhaustive `match` statements are implemented. Payload access
requires a typed arm binding or explicit payload discard. Enum equality retains
nominal identity. See [variant semantics](experiments/variants.md) for grammar,
control flow, storage, and added-variant guarantees.


Complete enum-indexed tables are implemented as `[Enum]Value`, with named
construction requiring every enum case. Lookup/replacement requires the exact
enum key type, and adding a case exposes incomplete constructors. See
[table semantics](experiments/tables.md) for mapping identity, evaluation order,
unknown-code boundaries, and storage costs. This completes A2.


Scoped borrowing is implemented as `borrow [mut] owner as name { ... }`, with
`read_ref(name)` and `write_ref(name, value);`. References have lexical scope,
whole-local access, and checked shared/exclusive permissions. Reads preserve
value snapshots; return cleanup ends child leases before parents. References
cannot be copied or stored in values. `&T` and `&mut T` parameters accept
active references through temporary call reborrows; value arguments evaluate
before those loans begin. Returned-reference contracts name an input with `from parameter`; callers use
`borrow [mut] helper(...) as result { ... }` to receive the view. See [the borrowing contract](experiments/borrowing.md).


Bounded slices use `borrow [mut] owner[start..end] as name { ... }`, with
`read_slice`, `write_slice`, and `len_slice`. `&[]T` and `&mut []T` parameters
accept varying lengths of the same element type. Bounds and exclusive suspension
remain checked in both host modes; slice writes preserve existing value snapshots.
See [slice semantics and costs](experiments/slices.md).


Returned references must derive from the single declared reference input and
preserve its type, slice shape, and permissions. Borrowed local storage and copied
input values cannot escape. The VM captures a valid result view, ends callee loans,
and reborrows the caller input for the receiving scope. See
[returned-reference semantics](experiments/returned-references.md) and
[B acceptance](experiments/b-audit.md). This completes the restricted borrowing
experiment; buffer acquisition/moves are now supported separately, with allocator and clock/random capabilities described below.


Nominal `result Name { ok: T, err: E }` declarations and explicit `acknowledge`
statements are implemented. Handling obligations transfer through value bindings,
parameters, returns, and wrappers. Scope exits, overwrites, control-flow joins,
loop back edges, and short-circuit paths cannot silently lose an obligation.
Exhaustive matching handles outcomes explicitly. See [result semantics and current
transfer restrictions](experiments/results.md). Owned buffers now participate in cleanup as described below.


`try expression` unwraps a success payload or propagates an exactly matching error
payload into the enclosing declared result type. Its early-return path must not
abandon pending result bindings or unfinished result-bearing expression operands.
Failure releases ordinary temporaries and ends active borrows before returning.
See [propagation semantics](experiments/propagation.md). Arithmetic traps remain
separate from recoverable errors.


`buffer Name: Element;` declares a nominal owned buffer. `acquire_buffer<Result>(heap, n)`
returns an empty buffer or a capacity error through a declared result. Buffers and
wrappers containing them transfer on use and reject reuse; ordinary owned values
clean up at block/match exits, return, and propagated failure. Results retain their
explicit handling obligations. See [source ownership semantics and current limits](experiments/owned-buffers.md).
[Buffer operations and views](experiments/buffer-operations.md) now provide length/capacity
queries, retained reads, typed mutation statuses, and borrowed slices that work with
existing slice helpers and returned-view contracts. Allocator/external capabilities,
resource I/O, and source pools are described below; nested arena scopes remain pending.


Function annotations `noalloc`, `noio`, and `effects(...)` bound inferred effects.
Owned buffer acquisition/reserve contribute allocation; reserved edits and buffer
cleanup do not. Calls propagate effects to a fixed point, including recursion.
`noalloc` constrains guest backing allocation rather than host VM bookkeeping;
`noio` excludes filesystem/network access without promising determinism.
[Effect semantics and limits](experiments/effects.md) define the complete current
contract. Clock/random operations are described below; external resource cleanup remains pending.


The opaque `allocator` capability is supplied only to a requesting entry parameter.
Helpers receive it explicitly; acquisition and reserve require it, and copies share
the same execution quotas. Numeric casts and effect declarations cannot manufacture
capabilities. The embedding runtime can deny provisioning. See [allocator authority
semantics](experiments/allocator-capabilities.md).

Opaque `clock_cap` and `random_cap` entry grants authorize `clock_now<R>(cap)`
and `random_u64<R>(cap)`. Their declared results carry i64/u64 success and i64
errors. Grants require injected host providers; the CLI provides neither. Reads
contribute distinct transitive effects, allowed under `noio` and `noalloc` without
promising determinism. See [provider contracts and limits](experiments/external-capabilities.md).
Filesystem/network/environment and external resource completion/cleanup remain pending.


`resource Name: filesystem;` and `resource Name: network;` declare move-only external
resources. Explicit filesystem/network entry capabilities authorize acquisition
from fixed byte-array requests. `complete_resource<Result>(owner)` consumes its
input and returns the owner inside an error record on recoverable failure; automatic
cleanup only releases. Owned signatures/locals conservatively contribute contained
resource cleanup effects, so noio cannot silently release external resources.
[Source resource semantics](experiments/source-resources.md) defines result shapes,
provider contracts, cleanup order, and the current whole-wrapper projection limit.
Providers are injected; actual file/socket data operations and environment access
remain pending.


`read_field(owner, field)` retains a copyable record field without consuming its
live owner or satisfying pending result obligations. This supports error-code
inspection before retrying with an owned completion failure. Owned/result fields
cannot be copied; shared/exclusive access rules still apply. Ordinary projection
keeps its existing consuming behavior. See [field-read semantics](experiments/owned-field-reads.md).


`environment_get<Result>(env, name)` uses an explicit `environment_cap` and fixed
byte-array name. Its result contains a bounded byte-array snapshot, present flag,
and actual length, or i64 error. Missing and empty are distinct; oversized values
fail without truncation. Entry grants require an injected provider. Lookup adds
an environment effect, allowed under noio/noalloc without implying determinism.
See [environment semantics](experiments/environment.md).


`read_resource<Result>(owner)` and `write_resource<Result>(owner, bytes)` require a
live mutable resource binding and preserve ownership. Reads return fixed byte-array
snapshots, actual length, and explicit EOF; writes return accepted byte count. Both
make one provider call and expose partial progress. Source and emission checks retain
filesystem/network effects and reject invalid mutable/owner/result/input metadata.
See [resource I/O semantics](experiments/resource-io.md). Slice/range I/O remains pending.


`restrict_resource<read, write, complete>(capability)` intersects filesystem/network
operation permissions with a named subset. Copies cannot restore removed rights.
Acquisition passes restrictions to the provider; owned reads/writes/completion check
them before callbacks. Denied operations retain ownership and fallback release stays
available. Provider scope and quotas remain shared. See [attenuation semantics](experiments/attenuation.md).


`read_resource_slice<Result>(owner, destination)` reads into an exclusive u8 slice;
`write_resource_slice<Result>(owner, input)` accepts shared/exclusive u8 slices.
Read results report length/EOF and update only the successful prefix, retaining
array snapshots and untouched bytes. Writes send exactly the chosen range. Lease
checks apply to fixed arrays, initialized buffers, parameters, and returned views.
See [resource slice I/O](experiments/resource-slices.md) for staging costs and failure
semantics. Source pools are described below. Nested source arena scopes remain
pending; execution-lifetime arenas are tracked in the experiment roadmap.


`take_field(owner, field)` transfers a field from an owned/result-bearing record
binding without retaining a copy in the parent. Missing fields and whole-value use
of a partial record are rejected. Untouched copyable fields remain readable through
`read_field`, and other fields can be taken independently. Branch/loop states track
field availability; remaining result fields still require handling. Complete binding
replacement restores fields after any remaining obligations are satisfied. Cleanup
releases only remaining fields; see [partial field moves](experiments/partial-fields.md).


## Source pools and nominal handles

`pool Nodes(NodeId): Node;` introduces a move-only owner and copyable inert IDs.
Allocator-authorized acquisition reserves capacity; typed result operations insert,
read snapshots, replace, and remove nodes. Clear invalidates IDs while retaining
capacity. IDs compare by pool/slot/generation; stale and foreign access returns
typed errors. [Source-pool semantics](experiments/source-pools.md) specifies quotas,
effects, cleanup, errors, and the current parent-allocator backing restriction.
