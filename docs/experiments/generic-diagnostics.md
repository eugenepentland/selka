# Readable generic diagnostics and explicit instance metadata

Specialized functions now carry their ordered concrete type arguments in checked
metadata. Their display names include those types, such as `divide::<u8>` or
`units::id::<units::Box>`, instead of a `$` and discovery ordinal. Bytecode dumps,
VM/native stack traces and reports using checked function names inherit this
presentation.

The metadata retains nominal type identities; display names use the catalog's
qualified type names. A change that discovers another specialization first no
longer renames existing specializations. Display names are still diagnostic
text, not a serialized type identity or a substitute for the declaration/type
keys used by the specialization registry.

Module export/schema selection now checks the explicit type-argument metadata.
It does not infer internal status from punctuation in a function name. Ordinary
public wrappers stay available, while their concrete generic instances remain
implementation details. Direct public generic invocation is still unfinished.

Acceptance covers discovery-order changes, scalar and nominal names, qualified
module/nominal identities, explicit argument metadata, bytecode dumps, trap frames,
public schema exclusion and allocation failures through existing specialization
and module fixtures. Native parity verifies that readable names agree between
backends. This addresses the roadmap's understandable-diagnostics requirement;
broader generic operations, public tooling, native embedding and incremental
compilation requirements remain open.

Validation: all 586 core tests passed in Debug and ReleaseFast, all 60 CLI tests
passed, and native parity passed 2682 comparisons across 93 single-file and 16
module fixtures with -O0/-O2 and undefined-behavior sanitization. Guardian passed
all 88 checks with baselines disabled. Tests cover discovery-order independence,
qualified nominal names, dump/trace output, schema exclusion and allocation-failure
cleanup. This does not establish completion of direct generic public tooling or
the other unfinished roadmap tracks.
