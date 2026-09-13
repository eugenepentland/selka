**Language simplicity audit — 12 September 2026**

The largest improvements would come from completing ordinary collection and text operations, unifying the public standard-library types, and publishing one consistent syntax. The recent GC and syntax changes improved the schematic entry point, but many familiar expressions still fail elsewhere. Replacing `fn` with `func` alone would leave most of those difficulties intact.

This audit examines the current working tree, including the recent uncommitted language changes. I inspected the parser, checker, formatter, feature manifest, standard library, and all 13 schematic guest modules, and ran 41 targeted source probes against the installed executable. The probes deliberately include missing features; they are not a representative success-rate measurement. The [evidence file](/home/epentland/ai/canopy/mylang/docs/audits/language-simplicity-2026-09-12-probes.json) contains every source program, result, diagnostic, the compiler SHA-256, and hashes of 24 relevant source files. No language implementation was changed and no build or Guardian gate was run.

**Choose a primary syntax reference, and name deliberate differences.** Go is the better primary reference for the existing static types, value structs, braces, and GC. Python provides useful conventions for collection operations and text handling. These languages do not share one grammar: Go uses `func`, typed declarations, and brace blocks; Python uses `def`, colon/indentation suites, and different binding rules. Adopting Python-shaped source also invites Python-shaped semantic expectations. [Go specification](https://go.dev/ref/spec), [Python compound statements](https://docs.python.org/3/reference/compound_stmts.html).

My recommended sequence is to repair the common operations below while keeping the current `fn`/`let` spelling, then evaluate a Go-shaped declaration syntax as one versioned migration. If maximum Go resemblance is the overriding requirement, adopt its declarations and binding rules together. Avoid accumulating `fn`, `func`, and `def` as three equally recommended spellings. Keeping `Result`, `Ok`/`Err`, and `?` would be an explicit Rust-style extension, already supported by familiar precedent. [Rust result documentation](https://doc.rust-lang.org/std/result/).

The following priorities describe expected benefit and implementation scope, not measured agent productivity or delivery estimates. P0 means a confusing inconsistency to resolve first; P1 means a major everyday usability improvement; P2 means a subsequent language-design change.

| Priority | Finding | Recommended change | Scope |
| --- | --- | --- | --- |
| P0 | Built-in and standard-library `List`/`Result` have different identities | Give ordinary code one canonical type for each | Type catalog, library compatibility, schemas |
| P0 | Familiar list operations only work in selected expression shapes | Support literals, arbitrary receivers, nested indexing, and ordinary iteration | Parser, checker, lowering, GC roots |
| P0 | Examples and documentation teach multiple generations of the language | One current guide, canonical examples, executable feature examples | Documentation, migration tooling |
| P1 | Text and maps still expose explicit-storage machinery | Managed strings and maps with ordinary operations | Runtime and standard library |
| P1 | Integer types and lengths require routine casts and suffixes | Default `int`, contextual literal typing, coherent index/length types | Type checking and API contracts |
| P1 | Floating-point syntax is absent | Primitive numeric floats, literals, and arithmetic | Type system, VM, interchange |
| P1 | Result constructors are simpler than result patterns | `Ok(value)`/`Err(error)` patterns and a consistent optional-value API | Parser and checker |
| P1 | Record updates require special forms | Ordinary field assignment and field shorthand, with explicit value semantics | Assignment lowering |
| P1 | Ordinary output code uses fake return values and borrow blocks | Unit-returning wrappers and direct literal arguments | Mostly library/application cleanup |
| P2 | Declaration, mutation, export, and generic rules need extra learning | Adopt one coherent declaration style; improve local inference | Versioned syntax/design work |
| P2 | Resource and low-level operations dominate the language vocabulary | A small ordinary API, with explicit storage/effects available separately | Libraries and advanced language surface |

**1. Unify the standard types before adding more convenience spellings.** These are actual failures from the probes:

```text
expected List<i64>, found std_list::List<i64>
expected Result<i64,i64>, found std_result::Result<i64,i64>
expected unit, found std_unit::Unit
```

For example, this currently fails:

```rust
import std_list
let items: List<i64> = std_list.create::<i64>()
```

The snippet is the relevant portion of a complete module in the evidence file. The built-in catalog creates its own generic types while the standard modules declare separate nominal types. An agent should not need to discover that two standard ways of creating a list produce incompatible types. [Built-in declarations](/home/epentland/ai/canopy/mylang/src/nominal_templates.zig:69), [standard lists](/home/epentland/ai/canopy/mylang/src/stdlib/std_list.my:8), [standard results](/home/epentland/ai/canopy/mylang/src/stdlib/std_result.my:18).

Make the standard constructors operate on the canonical built-ins, while retaining user-defined nominal types. Compatibility aliases or adapters must preserve old module interfaces and cached schemas. Unit needs separate care: the older `std_unit.Unit` deliberately serves wire interfaces that cannot encode the built-in unit type. Present one ordinary no-value convention, but retain an explicit wire adapter until those interfaces migrate. Do not silently change the old wire representation. [Unit boundary contract](/home/epentland/ai/canopy/mylang/docs/experiments/unit-procedures.md).

**2. Complete the collection expressions agents will naturally try.** The following all failed against the current executable:

| Expression or construct | Current result |
| --- | --- |
| `let xs: List<i64> = [40, 2]` | Parser expects an empty literal |
| `xs.append(42)` | Only `push` and `len` are recognized methods |
| `len(xs)` for a list | Type error; the existing builtin is for arrays |
| `box.items.push(42)` | Parser error |
| `rows[0][0]` with nested managed lists | Reports that a fixed array is required |
| `make_items()[0]` returning a managed list | Reports that a fixed array is required |
| `xs[0..1]` | Parser error |
| `for value in xs { ... }` | Parser expects an integer range |

The checker currently recognizes a managed-list operation by finding a named local receiver. Indexed assignment also requires a named binding. Those implementation restrictions leak into ordinary expressions. [Collection checking](/home/epentland/ai/canopy/mylang/src/sema.zig:546), [assignment parsing](/home/epentland/ai/canopy/mylang/src/parser.zig:772), [empty literals](/home/epentland/ai/canopy/mylang/src/parser.zig:887).

Support the full expression forms, preserving single evaluation and rooting of the receiver, index, and arguments. Prefer `append` as the public verb for a Python-oriented API, and a uniform `len(value)` for sized values. Python already uses list `append`, and its built-ins include `len`, `range`, and `enumerate`. [Python mutable sequences](https://docs.python.org/3/library/stdtypes.html#mutable-sequence-types), [Python built-ins](https://docs.python.org/3/library/functions.html).

Direct `for item in items` and indexed iteration should come before comprehensions, arbitrary iterators, or capturing closures. Specify mutation during iteration: for an initial design, evaluate the collection once, fix the iteration bound at entry, and reject structural changes during that iteration. Choose whether slices copy or share storage before exposing them. Avoid silently borrowing growable managed storage through the existing explicit-storage slice mechanism.

**3. Supply real strings and a managed map.** Today quoted text is a byte array; there is no ordinary `string` type, string concatenation fails, and byte/text helpers primarily take borrowed `u8` slices. Maps exist, but the exposed families involve allocator arguments, capacity contracts, borrowed views, and multiple result types. The [word-count example](/home/epentland/ai/canopy/mylang/examples/standard-word-count/main.my) demonstrates how much machinery a common application task currently requires. [String helpers](/home/epentland/ai/canopy/mylang/src/stdlib/std_strings.my), [map API](/home/epentland/ai/canopy/mylang/src/stdlib/std_map.my).

Add an immutable string type, distinct byte literals such as `b"..."`, ordinary equality/concatenation, split/join/formatting, and an automatically growing map with string keys. Keep bounded explicit-storage containers for code that requests them. A managed map should define missing-key behavior, key equality, iteration order, and growth; borrowing Python's notation does not supply those contracts automatically. [Python mapping operations](https://docs.python.org/3/library/stdtypes.html#mapping-types-dict).

For a Go-oriented design, I recommend a byte-indexed string contract with explicit Unicode iteration and byte/text conversion APIs. Document the difference from Python's text model. If Python compatibility becomes the primary goal, choose code-point-oriented text operations instead before programs rely on byte indexing. This is a substantive runtime decision, not just a new type alias.

**4. Make routine numbers routine.** There is no built-in `int` alias. A literal `42` passed to a `u8` parameter fails, as does `List<u8>.push(42)`, even though the value fits. List lengths return `u64`, while application counters frequently use `i64`. The schematic source contains 66 `cast<i64>` occurrences after stripping literals and comments. This count identifies visible friction; it does not mean every cast is unnecessary.

Use `int` as the ordinary signed integer, with a documented fixed width for this VM. Retain explicit-width types for protocols and storage. Allow compile-time literals to take an expected numeric type when representable; continue rejecting overflow and require an explicit policy for runtime narrowing conversions. Choose a consistent ordinary type for lengths and indices, using checked adapters for existing `u64` APIs.

Add native floating literals and numeric operators as a separate task. The current `std_math.F64` is an opaque domain using named arithmetic and `u64` bit encodings. Its ordinary domain equality compares representation bits, which is especially surprising for signed zero and NaN. Preserve bit-exact APIs separately from normal numeric equality. This is a high-impact change for geometry and scientific code, even though it requires more work than punctuation. [Floating-point contract](/home/epentland/ai/canopy/mylang/docs/floating-point.md).

**5. Complete error and optional-value syntax.** `Ok(42)` construction works, but `match value { Ok(x) => ... }` fails; patterns still need `ResultType.ok(x)`. Add contextual `Ok`/`Err` patterns and `_` for an intentionally ignored ordinary payload. An explicit arm still handles the outer result; nested must-handle obligations must remain checked. The current `_ = expression` assignment is not a discard form either. [Match contract](/home/epentland/ai/canopy/mylang/docs/match-expressions.md), [result constructor checking](/home/epentland/ai/canopy/mylang/src/sema.zig:524).

Provide one optional-value family, with familiar construction and matching, rather than teaching a different bespoke union for each API. Keep `Result` and `?` as the canonical checked-error path during the first simplification pass. Go's multiple-return error convention and Python's exception machinery are different control-flow designs, not spelling aliases for the current one. [Effective Go: errors](https://go.dev/doc/effective_go#errors), [Python compound statements](https://docs.python.org/3/reference/compound_stmts.html#the-try-statement), [Rust results](https://doc.rust-lang.org/std/result/).

Let effect-only functions omit a return annotation and infer unit. Consider allowing an application entry to return unit or a result through an explicit runner convention. The current i64-only entry forces the schematic to retain a `Done` alias and a final status-code match. Keep the legacy entry ABI available for embedded hosts.

**6. Allow ordinary record construction and assignment.** `Point { x }` shorthand and `p.x = 42` currently fail. Enum construction also still requires `new Kind.atom`, even though record construction no longer requires `new`. Complete these forms before adding a new object system.

Retain value structs and make that choice visible. A probe that reads a struct from a list, updates the list slot, then reads the earlier local returns the old field value. That is expected for the current value semantics. It differs from the expectations many Python object users bring. A local struct-field assignment should update the local value; an indexed field assignment should perform a checked update of that slot. Do not make a retrieved value alias its old slot implicitly. Managed lists remain shared handles. List equality also currently rejects; choose an explicit equality/identity API, including cycle behavior, before promising Python-like equality.

**7. Remove boilerplate that the current language already permits removing.** The schematic contains 112 borrow statements and 184 `discard` tokens across its 13 guest files. Many borrow scopes surround a literal passed to a readonly byte-slice parameter. This simpler form already works:

```rust
fn byte_count(value: &[]u8) -> i64 {
    return cast<i64>(len_slice(value))
}
fn main() -> i64 {
    return byte_count("abc")
}
```

The probe returns `3`. Binding the literal to an ordinary local and then passing that local directly does not work; the current special case is specifically the literal argument. Consequently, many existing literal/borrow blocks can be simplified immediately without claiming general automatic borrowing. [Schematic output boilerplate](/home/epentland/ai/canopy/mylang/src/schematic/guest/draw.my:9).

Several guest output helpers return `i64` and then always return zero; their callers repeatedly discard that value. Give these helpers unit-returning public wrappers, retaining the raw scalar host ABI internally. This reduces application noise without permitting unchecked errors to disappear. Re-audit individual return contracts rather than deleting all discards mechanically.

The application-specific module name `io` is another source of confusion. Rename its role-specific API to `schematic_inputs` or expose it through an application namespace. Keep standard facilities under an unmistakable standard-library namespace. `io.inputs()` is application API design, not a missing language keyword.

**8. Make inference and binding rules predictable.** A generic helper with arguments `(value: T, other: List<i64>)` rejects `choose(42, [])`, although the non-generic list parameter supplies the needed context. Explicit `choose::<i64>(42, [])` succeeds. Extend contextual checking through generic inference; do not require agents to know the checker's scheduling order. All source expressions must still evaluate once.

Bare generic parameters currently require a constraint: `<T>` fails where `<T:copy>` succeeds. Simplify common signatures after defining whether an unqualified parameter means an ordinary copyable/managed value or a more general transferable value. Preserve explicit contracts for owned and borrowed generic code.

The current binding model requires `let mut` for rebinding and rejects inner-block shadowing. Those are deliberate rules, but they differ from Go and Python habits. I recommend permitting inner-block local shadowing while retaining same-scope duplicate diagnostics; imported-name shadowing can remain restricted with a precise explanation. If adopting Go declarations, adopt `:=`/`var` and its binding model together. If retaining `let`, document binding immutability independently from mutability of a referenced list. [Current binding checks](/home/epentland/ai/canopy/mylang/src/sema.zig:1946).

Named arguments, default parameters, and broader destructuring would also reduce some application friction, but follow complete collections, text, and result patterns. Go and Python differ substantially here; introduce them only as part of the chosen public profile.

**9. Teach one surface and move specialist operations out of the beginner path.** The lexer contains 120 `kw_` token tags, including low-level resource, storage, integer, and float intrinsics; the library contains 35 source modules. These are inventory counts, not a complexity score. Many specialist operations can remain compiler intrinsics behind typed library functions instead of appearing as beginner-facing language constructs. Keep explicit ownership, arenas, capabilities, and `nogc`/`noalloc` available for tasks that need those guarantees.

For deterministic resources, a scoped construct shaped like `with ... as ...` would be easier to recognize than spreading acquisition/completion details through ordinary code. Python's `with` is a useful surface reference, but cleanup order, error propagation, and failed completion need mylang-specific contracts. GC must not become the mechanism for closing files or other external resources. [Python with statement](https://docs.python.org/3/reference/compound_stmts.html#the-with-statement).

Keep explicit visibility, but consider placing an export marker on the declaration rather than maintaining a separate name list. If moving fully toward Go, its capitalization-based visibility belongs in that larger migration. Avoid changing identifier case piecemeal while teaching the existing export rules.

The current formatter preserves token spellings, so it cannot turn legacy APIs into the new surface. The schematic still contains 584 `::` qualifiers and 22 `new` constructions. Older examples remain valid, but retrieved examples therefore continue to teach the older forms. A separate checked migration tool is more appropriate than silently rewriting semantics during formatting. [Formatter](/home/epentland/ai/canopy/mylang/src/formatter.zig:1).

One concrete documentation contradiction should be fixed promptly: the unit-procedure guide says there is no unit literal, whereas `()` is now accepted and documented in the newer guide. It also preserves obsolete runtime variant-count commentary. Establish one short current language guide, label historical documents clearly, and execute every advertised syntax example. The guide should state which APIs belong to the language, the standard library, or a particular host application.

**10. Stabilize newline behavior.** The current parser permits a binary operator at the start of a continuation line, but stops an unparenthesized call suffix across a newline. Both behaviors are verified in the probes. This is a defined dialect rule; it is not Go's semicolon insertion or Python's line joining. Preserve compatibility now, recommend trailing operators or parentheses in canonical output, and include the unary-minus ambiguity in the short guide. Do not keep revising newline rules to accommodate individual fixtures without a stable grammar. [Go semicolons](https://go.dev/ref/spec#Semicolons), [Python line joining](https://docs.python.org/3/reference/lexical_analysis.html#implicit-line-joining).

**A practical next sequence.** First unify canonical standard types and repair the public guide. Then complete list literals, uniform length, arbitrary receivers/indexing, and collection iteration. Next add managed text/maps, ordinary numeric typing, record assignment, and contextual result patterns. Clean up the schematic and word-count examples using the resulting APIs. Evaluate declaration-style alternatives after these shared improvements, so a keyword change is not credited for an unrelated library improvement. Resource syntax and advanced generic convenience can follow.

For example, the proposed collection improvements alone would permit this source while retaining the current declaration style:

```rust
// Proposed syntax: int and collection iteration are not implemented yet.
fn count_connected(pins: List<Pin>) -> int {
    let mut count = 0
    for pin in pins {
        if !pin.nc {
            count += 1
        }
    }
    return count
}
```

That removes the index counter, length conversion, and repeated indexing visible in the current schematic loops. It also leaves the record/list value model explicit and requires no exception-system redesign.

**Validate the AI benefit instead of assuming it.** This audit identifies familiarity gaps; it does not establish that any syntax improves a particular model's success rate. Use the existing application-comparison and development-velocity infrastructure to compare the current language, the proposed canonical surface, and a declaration-only variant. Hold model version, task prompts, tool access, instruction budget, and sampling settings fixed. Randomize task order and use multiple runs.

Measure first-check success, first independent-oracle success, repair turns, tokens, elapsed time, and failure categories. Separate syntax/API guesses from semantic mistakes such as aliasing, bounds, Unicode handling, and dropped errors. Include small list/text/map tasks and real schematic/JSON/file-I/O changes. Compare a better quick reference alone against actual language changes. Keep malformed-input and no-partial-output oracles unchanged. Fewer tokens of source are useful evidence only when correctness and repair effort improve too.
