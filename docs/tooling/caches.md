# Compiler caches

This document covers the front end's caches: the in-process caches and the
[persistent frontend cache](#persistent-frontend-cache) that ordinary one-shot
commands use across processes. Builds also keep unit objects, linked programs,
replay records and test receipts; see [the native build cache](#native-build-cache)
below and [native builds](native-build.md#the-caches).

The compiler keeps three bounded in-process caches: parsed module syntax, a
whole-program checking verdict, and checked function bodies. `selka check-session`
keeps them across requests so an editor or an agent can check the same project
repeatedly in one process. Every reply is one `check-session-v1` JSON line whose
`reuse`, `cache`, `semantic` and `functions` fields report what was actually
reused. The design records are
[bounded incremental module syntax](../experiments/incremental-syntax.md),
[persistent CLI checking sessions](../experiments/check-session.md) and
[larger-project incremental checking](../experiments/large-project-checking.md).

Actual work and reuse are reported separately from cache fingerprints; see
[Compiler work and reuse report](work-report.md#compiler-work-and-reuse-report).

## Persistent frontend cache

Ordinary one-shot `selka check`, `selka run`, `selka build` and `selka test`
also reuse front-end work across processes through content-addressed on-disk caches. The
syntax/verdict layers can skip lexing and parsing and can replay a whole
program's already-successful warnings. C2 adds a separate checked-body store:
ordinary `check`, project checking, `build`, `run` and native-test preparation
can reuse an unchanged ordinary function's checked body after the fresh
declaration/type collection and all global effect/mutation/codec passes run.
Neither layer stores a symbol index, an interface or a resolved declaration table.

For `check` and the other front-end commands of a project (an entry that imports,
declares `public` names or sits under a `selka.json`) the work directory is
`<cache-dir>` when `--cache-dir` is given, otherwise `SELKA_FRONTEND_CACHE`, otherwise
the build's own `.selka-cache/core`, so a check and a build of one program share their
front-end entries, summary table and ownership proofs; a project command runs on the same
front-end session a build does. A single-file `check` with no imports keeps the
per-project `.selka-cache/frontend`. `build`,
`run` and `test` keep their front-end entries in their own work directory,
`<cache-dir>/frontend/` and `<cache-dir>/semantic/` with `--cache-dir` defaulting to
`.selka-cache/core`, beside the build's other stores, so naming `--cache-dir` leaves
no other `.selka-cache` in the working directory. The checked-body store and the
invalidation baseline below follow the same root as the frontend entries.
`--no-cache` disables frontend reuse for `check` and the project commands; on
`build`, `run` and `test` it builds through an empty private cache, while the
per-user object store is still used. Within the root,
entries are partitioned by the compiler's
build-time identity (a digest of every file under `src`, the Zig toolchain and the
optimize mode), so a rebuilt compiler can never read an older build's entries.

The cache has two independent layers, and both are always keyed by the compiler
identity, a format version and the six-dimension cache contract: compiler build
identity, bootstrap-language version, target, runtime ABI, effects/capabilities
contract and invoking flags. The contract fingerprint is mixed into every syntax,
verdict, checked-body and specialization key, so changing any
dimension invalidates an entry even when the source bytes are identical. The
on-disk format is `selka-frontend-cache-v7`; the runtime ABI dimension is
`runtime-abi-v3` and changes when the native ABI changes. See
[the incremental contract](../experiments/incremental-contract.md#cache-key-contract).

| layer | stored | key also includes | skipped on a hit | still runs fresh |
| --- | --- | --- | --- | --- |
| parsed syntax | one parsed module body | exact source path, exact source bytes, module body start | the lexer and parser for that module only | every declaration, symbol, export, visibility, ownership, effect and typed-body check |
| project verdict | the rendered warning text of one successful `check-project` | every loaded module's name, exact path and exact bytes, plus the diagnostic format | declaration/interface resolution and the entire semantic check | loading every module from disk and recomputing the key |

Single-file commands (`check`, `run`) key syntax with body start `0`;
project commands key it with the body start after imports, so the two shapes
never alias. A syntax hit returns independently owned AST storage: the two
growable `Program` lists are persisted as exact-length owned slices, so a restored
list owns exactly its items and never advertises capacity it did not allocate.

A stored module is a header, a declaration part (types, functions, attributes and the trees outside every
function body: parameter and field defaults, constants, the root statement of each body) and one section per
function body, each with its own checksum. A build, a test and a project `check` read a module that did not change
as far as its declaration part and fill a function body only when something reads it: the checker for a function it
checks, the idiom pass, the dependency-key builder, or a scan around one site. The program that results is the one a
whole read gives, and a body whose section is gone or damaged is taken from a fresh parse of the module. The facts a
whole-program scan would find (the literals the type catalog registers, the retired constructs the rejections look
for) are stored with the declaration part, and a program that holds a retired construct is read whole.
`SELKA_LAZY_SYNTAX=0` reads every module whole; commands that read every body (`lint`, `fix`, `doc`, `context`)
always do. A Debug compiler, and any run with `SELKA_ENGINE_VERIFY` set, fills the bodies it has not read with a
sentinel so that a reader that missed its fill fails loudly. A ReleaseFast compiler writes no sentinel, so the
readers are inventoried instead: `src/lazy_readers.zig` lists every file under `src/` that indexes the tables of
`ast.Program` (`.nodes.items`, `.statements.items`, or a `.nodes` or `.statements` field in a file that names the `ast`
module), each with the reason its reads are safe under lazy loading and the hook or path that makes them so, and
`src/lazy_readers_test.zig` fails for a reader that is not on the list, for an entry whose file no longer reads the
tables, and for a `hooked` entry that calls no hook. A new reader adds its entry and says why.

### Limits and fallbacks

- **Typed bodies are persisted only as validated, remappable snapshots.** C2
  writes one complete checked ordinary body per file after a successful check.
  Fresh declaration/type collection, per-function dependency digests, global
  effect/mutation validation and codec validation still run on every request, and
  every decoded declaration/catalog reference is remapped through C1R or treated
  as a miss. A fresh error is never replaced by a previous pass. Symbol indexes,
  interfaces and resolved declaration tables are still never written.
- **Embedded files are inputs.** A file a module reads with `embed_bytes` or
  `embed_str` is read once when the project loads, and its outcome and BLAKE3
  digest join the configured identity every verdict-level layer keys on and the
  dependency context of each declaration whose region holds the call, so an edit
  to only that file misses exactly those bodies, summaries and stored units and
  nothing else. The syntax layer never sees the file: parsing does not depend on
  it. See [embedding a file](../bytes.md#embedding-a-file-at-compile-time).
- **Failed checks are never stored.** A verdict entry is written only after a
  complete, error-free `check-project`; a type, privacy, import or deleted-file
  error can never inherit an earlier success. The verdict key covers all loaded
  bytes, so a changed file, module name, import graph or generated input misses.
- **Damaged entries degrade to a miss.** Every entry repeats its key, payload
  length and an XxHash checksum in its header. A truncated, foreign, resized or
  bit-flipped entry is rejected (`damaged` in the receipt) and the caller parses
  or checks fresh; no partial result is ever used. Stores stage to a unique
  `.tmp` file and rename atomically, and concurrent trims can only cost a miss.
- **Bounded retention that scales with the project.** A run that stored an
  entry trims the directory once, after the command, to the larger of 128 MiB
  and twice the entry bytes the run itself read back or stored (its working
  set), least recently used first: a read renews an entry's modification time.
  So a project whose working set outgrows 128 MiB (about 8 bytes of cache per
  byte of source; a generated 440k-line project) keeps every entry it uses and
  an unchanged rerun evicts nothing, while old versions of edited modules age
  out. The directory costs at most twice the working set on disk, about 16
  bytes per byte of source: 560 MB for a million-line project. An entry larger
  than 128 MiB is bypassed rather than stored. `retained_bytes` is the size
  observed during the last trim, so a run that stored nothing reports `0`.
- **Invalidation is exact-content.** Any change to the compiler sources, Zig
  toolchain, optimize mode, diagnostic format, source path or source bytes
  changes a key. There is no time-based expiry and no notion of a "changed but
  currently unread" file: the caller always reloads every module first.

On `check`, `check-project` and the other front-end commands, `--report` prints one
`frontend-cache-v1` JSON receipt on stderr (and a `work-report-v1` line);
`--timings=json` adds the same JSON receipt alongside the phase-timing lines. The
receipt carries a `stages` object with a hit/miss count for each incremental query
stage; the last three (`lower_function`, `emit_fragment`, `link`) belonged to the
retired back end and are always `skipped`. On `build`, `run` and `run-project`,
`--report` is the build's `cache-report-v1` line instead
([native builds](native-build.md#reports)), and `--timings=json` is refused.

`--explain-invalidation` (on `check-project` and the other front-end commands;
`build`, `run` and `test` refuse it) compares the current checked project against
the previous `project-dependencies-v1` receipt and prints one
`invalidation-report-v1` line on stderr, naming the hit/miss status and the first
changed dependency for every stage. The baseline lives at
`<cache-dir>/invalidation/<entry>.json` (`--cache-dir`, else `SELKA_FRONTEND_CACHE`,
else `.selka-cache/frontend`), is deliberately not partitioned by
compiler identity so a compiler change can be explained, and `--no-cache` reads
and writes no baseline. A missing baseline is nine misses with `"no-baseline"`;
a corrupt baseline is nine misses with `"corrupt-baseline"` rather than a
failure.

```console
$ selka check-project app/main.selka --report --cache-dir=.selka-cache/demo
{"version":"frontend-cache-v1","syntax_hits":0,"syntax_misses":2,"syntax_stored":2,"verdict_hits":0,"verdict_misses":1,"verdict_stored":1,"damaged":0,"bypassed":0,"evicted":0,"retained_bytes":685,"stages":{"load_source":{"hits":0,"misses":0},"lex_parse":{"hits":0,"misses":2},"resolve_interface":{"hits":1,"misses":0}}}
$ selka check-project app/main.selka --explain-invalidation --report --cache-dir=.selka-cache/demo
{"version":"invalidation-report-v1","hits":6,"misses":3,"queries":[{"stage":"load_source","status":"miss","key":"...","first_changed":"module:main"},{"stage":"resolve_interface","status":"hit","key":"..."},{"stage":"check_body","status":"miss","key":"...","first_changed":"module:main::main"}]}
{"version":"frontend-cache-v1","syntax_hits":2,"syntax_misses":0,...,"stages":{"load_source":{"hits":1,"misses":0},"lex_parse":{"hits":1,"misses":0},"resolve_interface":{"hits":1,"misses":0}}}
```

## Shared compiler artifacts

Set `SELKA_COMPILER_SHARED_CACHE` to one dedicated local directory to share
immutable compiler artifacts between compatible worktrees. Sharing is off
otherwise: the per-user default location applies only once the compiler's
`default_sharing` switch is on ([default location](native-build.md#shared-compiler-artifacts)). Keep each worktree's
`--cache-dir` and `ZIG_LOCAL_CACHE_DIR` separate. This is independent of
`SELKA_TEST_SHARED_CACHE`, which shares eligible test successes.

```bash
export SELKA_COMPILER_SHARED_CACHE="$HOME/.cache/selka/compiler-artifacts"
selka build app/main.selka -o app.bin --cache-dir .selka-cache/private --report
```

The optional store uses `compiler-artifacts-v2/{syntax,typed,program}` and, for the
incremental engine's records and objects, `engine_record` and `engine_object`
([the shared tier](engine.md#the-shared-tier)). Ordinary
parsed syntax can move between paths because its serializer contains source
spans and bytes, not the original pathname. Compiler and contract identity,
exact source bytes and body start still match; trusted intrinsic and standard
library parsing remain private. Declarations, imports and policy resolve fresh.

Ordinary typed bodies share only when logical module identities and the current
source origins can be proved. They retain the existing remap-or-miss validation
against fresh declarations and catalogs. Their shared key additionally binds
the exact merged source bytes and ordered logical source layout because the
serialized body can contain layout indexes. This deliberately loses shared
typed-body hits after an unrelated source edit; the more precise private
incremental keys are unchanged. Unproved standalone paths, generic-template
references and unsupported metadata use fresh/private checking. Effects,
mutation validation, diagnostics and embedded inputs retain their fresh checks.
Typed transport also requires complete concrete bodies: validation-only checks
and warm demand requests with previous summaries keep using private retention.
A first build in an empty worktree can share because no prior summaries can
omit any body. All fresh embedded-input proofs join the shared layout identity.

Whole-check verdicts, rendered warnings, summaries, revision indexes and
invalidation baselines stay private. `check-session` retains its existing
in-process caches. Native linked programs can share when their exact objects
and linker identity match; see [native builds](native-build.md#shared-compiler-artifacts).
A shared program hit still follows frontend checking, lowering and emission.

Shared records carry their kind, key, bounded length and BLAKE3 checksum. Missing
or corrupt records miss and refill; valid different bytes for the same key are
a miss that keeps the existing record, publishes nothing and appends one line to
the namespace's `mismatches.log` (builds count program mismatches as
`shared_mismatches`). The engine's records are the exception that proves the rule: two trees
that hold two versions of a module ask one key and read different things, so each version is a
variant of the key (up to four slots, `variantKey`), served to the trees whose reads hold, and only
the same reads with another result is a mismatch. A configured unusable or unknown-format store is an error,
including before private replay. `--no-cache` and native `--verify-cache` suppress
shared lookup and publication. Individual payloads above 128 MiB stay private.
File publication and materialization stream through a fixed buffer.

No cache lock spans parsing, checking, code generation or linking. A per-key
publication lock covers comparing an existing record (by hashing the new bytes
in place, without a staging copy), staging and replacement. Reads use opened
immutable files with no lock or lease. A shared retention lease, taken without
waiting, covers each write, including staging and publication-lock waits; while
a collection holds the store, a write is skipped. The directory lock covers
only first format initialization. The store automatically attempts throttled
LRU collection under an exclusive nonblocking retention lease; no open, lookup
or restore waits on it. Use trusted local
producers and see [retention policies](cache-retention.md#native-cache-retention)
for budgets, configuration and explicit cleanup.

## Check summaries

A project check keeps one more record in the frontend cache: one slot per
entry module holding a *summary* of every ordinary function the last
successful check or lowering command checked. A summary names the function by
its stable declaration key and records its dependency context (the digest over
every declaration its signature and body reference, including each one's
defining module and `@deprecated` reason), the length and BLAKE3 digest of its
declaration region together with the names that region's syntax references,
its propagated effect mask and mutation summary, the diagnostics it
contributed with spans relative to its region, and the functions it calls.

The next `check` of the entry stands a summary in for every body whose context
and region digest are unchanged and whose touched records keep their shapes. The body is neither checked nor copied: the
function keeps its checked signature over an empty body, the effect and
mutation passes seed it with its stored facts and report nothing of their own
for it, and its stored diagnostics are replayed at the region's new offset.
Dependency keys for such a function resolve its recorded names instead of
walking its syntax. A stood-in body is not resolved again, so the imports its
recorded names go through, a qualifier written only inside an f-string hole
included, count as used: `W_UNUSED_IMPORT` names the same imports with or
without summaries. After the passes the check confirms that every body it did
check still has exactly its stored facts and that no call cycle runs through
both a checked and a stood-in body; if either fails, or a whole-program pass
reports an error, the check repeats in full without summaries. A body that fails
to check is reported by the attempt that found it and is not repeated: a body
stands in only while the context that decides its own result is unchanged, and
every body that was checked reports what a full check does. What `check` prints
never depends on summaries. The entry point, constants, conversions, host and
foreign declarations, and bodies whose checked tree names a specialization, a
lambda or a type interned while checking are always checked.

A stored warning, and a site a waiver silenced, stands in only while the `# lint: allow-file` waivers of its file and the
comment on the line above its region are the ones it was made under: a comment elsewhere in the file is not part of the region.
A W13 refusal (`E_METHOD_REMOVED`, `E_REMOVED_SPELLING`; warnings until W13-S5) reads more of its file than that: whether
another function binds the name of the module its rewrite imports, whether the file already imports it and whether the file
declares the prelude name the rewrite would call. A function with such a site is stored under the digest of its whole file as
well, so any edit of the file checks it again (lane FX13: before it, a cached check kept a warning that a file waiver added
later silenced, and withheld a rewrite after the parameter that hid its module was renamed). A refusing check stores
nothing, so a refusal is never served from a record; once the last old spelling of a file is rewritten, the file checks
afresh.

A body that holds a typed hole is always checked too. A debug build, `selka run` and `selka test` keep a hole as a trap
(`docs/typed-holes.md`), and `check` refuses it with `E_TYPED_HOLE`; the hole mode is not part of any key, so the summary a
trap-mode command publishes marks such a body neither `stubbable` nor `complete`. It stands in for neither its body nor its
passes, in the work directory or in the shared compiler store, and a later `check` meets the hole again. The bodies around it
still stand in. A check that refused a hole publishes nothing, so it never stops a later build from compiling the hole as a trap.

Two independent guards keep a stand-in from outliving a type it depends on.
The dependency context is transitive: a declaration's fingerprint covers every
declaration it reaches, in an order-independent way (so recursive and mutually
recursive types are covered), a composite type spelling such as `Inner[]`,
`dict[str, Inner]`, `Inner?`, `FixedArray[Inner, N]` or a callable type
references each component type, a type declaration's fingerprint covers its
source text, and a facade's re-exported name binds the declaration it names.
Independently, a summary records the transitive shape digest of every catalog
record its checked tree touched (`CHECK-SHAPES-1`), however the body reached it,
and is not stood in unless every one of them still has that shape. Renaming a
field of a record a body reaches only through `o.items[0]` therefore re-checks
that body.

Native builds also use lowering receipts to omit unchanged checked trees when
cached Core IR can supply the body. The receipts validate the declaration's
dependency context and source region. External debug locations additionally
require the same original source file, origin order and exact file bytes; this
lets an unchanged body use locations in another declaration without restoring
its typed tree. Changed or missing authority requires a complete body. If later
lowering needs an omitted body and its cached IR is unavailable, the build
repeats with complete frontend bodies. Allocation-bounded functions and their
transitive callees retain concrete trees for allocation diagnostics.

Where a complete tree is needed, the checked-body store below can replay it.
The summary facts still avoid repeating global pass work for unchanged bodies.

A `check` of a library entry (a module that declares no `main`) keeps and uses summaries
the same way, in a slot of its own that an executable check never reads and that is keyed by
the entry's path as given, so a tree and its copy in one cache keep a slot each. It has no
entry point, so the first function in the merged source takes that place: it is always
checked, and every other unchanged body stands in. Preparing the dependency keys costs about
a sixth of a cold check, and a library checked once, or one that does not check, never uses
them, so a library earns the summaries over its first checks. The first successful check runs
the plain library check, preparing and storing no table, and leaves a mark in the slot (an
empty table, written without a directory trim); the second finds the mark, prepares the keys and
stores the table; the third and later stand bodies in. A table byte-equal to the one already
stored is not written again, so re-checking an unchanged library leaves the cache as it is.
The payload spells each repeated string, the names a region references above all, once in a
pool and stores counts and indexes in as many bytes as they need, which keeps a table to about
half the size of a plain encoding.

`checked_bodies.reused` in the work report counts stood-in bodies; `performed`
counts the bodies actually checked. After a one-line body edit only that body
and the entry point are checked:

```console
$ selka check main.selka --report
{"version":"work-report-v1","command":"check",...,"checked_bodies":{"status":"miss","performed":25,"reused":0},...}
$ sed -i 's/k \* 1 + 1/k * 1 + 7/' m1.selka
$ selka check main.selka --report
{"version":"work-report-v1","command":"check",...,"checked_bodies":{"status":"miss","performed":2,"reused":23},...}
```

`--no-cache` and `--explain-invalidation` use no summaries, and every other
command that inspects the checked program (`context`, `lint`, `index-project`,
the native-test session) ignores them. A damaged or foreign slot is a miss.

## Persistent checked-body store

Ordinary one-shot single-file `check`, project commands that inspect the
checked program without summaries (above), and native-test preparation use the
same checked-body query path. The durable store lives under
`<cache-dir>/semantic/` when `--cache-dir` (or `SELKA_FRONTEND_CACHE`) is given
and `.selka-cache/semantic/` otherwise; it is one contract-namespaced directory of
versioned `semantic-cache-v7` files. Each file contains one stable declaration
key, the dependency context, the checked contract digest, the owned relocatable
`typed.Function`/node/statement tree, referenced stable identities, source
region/body bytes, the body-local binding-warning notes (code, severity, span and
message), a payload length and an XxHash checksum. No pointer, allocator
capacity, catalog ordinal or process address is written. The fresh binding pass
still relocates and emits those warnings from the copied locals, so persisted
notes never duplicate a diagnostic in output.

A hit requires all of the following before a body is admitted: format version,
compiler/effects/runtime-ABI/flags contract fingerprint, mutation-contract
version, stable declaration key, dependency context, checksum, bounded lengths,
reference ordinals and source ranges. Decoding does not integrate the body:
`semantic_cache.Session.lookup` still remaps old `FunctionId` and record ordinals
through the fresh catalog, verifies that the declaration region is byte-identical
at its new location, and treats any missing or ambiguous remap or failed
relocation as a fresh check. Each record reference also carries the record's transitive shape digest, and a
body whose touched record changed shape misses as `record-shape-changed`. The
fresh project's effect, mutation, codec and
binding-warning passes always run over the copied body, so a replayed body cannot
carry an obsolete global verdict and warning locations relocate with the source.
A replayed body is not checked again, so a body whose check reported anything (the
`W_DEPRECATED` of a call to a `@deprecated` function in another module) is never
stored, in memory or on disk: the next request checks it and reports it again. Nor is a body with a W13 site whose
warning a file waiver silenced, since removing the waiver elsewhere in the file leaves the body's region as it was. The
import-use scan that stands in for resolution reads the holes of format strings too, so
an import used only in an `f"..."` message stays used.

Supported dynamic arrays, tuples and function-value types store portable
interner inputs alongside their shape digests. Replay reconstructs them through
the current checker and verifies their fresh shapes before accepting the body.
Function-value contracts come from current declarations and the current use
site, including its expected callback type where available. Generic call sites
can reuse the target's standalone contract when its complete fresh shape
matches. Dynamic nominal types must already exist in the current catalog with
the same unique name and transitive shape; replay never expands a nominal graph
speculatively. Unsupported or ambiguous recipes fall back to checking.
Replayed nodes and statements are copied directly into
their final arrays, avoiding an intermediate outer-array allocation. The v6
format requires older checked-body entries to be repopulated once.

```console
$ selka check app/main.selka --cache-dir=.selka-cache/demo --report
{"version":"work-report-v1","command":"check","reused":false,...,"checked_bodies":{"status":"miss","performed":3,"reused":0},...}
$ selka check app/main.selka --cache-dir=.selka-cache/demo --report
{"version":"work-report-v1","command":"check","reused":true,...,"checked_bodies":{"status":"hit","performed":0,"reused":3},...}
```

Retained in-memory storage is governed by one shared budget: ordinary checked
bodies, `symbolic-template-v1` templates and `specialization-v2` instances all
charge their owned entry rows, exact arena backing allocations including
per-chunk allocator bookkeeping, stable keys, and the exact stable-key
hash-index backing allocation — including the standard map's minimum capacity,
header and alignment — against `reuse.max_bytes`. Publication and durable-hit
promotion converge on the bound by releasing the globally oldest generic entry or
truncating the ordinary snapshot to its fitting leading prefix; oversized entries
bypass retention without changing acceptance, a zero budget disables reuse, and
the reported retained bytes and per-kind eviction counts reflect the actual owned
storage. `check-session clear` releases all three kinds together, so a subsequent
check recomputes them fresh.

A second entry kind, `symbolic-template-v1`, stores one checked symbolic generic
template's direct abstract results: effect/mutation masks, body-local diagnostics
and ordered abstract call edges. It lives in the same contract namespace but is
keyed away from ordinary bodies, and replay additionally requires a byte-identical
declaration region/body, matching dependency context, name-resolution mode and
abstract-checker version. Scoped-bound resolution, structural validation and the
whole-graph effect propagation still run on every request, so a replayed template
never carries a stale transitive verdict.

A third entry kind, `specialization-v2`, stores one checked concrete
specialization under the canonical key over the template identity, ordered
positional type/length descriptors, transitive name-ordered provider contracts,
template constraint dependencies, declared effect/mutation/return-origin
contracts and build context. Replay additionally requires the defining template's
declaration region/body to be byte-identical and every stored function/record
reference to remap to exactly one fresh identity. Ordinary callees remap by
stable declaration key; nested specializations remap by canonical fingerprint. Missing instances may
be preregistered from a validated durable recipe only after matching the fresh
template, source bytes, context, current type arguments and re-derived fingerprint.
Registration uses the normal bounded instance registry, so recursive references
resolve to their existing fresh instance without recursively checking bodies. Missing,
ambiguous, interned-catalog or synthesized-lambda references fall back to a fresh
check. The specialization payload stores no effect or mutation verdict: the whole
graph `effects.check` and `origins.check` passes always rerun over the combined
fresh and replayed trees, so a changed provider body is reflected in generated
code and a changed declared ceiling invalidates by key. Concrete specialization
reuse increments `checked_bodies.reused` beside ordinary body reuse; the
`symbolic_templates` object only counts abstract template replay.

Publication stages the complete image in a same-directory `.tmp` file and renames
it over the stable key, so readers observe the previous complete file or the new
one, never a partial image. It never syncs the filesystem: a cache needs no
durability, and after a crash an image the disk did not keep is torn or missing,
which validation rejects as a miss. Concurrent publishers may
race on the same key; a loser only costs a later miss. Each contract namespace
retains at most 128 MiB and 65,536 entry files by default; a larger single body is
bypassed. One request publishes all of its fresh bodies as a batch: the batch
inventories the namespace once, charges each body to in-memory accounting, and
reconciles at batch end with a fresh mtime-sorted trim, so populating a namespace
costs linear filesystem work instead of a full scan per body. Reconciliation
tolerates a bounded slack (one sixteenth of the limit, at least 1,024 bytes or
entries) and converges to the limits at the end of every publishing batch; a warm
request with no fresh bodies performs no inventory at all. Truncated, oversized, damaged, foreign-version or
contract-incompatible files are plain misses and are re-derived. `--no-cache`
performs no durable reads or writes and preserves the same acceptance and
diagnostics.

## Syntax cache

A module's parsed body is retained under its path, its complete source bytes and
its body start, and reused only when all three match exactly; no hash comparison
can produce a false hit. A hit skips the interface phase's second lexer pass and
the body parser, and deep-copies the syntax into the fresh project, so returned
syntax never borrows retained storage and clearing or eviction cannot invalidate
it. Everything else still runs: source is reloaded and re-lexed for import discovery, and symbols, exports, resolution, visibility, ownership, effects and
every body are checked again. Retention is 256 entries and 16 MiB of entry arena
capacity with oldest-insertion eviction; larger entries are bypassed rather than
stored. In the session below the two-module project is checked, then `main.selka` is
edited between the requests, so the unchanged `helper.selka` parse is reused and
only the edited module is parsed again.

```console
$ selka check-session app/main.selka
check
{"version":"check-session-v1","action":"check","status":0,"failure":null,"reuse":{"hits":0,"misses":2},"cache":{"hits":0,"misses":2,"stored":2,"evicted":0,"bypassed":0,"retained_bytes":5568},"semantic":{"hits":0,"misses":1,"stored":1,"bypassed":0,"retained_bytes":602},"functions":{"reused":0,"checked":4,"stored":1,"bypassed":0,"retained_bytes":4748}}
check
{"version":"check-session-v1","action":"check","status":0,"failure":null,"reuse":{"hits":1,"misses":1},"cache":{"hits":1,"misses":3,"stored":3,"evicted":0,"bypassed":0,"retained_bytes":8500},"semantic":{"hits":0,"misses":2,"stored":2,"bypassed":0,"retained_bytes":602},"functions":{"reused":3,"checked":5,"stored":2,"bypassed":0,"retained_bytes":5232}}
quit
{"version":"check-session-v1","action":"quit","status":0,"failure":null,"reuse":{"hits":0,"misses":0},"cache":{"hits":1,"misses":3,"stored":3,"evicted":0,"bypassed":0,"retained_bytes":8500},"semantic":{"hits":0,"misses":2,"stored":2,"bypassed":0,"retained_bytes":602},"functions":{"reused":3,"checked":5,"stored":2,"bypassed":0,"retained_bytes":5232}}
```

## Exact verdict cache

One successful whole-program verdict is retained together with its rendered
warnings. A hit requires that the project and its input manifests were loaded
afresh and that every loaded module's name, path and source bytes compare equal;
the hit then replays the owned warning text and skips interface and semantic
work entirely, which is why a verdict hit reports no syntax lookup at all. Failed
checks are never retained, so a type, privacy or deleted-file error cannot
inherit an earlier success, and `clear` drops the verdict along with the other
caches while leaving the cumulative counters. Retention is one snapshot under a
separate 16 MiB arena-capacity bound; oversized entries bypass it. Below, the
second `check` of an unedited project is a verdict hit, and the `check` after
`clear` is a miss again.

```console
$ printf 'check\ncheck\nclear\ncheck\nquit\n' | selka check-session examples/modules/main.selka
{"version":"check-session-v1","action":"check","status":0,"failure":null,"reuse":{"hits":0,"misses":2},"cache":{"hits":0,"misses":2,"stored":2,"evicted":0,"bypassed":0,"retained_bytes":12928},"semantic":{"hits":0,"misses":1,"stored":1,"bypassed":0,"retained_bytes":2778},"functions":{"reused":0,"checked":4,"stored":1,"bypassed":0,"retained_bytes":8578}}
{"version":"check-session-v1","action":"check","status":0,"failure":null,"reuse":{"hits":0,"misses":0},"cache":{"hits":0,"misses":2,"stored":2,"evicted":0,"bypassed":0,"retained_bytes":12928},"semantic":{"hits":1,"misses":1,"stored":1,"bypassed":0,"retained_bytes":2778},"functions":{"reused":0,"checked":4,"stored":1,"bypassed":0,"retained_bytes":8578}}
{"version":"check-session-v1","action":"clear","status":0,"failure":null,"reuse":{"hits":0,"misses":0},"cache":{"hits":0,"misses":2,"stored":2,"evicted":0,"bypassed":0,"retained_bytes":0},"semantic":{"hits":1,"misses":1,"stored":1,"bypassed":0,"retained_bytes":0},"functions":{"reused":0,"checked":4,"stored":1,"bypassed":0,"retained_bytes":0}}
{"version":"check-session-v1","action":"check","status":0,"failure":null,"reuse":{"hits":0,"misses":2},"cache":{"hits":0,"misses":4,"stored":4,"evicted":0,"bypassed":0,"retained_bytes":20312},"semantic":{"hits":1,"misses":2,"stored":2,"bypassed":0,"retained_bytes":1624},"functions":{"reused":0,"checked":8,"stored":2,"bypassed":0,"retained_bytes":8138}}
{"version":"check-session-v1","action":"quit","status":0,"failure":null,"reuse":{"hits":0,"misses":0},"cache":{"hits":0,"misses":4,"stored":4,"evicted":0,"bypassed":0,"retained_bytes":20312},"semantic":{"hits":1,"misses":2,"stored":2,"bypassed":0,"retained_bytes":1624},"functions":{"reused":0,"checked":8,"stored":2,"bypassed":0,"retained_bytes":8138}}
```

## Function body cache

When the verdict cache misses because a module changed, the checked bodies of
functions that did not change can be reused. The in-process `check-session` path
uses this cache directly; ordinary one-shot commands use the durable store above
and hydrate the same cache only from validated entries. Reuse is conservative and
independently owned: a snapshot carries its own spans, nodes, statements and
locals, relocated into the current source, and any relocation that cannot be
validated falls back to checking fresh rather than trusting a stale reference.
Reuse is per function: a changed declaration, type or import identity, a
referenced constant, a scope/visibility lookup or a negative lookup that later
resolves invalidates only the bodies that depend on it, while an unrelated
generic, constant, alias or callback no longer disables reuse. Region, effect,
mutation and codec passes rerun completely after every body edit — so reusing a caller never
reuses a callee's effect or mutation verdict, and a callee that gains an effect
or an input-mutation footprint still rejects an unchanged bounded caller. The `functions` counters report bodies
actually reused and actually checked. In this single-module session `perimeter`
is rewritten between the two requests and the other two bodies are reused.

```console
$ selka check-session app/main.selka
check
{"version":"check-session-v1","action":"check","status":0,"failure":null,"reuse":{"hits":0,"misses":1},"cache":{"hits":0,"misses":1,"stored":1,"evicted":0,"bypassed":0,"retained_bytes":11452},"semantic":{"hits":0,"misses":1,"stored":1,"bypassed":0,"retained_bytes":670},"functions":{"reused":0,"checked":3,"stored":1,"bypassed":0,"retained_bytes":5914}}
check
{"version":"check-session-v1","action":"check","status":0,"failure":null,"reuse":{"hits":0,"misses":1},"cache":{"hits":0,"misses":2,"stored":2,"evicted":0,"bypassed":0,"retained_bytes":16624},"semantic":{"hits":0,"misses":2,"stored":2,"bypassed":0,"retained_bytes":524},"functions":{"reused":2,"checked":4,"stored":2,"bypassed":0,"retained_bytes":9118}}
quit
{"version":"check-session-v1","action":"quit","status":0,"failure":null,"reuse":{"hits":0,"misses":0},"cache":{"hits":0,"misses":2,"stored":2,"evicted":0,"bypassed":0,"retained_bytes":16624},"semantic":{"hits":0,"misses":2,"stored":2,"bypassed":0,"retained_bytes":524},"functions":{"reused":2,"checked":4,"stored":2,"bypassed":0,"retained_bytes":9118}}
```

## Native build cache

`selka build`, `run` and `test` keep their compiled objects in two stores, described
in full in [native builds](native-build.md#the-caches):

1. **The per-user object store** — `SELKA_CORE_RUNTIME_CACHE`, else
   `$XDG_CACHE_HOME/selka/core-runtime`, else `~/.cache/selka/core-runtime`. One
   object per LLVM unit (`units-v1/<key>.o`), keyed by the unit's exact text, the
   optimization level, the target and CPU, the toolchain and the runtime, plus the
   core runtime and number-text objects. Every project, worktree and test directory
   of one user shares it.
2. **The work directory** — `--cache-dir`, default `.selka-cache/core`: the front-end
   stores above, linked programs (`programs-v2`), `--link` C objects (`foreign-v1`),
   whole-build replay records (`replay-v1`) and test receipts (`tests/`).

An unchanged build replays its last identical build without checking or starting a
process; an edit recompiles only the debug units whose text changed. `--no-cache`
builds through an empty private work directory removed afterwards and reads or publishes no shared store (the object store
excepted, [native builds](native-build.md#--verify-cache-and---no-cache)), and
`--verify-cache` recompiles every served unit and fails on a byte difference. Doctests
stage both examples and their caches beneath `TMPDIR` and remove that workspace after
reporting. `scripts/prune-caches.sh` evicts both stores.

## Store settings in selka.json

Where the stores and the temporary folder are is said by environment variables, and a project's `selka.json` can say it
once instead, in an optional `stores` object. Each key stands for one variable, and the file is read only for a variable
the caller's environment leaves unset:

| Key | Variable | What it names | `false` |
|---|---|---|---|
| `cache_home` | `XDG_CACHE_HOME` | the parent of every per-user store with no key of its own (`<cache_home>/selka/<store>`), Zig's libc stubs and the toolchain records | no |
| `objects` | `SELKA_CORE_RUNTIME_CACHE` | the per-user object store ([native builds](native-build.md#the-caches)) | the objects stay in the work directory |
| `compiler` | `SELKA_COMPILER_SHARED_CACHE` | [shared compiler artifacts](#shared-compiler-artifacts) | off |
| `stages` | `SELKA_STAGE_SHARED_CACHE` | the [shared stage store](native-build.md#the-shared-stage-store) | off |
| `tests` | `SELKA_TEST_SHARED_CACHE` | shared test results ([guest tests](guest-tests.md#reusing-unaffected-results)) | off |
| `temporary` | `TMPDIR` | where `zig cc` and the compiler's helpers put temporary files; made when missing | no |

A value is a path: absolute, or starting with `~/` (the `HOME` of the command). `temporary` may also be relative to the
directory that holds `selka.json`. A store may not be relative and may not lie inside that directory, judged on the real
path, so a symbolic link cannot hide one: a store in the checkout could be one the project ships with records prepared
for it. Any other key, a repeated key, an empty string, `true` or `null` is refused with the file, line and column, as
every other key of `selka.json` is (`error[E_PROJECT_CONFIG]`, exit 2).

Precedence, for each place: a flag (`selka test --shared-cache-dir DIR`, `--no-cache`), then the variable, which decides
when it is set even to the empty string (off), then `selka.json`, then the default (`~/.cache/selka/...`, `/tmp`). A
project file never overrides what the caller's environment says, so the repository's own tests and gates, which give
every test its stores through the environment, are unchanged.

The commands that find a project from their entry read it before any store opens: `build`, `build --run`, `run`,
`run-project`, `test`, `check` (also `check DIR`, `check --examples` and the developer checks), `cost`, and the front
end's other commands that take an entry. `fix` decides through the `check` it runs for each entry. A directory of entries
(`selka test DIR`) decides once, from the nearest `selka.json` of the directory, and the child compilers it starts keep
that decision; a dependency's own `selka.json` never decides, since only the entry's project is read. The commands
without an entry (`selka cache gc|configure|init`, which name their store with `--shared-cache-dir`, and `selka engine`,
which reads the work directory) read no project, and neither does `selka doctest`, which builds its examples in a
workspace of its own beneath `TMPDIR`. The work directory itself stays `--cache-dir`, default
`.selka-cache/core`.

The compiler's children (`zig cc`, the helpers) run with the places set. A guest program started by `selka run`, and a
test process, starts with the caller's environment as it was: the variables the file set are taken out again, with
`SELKA_STORE_SETTINGS`, the placement variable that records which ones the file set and from which file. The places are
placement (`src/environment_identity.zon`): no key reads them, and every key reads `selka.json` without its `stores`
member, so moving a store leaves replay records and test verdicts valid. A test entry's stored report records the file's
exact bytes, so an edit of `stores` reruns that entry's check once, with its test verdicts served.

`selka cache where [ENTRY.selka|DIR]` prints, for the project of the entry or directory (default: the working directory),
each place, where it resolved and what decided it:

```console
$ cat app/selka.json
{"version": 1,
 "stores": {"cache_home": "~/stores/xdg", "objects": "~/stores/core-runtime", "stages": "~/stores/stage",
            "compiler": false, "tests": false, "temporary": "~/stores/tmp"}}
$ SELKA_STAGE_SHARED_CACHE= selka cache where app/main.selka
cache_home  /home/me/stores/xdg  (selka.json /home/me/app/selka.json)
objects     /home/me/stores/core-runtime  (selka.json /home/me/app/selka.json)
compiler    off  (selka.json /home/me/app/selka.json)
stages      off  (environment SELKA_STAGE_SHARED_CACHE)
tests       off  (selka.json /home/me/app/selka.json)
temporary   /home/me/stores/tmp  (selka.json /home/me/app/selka.json)
```

A compiler from before 13 November 2026 refuses a file with a `stores` object (`unknown field in selka.json`, exit 2),
so a project adds it only once every compiler it is built with has it.

## Auditing the caches

`scripts/audit_cache_reads.py` is the developer tool that checks the claim every section above
makes, that a result served from a cache equals a clean build of the same inputs. It is Python
and no part of the install graph. `trace` runs cold commands under `strace -f` and compares
every file read with the replay record; `env` classifies the environment names the compiler
reads with `src/environment_identity.zon`; `mutate` builds warm, changes one input (a source,
an embedded file, `selka.json`, a `--link` header, an environment variable, the working
directory, the toolchain, a flag, a signature a stood-in body uses) and compares the second
warm result with a `--no-cache` build; `fuzz` does the same along a chain of small edits to a
real project; `racy` alternates two same-size sources with no pause; `toolchain` runs cold
builds under `strace -f` with an empty Zig global cache and lists every file `zig` opened
that `src/core/tool_files.zig` does not track (run it after a Zig upgrade). Program bytes, stdout,
stderr and exit status must agree, so a replayed warning, a path spelled another way and a
header that appeared after the last build all count. Raw output goes under
`~/.cache/selka/cache-audit` and the evidence archive, never the repository; the regression
tests it produced are in `src/core/cache_staleness_test.zig`.
