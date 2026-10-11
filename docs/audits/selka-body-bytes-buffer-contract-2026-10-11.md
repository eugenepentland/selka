# B6 pure bytes, text and octet-buffer boundary

Status: the schema-6 byte/buffer producer and actual pure-library closure are integrated. Installed main qualification now passes 253 pure tests per mode, 443 normal/edit workflows with 1,772 comparisons, and 443 Debug-host release workflows with 886 comparisons. Earlier corrected library admission passes all 213 source operations and four forged replies. The latest full gate fails only because a repeated library run reuses an existing evidence directory; commit `8c58e7cb8` fixes that harness issue and the complete rerun is pending. B5 remains the last fully qualified boundary. B7 owns capability/resource entry closure. Reference remains the default; complete compiler bootstrap and the <=1.5x target are not established.

## Initial installed core evidence

Integration commit `e59f37c61` passes the plain Debug installation (14/14 steps),
the release-guest installed matrix (440 workflows, 880 comparisons, 30 warm
deployment checks and four live-session checks), 22 malformed requests,
92 forged-reply rejections and two expected publication failures. The matrix
reports zero failed or skipped cases. Formatting passes 20/20 steps with
987 live `.my` files and 204 deliberate exclusions. The native buffer selection
contains 11 named tests and seven unconditional test blocks, all passing.

The installed Debug host SHA256 is
`724a68c33d204c82dd900a4571e3d003979855f4cd29c72f60fe32a18cf33f17`.
The schema-6 body artifact SHA256 is
`c937729ed45b2bb0c1cbf8ee394262340dae98555a55a5b8cc91fc7c7fcfa80e`,
with content key
`314ee4d8a9f0fd6c80564044cba8d92649ea0be0858f50dee1064e4170f66b99`.
All seven package hashes and the unchanged qualified seed were verified. The
frozen B5 Debug installation was independently verified unchanged after install.
The [raw evidence inventory](evidence/selka-body-bytes-core-20261011/SHA256SUMS)
includes the complete installed report, identities and compressed command logs.

The normal/source-edit lane, ReleaseFast-host lane, full gate and actual compiler
helper-library admission are not established by this run. Compiler-library
follow-up still has exact negative-literal metadata differences and the largest
helper closure exhausts the logical value pool. These must be resolved without
discarding required typed rows or silently using native body checking.

## Concrete compiler dependencies

Actual production helpers, rather than strings containing parser test programs, require this closure:

- `body_check/graph.my:54`, `codec.my:21,53,126,135` and `scalars.my:31,34`: bounded raw byte slices, including omitted endpoints.
- `body_check/codec.my:138–160`, `checking.my:16–26`, `parser_pilot/syntax_codec.my:3–56`, `lexer_pilot/wire.my:19,312–318`: construct a byte_buffer from int[], append octets/ranges, reserve capacity and snapshot with bytes(buffer).
- `cache_plan/graph.my:49–54` and `incremental.my:199–204`: buffer construction and snapshots are used inside the algorithm, independently of its entrypoint.
- `declaration_index/codec.my:142–274` and `type_interface/codec.my:304–404`: mut buffer parameters, ordered encoding and immutable response snapshots.

These libraries can qualify in B6 without Filesystem, Stream or File. Every package executable still needs those capabilities: e.g. body_check/main.my:5–33, lexer_pilot/main.my:7–58, parser_pilot/full_adapter.my:50–51,131–140. Whole installed-package bootstrap is a B7 acceptance criterion, not a B6 claim.

## Exact native authority and lowering

`nominal_templates.zig:246` Index.addByteBuffer creates the builtin zero-argument buffer declaration, u8 element, copy/storable guarantees. `nominal_catalog.zig:358–368` materializes a managed byte-family schema with shape.buffer=u8 and nominal name byte_buffer. `typed.zig:434–445` distinguishes immutable bytes from the writable byte_buffer by the exact canonical name; matching the bytes family alone does not grant mutation.

`collection_lower.zig:24–38` preludeType lazily adds the builtin declaration and instantiates its schema at the original demand site. Therefore the retained Catalog.records prefix suffices to authenticate an existing buffer, but does not suffice to represent the first body-only buffer demand. Eagerly adding its schema in the common catalog would change native ID/order/site and is not proposed.

`sema_calls.zig:333–377` recognizes unshadowed byte_buffer(int[]), bytes(int[]) and bytes(byte_buffer). All emit typed .cast. The buffer constructor requires exactly the managed i64 list type. bytes(buffer) is an immutable snapshot, not a backing-storage alias. Call recognition respects local/function shadowing and canonical bytes authority. The producer must reproduce it from raw syntax/module facts, not an answered call table.

