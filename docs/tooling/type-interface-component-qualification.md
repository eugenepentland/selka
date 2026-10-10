# Type/interface component qualification

The `type-interface` package independently implements the whole-project signature
batch. Its raw projection contains parsed type declarations, generic bounds,
function signatures, module symbols and import metadata. It resolves names and
types without a native semantic worklist. Body checking, specialization, alias
contract rendering and effect inference remain native. Alias cycle failures from
later passes are not evidence that this batch detects cycles.

The installed driver compares reference, shadow and component modes with every
other producer in reference mode. Three additional enclosing workflows select
lexer, parser, declaration and signature producers together. The public default
remains reference. Installed commands run with an empty PATH; Python is only the
developer gate driver, never the compiler or component runtime.

The fixture corpus contains 27 cases: generic and nominal applications, public
aliases/domains, array/tuple/callback signatures, imported and re-exported named
constraints, implied structural copy, private nested type leakage, private bound
exposure, invalid arity and parameter constructors, unknown and wrong-kind
bounds, binder shadowing, qualifiers separated by whitespace or comments, and test-module private constraint access. Each expected diagnostic is checked against exact
reference status, stdout and diagnostic-v1 stderr, including related locations.
UTF-8 comments precede declarations to exercise byte locations. All six component entry sources also run through installed `check`. Successful cases
also compare deterministic interface listings.

There are 57 workflows and 114 component comparisons per matrix, or 228
comparisons when the normal gate repeats the matrix after a component-only source
edit. Thirty same-path warm deployment checks cover missing manifests/artifacts,
schema changes, digest corruption and authenticated wrong-protocol replacement.
Four live session checks mutate the same verified deployment after two successful
checks. Cache-enabled test receipts are separate from fact/leak qualification.

The transport suite uses one valid empty catalog module and 31 malformed frames,
counts, source/path/string bounds and module-order failures. Four pinned-Zig native
forged components echo correct correlation and package authentication, then return
invalid order, count, outcome or identity metadata. Both selected modes must
report host status 2, yielding eight hostile-result checks. Capture is bounded on
disk, with deadlines and an inherited-or-stricter 2 GiB external address-space
budget. These developer limits do not invent a production memory guarantee.

The gate verifies a coordinator seed receipt before invoking pure tests or the
installed workflows. Pure tests are discovered nonempty and run normally and with
release/fact verification and leak checking. All six installed package manifests
and artifact hashes are required. The private coordinator edit must change the
signature package receipt and artifact while preserving the host and five other
packages. Reports contain identities, every selected workflow, zero failed and
zero skipped totals; no unsupported selection is silently accepted.
