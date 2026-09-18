# Current language reference

Start with [the language guide](python-syntax.md). This index links the advanced APIs and the pages that describe them.

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
| Values | `int`, binary64 `float`, booleans, managed Unicode strings/dictionaries/lists, byte literals, value records, checked Result/Option, `Cell[T]`, domains/arrays, scalar and literal `str`/`bytes` constants and transparent aliases | [constants](module-constants.md), [aliases](type-aliases.md); [bounded scalar source evaluation](source-evaluation.md) |
| Control flow | Indented if/elif/else, while, foreach/enumerate/range, break/continue and match/case | [range iteration](range-iteration.md), [matching a variant](match-expressions.md); conservative outer ownership on loop exits |
| Generics | Functions and nominal records/unions/results/enums; structural field/operation contracts and const length parameters | [structural contracts](../examples/structural-constraints.my); [inferred call type arguments](generic-inference.md) |
| Managed allocation | Shared growing lists and dictionaries, immutable strings, nonmoving tracing GC and cycle reclamation | [Managed memory](managed-memory.md); managed graph host/native boundaries remain excluded |
| Managed arenas | `with arena() as name:` region blocks over ordinary managed objects, bulk release, `escape` copy-out, static and runtime escape checks | [Managed arenas](arenas.md); [runnable example](../examples/arena-managed/main.my); QBE native |
| Managed bytes | Immutable GC byte strings with Python indexing, slicing, membership, split/join and text/hex conversions | [Managed byte strings](bytes.md); byte strings are rejected at JSON and host boundaries like `str` |
| Ordinary I/O | `print` with Python rendering and an `output` effect; `with open(...)`, handle methods and whole-path file helpers over granted directories | [printing, files and authority](io.md); QBE native |
| Program boundary | `main(args: list[str], ...)` receives guest arguments after `--` from `run`/`build --run` or after `argv[0]` from an installed executable; `eprint` writes diagnostics; explicit `Environment` access and `main -> Result[int, str]` are supported | [arguments](io.md#arguments); [exit results](io.md#what-mylang-run-prints-and-returns); a synthetic program name is never placed in the list |
| Resources | External resource owners, explicit completion and deterministic cleanup | [source resources](experiments/source-resources.md) and [resource reads and writes](experiments/resource-io.md), with runnable [`examples/resources.my`](../examples/resources.my) and [`examples/resource-io.my`](../examples/resource-io.my); no ambient operating-system authority |
| Authority | Explicit host capabilities and transitive effect ceilings; `mylang run` grants them all, and `--restrict` plus `--allow-*` withholds and narrows them | [capability effects](effects.md); [command-line grants](io.md#capabilities); [byte runner scoped directory/endpoint grants](experiments/scoped-providers.md) |
| Modules | Disk imports, explicit exports, nominal identity and embedded standard modules | [domain codecs](../examples/domain-codecs/main.my); [local locked package roots](experiments/local-packages.md); no network version resolver |
| Standard library | Ten embedded Python-syntax modules over managed types: `math`, `strings`, `sort`, `path`, `hex`, `base64`, `json`, `pool`, `random`, `time` | [standard library](standard-library.md); no transcendental functions, no ordering contract for a generic sort, no filesystem or network module |
| Data interchange | Typed JSON codecs at the CLI and host boundary, and managed byte strings | [managed byte strings](bytes.md); `bytes` is not a Unicode string type; guest-source JSON operations were removed with the explicit storage tier |
| Development | Independent function diagnostics, navigation, parse-only declaration listing, formatting, syntax/exact-verdict/function-body caches, symbolic-template and concrete-specialization reuse, receipt-first native-test result and preparation reuse, affected verification | [navigation](experiments/navigation-client.md); [declaration listing](experiments/list-declarations.md) reports kinds and byte ranges without checking; [checked-body and specialization reuse](tooling/caches.md#persistent-checked-body-store) keeps fresh global effect/mutation checks and conservative fallbacks; [guest tests](tooling/guest-tests.md#reusing-unaffected-results) reuse receipts and a reduced preparation graph |
| Documentation | Every fenced `mylang` example in README, SPEC and docs is run, type-checked or explicitly skipped by the default test gate | [executable documentation](experiments/doc-examples.md); directives pin expected output, expected diagnostics and explicit skips |
| Tests | Exported test_ function discovery, typed expected values, filters and explicit skips | [guest test workflow](experiments/guest-tests.md); deterministic arguments and isolated source-provider fixtures |
| Byte application I/O | Scalar compatibility and bounded copied 256-byte blocks, configurable input/output/execution budgets | [bulk I/O](byte-io-bulk.md); output publishes only on successful guest exit |
| Execution | QBE native code is the only runtime: `mylang build` writes an executable, `mylang run`, `run-project` and `test` build one and execute it in a child process, and `emit-qbe`/`emit-project-qbe` stop at QBE IL | [native experiments](experiments/roadmap.md); [direct C imports](c-ffi.md) and [guest tests](experiments/guest-tests.md) describe the native route |

The detailed [SPEC](../SPEC.md) and focused experiment references describe
operation contracts and their tests. [legacy/semantics.md](legacy/semantics.md) preserves
historical checkpoints and must not be read as one current feature inventory.

Absent features include capturing closures, guest shared-memory threads, arbitrary
stored reference lifetimes and unrestricted source compile-time execution. The [feature audit](audits/feature-completeness-2026-09-07.md) proposes
extensions; their presence in that backlog does not claim implementation.

Memory safety combines the nonmoving tracing collector with the runtime's checked
handles, generations and leases. The guest runtime is single-threaded and the language
has no spawn syntax: parallelism is one guest process per task, arranged by the host.
`noalloc` restricts managed guest allocation, not all compiler/runtime/host allocation.
Host callbacks are trusted implementations of documented contracts. These limits are
part of the current model, not guarantees supplied by a future thread system.

`float` provides decimal literals and ordinary numeric operators over IEEE binary64; the standard `math` module adds classification, rounding, roots and integer helpers, and the raw `f64_*` intrinsics over `u64` representations remain available. See [floating-point.md](floating-point.md).

`str` and `bytes` constants require matching literals and their reads contribute `managed_allocation`; see [module-constants.md](module-constants.md#string-and-byte-literal-constants).

Scalar constants may call bounded nongeneric source functions with scalar locals and control flow; see [source-evaluation.md](source-evaluation.md).

Every process that runs guest code runs under a byte ceiling; see [runtime budgets](tooling/runtime-budgets.md). Typed holes and named executable laws are experimental agent-facing tools; comparative productivity evidence remains pending.

Run `python3 tests/feature_surface.py --compiler zig-out/bin/mylang --output receipt.json`
to execute the documented feature-surface examples and verify explicit
unsupported syntax and unresolved-hole rejection. The receipt pins the executable,
feature report and case source hashes; it complements the broader acceptance suite.
Generic functions and nominal declarations support explicit `const N:u64` length parameters; see [const-length-generics.md](const-length-generics.md).

[Typed noncapturing callbacks](experiments/callbacks.md) support reusable sorting and visitors with explicit signatures and effect ceilings. Captures remain excluded.

The [standard library guide](standard-library.md) lists the ten embedded modules that ship with the compiler, their signatures and their bounded contracts. They are ordinary guest source over `list`, `dict`, `str`, `bytes`, `Option` and `Result`, so nothing in them needs an allocator argument or a storage annotation.

Python-style procedures omit their return annotation or use `-> None`, bare `return`, and natural fallthrough; ordinary calls may stand alone only when returning unit. See [unit procedures](functions.md#unit-procedures).

A statement ends at its newline, at the dedent that closes its suite, or at end of file. A `;` separates two statements written on one line, as it does in Python. A new line ends a completed expression; a delimiter continues it, so parentheses also allow multiline calls and indexing. Use an explicit `;` to end the previous statement when a following operator, such as unary minus, must not continue its expression. Module, import, export and type declarations follow the same newline rule.

`None` and `()` both spell the unit type and unit value. `return` followed by a newline or a dedent returns unit. Postfix `expression?` propagates a failed result to the caller, with postfix precedence. Calls and parameter lists accept trailing commas.

The brace dialect this language grew out of was removed on 2026-09-13, together with the `migrate` tool that converted it; [the removed-features index](legacy/README.md) records what each spelling became.

The bytecode interpreter was removed on 2026-09-14. QBE native code is the only runtime, so `mylang run`, `run-project` and `test` build a program before executing it, and the `eval-project`, `check-value-project` and `invoke-project` commands went with the interpreter. Bytecode remains the compiler's internal IR that QBE consumes, and `dump-bytecode` still prints it.

## Feature reference pages

Every implemented feature has a section with a runnable example on one of the
pages below, and `mylang doc-coverage` fails the build when one does not; see
[documentation gates](tooling/documentation-gate.md). `mylang --features` reports
the same inventory with each feature's one-line summary and the pointer at its
section.

Language surface:

- [The language](python-syntax.md) — the syntax, end to end
- [Statements and bindings](statements.md), [functions and calls](functions.md), [docstrings](functions.md#docstrings)
- [Records, unions and enums](records-and-unions.md), [results and options](results-and-options.md)
- [Text and strings](text.md), [managed byte strings](bytes.md)
- [Managed application collections](managed-memory.md), [managed arenas](arenas.md)
- [Generic functions and types](generics.md), [generic call inference](generic-inference.md), [constant length parameters](const-length-generics.md)
- [Explicit integer operations](integer-operations.md), [binary64 floating point](floating-point.md)
- [Modules, imports and exports](modules.md), [immutable constants](module-constants.md), [transparent type aliases](type-aliases.md)
- [Capabilities and effects](effects.md), [printing, files and command-line authority](io.md)
- [Integer range iteration](range-iteration.md), [structured loop exits](structured-loop-exits.md), [matching a variant](match-expressions.md)
- [Nominal scalar domains and private members](domains.md)
- [Standard library](standard-library.md), [time and randomness](standard-time-random.md)
- [Typed JSON boundaries](typed-json.md), [typed holes](typed-holes.md)
- [Bounded source evaluation in constants](source-evaluation.md), [checking independent function faults](diagnostic-recovery.md)
- [Direct C imports](c-ffi.md), [bounded byte block I/O](byte-io-bulk.md)

Tooling:

- [Native builds](tooling/native-build.md), [guest tests](tooling/guest-tests.md)
- [Compiler caches](tooling/caches.md), [source navigation](tooling/navigation.md)
- [Agent-facing inspection](tooling/agent-tools.md), [documentation gates](tooling/documentation-gate.md)
- [Local packages](tooling/packages.md)
- [The byte runner host](tooling/byte-runner.md), [runtime budgets](tooling/runtime-budgets.md)
- [Command phase timings](tooling/timings.md)