`sema_collections.zig:1049–1076` checks special in-place octet methods; `:1117–1143` preserves receiver read/write counts and mutability requirements. Closed B6 special operations are:

| Typed buffer kind | Arity | Input requirements | Output |
| --- | ---: | --- | --- |
| buffer_reserve | 1 | integer extra count | bool |
| buffer_append_byte | 1 | integer value | bool |
| buffer_append_range | 3 | byte-family source, integer start/end | bool |
| read | 1 | integer index | u8; existing widening cast gives source int |
| length | 0 | byte-family owner | i64 |
| slice | 2 | integer endpoints | same owner type |
| text_tail | 2 | string owner, integer endpoints | string owner type |

The special methods require the canonical mutable buffer. append_range accepts immutable bytes or another byte_buffer; neither receiver nor source may be substituted with an arbitrary list/text/nominal. Source operands are checked in native order. Preserve integer-width rules and original owner/whole-call diagnostic spans rather than assuming every integer operand is already i64.

Important native limitation: checkTextDictionary at `sema_collections.zig:983–985` rejects nondictionary .write/.get with E_TEXT_IMMUTABLE, even when the owner is byte_buffer. The actual compiler libraries append instead of indexed writes. The source method spelling buffer.write(...) is rejected earlier as E_LIST_METHOD; sema_places.fieldDestination at line 539 also rejects indexed buffer assignment as immutable byte-family storage (confirmed native regression). the lower-level nondictionary write branch also rejects. B6 preserves these refusals and tests the actual source spelling; it must not silently invent indexed-write semantics. Capacity is not admitted merely because the enum contains it.

`collection_lower.zig:317–326` textSlice roots the checked receiver once, emits a temporary initialize, chooses .text_tail only for string with omitted end, otherwise .slice, and supplies default start=0/end=length(owner). The final expression is .block_value. Bytes slices are octet-indexed; string slices are scalar-indexed. Runtime clamping/negative endpoints remain runtime semantics. Plain slice endpoints use this native lowering, not the list-index normalization helper. Stepped bytes slices are native source errors (`sema_collections.zig:725`); stepped text slices need a separately exact lowering before admission.

## Proposed schema 6 contract

Keep Input, full typed Batch, diagnostics, import usage and existing list/result/option recipe representation. Add one tagged recipe `.byte_buffer: {id,span}` without type arguments to the same globally ordered append delta. The predicted ID is base_count plus the recipe ordinal, with existing scalar offset rules. At most one canonical new buffer recipe is possible; reuse a retained canonical buffer ID instead. Retained schemas and new buffer schemas remain fully compared against an untouched native oracle and independently materialized fresh catalog.

Catalog stays seven fields. Extend grouped Templates with `byte_buffer: BufferBasis{available:bool,identity:?Sequence}`. Identity is projected only from the canonical common semantic builtin byte_buffer with managed byte family/u8 shape and dense exact record ID. Availability is true if Index.names resolves an exact builtin declaration of kind buffer/arity zero, or both Index.names and Index.syntax.aliases lack byte_buffer. `nominal_templates.zig:108` addBuiltin returns without adding when either table already contains that name. A user declaration or raw alias blocks addability; a local/function shadow controls individual call recognition separately in the producer. Identity must imply available and remain distinct from bytes/str. No per-use answer table is projected.

Extend project/added/apply observers to recognize a new canonical byte_buffer schema. apply invokes native preludeType solely to materialize the validated producer recipe, verifies ID/count/site and full retained prefix, and checks the observed recipe. No body type resolver is invoked by adoption. Recipe depth treats the argument-free builtin as one logical leaf. Bounds stay 64 MiB frame, 256 type depth, existing catalog/pool/edge/string budgets. Old schema 1–5 artifacts fail before selected reuse.

No new typed node/statement tags are required for the requested core closure: casts, local, initialize, buffer_operation and block_value already exist. Native validation gains canonical buffer policy, the narrow cast whitelist, closed buffer-op arity/operand/result rules, owned local IDs and source spans. It does not duplicate bounds evaluation, UTF-8 decoding or source overload decisions. Buffer mut parameters retain exact full Function/local origin/usage/policy metadata; ordinary copy and snapshot operations must not be treated as moves or Result consumption.

Optional conversion followup within B6, only if agreed: str.encode()->bytes and bytes.decode()->Result[str,str], through existing .encode/.decode and tagged Result recipe. These are distinct from bytes(buffer). Their exact result-order/site/UTF-8 diagnostics need their own parity evidence; they are not necessary to claim the append-only codec closure above. str(value) is scalar formatting, not an implicit arbitrary bytes decode.

