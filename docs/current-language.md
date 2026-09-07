# Current language reference

The installed executable's `--features` JSON report identifies the binary by
SHA-256, the pinned Zig toolchain, supported features, exclusions and backend
coverage. `language-features-v1` versions the report format; the language remains
experimental version 0.1.0. A feature being implemented is distinct from a
particular build passing its tests. Run the acceptance suite for the binary you
intend to use; historical counts are not current verification receipts.

| Area | Supported surface | Executable example / restriction |
| --- | --- | --- |
| Values | Fixed-width integers, booleans, byte literals, records/domains/arrays, unions/results, standard Unit, scalar constants and transparent aliases | [constants](module-constants.md), [aliases](type-aliases.md); [bounded scalar source evaluation](source-evaluation.md) |
| Control flow | While, structured break/continue, integer range iteration and value-producing matches | [range iteration](range-iteration.md), [match expressions](match-expressions.md); conservative outer ownership on loop exits |
| Generics | Functions and nominal records/unions/results/enums/buffers/pools; structural field/operation contracts | [structural contracts](../examples/structural-constraints.my); explicit call type arguments |
| Ownership | Move-only buffers, pools, resource owners, deterministic cleanup and partial record moves | [buffers](../examples/buffers.my); elements cannot own backing or carry must-handle obligations |
| References | Lexical read/write borrows, slices and single-input-origin reference returns | [buffer views](../examples/buffer-views.my); whole-owner references and [checked disjoint splits](../examples/split-borrows.my); no stored reference fields |
| Regions | Explicit allocator capabilities, scoped arenas, reset with escape checks | [arenas](../examples/arenas.my); selected-field owner-return provenance; no general lifetime inference |
| Authority | Explicit host capabilities and transitive effect ceilings; resource attenuation | [effects](../examples/effects.my); [byte runner scoped directory/endpoint grants](experiments/scoped-providers.md) |
| Modules | Disk imports, explicit exports, nominal identity and embedded standard modules | [domain codecs](../examples/domain-codecs/main.my); [local locked package roots](experiments/local-packages.md); no network version resolver |
| Data interchange | Typed JSON codecs, checked ordinary-JSON accessors, byte/text helpers and bounded builders | [source JSON](../examples/source-json.my); byte slices are not a Unicode string type |
| Development | Independent function diagnostics, navigation, formatting, syntax/exact-verdict caches, affected verification | [navigation](experiments/navigation-client.md); edited programs recheck semantics |
| Tests | Exported test_ function discovery, typed expected values, filters and explicit skips | [guest test workflow](experiments/guest-tests.md); deterministic arguments and isolated source-provider fixtures |
| Byte application I/O | Scalar compatibility and bounded copied 256-byte blocks, configurable input/output/execution budgets | [bulk I/O](byte-io-bulk.md); output publishes only on successful guest exit |
| Execution | Typed bytecode VM; C emission/native embedding with host ABI and ordinary/typed/domain JSON | [native experiments](experiments/roadmap.md); [native host](experiments/native-host.md) and [JSON support](experiments/native-json.md) require their documented runtime integration |

The detailed [SPEC](../SPEC.md) and focused experiment references describe
operation contracts and their tests. [semantics.md](semantics.md) preserves
historical checkpoints and must not be read as one current feature inventory.

Absent features include builtin floating-point syntax, function values, guest threads, arbitrary
stored reference lifetimes and unrestricted source compile-time execution. The [feature audit](audits/feature-completeness-2026-09-07.md) proposes
extensions; their presence in that backlog does not claim implementation.

Memory safety combines static ownership/region checks with VM checked handles,
generations and leases. Each VM is single-threaded; [isolated process workers](experiments/workers.md) provide bounded parallel execution with copied typed messages. `noalloc` restricts guest
backing allocations, not all compiler/VM/host allocation. Host callbacks are
trusted implementations of documented contracts. These limits are part of the
current model, not guarantees supplied by a future backend or thread system.

`std_math::F64` provides named IEEE binary64 arithmetic, basic math, checked integer conversion and exact bit codecs; see [floating-point.md](floating-point.md).

Scalar constants may call bounded nongeneric source functions with scalar locals and control flow; see [source-evaluation.md](source-evaluation.md).

[Runtime memory reports](experiments/runtime-memory-budgets.md) distinguish logical slots, guest backing and bookkeeping. Typed holes, bounded VM traces, in-memory host replay and named executable laws are experimental agent-facing tools; comparative productivity evidence remains pending.

Run `python3 tests/feature_surface.py --compiler zig-out/bin/mylang --output receipt.json`
to execute the documented binary64/constant/split examples and verify explicit
unsupported syntax and unresolved-hole rejection. The receipt pins the executable,
feature report and case source hashes; it complements the broader acceptance suite.
