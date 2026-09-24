# Devspeed lane: build residue (2026-09-24)

Branch `devspeed/build-residue`, based on `fc742bd4`, with `devspeed/integration`
merged in twice (`d7885ab2` for check-at-scale, then `1e7267e5` for the false-clean fix
and test-loop-scale).

The goal: after an edit, everything `build` does apart from the check should scale
with the edit. The targets were edit → build minus a separately measured edit →
check of at most 0.35 s at 50k lines and 1.2 s at 200k lines.

## Result

Both targets are met: **0.27 s at 50k and 1.05 s at 200k**, down from 0.58 s and
2.10 s.

How it was measured:

- Two ReleaseFast `-Dcompiler-only` compilers. *before* is the shared baseline
  `trials/devspeed-20260923-private/compilers/integration-fc742bd4`. *after* is this
  branch's head.
- Both ran on fresh copies of the generated ladder (`gen_scale.py`: 10k = 26 modules,
  50k = 120, 200k = 480).
- Every command ran under `taskset -c 0-11`, with `TMPDIR` on disk.
- Each cell is the minimum of 3 samples. The before and after samples were
  interleaved.
- Builds are `build main.my --project --mode Debug` against a private `--cache-dir`.
  The check is `check main.my`, with its default cache in the project.
- The edit changes an integer on the marked line of the middle module's first
  function. The interface edit appends a public function that nothing calls. The
  literal edit swaps that integer for `len("litN")`, a new string literal.
- 1-minute load: 1.4–1.5 at 10k, 1.6–1.8 at 50k, and 2.3–4.8 at 200k (the after
  cold build ran at 4.8).
- The driver is `.tmp/lane/ab.sh`, over `probe.py`, and `summarize.py` reads its logs
  (listed under *Scripts* below).

Seconds unless marked:

| Row | 10k before | **10k after** | 50k before | **50k after** | 50k target | 200k before | **200k after** | 200k target |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| edit → build | 0.262 | **0.114** | 1.145 | **0.377** | — | 4.564 | **1.478** | — |
| edit → check | 0.116 | 0.023 | 0.562 | 0.106 | — | 2.467 | 0.432 | — |
| **edit → build − edit → check** | 0.146 | **0.091** | 0.583 | **0.271** | ≤ 0.35 met | 2.097 | **1.046** | ≤ 1.2 met |
| interface → build | 0.292 | 0.110 | 1.176 | 0.398 | — | 4.679 | 1.474 | — |
| literal edit → build | 0.263 | 0.122 | 1.145 | 0.400 | — | 4.551 | 1.492 | — |
| no-op build | 0.025 | 0.013 | 0.103 | 0.035 | — | 0.403 | 0.118 | — |
| first no-op after a cold build | 0.059 | 0.030 | 0.268 | 0.103 | — | 1.156 | 0.413 | — |
| cold build | 1.32 | 1.23 | 6.34 | 6.30 | no regression | 25.87 | 25.99 | no regression |
| cold build peak RSS | 181 MB | 101 MB | 829 MB | 484 MB | — | 3.41 GB | 1.92 GB | — |
| edit → build peak RSS | 173 MB | 78 MB | 734 MB | 239 MB | — | 2.91 GB | 0.93 GB | — |

Part of the edit → build gain comes from the check-at-scale lane, which is merged
here. To separate the two, a third ReleaseFast compiler was built from the integration
head `1e7267e5`, which has the check and test lanes but not this one. It was measured
against this branch in the same way. Load was 3.0–3.4 at 50k and 3.1–5.9 at 200k, so
these rounds are noisier than the table above:

| Row | 50k `1e7267e5` | **50k this branch** | 200k `1e7267e5` | **200k this branch** |
| --- | --- | --- | --- | --- |
| edit → build | 0.782 | **0.375** | 2.884 | **1.504** |
| edit → check | 0.106 | 0.106 | 0.429 | 0.424 |
| **edit → build − edit → check** | 0.676 | **0.269** | 2.455 | **1.080** |
| interface → build | 0.811 | 0.377 | 2.943 | 1.468 |
| literal edit → build | 0.790 | 0.400 | 2.860 | 1.464 |
| no-op build | 0.042 | 0.034 | 0.158 | 0.116 |
| edit → build: frontend / codegen / link | 0.402 / 0.235 / 0.092 | 0.236 / 0.046 / 0.076 | 1.730 / 0.642 / 0.307 | 0.999 / 0.167 / 0.287 |
| edit → build peak RSS | 428 MB | 239 MB | 1.69 GB | 0.96 GB |

