# The incremental engine (spec, part 1)

Status: part 1 accepted (30 October 2026). §17, part 2's compiler kinds (31 October): targets and deletions accepted by
the user (G0d); the kind-by-kind design is the coordinator's and is refined as the lanes land.
Plan: `docs/audits/incremental-engine-plan-2026-10-30.md` (N1). Evidence:
`experiments/incremental-engine-20261030/N0/INVENTORY.md` (cited as "N0 §n"). Part 1 builds the core (C1) and moves the
`selka test` receipts onto it (C2). The spec is language-neutral: a later Selka core reads and writes the same records,
keys and store, and passes the same test vectors.

## 1. What the engine does

A computation the engine runs is a **query**: a function of an argument and of whatever it reads through the engine.
The engine records what each query read and what it produced, stores that record, and serves the result again while
every read still sees what it saw. When a read changed, the query is recomputed; when the recomputed result is the
same, the queries that read it are still valid (early cutoff).

It replaces, consumer by consumer, the hand-built version of this in each cache: declared key lists, per-cache identity
choices, per-cache locks and retention (N0 §1: 46 rows, five concurrency mechanisms, five retention mechanisms, and
only two rows that record their reads end to end).

The model is Salsa's (rust-analyzer): validation on demand, walking a query's recorded reads. It is not Skyframe's
persisted reverse graph: N0 §5.2 and §5.3 measure restores that cost as much as recomputes (ownership proofs 1.7x,
checked bodies 1.0x), and a reverse graph is one more store to load before anything is served.

## 2. Terms

- **Kind**: a named query implementation (`test-exec`, `test-plan`, later `ownership-proof`). Each kind has a **code
  identity** (§3).
- **Argument**: canonical bytes the caller passes (digests of values, names, small settings). Never a path to read.
- **Key**: the record's address, `BLAKE3-256("selka-engine-key-v1" || kind || code identity || argument)` with each
  part length-prefixed (u32 little-endian).
- **Read**: one observation a query made through its context (§4), with what it saw.
- **Result**: the query's payload bytes and its **result digest** (BLAKE3-256 of the payload, unless the kind defines a
  smaller identity of its result).
- **Record**: key, kind, code identity, the reads in order, the result digest and the payload (inline or by object).
- **Object**: content-addressed bytes in the store, named by their digest.

## 3. Code identity

A kind names its implementation roots (Zig files, for the Zig core). Its code identity is the token digest of the import
closure of those roots, `@embedFile` targets included, chained with the identities it depends on, computed at build
time by the same machinery as the stage identities (`src/build_identity_rules.zig`, `build_identity.zig`). The closure
walk refuses a non-literal import or embed, as it does today.

- A comment or a layout change keeps every identity (token digest, as the compiler identity does now).
- `selka engine closure KIND` (developer command) prints the closure and the identity, so "why did this rekey" has an
  answer (N0 §7 point 4: a neutral edit to `stage_compression.zig` rekeys three stages; `sema.zig` sits in the runner
  identity and misses every guest receipt).
- The runner identity's hand-kept list of 22 files (N0 §6 row 1) becomes the closure of the `test-exec` kind's roots.

## 4. Reads

A query receives one handle, `*engine.Context`, and reads only through it. The vocabulary is `src/core/inputs.zig`'s,
extended:

| Read | What is recorded | Unchanged when |
| --- | --- | --- |
| `file(path)` | the bytes' digest (null: looked for and absent), and the stat tuple seen around the hash | the stat tuple is unchanged outside the racy window, else the digest is unchanged |
| `exists(path)` | present or absent | the same |
| `listing(path, filter)` | the digest of the sorted names the filter keeps | the same digest |
| `variable(name)` | the value or its absence; a **placement** variable (`environment_identity.zon`) is recorded as read but never compared | the same value |
| `tool(path)` | the tool's identity (the toolchain identity of `tool_identity.zig`) | the same identity |
| `query(kind, argument)` | the dependency's key and its result digest | the dependency, validated in turn, has the same result digest |
| `part(kind, argument, names)` | the dependency's key, and for each named part its digest or that it is absent (record format 2, §17.3) | the dependency, validated in turn, has the same digest for every named part (or still lacks it) |

Rules:
- **No raw access.** The files that implement a kind (its closure, §3) use no `std.fs`, `std.Io.Dir`, `std.process`
  environment access or `std.os` file calls. A test scans each kind's implementation files and fails on one (the K5
  rule of the provable-cache plan, never built until now). A read the context cannot express is a context feature to
  add, not an exception.
