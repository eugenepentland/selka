# Plain JSON and literal slice arguments

The interpreter accepts byte-string literals directly at readonly byte-slice
parameters:

> The example below is quoted from the removed explicit storage tier (`&mut []T` slices, `borrow`, `discard`, `std_json`) and is not source the compiler accepts; see [docs/legacy/](../legacy/README.md).

~~~text
discard std_text::emit("hello");
let role = std_json::field(document, component, "pin_roles");
return std_json::textis(document, role, "input");
~~~

The literal becomes an immutable temporary whose borrow lasts for that call.
The compiler releases its backing after the call, including repeated calls in
loops. Mutable slice parameters, non-byte references and reference-returning
calls reject this shorthand. Named buffers still use explicit borrow scopes.
Generic bodies follow the same rules. Implementation temporaries are omitted
from navigation symbols; literal contents remain visible to duplicate discovery.

## Ordinary JSON

Import std_json for the compiler's standard document library.
Calling std_json::parse(heap, bytes, limit) consumes an owned Bytes buffer and
returns Parsed: either an owned Document or an i64 error. The underlying
json_parse::<Result>(heap, bytes, limit) intrinsic requires an owned u8 input,
owned i64 success buffer and i64 error payload.

This reads ordinary JSON without the typed-json-v1 envelope.
The existing json_encode and json_decode retain their typed wire contract.
Parsing has the allocation effect, obeys allocator regions and buffer quotas,
and publishes no partial document. Error codes are malformed input (1),
quota (2), or invalid byte budget (4). Real allocator exhaustion and VM step
exhaustion retain their normal VM failure behavior.

Limits are 1 MiB input, 64 nested containers, 2,097,152 scanner tokens and
128 MiB temporary parser storage. VM work charges input bytes and output tape
words. Duplicate **decoded** object keys, invalid UTF-8/surrogates, trailing
content, integers outside i64 and nonfinite fractional numbers reject even
inside unused subtrees.

This initial inspection API represents objects, arrays, strings, i64 integers,
finite fractional numbers, booleans and null. Fractional numbers are classified
but do not expose a floating-point payload: the language currently has no
floating-point API here. It is not a lossless JSON round-trip API.

Borrow the document for queries:

~~~text
borrow document[0..len_buffer(document)] as view {
    let count = std_json::field(view, 1, "count");
    if std_json::get(view, count, 0) == 4 {
        discard std_text::number(std_json::get(view, count, 5));
    }
}
~~~

Node zero means missing, root is node one. Each node has six i64 metadata words:
kind, decoded-text start, decoded-text end, subtree end, child count, integer
payload. Kinds are object=1, array=2, string=3, integer=4, fraction=5,
true=6, false=7, null=8. Objects contain alternating key/value subtrees; arrays
contain value subtrees. Decoded UTF-8 bytes follow the node headers.
The field, textis, equal and compare helpers avoid application-specific key tags.
Queries expect an unmodified parser-produced tape; bounds remain VM checked.
Typed node handles and higher-level iteration remain possible future improvements.

## Disk projects and tooling

The reserved std_json and std_text modules are supplied by the compiler;
project files cannot replace them. They work through disk and embedded providers.
Their source bytes count against project budgets and participate in graph,
schema, check-session and navigation identities.

Receipts name these immutable sources @stdlib/std_json.selka and
@stdlib/std_text.selka. Navigation validates the compiler identity instead of
looking for these paths on disk. Verification caches require the receipt's
compiler to be a declared current tool before reusing the graph.

The std_text library provides bounded input reading, byte-slice output and
decimal i64 output including the minimum integer. It imports the explicit io
host interface; the application still supplies that declaration and the host
grants raw byte I/O. JSON parsing is a general VM primitive. Board schemas,
sorting, geometry, connectivity, pin roles and SVG generation remain in .selka.

Installing these language changes rebuilds Zig once. Editing a consuming
.selka project continues to use the installed binary, without Zig or Guardian.

The [pin-role refactor](../../experiments/ergonomics/pin-roles/README.md) records
behavioral verification and application/library line counts. It is a coordinator
refactor, not a new independent productivity trial.
