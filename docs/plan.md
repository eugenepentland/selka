# Language design and implementation plan

> Removed on 2026-09-13: the explicit storage tier (buffers, pools, legacy `list`
> declarations, the `allocator` capability, references and slices, lexical borrows and
> legacy arena scopes) and the C backend are gone. Entries below that describe them are
> history; see [legacy/](legacy/) and [the current language reference](current-language.md).

Native execution is outside the active roadmap-completion goal. Preserve the
ability to add a backend later, but do not implement or extend native execution
as part of completing this roadmap. The current goal is to develop the language
on its bytecode VM; a future decision can reopen native work.

Current development-tooling priority (2026-09-07): [disk projects and incremental
verification](experiments/incremental-development.md). Disk-loaded schematic and board hosts are implemented;
ordinary `.my` edits use the installed executable without rebuilding Zig or running
Guardian. Opt-in dependency inventories/affected-suite testing, shared successful
receipts, a local agent scheduler and combined-merge certificates are implemented.
The schematic has a persistent VM development host with request-boundary reloads.
These are bounded tools with explicit input contracts; production gates remain full
gates while shadow evidence is gathered. Profiling is implemented; finer semantic
query reuse remains conditional because measured schematic checks are already small.
The linked plan and runtime guides specify limitations and acceptance evidence.

Status: revision 3, interpreter-first direction adopted on 2026-09-06. Scalar MVP M0–M5 and substantial post-MVP experiments are implemented. The current priorities below supersede older sequencing and dated “next” statements; completed experiments remain historical evidence.

Working executable name: `mylang`. Working source extension: `.my`.

Purpose: a plan for an experimental implementation, not a finished language specification.

Revision 2 introduced Guardian-derived quality proposals. Revision 3 prioritizes
language semantics, diagnostics, typed host calls, and real application evidence.
Native compilation is deferred until the design is mature and a measured need
justifies revisiting it. Sections 4–14 preserve the original scalar MVP contract;
dated implementation entries record what was demonstrated at each checkpoint.

## 1. Project direction

Build a small, statically checked, interpreted language that helps agents write,
understand, and modify correct code with fewer mistakes and less repair effort.
Use a small custom bytecode VM implemented in Zig as the primary runtime while
the design develops. The VM executes real application code; it is also useful for
source-level debugging and inspecting semantics.

The existing parser, checker, separate typed IR, and VM remain the foundation.
Checking and lowering to bytecode are compilation steps within this interpreted
workflow. Zig builds the host implementation; it does not consume guest bytecode.
Keep Guardian on the Zig implementation with blocking checks and no frozen
violation baselines. Language guarantees and advisory application-code reports
remain separate from Guardian's implementation-quality policies.

Favor a small number of strong, understandable rules: distinct IDs and units,
exhaustive tagged unions, explicit optional values and checked errors, definite
initialization, checked arithmetic and indexing, ownership and borrowing, explicit
mutation, and controlled effects. Existing experiments cover many of these;
remaining syntax and usability must be evaluated on realistic programs. More
restrictions, obscure inference, or boilerplate are not success criteria. Keep
inferred duplication and complexity advisory; share domain knowledge through
explicit types, schemas, and interfaces where that improves the program.

### Current implementation order

1. Use the implemented interpreter acceptance workflow (`zig build test` or
   `test-interpreter`); native integration is optional (`test-native`, with
   `test-all` combining both). Local array/buffer views and concrete or generic fixed-array input slice
   results are implemented, along with arena/reset origin and escape checks.
   [Generic fixed arrays](experiments/generic-arrays.md) now support nested `[N]T`
   construction and substitution with explicit numeric lengths.
   Keep unsupported structural operations explicit until their rules are in place.
2. Improve structured diagnostics and repair examples alongside those features.
   Whole-value/partial-field moves, borrow conflicts, arena escapes and invalid
   reference returns now retain causal, declaration and contract evidence, with
   executed repair fixtures. [Versioned CLI diagnostics](experiments/json-diagnostics.md)
   now expose that evidence, VM traces and cached warnings with `--diagnostics=json`. The initial
   [optional-value audit](experiments/optional-values.md) retains named unions and
   checked results; measure application usability before adding convenience syntax.
3. The [typed VM host interface](experiments/host-functions.md) now supports
   explicit guest declarations and handwritten Zig wrappers with exact signatures,
   transitive effects, grants, copied values and typed failures. Registrations bind
   to the same compiled program; VM calls share bounded sessions and deterministic
   cleanup. Borrowed and runtime-owned boundary signatures reject explicitly.
4. The [bounded board keepout trial](../experiments/board_trial/README.md) now
   executes guest validation on the VM and a standalone Zig baseline against 87
   fixed oracle cases plus 60 transformed cases, with exact report/callback
   agreement. Geometry stays behind a typed wrapper. The [repair-study harness](../experiments/board_trial/repair/README.md)
   now prepares five task pairs, records submissions and grades fresh shared
   cases after sealing. Actual agent repair attempts remain pending.
5. The first trial-driven simplification, [scalar domain equality](experiments/domain-equality.md),
   removes nominal-ID comparison helpers while preserving type isolation. Use
   further evidence to prioritize parameterized records/unions, generic
   constraints/tooling, bounded source serialization, and finer incremental checks.
   [Nominal template syntax/interfaces](experiments/nominal-type-syntax.md) are
   implemented as groundwork. [Declaration checking](experiments/nominal-template-checks.md)
   now validates unused fields/payloads, identities and argument requirements;
   [finite layout checking](experiments/nominal-layouts.md) now validates stored
   dependencies while preserving phantom arguments. [Concrete instances](experiments/nominal-instances.md)
   now execute on the VM with complete schemas and existing ownership/host rules.
   [Symbolic nominal bodies](experiments/nominal-bodies.md) now check construction,
   fields, variants, ownership and lifetimes before late VM specialization.
   [Provider-specific symbolic shapes](experiments/nominal-providers.md) now cover
   resource/environment operations and concrete domain codecs in generic callers.
   The board trial now uses one `Slot<T>` declaration and one equality-constrained
   membership helper for component/net IDs. Public generic tooling and codec
   constraints on type parameters remain open.
   These remain open; completing all
   abstraction experiments is not a prerequisite for starting the trial.

Measure pre-execution mistakes caught, next-attempt diagnostic repair success,
unrelated edits and unsafe workarounds, and independent behavioral-test results.
Compare equivalent tasks against an existing implementation, recording failed
attempts as well as successes. Language usefulness remains an untested hypothesis
until this application evidence exists.

### Runtime and future backends

Keep VM semantics clear and execution bounded. Do not schedule instruction fusion,
adaptive optimization, JIT work, or interpreter speed competitions. Profile actual
application workloads before optimizing. Wasm remains an optional future runtime
experiment if its sandboxing or infrastructure solves a concrete need.

A typed host call lets interpreted code use an existing native library. It does
not require compiling the language to native code. Host wrappers are trusted:
the checker cannot prove arbitrary Zig/C/Rust safe. Keep raw pointers inside that
boundary and define input/output ownership, reference validity, and failure
behavior before exposing a function to guest code.

Retain completed C emission, native ABI/binding work, and parity fixtures as
experimental assets and historical evidence. Further native backend coverage,
borrowed/capability native ABIs, native compilation performance, LLVM, and direct
x86_64 Linux output are deferred, with no current delivery date. New language
features need interpreter acceptance, not new native parity as a completion gate.
Existing native commands may support only their documented experimental subset.

Keep typed IR independent of VM bytecode. Types, ownership, cleanup, evaluation
order, effects, overflow, and bounds behavior belong to the language definition.
A future backend must implement those same rules. Revisit native compilation
when representative projects establish stable semantics and measurements show a
need that the typed host boundary does not adequately address.

The detailed acceptance and trial design is in
[the interpreter-first roadmap](experiments/interpreter-first.md). The test workflow
now follows that direction: the default suite executes interpreter acceptance,
with native compilation integration available through explicit optional targets.

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

## 3. Original MVP commitments and historical open questions

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

```mylang
# doc: expect 4950
def sum_to(n: i64) -> i64:
    total: i64 = 0
    i: i64 = 0

    while i < n:
        total += i
        i += 1

    return total


def main() -> i64:
    print(sum_to(100))
    return 0
```

`mylang run sum.my` must print `4950`.

A second example exercises calls, local mutation, and remainder:

