# B7 scalar, managed value, checked-failure, and scoped file body checking

This producer owns typing and lowering of ordinary nongeneric function bodies
from raw ASTs. It emits complete native typed nodes, statements, functions, local
metadata, and per-function table ranges. It does not consume a native semantic
worklist or native checked bodies. The producer extends scalar and sequence checking with ordinary nongeneric value records. Selka chooses inferred list types and emits bounded catalog recipes; native
code materializes those recipes without choosing body types.

Admitted types are `int`/`i64`, `bool`, `Unit`, `str`, `bytes`, `byte_buffer`, and recursively
nested lists, ordinary records, and ordinary nongeneric variants whose payloads use those admitted types. Recursive record storage through a list is admitted; direct by-value layout cycles are rejected. Operations include
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
fixed-array schema interning and remain outside this profile. Byte indexing emits
the native narrow `u8` index node followed
by an `int` cast. These internal narrow types are not exposed as new source-level
integer types. Full typed tables retain native intermediate nodes and exact spans.

Other collections, generic functions,
lambdas, resources, invariant/contracts, generic or boxed records or variants, domains, non-i64 scalar suffixes,
floating division, chained comparisons, dynamic assertion messages, explicit
range strides, keyed/callback sorting, enumerated/unpacked iteration, non-list methods outside the closed byte vocabulary, stepped text slices, and list slices are outside this profile. Transparent aliases are resolved from raw declarations with module privacy and canonical re-export identities. Unsupported forms produce `P_BODY_PROFILE`; component
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
wire contract is [WIRE.md](WIRE.md): protocol 1, schema 7, correlated `SLKBCK01`
envelope, named-field `SLKBKI01` request and `SLKBKR01` reply. Older body schemas and packages are refused. The request contains raw ASTs, sources, declaration facts,
and the retained catalog descriptors. Batch fields remain
`nodes`, `statements`, `functions`, and `ranges`.

The bounded profile allows 64 MiB frames, 2,097,152 graph values, 4,194,304 graph
edges, depth 256, 1 MiB per module source, 8 MiB aggregate sources plus at most
4096 separator bytes, and 4096 modules. Typed nodes and statements are each capped
at 262144; functions and aggregate locals at 65536. Literal children count against
these same typed-node and graph limits. Body-private value helpers retain the
canonical codec algorithms with a body-only graph ceiling; the parser component
remains at 1,048,576 values. Other shared parser helpers remain immutable symlinks
copied into coordinator snapshots. Seed and component-v1
language admission remain unchanged.

Pure tests are the `*_tests.my` modules in this directory. Run each with the
coordinator-verified seed under `scripts/build-slot.sh build`, normally and with
`--release --verify-facts`, `MYL_CORE_LEAKCHECK=1`, private disk `TMPDIR`, and a
worktree-local Zig cache. Installed workflow tests compare complete
native/component/shadow outputs and generated program execution; pure tests do
not establish whole-checker adoption.


The schema-3 catalog adds `base_count`, sparse authoritative existing `lists`
(`id`, `element`), and `list_available`. The builtin can be absent or shadowed.
List interning reuses an existing element key or assigns the next contiguous ID
`19 + base_count + recipe ordinal`. Schema 3 originally returned a `lists` field; schema 5 replaces it with
ordered tagged `recipes`, retaining the true first source span. Existing forward dependencies are checked for cycles;
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


Schema 4 adds the complete retained `records` prefix to the catalog. Exact declaration spans join raw ordinary record declarations to authoritative retained type IDs through a stable indexed lookup. Selka resolves constructor names, visibility, aliases, arguments and defaults; it preserves source evaluation order and native field diagnostics. Field reads, nested record/list writes, receiver refresh after RHS evaluation, mut-record parameters, call snapshots, list elements and iteration preserve full typed metadata. The native materializer applies ordered Selka-owned catalog recipes without choosing body types.

