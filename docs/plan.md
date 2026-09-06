# Systems language: goals and Zig MVP implementation plan

Status: revision 2; scalar MVP M0–M5 implemented and audited on 2026-09-05. Post-MVP implementation is tracked in section 15.

Working executable name: `mylang`. Working source extension: `.my`.

Purpose: a plan for an experimental implementation, not a finished language specification.

Revision 2 adds explicit scalar-result discard and two advisory binding diagnostics to the MVP. It proposes complete record conversions, external capabilities, resource obligations, nominal domain types, exhaustive mappings, and compiler-assisted duplicate discovery for later experiments. Sections 3 and 15 distinguish the MVP commitments from those proposals; section 18 explains the Guardian-derived design and its limits. M0–M5 are complete; section 16 preserves the original starting task for context.

## 1. Project direction

Build a small systems programming language that makes execution costs, memory ownership, and compilation work understandable. The eventual targets include native tools, data-heavy algorithms, and embedded software.

Make important domain rules explicit enough that the compiler can identify affected code when those rules change. Favor one declared source for knowledge that must remain consistent, complete handling of data and variants, and visible dependencies. Code similarity and size are useful review signals; they do not establish whether a program is correct or an abstraction is appropriate.

The first implementation will be written in Zig. It will compile a deliberately small subset of the new language into a custom instruction set and execute those instructions in a VM also written in Zig.

This is our bytecode, interpreted by our VM. It is not bytecode consumed by the Zig compiler. Zig builds the host executable; that executable processes programs written in the new language.

The first experiment should answer:

1. Can we build a clean, understandable compiler pipeline?
2. Does the basic syntax feel comfortable when writing small programs?
3. Can we add a feature without entangling parsing, type checking, and execution?
4. Do failures produce useful source-level explanations?

It will not yet establish native performance, memory safety for pointer programs, fast incremental rebuilding, or a practical ownership system. Those need separate experiments.

## 2. Long-term language goals

### Predictable execution and allocation

Ordinary expressions should have understandable costs. Heap allocation should require an allocator capability, and APIs should make potentially allocating operations recognizable. Containers should support operations that use existing capacity as well as operations that may grow.

Use value semantics for ordinary data. Keep resource ownership and transfer explicit enough to follow. Support deterministic cleanup with no mandatory garbage collector. Represent recoverable errors as values, with convenient propagation and no exception unwinding.

Deterministic cleanup can execute code at scope exit. The goal is to make that ownership contract clear, not to pretend cleanup is free.

### Visible dependencies and effects

Extend the allocator-capability idea to filesystem access, networking, clocks, randomness, and environment access. Library code receives capabilities from callers; ambient mutable state and unrestricted access to external resources should not be ordinary safe-language conveniences.

Experiment with small function contracts for no I/O and no allocation. Verify them transitively through callees and cleanup operations. An explicit allocator argument alone does not establish a no-allocation guarantee. Absence of external effects does not establish termination or freedom from arithmetic traps. Exact syntax and the handling of indirect calls and FFI are deferred; section 18 describes the experiment.

### Practical memory safety

Aim for owned values, shared borrows, exclusive borrows, and slices. Safe references should be checked for lifetime and access validity. Raw pointers and hardware access should require explicit unsafe operations and documented preconditions.

Make arenas, pools, and typed integer handles practical. Graph-like applications should be able to store objects in pools and refer to them by IDs. An ID type prevents mixing categories; detecting stale or invalid IDs still requires an appropriate pool design and checks.

Do not promise a borrow checker with no complexity. Prototype its rules on realistic graph, arena, and container examples before making the syntax permanent.

Track resource ownership through ordinary scope exits, recoverable-error returns, and ownership transfers. Resource-owning containers must not be implicitly copied. Partial construction must release resources already acquired when a later acquisition fails. Operations with fallible completion, such as transaction commit, need explicit result-returning APIs; cleanup must not imply successful completion. Cleanup behavior on traps needs a separate decision before guest resources are introduced.

### Defined arithmetic and layout

Provide fixed-width integers and explicit checked, wrapping, and saturating operations. Ordinary arithmetic should not silently acquire undefined overflow behavior in an optimized build.

Eventually distinguish internal data layout, C-compatible layout, and precisely specified external layouts. Hardware access needs explicit width, alignment, and volatility; atomics and ordering are separate concerns.

### Bounded abstraction

Favor structs, tagged unions, composition, and generics with declared requirements. Use local inference while retaining written types at public function boundaries. Avoid implicit conversions that lose information.

Compile-time execution should have declared inputs, deterministic behavior, resource limits, and diagnostics explaining its cost. Specialization should be visible and measurable.

### Complete data handling and domain identity

Ordinary record construction should supply every field; defaults should be requested through explicit constructors. Updating an existing record should preserve unspecified fields according to its ownership rules. A conversion declared to represent a complete source value should account for both source and destination fields, so a newly added source field cannot disappear silently.

Make nominal scalar wrappers and private constructors practical for units, counts, and identifiers. Equal underlying numbers do not imply equal domain meanings. Keep runtime bounds and handle-validity checks where types cannot establish those properties.

Provide closed enums, tagged unions, exhaustive matching, and complete enum-indexed tables. Later, support typed serialization definitions and generated bindings from one schema so external names and mappings do not need to be maintained independently. These features are post-MVP proposals, not additions to the scalar grammar.

### Understandable compilation

Eventually record declaration-level dependencies and report why code rebuilt. Preserve enough semantic information to support both quick development code generation and stronger release optimization.

For the MVP, establish clean phase boundaries and function identities. Do not build a persistent query database, incremental linker, or caching framework yet. IDs in the first compiler are stable within one compilation, not across edits.

### Useful tooling early

Source locations, readable diagnostics, an instruction dump, and regression fixtures are core development tools. They make the implementation inspectable while the language is changing.

Distinguish language errors from advisory analysis and project verification. Preserve resolved identities so later tools can inspect actual references and types. Ship one formatter when tooling expands. Keep inferred duplication, code-size metrics, and complexity thresholds advisory by default; tests, mutation testing, benchmarks, and change-history policies belong in the project-verification layer.

## 3. Committed decisions versus open questions

| Decision | Status |
| --- | --- |
| Compiler and VM implemented in Zig | MVP commitment |
| Single source file, static types, direct function calls | MVP commitment |
| Typed program representation between parser and code generation | MVP commitment |
| Stack VM with explicit call frames | MVP commitment |
| Checked integer arithmetic in every host build mode | MVP commitment |
| In-memory instructions; no serialized bytecode format | MVP commitment |
| Explicit `discard expression;` for unused scalar results; no bare expression statements | MVP commitment |
| Advisory unused-binding and unnecessary-`mut` diagnostics | MVP commitment; precise rules in section 7 |
| Structured error/warning diagnostics and resolved reference identities | MVP commitment; compilation-local identities only |
| Complete record construction and declared complete conversions | Implemented in post-MVP experiment A1 |
| Nominal domain types, exhaustive variants, and enum-indexed tables | Implemented in post-MVP experiment A2 |
| External capabilities and transitive effect contracts | Post-MVP proposal; experiment C |
| Resource cleanup on recoverable errors and explicit fallible completion | Post-MVP proposal; experiment C |
| Module interfaces, schema generation, and compiler-assisted duplicate discovery | Post-MVP tooling/design experiments; section 15 |
| Exact spelling of ownership, error, and generic syntax | Deferred |
| Borrowing rules for arenas and returned references | Deferred design experiment |
| Native backend choice | Deferred |
| Language name, package system, self-hosting | Deferred |

Earlier examples involving `Result`, `Vec`, `move`, `&mut`, and `const N` illustrate the long-term direction. They are not part of the MVP grammar.

## 4. MVP scope and user-facing behavior

The MVP is complete when one executable can check, dump, and run scalar programs with loops and function calls.

| Command | Required behavior |
| --- | --- |
| `mylang check example.my` | Parse and check the complete program; do not execute it |
| `mylang run example.my` | Check, lower, execute `main`, and print its integer result |
| `mylang dump-bytecode example.my` | Check and print readable instructions grouped by function |

For all three commands, the file is a complete program requiring exactly one `fn main() -> i64`. Accept helper functions returning either `i64` or `bool`.

On a successful run, print the signed decimal result followed by a newline to stdout. A result such as `4950` is output, not the process exit code. Use exit status 0 for success, 1 for a source error or program trap, and 2 for usage, I/O, host resource, or internal compiler failures. Diagnostics go to stderr. A failed run produces no result on stdout.

All three commands emit the advisory diagnostics specified in section 7 after successful semantic checking. Warnings do not change exit status, stop execution, or enter stdout. The MVP has no warning-suppression attributes, warning-as-error mode, or project policy file.

### Included

- Decimal `i64` literals and `true`/`false`.
- `let` and `let mut`, with optional local type annotations.
- Unary `-` and `!`.
- Arithmetic `+`, `-`, `*`, `/`, and `%`.
- Comparisons `==`, `!=`, `<`, `<=`, `>`, and `>=`.
- Short-circuit `&&` and `||`.
- Assignment, plus `+=` and `-=` for mutable integer locals.
- Blocks, `if`/`else`, and `while`.
- Named functions, typed parameters, direct calls, recursion, and explicit returns.
- Explicit `discard expression;` statements for integer or boolean results.
- Whitespace and `//` line comments.

### Excluded

No strings, floats, structs, arrays, slices, pointers, user heap allocation, borrowing, ownership transfer, generics, compile-time execution, modules, globals, closures, function values, standard library, FFI, exceptions, language-level error values, concurrency, optimizer, native code generation, or self-hosting.

No general duplicate detector, effect checker, record-conversion checker, schema generator, formatter, or project-verification framework is required for the MVP. Those depend on later language features or a useful corpus of programs.

The host compiler and VM will allocate memory. Excluding allocation from the guest language does not mean the implementation is allocation-free.

Do not add a REPL or guest printing facility. Printing `main`'s result is enough for the initial experiment.

## 5. Example acceptance program

```text
fn sum_to(n: i64) -> i64 {
    let mut total: i64 = 0;
    let mut i: i64 = 0;

    while i < n {
        total += i;
        i += 1;
    }

    return total;
}

fn main() -> i64 {
    return sum_to(100);
}
```

`mylang run sum.my` must print `4950`.

A second example exercises calls, local mutation, and remainder:

```text
fn gcd(a: i64, b: i64) -> i64 {
    let mut x = a;
    let mut y = b;

    while y != 0 {
        let remainder = x % y;
        x = y;
        y = remainder;
    }

    return x;
}

fn main() -> i64 {
    return gcd(48, 18);
}
```

This program must print `6`. Its chosen inputs are positive; the language still defines signed division and remainder below.