```mylang
# doc: expect 6
def gcd(a: i64, b: i64) -> i64:
    x = a
    y = b

    while y != 0:
        remainder = x % y
        x = y
        y = remainder

    return x


def main() -> i64:
    print(gcd(48, 18))
    return 0
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
| `docs/legacy/semantics.md` | Rules each milestone implemented |
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

## 15. Post-MVP experiment record

Section 1 and [current tracking](experiments/roadmap.md) define the active order.
The dated notes below preserve past scope and validation; their pending native
work is deferred under revision 3.

Implementation update (2026-09-05): exact scalar duplicate discovery in track T
is now implemented as a separate advisory command. [Bounded approximate discovery](experiments/approximate-discovery.md) also reports near matches with canonical edits and explicit work limits. [Static quality reports](experiments/quality-reports.md) now expose resolved calls, binding counts, and configurable structural metrics separately from runtime coverage. [Canonical formatting](experiments/formatter.md) now preserves tokens/comments and supports syntax-only formatting checks. [Project verification](experiments/verification-driver.md) now executes an explicit manifest with filtered-scope reporting and separate correctness/timing evidence. See
[the experiment record](experiments/duplicate-discovery.md) and
[post-MVP tracking](experiments/roadmap.md). A1 now includes records, complete construction, field access, preserving
updates, declarative complete conversions, checked integer widths/casts, and
[fixed arrays with checked indexing](experiments/arrays.md). A1 is complete.
A2 now includes [nominal scalar domains and private construction](experiments/domains.md);
[closed variants and exhaustive matching](experiments/variants.md) are also implemented.
[Complete enum-indexed tables](experiments/tables.md) finish A2. Borrowing and
slices are in progress: [B has a tested memory/lease registry and scoped source references](legacy/experiments/borrowing.md),
including static access checking, VM cleanup, and shared/exclusive reference
parameters. [Bounded slices and checked narrowing](legacy/experiments/slices.md) are also
implemented. [Returned-reference lifetime contracts](legacy/experiments/returned-references.md)
complete B; see [the acceptance audit](legacy/experiments/b-audit.md). C/D now have
[typed recoverable results and checked handling obligations](experiments/results.md).
[Explicit propagation](experiments/propagation.md) now preserves error obligations
and borrow cleanup. [Owned-buffer transfers and partial-acquisition cleanup](legacy/experiments/ownership.md) now have backend acceptance evidence. [Source buffer acquisition, moves, wrappers, and partial-construction cleanup](legacy/experiments/owned-buffers.md) are also implemented. [Buffer queries, mutations, and checked borrowed views](legacy/experiments/buffer-operations.md) are also implemented. [Transitive allocation bounds and inference](experiments/effects.md) are implemented. [Explicit allocator capabilities](legacy/experiments/allocator-capabilities.md) are now required for acquisition and growth. [Clock/random capabilities and injected provider operations](experiments/external-capabilities.md) now contribute transitive effects. [External resource ownership, fallible completion, and scoped cleanup](experiments/external-resources.md) now have backend acceptance. [Source resource acquisition, explicit completion, owned error returns, and cleanup effects](experiments/source-resources.md) are now implemented with injected filesystem/network providers. [Non-consuming copyable field reads](legacy/experiments/owned-field-reads.md) now support code-dependent completion retry. [Bounded environment capabilities and lookup](experiments/environment.md) now use injected providers and transitive effects. [Owned resource reads/writes](experiments/resource-io.md) now expose bounded bytes, explicit EOF, and partial write progress through injected providers. [Resource operation permission attenuation](experiments/attenuation.md) now narrows grants monotonically and constrains provider acquisition and owned operations. [Borrowed resource slice I/O](legacy/experiments/resource-slices.md) now supports exclusive array/buffer destinations and writes of populated ranges with lifetime checks. [Typed-handle pools](legacy/experiments/typed-pools.md) now have backend graph, generation, snapshot, and bulk-clear acceptance. [Arena backing and checked region reset](legacy/experiments/arenas.md) now have backend borrow, snapshot, identity, and storage-reuse acceptance. [Execution-lifetime arena selection](legacy/experiments/arena-execution.md) now runs source programs through the VM and CLI. [Scalar native execution](legacy/experiments/native-execution.md) now emits C compiled by the pinned Zig toolchain, with shared scalar value/trap acceptance. [Partial record field moves](legacy/experiments/partial-fields.md) now preserve remaining field access, immediate ownership transfer, cleanup, and result obligations. [Source pools and nominal handles](legacy/experiments/source-pools.md) now integrate graph operations, checked IDs, shared quotas, snapshots, and ownership cleanup. [Checked region backing](legacy/experiments/region-backing.md) now shares arena lifetime guards between buffers and pools while retaining independent snapshots. [Lexical source arena scopes and conservative escape checking](legacy/experiments/source-arenas.md) now preserve allocator/owner lifetime boundaries through wrappers, calls, mutation, and cleanup. [Explicit source arena reset operations/results](legacy/experiments/arena-reset.md) now reclaim unused chunks with live-owner/child guards while preserving allocator authority. [Module header discovery](experiments/module-discovery.md) now loads bounded import graphs with deterministic ordering and cross-file cycle diagnostics; [module interface indexing](experiments/module-interfaces.md) now parses bodies, resolves declaration identities, and checks explicit exports and signature visibility. [Source maps and AST relocation](experiments/module-source-mapping.md) now retain module ownership and original locations through diagnostics and execution traces. [Cross-file type checking and VM execution](experiments/module-execution.md) now run shared-domain programs with private boundaries, nominal identities, and the existing ownership/effect rules. [Optional dependency-direction policy](experiments/import-policy.md) now evaluates resolved imports with explicit ordered rules and a separate policy verdict. [Module duplicate discovery](experiments/module-duplicates.md) now reports cross-file exact/near matches with qualified type/callee identities. [Module quality reports](experiments/module-quality.md) now distinguish entry-main reachability from exported interface roots. [Module formatting](experiments/module-formatting.md) now supports syntax-only file output and reachable-project checks. [Scalar module native execution](legacy/experiments/module-native.md) now has executed VM/native result/trap/path/trace parity. [Native nominal scalar domains](legacy/experiments/native-domains.md) now preserve domain identity/privacy and instruction-budget parity. [Native closed enums](legacy/experiments/native-enums.md) now preserve nominal tag identity, exhaustive dispatch, and instruction-budget parity. [Native packed variants and results](legacy/experiments/native-variants.md) now support nested scalar payloads, exhaustive matching, result transfer/acknowledgement/propagation, and packed layouts up to 127 bits. [Native ordinary aggregates](legacy/experiments/native-aggregates.md) add records, arrays, tables, conversions/updates, partial result field transfers, boxed payloads and wider variant layouts, with executed allocation-failure cleanup and bounded live-storage acceptance; [Native borrowing and slices](legacy/experiments/native-references.md) add scoped loans, reference/slice parameters, returned-reference contracts, snapshot-preserving writes, and checked access with executable parity; native resources remain pending. [Approximate header indexing](experiments/approximate-discovery.md) now skips incompatible pairs with bounded deterministic work and generated scaling acceptance; banded edit-distance comparison retains full-matrix match/explanation parity while reducing comparison storage and work. [Module graph boundary acceptance](experiments/module-scaling.md) now exercises 256-module chains and 4,096-import shared graphs through CLI checking, execution, and tooling. [Restricted project evaluation](experiments/restricted-evaluation.md) now establishes parameter-free/effect-free execution with explicit step, frame, and VM-allocation budgets. [Evaluation reports](experiments/evaluation-reports.md) now record loaded sources/imports, compiler identity, budgets, and a deterministic request digest; request-only mode computes the same identity after checking eligibility without running the VM. [Persistent evaluation caching](experiments/evaluation-cache.md) now reuses successful matching results after fresh frontend/eligibility checks and can explain field-level changes against a chosen prior request. [Typed scalar input manifests](experiments/input-manifests.md) now validate names/types/values and generate deterministic imported modules; repeated --inputs bindings supply fresh in-memory modules for evaluation and cache lookup, preventing stale generated-file reuse and rejecting conflicting modules under explicit count/byte limits. [Checked public schema derivation](experiments/schemas.md) now emits deterministic exported type graphs and function contracts, preserving nominal identities, opaque domain/resource boundaries, and checked borrowing/effects. [Typed JSON serialization](experiments/typed-json.md) now validates ordinary checked values and emits canonical versioned documents under explicit limits, preserving nominal identities and rejecting opaque dependencies. [Standalone Python data bindings](experiments/python-bindings.md) now derive nominal classes and compatible bounded codecs from fresh checked schemas, with deterministic generation, explicit unsupported types, and atomic installation. [Incremental binding artifact reuse](experiments/binding-cache.md) now records schema/generator/compiler/Python/limit requests, skips generation on validated cache hits after fresh checking, and preserves unchanged output timestamps. [Checked schema source receipts](experiments/schema-receipts.md) now identify all loaded sources and the actual compiler image, with fresh provenance in binding reports even on artifact cache hits. [Typed JSON failure locations](experiments/codec-diagnostics.md) now identify nested fields/elements/payloads through bounded owned JSON pointers while preserving cleanup and allocation-error classification. [Initial ordinary-application corpus review](../examples/corpus/README.md) now exercises an invoice calculator and borrowed packet decoder across 13 modules, with independent execution expectations, reviewed exact/near duplicates, quality/policy checks, and change-impact/schema/binding acceptance. This authored corpus does not establish production readiness or independent-user evidence. [Typed invocation](experiments/typed-invocation.md) now calls exported effect-free functions with bounded owned argument copies and typed results, providing the execution foundation for checked domain factories. [Explicit domain codec contracts](experiments/domain-codecs.md) now associate ordinary wire types with public effect-free methods, require exact decoder result signatures, and derive opaque-preserving schema metadata. [Executed domain JSON codecs](experiments/domain-json.md) now use those methods during nested traversal and CLI round trips, with shared memory/step/call/work limits and located typed rejections or source traps. [Schema-pinned public JSON calls](experiments/checked-calls.md) now invoke exported functions from named wire arguments, validate the expected public schema before execution, and share budgets across argument decoding, the target call, and result encoding. [Generated Python calls](experiments/python-calls.md) now provide nominal function wrappers and domain wire objects over schema-pinned public invocation, with explicit compiler/project selection, budgets, and transport failures. [Declared call inputs](experiments/call-inputs.md) now supply fresh in-memory manifest modules to schema generation, codecs, and Python calls, preserving source receipts and compatible artifact reuse. [Incremental module syntax](experiments/incremental-syntax.md) now reuses exact parse tables across fresh embedding projects under retention limits while rerunning semantic checks. [Persistent checking sessions](experiments/check-session.md) now reuse syntax across explicit CLI requests while reloading files/manifests and rerunning semantic checks, with bounded framing and status/cache reports. Source serialization operations, native ABI bindings, persistent/semantic query reuse, automatic watching, and other unfinished tooling remain pending. Generics, remaining compile-time/schema/incremental work, native expansion, and the other unfinished work below remain pending.

| Stage | Scope | Question to answer before proceeding |
| --- | --- | --- |
| A1: aggregate values and complete conversions | Structs, fixed arrays, checked indexing, additional integer widths, complete construction, preserving updates, and declared complete conversions | Does adding a field identify incomplete constructions and conversions, including a newly ignored source field? |
| A2: domain types and exhaustive mappings | Nominal scalar wrappers, private constructors, closed enums/tagged unions, exhaustive matching, and enum-indexed tables | Can domain units and identities stay distinct, and does adding a variant expose every mapping that promised complete handling? |
| B: borrowing | Shared/exclusive references and slices, initially with deliberately restricted lifetimes | Can common functions be expressed and invalid accesses rejected with understandable errors? |
| C: ownership, capabilities, and effects | Owned buffers, resource transfer, partial-construction cleanup, allocator/external capabilities, small no-I/O and no-allocation contracts, arenas/pools | Are acquired resources cleaned up on recoverable failure, and can a caller verify transitive resource and external-access costs? |
| D: errors and abstraction | Typed fallible results, propagation, deliberate-error acknowledgement, limited generics, typed handles | Are important results handled explicitly, and do abstractions preserve ownership, effects, and understandable diagnostics? |
| M: modules and interfaces | Explicit exports, private implementation, resolved imports, and optional dependency-direction policies | Can shared domain rules live behind usable interfaces without exposing unrelated implementation details? |
| E: native execution — deferred | Retain completed C/native experiments; LLVM and direct machine code remain future options | Reopen only after stable application semantics and measured need; no current native acceptance milestone. |
| F: compile-time work, schemas, and incremental builds | Restricted evaluation, declared inputs, typed serialization/schema derivation, generated bindings, dependency recording, invalidation | Do generated representations stay consistent, and can generation cost and rebuild causes be explained and measured? |
| T: compiler-assisted quality tooling | One formatter; exact structural duplicate discovery followed by approximate matching; reference/complexity reports; a separate project-verification driver | Do findings lead to useful improvements without unstable verdicts or forced abstractions? |

Use section 1’s interpreter-first order. Learn from the application trial before expanding abstractions; native backend experiments are deferred.

Experiments M and T are companion tracks, not prerequisites for the scalar MVP or every later feature. Introduce module support when programs need shared interfaces. Begin duplicate discovery after real programs provide a reviewable corpus. Bring a minimal recoverable-error representation from D into C as needed to test allocation failure and cleanup; the full error/generic design can follow. Typed serialization requires the aggregate and variant model; cross-language generators should follow the declared-input and resource-budget discipline of F.

Before adding pointers, choose a VM memory representation with allocation identity, bounds, and lifetime information. Host pointers alone would make it difficult to diagnose invalid guest memory operations. Before adding aggregates, decide their copy, address, and storage semantics; the current two-variant `Value` is only a scalar MVP representation.

A compiler written in a manually managed language does not prevent the new language from enforcing memory safety. Conversely, this scalar VM does not prove that a future borrow checker is sound.

Future native work requires mature semantics and evidence of need from representative interpreted projects. Completed C experiments remain available; LLVM or direct x86_64 Linux output has no current milestone. A concrete program alone does not require reopening native development.

The interpreter may later help implement compile-time evaluation, but runtime interpretation alone does not supply deterministic inputs, target-aware semantics, or caching. Cross-compilation requires guest types and layout to follow the target, not the host.

Self-hosting should follow a useful, stable subset and reliable tests. It is not a prerequisite for validating the design.

## 16. Suggested first implementation task

Start with M0 and M1 only. This is a suitable instruction to give an implementation agent or use as the first issue:

> Create a Zig project for the scalar-language MVP in this plan. Use the pinned Guardian Zig snapshot, `0.17.0-dev.1683+5ceec001b`, and record its exact version. Implement the smallest complete pipeline that accepts `fn main() -> i64 { return 1 + 2 * 3; }`, checks it, lowers it to an inspectable instruction list, and executes it to produce `7`. Keep the untyped AST, typed representation, and VM instructions separate. Include source spans, a readable instruction dump, checked addition/subtraction/multiplication, and focused precedence and malformed-input tests. Do not add locals, branches, function calls, native code generation, or future-language syntax until this vertical slice works. Report the implemented subset, commands, and test results.

After that works, proceed milestone by milestone. Keep any design change in `SPEC.md` and update the relevant fixtures in the same change.

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


### Native embedding entry and shared-library builds — 2026-09-06

Generated C now offers `mylang_native_run_v1` with explicit providers and budgets,
a scalar entry result, bounded located traps and returning host failures. Every
invocation releases guest storage; repeated calls reset state, and overlapping
calls return Busy. `scripts/native.py --library` builds a shared library while
preserving atomic and unchanged-output publication. See
`docs/experiments/native-embedding.md` for the public C header contract.

Focused acceptance passed 24 host programs across -O0/-O2 with undefined-behavior
sanitization, repeated calls, frame/step budgets, reentry/concurrent rejection,
live-resource trap cleanup and allocation-failure recovery. Independent public-header hosts
linked and ran Debug/ReleaseFast shared libraries and verified unchanged rebuilds.
All 586 ReleaseFast core tests passed; the full Debug regression command also
completed successfully, including 586 core and 60 CLI tests. Arbitrary exported native calls,
aggregate native arguments/results, generated native callable bindings, finer
incremental compilation and the other pending roadmap requirements remain open.


### Exported native scalar invocation — 2026-09-06

Module native emission now retains resolved export roots and exposes
`mylang_native_call_v1`. Hosts call qualified public names with exact typed scalar
bits; integer widths, full u64 results, Booleans, counts and ranges are checked.
Private helpers and internal generic instances remain unavailable. Located traps,
budgets, cleanup and repeated-call recovery share the native entry machinery.
The public C headers work with independently linked shared-library hosts. See
`docs/experiments/native-calls.md` for the contract.

Validation: 587 core tests passed in both Debug and ReleaseFast; all 60 CLI
tests and formatting passed. Native parity
passed 2682 comparisons across 93 single-file and 16 module fixtures, and all 24
embedding host programs passed. Named-call acceptance passed -O0/-O2 sanitizer
runs and Debug/ReleaseFast shared-library host links, covering visibility, every
scalar boundary, invalid inputs, trap locations, allocation failures and recovery.
Guardian passed all 88 checks without baselines. The earlier full Debug embedding
suite also completed successfully before this API extension. Aggregate/domain
native wire values, borrowed/capability signatures, generated native callable
bindings, incremental compilation and the other pending roadmap items remain open.


### Native ordinary aggregate value calls — 2026-09-06

`mylang_native_call_values_v1` now copies checked preorder scalar, record,
fixed-array/table, enum, packed/boxed variant and typed-result values across the
native host boundary. Inputs become guest-owned copies; outputs use caller-owned
nodes and retain no guest allocation. Counts, type names, tags and scalar ranges
are validated; the scalar call API shares that range implementation. Output
capacity failures report the required size without writing output. Domains,
resources and other runtime identities remain opaque. See
`docs/experiments/native-wire.md` for the positional schema and ownership contract.

Acceptance passes address/undefined-behavior sanitizer runs in -O0/-O2 and
independent Debug/ReleaseFast shared-library hosts. Tests cover snapshots,
empty values, nested packed/boxed payloads, enum tables, typed results, malformed
inputs, opaque signatures, output capacity, traps, allocation failures, recovery,
exact 128-level and 100000-node limits, and cross-API Busy rejection. Full core
runs passed 587 tests in Debug/ReleaseFast, all 60 CLI tests passed, and native
parity passed 2682 comparisons. All 24 embedding cases and scalar native-call
acceptance passed. Final shared-range refactoring is checked by both native call
drivers and focused compiler allocation tests. Guardian passed all 88 checks with
baselines disabled. A variant-input regression exposed and corrected use of a
guest-frame-only stack helper before entry-frame creation; this was test-derived
evidence. Native domain codecs, generated schema-pinned native bindings,
borrowed/capability signatures, incremental compilation and other roadmap items
remain unfinished.


### Schema-pinned generated native Python bindings — 2026-09-06

Native module libraries now expose canonical public schema bytes and SHA-256
from the same checked compilation as their code. Shared checked-schema rendering
avoids a project/schema import cycle. Generated Python modules include
`NativeClient` and `NativeLimits`; their existing typed wrappers call ordinary
native scalar/record/array/table/variant/result functions only after validating
the library's schema. Calls preserve host snapshots, report native traps and
budgets, and do not retry output-capacity failures. Both embedded runtime sources
participate in the generator/cache identity. See
`docs/experiments/native-bindings.md` for usage and the synchronous native boundary.

Independent metadata tests pass public field/type/case/export invalidation,
compatible body/private/relocation stability, concurrent queries, both native
optimization modes and absent single-file schemas. Generated Python acceptance
passes typed compiler/native comparisons, schema/ABI/I/O rejection, integer
boundaries, snapshots, traps/recovery, node/depth/frame/step budgets, malformed
results and calls after source removal. Existing Python data/call, binding-cache,
schema and receipt tests pass; cache tests include changes to the native runtime.
All 587 core tests passed in Debug/ReleaseFast, all 60 CLI tests and formatting
passed, and native parity passed 2682 comparisons. Native scalar/aggregate host
acceptance passes, and Guardian passed all 88 checks without baselines. These are
focused and core regression results, not a new full-build-test run.

Native domain codecs, borrowed/capability invocation, source serialization,
finer semantic/native incremental compilation and the other pending roadmap
requirements remain unfinished. Schema identity establishes interface
compatibility; it does not authenticate implementation behavior.


### Internal native codec execution — 2026-09-06

Generated native dispatch now permits internal calls only to functions selected
by checked domain codec declarations. One owned argument and result cross the
internal call boundary while the surrounding operands, frames, instruction/frame
budgets and cleanup destination are preserved. Normal public calls retain their
existing behavior. This is a prerequisite for codec-aware native value traversal;
public wire calls and NativeClient still reject domain signatures. See
`docs/experiments/native-codec-dispatch.md` for the remaining integration.

Four sanitizer hosts pass nontrivial decoder/encoder execution, packed/boxed
rejection ownership, caller operand/frame preservation, shared budgets, exact
trap frames, non-codec private-helper rejection, allocation failures and recovery.
An uninstantiated generic declaration verifies separation from source declaration
ordinals. Compiler codec-dispatch allocation sweeps pass. All 588 core tests
passed in Debug/ReleaseFast, all 60 CLI tests and formatting passed, and native
parity passed 2682 comparisons. Existing 24 embedding cases, ordinary aggregate
wire acceptance and generated native Python tests pass. Guardian passed all 88
checks with baselines disabled; no new full-build-test run is claimed.

Public native codec input/output conversion, typed rejection reporting, shared
codec-call quotas and generated-client domain support remain unfinished. Output
encoding must be staged so each encoder runs once rather than once per sizing
and writing pass. The other pending roadmap requirements also remain open.


### Public native domain codec calls — 2026-09-06

The new `mylang_native_call_codecs_v1` API converts declared domain wire values,
including domains nested in records, arrays and variants. Input decoders, the
public root and output encoders share step/frame limits and a separate bounded
call quota. Encoded output is staged before publication so each encoder runs once
and insufficient buffers or traps leave caller output unchanged. Implicit decoder
rejections carry the domain identity and ordinary typed rejection tree; explicit
public decoder calls retain ordinary language-result semantics. The original
value API keeps its domain opacity. See `docs/experiments/native-codec-wire.md`.

Four sanitizer hosts and four separately linked public-header hosts pass both
optimization modes and packed/boxed rejection representations. Coverage includes
nested conversion, exact call limits, shared step/frame budgets, decoder/encoder
traps, unchanged insufficient output, allocation failures and repeated recovery.
All 588 core tests pass in Debug and ReleaseFast. Existing internal codec, ordinary
wire, scalar call, generated Python native-client and 24 embedding host cases pass,
including cross-API Busy rejection. All 2682 VM/native comparisons pass. The new
driver runs in `zig build test`; a new
full-suite pass is not claimed here. Guardian passes all 88 checks with baselines
disabled. Generated Python domain support, source-level codec operations and all
other outstanding roadmap requirements remain open.


### Generated Python native domain bindings — 2026-09-06

Generated `NativeClient` now supports the codec-capable public function set,
using explicit domain wire wrappers and the native codec API for domain-bearing
signatures. Ordinary signatures retain the original value ABI and work without
the optional codec symbol. Domain calls report `NativeABIUnavailable` when that
symbol is absent. Schema pins still apply before invocation.

`NativeLimits.max_calls` defaults to 4096 and bounds implicit decoders, the public
root and output encoders under the shared native execution. Host traversal counts
explicit domain nodes in its depth and node budgets. Implicit decoder failures
raise `CallError` with domain/call context and a typed scalar or aggregate rejection
value. Insufficient output never triggers a retry, including when only the
rejection flag and required error-tree capacity are available.

Debug and ReleaseFast shared-library acceptance passes VM/native agreement for
ordinary and nested domain values, nontrivial decoding/encoding, scalar/record
rejections, explicit decoder results, decoder/encoder traps, exact call budgets,
malformed output, absent codec APIs, success/rejection capacity failures and calls
after source removal. Existing Python data binding (29 wire comparisons),
compiler-process call and binding-cache suites pass, including runtime digest
invalidation. Python syntax and whitespace checks pass; Guardian passes all 88
checks with baselines disabled. This change does not claim a new full Zig-suite
run. Source-level codec operations, borrowed/capability native invocation,
incremental compilation and all other pending roadmap requirements remain open.


### Source declared domain codec operations — 2026-09-06

Source expressions now support `codec_decode[Domain](wire)` and
`codec_encode[Domain](value)`. They select the methods named by an explicit codec
contract and lower to ordinary checked calls, retaining public visibility,
parameter/result typing, result obligations, effect checks and execution budgets.
The decoder returns its declared typed result; encoding cannot accept raw backing
values. Imported domain aliases and formatter round trips are supported.
See `docs/experiments/source-codecs.md`.

Both full core runs passed 591 tests in Debug/ReleaseFast; final focused acceptance
adds a nonstandard method-name/transformation case and generic-constraint rejection.
All 60 CLI tests and 2688 VM/native comparisons across 110 fixtures passed.
Allocation-failure tests cover source execution/formatting and imported codec
resolution. Guardian passes all 88 checks without baselines. New behavior
classification subjects for the lexer, formatter and resolver were labeled
intentional-change against the tagged SOURCE-CODEC-1 contract; uncertain subjects
remain pending. No new full build-test run is claimed.

This completes explicit source domain-to-wire conversion. JSON byte serialization
operations still need bounded buffer/slice contracts, allocation authority and
typed malformed-input handling. Generic codec constraints, borrowed/capability
native invocation, finer incremental compilation and all other outstanding
roadmap work remain open.


### Exact successful project-check reuse — 2026-09-06

Persistent checking sessions now retain one bounded successful verdict alongside
the syntax cache. Every request freshly loads files, module headers and generated
manifest inputs before comparing complete module names, paths and source bytes.
An exact hit replays owned warnings and skips interface/semantic work. Changed
snapshots check afresh; failed checks are never retained. Clearing drops both
caches. Cumulative `semantic` JSON observations distinguish hits, misses, storage,
bypass and retained bytes from actual syntax reuse.

Verdict retention is limited to a separate 16 MiB arena, for up to 32 MiB combined
syntax/verdict entry storage. Oversized entries bypass storage; failed replacement
allocations preserve the prior successful verdict. This is in-process whole-project
reuse, with no hash-only key or persistent disk verdicts. See
`docs/experiments/check-session.md` for the protocol and trust boundary.

Full core suites passed 595 tests in Debug/ReleaseFast; final five-test cache runs
add explicit failed-replacement preservation. All 60 CLI tests pass. Persistent
session and watch acceptance pass exact warm hits, identical warning replay,
source/type/privacy/deleted-file recovery, changed/invalid manifests, clear,
retention bounds and protocol/child cleanup. Guardian passes all 88 checks without
baselines; its complexity finding prompted shared loading/input-validation and
verdict helpers and was labeled useful-review. The cache behavior was labeled
intentional-change; uncertain subjects remain pending. No new full build-test run
is claimed. Finer semantic queries, persistent reuse, incremental native linking,
source JSON byte serialization and all other pending roadmap items remain open.


### Concrete schemas in generic bodies — 2026-09-06

The abstract generic checker now shares the resolved type catalog with concrete
specialization. Fixed copyable records, arrays and nominal values can appear
alongside symbolic parameters in signatures, local annotations, generic calls
and pure concrete helpers. Record/array construction, record projection, array
and enum-table indexing, and length use declared concrete schemas. Imported
aliases retain declaring-module resolution; nominally different records remain
distinct, and symbolic integer parameters still require explicit conversion to
fixed integer fields. Concrete domains can pass through without exposing backing
construction. Complete runtime-identity/result-bearing graphs remain excluded.
See `docs/experiments/generic-concrete.md` and `examples/generic-records.my`.

All 599 core tests pass in Debug/ReleaseFast, all 60 CLI tests pass, and VM/native
parity passes 2706 comparisons across 113 fixtures, including imported record
helpers and an imported generic bounds trap. Final focused tests in both modes
also verify concrete-domain passthrough. Allocation sweeps cover abstract and
concrete checking, VM execution and native emission. Formatting and all 88 Guardian
checks pass with baselines disabled. Its concreteType error-path claim was labeled
false-positive because rejection/allocation tests already covered the catch;
adding the helper name to the test title was the only required edit.

Parameter-dependent composite types, generic type declarations, structural
requirements, aggregate updates, variants/results/ownership abstract rules,
source codec constraints, public generic tooling and the remaining roadmap
requirements stay open. This is not completion of the full generic language or
a claim of a new full build-test run.


### Generic aggregate updates — 2026-09-06

Generic bodies now support partial updates of concrete copyable records and
replacement of fixed-array or enum-table elements. Construction/update field
validation and indexing/replacement index validation share helpers. Updates
preserve untouched fields, require unique known fields with exact types, and
cannot infer a record shape from a symbolic parameter. Table keys retain nominal
enum identity. Ordinary specialization/lowering retains snapshots, evaluation
order and runtime bounds. See `docs/experiments/generic-updates.md` and
`examples/generic-updates.my`, which returns 44 while reading original and updated
record/table values.

All 601 core tests pass in Debug/ReleaseFast; all 60 CLI tests and 2724 VM/native
comparisons across 116 fixtures pass. Allocation sweeps cover record/table snapshot
updates and native emission. Uncalled-template tests reject malformed fields,
indices, elements and enum keys; imported native fixtures cover empty-array and
maximum-u64 replacement traps. Formatting and all 88 Guardian checks pass with
baselines disabled. Uncertain ROI subjects remain pending, and no new full
build-test run is claimed.

Concrete variant construction/matching, result/ownership abstract rules,
parameter-dependent structural types, codec constraints, public generic tooling,
source JSON serialization and all other pending roadmap requirements remain open.


### Concrete generic variants and exhaustive matching — 2026-09-06

Generic bodies now construct concrete copyable enums/unions and match them
exhaustively. Nominal case ownership, exact payload presence/type, arm-local
bindings, duplicate/missing cases and all-arm return flow are checked before
instantiation. Every arm is checked even after a fallthrough arm; bindings do not
escape or conflict across independent arms. Named enum-table construction now
requires every declared key exactly once and shares record field validation.
See `docs/experiments/generic-variants.md` and `examples/generic-variants.my`, which
returns 16 from record/scalar union payloads and a complete enum table.

All 605 core tests pass in Debug/ReleaseFast; all 60 CLI tests and 2742 VM/native
comparisons across 119 fixtures pass. Allocation sweeps cover construction,
matching, enum tables, execution and native emission. Rejection tests cover
payload/case/type errors, scope escape, incomplete return paths and invalid later
arms. Imported fixtures retain aliases and located traps inside generic match
arms. Formatting and all 88 Guardian checks pass with baselines disabled.
Uncertain ROI subjects remain pending; no new full build-test run is claimed.

Result-bearing and runtime-owned variant graphs remain excluded pending abstract
handling/ownership rules. Parameter-dependent structural types, generic codec
constraints, public generic tooling, source JSON serialization and the remaining
roadmap requirements stay open.


### Full roadmap regression checkpoint — 2026-09-06

The complete `zig build test --summary all` run at source commit `27f4eec`
finished with exit status 0: **40/40 build steps succeeded and 665/665 Zig tests
passed** (605 core plus 60 CLI). The integration drivers also passed, including
2742 VM/native comparisons across 119 fixtures, generated Python value/domain
bindings, native embedding and codec wire calls, allocation-failure cleanup,
resource/provider boundaries, exact check-session reuse, watch recovery, schema
and evaluation receipts, binding caches, the two-application ordinary corpus,
and 256-module/4096-import boundary acceptance. This closes the full-suite
validation gap noted in the preceding focused milestone records. The earlier
ReleaseFast core results remain separate; this was the default Debug build test.

Guardian passed all 88 checks with violation baselines disabled. Report-only
file-size, function-length and line-length findings remain; passing the gate does
not mean the report contains no findings. Pending ROI subjects were inspected and
left unclassified where this run supplied no evidence for a human outcome.

Optimized C compilation for the quota-reuse and quota-network fixtures took
95.6 and 90.3 seconds respectively, versus about 1.2 seconds each at `-O0`.
These are observations from this run, not isolated benchmarks; native compilation
performance remains an open roadmap requirement.

Abstract generic result handling is the next implementation, with branch, loop,
scope and live-temporary acceptance requirements in
`docs/experiments/generic-results-plan.md`. It remains unimplemented. Structural
generic types, codec constraints, public generic tooling, source byte
serialization, borrowed/capability native invocation, finer incremental work and
the remaining roadmap requirements are still open.


### Concrete generic result obligations — 2026-09-06

Generic templates now check concrete result-bearing values before instantiation.
Whole-value transfer, acknowledgement, exhaustive payload handling, scope/return
obligations and safe reassignment are enforced. Branches and matches restore the
same incoming availability state and merge only continuing paths; loops and
short-circuit expressions reject inconsistent obligations. Aggregate operations
cannot silently erase sibling or replaced results. `try` checks compatible
concrete result errors, live local obligations and already evaluated result
temporaries in calls/aggregate construction. Result-bearing references reject
consistently with ordinary functions, including in uncalled templates.

See `docs/experiments/generic-results.md` and `examples/generic-results.my`
(result 9). New acceptance covers uncalled rejection, consumed aliases, both
branch outcomes, match fallthrough, nested payloads, overwrite/self-transfer,
loop/short-circuit state, propagation success/error and pending temporaries,
acknowledgement traps, and allocation failures during checking/execution/native
emission. All 614 core tests pass in Debug and ReleaseFast; all 60 CLI tests pass.
VM/native parity passes 2760 comparisons across 122 fixtures, including imported
result schemas with aliases and a located acknowledgement trap. The final
result-reference restriction also passes the 70-test generic-focused suite.
Formatting and all 88 Guardian checks pass with baselines disabled; report-only
size/line advice remains. This is focused milestone validation, not a new full
resource/provider/binding integration run.

Generic partial field moves remain explicitly unsupported. The next implementation
must track remaining field obligations through snapshots, merges, reassignment
and early propagation; `generic-results-plan.md` records that acceptance contract.
Runtime ownership/regions, parameter-dependent structural types, codec
constraints, public generic tooling, source byte serialization and all other
pending roadmap requirements remain open.


### Concrete generic partial field moves — 2026-09-06

Generic bodies now support `read_field` on concrete records and `take_field` on
concrete result-bearing records. Whole-value availability and immutable moved-field
bitmaps travel together through branch/match snapshots, loop checks and
short-circuit comparisons. Equivalent extraction orders agree; different remaining
fields reject. Scope exit, return, overwrite and early propagation inspect
remaining result obligations. Replacing a handled partial binding restores all
fields, while whole-value use of an incomplete record rejects.

See `docs/experiments/generic-fields.md` and `examples/generic-fields.my` (result
17). Acceptance includes uncalled malformed templates, repeated moves, result
copying, consumed owners, missing fields, nested records, returning/fallthrough
arms, loop replenishment, propagation with remaining fields or temporary results,
and allocation failures during checking, execution and native emission. All 620
core tests pass in Debug and ReleaseFast, all 60 CLI tests pass, and 2778 VM/native
comparisons pass across 125 fixtures. Imported schema/helper aliases and a located
trap after extraction are included. Formatting and all 88 Guardian checks pass
with baselines disabled; nonblocking size/line findings remain. No new full
resource/provider/binding integration run is claimed. Uncertain ROI observations
remain unclassified.

Runtime-owned generic graphs remain excluded. The next abstraction work must
preserve whole/field ownership transfer, implicit cleanup, borrowing, region
lifetimes and capability/effect authority before enabling those graphs. Symbolic
structural types, generic codec constraints, public generic tooling, source byte
serialization and all other pending roadmap items remain open.


### Concrete generic owned flow and cleanup effects — 2026-09-06

Generic bodies now accept concrete owned buffers, pools and external resources,
including their aggregate/result wrappers. Whole and partial reads transfer once;
continuing branches/loops/short-circuit paths agree on remaining ownership. Ordinary
owned values may be discarded or dropped at scope exit, and replacement releases
the prior owner. Result obligations remain explicit. Owned reference parameters and
general borrows still reject under the ordinary checker's current policy.

The abstract pass collects owned-type cleanup masks and resolved call edges, then
reuses the ordinary effect solver. Filesystem/network fallback cleanup propagates
through helper cycles and rejects incompatible bounds in uncalled templates.
Zero-length resource arrays retain their empty cleanup mask. Copy-constrained type
arguments still exclude owned values; ordinary pool handles retain copy identity.
See `docs/experiments/generic-owned.md`, `examples/generic-owned.my` (14), and the
explicit-provider `examples/generic-resources.my` (8 with the test provider).

All 626 core tests pass in Debug and ReleaseFast, all 60 CLI tests pass, and 2790
VM/native comparisons pass across 127 fixtures. Generic-focused coverage passes
82 tests. Selected native resource acceptance passes 10 outcomes and matching VM
provider traces, six generation sanitizer runs and 90 injected allocation failures.
Those selected cases include existing normal resource behavior and generic
filesystem/network cleanup, denied acquisition and a guest trap. The resource
oracle now distinguishes guest traps from host errors. Core allocation sweeps also
verify generic provider release exactly once after explicit or implicit drops.
Formatting and all 88 Guardian checks pass without baselines; nonblocking size/line
findings remain. Uncertain ROI observations remain pending. No new full
resource/provider/binding integration-suite run is claimed.

Acquisition, mutation, provider operations and local arena/reset scopes inside
generic bodies remain explicitly unsupported pending direct authority/effect,
result-shape and region-origin checks. Owned input flow does not establish those
operations. Structural generic types, codec constraints, public generic tooling,
source byte serialization and all other roadmap requirements remain open.


### Generic buffer and pool acquisition/operations — 2026-09-06

Generic bodies now acquire concrete buffers and pools with explicit allocator
arguments, integer capacities and matching owned-success/i64-error results.
Buffer queries/read/write/append/resize/reserve and pool queries/insert/read/
replace/remove/clear enforce exact element/handle/result types and mutable owners.
Owner availability is checked after argument evaluation, rejecting an argument
that transfers the buffer or pool being operated on. Acquisition and reserve seed
allocation effects through helper calls; in-capacity mutations retain noalloc.
The ordinary and abstract checkers share acquisition result validation, and the
ordinary/bytecode/abstract effect passes share the buffer allocation predicate.

See `docs/experiments/generic-runtime.md` and `examples/generic-runtime.my` (33).
Acceptance covers malformed uncalled operations, incorrect authority/capacity,
insufficient symbolic requirements, effect bounds, consumed/immutable owners,
nominal handles, typed mutation results, success and negative-capacity failure,
propagation and allocation-failure cleanup. All 631 core tests pass in Debug and
ReleaseFast, all 60 CLI tests pass, and 2808 VM/native comparisons pass across 130
fixtures. Imported acquisition/mutation helpers and a located empty-buffer trap
are included. Formatting and all 88 Guardian checks pass with baselines disabled;
nonblocking size/line findings remain and uncertain ROI subjects stay pending.
No new full resource/provider/binding integration-suite run is claimed.

Provider acquisition/completion/I/O, clock/random/environment operations and local
arena/reset/view scopes inside templates remain pending. They require capability,
permission, direct-effect and origin/lifetime checks. Structural generic types,
codec constraints, public generic tooling, source byte serialization and the
remaining roadmap requirements remain open.


### Generic provider operations — 2026-09-06

Generic bodies now check clock/random reads, environment lookup, resource
acquisition/completion, capability attenuation, fixed-byte I/O and I/O through
caller-supplied slices. Exact capability families and concrete result schemas are
required; resource I/O checks mutable owner availability after arguments, and slice
reads require exclusive byte views. Direct provider effects propagate through the
abstract call graph, including recursive helpers and statically unreachable source
branches. Runtime provider availability, permission intersection, partial I/O,
result ownership and cleanup retain their ordinary behavior.

See `docs/experiments/generic-providers.md` and the explicit-provider
`examples/generic-provider-slices.my`. Uncalled-template tests reject malformed
contracts and forbidden effects. Execution/allocation sweeps cover generic scalar
callbacks, bounded environment output, owned completion retry and slice I/O.
All 639 core tests pass in Debug and ReleaseFast, all 60 CLI tests pass, and 2808
standard VM/native comparisons pass across 130 fixtures. Native clock/random
acceptance passes 64 value/error/call-count comparisons and 28 injected failures;
environment acceptance passes 60 comparisons and 76 failures. Selected resource
acceptance passes 16 outcomes and matching provider traces, 88 allocation failures
and six generation sanitizer runs. Generic skipped calls execute no callbacks.
The provider builder fixture now selects its intended source explicitly instead
of depending on the final source-list entry. Formatting and all 88 Guardian checks
pass without baselines; nonblocking size/line findings remain and uncertain ROI
subjects stay pending. No new full binding/cache integration run is claimed.

Constructing local array/buffer views and local arena/reset scopes in templates
remain pending. They need abstract borrow and origin/lifetime tracking before
being enabled. Structural generic types, generic codec constraints, public generic
tooling, source byte serialization and all other pending roadmap requirements
remain open.


### Interpreter acceptance workflow — 2026-09-06

`zig build test` now runs the interpreter/checker, complete core/CLI roots and
interpreter/tooling integration. `test-interpreter` aliases that suite. Existing
native compilation drivers moved to optional `test-native`; `test-all` combines
both. Guardian gates every route. The corpus defaults to general/arena VM runs
against independent Python expectations (48 inputs, 96 comparisons), retaining
formatting, duplicate discovery, policy, schema/binding and change-impact checks.
Native corpus execution requires explicit `--native --zig`; shared inexpensive
C-emission checks remain in the core/CLI roots. No native execution work is part
of the active roadmap-completion goal, and no new native suite run is claimed.

Validation: default Debug passes 27/27 build steps and 699/699 core/CLI tests;
ReleaseFast through `test-interpreter` passes 28/28 steps and the same 699 tests.
Both execute all 17 interpreter/tooling Python invocations, including eight
verification-driver unit tests and 96 independent corpus comparisons. Verbose
commands confirm neither route selects native integration drivers. All 29 previous
script entries remain wired, with separate corpus modes; missing `--zig` is
rejected before native-mode execution. Formatting and all 88 Guardian checks pass
with baselines disabled; existing report-only size/line findings remain. Pending
ROI subjects have no new outcome evidence and remain unlabelled.

Next: generic local array/buffer views and region-origin/lifetime checks, followed
by diagnostic repair quality, typed host registration and the board/constraint
trial. These remain open under the interpreter-first roadmap.


### Generic local array and buffer views — 2026-09-06

Abstract generic bodies now create slices from concrete numeric arrays and owned
buffers, using the ordinary checker's shared element-shape helper. Bounds are
evaluated before owner availability checks, so consuming a buffer inside a bound
rejects the subsequent loan. Existing root identity and loan counters enforce
conflicting access, transfer/growth restrictions, parent suspension and lexical
restoration. Array snapshots preserve value semantics. Concrete whole-array
reference inputs may supply returned slices under their declared input lifetime;
local array/buffer views cannot escape that way.

See [the view contract](legacy/experiments/generic-local-views.md) and
`examples/generic-local-views.my` (22). Tests cover uncalled invalid templates,
shape/element/permission errors, transfers inside bounds, active-owner conflicts,
empty/nested views, source-located bounds traps, returned-input provenance and
allocation-failure cleanup. The CLI checks an imported generic returned-view
helper under general/arena VM memory and rejects a module-local lifetime escape.

Validation: 644 core tests pass in Debug and ReleaseFast; all 61 CLI tests pass
in both modes after correcting the new fixture's module call from `api.tail` to
`api::tail`. The initial full suite runs exposed that fixture error; the complete
CLI roots were rerun after the correction. Interpreter/tooling integration also
passes, including 96 independent corpus comparisons. Focused generic coverage
passes 100 tests. Formatting and all 88 Guardian checks pass without baselines;
existing report-only size/line findings remain. No native execution suite was run.

Generic local arena/reset scopes still require allocator-origin and escape
checks. Symbolic array/buffer constructors and structural constraints, generic
codec contracts, public generic tooling, typed host registration and the real
application/repair trial remain open. Native work is excluded from the active
goal.


### Generic arena scopes and reset — 2026-09-06

Generic bodies now create lexical arenas and call typed reset operations with
explicit allocator authority and checked results. Arena creation seeds allocation
effects through the abstract call graph. A stable dependency graph preserves
arena origins through assignments, aggregates, match payloads, partial fields,
loops, references and conservative helper writes; escape constraints are checked
after a monotone fixed point. Ordinary and abstract checking share concrete
arena-bearing type classification and the E_ARENA_ESCAPE contract. Current
equality/integer requirements prove that a symbolic value cannot carry an arena;
a copy requirement alone does not.

Returns, propagated errors, outer bindings and longer-lived buffer/pool storage
reject shorter-lived dependencies before instantiation. Heap-backed owners,
plain snapshots and inert handles can leave an arena scope under their ordinary
rules. Reset retains runtime checks for live storage and child regions. See
[the generic region contract](legacy/experiments/generic-regions.md) and
`examples/generic-regions.my` (3).

Validation: final Debug `zig build test` passes 27/27 steps and 714/714 core/CLI
tests; final ReleaseFast `test-interpreter` passes 28/28 steps and the same 714
tests (652 core, 62 CLI). Interpreter/tooling drivers pass, including the eight
verification-driver unit tests and 96 independent corpus comparisons. Focused
generic acceptance passes 108 tests. Coverage includes allocation failures,
every VM step-budget boundary in both execution backings, module-local escape
diagnostics, reset/reuse, dependency cycles and positive heap/snapshot/handle cases.
Review also removed an over-conservative equality-parameter classification and
added a regression. The rebuilt CLI example, formatting and all 88 Guardian
checks pass with baselines disabled; existing report-only size/line findings remain.
Four explicit-error-set ROI subjects were labelled useful-review; uncertain
subjects remain pending. No native execution acceptance was run.

Next: diagnostic creation/borrow/move/conflict provenance and repair fixtures,
then typed host registration and the board/constraint-processing trial. Structural
generic types, codec constraints, public generic tooling, source serialization
and finer incremental checking remain open; native execution remains excluded
from the active goal.


### Ownership diagnostic provenance and repairs — 2026-09-06

Whole-value transfer/handling failures, conflicting borrows and suspended parent
references now retain both the causal operation and the original binding's
source location. Ordinary and abstract generic checking share the diagnostic
helpers. Ownership snapshots preserve move witnesses across checked paths;
replacement clears the witness before a later transfer. Active-loan selection
is deterministic, and imported generic diagnostics map every note to the
original module. See [the provenance contract](experiments/diagnostic-provenance.md).

Authored repair fixtures assert exact diagnostic codes and source offsets, then
execute corrected result-transfer, borrow-scope, child-reference and moved-buffer
programs. A CLI fixture checks all three imported-module locations and executes
the repaired project. Allocation-failure coverage checks collection and rendering.
These regressions do not measure an agent's repair success rate.

Validation: Debug `zig build test` passes 27/27 steps and ReleaseFast
`test-interpreter` passes 28/28 steps; both pass 721/721 core/CLI tests
(658 core, 63 CLI), the interpreter/tooling drivers and 96 independent corpus
comparisons. Formatting and all 88 Guardian checks pass with baselines disabled;
existing report-only size/line findings remain. A test helper's parameter count
and five hard-limit call lines required one additional gate cycle. No native
execution suite was run.

Partial-field moves, arena/lifetime explanations, versioned machine-readable CLI
diagnostics and optional-value ergonomics remain open in this track. Typed host
registration, the real application/repair trial and remaining interpreter
roadmap items stay active. Native execution remains excluded.


### Partial-move provenance and optional-value audit — 2026-09-06

Partial record state now retains the source span of each extracted field in
immutable snapshots shared by ordinary and abstract generic checking. Reusing a
missing field reports E_FIELD_MOVED with its extraction and owner declaration;
using an incomplete record reports E_PARTIAL_MOVE with an earlier missing-field
witness. Continuing-path checks compare availability independently of source
locations. Restoring a branch restores its witnesses, and whole-binding replacement
clears them. This increases compiler bookkeeping per snapshot; the VM representation
and ownership rules are unchanged. See [diagnostic provenance](experiments/diagnostic-provenance.md).

New fixtures assert exact locations and execute repairs for repeated extraction,
incomplete whole-record use, a continuing branch after another branch returns,
and replenished records. Allocation sweeps preserve diagnostic rejection and
cleanup. Existing branch-order, result-obligation and runtime partial-move tests
remain part of acceptance.

The initial [optional-value audit](experiments/optional-values.md) retains named
unions for absence and declared results for errors. A combined VM lookup example
executed present, absent and failure states; five malformed alternatives rejected
with the expected codes. Nested statement matches and per-payload declarations
are documented design costs for the application trial, not evidence of measured
agent usability or a reason to add implicit unwrapping.

Validation: Debug `zig build test` passes 27/27 steps and ReleaseFast
`test-interpreter` passes 28/28 steps; both pass 725/725 core/CLI tests
(662 core, 63 CLI), interpreter/tooling drivers and 96 independent corpus
comparisons. Formatting and all 88 Guardian checks pass with baselines disabled;
existing report-only size/line findings remain. Two additional gate cycles resolved
a compound assertion, the spec-link format and a test-only failure sentinel warning.
The assertion finding was labelled useful-review; the sentinel finding was labelled
false-positive because an equivalent test assertion was the only resulting change.
No native execution suite was run.

Next: arena-origin and returned-lifetime explanations and versioned machine-readable
CLI diagnostics, then typed host registration and the application/repair trial.
Broader abstraction/tooling and trial evidence remain open. Native execution stays
outside the active goal.


### Arena and returned-reference diagnostic evidence — 2026-09-06

Arena dependency analysis now retains the limiting arena declaration alongside
its depth. Ordinary and abstract generic checking share monotone witness selection:
deeper arenas take precedence, and equal depths select the earliest declaration.
Witness changes propagate through cycles even when depth is unchanged. Existing
conservative dependencies through calls, aggregates, assignments and reference
writes remain intact. E_ARENA_ESCAPE identifies the originating arena scope.

Invalid reference returns now report the returned borrow, its actual owner and
the input parameter required by the signature. Structured diagnostics group owner
and contract evidence under `provenance`, alongside the immediate `related` note.
Both imported-module CLI fixtures verify original lines/columns and execute valid
repairs. See [the diagnostic contract](experiments/diagnostic-provenance.md).

New tests cover escaping buffer allocation repaired to caller-owned backing,
returning a declared input instead of local storage, loop fixed points, helper
writes, nested origins, deterministic cyclic propagation and diagnostic allocation
failures. Notes explain static origins and contracts, not a full trace of every
intermediate operation or a predicted execution path.

Validation: 668 core and 65 CLI tests are validated in Debug and ReleaseFast.
The full Debug interpreter suite passed 27/27 steps and 733/733 tests. The initial
ReleaseFast run passed all CLI tests but exposed NondeterministicMemoryUsage in
an existing allocation-failure sweep: in-place backing growth changed its counted
allocation sequence. Disabling resize in that sweep follows the existing allocator
test pattern. The corrected sweep passes separately in both modes; the final
ReleaseFast interpreter suite passed 28/28 steps, rerunning all 668 core tests and
reusing the unchanged successful 65-test CLI result. Interpreter/tooling drivers
and 96 independent corpus comparisons pass. Formatting and all 88 Guardian checks
pass without baselines; existing report-only size/line findings remain.

One extra gate cycle grouped diagnostic evidence, split a hard-limit line and
shared a repeated note string; the type-size finding was labelled useful-review.
A focused test also caught and corrected the fixture helper name `wrap`, which is
reserved syntax. These were test/design findings, not a new language runtime bug.
No native execution suite was run.

Next: versioned machine-readable CLI diagnostics, followed by typed VM host-function
registration and the board/constraint-processing trial. Broader abstraction/tooling
and application repair evidence remain pending; native execution stays excluded.


### Versioned machine-readable CLI diagnostics — 2026-09-06

`--diagnostics=json` now selects diagnostic-v1 JSON Lines on stderr while command
results and exit statuses retain their existing contracts. Source errors, warnings
and VM traps preserve stable codes, severity, original-file byte ranges and
byte-based line/columns, causal/origin/requirement notes, bounded guest frames and
omission counts. Project discovery/interface errors retain cross-module related
sites. Auxiliary messages have a separate record kind; usage and emergency output
failures may still use text. Invalid UTF-8 text is preserved as byte arrays.

A per-invocation output context applies the format across checking, execution,
formatting, evaluation and tooling. Persistent sessions keep their stdout reply
protocol. Successful warning caches record their format, preventing terminal-text
replay under JSON selection; cold/warm/clear checks preserve identical warnings.
See [the protocol contract](experiments/json-diagnostics.md). This adds no guest
execution to request-only evaluation and does not change language semantics.

Validation: the full Debug interpreter suite passes 28/28 steps and ReleaseFast
passes 29/29 steps; both pass 738/738 core/CLI tests (673 core, 65 CLI), all 18
interpreter/tooling driver invocations and 96 independent corpus comparisons.
New renderer/cache tests exercise allocation failures, mapped EOF/cross-file ranges,
escaped/Unicode/non-UTF8 data, all note roles and bounded traces. The independent
CLI protocol driver covers source errors, module repair, loader/interface errors,
traps, auxiliary failures, format rejection, text compatibility, request-only
behavior and session replay. Formatting and all 88 Guardian checks pass without
baselines; existing report-only size/line findings remain.

Guardian required the behavioral change to have spec/test coverage and then caught
an unconnected four-test module. After wiring it into the root, compilation exposed
an incorrect fixture cleanup API, which was corrected to arena-owned source storage.
The independent driver also corrected its assumption that evaluation-request would
execute a division trap. The orphan/reachability findings were labelled useful-review;
these findings did not expose a language runtime defect. No native execution suite
was run.

Next: typed registered VM host functions with explicit contracts and deterministic
fake-host tests, then the board/constraint application and measured repair trial.
Broader abstraction/tooling requirements remain pending. Native execution remains
outside the active roadmap-completion goal.


## Trusted host registry foundation — 2026-09-06

The [host-function boundary](experiments/host-functions.md) now provides owned
registration snapshots, exact nominal signatures and explicit effect grants.
Every declaration must be bound before a synchronous session begins. Unknown,
duplicate, mismatched, borrowed and authority-bearing contracts reject before
callback execution. Ordinary input/output graphs are validated and independently
copied, including declared result success/error payloads. Call, cooperative-work,
shared input/output value-count and depth limits bound the interface; reentry,
stale sessions and generation wrap reject. Wrappers remain trusted and must use
the execution allocator for owned outputs and release partial outputs on errors.

Nine new registry tests include deterministic fake callbacks, signature-storage
mutation, preflight with an unused missing binding, output-type failures, invalid
arguments, all session limits, ignored cooperative-budget errors, aggregate
independence and allocation-failure cleanup through typed success/error results.
Debug `zig build test` passes 28/28 steps and 747/747 tests; ReleaseFast
`test-interpreter` passes 29/29 steps and the same 747 tests (682 core, 65 CLI).
All 18 interpreter/tooling driver invocations and 96 independent VM corpus
comparisons pass in both modes. Formatting and all 88 Guardian checks pass with
baselines disabled; existing report-only size/line findings remain.

Guardian prompted explicit generation-exhaustion coverage and clearer cleanup
failure reports in fixtures. Its allocator-ownership inference incorrectly
required a destructor on the borrowed call context; an allocator accessor through
the session removes that inference without inventing ownership. The observation
was labelled false-positive; the two test improvements were labelled useful-review.
Other uncertain ROI subjects remain pending. No native execution suite was run.

Next: explicit guest host declarations, visible/transitive host effects, binding
against the same checked program and VM dispatch through one bounded session.
Those integrations remain pending; this checkpoint does not complete the typed
host-interface milestone. The board/constraint trial, measured agent repairs and
broader abstraction/tooling work remain open. Native guest execution stays
outside the active roadmap-completion goal.


## Typed guest-to-host VM execution — 2026-09-06

The initial [typed VM host interface](experiments/host-functions.md) now executes
explicit `host fn` declarations through handwritten Zig wrappers. A declaration
has a semicolon instead of a guest body and an exact `effects(host, ...)`
contract. Ordinary/imported calls and concrete generic helpers preserve nominal
parameter/result identities. Source checking rejects unsupported generic host
signatures, methods/conversions, references, capabilities and runtime-owned data;
main keeps a guest body. Host and additional declared effects propagate through
ordinary and abstract generic call graphs, including uncalled templates, and
exclude calls from effect-free evaluation, invocation and codec contracts.

The program-bound registry derives only marked declarations from validated
bytecode, snapshots their contracts and checks the exact immutable compilation
and catalog. Ordinary guest functions cannot be rebound. Preflight requires all
bindings/grants, including unused declarations, before guest operations. One
session spans an execution; VM instruction/frame accounting and host
call/work/value/depth budgets all apply. Typed success/error variants rejoin
normal guest handling. Callback failure, invalid output and host quota exhaustion
produce located traps with caller traces; allocation failure remains a host error.
Guest-owned buffers and partially produced/copied values clean up on every exit.

Independent bytecode validation rejects fabricated host bodies, entry functions,
signatures and effects. Formatting and disassembly preserve declarations;
duplicate discovery excludes external implementations. Public schemas include
the host effect. The CLI checks these programs and reports missing registrations
in text or versioned JSON; an embedding application supplies wrappers. The
retained C emitter rejects host declarations clearly. No guest-native backend
was added or extended to execute them.

Eleven new core tests and two actual CLI tests cover source contracts, transitive
and uncalled generic effects, separate-program rejection, all-binding preflight,
imported aggregate/result execution, source traces, quota failures, malformed
bytecode, formatting/discovery and cleanup. Allocation-failure sweeps span scalar
calls, imported nominal results and live guest buffer cleanup. The documented Zig
embedding example independently executes and returns 42; a public host schema
reports its exact parameter/result and host effect.

Debug `zig build test` passes 28/28 steps and 760/760 tests; ReleaseFast
`test-interpreter` passes 29/29 steps and the same 760 tests (693 core, 67 CLI).
Both pass all 18 interpreter/tooling driver invocations and 96 independent VM
corpus comparisons. Formatting and all 88 Guardian checks pass with baselines
disabled; existing report-only size/line findings remain. Guardian prompted a
cohesive extraction of binding-warning reporting from semantic checking, plus
line wrapping and one shared effects import; the cognitive-complexity subject
remains labelled useful-review. Fixture corrections used the existing generic
call syntax and source-location API. No native execution suite was run.

Next: the board-validation/constraint-processing application, an independent
behavioral oracle, and recorded agent repair attempts. Its evidence should guide
further abstractions/tooling. Borrowed host buffers/handles need explicit lifetime
contracts if the trial requires them; the current interface rejects such
signatures. Broader pending roadmap requirements remain active. Native guest
execution remains outside this goal.


## Board trial contract and typed application boundary — 2026-09-06

The [bounded keepout contract](../experiments/board_trial/contract.md) now fixes
snapshot capacities, distinct component/net/unit identities, explicit feature
states, input-error precedence, face/layer/net-exemption rules, positive-area
intersection and deterministic first-violation reporting. It is grounded in the
read-only EDA board_keepout/drc_board_keepout sources, with commit and file hashes
recorded. Rectangular integer footprints are a deliberate trial scope: no full
production DRC migration, geometric/performance equivalence or reliability
improvement is claimed.

Before either validator implementation, the independent Python interval/set
oracle and 87 fixed development cases now pass: 27 hand-checked boundary/error
sentinels, 36 face/admission matrix cases and 24 generated snapshots. Cases include
maximum violations, missing/duplicate identities, invalid rectangles, touching
boundaries, exempt copper, through-vias, geometry unavailability and error
precedence. Five oracle self-tests also cover transport rejection, exact
endpoints, translation and identity-renaming invariance. Expected callback counts
are recorded alongside typed result expectations. These are oracle checks, not
executions of a completed guest or Zig validator, and not blinded repair evidence.

The trial exposed the need for typed application entry points beyond scalar main.
`vm.invokeWithHost` and project `Compilation.invokePublicWithHost` now accept
ordinary copied snapshots and return caller-owned nominal values/results through
registered callbacks. Public invocation resolves only exports; references,
capabilities, runtime-owned graphs and direct host-only entries reject. Argument
copying, VM steps/frames and callback budgets remain independent. Pure invocation
retains its effect-free restrictions. Common invocation validation/execution is
shared rather than duplicated.

Three new core tests verify nominal success/error ownership and full allocation
failure cleanup, export selection and invalid inputs before callbacks, located
quota traps, step reporting and fresh sessions after failure. Debug `zig build
test` passes 29/29 steps and 763/763 tests; ReleaseFast `test-interpreter` passes
30/30 steps and the same 763 tests (696 core, 67 CLI). Both pass all 19
interpreter/tooling driver invocations, including the new oracle self-tests and
the existing 96 independent VM corpus comparisons. Formatting and all 88 Guardian
checks pass with baselines disabled; report-only size/line findings remain.
One additional gate cycle wrapped the long public-method signature. A focused
fixture correction used the language's explicit read_ref operation. No native
execution suite was run.

Next: implement the guest board validator and standalone Zig baseline against
these fixed expectations, register the rectangle kernel, compare typed reports
and callback behavior, then run matched repairs with fresh held-out cases. The
application and repair study remain incomplete. Other abstraction/tooling
requirements remain active; native guest execution remains excluded.

## Executable VM board-validation trial — 2026-09-06

The [trial application](../experiments/board_trial/README.md) now executes ten
checked guest modules on the bytecode VM. Its exported validator takes a bounded
nominal Board and returns a typed Validation result. One explicitly registered
`geometry::overlap` callback performs rectangle intersection in Zig. Whole-input
preflight precedes geometry; failed geometry discards the partial report. The
handwritten wrapper preserves domain identities, rejects changed numeric domain
representations, counts operations and charges cooperative work. Guest source is
embedded in the runner at build time.

A standalone Zig validator implements the same fixed contract. The Python grader
passes only sanitized requests to the executable, then compares each VM and Zig
observation independently with the previously fixed oracle. Both match all 87
fixed cases and 60 translation/identity-renaming cases: complete outcomes, exact
first-violation locations and callback counts. Eighteen malformed transports
reject without a report. Three seeded source edits verify located component/net
and unit type errors, and an incomplete feature match with its related new-variant
declaration. These are development regressions, not measured repair attempts.

Four new Zig tests cover snapshot/callback allocation failures, typed geometry
failure and fresh subsequent sessions, a located one-step VM-budget trap with no
callbacks, nominal/capacity rejection, endpoint checks before arithmetic and
partial transport-allocation cleanup. The fixed contract, oracle, cases and five
oracle self-tests remain unchanged. The native baseline is not the complete EDA
DRC, and the shared tiny rectangle kernel is not a routing-performance benchmark.

The application exposed explicit equality helpers for nominal IDs and separate
component/net slot helpers as abstraction costs. Default duplicate discovery
(exact-v28 / near-v3, minimum eight nodes) reports no candidates, indexing 18/29
functions without truncation. Its matching-header restriction excludes helpers
with different nominal argument types; this is not proof of no semantic overlap.
These observations can guide later equality/parameterized-type experiments.

Guardian's fixed src/test scan required moving executable trial sources under
`src/board_trial/`; the contract/oracle stay under experiments. Added real test
and executable reachability roots, documented boundary contracts and retained
structured trap data in the application helper. All artifact installations now
precede attaching the install gate so both executables are gated. Baselines stay
disabled; existing report-only size/line findings remain. Thirty-eight trial ROI
subjects received evidence-backed labels; uncertain subjects remain pending.

Validation: Debug `zig build test` passes 33/33 steps; ReleaseFast
`test-interpreter` passes 34/34. Each executes all four new trial Zig tests and
all 20 interpreter/tooling Python invocations, including 96 existing independent
VM corpus checks. Unchanged core/CLI test results are cached in these runs; no
fresh 763-test execution is claimed. `zig build`, Zig formatting, guest project
formatting and all 88 Guardian checks pass; ReleaseFast reuses the green Guardian
result. No guest-native execution acceptance was run.

Next: prepare matched repair tasks and fresh held-out cases, retain actual
attempts and independent outcomes, and use those results to prioritize the
remaining language abstractions and tooling. The repair study and broader
roadmap remain incomplete. Native guest execution remains outside the active goal.


## Recorded repair-study tooling — 2026-09-06

The [repair-study harness](../experiments/board_trial/repair/README.md) now
prepares five task pairs: nominal identity mixing, unit conversion, missing
through-via handling, net exemptions and board-boundary behavior. Four use the
existing board validator; the units task compares its existing guest helper
with an equivalent small Zig helper. The state task is a missing-handler
regression, not full evolution of the board schema. Actual agent repair attempts
and broader schema/application experiments remain pending.

Preparation freezes compiler/trial source, tool and harness hashes and provides
only editable files plus read-only same-language context. It records the seeded
failure before participant work, then captures every check's immutable source,
patch, diagnostics, command status and timing. Repeated unchanged checks are
separate from edited submissions. Out-of-scope edits, missing context and symlink
submissions are retained as failed boundary checks before execution. There are
five edited submissions and twenty checks per task; snapshots and later grading
retain failed and abandoned outcomes rather than selecting successes.

Sealing stops edits/checks from affecting the submitted candidate. Paired grading
requires both sides to be sealed and their task, model label, tools, sources and
budgets to agree. It then creates shared fresh inputs: 128 board cases or 64 unit
conversions. Interrupted grading resumes the same plan and retains partial runs.
Individual grading remains explicitly unpaired. The output records raw outcomes
and first-edited/final correctness, with no automatic comparative reliability
claim. Context restrictions are a study protocol, not an OS sandbox; review
actual patches for type erasure, changed contracts and other workarounds.

Ten harness self-tests verify all ten seeded failures and known restorations on
development and fresh cases, source boundaries, sealing, snapshot/tool/compiler
changes, check budgets, symlink handling, timeout records, paired case identity
and grading recovery. These are explicitly labeled fixture restorations, not
agent measurements. An initial fixture run found that the Zig admission seed
left an unused via payload capture; removing that capture made the seed expose
its intended behavioral error. No language implementation bug was identified.

Debug `zig build test` passes 34/34 steps and ReleaseFast `test-interpreter`
passes 35/35. Both execute all 21 interpreter/tooling driver invocations,
including the ten new harness tests, existing 147 board comparisons and 96
ordinary VM corpus checks. The three unchanged Zig test roots reuse cached
results; no fresh full Zig-test execution is claimed. The focused
`test-repair-study` target, formatting and the Guardian gate pass with baselines
disabled. Existing report-only findings remain. No guest-native backend work or
acceptance was performed.

Next: run actual matched attempts with fresh isolated participants, retain raw
outcomes and patch reviews, then use that evidence and a real project pilot to
prioritize remaining abstractions, serialization and incremental tooling. The
subagent authorization question is pending; the broader roadmap remains active.

## Scalar domain equality from the board trial — 2026-09-06

The board trial exposed redundant `same` helpers for nominal IDs. Scalar domains
now support `==` and `!=` between values of the same resolved declaration, using
their integer or boolean backing values. Generic `T:equality` accepts those
same types. This adds no implicit arithmetic, ordering, integer requirement,
conversion, representation access or equality between distinct declarations.
Import aliases preserve declaration identity; identical names in separate
modules remain distinct. See [the contract](experiments/domain-equality.md).

The typed binary IR remains independent of execution. A dedicated `CMP_DOMAIN`
bytecode operation validates the domain schema and checks runtime operand
identity and backing shape without synthesizing privileged unwraps in callers.
It preserves left-to-right evaluation, scalar precision, operand cleanup and
VM limits. The historical C emitter explicitly rejects this new operation;
guest-native execution remains excluded from the active goal.

The guest board validator now compares component/net IDs directly and removes
two `same` helpers. The fixed contract and oracle are unchanged. Parameterized
composite types are still needed to address the separate duplication between
component/net optional-slot membership routines.

Eight focused tests cover scalar widths and extremes, booleans, generic
requirements, module aliases and distinct declarations, forbidden operations,
invalid comparison schemas/runtime identities, disassembly, allocation-failure
cleanup, bounded loops, step limits and left-operand trap precedence. Existing
board cases check that simplifying the guest code preserves application behavior.

Validation: the first Debug acceptance run executed all 775 Zig tests successfully
(704 core, 67 CLI, four board integration), and its Python drivers passed. Its
only failure was Guardian's test-structure finding; instruction lookup was then
separated from assertions. The final Debug rerun passes all 34 build steps,
including a fresh 704-test core run and the Python drivers; the unchanged CLI
and board Zig test roots reuse their successful results. All 88 Guardian checks
pass with baselines disabled,
and existing report-only findings remain. ReleaseFast passes the eight new
focused tests plus four imported runtime tests, an 8/8-step gated install, and
the board driver: 147 comparisons, 18 malformed transports and three seeded
static errors. No guest-native suite was run.

Next: complete the matched repair study when fresh-participant authorization is
available, then prioritize parameterized composite types, serialization and
incremental tooling using that evidence and a real project pilot. The pending
agent study has not been run; the broader roadmap remains open.

## Generic fixed arrays — 2026-09-06

The next collection-abstraction layer now supports fixed numeric arrays whose
elements depend on function type parameters: `[2]T`, nested `[2][2]T`, array
parameters/results and annotations, construction, indexing, length, replacement,
whole-value references, local slices and returned input slices. Explicit calls
can substitute composite arguments such as `pair::<[2]T>(...)`. The example
[`generic-arrays.my`](../examples/generic-arrays.my) uses one membership function
for component and net IDs and returns `3`; their nominal identities remain
incompatible. See [the array contract](experiments/generic-arrays.md).

Universal checking preserves element requirements and exact shapes before any
instantiation. Uncalled invalid templates reject, arrays acquire neither scalar
equality nor arithmetic, and copy/result obligations, snapshots, borrowing and
arena-origin checks remain in force. Imported public generic functions resolve
array types through module/source relocation, and formatting round-trips them.

The catalog defers only enclosing declared type variables; unknown names still
fail. Concrete specializations intern arrays by length and resolved element
identity and reuse existing concrete shapes. Downstream checking and lowering
use the grown catalog. Additional shapes are capped at 4096 independently of the
existing 4096 function-specialization limit. Array type traversal is bounded;
ordinary expression/statement work accounting retains its previous boundary.
No guest-native backend implementation or acceptance work was added.

Ten focused tests cover nominal-ID reuse, nested/cross-call substitution,
concrete helper compatibility, empty arrays, malformed uncalled templates,
length/type requirements, copy/result boundaries, arena escape, mutable/shared
views and returned lifetimes, bounds source locations, imported declarations,
formatting, identity reuse, allocation failures and both expansion budgets.
The CLI test executes a generic array computation and checks a structured error
from an uncalled template. Existing generic regressions also cover provider
calls, effects, result handling and ownership around these changes.

Validation: Debug interpreter acceptance passes 34/34 build steps and 786/786
Zig tests (714 core, 68 actual CLI, four board integration), plus the 21 Python
drivers. All 121 generic regressions pass in Debug and ReleaseFast. The final
focused array tests, including the additional independent shape-budget check,
pass in both modes (ten array tests plus four imported runtime tests). The
ReleaseFast gated install passes 8/8 steps, the formatted example returns `3`,
and the board driver passes 147 comparisons, 18 malformed transports and three
seeded static-error checks. The repair-study harness's fixture regressions pass;
actual agent repair attempts remain pending.

Guardian passes all 88 checks with baselines disabled. Its type-size finding
prompted cohesive `ArrayCatalog` state, and a long conditional was split to fit
the hard line limit. The type-size subject is labeled useful-review locally;
existing report-only findings remain. The wider generic tests caught and helped
fix a temporary work-budget regression without relaxing their existing boundary.

This completes the numeric fixed-array portion of parameterized composites.
Parameterized records, optional-slot unions/results, named buffers, numeric
length parameters and broader structural constraints remain open. Symbolic
enum-keyed tables reject explicitly with `E_GENERIC_ARRAY_KEY`. The board trial's
optional-slot contract still requires separate component/net membership routines
until parameterized unions are implemented. The fixed trial contract is unchanged.

Next: parameterized nominal records and unions, plus actual matched repair
attempts when fresh-participant authorization is available. Source serialization,
public generic tooling, finer incremental checking and the other pending roadmap
requirements remain active; native execution remains excluded.

## Nominal template syntax and interface groundwork — 2026-09-06

This checkpoint adds the representation needed for parameterized nominal types;
**it does not implement their semantic specialization or execution**. Record and
variant declarations retain explicit type parameters/requirements, while
applications such as `Slot<Pair<i64,bool>>` retain separate base-name and argument
spans. Type expressions now group arrays and nominal applications separately
from declarations. Construction and match-arm type positions use the same
application syntax. See [the staged contract](experiments/nominal-type-syntax.md).

Owned AST copying, module relocation and the bounded syntax cache preserve this
metadata. Module interfaces check declaration identity through direct aliases,
application arity, nested public-type visibility and parameter shadowing. Unknown
requirements reject even in private nominal declarations. This phase does not
claim to verify layouts or application requirement satisfaction.

Formatting uses parsed nominal angle positions so argument commas do not become
field separators. Comments survive, and `let x:Box<i64>=...` is recognized as a
type close followed by assignment and formatted with separating whitespace.
Ordinary `x >= y` comparisons keep their meaning. Parameter/argument lists remain
bounded at 16 and recursive syntax at 256 levels.

Until semantic specialization is implemented, source checking rejects nominal
templates and applications with `E_GENERIC_TYPE_UNSUPPORTED` before typed IR or
bytecode is produced. An unused template cannot be silently treated as an empty
ordinary record. Existing executable generic functions and fixed arrays retain
their current behavior. No guest-native backend work was added.

Seven new core tests exercise nested declarations/applications, constructors and
patterns, owned copying, mapped spans, comments/formatting/operator ambiguity,
list/nesting bounds, cached module relocation, privacy/arity/kind/scope rejection,
allocation-failure cleanup and the explicit semantic boundary. One actual CLI
test checks formatting and structured execution rejection.

Validation: Debug interpreter acceptance passes 34/34 build steps and 794/794
Zig tests (721 core, 69 actual CLI, four board integration), plus the 21 Python
drivers. The board trial still passes 147 comparisons, 18 malformed transports
and three seeded static errors. All 40 nominal-related tests selected in
ReleaseFast pass, including the new syntax/allocation-failure tests. The gated
install passes 8/8 steps and formatting passes. These checks establish the
syntax/interface groundwork and preservation of existing interpreter behavior;
they do not establish executable nominal specialization or agent repair results.

Guardian passes all 88 checks with baselines disabled; existing report-only
findings remain. Two `error-path-test` findings required helper names in an
already-existing allocation-sweep test title. No coverage changed; both subjects
were labeled false-positive locally and the shared extra gate cycle was counted
once. Mandatory usage feedback records that limitation.

The remaining nominal-type milestone requires:

- Template validation even when unused: names, duplicate fields/cases, argument
  requirements, by-value recursion and declaration-scoped identities.
- Concrete instance interning by template declaration and ordered resolved type
  arguments, with bounded growth and complete layouts in the shared catalog.
- Symbolic field/payload checking for construction, projection, updates, matching
  and results, preserving ownership, partial moves, borrowing, effects and arena
  origins without representative-type substitution.
- Composition with generic arrays/calls and module visibility, followed by the
  board trial's parameterized optional-slot types and shared membership routine
  against its unchanged behavioral contract.

The nominal-type milestone remains open, alongside the actual matched repair
study, source serialization, public generic tooling, finer incremental checks
and other pending roadmap requirements. Native execution remains excluded.

## Nominal template declaration semantics — 2026-09-06

The [declaration-checking stage](experiments/nominal-template-checks.md) now
builds reusable semantic metadata for parameterized records and variants.
Field/payload expressions retain declaration identities, ordered applications,
recursive arrays and local type variables; identically spelled templates from
different modules stay distinct. This metadata is separate from executable
`typed.Type` IDs and does not substitute a representative scalar for a parameter.

Unused declarations now report unknown field types, parameter shadowing,
duplicate fields/cases/types, malformed result schemas, wrong application arity,
invalid constructor kinds and insufficient argument requirements before the
remaining specialization boundary. Requirement diagnostics retain the argument
site and the declaration's requirement site, including across imported modules.

Copy guarantees propagate through ordinary/generic records and unions using a
reverse dependency worklist. Owners and pending results remove copy transitively;
zero-length arrays do not acquire their element's value obligations. Nested
argument constraints still apply, including phantom parameters and enum table
keys. Scalar domains, enums and pool handles keep equality without gaining
integer operations, and records/unions do not acquire implicit equality.
Expression checking is bounded at 256 levels and 100,000 visits. The worklist
visits each removed copy guarantee once rather than recursively walking long
declaration chains.

Ten new core tests cover declaration metadata, invalid unused types, requirement
implication, ownership/results, array keys/lengths, checking-work exhaustion,
imported identities and original diagnostic locations. They include allocation
failure sweeps on successful collection, semantic rejection and a diagnostic
allocator separate from the compilation arena, plus a 1,200-record
reverse-ordered dependency chain. One actual CLI test verifies
structured errors from unused templates.

This completes the names/member/argument-requirement portion of template
validation. It does **not** prove finite by-value layouts or implement concrete
instance interning, executable layouts, symbolic field/payload operations,
borrowing/arena behavior for those operations, or board `Slot<T>` consolidation.
Well-formed templates still reject with `E_GENERIC_TYPE_UNSUPPORTED` before typed
IR or bytecode. Function-body uses of parameterized types remain behind that
boundary. No guest-native work was added.

Validation: the final Debug interpreter suite passes 34/34 build steps and
805/805 Zig tests (731 core, 70 actual CLI and four board integration), plus all
21 Python drivers. The board trial retains 147 matching comparisons, 18 malformed
transport rejections and three seeded static errors. All 50 nominal-selected
tests pass in Debug and ReleaseFast. The gated install passes 8/8 steps and
formatting passes. Repair harness fixtures pass; actual agent repairs remain
pending.

Guardian passes all 88 checks with baselines disabled; existing report-only
findings remain. Condition/diagnostic formatting and a sharper work-boundary test
were labeled useful-review. A test-only lookup error requirement was labeled
false-positive because replacing it with an ordinary test assertion added no
coverage. The shared extra gate cycle was counted once. Separate allocator
review/testing exposed and fixed metadata allocation through the diagnostic sink;
that leak was not a Guardian finding. Mandatory feedback records these outcomes.

Next: finite layout validation and concrete nominal instance interning in the
shared catalog, then symbolic construction/projection/update/match/result rules
and the unchanged board trial. The measured repair study, serialization,
incremental tooling and remaining roadmap requirements stay open.


## Finite nominal template storage graphs — 2026-09-06

[Finite layout checking](experiments/nominal-layouts.md) now validates the storage
of unused and imported nominal templates before executable specialization. Its
canonical identities retain declaration identity, parameter scope and ordered
arguments. Repeated applications share an identity without merging unrelated
nominal declarations or replacing parameters with representative scalar types.

The graph expands stored fields, payloads and array/buffer/pool elements. It
interns phantom arguments without expanding their storage. This admits finite
`Box<Box<T>>` nesting and `Empty<Finite<[1]T>>` phantom arguments while rejecting
actual stored recursion. Pool handles remain leaves, and zero-length arrays
retain the existing finite-type rule. The template metadata now also retains
buffer and pool element expressions for this check.

Worklist expansion and iterative DFS avoid host recursion along long declaration
chains. Direct, indirect, argument-permuting and array/result/owner cycles report
`E_RECURSIVE_RECORD` at their closing edge, with a related layout site and original
module locations. Argument-growing families stop at explicit limits: 4096
argument-bearing nominal identities, 4096 array identities and 100000 expansion
operations. Generic declaration roots count toward the nominal identity limit.
These are compiler limits, not claims that every rejected family is cyclic.

The graph owns its keys, edges and worklists, borrows the declaration index and
diagnostic sink, and cleans up success and partial failures. Eight new core tests
cover finite/recursive forms, ordered identity reuse/separation, independent
expansion limits, a 1200-type finite chain, allocation failures with separate
graph storage, and private imported cycle diagnostics. One CLI test verifies
recursive rejection and preserves the remaining execution boundary for finite
nested/phantom forms.

The finite storage-dependency portion is implemented. Graph IDs remain distinct
from executable type IDs; unexpanded phantom identities must not be converted to
empty runtime schemas. Concrete catalog materialization, parameterized
record/variant operations, ownership/borrowing/arena behavior for those operations
and board `Slot<T>` consolidation remain pending. Well-formed finite templates
still report `E_GENERIC_TYPE_UNSUPPORTED` before typed IR or bytecode. No native
guest backend work was added.

Validation: Debug interpreter acceptance passes 34/34 steps and 814/814 Zig
tests (739 core, 71 actual CLI, four board integration), plus all 21 Python
drivers. The final 58 nominal-selected tests pass in Debug and ReleaseFast,
including additional exact-cap acceptance and first-excess rejection assertions.
The board trial retains 147 matching comparisons, 18 malformed transports and
three seeded static errors. The gated install passes 8/8 steps and formatting
passes. Repair harness fixtures remain distinct from actual agent repair results.

Guardian passes all 88 checks with baselines disabled and existing report-only
findings retained. Its ownership check prompted explicit graph cleanup and
standalone allocation-failure coverage. Hash/equality documentation, diagnostic
formatting and a shared generic-limit code also received useful-review labels;
two extra gate cycles were recorded once each. These findings prompted design
and maintainability improvements rather than exposing an existing runtime bug.
Mandatory feedback records the outcomes.

Next: concrete nominal catalog specialization that preserves these semantic
identities and complete stored-value layouts, then symbolic field/payload
operations and the board trial. The measured repair study, source serialization,
incremental tooling and remaining roadmap requirements remain active.


## Concrete nominal instance execution — 2026-09-06

Concrete record, union, result and enum templates now specialize into complete
runtime schemas and execute on the bytecode VM. Declaration identity and ordered
argument identities preserve distinctions across nested applications, arrays,
enum keys and imported aliases. Existing generic functions can receive concrete
instances, including arrays of those instances. `examples/nominal-instances.my`
returns `16`. See [the instance contract](experiments/nominal-instances.md).

The catalog materializes only demanded concrete storage. Unused symbolic roots
and unexpanded phantom arguments do not become fabricated empty runtime records.
Graph expansion resumes for concrete source applications; the catalog and
ordinary declarations share runtime lookup and finite ownership/layout validation.
Canonical display names have a 1 MiB compilation budget to bound exponential
argument-name growth in otherwise finite type families.

Construction, updates, exhaustive matches, checked result propagation, partial
owned field moves, borrowing, snapshots and arena escape checks use the existing
language rules. Imported public value lookup now resolves the base declaration
and requires public argument identities, including phantom arguments. Typed host
registration transports complete concrete signatures and checked result payloads.
Tests also cover ordinary domains, pool handles and resource contracts when a
nominal template selects the new catalog path.

Symbolic nominal applications such as `Box<T>` in generic function bodies still
reject with `E_GENERIC_BODY_UNSUPPORTED`. Exporting a generic type constructor
through public schema tooling reports `E_SCHEMA_GENERIC_TYPE` with a source
location; the lower-level graph API has an explicit unsupported error. Neither
limitation is treated as completion of the larger nominal-type milestone.

Validation: `zig build test-interpreter --summary all` passes 35/35 steps and
829/829 Zig tests (753 core, 72 CLI and four board-runner tests), plus all 21
Python drivers. The 72 nominal-focused tests pass in Debug and ReleaseFast;
allocation-failure sweeps cover plain/owned schemas, imported programs, typed
host calls and mixed domain/pool/resource catalogs. Both CLI memory backings run
the example successfully. Formatting and the gated install pass. Guardian passes
all 88 checks with baselines disabled; existing report-only findings remain.

The board trial retains 147 matching comparisons, 18 malformed transports and
three seeded static-error checks; the ordinary VM corpus retains 96 independent
oracle comparisons. Repair harness fixture tests pass, but actual agent repair
attempts remain pending. No guest-native integration was run.

Guardian prompted an explicit specification contract, direct schema error-path
coverage and a reusable catalog test scenario now swept for allocation failures.
Those evidence-backed observations are labeled useful-review. Hard-limit line
splits, a shared import and removal of temporary debug output also cleared the
gate. These gate findings did not establish a language runtime defect.

Next: symbolic nominal field/payload operations and specialization in generic
functions, then board `Slot<T>` consolidation and public generic tooling. The
measured repair study, source serialization, finer incremental checking and other
remaining roadmap requirements stay active. Guest-native compilation remains
outside this goal.


## Symbolic nominal function bodies — 2026-09-07

Generic functions now check parameterized record, union, result and enum shapes
before calls. Scoped symbolic arguments preserve declaration identity through
callee substitution, construction, projection, updates, exhaustive matches and
named-result propagation. Mixed symbolic/concrete types compare semantic
identities; matching fields or requirements do not merge nominal declarations.
`examples/nominal-bodies.my` returns `7` on the VM. See [the body contract](experiments/nominal-bodies.md).

Stored-member contracts preserve partial ownership, result obligations, cleanup
effects, borrowed mutation, returned-input lifetimes and arena escape checks.
An explicit stack traverses stored children and caches nominal shapes; absent
phantom values and zero-length arrays acquire no storage contract from an unused
argument. Ordinary unconstrained type parameters still need structural constraints
for member operations. Buffer/pool acquisition and fixed operation-result contracts
also accept symbolic nominal result wrappers.

Late function specialization now appends complete runtime schemas to an existing
catalog while preserving earlier type IDs. Arrays created by an earlier generic
function reuse their identity, and field indexes grow with amortized capacity.
The shared nominal metadata is independent of the catalog builder. Graph and
identity storage remain in the compilation arena until checking finishes; the
symbolic shape context explicitly borrows its owning function's arena. Growing
specialization stops at compiler resource limits before producing bytecode.

Validation: the full Debug interpreter suite passes 35/35 steps and 841/841 Zig
tests (764 core, 73 CLI and four board-runner tests), plus all 21 Python drivers.
All 83 nominal-focused tests pass in ReleaseFast. New allocation-failure sweeps
cover symbolic shapes, late arrays/catalogs, result propagation, imported generic
helpers and owned cleanup. The example returns `7` with both memory backings;
formatting and the gated install pass. Guardian passes all 88 checks without
baselines; existing report-only findings remain.

The initial broad regression found four changed diagnostic codes, which were
restored rather than weakening their tests. Guardian's import-cycle finding led
to a separate shared-state module; nesting and public-key findings improved the
traversal and exposed API. The destructor heuristic incorrectly treated a
borrowed allocation context as an owner; that observation is labeled false-positive,
and the API now makes the borrowed arena explicit. Other classified findings are
useful-review. These findings do not establish a shipped runtime defect.

The board trial retains 147 matching comparisons, 18 malformed transports and
three seeded static errors; the ordinary VM corpus retains 96 independent oracle
comparisons. Repair harness fixtures pass, while actual agent attempts remain
pending. No guest-native execution integration was run.

Next: provider-specific symbolic shapes (resource/environment/codec contracts),
public generic tooling and board `Slot<T>` consolidation. Structural constraints,
source serialization, finer incremental checking, the measured repair study and
other remaining roadmap requirements stay active. Native guest compilation
remains outside this goal.


## Symbolic provider payloads and concrete generic codecs — 2026-09-07

[Generic provider contracts](experiments/nominal-providers.md) now accept nominal
result and payload templates around resource acquisition, completion, reads/writes,
slice I/O and environment lookup. Concrete and symbolic checking use the same
named field contracts, independent of source declaration order. Exact byte arrays
remain required, including when their u8 element is known through generic helper
substitution. General integer parameters cannot stand in for bytes.

Authority, resource identity, mutable access, borrow exclusivity, handling and
transitive effects remain checked before calls. VM tests preserve partial I/O,
zero padding, absent/empty/binary environment values, failed-completion ownership
and retries. Allocation-failure sweeps and traps at every instruction require each
acquired owner to be completed or released exactly once. Malformed named layouts
reject through both ordinary and generic checking.

Generic callers may also invoke declared codecs for concrete domains. The checker
follows selected factories/accessors and imported helper methods, retaining exact
signatures, results and domain representation privacy for wrap/unwrap. Codec
methods remain effect-free, including transitive calls. Codec constraints on
arbitrary type parameters are not implemented by this checkpoint.

Validation: `zig build test-interpreter --summary all` passes 35/35 steps,
853/853 Zig tests (776 core, 73 CLI, 4 board) and 21 Python drivers. Focused
provider/generic/resource/codec checks pass 299 tests; nominal and generic-codec
ReleaseFast checks pass 95. Formatting, gated installation and all 88 Guardian
checks pass with baselines disabled. Guardian caught a duplicate specification
anchor and hard-limit fixture/diagnostic lines; these were corrected without
baselines, and evidence-backed ROI subjects were labeled useful-review. Existing
report-only size/line findings and uncertain ROI subjects remain.

The board trial retains 147 matching comparisons, 18 malformed transports and
three seeded checker errors; the ordinary VM corpus retains 96 independent-oracle
comparisons. Repair fixture self-tests pass; actual agent repairs remain pending.
No guest-native execution integration was run.

Next: consolidate the board trial's optional slots and membership helpers using
nominal generics, then public generic tooling and remaining abstraction/codec,
serialization and incremental-checking work. The measured repair study and other
pending roadmap requirements remain active. Guest-native compilation remains
outside this goal.


## Board optional-slot and membership consolidation — 2026-09-07

The [board trial](../experiments/board_trial/README.md) now uses one `Slot<T:copy>`
union for optional component IDs, net IDs, regions, features and first violations.
One `has<T:equality>` function replaces the separate component/net membership
loops. Instantiated slot types preserve nominal ID separation; the trusted snapshot
boundary explicitly rejects a net-ID payload in a component slot. The five guest
modules changed by this refactor contain 34 fewer lines. Distinct validation
factories and domain-specific errors remain explicit.

No changes were made to the fixed trial contract, oracle cases, independent Zig
baseline, geometry kernel or transport schema. The refactored runner still matches
all 87 fixed and 60 transformed cases, including exact reports/callback counts;
18 malformed transports reject and three seeded static errors are caught. All five
board boundary tests pass in Debug and ReleaseFast, including allocation-failure
cleanup and the new cross-slot payload rejection. The ten matched repair fixture
self-tests pass after updating their exact seed strings for formatted generic
calls. These remain harness tests, not measured agent repair outcomes.

Guest project formatting, Zig formatting, gated installation and all 88 Guardian
checks pass with baselines disabled. Existing report-only size/line findings and
uncertain ROI observations remain. The preceding provider checkpoint's full
853-test Zig/21-driver interpreter run remains the compiler-wide regression
baseline; this guest refactor received the focused board and repair acceptance
above, with one additional board test. No guest-native acceptance was run.

Next: public generic schema/tooling, remaining structural and codec constraints,
source serialization, finer incremental checking and the measured repair study.
Those requirements and the broader roadmap goal remain active. Native guest
compilation stays deferred.


## Real Netlisp schematic pilot — 2026-09-07

The requested Straps LMX2595 subcircuit now has a reproducible
[SVG and application](../experiments/schematic/README.md). Its S-expression
parser, circuit model, validation, interface expansion, layout and SVG emission
are written in the language and execute on the bytecode VM. Four explicitly
registered Zig callbacks supply bounded source bytes and unpublished output;
they do not delegate parsing or drawing to the EDA renderer. No guest-native
execution work was added.

Quoted byte literals now lower to ordinary fixed `[N]u8` arrays. They support
UTF-8 bytes, escaped text and explicit hexadecimal bytes, preserve generic and
borrow semantics, and survive module relocation, cached syntax and formatting.
A literal is limited to 65,536 decoded bytes. The two embedded applications now
share the Zig project-compilation lifecycle and bounded source-manifest reader,
following Guardian's duplicate-code findings.

The generated schematic contains all 30 components, 95 connected pads, four
explicit no-connects and nine interface signals, including expanded SPI lanes.
An independent Python fixture reader checks component values and connections;
all 34 raw nets also match a separately captured Netlisp `netlist-dump`. Supply
branch labels follow Netlisp's structural host-pad/trunk rule while retaining
raw names in SVG metadata. Mutation checks change values, XML metacharacters,
quoted/line-break text, interface lanes and pin labels; those changes reach the
rendered result. Twenty-three malformed, duplicate, unsupported or disconnected
inputs reject with located diagnostics and no partial SVG. The SVG was rendered
and visually inspected.

This is a bounded real-source pilot, not a complete Netlisp implementation. It
supports a parameterless module, one 41-pad IC, the two-terminal primitive
families needed here, direct ports and peripheral interface renames. Known
non-rendering electrical/PCB metadata is retained as input but does not perform
electrical validation. Arbitrary expressions, nested module evaluation,
controller-role inversion and additional library families remain unsupported.
The CLI takes explicit module, pinout and interface files. The web URL required
sign-in, so the checked-in fixture manifest records hashes and paths of the
matching local source captured on this date.

Validation: the full Debug interpreter suite passes 39/39 build steps and
862/862 Zig tests (781 core, 73 CLI, five board, three schematic), plus all
22 Python acceptance drivers. Subsequent schematic-boundary and XML refinements
pass the focused ReleaseFast schematic gate (8/8 steps, three Zig tests and the
expanded 23-case rejection suite), the three Debug boundary tests and a byte-for-
byte regeneration of the saved SVG. Guest formatting, Zig formatting, gated
installation and all 88 Guardian checks pass with baselines disabled. Existing
report-only size/line findings remain; no frozen baseline was added. Guardian
ROI labels distinguish useful shared-code extraction from a test-name heuristic
that missed an already-exercised helper.

This establishes that the language can implement a useful bounded parsing and
rendering tool against real project source. It does not establish general EDA
coverage or measured agent-repair effectiveness. Public generic tooling,
remaining structural/codec constraints, source serialization, finer incremental
checking and actual repair-study attempts remain active roadmap items. Native
execution remains deferred to a future decision.

## Disk-loaded applications and development infrastructure — 2026-09-07

The schematic and board hosts now require `--project DIRECTORY` and read `main.my`
and its imports on each invocation. A shared bounded disk provider also serves
the ordinary CLI. Guest edits change VM behavior without rebuilding the installed
Zig executable or invoking Guardian. Missing source, syntax/type errors and host
contract mismatches fail explicitly; Zig boundary tests retain isolated fixtures.
The repair-study coordinator was updated for the disk-project runner interface.

`tests/disk_projects.py` verifies import additions/removals, repaired source,
independent project roots, real SVG/policy changes, unchanged binary hashes and
modification times, and operation without build tools on PATH. The full Debug
interpreter gate passes 40/40 steps and 864/864 Zig tests, plus its Python drivers.
Focused ReleaseFast disk/schematic verification passes 14/14 steps and 10/10 Zig
tests, including all 23 schematic input rejections. Formatting and gated ReleaseFast
installation pass; all 88 Guardian checks pass with baselines disabled. Existing
report-only findings remain. Exact-limit reads have a regression test.

The linked disk-project development plan specifies dependency-aware testing,
shared verification receipts, a multi-agent scheduler, combined-merge certificates,
safe request-boundary HMR and later semantic query reuse. Those stages are planned,
not implemented by this checkpoint. Native execution remains deferred.

## Incremental verification and persistent VM development — 2026-09-07

Three subagents implemented verification/cache infrastructure, scheduler/merge
certificates and persistent schematic reloads; integration added checked compiler
dependency receipts, a real `.my` verification example, profiling and cross-component
review. V2 verification supports declared suite input closures, affected/full/shadow
modes, bounded snapshots, shared successful receipts and a fixed bounded lock
namespace. SQLite coordination coalesces identical work, admits resource estimates,
ages priority, reclaims abandoned clients and fences late results. Merge certificates
verify the combined candidate and recheck branch, tool, environment and policy
freshness without changing any branch. The schematic development host keeps one
process alive, prepares and commits source generations between requests, and keeps
failed/superseded output from replacing the preview.

Review and regression tests covered cache-hit source races, generated in-memory
input receipts, tool/PATH identity, workspace input mutation, crashed sole-client
queue blockage, certificate freshness, bounded lock storage, FIFO rejection and
watcher shutdown. The current Python verification suite passes 43 tests with no
skips. The full Debug interpreter gate passed 42/42 steps: 861 Zig tests executed
and the six schematic tests reused their green cache result. Focused ReleaseFast
verification/reload gates passed 13/13 steps, with six schematic tests executed;
subsequent Python-only refinements passed the final 43-test suite. All Python
interpreter acceptance drivers passed. The live development host regenerated the
saved Straps SVG byte-for-byte. Formatting, ReleaseFast installation and all 88
Guardian checks pass with baselines disabled; report-only findings remain.

Runtime guides provide commands and limits. Selection is at declared suite/module
closure granularity; dependency completeness remains an explicit contract, not an
OS sandbox or automatic discovery of tool runtime libraries. Suites are self-contained,
and produced artifacts are not shared. Existing production gates remain full gates
while shadow evidence is gathered; the certificate tool does not merge/push. HMR
uses synchronous requests with fresh guest state, not state migration. A five-sample
ReleaseFast schematic profile recorded median checks of 8.23 ms cold, 1.07 ms exact
warm verdict and 3.91 ms after a body edit. Finer semantic query caching remains
conditional on larger measured bottlenecks. Native execution remains deferred.
