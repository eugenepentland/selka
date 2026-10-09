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
| Values | `int`, binary64 `float`, booleans, managed Unicode strings/dictionaries/lists, byte literals, value records, checked results and optional values, domains/arrays, scalar and literal `str`/`bytes` constants and transparent aliases | [constants](module-constants.md), [aliases](type-aliases.md); [bounded scalar source evaluation](source-evaluation.md) |
| Control flow | Indented if/elif/else, while, foreach/enumerate/range (with an optional step), break/continue and match/case | [range iteration](range-iteration.md), [stepped ranges](range-iteration.md#stepped-ranges), [matching a variant](match-expressions.md); conservative outer ownership on loop exits |
| Python expressions | Chained comparisons, `str`/`bytes` ordering, `*` repetition of text and lists, `round(x, n)`, and CPython format specifications in `f"{value:spec}"` | [operators Python has](python-syntax.md#operators-python-has), [ordering and repetition](text.md#ordering-and-repetition), [format specifications](text.md#format-specifications); `round` breaks ties away from zero (a declared divergence); `**` stays rejected |
| Generics | Functions and nominal records/unions/results/enums; structural field/operation contracts and const length parameters | [structural contracts](../examples/structural-constraints.my); [inferred call type arguments](generic-inference.md) |
| Managed memory | Value semantics: lists, dictionaries, sets and byte buffers are independent values; one-count reference counting with copy-on-write releases each value when its last owner goes away; no collector and no runtime choice | [Value semantics](value-semantics.md), [releasing memory](managed-memory.md#releasing-memory); `class` and builtin `Cell` are rejected |
| Managed arenas | Retired: `with arena():` is rejected with `E_ARENA_REMOVED`; `mylang fix` removes the line and dedents its body | [Retired arenas](managed-memory.md#retired-arenas) records the retirement |
| Managed bytes | Immutable reference-counted byte strings with Python indexing, slicing, membership, split/join and text/hex conversions | [Managed byte strings](bytes.md); byte strings are rejected at JSON and C boundaries like `str` |
| Ordinary I/O | `Stream.print` with Python rendering and an `output` effect; `with open(...)`, handle methods and whole-path file helpers over granted directories | [printing, files and authority](io.md) |
| Program boundary | `main(args: str[], ...)` receives guest arguments after `--` from `run`/`build --run` or after `argv[0]` from an installed executable; an `err: Stream` parameter writes diagnostics; explicit `Environment` access and `main -> int fails str` are supported | [arguments](io.md#arguments); [exit results](io.md#what-mylang-run-prints-and-returns); a synthetic program name is never placed in the list |
| Resources | External resource owners, explicit completion and deterministic cleanup | [source resources](experiments/source-resources.md) and [resource reads and writes](experiments/resource-io.md), with runnable [`examples/resources.my`](../examples/resources.my) and [`examples/resource-io.my`](../examples/resource-io.my); no ambient operating-system authority |
| Authority | Explicit host capabilities and transitive effect ceilings; `mylang run` grants them all, and `--restrict` plus `--allow-*` withholds and narrows them | [capability effects](effects.md); [command-line grants](io.md#capabilities); [scoped directory/endpoint grants](experiments/scoped-providers.md) |
| Modules | Path-based disk imports, `public` declarations, nominal identity and embedded standard modules | [domain codecs](../examples/domain-codecs/main.my); [local locked package roots](experiments/local-packages.md); no network version resolver |
| Standard library | Fourteen embedded modules over managed types: `math`, `strings`, `sort`, `path`, `hex`, `base64`, `byte_builder`, `json`, `pool`, `network`, `random`, `time`, `filesystem`, `environment` | [standard library](standard-library.md); no transcendental functions, generic sorting uses an explicit key callback; filesystem and network operations require capabilities |
| Data interchange | Typed JSON codecs for exported types (`schema-project`, `mylang test --cases`), and managed byte strings | [managed byte strings](bytes.md); `bytes` is not a Unicode string type; guest-source JSON operations were removed with the explicit storage tier |
| Development | Independent function diagnostics, navigation, parse-only declaration listing, formatting, syntax/exact-verdict/function-body caches, symbolic-template and concrete-specialization reuse, receipt-first native-test result and preparation reuse, affected verification | [navigation](experiments/navigation-client.md); [declaration listing](experiments/list-declarations.md) reports kinds and byte ranges without checking; [checked-body and specialization reuse](tooling/caches.md#persistent-checked-body-store) keeps fresh global effect/mutation checks and conservative fallbacks; [guest tests](tooling/guest-tests.md#reusing-unaffected-results) reuse receipts and a reduced preparation graph |
| Documentation | Every fenced `mylang` example in README, SPEC and docs is run, type-checked or explicitly skipped by the default test gate | [executable documentation](experiments/doc-examples.md); directives pin expected output, expected diagnostics and explicit skips |
| Tests | Exported test_ function discovery, typed expected values, filters and explicit skips | [guest test workflow](experiments/guest-tests.md); deterministic arguments and isolated source-provider fixtures |
| Execution | Native code is the only runtime: the compiler lowers to Core IR, emits LLVM and links with the C runtime. Builds are debug by default (one LLVM unit per module); `--release` optimizes the whole program as one unit. `mylang build` writes an executable; `mylang run`, `run-project` and `test` build one and execute it in a child process; `mylang dump-ir` prints the Core IR | [native builds](tooling/native-build.md), [performance](performance.md#build-for-speed); [direct C imports](c-ffi.md) and [guest tests](tooling/guest-tests.md) describe the native route |

The detailed [SPEC](../SPEC.md) and focused experiment references describe
operation contracts and their tests. [legacy/semantics.md](legacy/semantics.md) preserves
historical checkpoints and must not be read as one current feature inventory.

Absent features include capturing closures, guest shared-memory threads, arbitrary
stored reference lifetimes and unrestricted source compile-time execution. The [feature audit](audits/feature-completeness-2026-09-07.md) proposes
extensions; their presence in that backlog does not claim implementation.

Memory safety combines automatic reclamation (one-count reference counting) with
the runtime's checked pool handles and generations. The language has no guest spawn syntax. The native runtime can use a bounded
worker pool for compiler-selected collection work; independent guest programs and
tests can also run in separate processes.
`noalloc` restricts managed guest allocation, not all compiler/runtime/host allocation.
C functions called through `extern func` are trusted implementations of their
declared signatures. These limits are
part of the current model, not guarantees supplied by a future thread system.

`float` provides decimal literals and ordinary numeric operators over IEEE binary64; the standard `math` module adds classification, rounding, roots and integer helpers, and the raw `f64_*` spellings over `u64` representations are rejected with `E_REMOVED_SPELLING`. See [floating-point.md](floating-point.md).

`str` and `bytes` constants require matching literals and their reads contribute `managed_allocation`; see [module-constants.md](module-constants.md#string-and-byte-literal-constants).

Scalar constants may call bounded nongeneric source functions with scalar locals and control flow; see [source-evaluation.md](source-evaluation.md).

A program started by `mylang run`, `build --run` or `mylang test` runs under a byte ceiling; see [runtime budgets](tooling/runtime-budgets.md). Typed holes are an experimental agent-facing tool; comparative productivity evidence remains pending. Sampled named laws are an experiment outside mylang (`experiments/guest-laws/`, see [named executable laws](experiments/guest-laws.md)).

Run `python3 tests/feature_surface.py --compiler zig-out/bin/mylang --output receipt.json`
to execute the documented feature-surface examples and verify explicit
unsupported syntax and unresolved-hole rejection. The receipt pins the executable,
feature report and case source hashes; it complements the broader acceptance suite.
Generic functions and nominal declarations support explicit `const N:u64` length parameters; see [const-length-generics.md](const-length-generics.md).

[Typed noncapturing callbacks](experiments/callbacks.md) support reusable sorting and visitors with explicit signatures and effect ceilings. Captures remain excluded.

The [standard library guide](standard-library.md) lists the fourteen embedded modules that ship with the compiler, their signatures and their bounded contracts. They are ordinary guest source over growable arrays (`T[]`), `dict`, `str`, `bytes`, optional values (`T?`) and checked results, so nothing in them needs an allocator argument or a storage annotation.

Procedures omit their return annotation or use `-> Unit`, bare `return`, and natural fallthrough; ordinary calls may stand alone only when returning unit. See [unit procedures](functions.md#unit-procedures).

Statements end at newlines, at the dedent that closes a suite, or at end of file.
Semicolon-separated statements are rejected. Parentheses and other delimiters allow
multiline expressions, calls and indexing. Module identity comes from file paths;
redundant source `module` headers are rejected. The `module` line in a generated
`.api` interface is metadata, not source syntax.

`Unit` spells the unit type and `()` its value; `None` is an absent optional value.
A bare `return` returns unit. A fallible function declares `-> T fails E`, returns
its successful value with `return`, and returns an error with `fail`. Boundary
`try` propagates a failure; postfix expression `?` is rejected, while the type
suffix `T?` spells an optional value. Calls and parameter lists accept trailing commas.

The brace dialect this language grew out of was removed on 2026-09-13, together with the `migrate` tool that converted it; [the removed-features index](legacy/README.md) records what each spelling became.

The bytecode interpreter was removed on 2026-09-14, and the QBE back end, the tracing collector, managed arenas, legacy sharing and host functions (`host func`, `mylang invoke`) were retired with the switch to the new compiler core in October 2026. `mylang run`, `run-project` and `test` build a program before executing it, and the retired commands (`invoke`, `emit-qbe`, `dump-bytecode` and others) are refused with status 2 and a line naming what replaces them.

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
- [Managed application collections](managed-memory.md), [value semantics](value-semantics.md)
- [Generic functions and types](generics.md), [generic call inference](generic-inference.md), [constant length parameters](const-length-generics.md)
- [Explicit integer operations](integer-operations.md), [binary64 floating point](floating-point.md)
- [Modules, imports and exports](modules.md), [immutable constants](module-constants.md), [transparent type aliases](type-aliases.md)
- [Capabilities and effects](effects.md), [printing, files and command-line authority](io.md)
- [Integer range iteration](range-iteration.md), [structured loop exits](structured-loop-exits.md), [matching a variant](match-expressions.md)
- [Nominal scalar domains and private members](domains.md)
- [Standard library](standard-library.md), [time and randomness](standard-time-random.md)
- [Typed JSON boundaries](typed-json.md), [typed holes](typed-holes.md)
- [Bounded source evaluation in constants](source-evaluation.md), [checking independent function faults](diagnostic-recovery.md)
- [Direct C imports](c-ffi.md)

Tooling:

- [Native builds](tooling/native-build.md), [guest tests](tooling/guest-tests.md)
- [Fixes and migrations](tooling/fix.md): `mylang fix` and the `fix` field of `diagnostic-v1`
- [Compiler caches](tooling/caches.md), [source navigation](tooling/navigation.md)
- [Agent-facing inspection](tooling/agent-tools.md), [focused declaration context](tooling/agent-context.md), [documentation gates](tooling/documentation-gate.md)
- [Local packages](tooling/packages.md)
- [Runtime budgets](tooling/runtime-budgets.md)
- [Command phase timings](tooling/timings.md)
