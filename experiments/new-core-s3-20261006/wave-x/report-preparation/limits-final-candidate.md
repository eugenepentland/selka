# S3 remaining implementation limits

This inventory distinguishes source admission limits, runtime budgets,
optimization fallbacks and work reserved for S4. The final exit report must
identify the frozen source and the executions that qualify it. This preparation
does not claim that S3-X has passed or that the final source is frozen.

The supporting source audit is [exit-limit-audit.md](exit-limit-audit.md).
Historical package identities, receipts and coverage context are retained in
[exit-report-preparation.md](exit-report-preparation.md).

## Target and representation

- Qualification targets x86-64 Linux with AVX2, the SysV ABI, native CPU code
  generation and the current 47-bit user-address-space assumption. The fact
  pass uses the corresponding `2^47` list-length bound; actual address and
  allocation limits are tighter. `--generic-vectors` changes vector lowering
  on that platform and does not qualify another platform. See
  [target.zig](../../../../src/core/target.zig).
- Aggregate parameters must occupy a function's first 64 parameter positions
  (`E_PARAMETER_POSITION`). Scalar positions have no corresponding 64-position
  restriction. Register versus indirect aggregate passing and stack promotion
  have ordinary fallback paths. Four register words, a five-step packed field
  path and the 4,096-byte stack-promotion ceiling are optimization boundaries,
  rather than additional source admission limits.
- Concrete fixed-array lengths must fit `u32`. Generic const lengths separately
  stop at 1,048,576 elements; ordinary concrete syntax follows the frontend's
  host index/storage range before Core mapping. Whole rebinding of a `mut`
  fixed-array parameter is checker-refused; element writes and copying into a
  local remain available. See
  [generic_lengths.zig](../../../../src/generic_lengths.zig),
  [generic_arrays.zig](../../../../src/generic_arrays.zig) and
  [build.zig](../../../../src/core/build.zig).

## Source admission and foreign boundaries

- Source `extern` requires a first `Host` authority argument, erased from the
  C call, followed by fixed-width integer, bool or float parameters. Results
  are unit, integer, bool or float; float crosses as C `double`. The shared
  checker rejects `Stream` and additional `Host` parameters. General pointer,
  aggregate, `Option` and variadic source ABIs are not admitted, and declared
  `mut` parameters are refused. Internal scalar `Option` runtime returns are
  qualified only on x86-64 SysV; they do not extend this source contract. See
  [c_abi.zig](../../../../src/c_abi.zig),
  [sema.zig](../../../../src/sema.zig) and
  [Core C ABI lowering](../../../../src/core/c_abi.zig).
- Copied Host signatures reject recursive/boxed values and unsupported copied
  shapes, including `None` anywhere in a copied value graph: result, parameter,
  nested field, array element or variant payload. Immutable `bytes` is allowed
  as a boundary payload, while bytes nested inside a larger copied graph is
  rejected. Ordinary source Unit storage and rendering remain available;
  their physical placeholders do not create a Host ABI. See
  [data_type.zig](../../../../src/data_type.zig) and
  [build_host.zig](../../../../src/core/build_host.zig).
- Host/Stream `.cap` tokens cannot be stored in lists, fixed arrays or
  record/variant payloads. A domain's mapped wire type cannot be unit or `.cap`.
  These scalar tokens differ from the five pointer-backed Clock, Entropy,
  Filesystem, Network and Environment capability families. These type guards
  must not be counted as new observed corpus refusals when the shared checker
  already rejects the source combination. `Entropy` is the Python spelling
  of `random_cap`; see [docs/io.md](../../../../docs/io.md).
- Managed class identity/storage is refused with `class type`; value records
  are supported. Computed assertion messages are refused with
  `assertion with a message value`, including before eliminating a
  constant-true assertion. Static literal assertion messages remain available.
  See [build.zig](../../../../src/core/build.zig).
- Direct sort admits integer, bool, float, str and bytes elements. Keyed sort
  admits a scalar or flat 1–8-field key of those kinds, with each field offset
  at most 255. Other shapes have the precise `sort of this element type` or
  `sort key type` refusal. See
  [build_fn.zig](../../../../src/core/build_fn.zig).
