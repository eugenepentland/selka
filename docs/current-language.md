# Current language reference

The installed executable's `--features` JSON report identifies the binary by
SHA-256, the pinned Zig toolchain, supported features, exclusions and backend
coverage. `language-features-v1` versions the report format; the language remains
experimental version 0.1.0. A feature being implemented is distinct from a
particular build passing its tests. Run the acceptance suite for the binary you
intend to use; historical counts are not current verification receipts.

| Area | Supported surface | Executable example / restriction |
| --- | --- | --- |
| Values | Fixed-width integers, booleans, byte literals, records/domains/arrays, unions/results, standard Unit, scalar constants and transparent aliases | [constants](module-constants.md), [aliases](type-aliases.md); no general compile-time execution |
| Control flow | While, structured break/continue, integer range iteration and value-producing matches | [range iteration](range-iteration.md), [match expressions](match-expressions.md); conservative outer ownership on loop exits |
| Generics | Functions and nominal records/unions/results/enums/buffers/pools; structural field/operation contracts | [structural contracts](../examples/structural-constraints.my); explicit call type arguments |
| Ownership | Move-only buffers, pools, resource owners, deterministic cleanup and partial record moves | [buffers](../examples/buffers.my); elements cannot own backing or carry must-handle obligations |
| References | Lexical read/write borrows, slices and single-input-origin reference returns | [buffer views](../examples/buffer-views.my); whole-allocation conflict checks; no stored reference fields |
| Regions | Explicit allocator capabilities, scoped arenas, reset with escape checks | [arenas](../examples/arenas.my); no general lifetime inference |
| Authority | Explicit host capabilities and transitive effect ceilings; resource attenuation | [effects](../examples/effects.my); ordinary CLI grants no filesystem/network provider |
| Modules | Disk imports, explicit exports, nominal identity and embedded standard modules | [domain codecs](../examples/domain-codecs/main.my); no package version resolver |
| Data interchange | Typed JSON codecs, plain JSON document parsing, std_json and byte-oriented std_text | [source JSON](../examples/source-json.my); byte slices are not a Unicode string type |
| Development | Independent function diagnostics, navigation, formatting, syntax/exact-verdict caches, affected verification | [navigation](experiments/navigation-client.md); edited programs recheck semantics |
| Tests | Exported test_ function discovery, typed expected values, filters and explicit skips | [guest test workflow](experiments/guest-tests.md); deterministic arguments, no custom provider injection |
| Byte application I/O | Scalar compatibility and bounded copied 256-byte blocks, configurable input/output/execution budgets | [bulk I/O](byte-io-bulk.md); output publishes only on successful guest exit |
| Execution | Typed bytecode VM; partial C emission/native embedding | [native experiments](experiments/roadmap.md); host declarations and plain JSON reject native emission |

The detailed [SPEC](../SPEC.md) and focused experiment references describe
operation contracts and their tests. [semantics.md](semantics.md) preserves
historical checkpoints and must not be read as one current feature inventory.

Absent features include builtin floating-point syntax, function values, guest threads, arbitrary
stored reference lifetimes, disjoint split borrows and general source compile-time
execution. The [feature audit](audits/feature-completeness-2026-09-07.md) proposes
extensions; their presence in that backlog does not claim implementation.

Memory safety combines static ownership/region checks with VM checked handles,
generations and leases. The VM is single-threaded. `noalloc` restricts guest
backing allocations, not all compiler/VM/host allocation. Host callbacks are
trusted implementations of documented contracts. These limits are part of the
current model, not guarantees supplied by a future backend or thread system.

`std_math::F64` provides named IEEE binary64 arithmetic, basic math, checked integer conversion and exact bit codecs; see [floating-point.md](floating-point.md).

Scalar constants may call bounded nongeneric source functions with scalar locals and control flow; see [source-evaluation.md](source-evaluation.md).
