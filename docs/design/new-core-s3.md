# New compiler core, stage S3: applications and runtime effects

Status: Wave A approved; Waves B/C/X authorized from `3d0bfd23` on
`codex/new-core-s3-integration` by the user's 2026-10-06 go. The next review
stop is the final S3 exit report and S4 go/stop decision.
The implementation plan is `docs/audits/new-core-s3-implementation-plan-2026-10-06.md`.
The S0/S1/S2 as-built rules, N1–N6, R1, D1–D4 and L1–L4 remain binding.
This note specifies the shapes frozen by S3-0; later sections will record
package results and the S3 exit report. No S3 exit is claimed in Wave A.

## 1. Capabilities, resources and the C boundary

`Stream` and `Host` keep `Type.cap`, an unmanaged `i64` token. A stream names
a descriptor; a Host token is checked for authority before invoking its host
adapter. The other capabilities (`Filesystem`, `Network`, `Clock`, `Entropy`,
`Environment`) map to `Type.capability`, a counted pointer to an immutable
authority block. The added leaf enum tags use explicit high values to preserve S2 compound IDs
and emitted-definition names; they are not persisted type identifiers.
Their family remains known from the checked node, rather than
being encoded in a new IR instruction for each operation.

A capability block uses the existing 32-byte header, runtime kind 6. Data holds
family, rights, provider identity, stand-in identity and scope. Derived
`fs.dir`, `net.host`, read-only/write-only and `env.only` authorities create
new blocks retaining their parent and any owned scope/name bytes. They never
broaden parent authority. Mutable clock/entropy stand-in state belongs to a
counted provider-state child shared by derived capabilities; authority itself
is immutable. The descriptor in `reserved` enumerates those children for
iterative one-count destruction. Capability pointer bits and identity are
never dictionary keys or optimization facts.

The authority payload is `{u32 family, u32 rights, ptr provider, ptr parent,
ptr scope}` at offsets 32, 36, 40, 48 and 56. The provider is a counted state
block identifying the real/test adapter and its mutable stand-in state; the
scope is a counted name or name-list block, or null for an unscoped authority.
Runtime-owned static element descriptors enumerate these three nullable child
pointers. Authority/provider blocks have `len = 1`; their descriptors use the
existing layout format and do not interpret handle/token words as pointers.

Open files and acquired resources use `Type.resource`, another counted pointer
(kind 7). The data contains provider/handle, family, rights and an open/closed
state. The block retains its capability. Explicit completion/close is a
runtime effect on resource identity; it does not COW-copy an OS handle.
Successful completion marks it closed and unregisters it. Failed completion
preserves the resource in the old core's completion-result schema. Dropping
the final count releases an open handle exactly once. An explicit close of
an already-closed handle follows the old runtime's status, never a second
provider release. `with` emits completion on every normal exit including
return, break and propagation. Traps remain fatal with no SSA releases:
a runtime registry releases remaining external handles before fatal exit,
without reporting additional successful program output. Resource blocks and
registry links must not be followed after handle cleanup frees them.

Resource payloads start with the retained authority pointer, followed by
provider handle/token, family, rights and state; they also have `len = 1` and
a nonzero static child descriptor in `reserved`. S3-C extends the runtime's
iterative free dispatcher with a resource-finalization hook before releasing
children. The nonzero descriptor already forces emitted release through that
dispatcher, preserving existing leaf free-list code. Registry entries are weak
links, removed before block free; trap cleanup closes and marks surviving
resources without releasing their counted blocks or changing the pending chain.

S3-C ports algorithms from `qbe_io.c`, `qbe_files.c`, `qbe_grants.c`,
`qbe_providers.c`, `qbe_resources.c` and `qbe_host_runtime.c` into
`src/core/runtime/core_io.c`. It does not link their objects or QBE context.
The grant parser and scoped-path/endpoint checks preserve `MYLANG_OPTIONS`,
`--restrict`, allow flags, missing-authority diagnostics, provider statuses,
resource completion and flush ordering. The entry wrapper creates requested
capabilities and drops its owned arguments after main. Source `extern` still
drops its required Host token from the C ABI; Host authority is checked before
that call. Its shared scalar-only contract stays unchanged: no foreign pointer,
aggregate or variadic source signature is admitted. Runtime helper aggregates
use generated typed adapters and output slots with explicit byte layout; a
resource pointer is never passed as an old-core handle/context object.