- Two interior-mut refusals remain:
  `interior mut place changed while its index or key was evaluated` and
  `interior mut argument ancestor changed by a later interior write`.
  Executed whole-root mut arguments supersede earlier captured interior
  publication; sibling/same-place and untaken writes follow
  `COW-MUT-ARGUMENT-1`. Deeper publication protocols were not inferred from
  callee effects or value equality. See
  [build_capture.zig](../../../../src/core/build_capture.zig) and the
  [M package report](../../wave-b/s3-m/REPORT.md).

## Shared frontend budgets and entry contracts

- Headerless source/test reads cap at 64 MiB. Core's module-project defaults
  are 16,384 modules, 262,144 import edges, 4 MiB per source/embedded input and
  64 MiB combined source/embedded bytes. The standalone embed ceiling is
  16 MiB, but project budgets can be tighter. The current Core path supplies
  default project options and exposes no budget-override flag. See
  [frontend.zig](../../../../src/core/frontend.zig),
  [project.zig](../../../../src/project.zig) and
  [embed.zig](../../../../src/embed.zig).
- Function values have at most 16 parameters. A named function used as a value
  must be a nongeneric free function. Callback values and lambdas cannot have
  `mut` record/fixed-array parameters; such functions remain directly callable.
  See [callables.zig](../../../../src/callables.zig),
  [sema_calls.zig](../../../../src/sema_calls.zig) and
  [sema_expressions.zig](../../../../src/sema_expressions.zig).
- Generic declarations have at most 16 type/const arguments and 16 combined
  requirements per parameter. Instantiation budgets are 4,096 per generic
  declaration. Array shapes and callable signatures separately have 4,096
  specializations per source spelling. Generic inference and generic body
  checking stop at depth 256 or 100,000 checking operations. See
  [generic_requirements.zig](../../../../src/generic_requirements.zig),
  [generic_instances.zig](../../../../src/generic_instances.zig),
  [type_catalog.zig](../../../../src/type_catalog.zig),
  [generic_inference.zig](../../../../src/generic_inference.zig) and
  [generic_bodies.zig](../../../../src/generic_bodies.zig).
- Nominal expression expansion stops at depth 256 or 100,000 visits. Nominal
  layout expansion has per-request ceilings of 100,000 operations, 4,096
  instances and 4,096 array shapes, plus depth 256. Nominal argument shapes
  also stop at depth 256. Each display name is at most 1 MiB; retained names
  together are bounded by `max(1 MiB, source bytes)`, rather than a fixed
  program-wide 1 MiB ceiling. See
  [nominal_templates.zig](../../../../src/nominal_templates.zig),
  [nominal_layouts.zig](../../../../src/nominal_layouts.zig),
  [nominal_state.zig](../../../../src/nominal_state.zig) and
  [nominal_catalog.zig](../../../../src/nominal_catalog.zig).
- Main permits an optional first `args: list[str]`, followed by at most one
  parameter of each capability family and separate optional `out` and `err`
  Streams. It returns int, None or `Result[int/None, E]` with printable E.
  Tests return bool or `Result[bool, E]`; other results are unsupported in the
  ordinary test workflow. The checked entry adapter, rather than manual IR
  entry restrictions, defines the source-main contract. See
  [sema.zig](../../../../src/sema.zig),
  [entry_adapter.zig](../../../../src/entry_adapter.zig) and
  [test_runner.zig](../../../../src/core/test_runner.zig).

## Text, values and optimization fallbacks

- Text case conversion and classification preserve the old ASCII rules.
  Scalar indexing and valid UTF-8 behavior remain distinct from byte indexing.
  Non-ASCII lookup uses grouped continuation-bit counting and a cursor cache;
  the old runtime's sampled random-access index is not introduced. See
  [core_text.c](../../../../src/core/runtime/core_text.c).
- General split and immutable byte slices/views materialize owned values.
  Private whitespace-split dictionary-key loops can fuse only under exact
  compiler runtime authority and all-use/dominance checks. Escapes, stored
  lists, other consumers and phis retain materialization. Trusted whitespace
  cursors use bounded byte loops, including negative-offset guards; ordinary
  extern declarations retain their C call. See
  [fuse_text_split.zig](../../../../src/core/fuse_text_split.zig) and
  [emit_text_split.zig](../../../../src/core/emit_text_split.zig).