This lane accounts for 0.41 s of the 50k residue and 1.38 s of the 200k residue.

**Cold builds are 6% slower than the integration head at 50k, and 7% faster than
`fc742bd4`.** Measured with `.tmp/lane/cold.sh`: three rounds, interleaved, a fresh
tree and an empty cache each time, load 2.3–4.7:

| Compiler | Round 1 | Round 2 | Round 3 | Frontend | Codegen |
| --- | --- | --- | --- | --- | --- |
| `fc742bd4` | 6.72 | 6.80 | 6.89 | 3.06–3.10 | 3.53–3.67 |
| `1e7267e5` | 5.83 | 6.09 | 6.20 | 2.34–2.43 | 3.36–3.64 |
| this branch | 6.25 | 6.41 | 6.50 | 2.45–2.50 | 3.69–3.88 |

- The codegen cost is `QBE-BATCH-5`. A cold 50k build now starts 735 QBE runs and
  1,014 assembler runs, against 279 and 558 before (`.tmp/lane/coldcount.sh`).
- Batches of about 8 functions cost about 0.3 s of cold build at 50k. They save each
  edit most of a 32-function batch's QBE and assembler time, which the spec bullet
  puts at about 0.1 s.
- The frontend's extra 0.1 s most likely comes from storing one metadata record per
  unit (`EMIT-META-1`) and a stand-in record per function, which the integration
  head does not write. It was not profiled separately.
- At 200k, one cold build each, at different loads: 24.1 s for `1e7267e5` (load 4.6)
  and 25.8 s for this branch (load 5.9). Peak RSS was 2.14 GB and 1.92 GB.

## Where the time goes after an edit

The build's own phases (`--timings=json`) in the minimum sample. *frontend* is the child
that checks, lowers and emits, including its start and the manifest pipe. *codegen*
covers planning, keys, QBE, the assembler and metadata. *link* is the link and
publishing:

| Phase | 50k `fc742bd4` | 50k this branch | 200k `fc742bd4` | 200k this branch |
| --- | --- | --- | --- | --- |
| frontend | 0.785 | 0.238 | 3.402 | 0.979 |
| codegen | 0.212 | 0.046 | 0.642 | 0.167 |
| link | 0.093 | 0.074 | 0.318 | 0.278 |
| total | 1.145 | 0.377 | 4.564 | 1.478 |

The frontend child after the edit, from `emit-project-qbe --lean-manifest=executable
--timings=json` (`.tmp/lane/emitphase.py`, fastest of the samples):

| Frontend phase | 50k after | 200k after |
| --- | --- | --- |
| load, parse, replay syntax, merge sources | 0.055 | 0.21 |
| summary load and dependency keys | 0.024 | 0.10 |
| fresh body checks (every body, see below) | 0.081 | 0.335 |
| effect and origin passes, summaries | 0.004 | 0.013 |
| bytecode lowering | 0.003 | 0.010 |
| native emission (stand-ins, units, pack, manifest) | 0.028 | 0.116 |
| total | 0.220 | 0.885 |
| manifest handed to the driver | 1.46 MB | 5.69 MB |

The same split for the two earlier compilers. They emit through `--lean-manifest`,
since `=executable` is new:

| Frontend phase | 50k `fc742bd4` | 50k `1e7267e5` | 200k `1e7267e5` |
| --- | --- | --- | --- |
| load, parse, replay syntax, merge sources | 0.133 | 0.054 | 0.21 |
| summary load, dependency keys, retention store | 0.056 | 0.024 | 0.10 |
| body replay and fresh body checks | 0.152 | 0.085 | 0.34 |
| effect and origin passes, warnings | 0.161 | 0.003 | 0.012 |
| bytecode lowering | 0.046 | 0.059 | 0.228 |
| native emission | 0.131 | 0.115 | 0.547 |
| total | 0.738 | 0.368 | 1.56 |
| manifest handed to the driver | 8.76 MB | 8.75 MB | 35.0 MB |

