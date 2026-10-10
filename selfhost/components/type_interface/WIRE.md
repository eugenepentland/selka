# Type/interface batch schema 1

This stage moves the whole-project `Index.checkSignatures` pass and its name/type
resolution into one component exchange. Body, effect, contract and specialization
resolution remain native. No lookup launches a child. The input is raw projected
AST syntax, authenticated source and indexed module facts; native projection does
not precompute semantic resolution decisions.

All integers/counts/enums/Booleans are little-endian u32. Booleans accept only 0/1.
A byte string is length + raw bytes. A span is start/end. A slice is count + rows.
An optional field is Boolean presence + payload when present. Field order below
is normative. Kind IDs are type=0,function=1,constraint=2.

Outer64: magic `SLKTIF01`, protocol1 at8, schema1 at12, direction0(request)/1(reply)
at16, payload length at20, nonce8 at24 and request payload SHA256 at32. Reply echoes
bytes24..64 exactly. Payload length must match, with no trailing bytes.

Request `SLKTYI01`, order(slice u32), modules(slice Module). Module IDs are array
indices, Context.module must match, names are nonempty, is_imported equals the
incoming-edge fact, and order is an exact permutation.

- Module: context, imports(slice Import), symbols(slice Symbol), import_used(slice Boolean), catalog.
- Context: module, name(bytes), path(bytes), trusted_intrinsics(Boolean), is_imported(Boolean), source(bytes).
- Import: name(bytes), alias(bytes), span, target(module ID).
- Symbol: name(bytes), kind, span, exported(Boolean), owner(optional bytes), restricted(Boolean), re_export(optional Identity).
- Identity: module, symbol.
- Catalog: records, variants, aliases, domains, constraints, functions, suffixes, callbacks, arrays, applications, tuples (each a slice, in that order).
- Record: name(span), parameters(slice Generic), fields(slice span).
- Variant: name(span), parameters(slice Generic), cases(slice Case).
- Case: payload(optional span), fields(slice span).
- Alias/domain: name(span), target(span).
- Constraint: name(span), span, subject(Generic).
- Function: name(span), owner(optional span), parameters(slice Generic), inputs(slice span), return_type(span), failure_type(optional span).
- Generic: name(span), default_copy(Boolean), constant_length(Boolean), requirements(slice span), fields(slice Field), operations(slice Operation), named(slice Reference).
- Field: name(span), ty(span).
- Operation: name(span), parameters(slice Field), return_type(span).
- Reference: alias(optional span), name(span).
- Suffix: span, base(span).
- Callback: span, parameters(slice span), return_type(span), failure_type(optional span).
- Array: span, enum_index(optional span), element(span).
- Application: span, name(span), arguments(slice span).
- Tuple: span, elements(slice span).

Reply `SLKTYR01`, outcome tag0(success)/1(failure).

- Success: order(slice u32), import_used(slice of Boolean slices in ascending module ID), resolutions(slice Resolution).
- import_used: exact one Boolean slice/module and one flag/import; every input true remains true.
- Resolution: from(module ID), alias(optional bytes), name(bytes), kind, span, identity.
- Failure: code(bytes), message(bytes), site(Site), related(optional Site).
- Site: module, span. Failure vocabulary is the exact existing signature/generic/structural diagnostic catalog.

Receipts record successful `Index.resolve` calls in execution order, including
repeated calls and canonical re-export origins. Constraint resolutions swallowed
into a generic sink retain the native error transformation; failure replies carry
the final first diagnostic only. Import flags begin with declaration collection's
input flags. The native validator checks framing, bounds, raw-source association,
module/name/identity correspondence and usage consistency without rerunning the
signature checker. Shadow compares complete diagnostics, usage and receipts.

Limits:4096 modules;1MiB source/module and8MiB aggregate source;65536 aggregate
symbols;65536 aggregate type-expression rows;65536 aggregate declaration rows;
65536 aggregate nested syntax rows/edges;4096 imports/module and65536 aggregate
imports;16KiB path/module;8MiB aggregate non-source strings (including paths);
64MiB complete framed request/reply;256 recursive type depth;65536 receipts.
Counts are admitted before allocation. Empty type spans are allowed where native
preflight treats absence/Unit; declaration names must be nonempty. Source bytes
remain raw, including UTF8 interiors. Effect/mutation metadata, defaults, function
bodies, resource declarations and unused type-expression flags are deliberately
excluded because `checkSignatures` does not read them.
