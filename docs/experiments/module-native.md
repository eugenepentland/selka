# Native execution of scalar module projects

`emit-project-c` checks the complete reachable module program and emits C through the
existing scalar native backend. The native builder accepts an explicit `--project`:

```sh
zig build
zig-out/bin/mylang emit-project-c examples/module-duplicates/main.my
python3 scripts/native.py examples/module-duplicates/main.my --project --mode ReleaseFast -o zig-out/module-example
zig-out/module-example
```

The example returns 46, matching the VM. The builder verifies Guardian's exact pinned
Zig snapshot before emission/compilation. `Debug` and `ReleaseFast` select C O0 and O2
respectively. Omitting `--project` preserves the single-file builder behavior.

Module name/privacy/type/ownership/effect checks run before native generation. The
selected entry main, qualified function identities, resolved calls, scalar types,
and original file locations flow through the same checked bytecode as the VM. The
native executable retains step/frame options and per-instruction source paths;
traces identify both a failing dependency and its callers. These are executable
programs with direct C labels and explicit frames, not a bytecode interpreter wrapper.

The supported operations include scalars, domains, enums,
[ordinary aggregates and variants](native-aggregates.md), and
[ordinary-value references and slices](native-references.md).
Module packaging does not add native allocator, resource, pool, or arena operations. Unsupported signatures or instructions, including those in
uncalled dependencies, reject with E_NATIVE_FEATURE before any generated C reaches
stdout. A private cross-file call rejects at semantic checking. The builder preserves
an existing output when frontend rejection prevents invoking the C compiler. Import
policy remains a separate, explicitly requested check.

The native parity harness now includes five multi-file fixtures: nested calls with
same-spelled helpers in separate modules, overflow through a facade/dependency,
recursive calls, short-circuit avoidance of a trapping dependency, and integer-width
conversion through an alias. At C O0 and O2 with undefined-behavior sanitization,
68 executed comparisons cover ordinary execution, step/frame limits, and every step
budget through completion of the nested-call case. Comparisons include successful
stdout or the trap code, original path/line/column, and normalized call-frame paths
and function identities. The public builder is executed in both modes; unsupported
uncalled dependencies and private calls are rejection fixtures.

This supplements the existing 23 scalar fixtures and 182 comparisons rather than
replacing them. Zig tests also cover deterministic repeated project emission,
exhaustive allocation failures through loading/checking/lowering/emission, actual
CLI errors, and absence of partial C output on rejection. No performance or full
language-native support claim follows from this scalar parity evidence.

Broader module/candidate corpus and scaling review, generics, compile-time/schema/
incremental work, and wider native operations remain on the roadmap. Every added
native operation needs executable VM/native parity fixtures.