This lane's part of the frontend is lowering and emission:

- 50k: from 0.174 s to 0.031 s;
- 200k: from 0.775 s to 0.126 s;
- the manifest the driver parses: from 35 MB to 5.7 MB at 200k.

The residue at 200k, 1.05 s, splits roughly as follows:

- 0.34 s is body checks that `check` itself skips;
- 0.12 s is emission;
- about 0.1 s is the child's start and the manifest pipe;
- 0.17 s is codegen, of which the one QBE run and assembler run take 0.04 s and the
  rest is whole-program bookkeeping over 18,700 units;
- 0.28 s is the link: `ld.lld` writes a 130 MB executable from 3,841 objects in
  0.20 s, and the rest is the 8.4 MB sidecar and the publish.

## What changed

Each item has a `SPEC.md` bullet and a test.

### 1. Lowering-free keys: lower and emit only the changed functions

- **`EMIT-STANDIN-1`** (new). An executable's lean emission (`build`, `run`,
  `run-project`) keys every declared function by its *source identity*. That is the
  check's stable declaration key, dependency context, and declaration-region digest
  and length, all taken from the check lane's `semantic_key.Prepared`, which the
  summary request now carries.
  - Each lowered function leaves a record in the fragment store. The record holds:
    - its unit answer and metadata digest;
    - the facts other units and the program read about it: inline key, own
      allocation, calls after inlining, parameter writes, function values, and the
      invoke, arena and text marks;
    - a snapshot digest of what its unit read: emission switches, each named
      function's interface, inline key, allocation and writes, the schema of each
      record it reaches, the value-target set, and the source digests.
  - A later emission lowers only these functions:
    - functions with no record;
    - functions whose record says a caller may inline them;
    - the few that are always lowered: the entry, printers, specializations and
      lambdas.
  - It then recomputes the whole-program facts from the lowered bodies plus the
    records. A function whose snapshot no longer matches gets lowered, and this
    repeats until nothing is stale. The manifest names the same texts, facts and
    metadata as a full emission.
  - At 200k, lowering after an edit fell from 0.228 s on the integration head to
    0.010 s. At 50k, from 59 ms to 3 ms. Emission fell with `EMIT-META-1` and the
    executable manifest as well (see the frontend tables).
- **`EMIT-META-1`** (new). A lean unit names its positions, messages and inline frames
  by the digest of a stored record. The record is keyed by the unit's key plus the
  digests of its sources, so an unchanged unit locates no instruction. A
  just-computed record also rides inline in the manifest. An executable's lean
  manifest (`--lean-manifest=executable`) leaves out export, schema, wire, codec and
  test-dependency facts, and its emission no longer computes them.
- Keys reuse one set of canonical-encoding buffers across functions, and a store
  checks a text's presence by name in its open directory.

### 2. The manifest and the driver: O(changed) work where it was O(program)

- **`BUILD-METADATA-KEY-1`** (new). Batch metadata is keyed by a digest of what it
  is rendered from, and it is rendered only on a miss.
- **`QBE-BATCH-4`** (new). The shared metadata C unit names functions only for the
  frame map, so an added function does not recompile it.
- **`QBE-BATCH-5`** (new). Batch boundaries fall on one symbol in 8, not 32, so a
  body edit recompiles about 8 functions rather than 32 or more.
- **`QBE-BATCH-6`** (new). Metadata groups are four times coarser than code
  batches, which gives cold builds back most of the tool starts that `QBE-BATCH-5`
  added.
- Emission marks export roots once, instead of scanning them for every unit.

### 3. Link

- **`BUILD-LINK-1`** (new). Only the first link of a given shape goes through the
  `zig cc` driver, as `zig cc -###`, which links and prints its `ld.lld` command. The
  command is recorded as a template. Every later link runs `zig ld.lld` directly and
  skips the driver's host probe.
  - `--gc-sections` stays.
  - A direct relink of the same objects writes the bytes `zig cc` wrote. The CLI test
    checks this: the relink keeps the published executable.
  - A vanished path or a failed direct link falls back to `zig cc`.
  - `--report` names the route as `link_route`.
  - This covers libraries too: a guest-test library link starts no `zig cc` after its
    first link.
