# Incremental engine, part 2: guest builds on the engine (31 October 2026)

**What this is about:** the time an edit to a large Selka program takes to rebuild (`mylang build`, `run`, `check`, and
`mylang test` in a project). That is the loop an agent porting the 669k-line EDA lives in. It is not the compiler's own
test loop, not the run time of guest programs, and not release builds, which stay one whole-program LLVM unit by design.

The user asked for it on 31 October ("Let's do the items to speed up guest programs"), after part 1 moved the
`mylang test` receipts onto the engine (`docs/audits/incremental-engine-plan-2026-10-30.md`, spec
`docs/design/incremental-engine.md`). Part 2 moves the compiler's own caches onto the same engine: the front-end
records, the ownership proofs, and the stage records of lowering, the optimizer and emission.

It replaces two older plans: the "compiler stage records" later part of part 1, and the paused edit-cost plan
(`docs/audits/edit-cost-plan-2-2026-10-29.md`: T1a, L2, B4, C, K, S2). Its branches are not merged; §10 says what
each one contributes.

It starts when part 1 closes (C2c4). Sonnet lanes implement (`subagent_type: sonnet-lane`); the coordinator (Claude)
writes the design, reviews every lane, runs the gate and the shadow, and lands on main.

## 1. Why the edit build still scales with the program

**Last full measurement** (main b3e5d71ed, 28 October, ReleaseFast compiler, one-line edits, median wall):

| Edit | 99k port | 400k port |
| --- | --- | --- |
| comment in the hub module | 1.04 s | 4.19 s |
| leaf function body | 0.86 s | 3.08 s |
| body in the hub module | 1.11 s | 3.60 s |
| added function | 0.94 s | 3.32 s |
| type change (new enum variant) | 2.19 s | 6.7 s, or 14-30 s on a whole-tree retry |

The resident-server experiment (S0, `experiments/resident-server-s0-20261028/REPORT.md`) kept every record in memory
and still spent 3.64 CPU-s on a 400k one-line edit. The rest is work that grows with the program, not with the edit:

