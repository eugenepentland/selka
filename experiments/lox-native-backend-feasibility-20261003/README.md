# Native V2 backend selection: read-only feasibility

Recommend an explicit, versioned frontend emission policy, **original by
default**, rather than a downstream pass that trusts proof comments. A resolved
QBE native build can select the existing reviewed V2 emitter; LLVM selects the
original emitter. This keeps the ownership proof at the checked typed emitter
and adds no authority derived from external IL. This is an implementation
proposal, not an implemented or qualified compiler. No compiler build, guest
test or performance command was run for this assessment.

`analysis.json` and `raw.json.gz` bind 37 inspected production files to selected
core `3b33df52044a10cb84b908f8b1641af439e8c729`, all 37 selected AST port files,
selected d14/99ad tools and selected RC guests, and the 12 frozen native-V2
files from commit `9ab993c1b9e2088c471ea1b57c98361b8554d0ae`. All checked source
and tool identities matched before and after. The selected source directory is
`/home/epentland/ai/canopy/mylang-worktrees/codex-lox-parity-20261003/.tmp-lox-round3/ast`.
The retained V2 descriptor is
`/home/epentland/ai/canopy/mylang-worktrees/codex-lox-native-case-glue-20261003/.tmp-lox-native-case-20261003/proof-v2.json`
(SHA256 `33dc940cb303d78bc5556009e63f932b041458107234e1248fc04d64f952632a`).
Neither frozen trial nor selected core/source was modified.

## Explicit policy path

Use a small enum such as `original` / `qbe_native_variant_v2`, with `original`
as every public API's default. These are proposed names, not current flags.
They select equivalent checked ownership implementations; they do not change
step/frame accounting, COW, runtime selection, type schemas or opcode behavior.

| Path | Current API and required propagation |
| --- | --- |
| Whole native build | `qbe_build.prepare` resolves `qbe_build_backend.resolve` before emission; carry policy from `Prepared.cache.codegen.llvm` (or the same resolved backend result) into `frontendSwitches` and the frontend child. `emissionSwitches(parsed)` currently carries only debug/step/frame switches. |
| Whole frontend | `main.Parsed.emissionPolicy` → `main.emitMeasuredNative` → `compiler.Compilation.emitQbeWithOptions`, or the project path `project_compile.Compilation.emitQbeWithOptions` → `native_interface.Policy` → `qbe.generateWithInterface`. |
| Native emitter | Add the defaulted field to `EmitPass`, pass it in `emitFunction` to `Emitter`, and preserve it for appended borrowed units. V2 `admitted` must return null when policy is original **before** any print, `temp`, layout/shape query or new root/call. Keep its existing RC-enabled/non-counting and physical proof refusals. |
| Per-module build | `module_build.Session.open` already prepares the effective backend; incorporate the policy in its switches before selecting project and standard variants, then in `Build.start`'s `compile-module` argv. `module_compile_command.Options.config` → `module_compile.Request.config` → constructed `native_interface.Policy` must agree. |
| Raw API/CLI emission | Default `qbe.generate*`, raw `emit-qbe`/`emit-project-qbe`, direct `compile-module`, check-only compilation, interpreter `run` and embedding callers stay original unless they explicitly request the checked optimization policy. An internal frontend spelling must validate its enum and permitted emission commands; it is not an unchecked permission or an authenticating secret. |

The early policy refusal is stronger than relying on LLVM to optimize away V2
branches. It leaves all original temporary/label numbers, helper calls, failure
blocks, region reads and declaration queries unchanged. Merely hiding the new
branches in LLVM after emitting them does not establish this property.

The actual backend mapping must be:

| Effective backend/input | Policy and failure behavior |
| --- | --- |
| Auto/default or explicit real QBE, either Debug or ReleaseFast | V2 policy; ordinary native RC may admit a proof. Mode alone never selects LLVM. |
| Explicit LLVM, including `--release` | Original policy. |
| `--qbe .../qbe_llvm.py` | Original policy: `qbe_build_backend.legacyLlvm` recognizes the basename and `resolveQbe` returns `name=llvm`; it does not resolve or execute that adapter file. Inspect `cache.codegen.llvm` after resolution, not `parsed.codegen == .qbe`. |
| GC / native GC stress / RC counting | Keep the existing V2 admission refusal and complete original helper behavior, regardless of the recorded policy. Do not weaken those refusals to align caches. |
| Backend resolution fails | Preserve status2/NativeToolFailed before emission; no inferred QBE policy or optimization fallback. |
| Unknown/duplicate policy or invalid command | Parser refusal, not silently enabling a default. A native build derives policy from its backend rather than accepting an arbitrary user override to a backend decision. |

## Cache and imported module boundaries