## 6. Minimum grammar

Use a handwritten lexer, recursive descent for declarations/statements, and Pratt parsing or precedence climbing for expressions. Pick one expression parser approach and keep it.

The grammar below is EBNF: quoted text is literal syntax, square brackets are optional, and braces mean repetition.

```text
program      = { function }, EOF ;
function     = "fn", IDENT, "(", [ parameters ], ")",
               "->", type, block ;
parameters   = parameter, { ",", parameter } ;
parameter    = IDENT, ":", type ;
type         = "i64" | "bool" ;

block        = "{", { statement }, "}" ;
statement    = binding | assignment | return_stmt | if_stmt
             | while_stmt | block | discard_stmt ;
binding      = "let", [ "mut" ], IDENT, [ ":", type ],
               "=", expression, ";" ;
assignment   = IDENT, ( "=" | "+=" | "-=" ), expression, ";" ;
return_stmt  = "return", expression, ";" ;
if_stmt      = "if", expression, block,
               [ "else", ( block | if_stmt ) ] ;
while_stmt   = "while", expression, block ;
discard_stmt = "discard", expression, ";" ;

expression   = logical_or ;
logical_or   = logical_and, { "||", logical_and } ;
logical_and  = equality, { "&&", equality } ;
equality     = comparison, { ( "==" | "!=" ), comparison } ;
comparison   = additive, { ( "<" | "<=" | ">" | ">=" ), additive } ;
additive     = multiplicative, { ( "+" | "-" ), multiplicative } ;
multiplicative = unary, { ( "*" | "/" | "%" ), unary } ;
unary        = ( "-" | "!" ), unary | primary ;
primary      = INTEGER | "true" | "false"
             | IDENT, [ "(", [ arguments ], ")" ]
             | "(", expression, ")" ;
arguments    = expression, { ",", expression } ;
```

Use ASCII identifiers matching `[A-Za-z_][A-Za-z0-9_]*`; keywords are reserved. Decimal literals are digit sequences without separators, prefixes, or suffixes. Accept LF and CRLF line endings. Do not add trailing commas in the MVP.

`discard` is a reserved keyword. `_` and underscore-prefixed names are ordinary identifiers in this grammar; they are not discard patterns or automatic warning exemptions.

Binary operators are left-associative. Unary operators bind tighter than multiplication. Assignment is a statement, not an expression. Calls target top-level function names only.

## 7. Semantic rules to implement before expanding syntax

### Types, names, and scopes

- Integers are signed, exactly 64 bits. Booleans are a distinct type.
- There are no implicit conversions between `bool` and `i64`.
- Every local has an initializer. Its annotation, if present, must match the inferred type.
- Parameters are immutable. Copy a parameter into `let mut` to change a local version.
- Local names become visible after their initializer and end at their block boundary.
- Reject duplicate function names and duplicate parameter names.
- Parameters and locals may not use top-level function names.
- Reject shadowing of any currently active local or parameter. Separate sibling blocks can reuse a name.
- Collect all function signatures before checking bodies. Forward calls and mutual recursion are allowed.
- Check every function, including functions that `main` never calls.
- Each function explicitly returns its declared type. There is no implicit final-expression return.

### Explicit result discard

A standalone value-producing expression must use `discard expression;`. Reject bare statements such as `1 + 2;` and `helper();` with `E_EXPLICIT_DISCARD_REQUIRED` and suggest adding `discard` or using the result. `discard` accepts either MVP primitive type and introduces no binding.

Evaluate the operand exactly once, using ordinary evaluation order and short-circuiting, then discard its resulting value. The operand can still trap or exhaust an execution budget. For example, `discard 1 / 0;` passes `check` and traps when executed; `discard false && (1 / 0 == 0);` does not trap. Lower a successful discard to the operand's instructions followed by `POP`.

The scalar rule does not settle the later treatment of errors or owned resources. When those features arrive, require explicit handling or propagation of fallible results, with a dedicated acknowledgement operation for deliberately ignored errors. Ordinary value discard must not silently remove that obligation. Discarding an owned resource must follow the eventual ownership and cleanup rules.

### Advisory binding diagnostics

After successfully checking the complete program, emit these warnings for all functions, including uncalled helpers:

- `W_UNUSED_BINDING`: a local or parameter has no resolved read in its function body. A plain assignment target is a write, not a read; `+=` and `-=` read and write their target. A read inside `discard` counts as explicit use.
- `W_UNNECESSARY_MUT`: a `let mut` local has no assignment after initialization. Initialization does not count as mutation; any later `=`, `+=`, or `-=` targeting that binding does.

These are syntactic use observations over checked, resolved nodes. Count reads and writes in both branches and loop bodies even if execution would skip them. Do not infer liveness, detect overwritten values, prove termination, or build a general dataflow framework for these warnings. An unused mutable local may receive both warnings. Preserve all initializer evaluation, traps, and execution costs regardless of warnings.

Locate each warning at the binding declaration, suggest using/removing the binding or removing `mut` as appropriate, and sort warnings by source position then diagnostic code. A removal suggestion must explain that preserving a potentially trapping initializer may require `discard`. Warnings are non-blocking in the MVP and do not replace checking unused function bodies for errors.

### Control flow

`if` and `while` require boolean conditions. Both branches of an `if` are checked even if its condition is a literal.

Use a conservative return analysis: a return terminates its path; an `if` terminates only if it has an `else` and both branches terminate. A block propagates termination. Treat a loop as potentially falling through, including `while true`; require a subsequent return when needed. Reject statements after a structurally terminating statement as unreachable.

This avoids requiring constant evaluation or sophisticated flow analysis. Explain the conservative rule in missing-return diagnostics.

Evaluate operands and call arguments from left to right. `&&` and `||` skip their right operand when the left operand decides the result. This ordering matters even without I/O because an expression can trap or fail to terminate.

### Numeric behavior

| Operation | Rule |
| --- | --- |
| `+`, `-`, `*`, unary `-` | Trap if the mathematical result does not fit `i64` |
| `/` | Truncate toward zero; trap on a zero divisor or `I64_MIN / -1` |
| `%` | Remainder paired with truncating division; trap on a zero divisor; `I64_MIN % -1` returns 0 |
| Ordering comparisons | Accept two integers; return boolean |
| Equality comparisons | Accept two operands of the same primitive type; return boolean |
| `!`, `&&`, `||` | Accept booleans only |
| `+=`, `-=` | Same checked arithmetic as the corresponding binary operation |

Examples: `-7 / 3 == -2`, `-7 % 3 == -1`, and `7 % -3 == 1`.

Preserve integer token magnitudes until semantic analysis. Ordinarily accept magnitudes through `9223372036854775807`. Permit magnitude `9223372036854775808` only when it is directly negated, ignoring grouping parentheses, to represent `-9223372036854775808`. Reject other out-of-range literals. Negating the resulting minimum value again traps at runtime.

Do not fold arithmetic in the MVP. `1 / 0` can pass type checking and then trap when executed; an out-of-range literal is a compile error. Short-circuiting must preserve this distinction.

These semantics belong to the new language and must not change when the Zig host is rebuilt in a different optimization mode.

## 8. Compiler architecture and ownership

Use these phase boundaries:

| Phase | Input | Output |
| --- | --- | --- |
| Source management | File bytes | Owned source buffer and line-start index |
| Lexing | Source buffer | Tokens with byte spans |
| Parsing | Tokens | Untyped AST with source spans |
| Semantic checking | AST and signature table | Typed program with resolved names |
| Lowering | Typed program | Per-function VM instructions and source map |
| Execution | Lowered program | Final value or runtime diagnostic |

For the first version, the typed representation can be a typed tree. It does not need SSA, optimization passes, or a general control-flow graph. Each expression has a type and source span; identifier references become local slots, and calls become function IDs.

Retain each declaration's source span and the mapping from resolved local/function identities back to its declaration. A local slot is identified together with its enclosing function; the same slot number in two functions is not the same binding. Count binding reads and writes from these references. Duplicate spellings must never share a use counter merely because their text matches.

Represent diagnostics with a stable code, severity (`error` or `warning`), primary source span, message, and optional related spans. Render them at the CLI boundary. Source errors prevent lowering/execution; advisory findings do not. Do not introduce a plugin framework or persistent diagnostic database for this separation.

As later features arrive, extend the semantic representation with nominal type identities, field and variant identities, module ownership, resource information, and effect summaries. Record field mappings for declared complete conversions. Add this information with the feature that needs it; do not prebuild empty subsystems. Later duplicate analysis should consume checked semantic structure before optimization removes distinctions important to source-level review.

Keep the bytecode backend dependent on this typed representation, not parser-specific token patterns. A future native backend should have a clean semantic input to consume.

### Zig implementation choices

Use an explicit compilation context with a caller-supplied allocator. Own the source buffer for the entire compilation and execution request. Token text and diagnostic snippets may borrow that buffer.

Allocate AST and typed nodes in append-only tables addressed by IDs. Use tagged unions for node and instruction variants. An arena can own compilation-lifetime allocations; separately owned VM buffers are released after execution.

Growable tables may move. Do not retain pointers into them across append operations; retain IDs and look entries up again. Converting an ID to an array index still requires bounds and capacity handling.

Use separate ID types for functions, AST nodes, typed nodes, and local slots. IDs describe storage locations within a compilation and are not persistent identities.

Keep source-error diagnostics distinct from host allocation failures. Invalid user code should return a diagnostic through a normal path, not panic the Zig process.

Use the official Zig reference for implementation details. In particular, explicit overflow builtins allow checked arithmetic to be independent of host build mode; `@divTrunc` specifies truncation toward zero. Check division preconditions before calling it, and handle the minimum-integer remainder special case explicitly. See the versioned references in section 17.

Do not attempt a reusable compiler framework. Plain modules, concrete types, and direct calls are enough.

## 9. Instruction set and VM

### Representation

Start with an array of tagged instruction records, using instruction indices for jumps. This is the logical bytecode representation. It is deliberately not yet a compact byte stream or portable file format.

The following Zig shapes illustrate the approach; the complete implementation should use the pinned toolchain's APIs:

```zig
const FunctionId = enum(u32) { _ };
const LocalId = enum(u32) { _ };

const Value = union(enum) {
    integer: i64,
    boolean: bool,
};

const Instruction = union(enum) {
    push_i64: i64,
    push_bool: bool,
    load_local: LocalId,
    store_local: LocalId,
    add_i64_checked,
    jump: u32,
    jump_if_false: u32,
    call: FunctionId,
    ret,
    // Add the remaining operations from the table below.
};
```

Each bytecode function stores its parameter types, return type, local slot types, instructions, and an instruction-to-source-span map. Parameter slots come first, followed by local bindings. Allocate one slot per binding and do not reuse slots in the MVP.

