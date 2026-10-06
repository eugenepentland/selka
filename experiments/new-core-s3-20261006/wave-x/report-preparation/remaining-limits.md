# S3 implementation limits

This inventory records implementation boundaries. The final exit report must
identify the source and executions that qualify them; this preparation is not
an S3 pass. Source references and the detailed read-only audit are retained in
`exit-report-preparation.md` and `exit-limit-audit.md`.

## Target, representation and foreign calls

- Qualification targets x86-64 Linux, AVX2, the SysV ABI, native CPU generation
  and the current 47-bit user-address assumption. `--generic-vectors` changes
  vector lowering on that platform; it does not qualify another platform.
- Aggregates must occupy the first 64 parameter positions. Scalar parameter
  positions are unlimited. Register/indirect aggregate selection and stack
  promotion have ordinary fallback paths and are not additional source limits.
- Concrete fixed-array lengths fit u32. Generic const lengths separately stop
  at 1,048,576; ordinary concrete syntax follows the frontend's host storage
  range. Whole rebinding of a mut fixed-array parameter is checker-refused;
  element writes and copying into a local remain available.
- Source extern requires a first Host authority argument, erased from the C
  call, followed by fixed-width integer/bool/float parameters and
  unit/integer/bool/float results. Stream and additional Host parameters are
  rejected by the shared checker. Aggregate, pointer, Option and variadic
  source ABIs are not admitted; declared mut parameters are refused.
  Internal scalar Option runtime returns are qualified only on x86-64 SysV.
- Copied Host transport refuses recursive/boxed and unsupported copied shapes,
  including None anywhere in a copied value graph (result, parameter, nested
  field, array or payload). Host/Stream `.cap` cannot be stored in lists,
  arrays or record/variant payloads. Domain wire types cannot be unit or `.cap`.
  These scalar tokens differ from the five pointer-backed I/O capability types.
- Managed class identity/storage is refused (`class type`); value records are
  supported. Computed assertion messages are refused (`assertion with a message
  value`), including before eliminating a constant-true assertion. Static
  literal assertion messages remain available.
- Direct sort admits integer/bool/float/str/bytes. Keyed sort admits a scalar
  or flat 1–8-field key of those kinds, with each field offset <=255. Other
  shapes are precise `sort of this element type`/`sort key type` refusals.

## Frontend, modules and entries

- S4 still owns persisted per-module Core interfaces/caches, incremental builds,
  the full Lox port and an EDA slice. Fresh module-headed source already uses
  the shared module loader, interfaces and merged whole-program checker; this
  is not a blanket refusal of valid user-module source. The nine propagation
  tests remain S4 execution exclusions. Seven flattened example coverage
  contexts retain E_MODULE_NAME failures. External Lox stored-view migrations
  at resolver.my:195/251/259 and heap.my:300 remain unapplied.
- Headerless source/test reads cap at 64MiB. The Core's module-project defaults
  cap at 16,384 modules, 262,144 import edges, 4MiB per source/embedded input and
  64MiB combined inputs. The standalone embed ceiling is 16MiB, but project
  budgets can be tighter. Core exposes no budget-override flag on this path.
- Function values have at most 16 parameters and name nongeneric free
  functions; mut record/array callback parameters are refused. Lambdas share
  the mut record/array restriction.
- Generic declarations have at most 16 type/const arguments and 16 combined
  requirements per parameter. Instance budgets are 4,096 per declaration;
  array shapes and callable signatures separately have 4,096 per spelling.
  Generic inference/body checking caps at depth256 and 100,000 operations.
- Nominal expansion caps at depth256 and 100,000 visits/operations. Layout
  expansion additionally caps at 4,096 instances and 4,096 array shapes per
  request. An individual display name caps at 1MiB; retained display names
  together cap at max(1MiB, source bytes).
- Main permits an optional first args:list[str], at most one of each capability,
  and separate optional out/err Streams. It returns int, None or
  Result[int/None,E] with printable E. Tests return bool or Result[bool,E]; other
  returns are unsupported in the ordinary test workflow.
- Two interior-mut refusals remain: `interior mut place changed while its index
  or key was evaluated` and `interior mut argument ancestor changed by a later
  interior write`. Executed whole-root mut arguments still supersede earlier
  captured interior publication; sibling/same-place and untaken writes follow
  the qualified COW-MUT-ARGUMENT-1 behavior.

## Text, values and bounded storage

- Text case conversion/classification preserves the old ASCII rules. Scalar
  indexing and valid UTF-8 behavior remain distinct from byte indexing.
  Non-ASCII lookup uses grouped continuation-bit counting and a cursor cache;
  the old runtime's sampled random-access index is not introduced.
