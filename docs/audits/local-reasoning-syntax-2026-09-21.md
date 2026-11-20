# Syntax for reasoning from less context

Audit and design proposals, 21 September 2026. No language changes are implemented
by this audit. Code blocks below are illustrative; proposed spellings are marked.

The highest-value change is to make a call's mutation, effects and sharing
contract readable without its implementation. Mylang already has much of the
machinery. The remaining work is to make its guarantees consistent and give the
missing guarantees source syntax.

Here, local reasoning means answering these questions from an expression and its
nearby declarations: what changes, what remains the same, what can return early,
what is shared, and which operation is being called? More annotations are useful
only when they remove a consequential question. Inferring an element type is
usually helpful; silently choosing between a wrapper and its payload is a much
larger semantic decision.

**Scope and evidence.** I inspected the current language guides, effects and
origin checking, Option lowering, related regression tests, schematic guest code,
and the S-expression port. I also checked the earlier effects-as-arguments,
mutation-marker and cascading-levers proposals to distinguish existing work
from new ideas. Twelve small probes against the installed compiler yielded nine
accepted programs returning 42 and three intentional rejections. Sources,
commands, diagnostics, compiler hashes and outputs are retained in
[the experiment](../../experiments/local-reasoning-audit-20260921/README.md).
This is a focused syntax/semantics audit, not an exhaustive compiler correctness
review or a measured study of developer productivity.

| Priority | Recommendation | Context it removes | Status / cost |
| --- | --- | --- | --- |
| 1 | Complete mutation declarations and call-site markers | Callee bodies and hidden class writes | Existing experiment; semantic migration required |
| 2 | Declare public effects and result sharing | Transitive callees and allocation/copy implementations | Effects exist; return-sharing syntax is new |
| 3 | Give copying and shared mutation distinct spellings | Aggregate definitions and alias histories | Small changes possible; full isolation needs semantics |
| 4 | Separate introduction from reassignment | Earlier assignments and enclosing blocks | Larger departure from Python |
| 5 | Bind Option payloads explicitly | Earlier guards and destination parameter types | Additive syntax experiment |
| 6 | Use argument labels where order is ambiguous | Remote parameter lists | Mostly available today |
| 7 | Make deliberate failure suppression conspicuous | Result types and conventions around `_` | Small syntax/API change |

**1. Make the absence of a mutation marker meaningful.**

The port contains this real declaration and call:

```text
public def next_raw(lx: Lexer) -> Result[RawToken, LexError]:
    ...

match tk.next_raw(cursor.lexer):
    ...
```