- **Assumptions stay stated.** The kernel's timestamp granularity (the racy window), the immutability of the loader and
  libc during a process, and the language's capability-stand-in rule (N0 §6 rows 9, 10, 15, 19) are configuration of
  the context, written down in one place, not reads.

## 5. Running a query

`ctx.query(kind, argument)`:

1. **Memo.** A process-wide table maps a key to its validated result for this process's revision. A key validated once
   is not validated again in the process (the test runner's 297 sessions share it).
2. **Lookup.** One open of the record file named by the key (§7). No store-wide index is loaded or scanned.
3. **Validate.** Walk the record's reads in order. A file read checks its stat tuple (one `stat`, memoized per path per
   process revision) and hashes only when the tuple moved. A query read validates the dependency first and compares its
   result digest. The first changed read stops the walk.
4. **Serve or recompute.** All reads unchanged: serve the payload. Otherwise run the kind with a fresh context, record
   its reads, compute the result digest, publish (§8) and serve. A recomputed dependency whose result digest is
   unchanged leaves its dependents valid (early cutoff).
5. **Cycles** are an error naming the cycle.

**Lazy payloads.** Serving (step 4) hands back a result handle, not the payload's bytes. A record that holds its payload
inline serves it at once; one that names an object serves the digest, the parts and a handle, and the object is opened
when a caller first asks for the payload. Validation never reads or hashes an object: it trusts the record's trailer, and
the object's name is the digest the first use checks. A dependent that reads a dependency with `query` or `part` compares
digests and never opens the dependency's object. An object absent or not hashing to its name at first use is a miss: the
query runs again, publishes its record and object (a damaged object is deleted first, so the new one is written whole), and
answers the new payload; a rerun that gives another result digest or parts table than the record promised is the verify
error of §10. Per-part digests are in the record, so a part read never touches an object. Verify mode (§10) reads the
objects of the queries it samples.

**The cost rule.** Serving a query costs the reads of the queries it touches and one record open per query, never the
size of the store. N0 §5.2's largest line (half an unchanged `tests/lang` rerun spent re-indexing 347 packs per session,
58,304 pack opens) is the failure this rule forbids. A kind whose measured restore exceeds its recompute by more than
10% is a hard stop for that consumer (plan §7).

## 6. Granularity

A query should cost at least about 100 times its validation. A kind finer than that (a per-declaration check, a
per-function proof) uses a parent query that groups its members and records one read per member's input digest, so
that validating the parent validates them all with one record open. C1 measures the per-read and per-record costs
(plan §3 budgets) and states the threshold in numbers.

## 7. The store

Root: the work directory (`--cache-dir`, default `.selka-cache/core`) gets `engine-v1/`. A per-user shared tier is a
later part.

```
engine-v1/
  records/<kind>/<code identity, 64 hex>/<key[0..2] hex>/<key hex>.rec
  objects/<digest[0..2] hex>/<digest hex>
  inflight/<key hex>
```

- One file per record, published by write-then-rename (§8). There is no journal, no pack, no index and no per-record
  lock (N0 §8 finding 5: the stage store took its `sequence` lock 35,377 times for 39,606 records).
- Payloads over 4 KiB are objects shared by every kind; smaller ones are inline.
- **Partitioned by code identity**, so a session never sees another compiler's records (the ownership-store lesson).
  Retention keeps a kind's current identity directory and its two most recently used others (a `.last-use` stamp, as the ownership
  store's partitions did), and retires the rest under the work directory's existing lease (`work_retention.zig`).
  Objects not named by a live record and older than 14 days are collected by the same sweep.

## 8. Concurrency

- **Readers take no lock.** A record is either the old file or the new one (rename is atomic); a torn or corrupt record
  (trailer mismatch, §9) is a miss.
- **Duplicate work is allowed.** Two processes may compute the same key; both publish the same bytes, and the second
  rename replaces the first with identical content.
- **In-flight marker for expensive kinds.** A kind may declare itself expensive (a test execution). Its first computer
  writes `inflight/<key>` (pid, start time, host). Another process seeing a live marker polls for the record for at most
  the kind's wait bound (default 30 s), then computes itself. A marker whose pid is gone is ignored. This replaces the
  blocking claims that made gates wait about 250 s (N0 §7 point 3).
