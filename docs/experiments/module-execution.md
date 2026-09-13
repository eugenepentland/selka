# Cross-file type checking and VM execution

Track M now checks and runs module programs:

```sh
zig build run -- check-project examples/modules/main.my
zig build run -- run-project examples/modules/main.my
```

The example returns 12 through an imported Distance domain factory/accessor. The
same import graph, export lists, interface visibility, and mapped ASTs used by the
discovery commands feed the ordinary type/ownership/effect checker. Names resolve
in the module containing each source span, including callee parameter/result types.
Declaration identities are qualified by logical module name; identical spelling in
two modules does not make nominal types interchangeable. Direct import aliases
supply qualified references. Private module declarations and domain-private methods
are checked at body references as well as in exported signatures.

All discovered modules are checked, including uncalled private functions. Only the
entry module's main is the execution entry; dependencies may have their own main
without replacing it. The existing capability-only main parameter rules apply.
Shadowing checks include the local module's declarations/import aliases; private
names in dependencies do not occupy the caller's local namespace. No global search
or transitive import fallback supplies missing references.

Record/domain/variant/array/table/buffer/pool types use the same catalog and layout
checks as single-file programs, with module-aware name lookup. The function checker
uses the same argument/return, borrowing, ownership, result-obligation, arena-lifetime,
and effect passes. Interface signature exposure rules remain deliberately explicit:
public signatures may mention only exported named types. Imported references retain
the original module's nominal identity across parameters and returns.

`run-project` supports `--max-steps`, `--max-frames`, and `--memory=general|arena` with
the same VM limits as run. `check-project` accepts no execution flags. Successful
checking exits 0; running writes the i64 result and exits 0. Source errors and traps
exit 1; usage/host errors exit 2. Warnings and diagnostics use original file paths.
The single-file commands retain their grammar and behavior. Header/interface-only
commands continue to identify their narrower checks accurately.

The embedding `project_compile.Compilation` owns no separate arena: its syntax,
diagnostics, checked program, and bytecode belong to the interface index's project.
Keep the project and interface index alive until use ends. `init`, `check`, and
`emit` retain the mapped Source so diagnostics are renderable even if checking fails.
No text substitution or flattening of module namespaces is used.

Acceptance includes shared domain factories through private helpers, nominal
mismatch rejection, imported private function/type rejection, same-module private
method rules, local shadowing, dependency main isolation, uncalled invalid bodies,
recursive layout rejection, cross-file noalloc and result obligations, returned
slice references with caller mutation/snapshot preservation, real CLI execution,
cross-file trap traces, VM limits, and exhaustive allocation failures through
checking/lowering/executing a shared-domain program. Existing single-file and scalar
native parity fixtures remain regression coverage.

[Optional dependency-direction policy](import-policy.md) is implemented as a
separate check. Broader module corpus/scaling review remains. [Module duplicates](module-duplicates.md) and [quality/export roots](module-quality.md)
are implemented. [Module formatting](module-formatting.md) and [scalar native project parity](../legacy/experiments/module-native.md)
are also implemented. Broader native operations and schema/incremental identities
remain in their respective tracks. Generics, schema/compile-time/incremental work, and broader
native operations remain pending. This milestone does not complete the full roadmap.

[Default-limit graph and tooling acceptance](module-scaling.md) now covers deep
call chains and shared dense imports through checking, execution, and reports.