**Runtime calls use existing `call`, with new linkage `runtime_c`.** It follows
C scalar/pointer ABI and passes all declared arguments, including `cap`.
`extern_c` continues to omit `cap`. Both are external calls, never inlined as
an internal function or given the internal large-aggregate ABI. Runtime result
aggregates use an explicit caller-allocated box/output slot plus status and
IR aggregate construction, avoiding reliance on clang's C struct return ABI.
No new indirect external function-value ABI is admitted.

All effects remain exact ordered calls with `nounwind`; no `readnone`,
`readonly`, `willreturn` or speculative attributes on I/O, close, grants,
Host or stand-in operations. Facts do not infer capability/resource content
or open-state invariants. `err_trace.runtime` follows an error result. The
existing owned mask represents transferred arguments; others borrow. Adapter
output-slot allocations are consumed/read/released using existing box ops.

## 2. Mutable bytes and embedded blobs

`Type.byte_buffer` is a counted leaf pointer, kind 5, with the same 32-byte
header and bytes at offset 32 as `str`/`bytes`. `len` and `cap` count octets;
`reserved` is zero. It has no text/hash/cursor cache flags. Its updates are
value-functional: the ownership pass copies a borrowed or live receiver,
checks a maybe-shared receiver and updates a proven-unique one in place.
Every uniqueness claim receives the existing verify-mode count assertion.
The COW copy preserves bytes and capacity but not an immutable text cache.

The new IR operations are:

| Op | Operands | Result | Ownership/check |
|---|---|---|---|
| `buffer_new` | `a: u64` capacity | `byte_buffer` | fresh owned |
| `buffer_copy` | `a: byte_buffer` | `byte_buffer` | fresh independent copy |
| `buffer_set` | `a: byte_buffer`, `b: integer`, `extra[0]: u8` | `byte_buffer` | consumes a; exact bounds |
| `buffer_push` | `a: byte_buffer`, `b: u8` | `byte_buffer` | consumes a; allocation failure fatal |
| `buffer_pop` | `a: byte_buffer` | `byte_buffer` | consumes a; exact empty check |

`buffer_pop` follows `list_pop`: the builder first reads the final u8 using
`list_get`, then pops. `list_len` and `list_get` admit `byte_buffer` alongside
immutable bytes; they have the usual integer length and u8 element results.
Other list ops do not accept byte buffers. Clear becomes a fresh empty buffer;
extend lowers to pushes or an owned helper result, preserving snapshots and
place write-back. S3-T2 enables these ops in source only after implementing
COW integration and runtime behavior. Fresh-buffer provenance and length facts
are conservative until their rules and verify assertions are tested.

`bytes(buffer)` copies (later buffer writes must not change the bytes).
`buffer.decode()` validates/copies into immutable text. Immutable `bytes.decode`
may borrow the same block only after validation and with ownership tied to the
source; `str.encode` retains S2's exact identity helper. Invalid UTF-8 and
`errors=` modes follow the old core's result/trap behavior.

`typed.Blob` is not another source value type: it supplies a content digest
and length for `embed_bytes`/`embed_str`. S3-T2 resolves its checked source's
embedded asset, interns raw bytes, and emits an immortal STR/BYTES block with
compile-time ASCII/hash/scalar metadata where applicable. Arbitrary octets,
NULs and empty payloads must survive; an unresolved digest is a located
refusal, never silently an empty blob.

## 3. Numbers in text

