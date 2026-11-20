# The incremental engine

The engine answers a *query*: a function of an argument and of whatever it reads through the engine's context. It
stores what each query read and what it produced, and serves the answer again while every read still sees what it saw.
When a read changed the query is recomputed, and when the recomputed answer is the same, the queries that read it stay
valid. The design is `docs/design/incremental-engine.md`; this page is the developer commands. The engine is a library
of the compiler (`src/core/engine/`). Its kinds are the engine's own probes, the four kinds that decide what `selka test` reuses
([the engine in `selka test`](#the-engine-in-selka-test)), and the compiler's own kinds for the front end, the ownership proofs and
the unit stages ([the compiler's kinds](#the-compilers-kinds-as-built)).

## Commands

```bash
# the files a kind's code identity covers, and the identity itself
selka engine closure engine-probe

# the engine's kinds with their code identities
selka engine kinds

# answer a query (here: how big is a file, through two layers of queries), with the report line on standard error
selka engine query engine-probe-class src/main.zig --cache-dir .selka-cache/core --engine-report

# say why a query would not be served: the first read that changed, what it saw, what it sees now
selka engine explain engine-probe-class src/main.zig --cache-dir .selka-cache/core

# measure the engine on a synthetic graph and print one JSON line (--phase compute|serve|verify runs one pass)
selka engine bench --queries 100000 --reads 3 --files 1000

# the same where a quarter of the results are stored objects, serving without opening one; --read-payloads reads every
# payload it is served, which is what serving them eagerly cost; --deps N sets the query reads per node
selka engine bench --queries 9200 --reads 5 --deps 5 --objects 25 --os --phase serve
```

`selka engine closure KIND` answers "why did this kind rekey": a kind's code identity is the token digest of the import
closure of its roots (a comment or a change of layout keeps it), chained with the identities of the kinds it depends
on. The closure is computed at build time by the machinery that computes the stage identities
(`src/build_identity_rules.zig`, `engine_kinds`) and is the same on every machine that builds the same sources.

## The store

The engine's records live in the work directory (`--cache-dir`, default `.selka-cache/core`) under `engine-v1/`:

| Path | Holds |
| --- | --- |
| `records/<kind>/<code identity>/<key[0..2]>/<key>.rec` | one record per query: the reads, in order, with what each saw, and the result |
| `objects/<digest[0..2]>/<digest>` | result payloads over 4 KiB, named by their BLAKE3 digest |
| `inflight/<key>` | the marker an expensive kind's first computer writes (pid, start time, host) |
| `packs/<time>-<digest>.pack` | the records one build adopted from the shared tier (below), in one file with an index |

A record is published by write-then-rename, so a reader sees the old file or the new one and a torn file is a miss.

**Lazy payloads.** Serving a query never opens its object. A served result carries a handle, and the first call to
`Result.payload()` reads the object, checks that its bytes hash to its name and keeps them for the process's revision.
A query that only compares a dependency's digest (every `query` read does) never pays for the dependency's bytes. An
object that is absent or damaged when it is first read is a miss, not an error: the engine runs the query again, publishes
its record and object whole, and answers the new payload (counted in `object_misses` and in `recomputed`). If the rerun
gives another result than the record promised, the kind is not reproducible and the call fails with `E_ENGINE_VERIFY`.
Verify mode reads the objects of the queries it samples and compares them with the recomputation, and mends one that is gone
or damaged.
There is no journal and no per-record lock. Retention is the work directory's: a kind keeps its current
identity directory and the two most recently used others, objects no record (in a file or in a pack) names are collected
after 14 days, and a marker whose process is gone is removed. The one exception to a file for each record is the records
pack, below.

**The records pack.** A fresh work directory is served hundreds of records by the shared tier (below), and each used to be
copied into the work directory as a file of its own so that the next build found it with this tree's stat tuples. The
engine now holds those copies in memory (a record served from the tier, or from a pack, that needs a local copy: the
tier's bytes, or the record rewritten with this tree's tuples after its files were hashed) and writes them as one file
when it ends or starts a new revision: `packs/<time>-<index digest>.pack`, written by write-then-rename like a record
(`engine/pack.zig`, `engine/local_records.zig`). A build that adopts fewer than `Policy.pack_min_records` (16) writes
loose files as before. The file is a header naming the (kind, code identity) groups it holds, an index of
`(key, offset, length)` sorted by key under a digest, and the encoded records, each with its own trailer.

A lookup tries the memory of the revision, then the work directory's own file for the key, then the packs newest first
(a process reads at most eight, and a pack only when one of its groups is a registered kind at its current identity), then
the shared tier's variants. A file wins over a pack because it is only ever written after the pack's record was stale. A
pack is a hint: its records are decoded (their own trailers), checked for kind, identity and key, and validated under this
tree's stat tuples exactly as a file is, so a pack record whose file moved is hashed once, rewritten into the next pack, and
one whose file changed is stale. A pack whose header, index or digest is wrong is ignored whole; a damaged record in a good
pack is a miss for that record alone. `Engine.forget` drops a key from the queue, never serves it from a pack again in that
process, and rewrites the packs that hold it without it. Two processes in one work directory each write packs of their own
(the name carries the time and the digest of the index), so neither loses the other's records. Retention keeps the four
most recently used packs with a live group and the two most recent others (a build that serves from a pack stamps it,
at most once a minute), and removes partial pack files a dead writer left.

## Parts and the projection read

A query can publish **parts** of its result: a table of names and digests (`ctx.exposePart(name, digest)`) that is stored
in its record, beside the payload. A query that depends on the result can read some of the parts instead of the whole
(`ctx.part(kind, argument, names)`): it gets the digests of the parts it names, and it stays valid while those digests do,
whatever the payload or the other parts now are. A dependency recomputed to a table that agrees on the named parts is an
early cutoff, counted in `early_cutoffs` like any other. `selka engine explain` names the part that changed (`part p0:
1a2b3c4d then, 5e6f7a8b now`). Verify mode compares the parts table as well as the result digest, so a kind whose parts do
not follow from its payload is found. Records are format 2 (see `docs/design/incremental-engine.md` §9 and §17.3); records
of format 1 are still read.

## The compiler's kinds, as built

`selka engine kinds` lists every kind with its code identity. The compiler's kinds are per module or per unit, and they hold
digests of parts, so a build that serves a module reads its record and opens a payload only when something recomputed reads it
([parts](#parts-and-the-projection-read)). What each kind does in an ordinary `build`, `run`, `check` or `test`:

| Kind | Argument | In an ordinary build | Shared per user |
| --- | --- | --- | --- |
| `module-syntax`, `module-interface` | the module's project-relative path | read by `module-check`; computed from the parse the front end already holds, so a valid record costs no computation | compiler artifact store |
| `module-check` | the module | **decides** the module's prepared keys ([below](#the-engine-decides-the-modules-prepared-keys)), and keys each lowered function by its `body:` part | compiler artifact store |
| `ownership-proof` | the entry, the ownership mode and the module | **decides** which functions are proven ([below](#the-engine-decides-the-ownership-proofs)) | compiler artifact store |
| `test-exec`, `test-facts`, `test-graph` | see [the engine in `selka test`](#the-engine-in-selka-test) | **decide** what a test run reuses | native test store |
| `module-tokens` | a module source's path, as the test runner names it | read by `test-report`: the digest of the source's tokens without comments, blank lines, trailing whitespace and line numbers, so a comment edit or a line shift leaves the report valid | none |
| `test-report` | the same section | **decides** whether an entry's report is replayed | none (names this tree's paths) |
| `project-graph`, `noalloc-closure`, `module-passes`, `program-diagnostics` | the entry, a `@noalloc` promise, a module | **observed** only: the front end's own tables still answer, and the engine's record states the same facts | compiler artifact store, when recorded |
| `unit-lower`, `program-facts`, `unit-optimize`, `unit-emit` | a unit (a module, a generic instance or a runtime helper) | **observed** only: the records hold digests, not payloads, and the lowering, optimizer and emission caches still answer | none |
| `engine-probe`, `engine-probe-size`, `engine-probe-class` | a file | the engine's own probes | none |

"Observed" means the kind is asked only when `SELKA_ENGINE_SHADOW_COMPILER=1` is set with `SELKA_ENGINE_DECIDE_COMPILER=0`
([the compiler's shadow](#the-compilers-shadow)): the session computes the kind beside the front end and any disagreement is a finding.
An ordinary build asks none of them, so they cost nothing.

What serves the stages after the front end is the stage store, not the engine. Lowering, the optimizer and emission keep their
records in `stages-packed-v1/` in the work directory and, in the per-user shared stage store
([native builds](native-build.md#the-shared-stage-store)), whose shared half has been on by default since 4 November 2026, so that a
fresh worktree is served what another worktree built. Moving those records into the engine, one record per unit with payloads, and
deleting the stage store was deferred by the user on 3 November (part 2, step G4d). The spec's list of what it deletes is section 17.7
of `docs/design/incremental-engine.md`, and `experiments/guest-build-engine-20261031/G5b/DECISIONS.md` (D-G5b-4) says which items were kept.
A `--no-cache` build reads and publishes neither half of the stage store, nor the engine's shared tier
([which stores a cold build uses](native-build.md#--verify-cache-and---no-cache)), so it is the build to compare a rebuild with when a stored
stage record is in doubt.

`SELKA_ENGINE_VERIFY=N` recomputes one served query in N ([verify mode](#verify-mode)) in any of these commands. `selka test` and
`selka engine query` print the engine's counters with `--engine-report` ([the report line](#the-report-line)); `build`, `run` and `check`
refuse that flag, and a build's verify counters are the lines it appends to `<cache-dir>/engine-v1/shadow.jsonl`.

## The compiler's shadow

`SELKA_ENGINE_SHADOW_COMPILER=1` (placement; off unless set) makes `selka build`, `run` and the core `check` (`--stats`,
`--timings`) ask the engine the front end's own questions while the front end answers them, and compare. After a session has
loaded and parsed its project it asks `module-syntax` for each module (a digest for the module's header, each declaration's
head, each function's body, its import list, the heads taken together and its whole text), `project-graph` for the module order,
and, once the merged program is built, `module-interface` for each module (a digest per name the module binds, each covering
the declarations the name stands for and everything they reach, read by an importer one name at a time), and, once the bodies are
checked, `module-check` for each module (a digest per function of the region it was checked from and the dependency context it
was checked in, read from the module's text and from the interface names its bodies look up elsewhere, so a callee's body edit
leaves its callers' checks served), and `module-passes` for each module (a digest per function of the cross-function facts
the passes conclude about it, and a `warnings` part: the module's diagnostics, each in the module's own coordinates with what it
points at; read from the module's checked bodies and text, and the text of any module a warning points into, and the verdict of
each `@noalloc` promise the module declares: see below). The passes
are asked only after a check that publishes its summaries: `build`, `run`, and a first `check`. `program-diagnostics` is the program's
warnings as `check` prints them, assembled from the modules' `warnings` parts in module order; it is not recorded for a program
that has a module whose passes are not (`program_unrecorded`). An answer the
engine serves that is not what the front end computed is a finding: a line in the findings log
(`SELKA_ENGINE_SHADOW_LOG`, default `<cache-dir>/engine-v1/shadow.jsonl`, class `compiler`), the record is forgotten and
asked again. Each session writes one `compiler-summary` line with its counts (`syntax_served`, `syntax_recomputed`,
`syntax_ahead` for a module the engine served where the front end's syntax cache missed, `graph_served`,
`interface_served`/`interface_recomputed`, `check_served`/`check_recomputed`, `passes_served`/`passes_recomputed`/`passes_unrecorded`,
`noalloc_served`/`noalloc_recomputed`/`noalloc_unrecorded`, `findings`, `spent_us`). A session that overlays sources (`selka test`
appends a stub to the entry) is observed like any other (see the decision of the prepared keys, below). Nothing the compiler does
changes.

A `@noalloc` promise is the one whole-program question that reads callee *bodies*: the check lowers the function and everything it
calls to Core and looks for a site that may allocate. The shadow asks `noalloc-closure` for each promise, one query per root (a
generic function that promises it is a root for each instance the program makes). The record reads, as parts of `module-check`, the
body of every function Core reaches from the root, of this run's check, and publishes one part, `verdict`. An edit to a body
outside the closure leaves it served; an edit inside it asks the query again, and the module that declares the promise
(`module-passes`) or the program (`program-diagnostics`, for an instance) stays served when the promise still holds. A promise that
is broken is not recorded (the check fails and nothing is), nor one whose closure holds a function no declaration owns; the module
or the program that holds it is then not recorded. The stand-in planner, for its part, keeps concrete what a changed `@noalloc` body
can name (its module's functions and those of every module it imports, transitively) instead of sending the whole program to a full
check.

Once the program is lowered the shadow asks `unit-lower` for each unit lowering produced: a module, or a generic instance. The
result is one part per function (`fn:<name>`), the digest of the function's artifact in canonical form: the Core IR with
unit-local type and function ids, local string indexes and no spans, the requests it made of the program's tables, and the
position of every place in another file as a key path, a line and a column. The record reads the unit's `body:` parts of
`module-check` (the digest of the region and dependency context each body was checked in), for an instance the interfaces of the
records its type arguments reach, and, for a position in another module's text, the parts of that module's text up to the line.
An answer the engine serves whose artifacts are not the ones lowering just produced is a finding. `lower_units`,
`lower_served`/`lower_recomputed`, `lower_ahead` (a unit the engine served where the old cache lowered a function of it again),
`lower_behind` (a unit the engine computed where the old cache restored every function), `lower_restored`/`lower_lowered` (the
functions the old cache restored and lowered), `lower_recomputed_functions` (the functions in the units the engine computed) and
`lower_unobserved` (functions lowering built that no artifact describes, so no unit holds them) are in the summary line.

When the engine decides the session's modules (the default) it also keys lowering (G3g step 1): a function that has a `body:` part in
its module's `module-check` answer is keyed by that part, the debug flag, whether it is the entry and the embedded assets
(`lowered-function-v16`), so an unchanged function costs no tree hash, no walk of the declarations it reaches and no references
record (a warm one-line edit at 99k: the lowering stage 364 ms to 132 ms, CPU 17-21% lower). The part covers the function's region of
source and the declarations its signature and body name (a list `T[]` or an option `T?` names its base type), which is what the front end's own
cache trusts to keep a checked body. A generic
instance takes its template's part plus its type arguments and the declaration of every record they are made of (the fields, an enum's
case payloads, array and table elements and keys, a domain's backing type, a buffer's element, a callback's slots, each followed
through the records it names), and the entry module's functions
(named without their module's prefix) are found under the declaring module (step 1b: the lowering stage 364 ms to 94-110 ms at 99k and
1.0 s to 0.45-0.5 s at 400k). A session whose modules the engine does not decide is keyed as before; `SELKA_ENGINE_DECIDE_LOWERING=0`
(placement) keys every function as before. The output is the same either way (`exact.sh`, and 1,210 programs built through one shared
cache and with `--no-cache` are byte-identical).

The optimizer's `final` and `debug` records are stored by name (G3o stage 1, `optimizer_names.zig`): a stored body names its callees by
the digest of their reference, its compound types by stable name (a nominal record by module and name, `ir.Module.nominal`; other
compounds by structure over their children's names) and its source files by key path, and is rebound to the module being built on restore.
Their keys hold no function-table layout and no ordinal, so an added function or record elsewhere no longer misses every final; a name
the module lacks, shares, or holds with another structure refuses the record and the build computes the function (`Statistics.restores.refused`).
The stage records (`inline_leaf`, `inline_cfg`, `unswitch`, `parameter_inline`, the `first_facts` summary) are stored by name too (G3o stage 2), and so are the entries of the optimizer's manifest (stage 3; since G3p they are the rows of two chunks per group of functions, `optimizer-chunk-v3`): a function whose entry is valid stays deferred (not restored raw, digested, inline-checked or analysed), found by its lowering key and resolved against the build's raw module, even when the function table around it moved; only a function whose fusions requested a runtime helper or changed its body is recomputed after such a change, and a build under the manifest's own raw layout works as before. At 99k an added call's optimizer stage fell from 3.5 s to 0.5 s and a type edit's from 2.6 s to 0.6 s; at 400k 10.6 s to 2.1 s for the added call.

**The optimizer's chunks, heads and joins (G3p (a), (d)).** The stored entries of the functions of one group (a module, cut by a hash of the name when it is large: the part
of a function's checked name before the first `::`) are the rows of two chunks (`optimizer_chunks.zig`, scope `optimizer-chunk-v3`), each keyed by the digest of its bytes,
so a group with no changed function writes nothing. The **core** chunk holds, for every function, what a build reads of every function it finds (`optimizer_rows.zig`
`Core`: the digests, the call lists, the final metadata, the effect, the key and graph of each checkpoint, with the names both parts share) and names its **rest** chunk by
digest; the rest chunk holds the field rounds, the exploratory summary and the output digest and inline ancestry of each checkpoint (`Rest`). A build decodes and resolves the
core of every function it finds and reads the rest of a function only when something asks for it (`Index.settle`, counted as `restores.cutoff.settled`): a recomputed
function that is compared with its stored row, a callee a recomputed function reads, a function that is saved in full. The transitive mode (the cutoff's oracle) reads rows
in full. A build that knows the state of its program (the mode, the raw layout and every function's lowering key in table order, `chunks.stateOf`) publishes its
manifest once, as the head of that state (`optimizer-head-v3`), and the generation's record (`optimizer-manifest-v10`) points at it. A build with no manifest of
its own for its raw layout looks the head of its state up: the tree before an edit that was undone, or another worktree of the project when the stage store's
shared half is on (`SELKA_STAGE_SHARED_CACHE`, on by default as the per-user `stage-artifacts` store since 4 November 2026; it also shares the finals, fact payloads, checkpoints and chunks the entries name). An entry from a head is served
only when the store holds the records it names. On the 99k port a fresh worktree of an edited tree bypasses 3,490 of 3,495 functions and analyses none.

**The latest state of a project (G3p round 11).** An edit moves the state of the program, so a fresh worktree that has edited a body asks for a head nobody published. With the
stage store's shared half on, every build that publishes a head also publishes two small pointers beside it (`optimizer-latest-v1`, one record each, `optimizer_chunks.Latest`:
the state whose head is the newest): one for the project under the build's raw layout, one for the project under any layout. The project is the mode and the key paths of the entry
source and of every module merged into it (`chunks.ProjectId`; project-relative, so the same in every worktree), and a body edit moves neither it nor the layout. A build that has
no manifest of its own for its layout, after the lookup of its own state, reads the pointer for its layout and starts from the head it names; a build with no manifest at all
(a fresh worktree) and no match for its layout reads the project's pointer, whose head is then a candidate for the entries that can move, as a manifest of another layout is. The
pointer is a hint and never a result: the head it names is read and checked like any other, every entry it holds is served by its own key or refused, and the records it names
must be in the store. A pointer that is stale (another tree published a later state, or a state of another layout), foreign (another project that spells the same modules), torn,
dangling (its head was collected) or whose records were collected costs the reuse and nothing else. Two trees publishing at once keep the shared store's rule: a record is
published whole under the sequence lock, the later one replaces the earlier, and a pointer goes out in the batch of the head and the chunks it names. A store with no shared half,
or one that does not publish to it, writes and reads no pointer, so a tree that does not share is unchanged. At 99k a fresh worktree's first edit takes the optimizer stage from
3.4 s to 0.17 s (instructions 17.9 G to 3.6 G).

**The joins.** The two field rounds join every function's contribution: the record-field table (the input of the next round), the parameter hull of every callee, and the
return interval each caller's dependency digest holds. The manifest of a program with record types names a record of those joins (`optimizer_joins.zig`, scope
`optimizer-joins-v1`, content-addressed, so an edit that changes no join writes nothing). A build whose deferred functions all came from one manifest stored under its raw
layout, and that holds the hull and field-table digest the joins record holds, visits only the functions it recomputes in the rounds: each is compared with the row the
manifest holds at its place (the return interval, the writes and the functions it opens or lets escape, the call sites that make the hull, the calls its exploration
makes, the functions it takes by reference), and when all are the same the joins stand for every function left alone, whose rows are not read (`restores.cutoff.joined`).
When one differs the build takes the full rounds (`restores.cutoff.rejoined`). `--verify-cutoff` runs the full rounds, checks that no deferred function was recomputed for
its dependencies and that the joins it made equal the stored ones whenever the comparison held, and reads the rows it left unread to check their rest and the arity flag
of their summary (`restores.cutoff.findings`).

A function whose text only moved (a line inserted above it) has the lowering key it had, without the source proof of its own text that
the demand manifest mixes into its entry key (`demand_ir.Context.unmixed`, `Ref.unmixed`, `optimizer-manifest-v10`), so the entry lookup by the mixed key
misses and the function is red. A second lookup by the unmixed key, only under the raw layout the manifest was stored under, finds the entry; the
function keeps from it what no position enters (G3p-0): its exploration rounds when their dependencies are the same (`restores.rounds`), and its
effect when its parameter hull is the same and every function it calls keeps its own (`restores.effects`). A function that calls one the second lookup
did not find, or that has no entry, is recomputed, as the first lookup does for a changed callee. At 99k a comment above the hub module reuses 430 rounds
and 215 effects of its 220 red functions.

These comparisons run only for a shadow that compares: `SELKA_ENGINE_SHADOW_COMPILER=1` with `SELKA_ENGINE_DECIDE_COMPILER=0`
(with the decision on, the default, a shadow exists and compares nothing, and the build notes nothing of lowering or the
optimizer). A unit kind's answer is determined by its argument and its reads, and no unit kind reads a query that names a program
(spec §17.8, G-D13), so a record made for one program is the record of every program that supplies the same: the argument of
`unit-lower` carries the digest of the program's demand on the unit (the sorted checked names of the functions it lowers), and the
argument of `unit-optimize` the digest of what the program supplies to it (the arguments of the lowered units it reads and the
values of the fact parts it reads). `program-facts` names the digest of the units it reads. A generic instance is named under no
module (`Result<str,strings::Error>`): the module that first spells it depends on the program. The `unit-optimize` parts digest a final
body without source positions (G-D14; `Canon.plainDigest`): a line shift moves none of them. The optimizer's own records and
emission's keys keep the digest that covers positions, because an object carries debug information and trap lines.
`unit-emit` (G4a, in shadow) is asked per emitted unit under an argument that holds the digest of the emitter's compact receipt key, which covers positions,
and reads the `opt:` parts of the unit's functions; its payload is the digest of the unit's LLVM text. `SELKA_ENGINE_SHADOW_COMPILER=1` with
`SELKA_ENGINE_DECIDE_COMPILER=0` compares it with what the emitter made (`emit_*` tallies, `unit-emit` findings).

### The engine decides the ownership proofs

The ownership cache (`src/core/ownership_cache.zig`) omits a function's ownership check, and lets the semantic planner stand in
for its body, when the engine's `ownership-proof` record holds a proof of it. There is one record per module and entry
(`ownership_proofs.zig`), a table of parts named `proof:<function>@<16 hex digits of the digest>`, each holding the digest of the
inputs the function was checked under in the run that proved it: the planner's receipt (key, dependency context, region of source)
for a function it stands in for, and the function's body together with the declarations it reaches, with no whole-program prefix, for
any other (`lowering_cache.OwnershipReach`; the declarations a function names are digested as strongly connected components, each
once for the whole program, so a function's reach costs what it names directly, not the size of everything those declarations name). A function is proven while the record holds the digest **this run computed from its own
planning state**; the engine never supplies a digest to stand for one, so a stale record cannot be served. A record keeps up to four
proofs of one function (an edit and its revert, the two sessions of an entry), and a run's proofs are added to the record's; a group
whose table a run changes is published after the check passed, so an unchanged build writes nothing. The first question about a
module reads its record (one open), and the table is kept for the process.

The group's argument is the entry, the ownership mode and the module, so the functions of a module share one record and an edit to one
leaves the others proven. Interim until the front end's own queries are on the engine by default (G2g): the kind reads nothing, because
the planner asks for a proof before any front-end query has run; afterwards it reads its module's `module-check` and `module-passes`
parts, as spec section 17.2 states, and the digests leave its answer.

Verify mode (`SELKA_ENGINE_VERIFY=N`, one in 64 in a Debug compiler) checks one proven function in N anyway; a refusal of one is
the internal error `E_ENGINE_VERIFY` (exit 2). `SELKA_ENGINE_SHADOW_COMPILER` has no ownership part any more: the shadow of G1a, which
compared the engine's record with the pack store's decisions, ran its campaign (`experiments/guest-build-engine-20261031/G1b/REPORT.md`)
and went with the store. Builds remove the `ownership/` directories older compilers left in a work directory.

### The engine decides the modules' prepared keys

The engine decides (G2g), unless `SELKA_ENGINE_DECIDE_COMPILER` is `0` or `off` (placement). Before the front end opens its
per-module plan (`semantic_key.Plan`) it asks the engine, module by module, for the `module-check` record of the module and takes the
module's prepared facts from it when it is valid: a function's stable key, its region digest, its dependency context and the names the
context was collected from. A module whose record is not valid is computed by the front end, and its record is published after the
keys are prepared, whether the bodies then check or not. So an edit to one module's text recomputes that module's keys, and an
importer's only when a name its bodies look up has another digest. The record's query carries the front end's contracts (the compiler's
identity among them) next to the two program-wide flags, because the contexts fold them. The `module-syntax` and `module-interface`
records a check record reads are computed on demand from the parse the front end holds, so a valid record costs no computation. With
the decision off the front end computes every module's keys and keeps none; before G2g it kept per-module records of its own (P4a),
which are gone.

A session that overlays sources decides like any other. The test runner's providers and the stub `main` it appends to an entry are
modules the session reads from memory, and the engine's world reads them the same way (`os_world.Overlay`, installed by the session):
a file the session overlays has no stat tuple, so a read of it is validated by its bytes, and a record made over one text is never
served for another. `SELKA_ENGINE_SHADOW_COMPILER=1` turns on the comparison of the other front-end kinds (the module graph, the
interfaces, the passes and the program's diagnostics) beside the front end; it and the decision are exclusive in a session (the
comparison runs when the decision is off), and neither writes a summary line to the log unless a campaign asks for one
(`SELKA_ENGINE_SHADOW_COMPILER`, `SELKA_ENGINE_VERIFY` or `SELKA_ENGINE_SHADOW_LOG` set).

A unit's computation asks the front end for the bodies it needs with `Session.checkBodiesOf(entry, paths)`: the checked bodies of the
modules at `paths` (project-relative), restored from the checked-body store when their keys stand and checked otherwise, and no other
module's that can be left out. A body of an unasked module whose stored summary stands and whose ownership proof the engine holds is
not checked and not decoded: it is marked in `demandState().omitted`, the mask the stand-in planner and the passes already read, and
`Session.asks(module)` says whom the session was asked for. A module whose bodies changed is checked whoever asks, since the passes
that read it need it. The names a unit reads are stable: a `module-check` part is `body:<name>` of a declaration, its digest covers the
declaration's key, region bytes and dependency context and no position, and the stable key of a function is its module, owner and name,
so adding a function or a record to another module, moving imports or modules, and a comment that shifts every line move none of them
(`frontend_bodies_test.zig`).

`SELKA_ENGINE_VERIFY=N` samples the decision (a Debug compiler samples one in 64 by default, as everywhere): one valid record in N
is withheld from the front end, which computes it, and the two are compared; a record that is not what the front end computes is a
finding (`module-check`), forgotten and replaced. The session's summary counts `decide_served` (keys taken from a valid record), `decide_computed` (keys the front end computed and
the engine then recorded), `decide_withheld` (valid records the sampling withheld and compared) and `decide_rejected` (a valid
record that did not describe the module's functions, forgotten).

### What a summary stands in for

The front end's summary table (`semantic_summary`, one per entry) holds, for each function it checked, the facts the whole-program
passes concluded about it, the diagnostics it and the passes reported inside it, and what its tree needs from a catalog. A function whose
summary stands in *whole* (`stubbable`) has its body neither checked nor replayed, and its passes do not run: the declaration kind admits it
(a foreign, host or conversion declaration is checked for its signature), its diagnostics are stored, and what its tree names can be had
again. A tree that names only declared records is validated by their shapes (`uses.records`, `uses.shape`). A tree that names a
specialization or a type interned while it was checked (`Result[bytes, str]`, a generic record's instance, a structural array) carries
`uses.refs` (G2m): the specializations to register (each with the template it comes from), the records with their shapes and the recipes
that intern the interned ones, and the templates, with spans relative to the function's region. Planning resolves them before the body
loop through the cache's own resolver (`Session.resolveRefs`, the half of a body replay that finds the identities), so the catalog and the
instance list are those a replay would have made; a function whose references do not resolve is not stood in, and a template whose context
changed (or, when the artifacts read callee bodies, whose region did) makes it stale like a callee would. The ordinary functions a
specialization it reaches calls are among the function's callees.

Beside it the table keeps `Notes.complete`, the module-local part of that flag: the function was checked, is not the entry point, holds no
typed hole kept as a trap (a debug build's `todo[T]()` is `E_TYPED_HOLE` to a `check`, and the hole mode is in no key) and every
diagnostic inside it is stored; `module-passes`' per-function digest covers it (`selka-module-passes-fact-v4`). A function that is
`complete` but not `stubbable` (a foreign declaration) is checked as usual and its passes are taken from the summary: its stored facts
stand, the origin rules, the storage rules and the copy and binding warnings do not walk it, and its stored pass warnings are replayed,
once its touched shapes still match. An idiom repair or a site a waiver silenced is stored with a guard (`syntax_hints.Guards`): a digest
of the file-wide waivers of the function's file and of the comment on the line above its region, which the warnings depend on and its
region's own bytes do not hold; the notes stand in only while the guard is the one they were stored under.

`SELKA_ENGINE_DECIDE_PASSES=0` (or `off`; placement) turns the pass stand-in off for a session and leaves the whole stand-in as it was. With
`SELKA_ENGINE_VERIFY=N` one stand-in in N, whole or for the passes alone, is withheld: the function is checked and analysed afresh and its
facts and pass warnings (and, for a whole one, its body diagnostics and its references) are compared with the summary's; a difference is a
finding (kind `pass-stand-in`; `passes_verified` counts the comparisons).

## The report line

`--engine-report` prints one JSON line on standard error, per kind: `served`, `validated`, `recomputed`,
`early_cutoffs`, `verified`, `verify_mismatches`, `unverifiable` (a served query verify mode could not recompute because
the kind has no answer for it now, as a test run's kinds have not), `memo_hits`, `refreshed`, `shared_hits`, `shared_published`,
`shared_mismatches` (the shared tier, below), `object_reads` (stored objects opened because a payload was used: a served
query nobody reads opens none) and `object_misses` (objects found absent or damaged when read), and the nanoseconds spent in `lookup`,
`validate` and `compute`. `selka test PATH --engine-report` prints the same line for the process's engine (the kinds
`test-exec` and `test-report`); a directory run prints the line of the process that runs the entries itself.

## Verify mode

`SELKA_ENGINE_VERIFY=N` (or `--verify N`) recomputes one served query in N, chosen by the first bytes of its key so a
run is reproducible, and compares result digests. A mismatch is the internal error `E_ENGINE_VERIFY`, naming the kind,
the key and the first read whose recorded value no longer reproduces; it means a kind read something that is not in its
record. A Debug compiler samples one in 64 by default; a release compiler does not sample.

## The engine in `selka test`

`selka test` reuses a verdict when the engine's `test-exec` kind holds a valid record of it; the engine is the only thing
that decides. For every test the runner asks whether a record serves the argument this run built; a served pass is reused
(the test is `cached`, with the work its record reports), anything else runs, and the pass is recorded when the entry ends.
An entry's report is replayed the same way, from a `test-report` record, while every file its check read is as it was.
`SELKA_ENGINE_SHADOW=0` turns the engine off: every test runs and nothing is reused or recorded.

| Kind | Argument | Reads | Result |
| --- | --- | --- | --- |
| `test-exec` | a tag (`p` or `i`), the linked program's digest or the test's IR key, a digest of the run's execution settings, a digest of the keyed environment, the test's name | nothing: the argument holds what the verdict depends on | `passed`, then the work the run reported (`steps`, `peak_bytes`); only a pass is ever recorded or served |
| `test-report` | the run's settings digest, the entry's root, the entry's root-relative path, the name filter, the modules a directory run left to other roots | every file the front end read | the report of a complete, successful run and the warnings its check printed |
| `test-facts` | a 32-byte key: a lowered function's raw digest, places and declaration catalog (a fact), the digest of a group's fact keys, or the digest of a chunk of callee identities, each carrying the test-runner stage's identity | nothing: the argument holds what the value depends on | the encoded fact (the function's canonical digest and its callees), a group's facts, or the chunk |
| `test-graph` | a 32-byte key: the entry's source path (the head) or the digest of a chunk's bytes | nothing | the encoded head (the manifest of one generation of the test call graph) or a chunk of its nodes, tests or indexes |

A test run's check is decided by the engine as a build's is: `module-check` decides each module's prepared keys, in a root's
own check and in the check a directory's roots share, and the runner's key derivation keys each lowered function by its
`body:` part, so it hashes no body tree (stage 4 of the test-loop plan). A function without a part is keyed by its tree, and
`SELKA_ENGINE_DECIDE_LOWERING=0` keys every one by its tree; a test's key is the same either way, since it is the digest of
the lowered program and not of the lowering's key. A provider group's program is not the one the parts describe, so its
functions are keyed by their trees.

A root's facts are read by groups: the functions with a fact key are cut into groups of about six by a hash of their names, and
each group is one `test-facts` record of its members' facts, keyed by the digest of their fact keys. A group no function of
which changed is one record read; a group whose record is missing or does not describe its members reads each member's own fact,
recomputes the ones that miss and is recorded again. The facts a run uses are the same either way, and
`SELKA_TEST_FACT_GROUPS=0` reads each function's own record (stage 4 of the test-loop plan);
`cache.work.producer.facts.groups` counts the groups one record served.

An entry's report reads each module source it was checked from through `module-tokens` (stage 6 of the test-loop plan),
not by its bytes: the kind lexes the file and returns the digest of its tokens, each with the bytes before it on its own
line (or, for the first token of a line, the line's indentation), so a comment reworded or added, a blank line, trailing
whitespace and the line numbers that follow from them change no read, and the report is replayed. A string, a docstring, the
indentation, the spacing inside a line or any token is a changed read, and the entry is checked again. A module that a
diagnostic the check printed names, and every file that is not a module source (the cases file, the configuration, embedded
assets, interface files), is still read by its bytes. A report is recorded twice, under two arguments: once reading every file
by its bytes, which an unchanged run validates by the files' stat tuples alone and asks first, and once with the sources read
through `module-tokens`, which it asks when the first has gone stale; a report found that way is recorded again under the files'
bytes, so the next unchanged run is as cheap as before. `SELKA_TEST_TOKEN_REPORTS=0` (placement) records and asks only the
first, as before stage 6.

`test-facts` and `test-graph` are the test runner's planning metadata, which were the stage store's `core-test-function-facts-v2`,
`core-test-function-edges-v1` and `test-graph-*` scopes. They never certify a test: a fact or a chunk is checked against the
function or the digest it names when it loads, and a record that does not describe its subject only loses reuse. The runner hands
the kind the value it computed when it records one, as it does for `test-exec` (`test_records.zig`), and a process with no engine
(`SELKA_ENGINE_SHADOW=0`) records and finds none.

The kinds' code identities are the closure of their roots plus the runner code each covers
(`src/build_identity_rules.zig`: `test_exec_covers`, `test_exec_boundary`, `test_report_covers`); `selka engine closure
test-exec` lists it, marking the covered files. The result digest of a `test-exec` record is the verdict word alone, so a
rerun that reports other numbers is the same result. The runner builds and runs a selection's tests in processes of its own,
in batches, so it decides before running (`Engine.peek`: a served answer, never a computation) and hands the verdict it found to
the kind when it records one; the kind's body returns that verdict.

**What may be asked (D-48).** The engine is asked only with arguments this run produced: the IR key of the check that
just ran, the digest of the program the build just produced, the run's settings and keyed environment, the test's name. They
are built in one function (`test_runner_engine.argumentOf`) from digests the call sites pass by value, and no call site reads a
stored argument to ask with. A record under a key the run did not produce is never reached, so an edit that changes a test's
program changes the key it is asked under and the old pass is not served for it. The one record served without such a key is
the entry's report: its argument is the settings digest, the root and the filter, and its reads are every file the check
read, so it is served only while each of them is as it was seen. What an IR key covers, and why a record under it is served
only for the program it saw, is `experiments/incremental-engine-20261030/C2e/DECISIONS.md` (D-42).

A test has up to two arguments: the one keyed by its IR key (every test the runner can reuse has it, linked or not) and the one
keyed by its linked program (a test consulted at the execution tier has it, which survives a compiler edit that leaves the
program unchanged). A test that passed, ran or reused, is recorded under every argument it has in the run, so the next run finds
it whichever way its key moved. A test that fails is never recorded.

**Checking a reuse.** When `SELKA_ENGINE_VERIFY=N` is set, one served `test-exec` record in N (by its key) is checked: the
runner runs the test anyway and compares the fresh verdict with the record. A fresh failure is a `verify` finding and counts in
`verdict_differs`. A Debug compiler's default sampling (above) is the engine's own and does not check a run's reuses, so
which tests a run reuses never depends on the keys it draws. A record that served a pass the test now fails is wrong: the
run removes it (`Engine.forget`: the memo, the work directory's store and the shared tier), so no later run serves it
again, and a later pass is recorded afresh.

The log holds one JSON line for each finding and, when a process ends, one `summary` line with its counters: `asked` (tests
the engine was asked about), `reused` (served and not run), `ran`, `checked` (served records run anyway), `replayed` (tests of
reports replayed), `verify`, `verdict_differs`, `local_only` (records the shared tier's rule kept local), `unobserved` (tests of
runs the engine does not decide: forced, `--against`, native links, a loader override) and `spent_us`. A forced run reuses
nothing, but its passes are recorded and the next unforced run finds the engine warm. A log past 64 MiB takes no more lines.

```text
SELKA_ENGINE_SHADOW_LOG=PATH   where the lines go; unset, <cache-dir>/engine-v1/shadow.jsonl; @user is the per-user log
                                $XDG_CACHE_HOME/selka/engine-shadow/shadow.jsonl (else ~/.cache/selka/...)
SELKA_ENGINE_SHADOW_TAG=NAME   written as `tag` on every line the process logs, to read one session's lines from a shared log
SELKA_ENGINE_VERIFY=N          verify mode's sampling (above); the runner checks one served record in N
SELKA_ENGINE_SHADOW=0          the engine is off
python3 scripts/engine_log_summary.py LOG [--examples N] [--json] [--tag NAME]
```

The summary script prints the totals and the findings with the first examples, and exits 1 when the log holds a finding. The
variables are placement in `src/environment_identity.zon`: they check a result and never change one. The complete gate's
language suites and `scripts/edit_check.py`'s guest runs set verify sampling to 16 and the log to `@user`. (Logs written while the
receipts decided and the engine observed carry `old_reuse`, `soundness` and `efficiency` and are read by
`scripts/engine_shadow_summary.py`.)

A test with no `test-exec` argument is never reused: its call tree reaches a `Host` capability, a host function or an `extern func`
(the program declares one), has no checked body, or invokes a callback beside `function_digest` or takes a callable as input
(`test_runner_portable.refusal`). Its `--json` cache reason is `live-effects: ` followed by what stopped the proof and the function
it was reading. A callback invoked through a local, a record field or a parameter is no such case: the analysis follows every
function value the call tree creates, and a callback can hold only one of them, so the test is keyed and reused like any other (a
test that builds an evaluator holding its recursion hooks was refused until 5 November 2026, which kept 586 of the G3 port's 1,250
tests running on every invocation).

## The shared tier

Records of the kinds an engine `share`s are also kept in a per-user tier, so a tree that never ran a program or compiled a
module is served what another tree ran. There are two tiers, one for each kind of work, behind one interface
(`engine/shared_tier.zig`: fetch, contains, publish, forget, and for the compiler's tier fetch and publish of objects):

- **The compiler's tier** (`engine/compiler_records.zig`) holds the records of the front end's kinds (`module-syntax`,
  `project-graph`, `module-interface`, `module-check`, `noalloc-closure`, `module-passes`, `program-diagnostics`) and of
  `ownership-proof`, and the objects their payloads point to. It lives in the compiler artifact store
  (`compiler-artifacts-v2`, the directory `SELKA_COMPILER_SHARED_CACHE` or the per-user default names; `--no-cache` and an empty
  variable turn it off) as two tiers beside `syntax`, `typed` and `program`: `engine_record/<key>.blob` and
  `engine_object/<digest>.blob`, each entry under the store's header (key, size, BLAKE3 of its bytes, checked by every reader), its
  per-key publication lock, lease, 10 GiB size policy and retention (`selka cache gc --kind compiler`). A record's object is
  published first, so no record names an object the tier lacks; an object is fetched only when a caller first uses a served
  payload (the lazy restore of §5), must hash to its name, and is copied into the tree's own store. A result that is a miss
  (absent, damaged or evicted object) is computed again, as it is for a local object. A record the work directory serves that the
  tier may lack is checked from the tier entry's header, which holds its size and the BLAKE3 of its content (`Tier.holds`): a stat
  and one small read, with no read of the content, and the entry's recency is refreshed only when it is an hour old. The engine
  reads, decodes and compares the tier's record only when the header is not the local record's (another variant, or the same
  result with other stat tuples). The tier is asked about a kind's served records once an hour, not on every build: a partition
  of the work directory carries a `.swept` stamp (the time, and the digest of the tier's directory), and a process that finds
  none, an older one, or one made against another tier asks about every record it serves and stamps the partition when it ends
  (`Engine.sweeping`; `Policy.sweep_interval_ns`). A record a build computes is published to the tier when it is computed, and
  one it takes from the tier is already there, so the sweep only fills a tier that was off or busy, restores an entry the tier
  lost, and refreshes recency. The unit kinds (`unit-lower`, `program-facts`, `unit-optimize`) are not shared yet: their keys
  cover program positions until G3g and G4a.
- **The native test store's tier** holds the `test-exec`, `test-facts` and `test-graph` records, described below.

Every key in either tier is made of project-relative names (spec G-D11): a module is named by its path under the project root,
a test entry by its root-relative realpath (`entry_name.zig`; `ownership-proof` uses it for a headerless entry too, so
`selka check /abs/app/main.selka` and `selka check app/main.selka` keep one set of proofs), and everything else by digest. The
absolute root is read by the engine's world (`OsWorld.root`), never written into a key or a read.

The test store's tier works as follows. It is the `engine/` directory of the native test store (`native-tests-v3`, the one `SELKA_TEST_SHARED_CACHE` or the
per-user default names), one file `<key>.rec` per record, under the store's lease, size policy and retention: `selka cache gc
--kind tests` previews and applies it. A record is addressed by its key (kind, code identity and argument
digested), so the same record in another tree is the same query; it is served only while every read it holds still holds, as a
local one is, and the served record is copied into the tree's own store. A local miss consults the tier; a computed record is
published to it; a record served locally that the tier lacks is published too. A publication that finds another result under
the same key keeps the tier's record, logs the pair in the store's `mismatches.log` (`mismatch engine KEY existing=... attempted=...`)
and counts `shared_mismatches`; a collection that holds the store makes the publication a skip. Only kinds the engine `share`s use
the tier (`test-exec`, `test-facts` and `test-graph`; `test-report` names this tree's paths and stays local), and, in this tier, a
record with an object payload stays local.

Not every `test-exec` record is shared. The earlier design shared a result across worktrees only when the test was provably portable
(`test_runner_portable.shareable` for a result under the test's IR key, `executionRefusal` for one under its program's
digest: a source or an asset outside the project root, configuration the key cannot name relative to the root, an extern, a
callable digest and an error trace each keep a result private), and the tier applies those two rules
(`test_runner_eligibility.zig`): a record the rule refuses is published nowhere and looked up nowhere but in the work
directory, which is where every keyed test's record lives. The rule is applied the first time the tier is consulted for a
record, not up front, and the summary line counts the records it kept local as `local_only`.
