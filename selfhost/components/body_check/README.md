# B3 scalar, string, byte, and list body checking

This producer owns typing and lowering of ordinary nongeneric function bodies
from raw ASTs. It emits complete native typed nodes, statements, functions, local
metadata, and per-function table ranges. It does not consume a native semantic
worklist or native checked bodies. B3 extends the qualified scalar and immutable text/byte closure with growable
lists. Selka chooses inferred list types and emits bounded catalog recipes; native
code materializes those recipes without choosing body types.

Admitted types are `int`/`i64`, `bool`, `Unit`, `str`, `bytes`, and recursively
nested lists of those admitted types. Operations include
literals, scalar unary and binary operations, UTF-8 text and arbitrary byte
literals, managed length and indexing (including negative indices), concatenation,
equality and ordering, explicit `int`/`i64` conversion of admitted integer values,
lexical locals and mutable reassignment, ordinary forward
and recursive calls, named/default arguments admitted by the parser, scalar and
managed mutation markers, branches, while/basic integer range loops,
break/continue, return, discard, and assertions with static messages. Managed
`+=` preserves the same native local provenance as scalar augmentation. Range
variables remain read-only, with native `E_IMMUTABLE` diagnostics on assignment.
Signature and local annotations are checked by the producer.

The request supplies nullable catalog descriptors `string` and `bytes`, each
containing an authoritative type ID and its element type (`u32` and `u8`,
respectively). IDs are not hardcoded. Null descriptors preserve scalar admission
and cause explicit profile refusal only when the unavailable managed type is
used. UTF-8 literals emit exact code-point child nodes; byte literals emit octet
children. A byte literal expected as `str` follows native contextual UTF-8
materialization. Byte literals in scalar expected-type contexts require native
fixed-array schema interning and are explicitly outside B2. Byte indexing emits the native narrow `u8` index node followed
by an `int` cast. These internal narrow types are not exposed as new source-level
integer types. Full typed tables retain native intermediate nodes and exact spans.

Other collections, generic functions, checked failure signatures,
lambdas, resources, contracts, nominal declarations, non-i64 scalar suffixes,
floating division, chained comparisons, dynamic assertion messages, explicit
range strides, keyed/callback sorting, enumerated/unpacked iteration, non-list
methods and slicing are outside this profile. Scalar alias
names remain in the catalog for shadow checking, but alias annotations are not
resolved by this producer. Unsupported forms produce `P_BODY_PROFILE`; component
mode refuses without native body fallback. Malformed graph transport fails the
exchange rather than becoming a source diagnostic. Source diagnostics preserve
native messages, related sites, and edits within the admitted closure.

Native code retains catalog foundations, entry adaptation, effects and origin
analysis, domain codecs, warnings, and cache publication. The producer executes
after common catalog collection and before native generic-contract checking;
it performs the body decisions itself. Shadow mode compares an uncached native
body batch, diagnostics, and import usage. Component mode adopts the validated
batch at the body-checking seam. Reference mode remains available.

`main.my` accepts `--exchange FILE` or unframed `--request FILE`. The normative
wire contract is [WIRE.md](WIRE.md): protocol 1, schema 3, correlated `SLKBCK01`
envelope, named-field `SLKBKI01` request and `SLKBKR01` reply. Schema-1 packages and
requests are refused. The request contains raw ASTs, sources, declaration facts,
and the two retained-catalog descriptors. Batch fields remain
`nodes`, `statements`, `functions`, and `ranges`.

The bounded profile allows 64 MiB frames, 1,048,576 graph values, 4,194,304 graph
edges, depth 256, 1 MiB per module source, 8 MiB aggregate sources plus at most
4096 separator bytes, and 4096 modules. Typed nodes and statements are each capped
at 262144; functions and aggregate locals at 65536. Literal children count against
these same typed-node and graph limits. Existing parser value helpers are
immutable symlinks copied into coordinator snapshots. Seed and component-v1
language admission remain unchanged.

Pure tests are the seven `*_tests.my` modules. Run each with the
coordinator-verified seed under `scripts/build-slot.sh build`, normally and with
`--release --verify-facts`, `MYL_CORE_LEAKCHECK=1`, private disk `TMPDIR`, and a
worktree-local Zig cache. Installed workflow tests compare complete
native/component/shadow outputs and generated program execution; pure tests do
not establish whole-checker adoption.


The schema-3 catalog adds `base_count`, sparse authoritative existing `lists`
(`id`, `element`), and `list_available`. The builtin can be absent or shadowed.
List interning reuses an existing element key or assigns the next contiguous ID
`19 + base_count + recipe ordinal`. The output adds `lists`, whose recipes retain
the true first source span. Existing forward dependencies are checked for cycles;
new recipes depend only on the retained catalog or earlier recipes. The total
record limit is 65,536 and logical type depth is 256 including a scalar leaf.

Lists support inferred, contextual, empty and nested literals; annotations;
copies, rebinding, arguments and returns; length and negative indexing; equality;
`+=` extension; repetition; indexed writes and augmentation; direct and expression
receiver methods for append, extend, insert, pop, remove, index, reverse, sort,
copy and clear; and single-binding iteration. List `+` remains the native source
error. Unkeyed sorting admits int, str and bytes elements. The producer preserves
hidden collection roots, managed cleanup, constant packing at 64 inert elements,
full intermediate rows, and source-growth/rebinding behavior during iteration.
