# Compiler caches

This document covers the front end's caches: the in-process caches and the
[persistent frontend cache](#persistent-frontend-cache) that ordinary one-shot
commands use across processes. Builds also keep unit objects, linked programs,
replay records and test receipts; see [the native build cache](#native-build-cache)
below and [native builds](native-build.md#the-caches).

The compiler keeps three bounded in-process caches: parsed module syntax, a
whole-program checking verdict, and checked function bodies. `mylang check-session`
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

Ordinary one-shot `mylang check`, `mylang run`, `mylang build` and `mylang test`
also reuse front-end work across processes through content-addressed on-disk caches. The
syntax/verdict layers can skip lexing and parsing and can replay a whole
program's already-successful warnings. C2 adds a separate checked-body store:
ordinary `check`, project checking, `build`, `run` and native-test preparation
can reuse an unchanged ordinary function's checked body after the fresh
declaration/type collection and all global effect/mutation/codec passes run.
Neither layer stores a symbol index, an interface or a resolved declaration table.

For `check` and the other front-end commands the cache root is
`<cache-dir>/frontend/` when `--cache-dir` is given, otherwise
`MYLANG_FRONTEND_CACHE`, otherwise the per-project `.mylang-cache/frontend`. `build`,
`run` and `test` keep their front-end entries in their own work directory,
`<cache-dir>/frontend/` and `<cache-dir>/semantic/` with `--cache-dir` defaulting to
`.mylang-cache/core`, beside the build's other stores, so naming `--cache-dir` leaves
no other `.mylang-cache` in the working directory. The checked-body store and the
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
on-disk format is `mylang-frontend-cache-v7`; the runtime ABI dimension is
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
`<cache-dir>/invalidation/<entry>.json` (`--cache-dir`, else `MYLANG_FRONTEND_CACHE`,
else `.mylang-cache/frontend`), is deliberately not partitioned by
compiler identity so a compiler change can be explained, and `--no-cache` reads
and writes no baseline. A missing baseline is nine misses with `"no-baseline"`;
a corrupt baseline is nine misses with `"corrupt-baseline"` rather than a
failure.

```console
$ mylang check-project app/main.my --report --cache-dir=.mylang-cache/demo
{"version":"frontend-cache-v1","syntax_hits":0,"syntax_misses":2,"syntax_stored":2,"verdict_hits":0,"verdict_misses":1,"verdict_stored":1,"damaged":0,"bypassed":0,"evicted":0,"retained_bytes":685,"stages":{"load_source":{"hits":0,"misses":0},"lex_parse":{"hits":0,"misses":2},"resolve_interface":{"hits":1,"misses":0}}}
$ mylang check-project app/main.my --explain-invalidation --report --cache-dir=.mylang-cache/demo
{"version":"invalidation-report-v1","hits":6,"misses":3,"queries":[{"stage":"load_source","status":"miss","key":"...","first_changed":"module:main"},{"stage":"resolve_interface","status":"hit","key":"..."},{"stage":"check_body","status":"miss","key":"...","first_changed":"module:main::main"}]}
{"version":"frontend-cache-v1","syntax_hits":2,"syntax_misses":0,...,"stages":{"load_source":{"hits":1,"misses":0},"lex_parse":{"hits":1,"misses":0},"resolve_interface":{"hits":1,"misses":0}}}
```

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
walking its syntax. After the passes the check confirms that every body it did
check still has exactly its stored facts and that no call cycle runs through
both a checked and a stood-in body; if either fails, or a pass reports an error,
the check repeats in full without summaries, so what `check` prints never
depends on them. The entry point, constants, conversions, host and foreign
declarations, and bodies whose checked tree names a specialization, a lambda or
a type interned while checking are always checked.

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

`build`, `run`, `run-project` and `test` read the same summaries but check every
body, because building Core IR needs the checked tree; a summary stands in only for an unchanged body's facts and pass
diagnostics, so the passes walk only changed bodies. Such a command writes the
slot only when it had no summaries or repeated in full. A request served by
summaries neither reads nor publishes the checked-body store below.

`checked_bodies.reused` in the work report counts stood-in bodies; `performed`
counts the bodies actually checked. After a one-line body edit only that body
and the entry point are checked:

```console
$ mylang check main.my --report
{"version":"work-report-v1","command":"check",...,"checked_bodies":{"status":"miss","performed":25,"reused":0},...}
$ sed -i 's/k \* 1 + 1/k * 1 + 7/' m1.my
$ mylang check main.my --report
{"version":"work-report-v1","command":"check",...,"checked_bodies":{"status":"miss","performed":2,"reused":23},...}
```

`--no-cache` and `--explain-invalidation` use no summaries, and every other
command that inspects the checked program (`context`, `lint`, `index-project`,
the native-test session) ignores them. A damaged or foreign slot is a miss.

## Persistent checked-body store

Ordinary one-shot single-file `check`, project commands that inspect the
checked program without summaries (above), and native-test preparation use the
same checked-body query path. The durable store lives under
`<cache-dir>/semantic/` when `--cache-dir` (or `MYLANG_FRONTEND_CACHE`) is given
and `.mylang-cache/semantic/` otherwise; it is one contract-namespaced directory of
versioned `semantic-cache-v5` files. Each file contains one stable declaration
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

```console
$ mylang check app/main.my --cache-dir=.mylang-cache/demo --report
{"version":"work-report-v1","command":"check","reused":false,...,"checked_bodies":{"status":"miss","performed":3,"reused":0},...}
$ mylang check app/main.my --cache-dir=.mylang-cache/demo --report
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
stored. In the session below the two-module project is checked, then `main.my` is
edited between the requests, so the unchanged `helper.my` parse is reused and
only the edited module is parsed again.

```console
$ mylang check-session app/main.my
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
$ printf 'check\ncheck\nclear\ncheck\nquit\n' | mylang check-session examples/modules/main.my
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
$ mylang check-session app/main.my
check
{"version":"check-session-v1","action":"check","status":0,"failure":null,"reuse":{"hits":0,"misses":1},"cache":{"hits":0,"misses":1,"stored":1,"evicted":0,"bypassed":0,"retained_bytes":11452},"semantic":{"hits":0,"misses":1,"stored":1,"bypassed":0,"retained_bytes":670},"functions":{"reused":0,"checked":3,"stored":1,"bypassed":0,"retained_bytes":5914}}
check
{"version":"check-session-v1","action":"check","status":0,"failure":null,"reuse":{"hits":0,"misses":1},"cache":{"hits":0,"misses":2,"stored":2,"evicted":0,"bypassed":0,"retained_bytes":16624},"semantic":{"hits":0,"misses":2,"stored":2,"bypassed":0,"retained_bytes":524},"functions":{"reused":2,"checked":4,"stored":2,"bypassed":0,"retained_bytes":9118}}
quit
{"version":"check-session-v1","action":"quit","status":0,"failure":null,"reuse":{"hits":0,"misses":0},"cache":{"hits":0,"misses":2,"stored":2,"evicted":0,"bypassed":0,"retained_bytes":16624},"semantic":{"hits":0,"misses":2,"stored":2,"bypassed":0,"retained_bytes":524},"functions":{"reused":2,"checked":4,"stored":2,"bypassed":0,"retained_bytes":9118}}
```

## Native build cache

`mylang build`, `run` and `test` keep their compiled objects in two stores, described
in full in [native builds](native-build.md#the-caches):

1. **The per-user object store** — `MYLANG_CORE_RUNTIME_CACHE`, else
   `$XDG_CACHE_HOME/mylang/core-runtime`, else `~/.cache/mylang/core-runtime`. One
   object per LLVM unit (`units-v1/<key>.o`), keyed by the unit's exact text, the
   optimization level, the target and CPU, the toolchain and the runtime, plus the
   core runtime and number-text objects. Every project, worktree and test directory
   of one user shares it.
2. **The work directory** — `--cache-dir`, default `.mylang-cache/core`: the front-end
   stores above, linked programs (`programs-v1`), `--link` C objects (`foreign-v1`),
   whole-build replay records (`replay-v1`) and test receipts (`tests/`).

An unchanged build replays its last identical build without checking or starting a
process; an edit recompiles only the debug units whose text changed. `--no-cache`
builds through an empty private work directory removed afterwards, and
`--verify-cache` recompiles every served unit and fails on a byte difference. Doctests
stage both examples and their caches beneath `TMPDIR` and remove that workspace after
reporting. `scripts/prune-caches.sh` evicts both stores.