- **Maintenance never blocks a reader.** The sweep renames an entry aside before deleting it, and never holds a lock a
  query waits on (N0 §5.4: a build waited 12.4 s behind the store timer's exclusive phase).

## 9. The record format

Little-endian; strings and byte blocks are a u32 length followed by the bytes; digests are 32 raw bytes.

```
magic            8 bytes  "SLKREC01"
format           u32      2 (1 is still read)
kind             string
code identity    digest
key              digest
argument         bytes
result digest    digest
payload          u8 tag (0 inline, 1 object) then bytes (inline) or digest (object)
parts            (format 2) u32 count, then each part, in byte order of the names with none twice:
  name string, digest
reads            u32 count, then each read:
  tag u8: 1 file, 2 exists, 3 listing, 4 variable, 5 tool, 6 query, 7 part (format 2)
  file:      path string, u8 present, digest (if present), stat tuple (u64 inode, u64 size, i64 mtime ns, i64 ctime ns)
  exists:    path string, u8 present
  listing:   path string, u8 filter, u8 opened, digest (if opened)
  variable:  name string, u8 set, value string (if set), u8 placement
  tool:      path string, digest (tool identity)
  query:     kind string, key digest, result digest
  part:      kind string, key digest, u32 count, then each named part, in byte order of the names with none twice:
             name string, u8 present, digest (if present)
trailer          digest   BLAKE3-256 of every byte before it
```

A reader rejects an unknown magic or format, and a trailer mismatch, as a miss. The Selka codec of L1d (fixed-width
integers and u32-prefixed blocks) reads and writes this format; the varint forms are not used here.

**Format 2** (part 2, §17.3) adds the parts table beside the payload and the part read (tag 7). A writer writes format 2.
A reader reads both formats: a format 1 record has no parts table and no part reads (a tag 7 in it is malformed), so it
reads as a record with an empty table. A read tag no reader knows, a parts table or a part read whose names are out of
order or repeated, and a format later than the reader's are each a miss, never a crash. The frozen format 1 vectors
(`records.json`, `validation.json`) stay and pass; format 2 has its own (`records2.json`, `parts.json`).

## 10. Verify mode

`SELKA_ENGINE_VERIFY=N` recomputes one in N served queries, chosen by the key's first bytes so a run is reproducible, and
compares result digests. A mismatch is an internal error `E_ENGINE_VERIFY` naming the kind, the key and the first read
whose recorded value no longer reproduces. A Debug compiler defaults to N = 64; a release compiler defaults to off; the
complete gate runs the language suites with N = 16.

## 11. Observability

- `--engine-report` prints one JSON line per command: per kind, served, validated, recomputed, early cutoffs, verified,
  verify mismatches, and the time in lookup, validation and computation.
- `selka engine explain KIND ARGUMENT` prints, for a record that would not be served, the first read that changed and
  what it saw then and now.

## 12. The component protocol

A query may be computed by another process (a self-hosting component, the cache planner child of N0 row B18). The
request carries the kind, its code identity, the key, the argument and the payload digests of the query reads it was
given; inputs travel as objects in the store, by digest. The reply carries the result digest, the payload (or its object
digest) and the reads the component made, in this spec's read vocabulary. **Shadow mode** runs both implementations and
records any result-digest disagreement; it is how a Selka component replaces a Zig one, and how C2 replaces the old
receipts.

## 13. The first consumer: `selka test` receipts (C2)

Two kinds:

- `test-plan(entry path digest, settings)`: reads the entry's module files and listings, the keyed variables and the
  embedded standard library's identity; result: the entry's tests and, for each, the argument of its `test-exec` query.
  It lets an unchanged entry skip the front end entirely (N0 §7 point 1: the receipt lookup now comes after check,
  lowering and the pack index, 68% of the warm rerun's CPU).
- `test-exec(program digest, test name, settings)`: reads the linked program (a `query` read of the link step's result
  digest), the runner's settings, the keyed variables; result: the verdict and the output digest. Expensive (§8).

Shadow: the old receipt decision and the engine's decision for every test of every gate and edit check, logged; an
engine reuse where the old code reruns is a soundness disagreement (a hard stop until explained). The 196 tests that
never get a receipt today (`test_runner_portable.zig:reusable`, N0 §8 finding 6) keep today's refusal in part 1; whether
recorded reads lift it is a decision for the C2 review.

## 14. The second consumer, as a design note (not part 1)

Ownership proofs (N0 §7, second): one `ownership-proof` query per function, keyed by the function's digest and the
proof's code identity, reading its callees' proof results; grouped per module (§6), so validating a module's proofs is
one record open and one read per function. This is the shape that removes the 50.4% line for good, beyond lane D's
interim index fix.

**Interim form (part 2, G1).** Until the front end's own queries are on the engine by default (G2g), `ownership-proof` reads
nothing, and its group carries the digest of each function's proof inputs as the front end computes them in the run that proves it
(the semantic planner's receipt, or the function's body and reach). The planner asks whether a proof is held before any front-end
query has run, so it cannot read `module-check` parts yet; and a record is never taken for the digest of a run that did not
compute it: the front end compares a part with the digest it holds now. At G2g the kind reads the `module-check` and
`module-passes` parts of its module (spec §17.2) and the digests leave its answer.

## 15. Test vectors

`test/engine/vectors/` holds JSON vectors, generated once by C1 from the definitions below, reviewed, and frozen (a
change needs a format bump):

1. **Keys**: three (kind, code identity, argument) triples, including an empty argument and a 1 MiB argument, with the
   expected key.
2. **Records**: two records, one using every read tag and an inline payload, one with an object payload, as hex bytes
   with their trailer.
3. **Validation scenarios** over an in-memory filesystem: an unchanged file (served), a touched file with the same bytes
   (served after one hash), a changed file (recomputed), a dependency recomputed to the same result (early cutoff), a
   placement variable changed (served), a keyed variable changed (recomputed). Each lists the expected served and
   recomputed counts.

## 16. Decisions

| # | Decision | Evidence |
| --- | --- | --- |
| E1 | Validation on demand over recorded reads, no persisted reverse graph | N0 §5.2-§5.3: restores at 1.0-1.7x recompute; a reverse graph is one more store to load |
| E2 | One file per record, atomic rename, no journal, pack, index or record lock | N0 §5.2 (pack re-indexing, 58,304 opens), §8 finding 5 (35,377 locks for 39,606 records) |
| E3 | Partition records by code identity; keep the current and two others | the ownership-store growth (lane G, D12); N0 §5.2 |
| E4 | Readers never block; in-flight markers with a bounded wait for expensive kinds; duplicate work allowed | N0 §5.4 (12.4 s wait), §7 point 3 (about 250 s waits behind claims) |
| E5 | Code identity is the import closure of the kind's roots, shown by `selka engine closure` | N0 §6 row 1 (the runner's hand list), §7 point 4 |
| E6 | The read vocabulary is `inputs.zig`'s plus `tool` and `query`; placement variables recorded, not compared | B13 already records files, listings and variables end to end (N0 §1 point 2) |
| E7 | BLAKE3-256 digests, fixed-width little-endian record format | the compiler already digests with BLAKE3; the Selka codec (L1d) reads fixed widths |
| E8 | Verify mode samples served queries; Debug 1/64, gate 1/16 | soundness is the failure that cannot be seen any other way |
| E9 | First consumer the test receipts; second the ownership proofs | N0 §7 scoring (7 and 7 of 12) |

## 17. The compiler's kinds (part 2; draft, 31 October)

Plan: `docs/audits/guest-build-engine-plan-2026-10-31.md`. Evidence: `experiments/guest-build-engine-20261031/G0b/`
(cited as "G0b" with its row ids) and G0a's baseline (§17.10, pending). This section turns the plan's §3 sketch into
the kinds the lanes build. The user reviews §17.2's targets in the plan and §17.7's deletion list (decision D2); the
coordinator owns the rest.

### 17.1 Units, names and paths

- **Three sorts of unit.** A *module unit* is one source module. An *instance unit* is a generic template with its type
  arguments, named by the template's stable name and the arguments' structural digest. A *helper unit* is a runtime
  helper, named by its name and signature. At 99k there are 156 module, 221 instance and 91 helper units plus the entry;
  at 400k, 808, 409 and 64 (G0b EM-1). Every kind after the front end takes a unit as its argument.
- **Stable names, never positions.** Modules are named by project-relative path. Functions are named by unit and
  declaration name. Records and types are named by structural digest, or by module and name for nominal ones. Each
  generated family (thunks, workers and the seven others of G0b LW-13..20) is named by its creating function's stable
  name and a counter local to that function. No stored key or argument holds a program position (G0b §3 lists the
  eleven that do today).
- **Project-relative paths** in every argument and every `file` read. The project root's absolute path is never part of
  a key, so two worktrees of one project share records through the shared tier (G0b EM-30, FE1-40).

### 17.2 The kinds

Module and unit kinds group their members (declarations, bodies, functions) per §6: validating one costs one record
open and one read per member, and a recompute reruns only the members whose input digest changed.

| Kind | Argument | Reads | Result parts |
| --- | --- | --- | --- |
| `project-graph` | entry, settings | the entry; each module's `imports` part | module order (canonical by path), import-cycle and budget errors, program flags (`std_result`, the module-graph bit) |
| `module-syntax` | path | `file(path)` | `imports`; a digest per declaration and per body |
| `module-interface` | path | its syntax parts; the parts of imported interfaces it names (projection, §17.3) | a checked-declaration digest per declaration (types, signatures, layouts) |
| `instance` | template, argument digest | the template's interface part and body digest; the arguments' structural digests | the instance's checked signature and body digest |
| `module-check` | path | its syntax and interface; imported interface parts; the instances it uses | a checked-body digest per body; its diagnostics with (module, local span) |
| `module-passes` | path | its check result; the summary parts of the callees it reads | per function: the ownership plan, allocation contracts, origins, warnings, `inferred` |
| `program-diagnostics` | entry, settings | `project-graph`; each module's diagnostics part | what `check` prints: today's three gates and the global order, applied over per-module results (G0b FE2-2, 6, 36, 44) |
| `ownership-proof` | path | its passes result; the callees' proof parts | a proof result per function (no `Catalog.prefix`, G0b FE1-20) |
| `unit-lower` | unit, demand digest | the unit's checked bodies; the declaration digest of every record, type, signature and function it reaches, recorded as lowering reads them (projection) | per function: Core IR with unit-local ids, and an op log of its table effects (G0b answer 2) |
| `program-assembly` | entry, settings | `project-graph`; each unit's lowered digest | the program tables, by replaying the op logs in canonical order; positions exist only in this process |
| `program-facts` | entry, settings, digest of the units read | each unit's lowered summary part | per function: parameter hulls, address-taken, field hulls, `closed`, effects, inline class; the runtime-helper set (G0b OP-13, 20-34) |
| `unit-optimize` | unit, level, digest of what the program supplies | its lowered functions and the lowered bodies it inlines (projection); no query that names a program (G-D13) | per function: optimized IR, canonical and without source positions (G-D14) |
| `unit-emit` | unit | its optimized functions; its linkage (§17.5); descriptors | LLVM text digest |
| `unit-object` | text digest, toolchain, mode, target, CPU flags, runtime ABI | `tool()` | the object (the B9 store) |
| `program-link` | entry, settings | every unit object, in canonical order; the runtime objects | the linked program (B11) |
| `build` | entry, settings, keyed environment | `project-graph`; `program-link` | the program: the replay record's role, so an unchanged build validates by `stat` alone |

A unit kind's argument is not only the unit. What a program demands of a unit (the functions and instances it lowers) and the facts
it supplies (the intervals, effects and program flags its functions and their callees read) differ from program to program, and
without them in the argument the record of one program would validate in another and be wrong there (G-D13). `demand digest` is the
digest of the sorted checked names of the functions the program lowers of the unit; the digest of what the program supplies to
`unit-optimize` is the digest of the arguments of the lowered units it reads and the values of the fact parts it reads. Both are
computed in the run that asks (D-48).

Release builds keep one whole-program unit: `program-release` reads every `unit-lower` result and the facts, and
optimizes and emits once. Part 2 does not make release edits faster.

### 17.3 The projection read

`part(kind, argument, names)`, record tag 7: the dependency's key, and for each named part its digest. It validates the
dependency, then compares only the named parts. Lowering module M then depends on the declarations of N that M
reaches, not on all of N (G0b LW-24); a per-declaration kind would be below §6's granularity rule. The record format
becomes 2. Format 1 records stay readable, and a reader that sees an unknown tag treats the record as a miss.

**Parts.** A query publishes parts with `ctx.exposePart(name, digest)`: a table of names and digests, kept in byte order
of the names, that travels in the record (not in the payload, so a part read opens no object). A name published twice must
give the same digest, or the kind fails. The digests are the kind's to define (the digest of a declaration, of a body); the
engine only compares them. A part is a fact about the payload, so the table must be a function of the payload: verify mode
compares it as well as the result digest.

**Reading.** `ctx.part(kind, argument, names)` answers the digests of the named parts, in the order of `names`, null for a
part the dependency does not publish. It answers digests only, never the payload: a query that needs the bytes reads the
dependency whole with `query`, and then it is valid only while the whole result is. The names are sorted and repeated names
dropped before the read is recorded, and a second read of the same dependency with the same set of names returns the first
answer without a second record entry, so the recorded read does not depend on the order the kind asked in.

**Validating.** A part read is valid when the dependency, validated or recomputed in turn, has for every named part the
digest it had, or still lacks it. A dependency recomputed to a table that agrees on the named parts is an early cutoff
(counted as one, as for a `query` read), whatever its payload or its other parts now are. Read what you depend on, not
the neighbourhood: a part read that names a part the dependency never publishes is valid forever, so a kind names the parts
its computation actually consults.

### 17.4 Canonical orders

Every order that follows discovery today becomes canonical, by stable name: functions in a unit, units in the link,
helper declarations, generated names, and the optimizer's inline phase and recursion entry (G0b EM-2, EM-27, OP-20,
OP-26). Emitted bytes change once, when G3 and G4 land. Exactness is then "equal to `--no-cache` of the same compiler"
(what `exact.sh` checks today), never byte-equality with an older compiler. G0f's probe U1 measures whether the inline
phase and recursion entry can be made order-free without changing the optimized result's quality.

