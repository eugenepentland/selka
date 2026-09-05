# Module source mapping and AST relocation

Track M now has the source/AST storage bridge needed by cross-file semantic
checking. `Source.initMapped` copies unchanged source bytes into one offset space
and retains an origin record per input. A separator gives each file its own EOF
offset, including adjacent empty files. Origin metadata borrows original Sources;
those sources must outlive the mapped Source. All compilation storage normally
belongs to a request arena. Nested mapped inputs and empty source lists reject.

`mappedSpan` checks a local span and relocates it; `originalSpan` checks the reverse
mapping and rejects spans crossing file boundaries. `locate` resolves the original
path, line, column, and source line. Source text is preserved exactly, including
CRLF and tabs. `physicalLocation` addresses the combined buffer only, for metrics
whose line arrays are indexed in that space. This is a source map, not source-name
rewriting, an import resolver, or a way to merge module namespaces implicitly.

`project_syntax.build` consumes the parsed interface index and combines its AST
tables. It relocates all source spans, expression IDs, statement IDs, and nested
slices; preserves each function's owning module and each module's node/statement
range; and retains declaration source provenance. Original ASTs are unchanged.
The relocation walker covers every AST field through the pinned Zig snapshot's
reflection API; unsupported field representations fail at compiler build time.
Output belongs to the project arena. A later semantic consumer must use the
interface resolver in each declaration's original module context. Passing these
tables directly to the old single-file name resolver does not implement modules.

Diagnostics now use each resolved location's path for primary errors, related
notes, and VM call traces. Mapped bytecode dumps include file paths. Quality reports
use original paths while line metrics use combined-buffer indices. Duplicate report
locations also use original paths. Native scalar output records a path per
instruction, preserving caller/callee file attribution in native trap traces.
Single-file output conventions and the existing scalar parity contract remain.
These location changes do not yet add module-aware quality roots or nominal
cross-module duplicate identities.

Acceptance covers every offset and EOF in empty/CRLF/tab examples, checked forward
and reverse span mapping, cross-file related diagnostics, parser-to-VM trap traces,
bytecode locations, unequal file lengths in quality metrics, module AST spelling
and relocated call/body IDs, and exhaustive allocation failure for source/AST
mapping and rendering. Scalar native C was also compiled with pinned Zig at O2
with undefined-behavior sanitization: division by zero in `lib/helper.my` reported
that path and the caller in `entry.my`. This probe uses one scalar program's source
fragments to test provenance; it is not evidence of module name resolution.

[Cross-file checking/execution](module-execution.md) now connects the relocated
declarations to the type catalog and function checker using interface identities
and original module context. Optional dependency-direction policy, generics, schema
and incremental work, native expansion, and other unfinished roadmap work remain pending.