- Character scalar fusion requires every use to be eligible equality with a
  valid single-scalar literal or a disjoint append. Other consumers, escapes
  and phis retain the ordinary implementation. The producer retains its exact
  located bounds check; guarded ASCII lowering keeps Unicode/runtime fallback
  behavior. There is no general source/parameter view ABI or short-string
  representation. See
  [fuse_text_scalar.zig](../../../../src/core/fuse_text_scalar.zig),
  [emit_text.zig](../../../../src/core/emit_text.zig) and the
  [character package report](../../wave-c/s3-char/REPORT.md).
- D2 dictionary projections are immediate-use only. Storage and annotations
  fail with `E_VIEW_STORED`; snapshots require materialization. Keys membership
  uses a hash probe, while values/items membership scans. Unreachable old
  stored-view machinery may remain until S5.
- Dictionary/set requested capacity stops at `UINT32_MAX / 2`
  (2,147,483,647 entry slots) and follows the allocation-failure path above it.
  Geometric growth and address allocation can stop earlier. Mutable byte
  capacity/length use signed 64-bit storage; initial capacity above `INT64_MAX`
  and pushing from that length fail allocation. Actual allocation limits are
  tighter. See [core_dict.c](../../../../src/core/runtime/core_dict.c) and
  [core_bytes.c](../../../../src/core/runtime/core_bytes.c).
- Numeric format width and precision cap at 4,095. Float parsing retains 768
  significant digits as a sticky rounding horizon and continues validating
  the whole input; 768 is not a maximum accepted input length. See
  [format_spec.zig](../../../../src/format_spec.zig),
  [core_number_format.zig](../../../../src/core/runtime/core_number_format.zig)
  and [core_number_parse.zig](../../../../src/core/runtime/core_number_parse.zig).
- Rendering writes `...` beyond depth 24. Transparent boxes do not consume
  depth. Equality and hashing traverse iteratively and do not share this
  rendering-depth limit. See
  [core_values.c](../../../../src/core/runtime/core_values.c).

## Capability, provider and Host runtime budgets

- Environment enumeration collects at most 64 distinct raw names before
  UTF-8 filtering. Enumeration and in-memory provider validation allow
  128 bytes per name; the built-in getter instead allows 255-byte names and
  16 KiB values. Explicit allowlist grants filter the getter even without
  `--restrict`. Opaque provider context never supplies names. Scoped Host
  authority names/endpoints cap at 4,096 bytes. See
  [core_io.c](../../../../src/core/runtime/core_io.c).
- Scoped filesystem/network authority allows eight roots/endpoints,
  256 provider handles, 64 KiB transfers/snapshots, 256 snapshot entries and
  4,094-byte paths. In-memory stand-ins allow 256 handles and 64 MiB backing,
  with the same path/snapshot bounds. Runtime owners allow 1,024 open handles
  per filesystem/network family. Read-all accumulation stops at 64 MiB.
  Deterministic qualification uses private directories and clock/entropy
  stand-ins, without a real network. See
  [core_io.c](../../../../src/core/runtime/core_io.c).
- Host defaults are 10,000 calls, 1,000,000 work, 65,536 nodes, 64 levels and
  1 MiB payload. Hard registry transport ceilings are 100,000 nodes, 128 levels
  and 64 MiB payload; declared registry budgets remain enforced. Packed
  fast-path eligibility limits fixed argument/result storage to 1 MiB.
  Copied byte payloads and descriptor headers are separate, so this is not a
  total scratch bound. Other copied shapes use the ordinary adapter where
  supported. See [core_host.c](../../../../src/core/runtime/core_host.c).

## Property testing and diagnostics

- Property defaults are 100 runs, a discard budget ten times the requested
  runs and 2,000 shrink attempts. Trial batches contain at most 4,096 inputs,
  with the current 60-second whole-batch timeout. Every actual trial forks and
  resets its stand-ins. CLI property runs are restricted to 1–1,000,000. See
  [test_runner_property.zig](../../../../src/core/test_runner_property.zig),
  [property_execute.zig](../../../../src/core/property_execute.zig) and
  [main.zig](../../../../src/core/main.zig).