S3-T2 extends `build_number.zig` and `core_number.c`, with an independently
compiled Zig runtime unit `runtime/core_number_text.zig`. The old native
formatter is itself Zig: `native_format.zig` delegates to `number_text.zig`
and `format_spec.zig` (including `std.fmt.float.render` and `std.fmt.parseFloat`).
Port their algorithm into the new runtime namespace with Core block adapters;
do not link `native_format` or its legacy heap. The driver embeds/hashes the
complete helper sources, caches its object alongside the C runtime object and
links both. This keeps exactly the old algorithm with the bundled Zig version.
S3-T2 measures a program's first build in a fresh runtime cache, reporting the
separate cost of compiling this Zig float-text unit. Its cached object key
includes every helper's content hash, the Zig version and relevant target/build
options, so subsequent programs reuse the object and a toolchain change cannot
reuse stale formatter code.
It ports the old formatter
and parser algorithms, including nonfinite values, negative zero, exponent
spelling, rounding/ties and the bounded formatting frame. The sources are
`qbe_io.c` and the value/text-format implementations it calls; ported functions
name their sources in comments. No replacement by `%g`/`printf` is accepted
without exact old-core agreement over tests and float-text fuzz.

Float text, `number_format`, `hex`/`from_hex`, `parse_int_range`, receiver
parsing and `parse_float` use typed runtime calls and existing Option/Result
construction. Range parsing borrows its receiver; checked grammar, underscores,
sign, radix, whitespace and overflow remain the old grammar. Integer decimal
format/parse fast paths are unchanged. Float parsing consumes no string.
Float rendering creates owned ASCII STR blocks. Facts of parsed values stay
unknown; no finite/non-NaN premise is inferred from a successful parse alone.

## 4. Remaining text library

S3-T1 ports the old `native_text_methods.c`, text/UTF-8 helpers and the checked
buffer-operation contracts. It preserves scalar indices for text and octet
indices for bytes, including negative/range/step behavior, empty needles,
empty separators, whitespace and Unicode case expansions.

| Operations | Lowering |
|---|---|
| count, contains, starts/ends, find/index/rfind and range variants, find_any | borrowed runtime helpers; scalar results for text |
| upper/lower, strip/lstrip/rstrip/strip_chars, replace, reverse, splitlines, step slices | helpers returning owned text/list values |
| chr/ord, scalar_count, repr, text_format, decode | validated typed helpers; owned rendered text, scalar ord/count |
| extend | consuming byte-buffer or list composition; text remains immutable |
| string char/width/code, append, char append, views, slices | retain frozen S2 operations and cursor fusion |

No general source string view ABI or inline short-string representation is
introduced. Borrowed span helpers can admit S2's SSA `str_view` under the existing
views mask. Every added helper explicitly declares borrowed inputs and owned
outputs; an allocation-free identity needs an ownership parent rule, not just
an extern return type. Runtime helper calls that can fail retain locations and
trace/trap semantics. Existing row fast paths change only with profile evidence
and both old-core and Zig gates. The fused split cursor remains deferred until
multi-block inlining is justified; the existing split row already passes.

## 5. Generics

The shared checker already produces concrete `typed.Function` specializations;
`generic_specializations.zig` stores/replays concrete checked bodies and the
builder sees resolved local, parameter and result types. Source generic templates
need no Core IR type variables or backend instantiation pass. S3-M lifts static
conformance exclusions one file at a time, records all newly exposed refusals
and implements only those within S3. A specialization reached from an imported
standard module follows the same whole-program path. No specialization-cache
format changes are planned; any persisted shape change requires a version bump.

## 6. Standard-library imports

`frontend.Session.checkFile` already chooses the module graph for a source with
a module header. `project_compile.Compilation` returns a merged checked program
and source-origin map. `strings` and `json` use this whole-program path; S3-A
builds every reachable concrete imported function through ordinary builder IDs.
There is no second linking step and no `.myi` or per-module Core IR cache in S3.
The shared loader may resolve user modules, but those are not S3 admission or
qualification claims. User-module tests stay explicitly named for S4. Source
positions and embedded assets must use the merged source's origin authority.
The old persisted formats remain module-interface-v5, check-summaries-v6,
mutation-v2 unless a later package deliberately changes one.

## 7. Test runner and output

S3-C extends `test_runner*.zig`, retaining per-test status/stdout/stderr checks.
It ports the old runner's property trial counts, deterministic seed stream,
parameter generation, failure accounting and capability stand-in construction.
Each test owns a separate temporary directory and capability/provider state.
Clock and entropy use declared stand-ins; network tests use fixtures only.
Cleanup closes registered handles and checks both blocks and open handles.