These policy-dependent identities all need explicit coverage; changing only an
object key leaves cached frontend output capable of answering the wrong request.

- `qbe_fragments.Flags`, `qbe.flagsOf` and `Keys.local`: include a versioned
  enabled-policy token before the first pass is emitted. Its second-pass/unit
  digest then naturally includes the chosen IL. Default/original can retain the
  existing canonical encoding. Both fresh and fragment-reused emission need
  coverage; compiler identity partitions older compiler stores independently.
- `main.manifestReplayTicket`: partition both replay slot and key by the policy
  before `replayManifest`, not just after parsing the returned manifest.
  Currently this explicit switch list covers debug/step/frame/lean/executable,
  runtime and value semantics, but has no backend policy. Both cold→warm
  QBE→LLVM and LLVM→QBE sequences must miss the opposite policy.
- `module_interface.EmissionConfig` / `configName`: carry the policy in the
  configuration string; enabled gets a distinct versioned token, original
  retains its old spelling. `emissionHash` already hashes that string.
  `module_compile.importedFacts` explicitly refuses a mismatched config with
  `MissingEmission`; transitive physical dependencies also filter by config.
  Preserve refusal/recompile for old or opposite-policy interfaces, including
  standard modules, rather than silently importing their emitted facts.
- `module_build.variantDirectory`: hash the policy in the project and standard
  variant switches in addition to the backend-dependent environment. This also
  covers `compile-module --ready` announcements and module object reuse. A
  check-only variant can retain original policy because it emits no unit.
- Native object keys already include `lean.digest` of exact IL plus environment
  (`driver_identity`, runtime/tool/target/backend/mode) and the contract.
  V2/original identical IL may reuse an identical object safely, but changed
  IL cannot. Native build no-op receipts already key manifest bytes and the
  driver environment. The module link identity must bind the policy/config
  through its actual unit/object keys; assertions should verify that chain.

`build --manifest-file`, `module-objects`, `qbe_build.assemble` and standalone
`link-modules` consume supplied IL without invoking the source frontend. Under
the recommended route they do **no new transformation or proof admission**:
the given instructions remain the instructions compiled. There is no new
certificate parser and no JSON producer field can enable unsafe copy/clear.
An external file does not select a frontend replay ticket. An externally
provided QBE-V2 manifest intentionally compiled with LLVM is outside the claim
that LLVM builds *from checked source under original policy* match selected
LLVM bytes; do not report that different input as an equivalence failure or a
qualified default LLVM build. Unknown manifests keep current ABI/contract
validation and complete provided helper sequences.

`MYLANG_HOST_COMPILER` already selects the whole-source build's frontend child;
the new policy must be passed explicitly there. A foreign producer may reject
an unknown internal flag; preserve its failure and original call protocol,
without treating its identity strings as a proof certificate. The explicit
policy route adds no borrowed/copy authority from that child's comments.

## Accounted native tests and source-directory runs

Do not validate only unaccounted executable builds. Native tests exercise three
distinct frontend paths, and all must select policy from effective backend:

- `native_test_session.check`: the full `emit-project-qbe` fallback must append
  the emission policy to that child, without sending it to declaration-only
  `list-interfaces` / `native-test-graph` commands.
- `native_test_session.Compile.begin` starts `native-test-compile` and retains a
  checked compilation. Currently `main.nativeTestCompileSession` takes no
  policy, and `project_compile.emitQbeSelected` constructs an Interface with
  default policy. Add an explicit/defaulted policy path through that session
  and the selected emission API; preserve existing accounted step/frame
  settings. The returned selected manifest is consumed by the test library
  build using `--manifest-file`, so selecting policy only in that later build
  is too late.
- `native_test_command.openModuleTests` constructs QBE library settings and
  uses `module_build.openTests`; include the same policy in its module config
  and variant path. `--release` already avoids the ordinary QBE module-test
  path, while the legacy adapter may still enter with parsed `.qbe`; resolve
  before selecting a policy here too.

`native_test_session.initFrontend` deliberately resolves no tools. Keep its
policy original until native tools are actually resolved; do not guess from
ReleaseFast mode. `Session.init` currently stamps Zig and the QBE path and test
result keys include release, mode, tools and environment. Add the effective
emission policy to test library/query/result keys where they can affect
executed code; preserve semantic graph reuse when it has no emitted IL.
Directory fan-out in `native_test_directory.argv` already forwards `--qbe`,
`--release`, mode and runtime controls. Each child should derive the same
resolved policy; no directory-only default may erase it. Provider variants,
whole-program fallback, cold module seeding and `--no-cache` also need coverage.

## Why metadata is a larger alternative