Record admission rejects unsupported field policies and raw invariants globally, including unused and imported declarations. A bounded reverse-edge fixed point admits recursive record/list closure; a separate graph check rejects by-value record cycles. Private name indexes admit at most 1,048,576 entries and 64 MiB of generated key bytes, with early budget checks before key allocation. Record declaration span lookups and nominal name lookups use sorted indexes rather than full catalog scans per use.


Schema 5 adds authenticated optional Result/Option template bases. A nonzero
basis declaration span joins raw ordered cases and generic parameter spelling;
a zero span denotes the synthesized standard basis. Selka chooses List, Result,
and Option recipes in first-demand order, preserving the standard declaration's
case order. Retained schemas are leaves for new-recipe depth accounting; at most
255 new constructors may wrap a retained or scalar leaf. Fielded standard bases
that need additional synthesized payload records remain explicit profile refusals.
Source Result/Option applications currently use their bare canonical names;
qualified standard template applications and Option narrowing or receiver methods
remain explicit profile refusals.

The variant closure includes empty, single-payload and fielded constructors,
ordered named/default initializers, imported aliases and privacy, statement and
expression matches, nested/product normalization, wildcards and exhaustive
coverage. Recursive storage through lists is admitted; boxed payloads and direct
by-value cycles are refused. Checked failure signatures wrap success and failure
returns, and `try` propagates Result/Option values. Selka tracks pending transfers,
consumption sites, continuing-path agreement and scope obligations in local
metadata. Explicit discard consumes an obligation; implicit non-unit discard
requires a source repair. Lists cannot contain pending result-bearing elements.

This schema 5 producer is under development until the installed exact shadow
and generated runtime qualification complete. Utility tests and captured-request
successes alone do not establish full native body parity.


Integer text parsing is admitted as `parse_int(str_value)` and zero-argument
`str`/`bytes` receiver `.parse_int()` calls. Selka interns the canonical Option[int]
on its first body demand and emits native rooted or direct-local operation rows.
Invalid text and overflow remain runtime None results. The free function retains
the native str-only contract; parse_float and range parsing remain profile refusals.


## B6 byte closure

The schema 6 request authenticates `Templates.byte_buffer` using
`BufferBasis{available, identity:?Sequence}`. Existing canonical buffer IDs are
reused. First body demand emits one ordered `.byte_buffer{id,span}` recipe with
leaf depth one; IDs follow all earlier list/result/option recipes. A declaration
or alias that shadows the builtin disables its availability. Local shadowing remains a source decision. Standalone ordinary function names
block byte constructor recognition; project functions use native qualified keys
and therefore retain the current native bare-constructor precedence.

The producer admits `byte_buffer(int[])`, `bytes(int[])`, and immutable
`bytes(buffer)` snapshots; empty constructor lists receive native `int[]` hints.
It lowers plain string, bytes, and buffer slices with omitted/negative endpoints,
byte indexing with native u8-to-int widening, and canonical buffer `reserve`,
`append_byte`, and `append_range` calls. Receiver reads/writes, parameter origins,
COW aliases, and mutation markers retain native metadata. Byte `view` requires
an immutable bytes receiver. Indexed buffer writes and `.write()` retain native
source errors. UTF-8 scalar versus octet slicing and append-range runtime bounds
remain runtime semantics rather than producer constant evaluation.

Encoding/decoding, stepped text slicing, fused byte slice/view numeric parsing,
and wider byte methods remain explicit profile refusals. This wave does not
claim all compiler helper sources are admitted: text iteration, source-first
comprehensions, `str(int)` formatting, and `ord` remain separate pure-library
closure work. Filesystem/Stream/File capabilities remain outside this producer.
B6 installed qualification and performance evidence are maintained by the
integration lane; pure tests alone do not establish those claims.

## Pure-library source closure followup

A separate schema-6 followup adds immutable `str` and `bytes` iteration, scalar
`str` conversion, and `ord`. Text iteration binds one Unicode scalar as `str`;
byte iteration retains the native u8 read and i64 widening. Rebinding the source
retains its entry snapshot. `ord` folds a one-scalar literal and otherwise emits
the native rooted text operation. Rendering emits a direct canonical string cast.