### 17.5 Linkage

A debug unit's linkage is decided from its own module's source. A function is `hidden` when its module's interface
exports it, or when a generic template body in that module calls it, because an instance unit in another place calls it
by name. The compiler-generated callable-digest functions, which library code calls from the user's unit, are `hidden`
too. Every other function is `internal`. Today the choice depends on callers in other units, so a module's text
changes when another module changes (G0b EM-3). G0f's U12 fixtures confirm that an instance resolves names in its
template's module and may call that module's private functions; the inliner copies only call-free bodies, so an
instance never gains a callee it did not name. G4a verifies the rule against the EM-3 probe.

### 17.6 What stays program-wide

`project-graph`, `program-diagnostics`, `program-assembly`, `program-facts` and `program-link` read every unit, but only
as digests. Validating one costs one record open and one comparison per unit. They recompute only when a unit's part
changed, and then cost what today's whole-program step costs. Their recompute cost after a one-line edit is the main
term of the floor (§17.10).

### 17.7 What is deleted and what is kept (for the user's review)

**Deleted** (about 8,400 lines today, measured at G5a):
- **The stage store:** `stage_store.zig`, `stage_pack.zig`, journals, compaction, roots, the collector, leases,
  `stage_scopes.zig`, and the opt-in shared stage tier.