- The random-size schedule reaches 100. Random collections stop growing after
  4,096 generated nodes, and variant choices use minimal cases past depth 12.
  Declared fixed arrays and mandatory record shapes remain intact, so these
  generation horizons are not hard graph maxima. Minimal-case recursion
  separately rejects depths beyond 24. Candidate lists contain at most 1,024
  entries and nested candidate lists at most 128. Batch drawing stops after
  reaching 500,000 nodes; the last complete input can cross that threshold.
  Class identities, constructor-only domains, function values and Host are
  nongeneratable under the existing contract. See
  [property_generate.zig](../../../../src/core/property_generate.zig),
  [property_shrink.zig](../../../../src/core/property_shrink.zig) and
  [property_types.zig](../../../../src/core/property_types.zig).
- Response files cap at 64 MiB. Copied property input text/bytes cap at 4,096
  scalar/byte elements, respectively. Each trial transport is limited to
  1,000,000 words. These reader limits apply separately from generation and
  batch-drawing thresholds. See
  [property_execute.zig](../../../../src/core/property_execute.zig) and
  [core_test.c](../../../../src/core/runtime/core_test.c).
- Error traces retain the origin plus the last 32 propagation entries and
  note dropped entries. Native stack walks retain 128 PCs; DWARF inline chains
  cap at 64. Ordinary trap/effect/inline-frame text caps at 1,023 bytes,
  assertion/error-trace records at 2,047 bytes, and ordinary trap
  detail/operation records at 255 bytes. Compiler-owned trace helpers use the
  register-preserving `preserve_most` ABI and record events at their original
  points; ordinary foreign calls retain their C ABI. See
  [core_rt.c](../../../../src/core/runtime/core_rt.c) and
  [emit_llvm.zig](../../../../src/core/emit_llvm.zig).

## Modules, coverage context and S4 work

Fresh module-headed source already uses the shared loader, interfaces and
merged whole-program checker. S4 owns persisted per-module Core interfaces,
`.myi`/Core IR caches, incremental builds, the full Lox port and an EDA slice.
Existing merged-source module loading must not be described as a blanket
refusal of valid user modules. See
[frontend.zig](../../../../src/core/frontend.zig).

The nine propagation tests in `tests/lang/migrated/propagation.my`, importing
`propagation_case_1` through `_9`, remain named S4 execution exclusions.
N6 separately excludes 118 retired arena cases. Entire retired modules include
`arena_class_escape`, `arena_managed`, `arena_regions`, `arena_scopes` and
`rc_arena_values`; additional individual arena cases occur elsewhere. The exact
[127-name inventory](../../wave-b/integration/resume-exceptions-run01.json)
records all 118 arena and nine S4 names.

The coverage preparation retains seven flattened example `E_MODULE_NAME`
failures: `examples/corpus/invoice/{catalog,money,pricing}.my`,
`examples/interface-files/shop/{billing,money}.my`,
`examples/input-values/config/values.my` and
`examples/modules/shared/units.my`. They are coverage-context failures, not
executed successes or proof that valid user-module source is unsupported.
External Lox stored-view migrations at `resolver.my:195/251/259` and
`heap.my:300` remain unapplied.

The historical coverage refusal set contains six bodyless declarations:
extern `abs`, `floor`, `main::runtime_bench_now`, and Host `io::length`,
`io::byte`, `io::put`. Repeated imports produce eleven raw occurrences.
Standalone declaration-body refusal does not mean linked calls are unsupported;
provider fixtures and benchmarks exercise those calls. Final coverage results
must retain their own source and asset/context accounting, rather than
relabeling these historical receipts.

## Frozen contracts and stage handoff

IR remains frozen at `dc1a5831`; record phis retain ownership and `own.zig`
remains frozen. Persisted formats remain `module-interface-v5`,
`check-summaries-v6` and `mutation-v2`. Only explicit compiler runtime authority
admits private fast paths; ordinary extern names, signatures and marker strings
confer no authority. Fact and uniqueness optimizations retain verification of
their premises in verify mode.

Core test-run RSS must stay below 2.5 GiB. Measured uncontended Core rebuilds
must be at most 10 seconds, Core suites below 300 seconds and individual shards
below 90 seconds. A successful command or build summary does not replace exact
shard-verdict and RSS inspection. These are qualification budgets, not source
admission limits.

The old compiler remains default until S5. No push or main merge is authorized.
The final S3 report stops for the user's S4 go/stop decision.