### Required operations

| Operation | Behavior |
| --- | --- |
| `PUSH_I64 value`, `PUSH_BOOL value` | Push one typed value |
| `LOAD_LOCAL slot` | Copy one initialized local onto the operand stack |
| `STORE_LOCAL slot` | Pop one value into the designated local |
| `POP` | Remove the successfully evaluated operand of a source `discard` statement |
| `ADD_I64_CHECKED`, `SUB_I64_CHECKED`, `MUL_I64_CHECKED` | Pop two integers and push one checked result |
| `DIV_I64_CHECKED`, `REM_I64_CHECKED` | Apply the division/remainder rules from section 7 |
| `NEG_I64_CHECKED` | Pop one integer and push its checked negation |
| `CMP_I64 predicate` | Compare two integers; push a boolean |
| `CMP_BOOL predicate` | Compare two booleans for equality or inequality |
| `NOT_BOOL` | Negate one boolean |
| `JUMP target` | Set the current frame's instruction index |
| `JUMP_IF_FALSE target` | Pop a boolean; jump only when false |
| `CALL function_id` | Consume the callee's argument count and enter a new frame |
| `RET` | Return exactly one value to the caller |

For every binary operation, pop the right operand first and then the left operand; compute `left op right`. This is easy to get wrong for subtraction and division.

Do not implement eager `AND` or `OR` instructions for source-level logical operators. Lower short-circuit expressions to conditional jumps, producing exactly one boolean on either path.

Use labels and jump patching during emission. Every expression leaves one value on the operand stack. Every normally completing statement leaves the stack at its previous height; returns transfer control instead. Conditional branches must agree on stack shape at a join.

For `discard expression;`, emit the expression normally and then `POP`; never skip evaluating it because its value is unused. In particular, discarded calls must preserve the caller's existing operand values and the call/return frame contract.

For example, `fn add(a: i64, b: i64) -> i64 { return a + b; }` becomes:

```text
function add(i64, i64) -> i64
  0000  LOAD_LOCAL 0
  0001  LOAD_LOCAL 1
  0002  ADD_I64_CHECKED
  0003  RET
```

### Runtime storage

Use three growable buffers: an operand-value stack, a local-value buffer, and a frame stack. Uninitialized local slots can use an optional host value as a debugging sentinel; the guest language has no uninitialized-value feature.

A frame holds its function ID, next instruction index, local-buffer base, operand-stack base, and the source span of the call that entered it.

Keep the interpreter iterative. Guest recursion should push VM frames, not recursively invoke a Zig interpreter function. Re-fetch frame references after growing a buffer so reallocation cannot leave a dangling host pointer.

### Call and return contract

1. The caller evaluates arguments left to right onto its operand stack.
2. `CALL` finds the argument suffix using the callee's parameter count, checks frame limits, and advances the caller's instruction index.
3. Append the callee's local slots and copy arguments into its parameter slots in source order.
4. Remove those argument values from the operand stack. Save the resulting stack length as the new frame's operand base.
5. Execute the callee. Its temporary values must stay at or above that base.
6. `RET` extracts one value of the declared return type. There must be no other callee temporaries remaining.
7. Truncate the local buffer to the returning frame's local base, pop the frame, and push the result onto the caller's operand stack.
8. Returning from `main` yields the CLI result instead.

Values belonging to a caller's unfinished expression remain below a callee's operand base. This is what makes expressions such as `1 + add(2, 3)` and nested calls work.

### Traps and resource limits

Use explicit VM results for integer overflow, division by zero, step-limit exhaustion, and call-depth exhaustion. Include the responsible source span and a short guest call trace.

Start with a default budget of 10,000,000 executed instructions and 1,024 active frames, counting `main`. Provide positive-integer overrides `--max-steps=N` and `--max-frames=N` on `run`. These are execution budgets, not intrinsic language semantics. Check the step budget before dispatching the next instruction.

Host out-of-memory is a separate implementation failure. Invalid instruction tags, impossible stack shapes, or invalid compiler-generated IDs are internal errors, not ordinary guest traps.

Check jump targets and referenced function/local IDs after emission. Assert operand types, initialization, and frame boundaries during VM development. Do not add a loader for untrusted bytecode or a full bytecode verification framework in this milestone.

## 10. Suggested repository structure

Create these modules as the corresponding milestone needs them; empty scaffolding for every file is unnecessary.

| Path | Responsibility |
| --- | --- |
| `build.zig`, `build.zig.zon` | Toolchain-compatible build, run, and test targets |
| `src/main.zig` | CLI parsing, output, and exit statuses |
| `src/compiler.zig` | Compilation context and phase orchestration |
| `src/source.zig` | Source ownership, spans, and line mapping |
| `src/diagnostic.zig` | Error/warning records, stable codes, source spans, and rendering |
| `src/lexer.zig` | Tokens and lexer |
| `src/ast.zig`, `src/parser.zig` | Untyped syntax and parsing |
| `src/sema.zig`, `src/typed.zig` | Signatures, scopes, checking, typed representation |
| `src/bytecode.zig`, `src/lower.zig` | Instruction definitions and lowering |
| `src/vm.zig` | Frames, checked execution, and guest traps |
| `src/disassemble.zig` | Stable, human-readable instruction dump |
| `test/fixtures/` | Accepted, rejected, and trapping source programs |
| `test/integration.zig` | CLI fixture runner |
| `examples/` | Small programs users can edit and run |
| `docs/semantics.md` | Rules actually implemented |
| `README.md` | Exact Zig version, commands, limitations, next milestone |

Keep the dependency direction simple: CLI orchestrates compilation and VM execution; lowering consumes typed nodes; the VM consumes bytecode and source metadata. The VM should not resolve names or ask the parser what an expression means.

Toolchain decision (2026-09-05): use Guardian's exact Zig snapshot, `0.17.0-dev.1683+5ceec001b`, as explicitly requested by the user. Pin it in `.zigversion`, the package manifest, README, and CI. This supersedes the earlier released-toolchain preference. Use this snapshot's standard-library APIs; changing the toolchain later should be a separate change from adding language features.

## 11. Implementation milestones

Prefer a working program at the end of every milestone. Add regression checks with each behavior, rather than postponing all tests until the last phase.

### M0 — Reproducible host project

- [x] Pin Zig and configure one native host target.
- [x] Build the executable and establish `zig build test`.
- [x] Add CLI dispatch, file ownership, spans, and basic diagnostic rendering with separate error/warning severities.
- [x] Keep host I/O behind the CLI so compiler functions can accept source buffers in tests.

Acceptance: the executable reports usage and missing files cleanly; a source buffer survives for the full request and is released afterward.

### M1 — First complete vertical slice

- [x] Implement the syntax needed for `fn main() -> i64 { return 1 + 2 * 3; }`.
- [x] Produce an AST, a minimal typed representation, and VM instructions.
- [x] Run the instructions and print `7`.
- [x] Implement the first readable instruction dump.
- [x] Check precedence and checked arithmetic in this small subset.

Acceptance: the source program executes end to end; malformed syntax produces a located diagnostic; the dump explains why multiplication happens before addition.

Do not write the complete lexer and parser for future syntax before this works.

### M2 — Types, locals, and scopes

- [x] Add booleans, local declarations, annotations, mutation, and nested blocks.
- [x] Resolve locals to slots and enforce initialization, immutability, and scope rules.
- [x] Retain declaration spans and resolved read/write counts; emit advisory unused-local and unnecessary-`mut` warnings.
- [x] Add unary operations and comparisons.
- [x] Reject type mismatches and invalid identifiers before execution.

Acceptance: a mutable counter program works; assignment to `let`, use outside a block, and `true + 1` are rejected with the correct source spans.

### M3 — Branches, loops, and complete scalar operators

- [x] Add `if`/`else`, `while`, assignment shorthand, and explicit `discard` statements; reject bare expression statements.
- [x] Implement all arithmetic rules, including signed division/remainder.
- [x] Lower `&&` and `||` with actual short-circuiting.
- [x] Patch jumps and preserve operand-stack balance.
- [x] Add the conservative return analysis.
- [x] Introduce the instruction budget as soon as loops are executable.
- [x] Preserve operand evaluation, traps, and short-circuiting inside `discard`.

Acceptance: an inline sum loop returns `4950`; short-circuit expressions skip division by zero, including under `discard`; discarded division by zero still traps; a bare expression statement is rejected; an infinite loop stops at its configured budget.

### M4 — Functions and explicit frames

- [x] Collect signatures before checking bodies.
- [x] Add arguments, forward calls, return-type checking, and recursion.
- [x] Extend unused-binding diagnostics to parameters and verify use counts remain separate across functions.
- [x] Implement the call/return contract from section 9.
- [x] Add frame limits and source-level call traces.

Acceptance: the exact programs in section 5 run; recursive factorial and nested-call fixtures pass; excessive recursion produces a guest diagnostic instead of exhausting the Zig call stack.

### M5 — Complete the MVP contract

- [x] Finish `check`, `run`, and `dump-bytecode` with the documented output/status behavior.
- [x] Finish source-error and runtime-error fixtures, including integer boundaries.
- [x] Add readable messages for missing returns, missing `main`, duplicate declarations, and invalid calls.
- [x] Verify explicit-discard errors and binding warnings have stable codes/spans and deterministic order; warnings preserve each command's normal stdout and exit status.
- [x] Reject excessive parser nesting with a diagnostic; a default nesting budget of 256 is sufficient initially.
- [x] Check emitted jump targets and IDs, and ensure host allocations are cleaned up on failures.
- [x] Run the same semantic fixture suite with the host built in Debug and ReleaseFast.
- [x] Document implemented syntax and unsupported features.

Acceptance: every check in section 13 is satisfied. Stop feature expansion and try writing small programs.

No calendar estimate is attached: compiler experience, diagnostics quality, and time available will dominate. The milestone boundaries are intended to make progress assessable without requiring a schedule.

## 12. Validation that earns its maintenance cost

Use small fixtures to exercise semantics, not tests that merely reproduce implementation details. Each fixture should specify its source, expected result or diagnostic code, and the important source span. Use stable diagnostic codes so changing prose does not invalidate every test.