- **Lowering's keys:** the guard, the discovery counts, `validPrefix` and `FinishRecord`; the front end's omission
  decision, the whole-tree retry and the `.unreachable` receipts; the demand generations.
- **The optimizer's reuse machinery:** `optimizer_shortcut.zig`'s candidates and manifest; the whole-program layout gate
  (`ir_snapshot.layout` in keys).
- **Emission's compact receipts.**
- **The front end's caches:** the checked-body store's keys and the frontend cache's entries (A1-A3).
- **The ownership pack store** and its partition (B6).
- **The replay record** (B13), whose role passes to the `build` kind, and the stage parts of `work_retention.zig`, which
  pass to the engine's retention.

**Kept:**
- the unit object store (B9) and the runtime objects (B10);
- the linked-program store (B11), as engine objects;
- `--link` objects (B12);
- the toolchain identity, as `tool()` reads;
- the test kinds (`test-exec`, `test-report`).

**Moved:** the test runner's six stage-store scopes become engine kinds (`test-facts`, `test-graph`) in a G4 step, since
G4d deletes the store (G0b, the scope answer). `static-cost-function-v1` serves `selka cost`, which is not a build: it
recomputes, uncached, unless its time says otherwise.

### 17.8 Decisions

| # | Decision | Evidence |
| --- | --- | --- |
| G-D1 | Generic instances and runtime helpers are units of their own | G0b EM-1: 221 of 469 units at 99k are instances |
| G-D2 | Canonical orders, sorted by (name, signature); output changes once; exactness is equality with `--no-cache` of the same compiler | G0b decision 2, EM-2, EM-27, OP-20, OP-26; G0f U1: at 99k 14 of 3,696 functions change and text grows 0.003%; 38 runtime helpers share a name |
| G-D3 | A projection read (tag 7, record format 2), not a per-declaration kind | G0b LW-24; spec §6's granularity rule |
| G-D4 | Linkage from the module's own source (§17.5) | G0b EM-3 |
| G-D5 | `inferred` leaves the declaration hashes (G3). Builds keep the transitive-caller closure until `module-passes` reads callee fact digests as recorded reads | G0b FE2-13, 24; LW-25; G0f U3: exact, an inferred-flipping edit relowers 1 function instead of 27; dropping the closure saves nothing and forces a full front-end retry (3.1 s against 1.0 s) |
| G-D6 | `program-diagnostics` decides what a program shows; every diagnostic carries (module, local span), its `related` and its fix edits included | G0b FE2-2, 6, 36, 44, 46 |
| G-D7 | A canonical `@noalloc` witness; its message text may change | G0b decision 7; neither port uses `@noalloc` |
| G-D8 | The whole-tree retry and `.unreachable` receipts go when `unit-lower` reads `module-check` | G0b decision 8 |
| G-D9 | The test runner's scopes become engine kinds | G0b, the scope answer |
| G-D10 | Query dependencies follow imports (acyclic, `E_IMPORT_CYCLE`) or go to program-level kinds, which read only per-unit parts. Units can still call each other in a cycle (a module and an instance of its own template; the callable-digest helpers), so kinds that read callee results read them per function, or a cyclic unit component is one query node; a query cycle stays an engine error | G0b decision 10; G0f U9: no unit cycle at 99k or 400k, but 8 of 359 `tests/lang` programs have one |
| G-D11 | Project-relative paths in every argument and read; no absolute root in any key | G0b EM-30, FE1-40 |
| G-D12 | Scenarios: `add_func_called` (G0a), and the `run` path and `check` on a library entry (G5a) | G0b decision 12 |
| G-D13 | A unit kind's answer is determined by its argument and its reads. No unit kind reads a query whose argument names a program (an entry). Each program-level input becomes part of the argument, as a digest computed in this run: for `unit-lower`, the program's demand on the unit; for `unit-optimize`, what the program supplies (§17.2); `program-facts` (program-level) carries the digest of the units it reads, so a change of the units is another query. Programs whose demand and facts agree share records. The fallback of the entry name in the argument is correct and loses that sharing | G3f: 118 findings in 657 programs, 116 of them in units two programs share (`@stdlib` modules and generic instances: other part sets, other digests of one function), and 29 unanswerable queries (a record of one program validated in another by re-asking a query about a module the other lacks) |
| G-D14 | `unit-optimize` parts and payloads are position-free, in the canonical form of `unit-lower` (spans zeroed); consumers relocate positions from the run's lines. Emission's keys keep covering positions until G4a (objects carry debug information and trap lines), so the optimizer keeps two digests of a final body: the positioned one for its records and emission, the plain one for the engine | G3f: a line shift left every `unit-lower` part unchanged and moved the optimizer's final-body digests; 20 findings at 99k and 400k, 0 with positions left out of the digest |
| G-D15 | The shared tier keeps up to four variants of a query key, told apart by the signature of the reads of each record (`record.readSignature`: every read in order, without stat tuples and placement values). Slot 0 is the key itself (so earlier records are slot 0) and slots 1-3 are `variantKey(key, slot)`; the engine does the slotting, over any tier. A lookup tries the work directory's record, then the slots in order, each validated by its reads; a publication goes to the slot of the same signature (the tier then compares results: the same reads with another result is a determinism mismatch, logged), else the first absent slot, else one the signature picks. Forgetting a query removes every slot | F33: 76,093 lines for 2,662 keys in the per-user mismatch log, none of them nondeterminism: two worktrees with two versions of a module, and unrelated projects with a `main.selka`, publishing under one key (`module-syntax` 8,860 lines, `module-check` 8,749, `module-interface` 834, `ownership-proof` 135) |