- **`BUILD-PUBLISH-1`** (new). A link over freshly compiled objects publishes the
  candidate without comparing two whole executables. At 200k, the comparison read
  two 130 MB files.
- Two skips were already in place and still hold: the link, when every object was
  reused (`BUILD-BACKEND-4`), and the whole build (`BUILD-NOOP-1`). The link identity
  they use is now BLAKE3, and it is read without parsing the sidecar's records.

### 4. Hash hygiene

- **`BUILD-KEYS-1`** (new). Object keys and the link identity are BLAKE3
  (`mylang-object-key-v3`). They were SHA-256, which the pinned toolchain runs at
  about 14 MB/s on this host, twice per unit and per batch. The sidecar names the
  link identity first, so reuse checks no longer parse every record.
- **`BUILD-VERIFY-1`** (new). A cached object whose recorded inode, size and mtime
  still match is accepted by `stat`, without being read and hashed.
- The run-manifest cache key moved to BLAKE3 (`native-run-validated-graph-v2`). The
  fragment store format moved to `mylang-qbe-fragments-v2` (pack `MYLFRAG3`).

### 5. Fragment store eviction

- **`FRAGMENT-SWEEP-1`** (new). Every process that opens a store holds a shared lock
  on its `.lease`. After a whole-project emission has flushed its pack and its
  replay, the store may sweep: once the texts written since the last sweep outnumber
  both 4,096 and the texts this emission names, it deletes every text under `il/`
  that no pack or replay names. It does this only when it can take the lock
  exclusively. The test covers named texts, unnamed texts, staging litter and a
  second holder of the lease.

### 6. `--drop-debug` on the project path

- **`DEBUG-LINE-1`** (amended). `lowerForReceipt` lowered projects with
  `drop_debug = false` before emission could ask for anything else, so ReleaseFast
  project builds kept `debug` lines. They now drop them. A CLI test builds one
  project in both modes.

## Ratchets

The ratchets count work deterministically. None of them uses a wall-clock threshold.

- `qbe_fragments_test`, *an executable's emission lowers only what an edit changed…*
  (`EMIT-STANDIN-1`):
  - a cold emission reuses nothing;
  - an unchanged one reuses exactly 2 of the helper module's functions and lowers the
    rest;
  - body, interface, signature and schema edits each produce the manifest a full
    emission produces.
- *…stands in every function of the modules it did not touch*: after a body edit in
  one module, both functions of the untouched module are still reused (exactly 2 of
  4), and the lowered and reused counts sum to the cold count.
- *an edit computes metadata only for units of the sources it changed* (`EMIT-META-1`).
- *a sweep removes only the texts no pack or replay names…* (`FRAGMENT-SWEEP-1`).
- `qbe_build_batch`: batch sizes near 8, and metadata groups near 32 within a module
  (`QBE-BATCH-5`, `QBE-BATCH-6`).
- `qbe_build_outputs`: the shared unit is unchanged by an added function
  (`QBE-BATCH-4`), and metadata digests change exactly when the tables can
  (`BUILD-METADATA-KEY-1`).
- `qbe_build_cache`: key composition (`BUILD-KEYS-1`) and stat versus content
  acceptance (`BUILD-VERIFY-1`).
- CLI tests in `test/integration.zig`:
  - relink keeps, compile replaces (`BUILD-PUBLISH-1`);
  - `recorded changed` → `direct kept` → `direct changed` (`BUILD-LINK-1`);
  - debug lines are dropped in ReleaseFast only (`DEBUG-LINE-1`).
- The CLI test *an incremental build after body, signature and interface edits builds
  the program a clean build builds* still passes: the same guest objects and the same
  output as a clean build.

## The coordinator's follow-ups

### Item 1, checking only the changed bodies: not done

What is done is the lowering-free key, and lowering and emitting only the changed
functions (`EMIT-STANDIN-1`). The build frontend still checks every body. That costs
0.08 s at 50k and 0.34 s at 200k, a third of the remaining 200k residue.

Standing bodies in during `build` has three prerequisites. All three are check-lane
work:

1. **Types and specializations a body creates.** The checked program's record table
   holds every type a body interns, including containers. It also holds the
   specializations a body instantiates.
   - `runtime_data` renders a descriptor for every one of those types.
   - So a stood-in body that is the only user of `list[list[str]]`, or of `f[int]`,
     would change the descriptor set, and reused units could name symbols nobody
     defines. The executable would also differ from a clean build's.
   - A summary would have to carry the types and specializations its body interns,
     and the stand-in would have to intern them again.
2. **Stale records need a checked body.** A stand-in whose record goes stale during
   emission (an interface or inline-key change) has to be lowered, which needs its
   body. That means a hook in the summary request, with per-source digests kept in
   each record so the hook can refuse bodies whose file changed, plus a
   check-again-and-re-emit fallback.
3. **Summaries stay stale after lowering commands.** A lowering command publishes no
   summary once it has had one to stand in, so an edited body's summary is never
   refreshed by `build`.

The hook would sit where `prepareStandIns` in `project_compile.zig` computes the
identities. `sourceIdentity` would drop the checked name, since the declaration key
already names the module and the declaration, so the identity could be computed
before the check.

### Test-loop finding: "the link goes through the zig cc driver"

Resolved by `BUILD-LINK-1`, which that lane's measurement predates. On `mylang test`
at 50k and 200k after this merge, no library link starts `zig cc`. Each edit starts
one `zig ld.lld`.

### Test-loop finding: "the first edit after a cold run is slower"

The finding is confirmed. The cause is mostly not QBE batches. Guest test loop,
fresh copies, `.tmp/lane/tl.sh` and `tl2.sh`, ReleaseFast after-compiler, traced with
`strace --seccomp-bpf`:

| Run | 50k | 200k |
| --- | --- | --- |
| cold `test` | 1.03 | 3.44 |
| first edit after cold | 0.55 (51 QBE runs) | 1.92 (205 QBE runs) |
| same affected set again | 0.32 (1 QBE run) | 1.23 (1 QBE run) |
| a new affected set, few changed batches | 0.53 (1 QBE run) | 1.93 (2 QBE runs) |
| a new affected set, many changed batches | 0.49 (36 QBE runs) | 1.72 (143 QBE runs) |

- **The dominant cost is the embed wrapper.** Every new affected set changes the
  library's export list, and `libraryWrapper` renders one C unit over all of it.
  - At 200k, with 480 exports, that unit is 1.68 MB of C. Roughly: `dispatch`
    430 KB, `wire_dispatch` 300 KB, the schema literal 270 KB, codecs 180 KB, and the
    `co_*` functions 400 KB.
  - `zig cc` compiles it in 0.55 s on the critical path. Of that, clang takes
    0.45 s, `ld.lld -r` 0.07 s and the host probes the rest.
  - At 50k it is 0.18 s.
  - The 143 QBE runs of a changed selection finish within 0.27 s, in parallel with
    that compile.
- **Batches change only where membership changes.** The planner's boundaries are
  already content-defined (they fall on a hash of the symbol, `QBE-BATCH-5`). A
  selection that drops functions from a run changes that batch's key.
- **`build` re-batches only the edited module.** At 50k, per `.tmp/lane/rebatch.sh`:
  - a body edit starts 1 QBE run and 1 assembler run;
  - a new unreferenced public function starts 1 QBE run and 2 assembler runs;
  - a new function called by the edited body starts 1 QBE run and 2 assembler runs.
- **Options, cheapest first:**
  1. Compile generated C without UBSan. Clang on the 200k wrapper drops from 0.54 s to
     0.27 s, and its object from 8.2 MB to 2.4 MB (`.tmp/lane/ccbench.py`). This is
     a policy change about checking generated code, so it is not made here.
  2. Compile C units with the `-cc1` command that `zig cc -###` prints, the way the
     link template works. That saves the probes and `ld.lld -r`: 0.04 s at 50k and
     0.1 s at 200k per compile.
  3. Make the test library's export set independent of the affected set. For
     example, the wrapper could list every test of the graph through weak
     references, so a selection change does not re-render it. That is the test lane's
     selection, together with this lane's wrapper.
  4. Render the wrapper as data: a table of entries, with one fixed dispatcher
     compiled once.
  - Reusing a batch compiled for a larger selection is not safe for a shared
    library. Every guest symbol is exported, so the extra members would stay live,
    and their references to functions that are not in the library would fail
    `dlopen` under `-z now`.