A `Result[bool,E]` test succeeds only on Ok(True); Ok(False) is a failure and
Err reports its rendered value/trace exactly as the old runner. No status-1 or
signal exit is accepted solely because stderr is empty. Generated runner calls
build the existing result tag/payload ops, not a new Result ABI.
`print` with dynamic separator/end lowers to ordered runtime write/render calls;
the existing plain print remains unchanged for code identity. `stream_write`
uses a borrowed stream/text runtime call. Error reporting preserves flushing,
float rendering and source traces.

## 8. Numeric operations and facts

The frozen IR gains `shift_left`, `shift_right`, `saturating_add` and
`float_unary`. Shifts take `a` and `b` of their result integer type, trap for a
negative signed count or count >= bit width, and left shift discards bits (no
arithmetic overflow trap). Right shift is arithmetic for signed and logical
for unsigned. Saturating addition clamps to the signed/unsigned type bounds.
`float_unary` takes and returns f64; `data` is `FloatUnary`:
sqrt, floor, ceil, trunc, abs, sin, cos. Integer/f64 conversions reuse existing
`int_to_float` and checked `float_to_int`; round uses helper composition for
the old tie rule. Special-value/NaN canonicalization follows the old runtime.

Wave A supplies typed, fail-closed emission stubs for these ops. S3-M replaces
them with checked shifts, LLVM saturating/float intrinsics or equivalent exact
helpers. No source construct is admitted on the strength of a stub.
Facts initially leave the new scalar ops unknown. Later shift-count proofs
must assert the count range in verify mode; saturation intervals clamp the hull;
float rules infer finite intervals only with outward rounding and valid domain
premises. All derived intervals are asserted at definition/function entry using
the existing mechanism. Trig results are not assumed finite for arbitrary input.

## 9. Recursive equality and aggregate operators

S3-M generates structural equality helpers per concrete recursive type, using
existing calls, field/tag/box reads and loops. Tag comparison precedes payload
reads; record/array fields ignore padding, and list/dictionary equality keeps
old semantics including order-independent dictionaries. Immutable boxed recursive
values cannot acquire cycles through ordinary checked value construction; deeply
nested comparisons use an explicit worklist rather than unbounded C recursion.
Resource/capability equality, if checked, follows the old identity contract,
not the bytes of its authority block. Unsupported cases remain located refusals.
Aggregate operators follow the checked form: collection concatenation/repetition
and set compositions lower to existing updates/calls; no blanket bitwise operator
on record memory is introduced. Keyword/interior mut refinements preserve the value selected before later arguments
and current whole-root reload. Later ancestor writes supersede interior publication,
including a whole-root mut call that changes only a scalar field. Narrowing the conservative refusal
requires differential proof; an old implementation accident is reported for a
user decision rather than given invented semantics.

Captured places carry a scoped SSA publication guard while later arguments evaluate.
Executed whole-root writes invalidate publication; sibling updates keep the place
live, and a same-place update is read from the current binding before the call.
Dictionary paths retain evaluated keys instead of entry offsets. Guards join across
conditional arguments, so an untaken root mutation has no effect. Reordered keyword
arguments start their guards when the checker-generated source-order temporaries
select their places. An orphaned path is never reread. Two narrower cases remain
located refusals: an ancestor changes during the initial index/key evaluation, or a
later interior write may name an ancestor. The old native pin protocol can preserve
publication through an interior ancestor update; a root-version test cannot model
that distinction, and S3 does not guess from a callee's body or leaf equality.

## 10. Wave A qualification and as built in S3-0

S3-0 adds three leaf pointer types, nine operations (five buffer updates and
four numeric shapes), the float-unary selector and runtime-C linkage. It extends
layout, verifier, printing, ownership COW dispatch and emitter dispatch. Existing
scalar capability `cap` and existing source refusals remain until Wave B.
Hand-built IR verifies every new op's shape and compiles its fail-closed stub;
additional tests cover malformed operands, float selectors, byte reads, managed
aggregate/niche layouts and runtime-C token passage versus source extern erasure.
The new runtime files are embedded and included in the runtime object digest.
No legacy runtime is linked.