### 17.9 Probes before the code (G0f)

Done on 31 October (`experiments/guest-build-engine-20261031/G0f/REPORT.md`). Besides G-D2, G-D5 and G-D10 above:
U6 found `Module.intern` unifying a structural type with a reserved nominal one in 0.10-0.19% of calls. The union cases
(Option, Result) are load-bearing, so the front end's `Option<T>` and `Result<T,E>` must map to the IR's union by
construction; the record cases are coincidental, and G3a1's op log need not reproduce them. U7 found that adding any
record, used or not, in any module, relowers the whole tree with one retry, because of `Catalog.prefix`'s whole-table
hash: G3b must make it relower only the units that read the record.

The probes, as planned:
- U1, order dependence: G-D2's quality question;
- U3, `inferred` (G-D5);
- U6, structural and nominal records unified by `Module.intern`;
- U7, a record added early in load order;
- U9, function-level cycles at 400k;
- U12, where a generic instance resolves names.

The rest go to the steps that touch them as their first task:
- U2, the per-module check on all modules: G2c;
- U4 and U5, effects order and name uniqueness: G3e and G3a-1;
- U8, the unmeasured profile splits: G0a;
- U10, U11, U13, U14 and U15: the steps whose code they read.

### 17.10 The floor

**Today** (G0a, main ea6e913b2, ReleaseFast, `experiments/guest-build-engine-20261031/G0a/`): a one-line leaf edit of
the 400k port costs 7.81 CPU-s at load about 15. Its profile, in CPU-seconds:

| Group | CPU-s |
| --- | --- |
| idiom warnings (F17 removes them: 450 to 5 ms per edit at 99k) | 2.81 |
| decode and restore of stored records | 1.60 |
| whole-program front-end passes | 0.88 |
| keys and digests of unchanged records | 0.59 |
| whole-module validation | 0.57 |
| emission lookups | 0.47 |
| the lowering walk and restore | 0.44 |
| optimizer bookkeeping | 0.21 |
| the edit's own work | 0.8 at most (10% of samples) |

About 90% of the CPU scales with the program, on the 28 October pin too. A realistic added function (added and
called) takes the whole-tree retry: 8.3-10.3 CPU-s at 99k and 24-34 at 400k.

**Measured floor** (G0e, `experiments/guest-build-engine-20261031/G0e/REPORT.md`; CPU-seconds, load 9-37). A live leaf
edit costs at least 0.44-0.70 CPU-s at 400k and 0.19-0.33 at 99k:
- **validation, one file changed:** 0.11-0.23 at 400k, 0.035-0.09 at 99k;
- **the edit's own front end, lowering and optimizer:** about 0.05-0.12 and 0.03-0.07;
- **compile:** 0.03-0.05 at both sizes;
- **link:** 0.19-0.21 at 400k, 0.08 at 99k;
- **copy and checksum of the program:** 0.04-0.07 at 400k, 0.01-0.02 at 99k;
- **process start:** 0.01.