## Files outside the lane's scope

All changes outside the scope are small:

- `src/semantic_summary.zig` and `src/sema_summaries.zig` (check lane):
  `Request.prepared`, which `Plan.init` sets, so the build can key functions by
  source identity. 5 lines.
- `src/bytecode_inline.zig`: a `pub fn eligibleFunction` wrapper over the existing
  inline-eligibility test.
- `src/qbe_arena.zig`: `opens` made `pub`.
- `src/qbe_exports.zig`: `rootMask` and `describeMarked`, so export roots are marked
  once.
- `test/integration.zig`: the three CLI tests above.
- Nothing in `native_test_*.zig`, `sema*.zig` beyond the two files above,
  `semantic_cache`, `semantic_store` or `frontend_cache` was touched.

## Known gaps

- `build` checks every body. See item 1 above.
- **The link scales with the program, not the edit.** At 200k the executable is
  130 MB:
  - `.text` is 78 MB;
  - `.data.rel.ro` is 52 MB of location and inline tables;
  - linking it from 3,841 objects takes `ld.lld` 0.20 s. Without `--gc-sections`
    it still takes 0.15 s.
  - Smaller position tables are the lever.
  - The link also rewrites the 8.4 MB `<output>.qbe-manifest.json` sidecar, which only
    `link_identity` is read back from.
- **The lean manifest is 5.7 MB of JSON at 200k.** The driver parses it into a
  dynamic tree and keys all 18,700 units: about 0.12 s of codegen that is not QBE.
- **A function keeps one record.** After an edit replaces it, returning to the
  earlier version lowers the function once more. Both tests pin this.
- **A body edit re-lowers every function of the edited source,** because records
  snapshot whole-source digests for positions. That costs 10 ms at 200k, and the
  texts it produces are fragment hits.
- **The first no-op after a cold build is not a receipt hit.** The cold manifest
  carries metadata inline and the next one names it by digest. It costs 0.1 s at 50k
  and 0.4 s at 200k, once.
- **The sweep runs after whole-project emissions only.** Selective (test) packs are
  bounded, but a test-only workflow never sweeps texts.
- **Cold builds cost 0.3 s more at 50k than on the integration head, about 6%.**
  The finer batches of `QBE-BATCH-5` start 456 more QBE runs and 456 more assembler
  runs. `QBE-BATCH-6` and inline metadata already won part of it back. Against
  `fc742bd4`, cold is still 7% faster. See the cold table under *Result*.

## Gate

On the branch head, with `devspeed/integration` (`1e7267e5`) merged:

| Step | Result |
| --- | --- |
| `zig build test --summary all --maxrss 8000000000` | 92/92 steps succeeded; 1,900 tests run, 0 failed |
| `zig build test-qbe --summary all` | 51/51 steps, 390/390 tests |
| `zig build test-qbe-build --summary all` | 33/33 steps (its test verdict was shared with the `zig build test` run just before) |
| `zig build fmt-check` | clean |
| `zig-out/bin/mylang test tests/lang` | 569 passed, 0 failed, across 106 programs |

Before the second merge, focused runs of the following passed; the gate above
covers them again on the merged head:

- `qbe_fragments_test`, 19 tests;
- the CLI tests *an incremental build after body, signature and interface edits builds
  the program a clean build builds*, *a relink of reused objects…*, *…drops debug
  lines…*, *…how zig cc links…*, *an unchanged build keeps its executable…*, and the
  `lean` and `stand` filters.

## Scripts

All scripts are in the worktree's `.tmp/lane/`:

- `ab.sh`, `probe.py`, `summarize.py`: before and after build loops, and the
  measurement logs `ab10-1.out`, `ab50-3.out` and `ab200-2.out`;
- `emitphase.py`: frontend child phases;
- `linkbench.py`: link variants;
- `rebatch.sh`: QBE and assembler runs per kind of edit;
- `tl.sh`, `tl2.sh`: the guest test loop across affected sets;
- `capture_c.sh`, `ccbench.py`: the wrapper C unit and its compile variants.