Backend-independent comments could carry a bounded plan at the unchanged
take/drop/unloan helper sites. `qbe_build_units.text` retrieves inline or
BLAKE3-verified lean IL; `MemberTexts.next` is the QBE batch-miss interception
point before `batch.stage`/`sectioned` write each file. The single-object
`qbe_build_cache.prepare(.qbe)` path would also need consistent coverage. LLVM
uses a different `compileUnits`/`qbe_build_llvm_compile` path. A pass must preserve
the entire slow call/status/failure sequence, choose collision-free new SSA
and block names, and rerun QBE size admission on expanded text.

The exact V2 plan admits at most eight cases/fields and four edge-free tags;
take requires the current/live **SSA region** with unsigned-word
`region <= heap.region_depth`, and overlap checks unless the existing completed
owned private-buffer proof applies. Release has no region. Preserve whole blit
then complete source clear for take and complete clear for release. All unknown
tags/count/unique/non-copyable/niche/large-layout/counting/GC cases keep helpers.
No numeric-zero region proof, relaxed lifetime rule, changed callback order,
new inline-cache algorithm or ABI is admissible.

Unknown comments are ignored by LLVM `Reader.blocks`, but
`referencedSymbols` scans `$` in raw comments, and frontend `loweredAllocates`
scans `call $` in raw text. Use a distinct marker namespace without `$`,
existing LLVM/literal/RC-site prefixes, or header keywords consumed by textual
scanners. Physical layout/shape queries merely memoize deterministic facts,
while type declarations, descriptor and glue definitions are sorted by stable
names. A future marker producer must still demonstrate no extra `temp`, emitted
root/call or catalog ordering change; emit metadata after the unchanged original
helper sequence if necessary to avoid moving descriptor queries.

Existing `meta_digest` sidecars cover source positions/assertions/inline frames;
they can carry bounded metadata but **their BLAKE3 is integrity, not proof
authority**. External manifests, inline IL and copied stores can name arbitrary
metadata. A new downstream optimizer would need an out-of-band origin
capability issued only by this compiler's checked source emitter/replay, never
from a manifest field. Module compile in-process, captured self-compiler output
and cached replay are separate authority paths. Public external file/link/API
and host-compiler override inputs would keep original code. Pass-enabled versus
original mode would need separate unit/batch/object/module/no-op keys even for
identical IL, preventing an external manifest from reusing an optimized trusted
object. No existing capability API supplies this today. The QBE-specific pass
must be in `driver_identity` (a `qbe_build_*` source is already included by
`build_qbe_assets.drivesNativeBuilds`) and a versioned QBE policy identity;
frontend cache may remain backend-independent only in this more complex route.

The retained Python lexical model inserts **illustrative inert comments** at
selected helper sites in two exact selected IL texts. Their noncomment lines
and raw symbol sets match, and deliberately inserting a `$` comment changes the
symbol set. These counts are neither admitted native sites nor executed paths.
No actual translator, object compiler, ownership checker or speed test ran.

## Focused implementation acceptance proposal

Before any performance screen, verify policy derivation for auto-QBE, explicit
QBE, Debug/ReleaseFast, LLVM/release and the retired adapter spelling; unknown
flag/backend failures must keep original statuses. Assert original-policy
stand-in emitter performs no query/temp/print before returning refusal. Reuse
the V2 byte/region/overlap/malformed-tag/counting/GC/unique/root tests, preserving
complete fast/slow streams and budget/trace behavior rather than testing only
good tags.

Test fresh and warm shared-cache opposite-policy builds, whole manifest replay,
per-module project and standard interfaces, stale/precompiled opposite-policy
imports, borrowed-unit append, `compile-module --ready`/module linking, native
selected sessions and source-directory fan-out, including provider/whole/no-cache
fallbacks. An external manifest containing forged plan comments must compile
the unchanged supplied call sequence; it cannot enable a transformation or
poison a source emission replay.

Exact LLVM equivalence is feasible but **unverified** here. From the fixed same
37 selected source files, require original-policy cold emission's complete IL,
all positions/assertions/inline metadata and runtime C definitions to match d14
before translation; compare all translated IR and selected O3/full-LTO RC and
separate actual-GC ELFs/allocated sections with explicit selected99ad where QBE
is used. Check whole-program and per-module original policy, even after warming
the same frontend cache with QBE policy. Native counting/stress and fresh
accounted public tests must bind their actual new ELFs, not reuse older guest
qualification. Any changed LLVM stream, cache cross-answer, lost region/overlap
guard or callback/root/trace discrepancy blocks selection.

The assessed benefit is the already measured root V2 opportunity, not a speed
claim for this proposal. Root owns performance and selection. Implementation
requires explicit root authorization and independent lookup review of this
written path; selected core, original checkout and both frozen trials stay
unchanged. Guardian feedback remains root-consolidated.
