# Complete parser syntax values

The parser component exchanges logical `ast.Program` fields and parser
diagnostics with a native host. The host validates every value before comparison.
This version is a qualification contract; changing an AST field requires updating
the producer and schema qualification together. It is not a Zig memory layout.

`mylang dump-syntax FILE.my` parses one module without loading its imports and
writes a binary `SLKAST01` document. Source failures retain ordinary diagnostic
output and exit 1; protocol, deployment, or comparison failures exit 2 without
partial syntax output. `MYLANG_PARSER_MODE=reference` is the default;
`MYLANG_PARSER_MODE=shadow` executes the verified `parser-pilot` component and
compares every canonical field before returning the reference result.
`MYLANG_PARSER_MODE=component` adopts the validated component result.
`MYLANG_COMPONENT_DIR` selects the installed component directory.
This command performs no syntax or semantic cache lookup.

## Request and process envelope

All integers are little-endian. A 64-byte `SLKPRS01` envelope contains protocol
and schema (`u32`, protocol 1 and profile schema 2), direction (`u32`, request 0 or reply 1), payload byte
length (`u32`), an 8-byte request nonce, and the SHA-256 digest of the complete
request payload. Replies echo all 40 identity bytes exactly. Length, version,
direction, identity, and reply schema are checked before decoding.

The request payload begins with `SLKPAR01`, then five `u32` values: source byte
length, token count, module flag, intrinsic-trust flag, and path byte length.
Path and source bytes follow, then token rows. Each row contains `u32` tag length,
ASCII tag bytes, and `u32` start/end byte offsets. Module and trust flags are
either zero or one. Bounds are 1 MiB source, 1,048,833 tokens, 16,384 path bytes,
and 64 MiB complete framed request. Tokens must have ordered valid spans and a
final zero-width EOF at the source length. Token spelling correspondence belongs
to the trusted lexer that constructs this request.

The host derives intrinsic authority from explicit source authority or exact
embedded standard-library bytes; a standard-library-looking path alone grants
nothing. Selected component parsing requires a fresh current-dialect cursor.

Execution verifies the artifact manifest and digest, runs an immutable sealed
executable snapshot, uses a private request directory, bounds both output streams,
and applies a deadline to the complete child lifecycle. It checks the deployed
artifact again afterward. Missing, corrupt, replaced, timed-out, and malformed
components fail explicitly. The installed path needs no Python.

## Value documents

Success uses `SLKAST01`; parser failure uses `SLKERR01`. Both have an 8-byte magic,
`u32` value count, and `u32` root ID. Values are postorder, and the root must be
the final value. Each value has these fields in order:

| Field | Encoding |
| --- | --- |
| Kind | `u8`: null 0, integer 1, boolean 2, bytes 3, enum 4, record 5, list 6, tagged union 7 |
| Integer | `i64`; zero when unused |
| Data | `u32` byte length, then bytes; empty when unused |
| Children | `u32` count, then `u32` IDs strictly below this value's ID |
| Field names | `u32` count, then length-prefixed byte strings; records only |

Records require exactly the named fields of the expected logical type, with no
duplicates or extras. A decoder accepts field order differences; canonical
encoding restores declaration order. Enums use tag bytes. Tagged unions carry
one named tag and one payload child. Options use null or the contained value;
void is null. Boolean integers must be zero or one. Node and statement IDs are
integers, while their ordered tables are lists. List capacities and pointers
never enter the document.

The syntax root includes type declarations and all their auxiliary tables,
nodes, statements, functions, lambdas, declaration attributes, and docstrings.
Function policies/signatures, literal payloads, operator spans, named/mutable
arguments, contracts, and ordered metadata are ordinary required fields.

The error root contains an ordered `diagnostics` list. Each entry preserves code,
severity, span, message, related note, and provenance. Provenance preserves origin,
requirement, and the ordered primary/additional repair edits. Note roles remain
explicit. Runtime stack and obligation data are outside this parser contract.

## Validation and ownership

The native decoder owns an arena independent of the request and producer. Its
caller releases that arena after comparison or deliberate adoption. Byte spans
must lie inside the original immutable source. Every node/statement ID must name
the correct table; mixed node/statement cycles are rejected before traversal.

Bounds are 64 MiB serialized value bytes, 1,048,576 values, 4,194,304 aggregate
child edges, depth 256, 4,194,304 decode visits, and a combined 512 MiB
graph/decode allocation budget. The outer reply adds 64 bytes. AST validation
separately bounds node and statement tables to 262,144 each, graph visits to
4,194,304 and depth to 256. Exceeding a bound is a protocol failure. The
[profile qualification](parser-component-qualification.md) distinguishes these
independent bounds from source-language diagnostics and default adoption.

The native full oracle roundtrips the selected language and standard-library
sources separately from Selka grammar comparisons. Oracle roundtrip success
proves codec coverage only. The full parser fixture harness compares canonical
ASTs or complete diagnostic reports, and a corpus audit rejects unsupported or
mismatched modules instead of counting them as passes.

The reusable host API is `parser_component.parse`; `identity` binds mode, schema,
and verified producer digest. Compilation, module loading, formatting and tooling
use the selected whole-source boundary. Authenticated producer identities
partition reusable syntax, semantic state and execution receipts. Shadow bypasses
those hits to preserve comparison. Native reference remains the default; see
[workflow qualification](frontend-adoption-qualification.md).