- General split and immutable byte slices/views materialize owned values.
  Private whitespace-split dictionary-key loops may fuse only under exact
  compiler runtime authority and all-use/dominance checks. Escapes, stored
  lists, other consumers and phis retain materialization. Character scalar
  fusion likewise requires every use to be eligible literal equality or a
  disjoint append; other uses retain the ordinary implementation. Guarded
  ASCII paths retain Unicode/runtime fallbacks. There is no general source or
  parameter view ABI and no short-string representation.
- D2 dictionary projections are immediate-use only; storage/annotations fail
  with E_VIEW_STORED. Keys membership is a hash probe; values/items scan.
  Unreachable old stored-view machinery may remain until S5.
- Dictionary/set requested capacity stops at UINT32_MAX/2 slots and follows the
  allocation-failure path above it; geometric growth/address allocation can
  stop earlier. Mutable byte capacities/lengths use signed64, with allocation
  failure above INT64_MAX or when pushing from that length. Actual allocation
  limits are tighter.
- Numeric format width/precision caps at 4,095. Float parsing's 768 retained
  significant digits are a sticky rounding horizon, not a maximum input length;
  the parser continues validating the whole input.
- Rendering writes `...` beyond depth24, with transparent boxes not consuming
  depth. Equality and hashing use iterative traversal, without this rendering
  limit.

## Capabilities, providers and Host budgets

- Environment enumeration collects at most 64 distinct raw names before UTF-8
  filtering, with 128bytes/name in enumeration/in-memory provider validation.
  The built-in getter instead caps names at255bytes and values at16KiB.
  Allowlist grants filter that getter even without --restrict; opaque provider
  context never supplies names. Scoped Host names/endpoints cap at4096bytes.
- Scoped filesystem/network authority caps at eight roots/endpoints,
  256 provider handles, 64KiB transfers/snapshots, 256 snapshot entries and
  4094byte paths. In-memory stand-ins cap at256handles and64MiB backing.
  Runtime owners cap at1024open handles per filesystem/network family;
  read-all accumulation caps at64MiB. Deterministic tests use private directories
  and clock/entropy stand-ins; no qualification reads a real network.
- Host defaults are10,000calls,1,000,000work,65,536nodes,64levels and1MiB payload.
  Hard transport bounds are100,000nodes,128levels and64MiB payload. Packed
  fast-path fixed storage is limited to1MiB; copied payloads and descriptor
  headers are separate, so this is not a total scratch bound. Declared registry
  budgets remain enforced.

## Property testing and diagnostics

- Property defaults are100runs, ten times that discard budget and2000shrink
  attempts. Trial batches cap at4096inputs with a60second whole-batch timeout.
  The random-size schedule reaches100; random collections stop growing after
  4096nodes, and variant choices use minimal cases past depth12. Declared fixed
  arrays and mandatory record shapes remain intact, so these generation
  horizons are not hard graph maxima. Minimal-case recursion separately guards
  depths beyond24. Candidate lists cap at1024 and nested candidate lists at128.
  Batch drawing stops after reaching500,000nodes; the last complete input can
  cross that threshold. Class identities, constructor-only
  domains, function values and Host
  are nongeneratable under the existing contract. Every actual trial forks and
  resets its stand-ins.
- CLI property runs are1..1,000,000. Response files cap at64MiB; copied input
  text/bytes cap at4096 and trial transport at1,000,000words. These complement
  the batch/node budgets above.
- Error traces retain the origin plus the last32 propagation entries and note
  dropped entries. Native stack walks retain128PCs; DWARF inline chains cap at64.
  Ordinary trap/effect/inline-frame text caps at1023bytes, assertion/error-trace
  records at2047bytes, and ordinary trap detail/operation records at255bytes.
  Register-preserving compiler trace helpers do not suppress or delay events;
  ordinary foreign calls retain their C ABI.

## Frozen contracts and stage handoff

IR is frozen at dc1a5831. Record phis retain ownership; own.zig remains frozen.
Persisted formats remain module-interface-v5, check-summaries-v6 and mutation-v2.
Only explicit compiler runtime authority admits private fast paths; ordinary
extern names/signatures do not. Every fact/uniqueness optimization retains
verification of its premise. Core shard RSS caps at2.5GiB; measured Core rebuilds
must be <=10seconds, Core suites <300seconds and shards <90seconds.

The old compiler remains default until S5. No push or main merge is authorized.
The final S3 report stops for the user's S4 go/stop decision.