## Ownership and refusal boundaries

Producer owns raw type/constructor/method recognition, source diagnostics, evaluation order, temporary/local append order, buffer alias/mut marker handling and new recipe choices. Native lane owns DTO/schema/structural admission and recipe materialization; root owns common projection/routing/cache identity and independent shadow catalog reconstruction. Probes owns authentic installed source/forgery qualification.

B6 continues explicit profile refusal for Filesystem/Stream/File, scoped resources/arenas, general capabilities, callbacks, user generics, contracts, dictionaries/sets and wider numeric/floating closure. Unsupported library byte vocabulary is not silently accepted through a generic enum switch. Invalid source operations within the admitted family must retain native E_BYTES_CONVERSION/E_COLLECTION_METHOD/E_IMMUTABLE/E_TEXT_IMMUTABLE diagnostics, not become arbitrary profile failures.

## Acceptance evidence before adoption claims

1. Pure producer tests and exact native/shadow typed batch, diagnostics, recipes and full catalog comparisons for slices with negative/omitted/clamped endpoints, UTF-8 scalar versus byte boundaries, expression receivers, side-effect ordering, buffer construction, all three special methods, mut parameters and aliases.
2. Immutable snapshots before/after mutation, COW aliases and independently retained source ranges remain byte-exact in normal/release/fact/leak modes. append_range self-overlap and foreign-source range bounds require runtime regression evidence.
3. Authenticated forged replies fail for wrong nominal buffer authority, duplicate/gapped/wrong-site buffer recipes, bad cast pairs, immutable mutation receivers, wrong op arity/result/argument types, foreign locals and damaged block graphs.
4. Compile/check the actual pure compiler helper closures and run their existing pure tests under selected component mode with native-body fallback disabled. Document the precise source roots admitted; do not assert all seven main functions are supported.
5. Package/identity schema bump, old-schema refusal, cold/warm/live replacement fail-closed and before-publication aggregate revalidation remain mandatory. Shadow must execute even warm.
6. Root runs isolated performance only after correctness gates. No performance estimate or <=1.5x assertion is inferred from this contract.

B7 subsequently admits capability signatures, file open/read, stream write/print and with-scope cleanup/effects, then independently builds/runs all seven actual packages and a second generation. Native catalog, symbolic generic checking, contract synthesized bodies, entry adaptation, effects/origins, domain codecs, warnings and backend are still explicitly retained seams after that bootstrap milestone. Full language selfhosting requires moving those semantic owners as well.

## Archived library preparation (2026-10-11)

[Preparation evidence](evidence/selka-body-library-preparation-20261011/README.md) retains native integration, strict runner registration/selfchecks, the body-only value-policy checks, and the producer's final measurement/profile receipt. The failed native-policy log is explicitly retained as resolved: 13 body tests passed before parser compilation failed; the separate corrected parser log records 15 passing tests. It is not counted as a passing gate.

The instrumented checking measurement reports 1,139,971 canonical occurrences (37,032,310 canonical bytes), motivating the body-only 2,097,152-value ceiling; its profile reply is measurement evidence, not successful installed admission. Parser/declaration/type-interface policy remains unchanged. Earlier failed logical measurement output is excluded. Deterministically compressed artifacts and SHA256SUMS preserve provenance.

Strict installed library admission remains pending: all 24 controls, nine actual library check roots, and six actual test roots require all 183 operations and exact selected parity. These preparatory results do not establish full component-source bootstrap or performance acceptance.

The first library followup installation at `6cbe600ef` passes 14/14 steps. Its admission attempt completes 120 fixture operations and six actual graph/codec checks, then stops at operation 127 on valid native unused-binding warnings from `body_check/checking.my`. The runner's zero-warning assumption is corrected while retaining exact selected warning equality. This incomplete run is archived as failure evidence, with installation identities; it is not the 183-operation acceptance result. Independent developer replay also found two remaining shadow metadata differences under investigation.

## Final library closure and gate integration

Implementation `848bfe678` adds exact nested assignment/iteration metadata, text and immutable-byte repetition, comprehension/list repetition hints, and complete iteration effect scans. Native admission authenticates canonical immutable join signatures and exact augmented-repetition operator demand sites. The final Debug install passes 14/14 steps; its host SHA256 is `106c74ea88a9c8817a1320e5cd0cd951bfe8f030dc5336bc6dc5afd7c4ee2138`, with schema-6 body artifact `f9b441269f2c56807e978d3eaaca2af005d4ab9de61bb834c53ee38945fa8703`. The matching ReleaseFast installation also passes 14/14 steps.