Qualification commands, results and commits belong in
`experiments/new-core-s3-20261006/wave-a/`. Required checks: held sharded test-core
under five minutes, full debug/release conformance with zero mismatches, complete
S0/S1/S2 emitted-definition identity and the full old-core gate for S3-L/shared
changes. The coordinator runs cheap checks after both package merges and then
stops for review. No Wave B feature is implemented before that review go.

**Wave A completed.** The approved foundation source is `dc1a5831`, with
qualification in `643858e3`; D2 source and qualification are `225bee07`.
Integration merges are `e39ad11d` (S3-0) and `f5ba28e5` (S3-L). `ir.zig` is
unchanged from the foundation through both merges. D2 rejects source view
annotations at their declarations, indexes immediate consumers once per check,
and uses dictionary hash membership for keys; values/items membership scans.
Impossible held-view tests are retired or replaced by explicit snapshots and
rejection checks. The full old-core gate is green.

The final source merge rebuilds uncontended in 1.67 seconds. Its held
eight-shard core suite passes all 219 tests in 68.31 seconds, with the longest
shard at 66.81 seconds and maximum reported shard RSS `201M`. Debug and release
each give 1243 matching, zero mismatching and 275 unsupported tests of 1518;
the package's strict leak/fact-verify sweep is clean. All 35 existing benchmark
function definitions match `92590700`. The S0 and dictionary packages each pass
50-case strict fuzz (750 comparisons each). Checked coverage moves from
3185/3627 to 3213/3595, with no accepted-name regression; the changed denominator
is documented by name. Commands, exact commits, all remaining refusals and
historical failures are in
`experiments/new-core-s3-20261006/wave-a/REPORT.md`. Wave A stops for review;
Wave B and the §11 exit record remain pending the user's go.

## 11. S3 as built and exit record

S3 exited on 2026-10-06 at `d4994214579adb8d1897a40fc65de1462b000939`. The exit
report is `experiments/new-core-s3-20261006/wave-x/REPORT.md`. The package history
and the remaining-limits inventory are under `wave-x/report-preparation/`.

**As built.**
- **S3-0** froze the capability, resource and byte-buffer pointer types, nine
  operations and runtime-C linkage. `ir.zig` is unchanged since.
- **D2:** dictionary views are immediate-use only (`E_VIEW_STORED`). Key membership is
  a hash probe.
- **T1** keeps the old scalar and octet text semantics.
- **T2** adds byte-buffer copy-on-write, embedded assets, and the old Zig float
  formatter and parser in an independently cached runtime unit. Its first build costs
  0.97 s; later programs reuse it in 0.11 s.
- **M** adds exact numeric operations, descriptor equality and hashing, and
  source-aware rendering. Captured `mut` places follow `COW-MUT-ARGUMENT-1`.
- **C** owns counted authorities and resources and the property runner.
  `ENV-NAMES-GRANT-1` corrected both cores.
- **A** adds `strings`/`json` imports and the five applications, with generic,
  profile-driven repairs.

**S3-X found one wrong answer**, fixed by `NEW-CORE-RC-13`. A field read after its
record was already consumed by an earlier update had been promoted to its own count,
and a later in-place push then corrupted a live snapshot. `liveAfter` now returns
false before a value's definition.

**Exit receipts** (all on the final source):
- uncontended rebuild 1.80 s;
- 277/277 core tests in 146 s, longest shard 51 s;
- conformance 1518/0/0 per mode, ordinary and with leak and fact verification;
- the full old gate in four steps;
- 9 × 200 fuzz with 25,800 comparisons, plus the 200-source split sweep with 3,000;
- all 40 rows within 1.10× Zig ReleaseSafe and 1.10× the old core at 4096 and 64
  (worst: 1.089× Zig, 1.060× old);
- the count audit;
- coverage 3,633/3,639;
- exclusions: 9 S4 tests and 118 retired arena tests.

**Remaining by design for S4:** user modules, persisted interfaces and incremental
per-module builds. The old core stays the default until S5.