Recomputing one unit needs only its own records: about 0.5 ms against 0.75-1.5 s for today's whole restore. The 400k
exit is met. The 99k exit is tight, because the compile, link and copy alone are 0.12-0.15 s.

**Requirements** that follow from it (any one missing breaks an exit):
1. **Lazy payloads.** A served query hands back a result handle that is read on first use. Validation never reads or
   hashes an object payload, and per-part digests are inline in the record. The lookup used to read every object (2.0-2.5 ms
   per MB, 0.7-1.0 s for a 400k build's 342-404 MB). Done in step GE2 (§5, "Lazy payloads").
2. **Lazy assembly.** `program-assembly` replays only the recomputed units' op logs (saves 0.16 s at 400k).
3. **Per-function effect parts.** `program-facts` publishes them with early cutoff, so a body edit whose summary is
   unchanged serves it (saves 0.06-0.4 s at 400k). Step G3h.
4. **Link and copy levers,** to keep 0.4 s at 99k for live edits. Step G4b, measured on 1 November
   (`experiments/guest-build-engine-20261031/G4b/DECISIONS.md`):
   - *hard-link the program into place instead of copying it:* **done** (`program_store.place`, landed). It removes the output's
     copy only: 4 ms at 99k and 12 ms at 400k, against 6 microseconds for the link. The output is read-only and carries the stored
     file's modification time.
   - *pre-link groups of unchanged unit objects:* **dropped.** The expected saving was 0.05 s at 99k and 0.15 s at 400k. A probe on
     real unit objects (an upper bound: it leaves out the group lookups and publication) saves at most 0.01 s wall and 0.015 CPU-s at
     99k, and 0.03 s and 0.06 CPU-s at 400k. A link of two objects already costs 0.0175 s wall (starting `zig cc` and lld); the rest
     scales with the bytes and relocations, not with the number of files.
   - *the program passes that remain* (the rest of the 0.04-0.07 s at 400k): the program is read and hashed by `programs.publish`,
     read, hashed and written again by the shared store's `publishFile`, and copied back over the private name by `adopt` when the
     two stores are on different file systems. G4b continues with those (hash once, skip the copy back).

**Measuring.** G0a's machine ran at load 6-27 with swap full, and wall time was 1.6-5x the quiet values even for the
old pin. The exits should be stated in CPU-seconds (user + sys, median of at least three reps), with the G0a pin and
the 28 October pin in the same rounds, and wall reported at its load. This is a proposal for the user's review (G0d).
