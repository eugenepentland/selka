# Current language reference

Start with the [Python-style application guide](python-syntax.md) for canonical syntax. This index also links advanced APIs and compatibility examples.

The installed executable's `--features` JSON report gives its compiler identity,
the pinned Zig toolchain, supported features, exclusions and backend coverage.
`compiler_sha256` is that identity: a SHA-256 computed when the compiler was built,
over its own source inputs, Zig version and optimize mode — not a hash of the
executable file, which the compiler no longer reads. The same value appears in every
receipt's `implementation`, so a feature report and a receipt from one compiler always
agree, and two builds of the same sources are recognisably the same compiler.
`language-features-v1` versions the report format; the language remains
experimental version 0.1.0. A feature being implemented is distinct from a
particular build passing its tests. Run the acceptance suite for the binary you
intend to use; historical counts are not current verification receipts.

| Area | Supported surface | Executable example / restriction |
| --- | --- | --- |
| Values | `int`, binary64 `float`, booleans, managed Unicode strings/dictionaries/lists, byte literals, value records, checked Result/Option, domains/arrays, scalar constants and transparent aliases | [constants](module-constants.md), [aliases](type-aliases.md); [bounded scalar source evaluation](source-evaluation.md) |
| Control flow | Indented if/elif/else, while, foreach/enumerate/range, break/continue and match/case | [range iteration](range-iteration.md), [match expressions](match-expressions.md); conservative outer ownership on loop exits |
| Generics | Functions and nominal records/unions/results/enums; structural field/operation contracts and const length parameters | [structural contracts](../examples/structural-constraints.my); [inferred call type arguments](generic-inference.md) |
| Managed allocation | Shared growing lists and dictionaries, immutable strings, nonmoving tracing GC and cycle reclamation | [Managed memory](managed-memory.md); managed graph host/native boundaries remain excluded |
| Managed arenas | `with arena() as name:` region blocks over ordinary managed objects, bulk release, `escape` copy-out, static and runtime escape checks | [Managed arenas](arenas.md); [runnable example](../examples/arena-managed/main.my); VM only, rejected by the QBE native backend |
| Managed bytes | Immutable GC byte strings with Python indexing, slicing, membership, split/join and text/hex conversions | [Managed byte strings](bytes.md); byte strings are rejected at JSON and host boundaries like `str` |
| Ordinary I/O | `print` with Python rendering and an `output` effect; `with open(...)`, handle methods and whole-path file helpers over granted directories | [printing, files and authority](io.md); VM only, rejected by the QBE native backend |
| Resources | External resource owners, explicit completion and deterministic cleanup | [source resources](experiments/source-resources.md); [resource reads and writes](experiments/resource-io.md); no ambient operating-system authority |
| Authority | Explicit host capabilities and transitive effect ceilings; `mylang run --allow-*` grants them from the command line | [effects](../examples/effects.my); [command-line grants](io.md#capabilities); [byte runner scoped directory/endpoint grants](experiments/scoped-providers.md) |
| Modules | Disk imports, explicit exports, nominal identity and embedded standard modules | [domain codecs](../examples/domain-codecs/main.my); [local locked package roots](experiments/local-packages.md); no network version resolver |
| Data interchange | Typed JSON codecs at the CLI and host boundary, and managed byte strings | [managed byte strings](bytes.md); `bytes` is not a Unicode string type; guest-source JSON operations were removed with the explicit storage tier |
| Development | Independent function diagnostics, navigation, parse-only declaration listing, formatting, syntax/exact-verdict/function-body caches, affected verification | [navigation](experiments/navigation-client.md); [declaration listing](experiments/list-declarations.md) reports kinds and byte ranges without checking; [changed-source reuse](../experiments/semantic-incremental/README.md) preserves fresh global checks with conservative fallback |
| Documentation | Every fenced `mylang` example in README, SPEC and docs is run, type-checked or explicitly skipped by the default test gate | [executable documentation](experiments/doc-examples.md); directives pin expected output, expected diagnostics and explicit skips |
| Tests | Exported test_ function discovery, typed expected values, filters and explicit skips | [guest test workflow](experiments/guest-tests.md); deterministic arguments and isolated source-provider fixtures |
| Byte application I/O | Scalar compatibility and bounded copied 256-byte blocks, configurable input/output/execution budgets | [bulk I/O](byte-io-bulk.md); output publishes only on successful guest exit |
| Execution | Typed bytecode VM; QBE native builds through `mylang build`, `emit-qbe` and `emit-project-qbe` | [native experiments](experiments/roadmap.md); [direct C imports](c-ffi.md) and [guest tests](experiments/guest-tests.md) describe the native route |

The detailed [SPEC](../SPEC.md) and focused experiment references describe
operation contracts and their tests. [semantics.md](semantics.md) preserves
historical checkpoints and must not be read as one current feature inventory.

Absent features include capturing closures, guest shared-memory threads, arbitrary
stored reference lifetimes and unrestricted source compile-time execution. The [feature audit](audits/feature-completeness-2026-09-07.md) proposes
extensions; their presence in that backlog does not claim implementation.

Memory safety combines the nonmoving tracing collector with VM checked handles,
generations and leases. Each VM is single-threaded; [isolated process workers](experiments/workers.md) provide bounded parallel execution with copied typed messages. `noalloc` restricts managed guest
allocation, not all compiler/VM/host allocation. Host callbacks are
trusted implementations of documented contracts. These limits are part of the
current model, not guarantees supplied by a future backend or thread system.

`float` provides decimal literals and ordinary numeric operators. `std_math::F64` retains named IEEE binary64 arithmetic, basic math, checked integer conversion and exact bit codecs; see [floating-point.md](floating-point.md).

Scalar constants may call bounded nongeneric source functions with scalar locals and control flow; see [source-evaluation.md](source-evaluation.md).

[Runtime memory reports](experiments/runtime-memory-budgets.md) distinguish logical slots, guest backing and bookkeeping. Typed holes, bounded VM traces, in-memory host replay and named executable laws are experimental agent-facing tools; comparative productivity evidence remains pending.

Run `python3 tests/feature_surface.py --compiler zig-out/bin/mylang --output receipt.json`
to execute the documented feature-surface examples and verify explicit
unsupported syntax and unresolved-hole rejection. The receipt pins the executable,
feature report and case source hashes; it complements the broader acceptance suite.
Generic functions and nominal declarations support explicit `const N:u64` length parameters; see [const-length-generics.md](const-length-generics.md).

[Typed noncapturing callbacks](experiments/callbacks.md) support reusable sorting and visitors with explicit signatures and effect ceilings. Captures remain excluded.

The [standard library guide](standard-library.md) lists the embedded modules that ship with the compiler and their bounded contracts.

Python-style procedures omit their return annotation or use `-> None`, bare `return`, and natural fallthrough; ordinary calls may stand alone only when returning unit. See [unit procedures](experiments/unit-procedures.md).

Statements may end at a newline, `}`, or end of file. Semicolons remain valid and separate statements written on one line. A new line ends a completed expression unless a binary operator continues it. Multiline expressions may place binary operators at either end of the line; parentheses also allow multiline postfix calls and indexing. Use an explicit semicolon to end the previous statement when a following operator, such as unary minus, must not continue its expression. Module, import, export, and unbraced type declarations follow the same newline rule. The formatter preserves line boundaries.

`()` is an alternative spelling for the unit type and unit value. `return` followed by a newline or closing brace returns unit. Postfix `expression?` propagates a failed result to the caller, with postfix precedence. Calls and parameter lists accept trailing commas.

[Checked legacy migration](experiments/migration.md) rewrites brace-syntax sources into the canonical Python surface and reports every construct without a Python spelling.
