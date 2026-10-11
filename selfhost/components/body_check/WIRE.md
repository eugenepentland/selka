# Scalar body-check batch B1

B1 transfers body checking for every admitted ordinary function to a qualified Selka process. Native catalog construction, entry checks/adaptation, effects/origin/mutation passes, domain codecs and final warnings remain explicit host stages. Unsupported syntax produces a located profile refusal; selected modes never fall back to native body checking. Reference remains the default.

## Framing

The 64-byte outer frame is `SLKBCK01`, little-endian u32 protocol/schema `1/1`, direction `0` request or `1` reply, payload byte length at offset20, nonce8 at24 and request payload SHA256 at32. A reply echoes bytes24..64 exactly. Both complete frames are at most64MiB. Payloads are named postorder logical tables under `SLKBKI01`/`SLKBKR01`, using the existing parser value kinds0null,1signedi64,2bool,3bytes,4enum-tag,5namedrecord,6list,7taggedunion. Payload header contains value count and final root ID. References must point backward; duplicate/unknown fields, malformed tags, trailing bytes and correlation mismatches are host protocol failures.

## Request

`Input{context,program,modules}` has raw full AST `program` with the existing parser schema. Context is `{path,source,trusted_intrinsics,entry_required}`. Module is `{context,offset,imports,symbols,import_used}`. Its context/import/symbol fields use declaration DTOs unchanged; offset maps original bytes into merged source. Initial import flags are copied before any native shadow oracle mutates project state. The producer enumerates raw functions; the host supplies neither a typed catalog nor a body worklist.

## Reply

Outcome tags are `success`, `failure` and `profile`.

Success is `Output{batch,import_used,diagnostics}`. Batch is `{nodes,statements,functions,ranges}`, preserving all `typed.Node`, `typed.Statement` and `typed.Function` logical fields and stable append order. Ranges contain `{nodes:{start,end},statements:{start,end}}` per raw function, in declaration order. They form exact contiguous partitions and assign even unreachable intermediate rows to one lexical local table. Calls reference global function IDs; local IDs belong only to their owning function. Type IDs use builtins i64=0, bool=1 and Unit=15. Scalar integer literals use signedi64 wire values widened to native i128; B1 cannot encode wider integers.

The retained native catalog and entry phases may observe additional import uses
after the raw request snapshot. Before adopting or comparing successful bodies,
the host copies the producer flags and merges those common-phase observations.
Shadow captures this common state before native body checking, so missing
producer body observations still cause a mismatch. Neither the reply nor its
authenticated input snapshot is mutated.

Source failure is the complete ordered diagnostic array. Profile is `{code:"P_BODY_PROFILE",span,message}` and maps to host `ComponentProfile`. Diagnostic elements use the existing six-field SyntaxDiagnostic schema, including related/origin/requirement notes and structured fixes. Runtime traces or checker obligation pointers are rejected during oracle projection, never silently dropped.

## Bounds and validation

Sources:1MiB per original module,8MiB aggregate originals,4096modules,16KiB top-level path; merged source permits4096delimiter bytes beyond8MiB. AST and typed node/statement tables:262144each; functions and aggregate locals:65536. Logical transport:1048576values,4194304edges, depth256 and512MiB decoded allocation budget. These independent ceilings may reject a graph before its table cap. Graph validation uses at most4194304scheduled work entries and rejects cycles, cross-function node/statement/local references, incompatible scalar payload types, invalid call permutations, missing functions, bad declaration association, invalid parameter metadata, malformed range partitions and out-of-source spans. Failure diagnostics require at least one error; success diagnostics contain no errors. Initial true import flags cannot be cleared.

Validation is structural, not a second body/type checker. Semantic completeness comes from the authenticated producer and qualification against the native oracle. Shadow compares the entire canonical typed batch, all metadata/ranges, ordered diagnostics and import flags. Selected modes disable body semantic/specialization reuse. Aggregate frontend identity must be revalidated before either successful program or diagnostic publication. Adopted batch and diagnostics own caller-arena storage independently of the captured reply.