- keys and digests of unchanged records, about 23% of CPU (the lowering key's declaration walk alone 12%);
- whole-module validation (ownership cache validate, allocation contracts), about 14%;
- the lowering walk and restore, about 11%;
- emission lookups, about 8.5%;
- optimizer bookkeeping, about 6%.

A steady build restores every optimized function and the LLVM text of the whole program (156 MB decoded at 99k,
342-404 MB at 400k). The inventory (N0 §5.3, §8) adds that a checked-body restore costs what a fresh check costs (1.0x),
and that the stage store took a file lock per record (35,377 for 39,606 records on a cold 99k build).

**The engine's costs are small enough to fix this.** C1 measured about 5 µs to serve a query plus 0.2-0.7 µs per read,
and 35-40 µs to publish one (`experiments/incremental-engine-20261030/C/REPORT.md`). At 400k, with about 1,300
modules and the eleven kinds of §3, validating every unchanged module is a few tens of thousands of queries: roughly
0.1-0.2 s. The rest of an edit build would then be the edit's own work: one module checked, lowered, optimized, emitted
and compiled, and the link.

## 2. Goal and exit

**Goal.** An edit build does work in proportion to the edit. An unchanged module costs its validation, and its results
are not decoded unless a recomputed query reads them.

**Exit** (ReleaseFast pins, private copies of the 99k and 400k ports, `measure.py` medians, load stated):
- **One-line edits** (comment, leaf body, hub body, added function): 400k at most 2.0 s, 99k at most 0.4 s, except the 99k comment edit,
  at most 0.5 s. The 400k target was 1.0 s until 2 November, when the user accepted about 2 s for the 400k port. The 99k comment edit's
  target was 0.4 s until 3 November. M1 measured it at 0.54 s, and about 160 ms of that is rendering, compiling and linking the hub unit
  again, because a comment moves its line numbers. That is the cost of keeping line-level debug information (G4f stopped), so the user
  relaxed it to 0.5 s.
- **Type edits:** a new-shape type edit with no whole-tree retry, 400k at most 6 s, 99k at most 1.5 s. The targets were 2.0 s and 0.8 s until 2 November. Then lane 3's profile measured 9.4 s and 2.1 s on main 4617adf5a, and lane 4 found that the front end's share is mostly re-checking the users of the changed type: the test edit changes a type used across the program, 4-5% of all functions. The planned steps reach about 6 s and 1.3 s, and only an early cutoff of record users, not planned, would go further, to about 4 s at 400k. The user relaxed the targets to what the planned steps reach, to be re-measured when they land.
- **Unchanged builds** stay a replay (at most 0.05 s), after type edits too (F16 found they stop replaying today). A
  **cold build** is at most 10% slower than G0a's baseline.
- **A new worktree's** first edit build is at most 1.5x a warm one, through the engine's per-user shared tier. P4d2
  missed this: 4.04 s against about 1 s.
- **`mylang check`** after a one-line edit is at most half of G0a's baseline. The 99k port's `mylang test` after a leaf
  edit is measured and no worse. Met on 2 November for `check`: 0.34 CPU-s at 99k and 1.34 at 400k, 0.25x and 0.17x of G0a. `check` then moves
  onto `Session` anyway (G2o, the user's decision of 2 November).
- **Exactness:** every program and diagnostic equals `--no-cache` (`exact.sh`, every scenario, both trees). Verify mode
  is clean, the port's 1,250 tests pass, and the complete gate passes.
- **Net lines removed.** About 8,400 lines of stage store, packs, journals, compaction, roots, collector, leases,
  scopes, demand generations and the per-cache key code are deleted or shrink to their kinds.

G0a (31 October) measured today's numbers on a loaded machine (load 6-27, wall 1.6-5x quiet values); spec §17.10 has
its profile and the floor estimate, and proposes stating these exits in CPU-seconds with the old pin run alongside.
**Accepted by the user on 31 October (G0d),** with the deletion list of spec §17.7, measured in CPU-seconds (user + sys,
median of at least three reps) with the G0a pin and the 28 October pin in the same rounds, and wall reported at its
load. If G0e or a later measurement shows an exit out of reach, the coordinator keeps the exit and changes the design;
if no design change can reach it, that exit's work stops for the user's decision, and the rest continues.

## 3. Design: the query graph

Kinds are per module, grouped per the spec's §6: one record open validates all of a module's members. From the leaves
to the program:

| Kind | Argument | Reads | Result identity (early cutoff) | Replaces |
| --- | --- | --- | --- | --- |
| `module-syntax` | module path | `file(path)` | digest of each declaration and each body | A1 syntax entries, P4a module records |
| `module-interface` | module | its syntax; the interfaces of what it imports, only the declarations it names | the checked declarations (types, signatures, layouts) | A1 verdicts, A2's dependency context |
| `module-check` | module | its syntax and interface; imported interfaces; the generic instances it instantiates | per-body digests; the bodies as one object | A2 checked-body store, A3 summaries |
| `module-passes` | module | its check result; the callee summaries it reads | ownership plan, allocation contracts, origins, warnings | the whole-program passes (S2) |
| `ownership-proof` | module | its passes result; the callee proofs | one proof result per function | B6 (spec §14) |
| `module-lower` | module, settings | its check result; the digest of each record, type and signature lowering reaches, recorded as it reads them | Core IR with program-independent names | B2, B3 demand generations, T1a, B4, D5 |
| `module-optimize` | module, level | the lowered module; the callee summaries and bodies the inliner and the facts passes read | optimized IR | B4 optimizer records and shortcut, package C |
| `unit-emit` | unit | the optimized module; emission settings | LLVM text digest | B5 `llvm-unit-v1` |
| `unit-object` | text digest | `tool()` | the object, in the B9 store as today | native-unit receipts |
| `program-link` | entry, settings | unit and runtime object digests | the linked program (B11 store) | |
| `build` | entry, settings | the program's files by stat; the link | the program | B13 replay record |

**Rules:**
- **Program-wide facts are queries, never ambient.** Some module work reads something program-wide: the type
  catalog's positions, a program-wide count, the dictionary helper set (J11). It reads that through a small query of
  its own and depends on its result digest. G0b lists every such fact in today's pipeline.
- **Names, not positions, across modules.** Core IR refers to another module's types, records and functions by stable
  name. Positions are assigned when the program is assembled. Q1's callees by unique name (3421dadec) is the
  precedent.
- **Lazy restore.** A served module's result is one object, read only when a recomputed query reads it.
- **Code identity** per kind is the import closure of its stage's roots, generalizing M1's five stage identities.
- **Shared tier.** Every kind publishes to the engine's per-user shared tier (C2e1), which is how a fresh worktree is
  served.
- **Verify mode** samples served queries: Debug 1/64, the gate 1/16 (spec §10). It is the soundness net for every kind.
- **Migration per stage:** shadow (the old cache decides; the engine records and compares result digests), then switch,
  then delete the old cache. This is part 1's method.

G0c writes this as the spec's §17, "compiler kinds", with every kind's reads, granularity and replaced code. The draft
(31 October) refines this sketch from G0b: after the front end the kinds take units (modules, generic instances and
runtime helpers), five program-level kinds read per-unit digests, and a projection read lets a module depend on only
the declarations of another that it reaches.

## 4. Packages

No step is longer than six hours. A lane that finds a step will take longer splits it and says so before starting.

### G0. Baseline and design (before any change to `src/`)

| Step | Who | Hours | Done when |
| --- | --- | --- | --- |
| **G0a** Baseline on main | lane | 4-6 | Measured on a ReleaseFast pin of the C2c4 landing, at 99k (3 reps) and 400k (2 reps): the five one-line scenarios, new-shape and same-shape type edits, cold and unchanged builds, `check`, and the 99k suite after a leaf edit. Stage and phase split and a CPU profile, in a table. |
| **G0b** Program-wide inventory | lane, read-mostly | 4-6 | A list, with file and line, of everything module work reads program-wide: sema's collection, catalog positions, positional ids, whole-program passes, demand state, optimizer facts, emission helper sets. Each item gets a proposed query or a per-module rewrite. |
| **G0c** Design: spec §17 | Claude | 4-6 | Every kind's argument, reads, result identity and granularity, the code it replaces, and a 400k floor estimate from G0a and G0b. The draft is on main (31 October); the floor waits for G0a. |
| **G0e** Floor spike | lane 1 | 4-6 | A throwaway prototype on the engine store at 400k: the unchanged modules' records validated, one module recomputed. Its time confirms or re-sets the §2 exits. |
| **G0f** Probes before the code | lane 3 | 4-6 | Spec §17.9's six probes (U1, U3, U6, U7, U9, U12) settled on scratch builds, with the decisions they decide updated. |
| **G0d** Design review | you (targets and deletions), Claude (the rest), per D2 | 1-2 | Accepted on 31 October, with G0e's first two measurements in hand. |

### G1. Ownership proofs (the spec's second consumer; independent of G2 and G3)

| Step | Who | Hours | Done when |
| --- | --- | --- | --- |
| **GE** The projection read | lane 2 | 4-6 | Spec §17.3's `part` read (tag 7, record format 2) in the engine core, with test vectors, a property test, and format 1 records still read. |
| **G1a** `ownership-proof` kind | lane | 5-6 | Grouped per module, reading callee proofs. Shadowed against `ownership_cache.zig` with zero disagreements on `tests/lang`. |
| **G1b** Shadow campaign | lane | 4-6 | `tests/lang`, the 99k port and `selka-projects` in shadow: no unexplained line, restore at most recompute plus 10%. |
| **G1c** Switch and delete | lane | 4-6 | The engine decides. B6's pack store and `ownership_partition.zig` are gone. Gate green. |
| **G1d** Validate by module (after G2m) | lane | 4-5 | Ownership validation walks only the modules whose proofs were recomputed; a served proof carries its validation. Ownership validation in a one-line edit under 15 ms at 99k and 40 ms at 400k (Gmid: the ownership and contracts group is 106-138 ms and 265-348 ms, its contracts half is G2k's). A Debug compiler still validates every certificate it computes. |

### GE2. Lazy payloads (G0e's first condition; before G1 and G3)

| Step | Who | Hours | Done when |
| --- | --- | --- | --- |
| **GE2** Lazy payloads | lane 1 | 4-6 | A served query returns a result handle read on first use. Validation never reads or hashes an object payload, and per-part digests are inline in the record. The engine bench serves 9,200 queries at 400k, a quarter of them with object results, at no more than the inline-only cost (0.08 CPU-s warm). Verify mode still recomputes and compares a sampled payload. |

### G2. Front end

| Step | Who | Hours | Done when |
| --- | --- | --- | --- |
| **G2a** `module-syntax` | lane | 5-6 | Declaration and body digests as the result identity; shadowed against A1. |
| **G2b** `module-interface` | lane | 5-6 | An edit inside a body leaves every importer's interface read unchanged (an early-cutoff test). |
| **G2c** `module-check` | lane | 6 | Checked bodies grouped per module, one object each; shadowed against A2 and A3. |
| **G2d** Lazy restore | lane | 5-6 | An unchanged module's bodies are not decoded unless read. Checked-body restore measured below 0.5x recompute (1.0x today). |
| **G2e** `module-passes`, part 1 | lane | 6 | `stand_in_planning` and `allocation_contracts` per module. Lane Q's three exact speedups reapplied only if they still win. |
| **G2f** `module-passes`, part 2 | lane | 5-6 | `origin_passes`, `warning_derivation` and the check summaries per module. Diagnostics and warnings unchanged on the gate corpus and both trees. |
| **G2h** `program-diagnostics` | lane | 5-6 | Every diagnostic carries (module, local span), its `related` and fix edits included. Today's three gates and global order are applied over per-module results. Diagnostics are unchanged on the gate corpus and both trees. |
| **G2g** Switch the front end | lane | 5-6 | A shadow campaign passes, the engine decides, and A1-A3's key code is deleted. Gate green. |
| **G2j** The front end G3g needs | lane | 4-6 | `module-check`'s `body:<name>` parts and function ids are stable across unrelated edits (a function or record added elsewhere, modules reordered, a comment that shifts lines). One module's checked bodies can be asked for alone, served from its record when it is valid, without checking the other modules. |
| **G2k** `module-passes` decides | lane | 5-6 | The engine serves each unchanged module's passes result (origins, warnings, summaries, stand-in plan, allocation contracts), and the front end runs the passes only for recomputed modules. Passes and contracts in a one-line edit are under 20 ms at 99k and 60 ms at 400k (Gmid: 0.2-0.26 s and 0.6-0.77 s). Diagnostics and warnings unchanged on the gate corpus and both trees. |
| **G2m** Every body can be stood in | lane | 5-8 | A body that names a specialization or a type interned while checking keeps a stand-in: its summary names those types by stable name (structural digest, spec §17.1) and standing it in interns them from the summary, so the interning order of the program no longer decides `stubbable` (D-G2r3a-1). Lane 1's G1d probe (1 November): 1,051 of 4,557 functions at 99k and 4,630 of 23,825 at 400k have no stand-in today, so every build replays their bodies (`ordinary_body_replay`) and the ownership digest walks each one. Done when no ordinary function is replayed in a one-line edit for want of a stand-in. |
| **G2l** Parse and merge only what changed | lane | 27-38 | An unchanged module is not loaded, parsed or replayed into the merged program unless a recomputed module or unit reads its trees. Parse and merge in a one-line edit at most 60 ms at 99k and 200 ms at 400k (Gmid: 82-111 ms and 346-400 ms). Re-estimated on 2 November from 6-8 h, after a profile and a probe that poisoned every unchanged module's trees (`experiments/guest-build-engine-20261031/G2l/DESIGN.md`). The steps, each landed on its own: **G2l-0** cheap exact wins: BLAKE3 module digests hashed once, a vectorized line scan, concatenated line tables (3-4 h; parse group about 68 / 295 ms); **G2l-1** the whole-table scans of seven readers become per-module facts or per-body indices (6-8 h; about 25 ms at 99k and 100 at 400k outside the group); **G2l-2** stored syntax v2, a declaration part plus per-function body sections (6-8 h); **G2l-3** a lazy merged program whose bodies load through `ensureBody` hooks, with a Debug canary and a verify-mode fill (9-13 h; about 35 / 120 ms); **G2l-4** the flip, exactness and measurement (3-5 h). Spans stay merged-absolute: nothing persistent holds a merged offset, and a body loaded later is relocated at the run's base. `mylang check`'s own route in `main.zig` stays eager and is placed separately. **G2l-3 and G2l-4 done** 2 November (ca6898c98): the lazy merged program is the default for build, run, test and the project check family, and `MYLANG_LAZY_SYNTAX=0` reads whole. Since G2o, `check` of a project takes the same route; lint, fix, doc, context, index and the other complete-program commands read whole. Parse and merge in a one-line edit: 99k 59-67 -> 23-30 ms, 400k 297-314 -> 148-175 ms, both under target. The page-fault probe and the Debug canary found readers the earlier probe missed; three misses in the first lazy-default gate were fixed. The exactness corpus (1,037 programs), both ports, the cycles and 8,872 verify comparisons are all clean. Residual risk: a ReleaseFast compiler without verify reads an unfilled entry silently if a hook is missed, so a reader-inventory test (every reader of `program.nodes` and `program.statements` on an audited list) follows with the settleDecided cut (D-G2l-17). |
| **G2o** `mylang check` through `Session` | lane | 14-20 | Added on 2 November by the user's decision. `check` builds its program through `Session` and the engine-decided keys, like a build, and `main.zig`'s separate merged-program driver is deleted, so G2l's facts and lazy program are built for one route only. Its output (diagnostics, warnings, `--json`, exit codes and fix edits) is byte-identical to the old route's over the gate corpus and both trees. Expected warm `check` after a one-line edit: about 0.15 CPU-s at 99k and 0.6 at 400k (0.34 and 1.34 before). Runs after G2l-0 and G4c part 2a, before G2l-1. **Done on main (37e7b1399, 2 November).** Every project command and `check-session` run on Session, and the second driver is deleted: about 214 lines out of `main.zig` against about 274 new, so 3,712 -> 3,804 lines (D-G2o-8). The 450-550 estimate counted helpers the single-file `check` still uses. Equal to the old route on 13,851 check rows and 9,288 command rows, except two accepted classes where the old route's warm run disagreed with its own `--no-cache` (D-G2o-7, D-G2o-9). Warm check after a one-line edit: 99k 0.30-0.38 -> 0.26-0.27 CPU-s, 400k 1.67-1.74 -> 1.35-1.53 under load (instructions 1,524 -> 1,215 M and 7,298 -> 4,684 M). The expected 0.15 and 0.6 wait on G2l-3. |
| **G2p** The front end's per-edit residue | lane | 16-28 | Added on 2 November after lane 4's front-end profile (`experiments/guest-build-engine-20261031/G2l/Gmid2.md`): about 860 ms of a 400k one-line edit's 1,990 ms front end is covered by no other step, so even with G2l-3, G2o and G4c-2c-2 on target the front end would stay near 900 ms. The parts at 400k: `stand_in_planning` 442 ms (one lowering-host `allow` per stood-in function, 23k), `specialization_body_replay` 108, `body_loop` 70, `frontend_cache_finish` 66, `symbolic_templates` 52, the declaration-linear rest of `sema_collect` 64, and smaller parts. Done when an unchanged module's results are served whole (a module-level cutoff, not a loop over its functions) and these parts total under about 150 ms at 400k and 35 ms at 99k, exact against `--no-cache`. The hours are the design's to set; 16-28 is a placeholder. **Landing A, F42 and part 1 on main (73c9a5054, 2 November):** the lowering and ownership hosts answer for a whole module (`Demand.allow_module`), and the planner asks per function only for what a module answer did not cover. The nine parts at the 400k leaf edit went 802 -> 444 ms, and at 99k 170 -> 127 ms. Whole-build instructions are 0.88-0.96x of main. Exact on both ports, with 147k module cross-check comparisons and 0 findings. The aim is not met. What is left, all done by lane 4 with minimal announced edits in the hosts: (1) the summary table split by module, about -80 ms at 400k, 12-16 h; (2) ownership markers read without opening the whole group, about -40 ms; (3) instance stand-ins keyed by (template, context, arguments), about -60 ms. Since the 400k target moved to 2.0 s, the 99k residue (aim 35 ms) is the part that matters. |

### G3. Lowering and optimizer (in parallel with G2; lowering reads today's checked bodies until G2g)

| Step | Who | Hours | Done when |
| --- | --- | --- | --- |
| **G3a1** Names and the op log | lane | 4-6 | The stable-name vocabulary (spec §17.1), `Function.module`, and a write-only op log of each function's table effects. Output unchanged. |
| **G3a2** Assembly of compounds and strings | lane | 4-6 | Compounds and strings assembled from the op logs in canonical order. Output equal to `--no-cache` of the same compiler. |
| **G3a3** Generated names | lane | 4-6 | The nine generated-name families named by their creator and a local counter; the twelve parse sites read names. |
| **G3b1** Callees and helpers by name | lane | 4-6 | Calls name their callee; runtime helpers are op-log entries. |
| **G3b2** Discovery replay | lane | 4-6 | Program assembly replays the op logs; `FinishRecord` deleted. Assembly replays only the recomputed units' logs (G0e: decoding all of them adds 0.16 s at 400k). |
| **G3b3** No positions in keys | lane | 4-6 | Lazy relocation; the guard, the counts and `validPrefix` deleted; the raw demand key without `layout`. |
| **G3c** `unit-lower` | lane | 6 | The reach recorded as lowering reads it (replacing the catalog guard and the discovery-count keys); shadowed against B2. |
| **G3d** Type edits and added records and functions | lane | 5-6 | Zero whole-tree retries for new-shape type edits, an added record (used or not) and an added, called function (`add_called_func`): ten cycles each at 99k and three at 400k, output equal to `--no-cache`. |
| **G3h** `program-facts` | lane | 5-6 | The cross-function joins (hulls, address-taken, `closed`, effects, inline class, helper set) as one program-level kind with per-function parts, the effects included, with early cutoff: a body edit whose summary is unchanged serves it (G0e: the recompute costs 0.06-0.4 s at 400k). |
| **G3e** `unit-optimize` | lane | 6 | Callee summaries and bodies recorded as the inliner and the facts passes read them; the whole-program layout gate gone. |
| **G3f** Optimizer shadow | lane | 5-6 | `exact.sh` identical on both trees for every scenario; shadow clean. |
| **G3s** Shadow clean | lane | 6-10 | G3f's findings removed (1 November): `unit-optimize`'s parts and payloads are position-free like `unit-lower`'s, and emission's keys keep positions until G4a; each unit kind's argument carries, as digests computed in the run, the program's demand on the unit and the facts slice it reads, so no unit kind reads a query that names a program (spec G-D13). 0 findings and 0 unexplained errors on the 657-program corpus, the 443 builds and both trees; `exact.sh` identical. |
| **G3o** The optimizer's records by name | lane | 34-48 | What G3e's "layout gate gone" left undone (found in G3g on 1 November): the optimizer's snapshots name callees by name and signature and types by structure, as the lowering artifacts do since G3a/G3b, and are rebound to the current table on restore. Its stage records and manifest lose `snapshot.layout`, so an added, called function no longer re-analyses every function (99k: 3,496 functions, 3.3-4.1 s) and a type edit no longer decodes every final body (1.5 s). Staged: final bodies (8-10 h), stage records (10-14 h; the inliner's `target < caller` rule is about ordinals), manifest (16-24 h: the manifest matched by lowered key with local names, and the fusion catalog by name; a profile on 2 November showed that its raw-layout gate, not the field rounds, keeps every function from being green, so the separate field-round step was dropped); each exact against `--no-cache` and gated. Re-estimated by lane 3 on 1 November from 10-16 h: the layout dependence is in five places (the lowering `Wire`'s ordinals, the stage keys' callee ordinals, provenance, the manifest's graph lists and layout gate, the fusion catalog and emission cache). S3b-1 **done** 2 November: manifest entries are matched by lowering key and stored with local names, so an added, called function leaves 3,196 of 3,496 functions deferred at 99k. Its optimizer stage went from 3.5 s before S1 to 0.49 s at 99k, and from 10.6 to 2.1 s at 400k; a type edit's optimizer stage went from 1.6 to 0.57 s at 99k. S3b-2 (the fusion catalog by name) and S3b-3 (portable fusion bodies) are deferred until after G4a: they help only the ~300 functions that request a helper (20-60 ms at 99k, 8-12 h), and are done with the deletion of the raw-layout regime (`snapshot.layout`, the same-layout `Candidates` path, `Catalog.layout`). |
| **G3p** The optimizer's dense program record | lane | 25-38 | Re-scoped on 2 November after three profiles (`experiments/guest-build-engine-20261031/G3p/DECISIONS.md`, D-G3p-1 to D-G3p-7 and later). A deciding `program-facts` kind would have saved only 1-5% of a one-line edit. The optimizer stage's floor is reading every function's manifest entry, and that cost is per-record store overhead, about 10 us a read, not the size of the fields. A 400k leaf edit makes about 58,000 stage-store loads, about 0.6 s of a 4 s build. The steps, each landed separately: **G3p-0** reuses the exploration rounds and effects of a function changed only by a line shift (2-3 h; about 50 ms at 99k and 90-100 at 400k for comment_hub); **S** stops checksumming a record whose block this process has already verified, and keeps pack descriptors open per process, revalidated when the store moves (3-5 h; about 5 us a load, 65 ms at 99k and 290 ms at 400k in every scenario, until G4d deletes the stage store); **(a)** one chunk per unit as an engine part, with flat columns for what the sweeps read and the rest per function, read only for changed ones (14-20 h; about 30 ms at 99k and 145 at 400k beyond S; writes stay under 2 MB per edit); **(b)** the joins by name over the columns, `mapEntry` gone (6-10 h; 20 ms and 70 ms more). G3g step 2 needs these joins by name, not a `program-facts` kind; the kind only packages the record at G3g step 3. **(a), first form, on main (2cef57968, 2 November):** the manifest's entries are rows in chunks of about six functions, published once as the head of the program state, and kept as stage-store records on the shared route until G4d (D-G3p-13). Instructions 0.972-0.992x on every one-line scenario at both trees: about 25-30 ms at 99k and 80 at 400k, from record reads alone, because rows are still decoded whole. Writes at 400k: type_edit, add_called_func and comment_grow 6.2-7.4 MB per edit (5.7-6.8 before). The columnar rows, the input digests readable without a decode, and (b) are one refactor, which lane 3 does next after a fresh profile of main; (b) starts with a design note on placing only the functions its worklist reaches. **Re-scoped on 2 November after lane 3's profile of main** (`G3p/profile-main-r6.md`, `G3p/B-DESIGN.md`). The optimizer needs no lazy placement: lowering's ordinals stay array indexes, and a row is found by chunk group and lowering key. A hub comment or body edit makes 215-220 functions red at 99k (708-713 at 400k), but only 13-14 move; the rest are transitive callers marked red by `invalidateCallers`, and about 95% of the red work restores results that did not change, at 1.2-1.4 ms each. The order now: **F45** stage-store compaction off the edit path (at 400k every second new-shape type edit compacts inside the build, 3-5 s), **done** 2 November (971f55a5b): each build compacts the smallest packs within a 96 MB budget, so the 400k type edit's compaction is about 2.5 s instead of 11-23 s; **(c) early cutoff of callers** (22-32 h): only the changed functions and their direct callers go red, and a caller's callers follow only when a digest it reads from a recomputed callee changed, with a verify mode that runs the old transitive rule and compares. Optimizer stage on a hub edit about -250..-300 ms at 99k and -600..-650 at 400k. **(c) done** 2 November (7e5d19a22): instructions against main on a hub body edit 0.50x at 99k and 0.67x at 400k, comment 0.70x and 0.84x, added called function 0.71x and 0.87x. Exact with `--verify-cutoff` in every build, which a Debug compiler also samples on 1 build in 4. D-G3p-16 lists the reads the enumeration missed. A comment edit still recomputes the direct callers of the shifted functions (59 at 99k, 217 at 400k), which needs G4a's position-parametric keys; **(d) the digest header plus cached joins plus the split** (16-22 h), so a green function's row is never decoded: about -70 ms at 99k and -280 at 400k on every edit. **(d) done** 3 November (b0669d4b4): a row is a Core every build reads and a Rest read on demand, and the field rounds' joins are a content-addressed record the manifest names. Optimizer stage of a leaf edit: 99k 120 -> 69 ms, 400k 450 -> 296 ms, and instructions 0.92-0.95x on the one-line edits. It unblocks G3g step 2c: unit-optimize keys from each function's lowered, final, body.plain and analysis digests plus the joins digest. What is left is the per-function lookup, now 40% of the stage (27 / 130 ms), and a comment edit's direct callers. Relocating line-shifted functions saves about 18 ms for 30-45 h and waits for G4a. |
| **G3g** Switch lowering and optimizer | lane | 5-6 | The engine decides; B2-B4 and the demand generations are deleted. Gate green. | Done in parts on 1 November: steps 1 and 1b key every function by its `module-check` parts. Step 2 (a unit-level lowering record) is deferred until after G3o's manifest stage, G3p's dense program record and G4a: lowering's remaining cost is the placement of every function into the program-wide tables whose ordinals the inliner, the joins, emission and the helpers read, so before them it is 22-35 lane hours for 8-12% of an edit, after them about 8-12 (per-unit name manifests, bodies restored lazily). Re-planned on 2 November (`experiments/guest-build-engine-20261031/G3g/STEP2-DESIGN.md`, 24-33 h): a per-unit name manifest replaces `Session.key`, `restore` and `FinishRecord`, and `unit-lower`, `program-facts`, `unit-optimize` and `unit-emit` decide, then `unit-object`, `program-link` and `build`. Steps a-b (the lowering side, 10-14 h) need nothing from G3p; c-e follow G3p's joins by name. Positions stay in `unit-emit`'s argument since G4f stopped, so a comment edit still renders and compiles its unit. **Steps a-b on main (73a81d35a, 2 November), built differently from the design (D-G3g2-1):** tables are numbered in discovery order, which interleaves units, so a served unit's op log cannot be replayed without its neighbours. Instead an assembly record keeps the tables a lowering ended with, plus each function's key and effects digest. When an edit leaves a function's effects on the tables unchanged, the build assembles from the record instead of replaying every function, and anything else replays as before. Lowering stage: 99k 100 -> 30 ms (comment_hub), 128 -> 61 (leaf, median); 400k 392 -> 115, 422 -> 144 (min). add_called_func and type_edit +2-4% instructions. Exact on both trees, with 0 different in the corpus. `unit-lower` still only packages (shadow). Making it decide replaces only the per-function key hashing, so it moves into step c with G3p (b). The assembly record is a private per-tree file, so it does not help a fresh worktree.

### G4. Emission, link and the build

| Step | Who | Hours | Done when |
| --- | --- | --- | --- |
| **G4a** `unit-emit` and `unit-object` | lane | 15-20 | One LLVM unit per module, instance and helper from its optimized result, with spec §17.5's linkage rule and canonical function order; the object store unchanged. Step 1 **done** 2 November: linkage comes from the check (`sema.privateFunctions`; a module with a test file, and a function marked `@test`, count as visible) and functions are emitted in canonical order by name; exact on both trees and over the 657-program corpus, and the release build is byte-identical to `--no-cache`. Step 2, keys local to the unit, is re-estimated at 8-10 h: a receipt today hashes the module's whole layout, its export vector and every function's signature, plus the descriptor catalog, and emission still reads type ordinals out of names (`myl_core_equal_<N>`, `@myl.value.<ordinal>`). That G3a leftover goes first. Step 2 **done** 2 November (7cdd33789). Step 3 runs `unit-emit` in shadow (0 findings over 134 sessions and about 99,000 units on both trees). It does not decide yet: its reads are `unit-optimize` parts, which answer only inside a comparing shadow, so a deciding `unit-emit` would only relabel the receipt lookup (D-G4a-8). `unit-object` is deferred to G4b. |
| **G4b** `program-link` and `build` | lane | 5-6 | The replay record becomes the top query; unchanged builds still replay at or under 0.05 s. The program is hard-linked into place (**done**, 1 Nov: saves the output copy, 4 ms at 99k and 12 ms at 400k). Pre-linked groups were **dropped** after a probe (at most 0.01 s wall at 99k and 0.03 s at 400k, against 0.05 and 0.15 expected; spec §17.10). The remainder **done** 2 November (eafb48acb): the shared record is a hard link of the caller-hashed program, a reused program is checked by its sidecar digest instead of republished, and the toolchain is scanned only after a tool ran (about 10 ms at 99k and 25-30 ms at 400k on a quiet disk). The replay record as the top query comes with G3g step 2. |
| **G4c** Shared tier for compiler kinds | lane | 15-25 | Project-relative paths in every key (spec G-D11). A new worktree's first edit build at most 1.5x a warm one. Part 1 **done** 1 November: the front-end, ownership and test kinds are shared per user. A fresh 99k check was then 2.7x warm, `test` 1.9x and the build 8.7x. Lane 2's sizing on 2 November (`experiments/guest-build-engine-20261031/G4c/front-end-facts.md`) found the dominant missing record is the entry's summary table, which lives only in the work directory: a fresh check is 5.7x warm at 99k and 7.9x at 400k, and 1.6x and 1.4x with that one table copied. Part 2a (lane 2, 4-6 h) shares the whole table through the compiler store, under a path-free project identity, local first and last writer wins; the header records and the template body store are shared too where cheap. Part 2a **done** 2 November (42117314e): a fresh check is 1.45x warm at 99k and 1.25x at 400k. A fresh first edit build is still 11.5x and 10x. Its front end is 3.0 s against 1.4 s warm at 99k, and the unit kinds account for the rest (lowering 0.65 s, optimizer 3.4, emission 2.0, against 0.08-0.15 warm). Part 2b (lane 1): F37 found that every stage-store scope misses in a fresh worktree because the stage store's shared half is opt-in, not because keys are tree-specific; with it on, a fresh 99k build's user CPU falls from 12.7 to 4.6 s. Since the stage store goes at G4d, 2b keeps only what survives it: store objects trusted by a stat tuple the writer recorded (2 h), and the optimizer's per-unit chunks (G3p) shareable as engine parts. An interim default-on shared stage store (6-8 h) is taken only if G4d slips. Part 2c (the front end) has two halves: 2c-1, 3-5 h, stops writing 4,698 checked bodies that are never read back (about 0.5 s), and 2c-2, 4-8 h, profiles and cuts the dependency key preparation (about 0.6 s). F33 **done** 2 November (34389d332): the shared tier keeps up to four variants of a key, told apart by their read signature, so two worktrees holding two versions of a project are each served their own (400k: the second version served 1,057 of 1,057 modules, no mismatches). **2c-2 done** 2 November (49b8bf6e1): on current main the dependency key preparation of a fresh 99k build is 43-107 ms, not 0.89 s, so its premise is gone. The fresh build's front end (`fresh_body_check`: 0.5-0.67 s at 99k and 9-13 s at 400k on a quiet machine, and up to 9.8 s and 55 s under load with the same instructions) is file-system latency: about 3,300 preadv, 800 renameat, 500 mkdirat, 1,150 utimensat and 30,000 failing mkdirat per fresh 99k build. The cut that landed: a hit refreshes a shared entry's recency at most once an hour (1,147 -> 0 metadata writes). The rest is G4d's: fewer, larger files (packed records, lazily written local copies of shared records, remembered shard directories). |
| **G4e** The test runner's records | lane | 4-6 | The six test-runner scopes become engine kinds (`test-facts`, `test-graph`), so nothing reads the stage store. |
| **G4f** Positions out of the unit text | lane | 12-20 | Added on 2 November after lane 1's comment_grow measurement: a comment of a new length above a unit's functions re-renders 2 units and compiles 1, 80-105 ms at 99k and 85-115 ms at 400k, over the 60 ms line set on 1 November. The DWARF line tables and the trap lines move out of the unit text into a per-unit table that the link step patches or the runtime reads, fed by the optimizer's positioned digests (G-D14). Done when a comment edit renders and compiles 0 units, every address maps to the same line in the debug information, and traps report the same lines. **Stopped** on 2 November after a spike (`experiments/guest-build-engine-20261031/G4f/SPIKE.md`): at -O0 an object holds one line-program sequence for all its functions, so a line shift changes opcodes and section sizes, and a link-time patch would need a full DWARF line-program codec and section re-layout (30-40 h) for 80-115 ms on comment-only edits. The cheap alternative, debug builds without line-level DWARF, would cost trap reports their caller lines (the runtime names caller frames from the DWARF line tables), line stepping in a debugger and per-line profiles; on 2 November the user chose to keep the line information. A comment edit therefore still renders and compiles its unit (80-115 ms). |
| **G4g** Emission's per-edit cost | lane | 4-10 | Added on 2 November from lane 3's profile of main: emission was 72-118 ms of every one-line edit at 99k and 252-342 at 400k, and it grew with the program, though an edit renders one or two units. **Done** 2 November (e1c46489a): 64% of that CPU was starting threads for units that their receipt answers. Those now complete on the coordinator, the descriptor catalog renders at the first miss, module groups are found by hash, and the compact key hashes through a staging buffer. No key changed. Emission stage wall: 99k leaf 67 -> 25 ms, 400k leaf 264 -> 77, 400k type edit 314 -> 85; thread starts per 99k build 481 -> 13. Left for G3g step 2c-d: the compact key (4.5 / 20 ms) and the receipt reads. |
| **G4d** Delete the stage store | lane | 5-6 (re-sized to 85-130 by D-L1r11-2) | **Deferred by the user on 3 November**, who chose the cheap path (G4h) for the fresh-worktree target; the full move is a structural cleanup to weigh later, perhaps after the EDA port. As planned: Packs, journals, compaction, roots, collector, leases, scopes and the shared stage tier gone. Retention is the engine's. Gate green. F37 (2 November) measured the engine store at 9.8 us a record, the same as the stage store, but the end state reads about 2k records at 99k and 8k at 400k, against 58k stage-store loads today: about 80 ms at 400k. No pack format is built. The rule for every kind: read parts first, and hash a payload only when it is served. G3p (a) (2 November) keeps the optimizer's chunks and heads as stage-store records on the shared route, because the finals, fact payloads and checkpoints their rows name are stage-store records too (D-G3p-13). G4d moves them into the engine with those records, and that is when a fresh worktree is served them by default. |
| **G4h** A fresh worktree, the cheap path | lane | 6-8 | Chosen by the user on 3 November in place of the full engine move (`experiments/guest-build-engine-20261031/G3g/DECISIONS.md` D-L1r11-2). The stage store's shared half on by default: a per-user store when `MYLANG_STAGE_SHARED_CACHE` is unset (an empty value disables it), with bounded automatic retention that never holds a lease long enough to stall a build, and no gate test reading or collecting the per-user store. It lands after F54 (module receipts keyed by the module alone, so two projects sharing files overwrite each other's). Already on main: the shared project head (`optimizer-latest-v1`, 56e0a2672), with which a fresh first edit is 1.64x of warm CPU at 99k and 1.66x at 400k with the half on. Also part of it: lane 4's fresh front end (424 -> 229 ms at 99k with the half on) and lane 1's local records pack (D-G4c3-5). The 1.5x exit stands until a calm combined measurement (M2); it moves to 2x only if M2 misses and the user agrees. |

### G5. Measure and land

| Step | Who | Hours | Done when |
| --- | --- | --- | --- |
| **Gmid** Mid-course profile | lane | 2-3 | Done 1 November (`experiments/guest-build-engine-20261031/Gmid/`): each stage of the edit build beside G0a and the floor, and the step that removes it. It found the front end's parse, passes and validation covered by no step, hence G2k, G2l and G1d. |
| **G5a** Final measurement | lane | 5-6 | G0a's sequence repeated on the same trees, beside G0a's numbers; `exact.sh` on both trees; the port's tests. Instruction counts are taken with `perf stat --no-scale`: on this hybrid CPU the default scaling of each core type's count swung identical 400k work between 29 and 37 G, against 19.00-19.02 G unscaled (lane 3, 2 November). A comment edit uses a new line count in every rep, since a repeated line shift is served by the manifest's undo lookup. A type edit is measured with a new shape in every rep, since a user's type edit is always new (Gmid: the first build of a shape costs 6.9 CPU-s at 99k and 20.6 at 400k, against medians of 2.7 and 10.8). |
| **G5b** Docs and report | lane | 3-4 | `docs/tooling/native-build.md`, a draft of `CLAUDE.md`'s cache paragraph (the coordinator commits `CLAUDE.md`), `REPORT.md`, `DECISIONS.md`. |
| **G5c** Gate and land | Claude | 2-3 | Complete gate, edit-check shadow, landed. |

**Total:** 52 steps (38 plus GE2 and G2i, on 1 November G3s, Gmid, G2j, G2k, G2l, G2m, G1d, G3o and G3p, and on 2 November G2o, G2p and G4f; the F
follow-ups are not counted), about 370-517 lane hours at these estimates. Re-split on 31 October after G0b: stable names grew from two steps to six,
and G0f, GE, G2h, G3h and G4e were added. Amended on 1 November after G3f's shadow findings (G3s) and the mid-course profile
(Gmid), which showed that the listed steps leave about 0.5 s of a 99k one-line edit and 1.4-1.6 s at 400k (G2j, G2k, G2l, G1d). On 2 November G4a grew from 5-6 to 15-20 h after step 1 found its receipts keyed by the whole module. G2l grew from 6-8 to 27-38 h when its probe showed that parse and merge need a lazy merged program, not a faster loop.

## 5. Order and lanes

- **2 November:** lane 4 opened (worktree `mylang-g2l`) for G4c-2c-1, G2l-1 and G2l-2, so that lane 2 can do G2o, G4c-2c-2, G2l-3 and G2l-4 in parallel.
- **2 November, afternoon:** G2l-3 and G2l-4 moved from lane 2 to lane 4, and lane 5 (worktree `mylang-store-gc`) opened for F44, the per-user object store's cleanup, which stalled builds and gates. At 15:50 the user limited part 2 to **three lanes at a time**, because five kept the machine at load 10-60 and every build, gate and measurement slower. Running: lane 3 (F45, then G3p's early cutoff of callers), lane 4 (G2l-3, G2l-4) and lane 5 (F44). Paused at a clean point, resuming in this order as slots free: lane 1 (the ownership group read from D-G2p-12, then the declined-assembly cuts), then lane 2 (G4c-2c-2).
- **3 November:** the user chose the cheap path for a fresh worktree (G4h) over the full engine move (G4d, deferred), keeping the 1.5x exit until M2. Lane 3 owns the default switch and its retention, after F54; lane 1 builds the local records pack; lane 4 lands the fresh front end.

- **When part 1 closes:** lane 1 runs G0a (it needs a quiet-ish machine and reports CPU with the load), and lane 2
  runs G0b at the same time. Claude writes G0c from both. Then G0e (lane 1) and G0f (lane 3), then G0d.
- **Then three lanes, split by file so no two lanes edit the same code:**
  - lane 1: GE (the engine core), G1 (ownership files), then G4 (emission, link, store) and G5;
  - lane 2: G2 (front end);
  - lane 3: G0f, then G3 (Core IR, lowering and the optimizer).
- **Dependencies:** G2b and G3c wait for GE. G3g waits for G2g, so lowering reads the engine's check results before the
  old ones go. G4 waits for G3g and G1c. G4d waits for G4e. G5 comes last.
- **Measurement:** only one lane measures at a time. Measurements use pins, not the live tree.

## 6. Lane rules

Part 1's rules apply (`.tmp/BRIEF-COMMON.md` in each lane worktree):
- **Setup:** `source ~/.config/mylang/dev-env.sh`, and builds and focused tests through `scripts/build-slot.sh`.
- **Measuring:** no timing windows and no synthetic load. Report CPU and load beside wall time, over several reps.
- **Files:** evidence goes to `~/ai/canopy/mylang-evidence-archive/experiments/guest-build-engine-20261031/`, never
  into git. Write-ups go in `experiments/guest-build-engine-20261031/<step>/`. No large files in `/tmp`.
- **Landing:** lanes message the coordinator after each step and never land.
- **Changes:** a behavioral change ships with its test, and a new key encoding bumps its kind's format.

## 7. Measurement

- **Trees:** private copies of `~/ai/.home-cache/cache-quick-wins/eda/stage2/mylang` (99k) and
  `~/ai/.home-cache/cache-quick-wins/n24` (400k). Never run two drivers on one copy.
- **Compilers:** ReleaseFast pins under `~/.cache/mylang/edit-loop-pins/<label>-<sha>`.
- **Scenarios:** `experiments/frontend-cache-audit-20261026/measure.py` with
  `--scenarios comment_hub,leaf_body,hub_body,type_edit,add_func`. Tables come from
  `experiments/frontend-edit-loop-20261026/table.py`. Exactness is
  `experiments/frontend-edit-loop-20261026/exact.sh` (`IDENTICAL program`, `IDENTICAL diagnostics`,
  `verify-cache exit 0`).
- **Engine counters:** `--engine-report` on every measured command: served, recomputed, early cutoffs, verified.

## 8. Hard stops (report and wait)

- any program or diagnostic differing from `--no-cache`;
- a verify-mode mismatch;
- a shadow line where the engine serves and the old cache recomputes, until it is explained;
- a kind whose restore costs more than 10% above its recompute;
- a program-wide fact that cannot be expressed as a read (never an unrecorded read);
- G0e's floor above a §2 exit;
- under 25 GB free on `/home/epentland/ai`, or sustained swapping.

## 9. Decisions (made by the user on 31 October)

- **D1. Order against the EDA port: (b), the EDA port waits for G5** ("We can do the eda port after this next wave
  finishes"). The coordinator had recommended (a), resuming it alongside this plan on a ReleaseFast pin of main.
- **D2. Who reviews the design (G0d): (a).** The user reviews the §2 targets and the list of what gets deleted; the
  coordinator reviews the kind-by-kind design. The alternative was the user reviewing the whole of spec §17, as with
  part 1's spec.

## 10. What part 2 does not do, and what happens to the paused branches

- **Out of scope:**
  - **release builds,** which stay one whole-program unit, so any edit recompiles it;
  - **guest run time;**
  - **the compiler's own test loop.** The test-layer rebuild and the selective gate discussed on 31 October are not
    planned.
  - **a resident server,** dropped after S0.
- **The paused branches** (`edit-cost/t1`, `edit-cost/s2`, `edit-cost/k`) stay unmerged. Their findings feed this plan:
  - T1a's position-independent keys and B4's recorded reach are what G3c records;
  - package C's per-entry reach is G3e's recorded reads;
  - L2's memo is moot once reach is recorded rather than walked;
  - S2's three speedups are reapplied in G2e if they still win;
  - K's buffered BLAKE3 is cherry-picked only if G0a's profile still shows the digests.
- **The language does not change,** so the EDA port's hold-still rule (R-6) is unaffected.