| Area | Representative acceptance check |
| --- | --- |
| Precedence | `1 + 2 * 3` returns 7; `(1 + 2) * 3` returns 9 |
| Operand order | `20 - 6 / 2` returns 17 |
| Integer limits | Minimum and maximum literals accepted; one step outside the allowed range rejected |
| Overflow | Maximum plus 1, minimum minus 1, overflowing multiplication, and negated minimum trap |
| Division | `-7 / 3` returns -2; zero divisor and minimum divided by -1 trap |
| Remainder | `-7 % 3` returns -1; `7 % -3` returns 1; minimum remainder -1 returns 0 |
| Type checks | Boolean arithmetic, integer conditions, and incompatible assignments rejected |
| Scope | Out-of-scope names, active shadowing, and parameter mutation rejected |
| Explicit discard | `fn main() -> i64 { discard 1 + 2; return 7; }` returns 7; discarding a boolean is accepted; bare `1 + 2;` and bare helper-call statements get `E_EXPLICIT_DISCARD_REQUIRED` |
| Discard evaluation | `discard 1 / 0;` checks successfully and traps on execution; `discard false && (1 / 0 == 0);` does not trap; discarded helper calls return with balanced stacks |
| Binding warnings | An unread local/parameter gets `W_UNUSED_BINDING`; `let mut x = 1; return x;` gets only `W_UNNECESSARY_MUT`; assignment targets, compound assignments, and `discard x;` follow section 7's read/write rules |
| Resolved identity | Same-spelled bindings in different functions or sibling blocks have independent use counts; a read of one cannot mark another used |
| Control flow | Both outcomes of `if`, zero-iteration loops, and multi-iteration loops |
| Short-circuiting | `false && (1 / 0 == 0)` and `true || (1 / 0 == 0)` do not trap |
| Left-to-right order | Use two distinct failing operands and assert that the left failure is reported first |
| Calls | Forward call, mutual recursion, nested calls, and wrong arity/type rejection |
| Frames | `1 + add(2, 3)` returns 6 and recursive factorial of 5 returns 120 |
| Returns | Wrong return type, missing return, and unreachable following statements rejected |
| Entry point | Missing, duplicate, parameterized, or boolean-returning `main` rejected |
| Budgets | Infinite loop and excessive recursion stop with located diagnostics |
| Diagnostics | LF and CRLF input produce correct line numbers; EOF errors identify the end position |
| Advisory behavior | A valid program with warnings still checks, dumps, and runs with exit 0; stdout remains result-only or bytecode-only as appropriate; warnings go to stderr in stable order |
| Mode independence | Same valid results and guest traps in Debug and ReleaseFast |

Boolean expressions can be tested through helpers or an `if` in an integer-returning `main`. Do not silently broaden the CLI entry-point rule to accommodate a test.

Use targeted unit tests for precedence and integer edge cases, then end-to-end fixtures for the overall contract. A few malformed-input smoke tests are useful; extensive fuzzing can follow once the pipeline stabilizes.

The build's test target should exercise the actual CLI as well as internal functions. Propagate the selected host optimization mode to both the compiler executable and its test targets.

## 13. MVP definition of done

- [x] A clean checkout builds with the documented Zig version.
- [x] All three CLI commands behave as specified.
- [x] Every included feature in section 4 has a positive or negative fixture as appropriate.
- [x] The sum, GCD, recursive factorial, and nested-call programs pass.
- [x] Semantic errors are rejected before execution, including in unused functions.
- [x] Bare expression statements are rejected; explicit discard preserves evaluation and releases exactly one operand-stack value on normal completion.
- [x] Binding warnings use resolved identities, have stable codes/spans, and do not change successful command output or exit status.
- [x] Guest arithmetic and resource failures are located diagnostics, not host panics.
- [x] Calls and loop iterations do not accumulate abandoned locals, frames, or operand values.
- [x] The semantic suite passes in Debug and ReleaseFast.
- [x] The instruction dump is deterministic for the same source and compiler version.
- [x] Source locations survive parsing, checking, lowering, and execution.
- [x] Repeated compilation/execution in the test process releases request-owned allocations.
- [x] Unsupported features and the actual language rules are documented.

This is the stopping point for MVP implementation. A native executable produced from a guest program is not required.

## 14. What to measure during the experiment

Separate host build time, guest frontend time, guest lowering time, and guest VM execution time. A Zig build of the compiler and the compiler processing a `.my` file are different measurements.

Once the MVP is correct, add lightweight phase timing and counts for source bytes, AST/typed nodes, and instructions. Use a generated source file containing many small functions to find obvious frontend scaling problems. Use a loop program to inspect VM behavior separately.

Record the machine, exact Zig version, host optimization mode, and input size when comparing runs. Set performance targets after collecting a baseline. Tiny examples cannot establish that the eventual language will compile large projects quickly.

Do not judge potential native performance from the stack interpreter's speed. Use the interpreter to validate semantics and expose implementation mistakes.

When advisory analysis is introduced, measure its incremental time separately from required semantic checking. Assess duplicate findings on reviewed examples, recording whether a finding exposed drift, suggested worthwhile reuse, or merely matched unrelated code. Include test fixtures and intentionally separate implementations in the evaluation corpus. Similarity scores, warning counts, and reductions in line count are not themselves evidence of improved correctness.

## 15. Next experiments after the MVP

Implementation update (2026-09-05): exact scalar duplicate discovery in track T
is now implemented as a separate advisory command. [Bounded approximate discovery](experiments/approximate-discovery.md) also reports near matches with canonical edits and explicit work limits. [Static quality reports](experiments/quality-reports.md) now expose resolved calls, binding counts, and configurable structural metrics separately from runtime coverage. [Canonical formatting](experiments/formatter.md) now preserves tokens/comments and supports syntax-only formatting checks. [Project verification](experiments/verification-driver.md) now executes an explicit manifest with filtered-scope reporting and separate correctness/timing evidence. See
[the experiment record](experiments/duplicate-discovery.md) and
[post-MVP tracking](experiments/roadmap.md). A1 now includes records, complete construction, field access, preserving
updates, declarative complete conversions, checked integer widths/casts, and
[fixed arrays with checked indexing](experiments/arrays.md). A1 is complete.
A2 now includes [nominal scalar domains and private construction](experiments/domains.md);
[closed variants and exhaustive matching](experiments/variants.md) are also implemented.
[Complete enum-indexed tables](experiments/tables.md) finish A2. Borrowing and
slices are in progress: [B has a tested memory/lease registry and scoped source references](experiments/borrowing.md),
including static access checking, VM cleanup, and shared/exclusive reference
parameters. [Bounded slices and checked narrowing](experiments/slices.md) are also
implemented. [Returned-reference lifetime contracts](experiments/returned-references.md)
complete B; see [the acceptance audit](experiments/b-audit.md). C/D now have
[typed recoverable results and checked handling obligations](experiments/results.md).
[Explicit propagation](experiments/propagation.md) now preserves error obligations
and borrow cleanup. [Owned-buffer transfers and partial-acquisition cleanup](experiments/ownership.md) now have backend acceptance evidence. [Source buffer acquisition, moves, wrappers, and partial-construction cleanup](experiments/owned-buffers.md) are also implemented. [Buffer queries, mutations, and checked borrowed views](experiments/buffer-operations.md) are also implemented. [Transitive allocation bounds and inference](experiments/effects.md) are implemented. [Explicit allocator capabilities](experiments/allocator-capabilities.md) are now required for acquisition and growth. [Clock/random capabilities and injected provider operations](experiments/external-capabilities.md) now contribute transitive effects. [External resource ownership, fallible completion, and scoped cleanup](experiments/external-resources.md) now have backend acceptance. [Source resource acquisition, explicit completion, owned error returns, and cleanup effects](experiments/source-resources.md) are now implemented with injected filesystem/network providers. [Non-consuming copyable field reads](experiments/owned-field-reads.md) now support code-dependent completion retry. [Bounded environment capabilities and lookup](experiments/environment.md) now use injected providers and transitive effects. [Owned resource reads/writes](experiments/resource-io.md) now expose bounded bytes, explicit EOF, and partial write progress through injected providers. [Resource operation permission attenuation](experiments/attenuation.md) now narrows grants monotonically and constrains provider acquisition and owned operations. [Borrowed resource slice I/O](experiments/resource-slices.md) now supports exclusive array/buffer destinations and writes of populated ranges with lifetime checks. [Typed-handle pools](experiments/typed-pools.md) now have backend graph, generation, snapshot, and bulk-clear acceptance. [Arena backing and checked region reset](experiments/arenas.md) now have backend borrow, snapshot, identity, and storage-reuse acceptance. [Execution-lifetime arena selection](experiments/arena-execution.md) now runs source programs through the VM and CLI. [Scalar native execution](experiments/native-execution.md) now emits C compiled by the pinned Zig toolchain, with shared scalar value/trap acceptance. [Partial record field moves](experiments/partial-fields.md) now preserve remaining field access, immediate ownership transfer, cleanup, and result obligations. [Source pools and nominal handles](experiments/source-pools.md) now integrate graph operations, checked IDs, shared quotas, snapshots, and ownership cleanup. [Checked region backing](experiments/region-backing.md) now shares arena lifetime guards between buffers and pools while retaining independent snapshots. [Lexical source arena scopes and conservative escape checking](experiments/source-arenas.md) now preserve allocator/owner lifetime boundaries through wrappers, calls, mutation, and cleanup. [Explicit source arena reset operations/results](experiments/arena-reset.md) now reclaim unused chunks with live-owner/child guards while preserving allocator authority. [Module header discovery](experiments/module-discovery.md) now loads bounded import graphs with deterministic ordering and cross-file cycle diagnostics; [module interface indexing](experiments/module-interfaces.md) now parses bodies, resolves declaration identities, and checks explicit exports and signature visibility. [Source maps and AST relocation](experiments/module-source-mapping.md) now retain module ownership and original locations through diagnostics and execution traces. [Cross-file type checking and VM execution](experiments/module-execution.md) now run shared-domain programs with private boundaries, nominal identities, and the existing ownership/effect rules. [Optional dependency-direction policy](experiments/import-policy.md) now evaluates resolved imports with explicit ordered rules and a separate policy verdict. [Module duplicate discovery](experiments/module-duplicates.md) now reports cross-file exact/near matches with qualified type/callee identities. [Module quality reports](experiments/module-quality.md) now distinguish entry-main reachability from exported interface roots. [Module formatting](experiments/module-formatting.md) now supports syntax-only file output and reachable-project checks. [Scalar module native execution](experiments/module-native.md) now has executed VM/native result/trap/path/trace parity. [Native nominal scalar domains](experiments/native-domains.md) now preserve domain identity/privacy and instruction-budget parity. [Native closed enums](experiments/native-enums.md) now preserve nominal tag identity, exhaustive dispatch, and instruction-budget parity. [Native packed variants and results](experiments/native-variants.md) now support nested scalar payloads, exhaustive matching, result transfer/acknowledgement/propagation, and packed layouts up to 127 bits. [Native ordinary aggregates](experiments/native-aggregates.md) add records, arrays, tables, conversions/updates, partial result field transfers, boxed payloads and wider variant layouts, with executed allocation-failure cleanup and bounded live-storage acceptance; [Native borrowing and slices](experiments/native-references.md) add scoped loans, reference/slice parameters, returned-reference contracts, snapshot-preserving writes, and checked access with executable parity; native resources remain pending. [Approximate header indexing](experiments/approximate-discovery.md) now skips incompatible pairs with bounded deterministic work and generated scaling acceptance; banded edit-distance comparison retains full-matrix match/explanation parity while reducing comparison storage and work. [Module graph boundary acceptance](experiments/module-scaling.md) now exercises 256-module chains and 4,096-import shared graphs through CLI checking, execution, and tooling. [Restricted project evaluation](experiments/restricted-evaluation.md) now establishes parameter-free/effect-free execution with explicit step, frame, and VM-allocation budgets. [Evaluation reports](experiments/evaluation-reports.md) now record loaded sources/imports, compiler identity, budgets, and a deterministic request digest; request-only mode computes the same identity after checking eligibility without running the VM. [Persistent evaluation caching](experiments/evaluation-cache.md) now reuses successful matching results after fresh frontend/eligibility checks and can explain field-level changes against a chosen prior request. [Typed scalar input manifests](experiments/input-manifests.md) now validate names/types/values and generate deterministic imported modules; repeated --inputs bindings supply fresh in-memory modules for evaluation and cache lookup, preventing stale generated-file reuse and rejecting conflicting modules under explicit count/byte limits. [Checked public schema derivation](experiments/schemas.md) now emits deterministic exported type graphs and function contracts, preserving nominal identities, opaque domain/resource boundaries, and checked borrowing/effects. [Typed JSON serialization](experiments/typed-json.md) now validates ordinary checked values and emits canonical versioned documents under explicit limits, preserving nominal identities and rejecting opaque dependencies. [Standalone Python data bindings](experiments/python-bindings.md) now derive nominal classes and compatible bounded codecs from fresh checked schemas, with deterministic generation, explicit unsupported types, and atomic installation. [Incremental binding artifact reuse](experiments/binding-cache.md) now records schema/generator/compiler/Python/limit requests, skips generation on validated cache hits after fresh checking, and preserves unchanged output timestamps. [Checked schema source receipts](experiments/schema-receipts.md) now identify all loaded sources and the actual compiler image, with fresh provenance in binding reports even on artifact cache hits. [Typed JSON failure locations](experiments/codec-diagnostics.md) now identify nested fields/elements/payloads through bounded owned JSON pointers while preserving cleanup and allocation-error classification. [Initial ordinary-application corpus review](../examples/corpus/README.md) now exercises an invoice calculator and borrowed packet decoder across 13 modules, with independent execution expectations, reviewed exact/near duplicates, quality/policy checks, and change-impact/schema/binding acceptance. This authored corpus does not establish production readiness or independent-user evidence. [Typed invocation](experiments/typed-invocation.md) now calls exported effect-free functions with bounded owned argument copies and typed results, providing the execution foundation for checked domain factories. [Explicit domain codec contracts](experiments/domain-codecs.md) now associate ordinary wire types with public effect-free methods, require exact decoder result signatures, and derive opaque-preserving schema metadata. [Executed domain JSON codecs](experiments/domain-json.md) now use those methods during nested traversal and CLI round trips, with shared memory/step/call/work limits and located typed rejections or source traps. [Schema-pinned public JSON calls](experiments/checked-calls.md) now invoke exported functions from named wire arguments, validate the expected public schema before execution, and share budgets across argument decoding, the target call, and result encoding. [Generated Python calls](experiments/python-calls.md) now provide nominal function wrappers and domain wire objects over schema-pinned public invocation, with explicit compiler/project selection, budgets, and transport failures. [Declared call inputs](experiments/call-inputs.md) now supply fresh in-memory manifest modules to schema generation, codecs, and Python calls, preserving source receipts and compatible artifact reuse. [Incremental module syntax](experiments/incremental-syntax.md) now reuses exact parse tables across fresh embedding projects under retention limits while rerunning semantic checks. [Persistent checking sessions](experiments/check-session.md) now reuse syntax across explicit CLI requests while reloading files/manifests and rerunning semantic checks, with bounded framing and status/cache reports. Source serialization operations, native ABI bindings, persistent/semantic query reuse, automatic watching, and other unfinished tooling remain pending. Generics, remaining compile-time/schema/incremental work, native expansion, and the other unfinished work below remain pending.