Source-first list comprehensions over admitted lists, text, bytes, and ordinary
i64 ranges preserve filter-before-output checking, scoped immutable bindings,
first-demand list recipes, and hidden-local/table order. Unfiltered ranges use
the native unsigned capacity graph, including the minimum-safe crossing-zero
case; filtered forms reserve zero. Nested source-first comprehensions reuse the
same lowering. Set/dictionary gathers, generator callbacks, stepped ranges, and
wider collection families remain explicit profile refusals.

Plain list slices preserve normalized and clamped endpoints, snapshot ownership,
and the native copy-loop table order. Conditional expressions preserve branch
initialization and pending-value joins. Managed literal `str`/`bytes` constant
getters and imported reads retain ordinary function bodies and zero-argument
calls. Literal i64, bool, and Unit constants retain checked body rows, then
append the folded declaration return and fold each name use. General scalar
constant expression evaluation and embedded literals remain outside this
followup. Iteration through nested record/list places refreshes the same source
path under the native mutation guards. Text and immutable bytes repetition
evaluates each operand once, gathers references in a producer-interned list, and
joins with an empty separator. Zero and negative counts yield an empty value;
`*=` rebinds text/bytes while list repetition retains its in-place behavior.

Pure tests and authenticated developer replays are distinct from installed
source admission. The integration lane records admission of the nine selected
actual libraries and six actual test roots, together with full qualification.
The frozen B6 byte profile and its evidence remain a separate baseline.


## B7 scoped file and explicit output closure

The producer resolves `Filesystem` and `Stream` primitive signatures while
preserving declaration, alias, and import authority. Binary `open(..., "rb")`
selects canonical `str`, `bytes`, and `str[]` shapes before selecting the
canonical `Result[file, str]` recipe. A direct open at a `with` head uses a
file handle; ordinary calls keep the checked Result and its handling obligation.
`with try fs.open(...) as file` and matched handles bound by `with` both emit
real typed `with_scope` statements. File reads accept an absent count or an
`int` count. Scoped handles cannot escape through value reads, storage, calls,
or returns; methods outside lexical file ownership are explicit profile refusals.

`Stream.write` accepts admitted text, byte values, and byte buffers and returns
`int`. `Stream.print` admits `int`, `bool`, `Unit`, canonical text/bytes and byte buffers.
It retains written value order, `sep=` and `end=` checks,
explicit receiver identity, and exact source diagnostics. Ambient print is a
source error. Native scope cleanup, entry adaptation, effect inference, origins,
and other retained postpasses remain separate; the producer does not replace
resource cleanup with ordinary blocks.

Text/writable file modes, other file methods, native-renderable aggregate output,
arbitrary owned resources,
provider capabilities, and receiver forms outside this closure remain explicit
profile refusals. Schema 7 changes the admitted semantic profile without adding
request fields or widening the body graph, byte, edge, depth, or allocation limits.
Development replies from rewritten schema-6 captures are not schema-7
qualification evidence. Whole-source shadow and runtime qualification is required
before declaring the new entrypoint closure qualified.


The schema-8 dictionary/set producer is being implemented in reviewable slices.
The connected foundation adds authenticated collection templates, one globally
ordered recipe stream, dictionary literal arrays in written key/value order,
contextual narrow integer literals, structural Option facts and payload
lowering, direct dictionary indexing and length, and set literals, contextual
empty construction, and native set combination/relation lowering. Named
dictionary bindings support get, pop, setdefault, update, copy, clear, keys,
values and items with source operand typing and receiver usage metadata. Collection recipes use the outer `collection` tag and six inner tags;
views require their canonical dictionary to exist first. Ordinary record and
collection storage recursion remains bounded and does not change wire limits.

This slice does not qualify the complete dictionary/set closure. Collection
expression-receiver methods, live-view snapshots, dictionary/set iteration
and comprehensions are still being connected and must pass the native-controlled corpus before
selected-source admission is claimed. The previous B7 deployment and evidence
remain separate from schema-8 development.
