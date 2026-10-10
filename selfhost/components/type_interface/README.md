# Selka type/interface batch producer

This component owns the whole-project signature checking pass formerly executed
by `Index.checkSignatures`, including its type/name resolution, generic bounds,
structural declaration checks and exported-interface visibility decisions. It
receives raw projected AST catalogs and already-indexed module facts. It builds
its own traversal and lookup indexes; the host supplies no resolved types or
precomputed semantic worklist. One request checks the complete indexed project.

The package is `type-interface`, selected with `MYLANG_TYPE_INTERFACE_MODE`.
Reference remains the default; shadow compares the complete result, and component
adopts it without executing the native signature checker. Dynamic body checking,
concrete generic specialization, effect inference and contract rendering remain
separate native consumers. No name lookup starts another process.

[WIRE.md](WIRE.md) is the normative protocol/schema 1 contract. The entrypoint
accepts `--exchange FILE` for the standard correlated 64-byte `SLKTIF01` envelope,
or `--request FILE` for an unframed `SLKTYI01` payload. Replies are `SLKTYR01`.
Source diagnostics are binary failure outcomes and exit 0. Malformed transport,
profile limits and I/O failures return exit 2 without binary output. There is no
source reparsing or fallback. The lexer closure is used only to normalize a
short qualified type name exactly as the native resolver does.

The limits are 4096 modules; 1 MiB source per module and 8 MiB aggregate source;
65536 aggregate symbols, declaration rows, type rows, nested syntax rows/edges,
imports and successful resolution receipts; 4096 imports per module; 16 KiB paths
per module; 8 MiB aggregate non-source strings; and 64 MiB complete framed
requests/replies. Recursive type depth includes the final leaf and is limited to
256. Admission counts precede decoded list allocation and index construction;
cycles and oversized catalogs fail closed before signature traversal. Generated
lookup keys use a private copy of the declaration primitive with an 8 MiB byte
budget per sorted index, while source and query lengths remain bounded to 1 MiB. Receipt
string storage is separately bounded to 8 MiB before append.

`checking.my` preserves project order and native declaration order: records,
variants, aliases, domains, constraints, functions. Every nominal/function generic
list is checked even when its declaration is private. Type-expression indexes
retain insertion IDs and each caller's native precedence. Successful resolution
receipts preserve repetitions and canonical facade origins; import flags retain
all input true flags and use the first matching alias or full module name.
Failures preserve native sites and related sites. Generic sink conversions
intentionally strip related sites, matching the existing interface layer.

Two subtle rules are deliberate: function-bound `default_copy` counts as an
explicit contract but does not independently make structural fields copyable;
constraint-subject `parameterCopy` does include that default. Repeating explicit
`copy` after a default does not duplicate the builtin list, because the native
builtin duplicate detector starts with a separate empty local set.

Pure tests cover ordering, visibility, canonical receipts/import usage, builtin
and nominal arity, generic constructors, private-template validation, structural
copy rules, transformed bound diagnostics, qualified names, malformed ordering
and codec frames, cycles and the exact 256/257 depth boundary. Qualification uses
the existing receipt-verified component-v1 seed, unchanged pins, build admission,
private disk scratch/local Zig cache, and release fact/leak checks. Installed
workflow parity and raw framing qualification are recorded by the separate
`run_type_interface_qualification.py` driver. No performance or default-adoption
claim is made here.

Type-expression rows require a nonempty parent span. Each child must be contained
within that parent and differ from it; a zero-length leaf at either boundary is
allowed. The nested budget counts scalar suffix bases, callback results/failures,
array elements/indexes, application constructor names and each constraint subject
in addition to list rows. `profile_tests.my` admits exactly 65536 nested edges and
rejects one additional scalar edge. That root is qualified with an explicit
100-million-step test budget; ordinary tests retain their default budget.