| Stage | Scope | Question to answer before proceeding |
| --- | --- | --- |
| A1: aggregate values and complete conversions | Structs, fixed arrays, checked indexing, additional integer widths, complete construction, preserving updates, and declared complete conversions | Does adding a field identify incomplete constructions and conversions, including a newly ignored source field? |
| A2: domain types and exhaustive mappings | Nominal scalar wrappers, private constructors, closed enums/tagged unions, exhaustive matching, and enum-indexed tables | Can domain units and identities stay distinct, and does adding a variant expose every mapping that promised complete handling? |
| B: borrowing | Shared/exclusive references and slices, initially with deliberately restricted lifetimes | Can common functions be expressed and invalid accesses rejected with understandable errors? |
| C: ownership, capabilities, and effects | Owned buffers, resource transfer, partial-construction cleanup, allocator/external capabilities, small no-I/O and no-allocation contracts, arenas/pools | Are acquired resources cleaned up on recoverable failure, and can a caller verify transitive resource and external-access costs? |
| D: errors and abstraction | Typed fallible results, propagation, deliberate-error acknowledgement, limited generics, typed handles | Are important results handled explicitly, and do abstractions preserve ownership, effects, and understandable diagnostics? |
| M: modules and interfaces | Explicit exports, private implementation, resolved imports, and optional dependency-direction policies | Can shared domain rules live behind usable interfaces without exposing unrelated implementation details? |
| E: native execution | One native code-generation route and shared semantic fixtures | Does native execution implement the same observable rules as the VM? |
| F: compile-time work, schemas, and incremental builds | Restricted evaluation, declared inputs, typed serialization/schema derivation, generated bindings, dependency recording, invalidation | Do generated representations stay consistent, and can generation cost and rebuild causes be explained and measured? |
| T: compiler-assisted quality tooling | One formatter; exact structural duplicate discovery followed by approximate matching; reference/complexity reports; a separate project-verification driver | Do findings lead to useful improvements without unstable verdicts or forced abstractions? |

Treat this as an experimental sequence, not a promise to finish each row before learning from the next. A small native backend experiment may be useful earlier if it exposes a representation problem.

Experiments M and T are companion tracks, not prerequisites for the scalar MVP or every later feature. Introduce module support when programs need shared interfaces. Begin duplicate discovery after real programs provide a reviewable corpus. Bring a minimal recoverable-error representation from D into C as needed to test allocation failure and cleanup; the full error/generic design can follow. Typed serialization requires the aggregate and variant model; cross-language generators should follow the declared-input and resource-budget discipline of F.

Before adding pointers, choose a VM memory representation with allocation identity, bounds, and lifetime information. Host pointers alone would make it difficult to diagnose invalid guest memory operations. Before adding aggregates, decide their copy, address, and storage semantics; the current two-variant `Value` is only a scalar MVP representation.

A compiler written in a manually managed language does not prevent the new language from enforcing memory safety. Conversely, this scalar VM does not prove that a future borrow checker is sound.

For native code generation, evaluate one route when there is a concrete program to compile. LLVM integration or emitting C are possible experiments; neither belongs in the first milestone. Do not begin with a custom machine-code backend, register allocator, linker, and debugger integration simultaneously.

The interpreter may later help implement compile-time evaluation, but runtime interpretation alone does not supply deterministic inputs, target-aware semantics, or caching. Cross-compilation requires guest types and layout to follow the target, not the host.

Self-hosting should follow a useful, stable subset and reliable tests. It is not a prerequisite for validating the design.

## 16. Suggested first implementation task

Start with M0 and M1 only. This is a suitable instruction to give an implementation agent or use as the first issue:

> Create a Zig project for the scalar-language MVP in this plan. Use the pinned Guardian Zig snapshot, `0.17.0-dev.1683+5ceec001b`, and record its exact version. Implement the smallest complete pipeline that accepts `fn main() -> i64 { return 1 + 2 * 3; }`, checks it, lowers it to an inspectable instruction list, and executes it to produce `7`. Keep the untyped AST, typed representation, and VM instructions separate. Include source spans, a readable instruction dump, checked addition/subtraction/multiplication, and focused precedence and malformed-input tests. Do not add locals, branches, function calls, native code generation, or future-language syntax until this vertical slice works. Report the implemented subset, commands, and test results.

After that works, proceed milestone by milestone. Keep any design change in `docs/semantics.md` and update the relevant fixtures in the same change.

## 17. Implementation references and status

The scalar syntax, VM format, semantics, and budgets in sections 4–13 are implemented in the sibling `mylang` repository. See [mvp-audit.md](mvp-audit.md) for the requirement-by-requirement evidence and [progress.md](progress.md) for milestone verification. M0–M5 are complete. Post-MVP implementation progress is tracked in section 15 and the experiment records; other features remain proposals. No performance claims are made.

Guardian now checks the Zig implementation itself on build, test, run, and local
commits. The strict policy blocks violations with baselines disabled; no frozen
violations are accepted. Compiler/runtime refactors remove blocking complexity,
dependency, ownership, and test-quality findings. This host-code gate is separate
from the language's own source checks. See the compiler-quality milestone in
[progress.md](progress.md) for validation and integration limits.

Official Zig reference checked for the host arithmetic mechanisms:

- [Zig 0.15.1 language reference](https://ziglang.org/documentation/0.15.1/).
- [Overflow-reporting addition](https://ziglang.org/documentation/0.15.1/#addWithOverflow).
- [Overflow-reporting subtraction](https://ziglang.org/documentation/0.15.1/#subWithOverflow).
- [Overflow-reporting multiplication](https://ziglang.org/documentation/0.15.1/#mulWithOverflow).
- [Truncating division](https://ziglang.org/documentation/0.15.1/#divTrunc).
- [Signed remainder](https://ziglang.org/documentation/0.15.1/#rem).

These are versioned references, not a claim that 0.15.1 is the latest Zig release or a requirement to adopt that version. These historical arithmetic references do not select the toolchain. Verify library and build APIs against the pinned Guardian snapshot at M0; consult its bundled standard-library source for exact APIs.

Revision 2 also draws on a read-only review of Guardian's source and recorded usage feedback. The following are local design evidence and documented incidents, not new defect-rate measurements:

- [Projection completeness: omitted defaulted fields and ambiguous type-name matching](/home/epentland/ai/canopy/guardian-zig/src/checks/projection_completeness.zig:5).
- [Constructor cleanup: the limits of counting `try` and `errdefer`](/home/epentland/ai/canopy/guardian-zig/src/checks/errdefer_in_init.zig:53), and [resource-container copies](/home/epentland/ai/canopy/guardian-zig/src/checks/must_return_ref.zig:1).
- [Filesystem dependency policy](/home/epentland/ai/canopy/guardian-zig/src/checks/ban_fs.zig:5) and [domain vocabulary's lexical limits](/home/epentland/ai/canopy/guardian-zig/src/checks/measure_vocabulary.zig:31).
- [Concept ownership and stale cross-language mirrors](/home/epentland/ai/canopy/guardian-zig/src/checks/concept.zig:27), and [twin parity's test-presence contract](/home/epentland/ai/canopy/guardian-zig/src/checks/twin_parity.zig:18).
- [Duplicate discovery without identifier resolution](/home/epentland/ai/canopy/guardian-zig/src/checks/twin_drift.zig:633), [scoring stability study](/home/epentland/ai/canopy/guardian-zig/docs/twin-drift-scoring-study-2026-09-02.md), and [deduplication interacting with layering policy](/home/epentland/ai/canopy/guardian-zig/FEEDBACK.md:11192).
- [Name-only reference counting limitation](/home/epentland/ai/canopy/guardian-zig/src/checks/dead_pub.zig:19) and [Guardian's distinction between duplicated knowledge and coincidental similarity](/home/epentland/ai/canopy/guardian-zig/FRAMEWORK.md:158).

Language/tooling precedents consulted in that review:

- [Rust diagnostic attributes](https://doc.rust-lang.org/reference/attributes/diagnostics.html): `must_use`, configurable lint severity, and lint expectations. These illustrate mechanisms; this plan defines its own scalar-discard rule.
- [Rust record update expressions](https://doc.rust-lang.org/reference/expressions/struct-expr.html#functional-update-syntax): explicit updates obtain remaining fields from an existing value.
- [Koka effect types](https://koka-lang.github.io/koka/doc/book.html): effects represented in function types. The proposed systems language begins with a much smaller experiment.
- [Cap'n Proto schema language](https://capnproto.org/language.html): generating language bindings from a shared typed message definition.

## 18. Proposed quality contracts after the MVP

These proposals guide the experiments in section 15. They do not extend the MVP grammar or definition of done. Except for the explicit scalar-discard syntax and advisory rules already specified in sections 6–7, syntax remains open. Prove each design on small programs and add semantic fixtures before making it permanent.

### 18.1 Enforcement boundaries

| Layer | Examples | Contract |
| --- | --- | --- |
| Language semantics | Types, ownership, complete initialization, explicit discard, declared effect bounds, exhaustive cases | A violation is a source error. Advisory suppression or accepting a baseline cannot make the program valid. Runtime checks remain where the language requires them. |
| Compiler-assisted analysis | Suspected duplication, unused declarations, nesting, function size, complexity | Findings explain a concern using resolved semantic information where available. Heuristics are advisory by default and do not redefine runtime semantics. |
| Declared project policy | Import direction, approved public surface, documentation requirements | Projects choose these constraints. Evaluate them against resolved interfaces/graphs when available; distinguish policy failures from invalid language constructs. |
| Project verification | Tests, mutation testing, specification links, benchmarks, compatibility and change-history checks | A driver runs these separately from ordinary semantic checking. A language/toolchain may ship the driver without requiring every compilation to execute it. |

Pin analysis versions/configuration when a project elects to gate advisory findings. A similarity score whose inputs include other files can change when those files change; do not make such a score a language-validity rule. A later suppression mechanism should be narrow, carry a reason, and report stale expectations. It must apply only to analysis/policy findings, never to type or ownership errors.

### 18.2 Complete construction, preserving updates, and conversions

Distinguish three operations:

1. **Construction:** provide each destination field. Make defaults available through explicit, named constructors rather than silently filling omissions in ordinary literals.
2. **Update:** start from an existing value of the same nominal record type, change named fields, and preserve the rest. Define moves/copies and borrowing before introducing this operation for resource-owning records.
3. **Declared complete conversion:** account for every field in the designated source record and initialize every destination field. Each source field must be preserved, transformed, or explicitly discarded. The explicit discard names the field so adding a new source field creates a new obligation.

Do not impose source-field completeness on arbitrary computations: a function computing a board's width legitimately reads only the geometry it needs. Completeness is a declared conversion contract, not a claim that every function must read every field of its inputs.

Prototype conversions using explicit field mappings and resolved type/field identities. Calling a helper with the whole source value must not automatically prove that every field was accounted for; delegation needs a checked complete-conversion contract of its own. Blanket omission of all remaining fields would defeat the change-detection promise and should not satisfy this contract.

An explicit default constructor communicates a deliberate policy, but cannot prove that its use in a conversion preserved source data. Complete conversion checking still accounts for the source fields. Constructors and defaults are not a substitute for that requirement.

Representative diagnostic, with illustrative type names:

```text
error[E_INCOMPLETE_CONVERSION]: conversion from Routes to Copper
  does not account for source field `arcs`
help: preserve or transform `arcs`, or explicitly discard that field
```

The check establishes structural accounting, not that a transformation computes the correct value. Keep behavioral tests for that. The compiler's actual type identities should also let the rule work on inferred record literals without mistaking an unrelated record with similar field names for the source or destination type.

### 18.3 External capabilities and transitive effects

Begin with explicit capability parameters and a small set of effects: allocation, filesystem access, networking, clock reads, randomness, and environment access. Choose capability creation at entry/runtime boundaries; ordinary safe library code must not be able to manufacture unrestricted capabilities from nothing or retrieve them through ambient mutable state. A capability may represent restricted authority, such as a single open directory.

Infer effects for ordinary direct calls and allow explicit bounds at public interfaces. Check an asserted no-I/O or no-allocation bound transitively, including calls through wrappers, generated operations, and cleanup. Mutable local variables alone need not imply external I/O. A no-allocation function may receive and modify already-allocated storage; container operations using existing capacity should make that distinction expressible.

Define which effects each bound excludes; a no-I/O label alone must not imply determinism if clock reads, randomness, or external mutation are still permitted. Keep arithmetic traps and possible divergence separate from these bounds. Do not attempt totality checking in this experiment.

For recursion, compute conservative summaries until they stop changing. When function values, generics, or FFI arrive, calls need explicit or inferred effect summaries. Unknown effects cannot satisfy a restrictive bound. Foreign declarations form an explicitly trusted boundary; the compiler cannot verify an external implementation merely because its declaration claims an effect bound.

Use fake capability implementations in tests. Validate both direct forbidden access and a helper that performs it transitively. Avoid an ambient injection mechanism that silently reintroduces the dependencies this design is meant to expose.

### 18.4 Resource obligations and fallible results

Check ownership for each acquired value along control-flow paths. A resource remains owned until transferred or cleaned up; it cannot become two independent owners through an ordinary copy. On recoverable failure during construction, release the already-acquired resources exactly once. Borrowing a capability or allocator does not itself mean owning every resource that capability can create.

Prototype partial construction, early returns, movement into aggregates, container growth while borrowed, and nested scopes. Keep resource information in the semantic model rather than recognizing conventional names such as `init`, `deinit`, or `ArrayList`.

Define cleanup order and its effects. Require an explicit result-returning operation for fallible completion such as `commit` or durable flushing; a fallback cleanup path may roll back or release storage but must not imply that the requested operation succeeded. Specify the treatment of traps before exposing guest resources. Do not promise cleanup following process termination or a host failure that prevents execution from continuing.

Once typed errors arrive, public APIs declare their fallible result types and callers handle or propagate them. A deliberate error-ignoring operation must acknowledge that failure may have occurred. Converting failure to an ordinary absence/default is an explicit error-handling decision, not an implicit coercion. Design the result obligation so merely wrapping, binding, or ordinarily discarding a value does not silently erase it.

### 18.5 Domain identity, exhaustive cases, and shared representations

Start with nominal wrappers over existing scalars and explicit construction/conversion. Distinguish values such as millimeters, seconds, byte counts, element counts, board IDs, and net IDs even when their storage representation is identical. Preserve runtime checks for bounds, overflow during conversion, stale pool handles, and other properties that these types do not prove. General dimensional algebra is deferred until concrete programs justify it.

For closed variants, distinguish an exhaustive decision from a deliberate fallback policy. Mappings that promise to expose every new variant must enumerate cases individually; a wildcard would otherwise absorb the new variant. Protocols that need forward compatibility may represent unknown external values explicitly, with a deliberate handling policy.

An enum-indexed table must have exactly one entry per variant. A typed serialization schema must reject duplicate statically declared external keys. Dynamic maps and handwritten output remain subject to runtime validation; these guarantees apply to the typed schema path.

Use a shared definition for domain identifiers and their external spellings, metadata, serializers, and generated bindings where practical. Keep generation deterministic, bounded, and based on declared inputs. Generated structure does not prove that independent CLI, HTTP, native, or browser implementations behave identically. Reuse the domain operation and retain shared behavioral/parity tests for the adaptations around it.

### 18.6 Duplicate discovery and explicit relationships

Prevent duplicated knowledge through domain types, shared constants, complete mappings, schemas, and usable module interfaces. Complement this with discovery in compiler-assisted tooling once real programs exist.

Start with exact structural candidates from the checked representation before optimization. Consistently rename bound locals/parameters for comparison while preserving nominal types, resolved callees and fields, literal values, operators, evaluation order, and effects. Hashes may select candidates; compare the structure before claiming an exact match. Recursive functions need an explicit normalization policy rather than accidental dependence on compilation-local ID numbering.

Add approximate matching only after reviewing the exact-matching results. It may identify candidates with renamed helpers or changed constants, but should show those differences rather than erase them from the final explanation. Index candidates to avoid comparing every function with every other function. Run expensive discovery separately from the small mandatory frontend passes.

Report both source locations, shared structure, meaningful differences, and any existing canonical helper. Explain whether the finding is an exact structural match or approximate similarity. Neither establishes that two functions represent the same domain policy or proves general behavioral equivalence. Do not automatically merge them.

Treat generated code, independent test expectations, protocol implementations, and intentionally separate policies as distinct populations in analysis. Allow reviewable intentional duplication; tests should not derive every expected value from the same implementation they are checking.

When a programmer declares a relationship, check the concrete promise: a constant mirror equals its referent, an enum table covers all variants, or an alternative implementation participates in a named parity suite. Resolve referenced declarations and test identities. Test presence does not establish execution, and successful tests establish agreement only for the inputs and properties exercised.

### 18.7 Simplicity, interfaces, and project verification

Favor a small language with explicit public signatures, private implementation details, local inference, composition, visible effects, and generics with stated requirements. Add module interfaces when sharing domain code becomes necessary; check that public signatures expose usable public types or deliberately declared opaque types. Keep a project's dependency-direction policy separate from language semantics.

Ship one formatter. Keep line length, function length, parameter count, nesting, and complexity thresholds as configurable review signals. These differ from parser/VM resource limits, which protect the implementation. An exhaustive table or coherent record can legitimately be large; splitting it only to satisfy a counter can make maintenance harder. Explain interactions when a suggested extraction would violate a declared module boundary or add other costs.

Build later reference reports from resolved declarations, not identifier spelling. Distinguish private dead code from public entry points that may be used outside the current compilation. A test referencing a function is not evidence that the function ran or that its behavior was asserted; report static reachability, runtime coverage, and verification outcomes separately.

The project-verification driver may run tests, shared backend fixtures, mutation tests, specification-link checks, and benchmarks. A filtered test run must report what it selected and must not claim that unchecked tests compiled or the full suite passed. Keep correctness checks independent of host-load-sensitive performance thresholds. Compiler analysis can supply identities and source maps without taking on all workflow execution.

### 18.8 Acceptance experiments for the proposals

These are future-feature fixtures, not additional M0–M5 requirements.

| Proposal | Positive and negative evidence to obtain |
| --- | --- |
| Complete construction | Adding a destination field breaks incomplete literals; explicit constructors and updates behave as documented. |
| Complete conversion | Adding a source field breaks a declared complete conversion even when the destination type is unchanged; naming a deliberately discarded field satisfies its obligation; an unrelated geometry query remains valid. |
| Preserving update | A newly added field survives an update that changes another field; owned fields are moved or borrowed according to the chosen rules without implicit duplication. |
| Effect bounds | A no-allocation function using existing capacity passes; allocating through a helper or cleanup fails the bound; an unknown foreign effect cannot silently pass. |
| Partial construction | Failure acquiring B releases acquired A exactly once; success transfers ownership; later cleanup does not double-release. |
| Fallible results | Handling and propagation pass; a silently dropped result fails; deliberate error acknowledgement is explicit and preserves operand execution. |
| Nominal domains | Passing seconds where millimeters are required fails; an explicit checked conversion passes; unrelated constants may have equal numeric values. |
| Exhaustive mappings | Adding a variant exposes incomplete declared-exhaustive matches and enum tables; duplicate schema keys fail; unknown external values follow the chosen protocol policy. |
| Duplicate discovery | Renamed locals can still produce an exact structural candidate; differing domain types, callees, constants, or effects remain visible; legitimate independent implementations can remain separate. |
| Reference accuracy | Same-spelled declarations in different modules retain independent uses; test reachability is reported distinctly from executed coverage. |

Evaluate these experiments by the errors prevented, the clarity of diagnostics, the cost of implementation and compilation, and the code users must write. Keep uncertain heuristics advisory and revise proposals when realistic examples expose unnecessary complexity.


## Native owned-buffer implementation

Root allocator parameters, owned buffers, mutations, reserve, and borrowed buffer
slices now emit native C. Debug and ReleaseFast pass all 28 build steps, including
2,538 VM/native comparisons and 322 allocation-failure cases. Native pools and external resources,
and the remaining roadmap requirements are still open.


## Native lexical arenas

Native arena scopes, chunk backing, allocator identity, reset, and frame cleanup
are implemented. Debug and ReleaseFast pass all 28 build steps, including 2,568
VM/native comparisons and 380 allocation-failure cases. Native pools, external resources, and
the other unfinished roadmap requirements remain open.


## Native pools

Native pools now implement generation-checked handles, queries/mutations, snapshots,
shared quotas, and root/arena cleanup. Both compiler modes pass all 28 build steps
and 591 Zig tests; native acceptance covers 2,616 VM/native comparisons and 468
sanitizer allocation-failure cases.
External resources and the remaining roadmap work stay open.


## Native clock/random providers

Native clock/random capabilities now use explicit C provider adapters with typed
errors and pre-execution grant checks. Debug and ReleaseFast pass all 29 build
steps and 592 core/CLI tests, including 32 VM-checked provider comparisons and
14 provider allocation-failure cases.
Environment and external-resource native operations remain pending alongside the
other unfinished roadmap work.


## Native environment lookup

Native environment lookup now uses explicit provider ABI v2 with bounded byte
output, missing/empty distinctions, padding, and independent snapshots. Complete Debug and ReleaseFast acceptance passes all 30 build steps and 593
core/CLI tests, including 38 VM-checked environment comparisons and 56 injected
allocation failures plus builder/ABI rejection checks. Native filesystem/network resources and remaining roadmap
work remain open.

## Native resource cleanup foundation

Native frame returns now destroy locals in reverse slot order, matching the VM.
An executable harness covers local/operand/schema order, shared snapshots, and
20,000-level nonallocating destruction. Complete Debug/ReleaseFast acceptance
passes all 30 build steps and 593 core/CLI tests, plus the native memory checks.
Emergency ownership unwind and filesystem/network resource operations remain
pending prerequisites for complete native execution.

## Native emergency ownership unwind

Native emergency cleanup now tracks temporary acquisition order and reconstructs
ownership roots without allocating, preserving temporary/operand/local/schema
destruction order. Debug and ReleaseFast pass all 30 build steps and 593 core/CLI
tests, including ten explicit trap/OOM ordering cases and the existing 468 native
allocation-failure cases under sanitizers. Native resource callbacks, propagation
sequencing, and remaining roadmap work stay open.

## Native propagation allocation order

Native error propagation now boxes its outgoing result before releasing unfinished
operands. An allocation-failure regression reproduces the previous reversed cleanup
order and verifies the correction at O0/O2 with sanitizers. Debug and ReleaseFast
pass all 30 build steps and 593 core/CLI tests; native memory acceptance now covers
484 injected allocation failures. Native filesystem/network provider integration
and all other unfinished roadmap requirements remain open.

## Native filesystem/network lifecycle

Native resource acquisition, retryable completion, permission intersection, nominal
owners, and failure cleanup are implemented through explicit provider ABI v3.
Debug and ReleaseFast pass all 31 build steps and 594 core/CLI tests. The new
driver checks 32 native outcomes (28 with exact VM callback trace comparisons)
and 120 injected lifecycle allocation failures under sanitizers.

Resource byte I/O, broader permission/quota/generation and mixed-store acceptance,
and the other unfinished roadmap requirements remain pending. This completes
the initial native lifecycle implementation, not full native resource support.

## Native resource byte I/O

Provider ABI v4 implements array/slice reads and writes with partial progress, EOF,
permission checks, snapshots, and failure-safe staging. All currently defined
bytecode operations have native emission. Debug and ReleaseFast pass all 31 build
steps and 595 core/CLI tests. Resource acceptance covers 114 outcomes, 104 exact
VM trace comparisons, and 392 injected allocation failures, plus quota/reuse and
mixed-store checks. The large sanitized quota compilation needs a separate
300-second test budget; observed O2 compilation took approximately 106–120 seconds.

Generation-exhaustion/stale-owner and simultaneous per-kind quota stress, native
embedding/performance, and all other unfinished roadmap requirements remain open.


### Native resource registry stress — 2026-09-06

Completed generation-exhaustion, stale-owner, registry-growth, and simultaneous
per-kind quota stress in the native runtime acceptance harness. Six O0/O2
sanitizer runs pass with zero retained allocations; mutation checks reject
unchecked generation wrap and stale-token release. Mirrored source quota fixtures
pass four exact VM/native trace comparisons, including acquisition from the other
provider family while one is full and reuse after cleanup. Mixed-store acceptance
passes two outcomes and 30 allocation failures. Guardian passes all 88 checks with
baselines disabled. This follow-up used focused acceptance; the prior full-suite
baseline remains 31 steps and 595 core/CLI tests. Native embedding/performance,
generics, source serialization, and finer incremental compilation remain open.


### Automatic project checking — 2026-09-06

Implemented `scripts/watch.py`: one persistent compiler session checks initially
and after content changes to module sources or declared manifests. Bounded polling
handles atomic replacement, deletion/recreation, nested imports, same-size edits
with preserved timestamps, and changes during an active check. Source/input
errors remain recoverable. Reply limits, timeout, SIGINT/SIGTERM, and child reaping
are explicit. The standard test build includes end-to-end watch acceptance.
See [watch behavior and acceptance](experiments/watch.md) for conservative
whole-source-tree invalidation and polling limits. Semantic query reuse,
persistent query storage, native incremental compilation/embedding, generics,
source serialization, and other unfinished roadmap requirements remain open.

Validation: the full ReleaseFast build passed all 32 steps (unchanged core/CLI test
steps reused cached results). Final focused watch acceptance passed with Debug
and ReleaseFast compiler builds. Guardian passed all 88 checks with baselines
disabled. Native resource acceptance passed 116 outcomes, 106 VM trace comparisons,
392 allocation failures, and six registry sanitizer cases.


### Native build publication and measurement — 2026-09-06

The native builder now stages guest C, trusted adapter compilation, and linking,
then atomically publishes complete executables. Identical executable bytes preserve
inode/timestamp; failures preserve the last successful output. `--report` records
generated-C identity, frontend/native elapsed time, and publication status while
explicitly stating that the driver does not reuse compilation. Fresh trusted
adapter cache storage prevents stale assembly `.incbin` inputs observed in the
regression fixture. Adapter compilation retains the caller's working directory.
Native compilation/query reuse, incremental linking, embedding/bindings, generics,
source serialization, and the remaining roadmap requirements stay open.

Validation: focused native-builder acceptance passes, including a failing-before
partial-output simulation and the changed `.incbin` regression. Scalar/module
parity passes all 2,616 comparisons; clock/random and environment acceptance pass
32/38 comparisons and 14/56 allocation failures. Final fixed-I/O resource selection
passes two VM/native traces, 28 allocation failures, and six registry sanitizer
runs. The build gate passes all 88 Guardian checks without baselines. This was
focused validation; no new full-suite result is claimed for this milestone.


### Declared-requirement generics: frontend stage — 2026-09-06

Added explicit type parameters with nonempty requirement lists and `::<...>` call
arguments to the AST/parser. Owned copies, mapped source spans, syntax-cache reuse,
formatter round trips, exported-signature privacy, and 16/17 list boundaries are
covered. Semantic preflight rejects these forms with `E_GENERIC_UNSUPPORTED`;
requirements are not yet resolved and templates cannot execute. Generics remains
open: requirement checking, bounded specialization, module/ownership/effect
integration, VM/native execution, and tooling acceptance are the next work.

Validation: the full core suite passed 540 tests in Debug and ReleaseFast, all 60
CLI tests passed, and the final generic-focused run passed seven tests including
the additional qualified-module formatting fixture. All Zig tests compiled and
the build gate passed all 88 Guardian checks without baselines. No executable
generic or native-specialization acceptance is claimed.


### Generic builtin requirement resolution — 2026-09-06

Added normalized `copy`, `equality`, and `integer` requirements, implication checks,
and concrete type matching using existing ownership/result contracts. Equality
uses the same predicate as ordinary expressions. Unknown requirements are rejected
in all templates, including uncalled private module declarations; malformed AST
inputs and allocation-failure cleanup are covered. Template-body checking and
executable specialization remain unsupported. General move-only/user-defined
requirements, bounded instance interning, substitution, backend/tooling integration,
and the rest of the roadmap remain open.

Validation: full core runs passed 546 tests in Debug and ReleaseFast; all 60 CLI
tests passed. The focused requirement run passed seven tests, including the added
module/private-template diagnostic case. The build passed all 88 Guardian checks
without baselines. These results validate requirement resolution/matching and
ordinary language regressions, not executable generics or template-body checking.


### Initial abstract generic body checking — 2026-09-06

Added symbolic checking of the pure builtin/type-parameter subset: locals,
assignment, returns, branches/loops, casts, arithmetic, and equality. Type-variable
identities remain distinct and operations require declared guarantees; no concrete
representative type is substituted. Literal validation is shared with the concrete
checker. Module scope, original diagnostics, allocation cleanup, and explicit
256-depth/100000-visit limits have acceptance coverage. Calls, nominal/composite
signatures, references, ownership/effects, and executable specialization remain
explicitly unsupported. Generics and the broader roadmap remain open.

Validation: all 554 core tests passed in Debug and ReleaseFast, all 60 CLI tests
passed, and the focused abstract-body run passed eight tests. The Guardian build
gate passed all 88 checks without baselines. These runs cover the implemented
symbolic subset and ordinary-language regressions; they do not establish executable
generics or completion of the full template-body contract.


### Abstract generic calls and requirement forwarding — 2026-09-06

Added indexed generic declaration lookup, explicit type/value argument arity,
requirement implication, and symbolic parameter/result substitution. Calls retain
module/domain privacy and cross-file diagnostic links; same-named declarations
remain distinct. Recursive calls check signatures without expanding bodies.
Allocation-failure acceptance covers local and module-backed checking. Concrete
helper summaries, broader abstract body forms, instance interning/substitution,
executable specialization, and the remaining roadmap stay open.

Validation: the full core suites passed 559 tests in Debug and ReleaseFast, all 60
CLI tests passed, and final generic-focused acceptance passed 25 tests. The build
gate passed all 88 Guardian checks without baselines. This validates abstract
calls and ordinary-language regressions; executable generic specialization and
completion of the broader roadmap remain unproven and unfinished.


### Pure concrete helpers in generic call graphs — 2026-09-06

Abstract generic checking now follows ordinary helper calls and validates all
transitively reachable bodies using the supported pure builtin rules. A worklist
bounded by declaration count visits each body once, including recursive cycles;
uncalled ordinary functions are left to concrete checking. Original module/domain
privacy and source locations survive traversal. Hidden clock operations reject
even behind constant-false branches. General effect/reference contracts, nominal
substitution, executable specialization, and other roadmap requirements remain open.

Validation: all 563 core tests passed in Debug and ReleaseFast, all 60 CLI tests
passed, and the build passed all 88 Guardian checks with baselines disabled.
Coverage includes helper cycles, shared callees, module/domain privacy, hidden
clock effects, invalid signatures/bodies, and allocation-failure cleanup. No
executable specialization or full native-suite result is claimed for this change.


### Bounded concrete specialization identities — 2026-09-06

Added an independently tested compilation-local instance registry keyed by
resolved declaration ordinal and ordered concrete type identities. Owned argument
copies, stable discovery IDs, existing-key reuse at capacity, nominal identity,
4096-entry/16-argument bounds, and allocation-failure recovery are covered.
The registry is not yet wired into executable lowering: call discovery,
per-instance type substitution, semantic/function-index migration, VM/native and
tooling integration remain unfinished. See `docs/experiments/generic-instances.md`
under docs/experiments. Generics and the broader roadmap remain open.

Validation: all 568 core tests passed in Debug; focused instance-table acceptance
passed six tests in Debug and ReleaseFast, including allocation-failure sweeps
and recovery. The build passed all 88 Guardian checks with baselines disabled.
This is registry and ordinary regression evidence; no new executable generic,
CLI, or full native-suite result is claimed.


### Executable pure generic specialization — 2026-09-06

Concrete semantic checking now separates source declarations from executable
instances, resolves callee signatures through concrete type arguments, and clears
touched expression cache entries between bodies. Recursive/repeated calls reuse
bounded specialization IDs; ordinary functions do not consume the 4096 generic
instance budget. The supported pure templates execute through VM/C lowering,
including integer widths, nominal copy values, and imported calls. Ordinary
public wrappers remain schema roots while internal instances are excluded.
General reference/effect/ownership contracts, direct generic schema/invocation,
user-defined requirements, and other roadmap tracks remain unfinished.
See `docs/experiments/generic-execution.md` for the current scope and boundaries.

Validation: full core runs passed 573 tests in Debug and ReleaseFast; all 60 CLI
tests passed. Final generic-focused acceptance passed 40 tests, including the
additional returned-reference identity regression. Native parity passed 2640
comparisons across 86 single-file and 16 module fixtures with -O0/-O2 and undefined
behavior sanitization; 50 final targeted codec comparisons passed after inserting
an uninstantiated template before codec functions. Guardian passed all 88 checks
with baselines disabled. No new full resource/provider-suite result is claimed.


### Generic borrowed input parameters — 2026-09-06

Abstract checking now distinguishes value, shared-reference and exclusive-reference
bindings. Supported templates read, write and forward reference inputs while
preserving symbolic types, access permissions, and ordinary alias rules. Duplicate
exclusive inputs reject even when forwarded to shared callee parameters; repeated
shared inputs remain valid. Calls use a temporary name table and count reference
arguments toward the work budget. Concrete instances retain ordinary borrow
validation and VM/C execution. Generic slices, lexical borrow scopes, returned
reference provenance, broader ownership/effects, and other roadmap work remain open.
See `docs/experiments/generic-references.md` for scope and acceptance.

Validation: all 576 core tests passed in Debug and ReleaseFast, all 60 CLI tests
passed, and native parity passed 2646 comparisons across 87 single-file and 16
module fixtures using -O0/-O2 and undefined-behavior sanitization. Guardian passed
all 88 checks with baselines disabled. Allocation-failure coverage includes local
reference forwarding and imported setter execution/schema generation. These
results do not establish the unfinished slice or returned-reference contracts.


### Generic slice input operations — 2026-09-06

Generic shared/exclusive slice inputs now support length, element reads/writes,
and forwarding. Abstract checks retain reference kind, symbolic element identity,
integer-index requirements, access permission, and alias rules. Concrete VM/C
instances retain runtime view lengths, bounds traps and immutable snapshots.
Imported slice helpers execute through ordinary public wrappers. Lexical generic
borrow scopes/narrowing, reference-result provenance, wider effect/ownership
contracts, and other roadmap tracks remain unfinished. See
`docs/experiments/generic-slices.md` for current scope and acceptance.

Validation: all 579 core tests passed in Debug and ReleaseFast, all 60 CLI tests
passed, and native parity passed 2664 comparisons across 90 single-file and 16
module fixtures with -O0/-O2 and undefined-behavior sanitization. Guardian passed
all 88 checks with baselines disabled. Allocation-failure coverage includes slice
forwarding and module-backed execution/schema generation. Generic lexical borrow
scopes and returned-reference contracts remain unverified and unfinished.


### Generic lexical borrowing and narrowing — 2026-09-06

Generic bodies now borrow copyable local values, reborrow references, and narrow
known slice inputs. Root identities, loan counts and parent child counts enforce
owner access and exclusive-parent suspension without scanning every local. Scope
exit restores access and removes names on returns and failures. Recursive generic
slice helpers execute through VM/C with runtime subrange bounds checks. Generic
reference-result provenance, abstract whole-value range shape, broader ownership
and effects, and other roadmap requirements remain unfinished. See
`docs/experiments/generic-borrows.md` for current scope and acceptance.

Validation: all 582 core tests passed in Debug and ReleaseFast, all 60 CLI tests
passed, and native parity passed 2676 comparisons across 92 single-file and 16
module fixtures with -O0/-O2 and undefined-behavior sanitization. Guardian passed
all 88 checks with baselines disabled. Allocation-failure tests cover recursive
borrows and imported narrowing helpers. These results do not establish generic
reference-result provenance or completion of the broader roadmap.


### Generic reference-result provenance — 2026-09-06

Generic whole-reference and slice results now validate explicit input provenance,
kind, permission and symbolic type before specialization. Borrow-call scopes and
forwarding preserve roots and parent suspension, including results borrowed from
later parameters. Concrete return contracts resolve types in the callee instance.
Imported result helpers execute through ordinary wrappers with internal instances
excluded from public schema roots. Abstract whole-value-to-slice shape, broader
nominal/composite operations, move-only/external-effect contracts, direct generic
public invocation, and other roadmap requirements remain unfinished. See
`docs/experiments/generic-returned-references.md` for scope and acceptance.

Validation: all 584 core tests passed in Debug and ReleaseFast, all 60 CLI tests
passed, and native parity passed 2682 comparisons across 93 single-file and 16
module fixtures with -O0/-O2 and undefined-behavior sanitization. Guardian passed
all 88 checks with baselines disabled. Allocation-failure coverage includes
forwarded references, later-input provenance and imported result helpers/schema
rendering. These results validate the supported reference contracts, not the
remaining generic operations or broader roadmap requirements.


### Readable specialization diagnostics and metadata — 2026-09-06

Checked functions now retain concrete type arguments explicitly. Instance display
names include ordered concrete types and qualified nominal names, remain unchanged
when discovery order changes, and flow into dumps/reports and VM/C traces. Public
module/schema roots use metadata rather than punctuation to exclude internal
instances. This advances the original understandable-diagnostics criterion; it
does not complete direct public generic tooling, broader operations, native
embedding or incremental compilation. See `docs/experiments/generic-diagnostics.md`.

Validation: all 586 core tests passed in Debug and ReleaseFast, all 60 CLI tests
passed, and native parity passed 2682 comparisons across 93 single-file and 16
module fixtures with -O0/-O2 and undefined-behavior sanitization. Guardian passed
all 88 checks with baselines disabled. Tests cover discovery-order independence,
qualified nominal names, dump/trace output, schema exclusion and allocation-failure
cleanup. This does not establish completion of direct generic public tooling or
the other unfinished roadmap tracks.