`Lexer` is a class; this advances shared state. The signature does not say so.
See [the declaration](../../experiments/sexpr-port/sexpr/tokenizer.my#L407),
[the caller](../../experiments/sexpr-port/sexpr/parser.my#L40), and
[the cursor writes](../../experiments/sexpr-port/sexpr/tokenizer.my#L143).

There is already an opt-in `--mutation-markers` mode. It requires `&` for
positions in a declared `mutates(...)` footprint. However, missing footprints
only warn for ordinary managed inputs, and class/Cell parameters are exempt from
that warning. The probes confirm that both an unannotated list writer and an
unannotated class writer still accept an unmarked call with the flag enabled;
the class writer emits no warning. See [marker enforcement](../../src/sema.zig#L3591)
and [the exemption](../../src/origins.zig#L622).

Proposed normal spelling, building on the existing experiment:

```text
public def next_raw(lx: Lexer) -> Result[RawToken, LexError] mutates(lx):
    ...

token = tk.next_raw(&cursor.lexer)?
```

The useful rule would be: caller-owned mutation requires a declared footprint
for every parameter type, including classes, and calls mark every writable
argument. An ordinary argument then promises its reachable mutable state will
not be changed by the call. The marker means permission to mutate reachable
objects; it does not turn value records into by-reference parameters, guarantee
that a write occurs, or promise uniqueness. Existing receiver operations such as
`items.append(x)` and explicit assignment already identify their write target.

This needs the overlap policy to be addressed as part of the migration.
Declaring `mutates(dst)` currently rejects calls where `dst` may overlap an
unmarked `src`, including unknown overlap between two parameters. Adding the
clause can therefore make a previously accepted helper fail. Preserve the
read-only promise; report the overlap and require a truthful writable contract,
a proof of separation, or an independent snapshot. A shallow copy is insufficient
when mutable descendants are shared. Do not sell a warning-to-error change as a
purely mechanical rewrite. Generic and callback checking also need equivalent
coverage before making this the default.

Later, field footprints such as `mutates(lx.pos, lx.line, lx.col)` could tell a
caller that `lx.src` is preserved. That is a separate precision feature, not
something the current whole-argument footprint promises.

The visual precedent is useful: Swift requires `&` at calls to `inout`
parameters, making those arguments conspicuous. Mylang should reuse the visual
idea while retaining its own value/reference semantics; Swift's copy-in/copy-out
contract is different. [Swift language guide](https://github.com/swiftlang/swift-book/blob/main/TSPL.docc/LanguageGuide/Functions.md#in-out-parameters).

**2. Make public signatures sufficient contracts.**

An omitted effect annotation is unbounded; public interfaces publish inferred
effects. A reader needs the body or compiler-generated metadata to learn the
bound. Conversely, return sharing already has internal metadata, but no public
source annotation for a precise bound: exported returns default to `unknown`.
[This regression](../../src/incremental_test.zig#L482) explicitly checks that
returning an input and returning fresh storage have the same declared origin.

Use the existing `effects(...)` syntax for stable public ceilings, and add a
checked return-sharing clause. Illustrative proposal:

```text
public def identity(values: list[int]) -> list[int] effects() returns(alias(values)):
    return values

public def duplicate(values: list[int]) -> list[int] effects(managed_allocation) returns(fresh):
    return values.copy()
```

`returns(fresh)` should guarantee that the returned mutable graph is independent
of input mutable graphs. It must not mean merely that the outer list is new.
The same `.copy()` implementation on `list[list[int]]` could not claim that
guarantee. Sharing immutable strings or bytes is harmless and should remain
permitted. An alias clause is an upper bound on possible input sharing, not an
identity-equality promise. Mixed results need a union of possible origins; an
explicit `unknown` is an honest fallback.

Keep body inference for private helpers and use it to suggest public annotations.
A public body that exceeds its declared contract should fail at that boundary.
This allows implementation changes within the bound without changing callers'
assumptions. It does not make tests independent of changed implementations.

Avoid adding a vaguely named `pure` keyword first. Existing `noio` permits clock,
randomness, environment access and mutation; it does not mean deterministic.
`effects()` prohibits effects but does not promise termination, absence of
traps, or fresh returns. Spell the guarantees separately.

The earlier [cascading-levers proposal](cascading-levers-2026-09-21.md) suggests
deriving effects from capability parameters. That remains a possible reduction
in annotation volume, but deriving only from direct parameter names/types is
insufficient: bundles, returned capabilities and callbacks need sound treatment.
For this audit's goal, explicit public ceilings are the smaller first step.

**3. Distinguish value replacement, shared mutation and independence.**

The language's own [Tally example](../statements.md#assignments-and-value-records)
is the clearest illustration:

```text
second = first
second.count = 40       # first.count stays unchanged
second.seen.append(7)  # first.seen changes too
```

One assignment produces a copied record with shared managed descendants.
Additionally, `alias += [2]` extends a shared list, while numeric augmented
assignment replaces a local value. The probes confirm both behaviors. A reader
needs the type and its fields to decide what the writes affect.

The smallest useful change is to prefer the existing explicit forms:

```text
second = replace(first, count=40)
alias.extend([2])
```

Consider disallowing `+=` for shared mutable collections, while retaining it for
numeric accumulation. `extend` states the collection mutation directly. This
trades some Python familiarity for fewer type-dependent meanings.

`replace` is still shallow: it preserves shared descendants. For independent
editing, a proposed `snapshot(first)` should copy the reachable mutable graph,
preserving cycles and internal sharing. It needs explicit rules for unsupported
resources/capabilities and a visible allocation cost. A shorter keyword cannot
make shallow copying independent. Keep `.copy()` documented as shallow, or make
`copy_shallow()` the clear spelling if willing to pay the migration cost.

Another hidden distinction: `[1, 2]` creates a managed list or a fixed value
array according to the expected type. Keep the ordinary literal for lists and
consider an explicit constructor for fixed arrays/tables, for example the
proposed `array[int, 2](1, 2)`. This is most helpful as a call argument, where the
expected storage kind is otherwise in another file. It is less urgent when the
type annotation is on the same line.

Keep `record` and `class` distinct. Replacing every value record with a class
would exchange copy surprises for alias surprises.

**4. Distinguish a new binding from a reassignment.**

Today `name = expression` introduces or reassigns a function-scoped mutable
binding. Nested ordinary blocks reuse it, while loop variables, match payloads
and resources have narrower scopes. The checker catches unbound paths, but a
reader still needs earlier assignments to understand an isolated block.

If willing to make a larger syntax change, trial block-scoped declarations:

```text
# Proposed
let limit = len(items)
var total = 0
for item in items:
    let contribution = score(item)
    total += contribution
return total
```

`let` fixes the binding; `var` permits reassignment; plain `=` only reassigns an
existing mutable binding. Reject accidental shadowing and require an explicit
shadowing form if it is later needed. Expression-valued `if`/`match` would let
branches initialize a value directly instead of creating a dummy mutable local.

This is about the stability of names. `let items = [...]` must not be advertised
as deep immutability: it can still name a mutable object. Deep read-only/frozen
values are a separate type-system feature. Measure this change independently;
it is a substantial reversal of the current Python-style local-scope decision.

**5. Give an Option payload its own local name.**

The current narrowing rule is more contextual than a simple presence test:

```text
candidate: Option[int] = Some(21)
if candidate is None:
    return 0
return payload(candidate) + wrapper(candidate)
```

In the verified probe, `payload` accepts `int` and `wrapper` accepts
`Option[int]`; both calls work. The compiler selects the payload or wrapper
according to the expected destination type. [The selection is explicit in
the checker](../../src/sema.zig#L3235). Changing a callee's parameter can change
what this unchanged argument expression passes.

Add a concise pattern-binding guard, and make the new name always mean the
payload. One possible spelling:

```text
# Proposed: else must leave this control-flow path
let Some(number) = candidate else:
    return 0
return payload(number) + wrapper(candidate)
```

The original `candidate` always means the Option, and `number` always means the
payload. This does not require copying a class/list payload: its usual shared
identity remains. Exhaustive `match` already provides explicit binding today;
the proposal makes that clarity affordable for common guard clauses. Trial it
additively before considering removal of automatic narrowing. Keep `?` for
Result propagation; it already puts an early-return marker on the operation.

**6. Require argument labels where positional order carries meaning.**

The tokenizer has a real seven-argument call:

```text
raw(Kind.unit_val, offset, pos, start, num_end, start_line, start_col)
```

Six arguments have the same integer type. A reader must open `raw` to distinguish
the complete source span from the text span. The existing keyword syntax allows:

```text
raw(Kind.unit_val, start=offset, end=pos, text_start=start,
    text_end=num_end, line=start_line, col=start_col)
```

Use this now for coordinates, spans, source/destination pairs, and Boolean
options. The declaration and call are in
[the tokenizer](../../experiments/sexpr-port/sexpr/tokenizer.my#L198).
For language support, add Python-style keyword-only parameters after `*`, letting
an API enforce its meaningful labels. Do not require labels on every small
arithmetic helper. This has a modest verbosity cost and little semantic risk.

**7. Distinguish ignoring a value from ignoring a failure.**

Today `_ = fail()` explicitly discharges a Result handling obligation; the probe
returns successfully after discarding `Err("failed")`. That is permitted design,
not a checker bug. But it uses the same symbol as an unused count or index.

Reserve `_ =` for ordinary data and consider a dedicated failure-discard form:

```text
# Proposed spelling
ignore_error write_report(fs, report)
```

The compiler would require a Result expression, evaluate it once, preserve its
effects and perform normal cleanup. This makes deliberate failure suppression
searchable and locally obvious. Keep `?` as the common path.

Likewise, distinguish fallible text parsing from numeric conversion in API
names: `parse_int(text)` versus `int(number)`. Today `int(str)` returns an
Option while numeric conversion returns a scalar and may trap. Prefer named
error mapping when `?` would otherwise wrap an error into an enclosing union
based on a distant variant declaration. These are smaller API refinements;
there is no need to mark every potentially trapping arithmetic operation.

**Other issues worth tracking, below the first implementation batch.**

- `==` is structural for records/collections but identity-based for classes.
  A dedicated identity operation would let code state that intention. Changing
  class equality itself needs cycle, cost and compatibility decisions.
- A user-defined `Ok` can shadow the result constructor; the probe's `Ok(41)`
  returns an ordinary integer. Consider reserving the small set of syntax-like
  prelude names, with a qualified spelling for intentional alternatives. Avoid
  reserving every standard-library function.
- Arena allocation is dynamically inherited by helpers. The existing explicit
  arena block and `escape` boundary are valuable. An expression-valued arena
  block could yield its escaped result without a dummy outer binding, but adding
  allocator parameters to every helper would spread substantial new context.
- Named generic constraints, explicit capability values, qualified module
  calls, strict Boolean conditions, and `public` on declarations are already
  good local cues. Preserve them. In particular, current public placement has
  already solved the earlier separate-export-list problem.

**Recommended sequence and how to decide.**

First complete the mutation-contract experiment, including class inputs and
overlap migration. Add public return-sharing contracts and stable effect
ceilings next. Apply argument labels to ambiguous APIs using existing syntax.
Trial binding/Option changes separately, since they have a larger familiarity
cost. This sequence extends existing machinery before changing the everyday
shape of every function.

Evaluate with tasks that expose only a short function/call-site window, then
permit additional source reads. Ask readers/agents to predict changed state,
return shape, failure exits and sharing; also ask them to make small edits.
Measure wrong predictions, additional bytes read, failed checks on changed
source, and time/tokens to a correct answer. Include aliasing through nested
records, classes, callbacks and imported functions. Use matched current/proposed
programs, multiple independently sampled runs, and score correctness before
brevity. Do not infer a productivity improvement from fewer lines or a passing
micro-probe: this audit establishes the semantic surprises and the design
options, not their measured human or agent benefit.