The strict selection now contains 30 controls (20 successful, ten exact diagnostics), 150 fixture operations and 63 actual-library/test operations, plus four separately accounted join forgeries. The final installed attempt completes all 213 source operations with exact selected parity, including release/facts/leak tests, before the first forgery hits an overly narrow rendering assertion. The reply was rejected with status 2; native diagnostic-v1 renders ComponentProtocol as a legacy test-index message. Commit `167828d28` matches that exact object and rejects unrelated host failures. All four retained mutations then pass an independent developer replay. This does not retroactively turn the incomplete installed attempt into a passing gate.

The first full-gate attempt is stopped after exposing stale schema expectations, relative CLI paths and donor formatting, plus two environment/cache issues. Commit `6ad3d0fbc` fixes the repository integration; empty historical cache directories are removed so Zig rebuilds their missing executables, and subsequent gates use the physical temporary-directory path. Six native/selected fixture checks, 61 harness selftests and the nine primer documentation examples pass. The final main matrix, complete corrected library gate, full repository gate and new performance measurement remain pending.

[Library closure evidence](evidence/selka-body-library-admission-20261011/README.md) preserves the incomplete attempts, installation identities, focused tests, exact developer replays and environment repair receipts with checksums. No component-source bootstrap or full-language performance claim follows from these records.

The final ReleaseFast-host release/facts/leak matrix passes **443 workflows and 886 comparisons**, 30 warm deployments, four live sessions, 22 malformed requests, 92 forged rejections and two publication failures. Host SHA256 is `dc39e088da6dbbe686bc50206da98729ddf21def02febec61d74bb179a41ab4c`. A second full-gate attempt is stopped on stale native-test compile manifests; both missing executables are then regenerated by invalidating just those manifests (16/16 compile steps). Full corrected qualification is still pending, and both stopped logs remain explicit failures.

The repaired native support/memory and formatting gate passes: **17/17 native tests**, all live `.my` formatting, and formatter selfchecks. This verifies both regenerated test executables before the next full gate.

The next full-gate attempt passes the bootstrap-containing CLI shard's 43 tests but fails its old 2 GiB RSS declaration: the uncached enlarged body component rebuild peaks at **2,345,099,264 bytes**. The CLI shard scheduling reservation is raised to 2.5 GiB, matching the existing whole-root and component-driver bounds. This stopped attempt remains failed evidence; transport/runtime limits are unchanged and a complete rerun remains required.

The fourth full gate completes with one failed action: **133/136 steps**, 820 native tests passed, zero native failures, and 5,642 other-shard skips; `fmt-check` passes. The corrected strict library lane is now green: **213 source operations plus four exact join-forgery rejections**, bound to the final Debug host and schema-6 package identities above. The main matrix fails during its private implementation-edit rebuild, before it can publish a complete normal/edit receipt or start its Debug release lane. Isolated process tracing reproduces the failure as **SIGXFSZ** at the inherited 64 MiB file-size limit. This is retained as a failed full gate; the coordinator-only file-budget repair and complete rerun remain pending.

Commit `84b097ff7` separates the coordinator compiler-file allowance (128 MiB) from captured output (unchanged 64 MiB plus framing), preserving stricter inherited limits and the existing 4 GiB coordinator address-space bound. The traced isolated rebuild now succeeds and changes only the body artifact; the six other packages remain identical. Its process high-water RSS is 2,266,428 KiB. This traced run deliberately omits the workflow matrix and is not performance evidence. Forty-four frontend/body/library harness selfchecks and all 88 Guardian checks pass. The previous failing trace, successful trace, raw command results and scripts are retained. Complete corrected normal/edit and Debug release qualification still require the next full gate.

The fifth full gate verifies the compiler-file repair: all **253 pure tests per mode** and both installed main matrices pass (**443 workflows / 1,772 comparisons** normal/edit, **443 / 886** Debug-host release/facts/leaks). Both matrices retain 30 warm deployments, four live sessions, 22 malformed requests, 92 forged replies and two publication failures, with zero failed/skipped cases. The complete repository attempt still exits 1: **133/136 steps**, 816 native passes and 5,642 other-shard skips. Its sole failed action is repeated library admission, which completes its 213 source operations but cannot create the previous invocation's retained join-evidence directory. This failed attempt and both successful main receipts are preserved separately. Commit `8c58e7cb8` reserves a fresh evidence directory per invocation, preserving earlier payloads; eight library harness selfchecks and all 88 Guardian checks pass. A complete repeat-safe gate remains required before B6 qualification closes.
