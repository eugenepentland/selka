# The compilation model — 24 September 2026

**Asked:** how does mylang turn a module into machine code, which parts of that cost grow
with the project instead of the edit, and how should the compilation model change so a
large codebase's edit → build → test loop beats Go's? This is an audit with measurements
and throwaway prototypes. No production code changes; the scripts are in
`experiments/compilation-model-20260924/`.

Base: `main` fd36abc2 (the compiler of `devspeed/integration` 183251a9). Timed compiler:
the shared ReleaseFast build `trials/devspeed-20260923-private/compilers/integration-183251a9`.
Three prototype compilers were built from uncommitted patches (see *Prototypes*).

## Summary

**Where the time goes.** At 200k lines, one body edit costs 1.62 s quiet, per the
build-loop report. One build traced here with `strace` at load 5 took 2.42 s:

- **The frontend child:** 1.18 s, 950 MB. About 0.4 s of it re-reads the whole
  project: load, replay, merge, key. Another 0.42 s re-checks all 18,722 bodies.
  Emission bookkeeping over every function record is 0.18 s.
- **The driver:** 0.51 s of bookkeeping. It parses a 5.7 MB JSON manifest, keys 18,721
  units, plans 2,799 batches and `stat`s every object. It then runs one QBE batch and
  one assembler run, 0.04 s together.
- **The link:** 0.56 s at that load, 0.25 s quiet. `ld.lld` reads 3,841 objects and
  writes a 90 MB executable, resolving 4.6 million relocations.
- **Publishing:** 0.13 s. The 8.4 MB sidecar, the rename and the receipt.

Only about 0.06 s of that is proportional to the edit: one batch, and lowering and
emitting the edited module's functions.

**Why.** mylang has no compiled module interface. Every command rebuilds one merged
program: one AST, one type catalog, one checked program, one manifest. The caches
(syntax, summaries, fragments, objects) skip work per function, but each command still
walks every function to find out which ones to skip. Nothing is essentially
whole-program except the static link.
- Symbols are named by content: `myl_f_<sha(name)>`, `myl_t_<sha(type identity)>`,
  `myl_lit_<digest>`.
- GC roots live on a shadow stack, so there are no stack maps.
- Trap metadata is found per batch through a linker section.
- Import cycles are rejected, so effects can be computed bottom-up.

**The decisive prototype.** I compiled one module (`m240` of the 200k tier) alone.
Its only dependency was a stub made of signatures, which stands in for Go-style export
data.
- All 46 of its functions came out with the same unit keys as in the whole-program
  build, and the object files are byte-identical (`cmp`).
- The stub project builds cold in 0.26 s at 74 MB peak. After a body edit it rebuilds
  in 0.08–0.12 s at 49 MB peak, and neither figure depends on project size.
- Doing the same for all 480 modules in parallel, frontend only, takes 2.7 s on
  20 threads (load 12), at 14 MB per process. The whole-program cold frontend takes
  15.4 s at 1.98 GB.

**The link is the only essential whole-program step, and it can leave the edit loop.**
A development build that puts the edited module in its own shared object relinks
that object in **5 ms** instead of 254 ms, and the program prints the same answer.
- One `.so` per module costs 109 ms of start-up at 200k. Two libraries cost 38 ms,
  against 9 ms for the static executable.
- Most of that start-up is the 3.2 million pointer relocations of the position tables.
  A compact, pointer-free table encoding is 10× smaller (51.8 MB → 5.1 MB) and needs
  no per-instruction relocation.

**Scale beyond 200k fails today, and memory is not the first limit.**
- **`E_GENERIC_LIMIT`.** Two program-wide budgets of 100,000 type-expression operations
  (`nominal_layouts`, `nominal_templates`) reject the generated project from about 240k
  and 480k lines. Neither is configurable.
- **Frontend cache.** A 128 MiB budget starts evicting every entry on every run at about
  440k lines, so nothing is reused. 500k edit → check becomes 5.4 s, against 0.51 s at
  200k.
- **`mylang test`.** A hard 16 MiB snapshot limit (`InvalidTestSnapshot`).
- **Project bytes.** The default 16 MiB budget; `mylang.json` can raise it.
- **The link command line.** It passes every object path, and at 1M the `execve`
  fails with `E2BIG`.
- **Memory.** At 1M the cold frontend exceeds the 8 GiB address-space ceiling, and a
  14 GiB one too.

With these lifted by patch or worked around:
- 500k builds cold in 89 s at 4.8 GB, and an edit builds in 5.6 s.
- At 1M, edit → check is 4.8 s and the whole-program static link alone is 2.8–3.2 s
  (load 8).
- In this model, 1M edit → build would be 10–12 s.

**Recommendation.** Make the module the unit of compilation, Go style:
- a per-module interface artifact with an interface hash;
- per-module check, lowering, emission and objects, keyed by the module's source and
  its imports' interface hashes;
- a module-DAG scheduler that runs modules in parallel;
- a dynamic development link, with the static link kept for release.

Before that, lift the scale limits, stop the frame-map roots array from depending
on the function set in QBE builds (the unexplained interface-edit cost), and replace the
position tables with a compact encoding. The plan below says what each step buys.

| Target | Current model | After the plan (projected from measurements) |
| --- | --- | --- |
| 200k edit → build ≤ 0.5 s | 1.62 s | ~0.1 s dev (module compile 0.08–0.12 s + 5 ms relink); ~0.35 s with a static link |
| 1M edit → build ≤ 1 s | does not build (limits); with them patched, ~10–12 s | ~0.15 s dev. A static link alone is ~1.3 s quiet (measured 2.8–3.2 s at load 8), and ~0.75–1.0 s with compact tables and no `--gc-sections`, so 1 s with margin needs the dynamic dev link |
| 200k cold ≤ 10 s | 21.8 s | ~8–10 s: parallel module frontends (≤ 2.7 s measured) pipelined with codegen (110–119 CPU-s over 20 threads). Codegen volume sets the floor |
| 200k peak ≤ 1 GB | 1.9 GB cold, 0.95 GB after an edit | per-module processes of 14–75 MB; the largest process is the static linker (560 MB) |

## Contents

1. Method
2. The pipeline as it is
3. What is whole-program, and why
4. Module boundaries
5. Other compilation models
6. Parallelism
7. Linking
8. Memory
9. Scale beyond 200k
10. Prototypes
11. Ranked implementation plan
12. Correctness strategy
13. What surprised me

## 1. Method

- **Machine.** i7-12700H, 20 threads, 30 GB. The machine was shared with other agents
  for the whole session: the 1-minute load average was 2–18, usually 7–13, and every
  table gives the load. Timings are under `taskset -c 0-11`. Absolute wall times at load
  8–10 are about 1.2–1.8× the quiet figures in
  [the build-loop report](devspeed-build-loop-2026-09-24.md). That report is the
  reference for headline totals; this audit uses splits, counters and CPU time, which
  shift less with load.
- **Tiers.** `gen_scale.py` from `experiments/build-loop-20260924/`: 50k = `120 38`,
  200k = `480 38`, 500k = `1200 38` (17.4 MB, 46,801 functions), 1M = `2400 38`
  (35.1 MB, 93,601 functions). Edits as in `run_scale.py`: a constant in the middle
  module's first body, or an appended public function (*interface edit*). The 500k and
  1M tiers need `mylang.json` with `{"version": 1, "budgets": {"max_total_bytes": …}}`
  (§9).
- **Mode.** Default `mylang build` (ReleaseFast QBE, frame-map protocol) unless marked
  `Debug`.
- **Scripts** (all in `experiments/compilation-model-20260924/`):

  | Script | What it does |
  | --- | --- |
  | `probe.py` | Per-stage ladder. The frontend child and the driver are also run as separate processes (`emit-project-qbe`, then `build --manifest-file`), so each one's time and peak RSS is visible. `trace` spans every tool with `strace`. |
  | `timed.py` | Wall, peak RSS, CPU and load for one command. |
  | `rss_timeline.py` | Samples the process tree's RSS over time, next to the phase timings. |
  | `capture_link.py`, `linkbench.py`, `lldtrace.py` | Link variants and prototypes. |
  | `module_compile.py` | Per-module compile prototype. |
  | `ab_iface.py`, `ab_module.py` | Interleaved A/B of two compilers, and of a whole-program build against a single-module build. |
  | `rebuild_link.py` | Re-runs a link that failed with `E2BIG` through a response file. |
  | `go_probe.py` | Go's own per-package split. |
  | `elfsizes.py`, `meta_size.py` | Object and executable composition. |
  | `summarize.py` | Tables from the logs. |

## 2. The pipeline as it is

### 2.1 The map

```text
mylang build main.my --project -o out            (parent: the driver, single thread + tool pool)
 ├─ zig version probe                            4 ms
 ├─ emit-project-qbe main.my --lean-manifest=executable [--drop-debug --drop-step-checks
 │   --drop-frame-checks]                         (child: the frontend, ONE thread)
 │   1  load sources, lex every module header      project.zig          all modules, no cache
 │   2  replay check (EMIT-REPLAY-1)               main.zig             key = every module's bytes
 │   3  parse | replay cached syntax               interfaces.zig       per-module cache (frontend cache)
 │   4  interface index + checkSignatures          interfaces.zig       all modules, every run
 │   5  merge into ONE AST + source map            project_syntax.zig   deep copy, program ordinals
 │   6  record catalog, dependency keys            semantic_key.zig     per function, memoised
 │   7  summary load, stand-in planning            sema_summaries.zig   one slot per entry
 │   8  body check                                 sema.zig             EVERY body in build/run/test
 │   9  effect / mutation / origin passes          effects.zig          seeded by summaries
 │  10  bytecode lowering (EMIT-STANDIN-1)         lower.zig            changed functions only
 │  11  inliner fixed point                        bytecode_inline.zig  crosses modules
 │  12  QBE emission: first/second/meta pass       qbe.zig              per-function fragment store
 │  13  whole-program facts, runtime_data, manifest JSON -> stdout
 ├─ receipt check (BUILD-NOOP-1)                  BLAKE3 over the manifest
 ├─ JSON parse, validate, key 18.7k units, plan batches (1 in 8) and metadata groups (1 in 32)
 ├─ tool pool (clone(VM|VFORK)): qbe + zig clang -cc1as per missed batch; metadata asm per missed group;
 │   zig cc for the shared metadata C unit (descriptors, literals, host bridges, frame-map roots) and the entry
 ├─ link: zig ld.lld from a recorded template (BUILD-LINK-1), --gc-sections, -s, static, non-PIE
 └─ sidecar <out>.qbe-manifest.json (8.4 MB at 200k), publish, receipt
```

`mylang test` shares steps 1–9 and 11–12 through a long-lived
`native-test-compile` session.
- It lowers only the selected tests' closure (`emitQbeSelected`).
- It writes a library manifest to a file, and `build --library --manifest-file` links
  one `tests.so`.
- It runs each test as its own process, in parallel, `dlopen`-ing that library.
- The declaration check (`list-interfaces --contracts`) runs beside the session.

Two things are different from `build`:
- The library adds a whole-program wrapper C unit: dispatch, wire dispatch, schema and
  codecs, 1.68 MB of C at 200k. Its dispatch table is ordinal, so any change to the
  selection re-renders it.
- The session checks every body.

### 2.2 Per stage, 50k and 200k

Frontend phases come from `emit-project-qbe --timings=json`. Driver phases come from the
`build` report. Tool spans come from `strace`. *CPU* is user + system over the process
tree. Each row is the fastest of 3 samples.

**Frontend child (`emit-project-qbe`), one thread**

| Phase (seconds) | 50k cold | 50k edit | 200k cold | 200k edit | 200k interface edit |
| --- | --- | --- | --- | --- | --- |
| load + header lex | 0.032 | 0.018 | 0.123 | 0.074 | 0.074 |
| parse / syntax replay | 0.201 (parse) | 0.027 (replay) | 0.505 (parse) | 0.109 (replay) | 0.112 |
| source merge | 0.041 | 0.021 | 0.091 | 0.086 | 0.082 |
| summary load + dependency keys | 0.092 | 0.030 | 0.271 | 0.123 | 0.117 |
| body check (bodies checked) | 0.128 (4,682) | 0.104 (4,682) | 0.461 (18,722) | 0.418 (18,722) | 0.404 |
| effect / origin passes | 0.157 | 0.003 | 0.421 | 0.011 | 0.011 |
| bytecode lowering (functions lowered) | 0.095 (all) | 0.003 (41) | 0.304 (all) | 0.012 (41) | 0.012 |
| native emission (units emitted) | **3.704** (4,681) | 0.041 (1) | **12.932** (18,721) | 0.176 (1) | 0.158 |
| **total in-process** | 4.51 | 0.28 | 15.29 | 1.17 | 1.11 |
| wall (process) | 4.54 | 0.30 | 15.41 | 1.23 | 1.16 |
| peak RSS | 495 MB | 243 MB | 1,980 MB | 949 MB | 948 MB |
| load | 9.8 | 10 | 2–4 | 11 | 9 |

**Driver (`build --manifest-file`, parent process + tools)**

| Step | 50k edit | 200k edit | 200k interface edit | 200k cold |
| --- | --- | --- | --- | --- |
| driver wall | 0.179 | 0.72 (0.65 Debug) | 0.82 (0.59 Debug) | 21.9 (load 11.5) |
| manifest parse → first QBE start (strace) | 0.09 | 0.40 | 0.42 | — |
| QBE + assembler (runs) | 0.02 (1+1) | 0.04 (1+1) | 0.04 + shared C unit **0.26** (`zig cc`) | 110–119 CPU-s over 2,799 + 1,043 runs |
| link (`ld.lld`) | 0.17 | 0.25–0.56 | 0.52 | 0.36–0.66 |
| sidecar, publish, receipt | 0.03 | 0.13 | 0.13 | — |
| peak RSS (driver / `ld.lld`) | 179 MB | 577 MB / 558 MB | 576 MB | 435 MB / 558 MB |
| load | 10 | 5–11 | 5–11 | 11.5 |

**No-op.** The frontend child still loads and hashes every source, then replays the
last manifest (EMIT-REPLAY-1):
- 0.24–0.26 s at 200k (load 9) and 1.5 s at 500k;
- the driver's receipt then returns before parsing anything;
- quiet, the whole no-op is 0.198 s at 200k.

With `--report`, which the probe passes, the receipt is bypassed and the driver re-keys
every unit (+0.17 s at 200k).

**The `mylang test` path after an edit** at 200k, from the test-loop lane's trace
(`devspeed-test-loop-scale-2026-09-24.md`):

| Step | Seconds |
| --- | --- |
| session check (every body) plus facts | 0.89 |
| declaration check (overlapped) | 0.21 |
| selective lowering and emission of the 720-function closure | 0.11 |
| build child (0.11 of it the link) | 0.22 |
| 240 test processes | 0.12 |
| planning, start-up, tail | 0.18 |

At 500k (proto2, load 6–10) edit → test is 4.8–6.1 s at 2.78 GB, and a no-op `test`
is 7.0 s.

**End to end.** The 50k and 200k columns are this session's (the 200k *build* rows at
load 9–13). The quiet reference comes from the build-loop report.

| Step | 50k | 200k | 200k quiet reference |
| --- | --- | --- | --- |
| cold build | 7.4 s, 29.6 CPU-s, 489 MB | 27.8–37.3 s, 125 CPU-s, 1.94 GB | 21.8 s, 1.9 GB |
| no-op build | 0.13 s, 42 MB | 0.57 s (receipt bypassed by `--report`) | 0.198 s |
| edit → build | 0.49 s, 247 MB | 1.78–1.88 s, 979 MB | 1.62 s |
| interface → build | 0.54 s | 2.12 s (Debug 1.78 s) | 2.23 s (Debug 1.58 s) |
| edit → check | 0.13 s | 0.51–0.54 s, 458 MB | 0.455 s |
| edit → test | — | — | 1.30 s |

**Threads.** The frontend runs on one thread; nothing in check, lowering or emission
uses `std.Thread`. The driver starts tools in a pool as wide as the allowed CPUs, capped
by MemAvailable at 256 MiB per tool. QBE is single-threaded per batch. `ld.lld` uses
every thread it is given: with `--threads=1` the 200k link goes from 0.254 to 0.404 s.

**What is cached, and at what granularity**

| Cache | Granularity | What a hit skips |
| --- | --- | --- |
| Header / source load | none | nothing: every module is lexed and SHA-256'd on every run |
| Syntax | per module (frontend cache, **128 MiB budget**) | parsing |
| Replay | whole project, one slot per entry | the whole frontend of an unchanged project |
| Check summaries | per function, **one 6.6 MB slot per entry**, rewritten after each check | the body check in `check`; only pass facts in `build`, `run` and `test` |
| Stand-in records (EMIT-STANDIN-1) | per function, keyed by source identity | lowering |
| Fragment store | per function IL text (16.6 KB each, 436 MB at 200k) plus a metadata record | emission |
| Objects | per batch of about 8 functions; metadata per group of about 32; shared C unit and entry by text | QBE, the assembler and `cc` |
| Link | whole program (`link_identity`) | the link, when nothing changed |
| Receipt | whole build | everything after the frontend |
| Runtime archive | per runtime content hash, prebuilt | compiling the runtime |

Every one of these still needs its whole key space enumerated on every run. That
enumeration is the whole-program cost.

## 3. What is whole-program, and why

*Scales with* is what the step walks on a one-line edit. *Essential* means a correct
separate-compilation design would still need it at link time.

| # | Step | Scales with | 200k edit cost | Essential? | Why it is whole-program today; what removes it |
| --- | --- | --- | --- | --- | --- |
| 1 | Header lex of every module, SHA-256 of every file | modules, bytes | 0.074 | no | Discovers the import graph. Go stats files and trusts a build cache keyed by content. A per-module state file (size, mtime, digest) makes it O(changed). |
| 2 | Syntax replay of every module | modules | 0.11 | no | Checking needs every AST in memory. A per-module compile needs only its own AST plus its imports' interfaces. |
| 3 | Merge into one AST (deep copy) | nodes | 0.086, +177 MB | no | Node, function and record IDs are ordinals in the merged program. |
| 4 | Dependency keys for every function | functions | 0.10 | no | Per-function validity keys exist because there is no interface hash. With one, a module's key is its source digest plus its imports' interface hashes. |
| 5 | Body check of every body in `build`, `run`, `test` | bodies | 0.42 | no | Lowering needs checked trees, and summaries do not carry the types and specializations a body interns (build-residue item 1). A per-module compile checks only its own bodies. |
| 6 | Record/type catalog; types interned during body checks get program-wide ordinals in check order | types | in 5 | no | Everything downstream already names types by content: fragment keys by name, descriptors by `sha(identity)`. Ordinals can be module-local. |
| 7 | Effect, mutation and origin passes (a transitive fixed point) | call graph | 0.011 (seeded) | **facts yes, pass no** | Effects are transitive, but imports form a DAG (`E_IMPORT_CYCLE`). Each module can be solved bottom-up from its imports' exported facts, which is exactly what summaries hold. |
| 8 | Generic specialization: one instance per (declaration, arguments) per program, always lowered | instantiations | small here | no | Instantiate in each using module under a content-derived symbol, deduplicated by the linker (COMDAT, or the content-named symbols the program already uses). |
| 9 | Inliner fixed point across modules | lowered functions | small | only for eligible leaves | Only small, leaf, non-allocating functions are inlined (`bytecode_inline.eligible`). Their bodies go into the interface, as Go exports inlinable bodies. A body edit to such a function changes its interface hash. |
| 10 | Allocation analysis: may each callee allocate? (decides GC-root protection at call sites) | call graph | in emission | **fact yes** | Per exported function, in the interface. |
| 11 | Function-value target set: one digest over every `function_value` instruction | functions | in emission | no | Conservative in development builds (an indirect call may allocate), or an interface fact per signature. |
| 12 | Stand-in snapshot re-validation over every function record | functions | 0.18 | no | A consequence of 4 and 5. |
| 13 | `runtime_data`: a descriptor for every type in the catalog, in one C unit | types | in 17 | no | Descriptors are content-named (`myl_t_<sha>`), so each module can emit its own as COMDAT. |
| 14 | Literal pool: `# myl-lit` lines from every unit, collected into the shared C unit | units | in 17 | no | Content-named (`myl_lit_<digest>`), so they can be per module as COMDAT. |
| 15 | Host bridges (`<sym>_host` stubs) | host declarations | in 17 | no | Per module. |
| 16 | **Frame-map roots array**: `extern` plus a `used` array naming every function's `_meta`, emitted whenever the frame map is used | functions | **0.26 s `zig cc` of 3 MB on every interface edit** | no (LTO only) | Needed only so LTO keeps the metadata; `qbe_build_outputs.frameMapRoots` says so itself. In QBE builds the retained `mylang_frame_map` section already references every `_meta`. This is the unexplained default-mode interface cost (§10.1). |
| 17 | Shared metadata C unit, keyed by its whole text | all of 13–16 | 0.26 when it misses | no | Split per module (13–15); drop 16 outside LTO. |
| 18 | Manifest JSON: 5.7 MB lean after an edit, 22 MB cold, piped to the driver and parsed into a dynamic tree | units | ~0.15 | no | Module-level records, in-process or binary. |
| 19 | Driver: key 18.7k units, plan batches, `stat` every object, `link_identity` JSON over the object list | units, objects | ~0.2 | no | Per-module outputs: one record per module. |
| 20 | Static link: 3,841 objects, 90 MB output (130 MB Debug), 4.6M relocations | objects, bytes | 0.25 quiet | **yes** for a static executable | Unavoidable for a static binary. It can leave the edit loop (dynamic development link, §7), and it shrinks with 23. |
| 21 | `--gc-sections` | relocations | 51 ms of the link (`markLive`) | no | Not needed in development builds. |
| 22 | Sidecar: 8.4 MB of per-function records | functions | ~0.03 | no | Only `link_identity` is read back. |
| 23 | Executable size: `.data.rel.ro` 51.8 MB of position tables (32 bytes and 2 absolute relocations per bytecode instruction, 1.59M instructions); `.text` 33 MB (1.77 KB per 11-line function; 78 MB in Debug); `mylang_frame_map` 5.3 MB | instructions | link bytes and relocations | no | A compact delta encoding is 5.1 MB, with no per-instruction relocation (`meta_size.py`). |
| 24 | Export roots, schema and the test library wrapper (`--library` only): one C unit with an ordinal dispatch over every export (1.68 MB of C at 200k) | exports | 0.55 s `zig cc` when the test selection changes (test-loop and build-residue lanes) | no | A table-driven dispatcher compiled once, with per-module export tables. Executables skip export roots already. |
| — | GC roots | — | — | not whole-program | A shadow stack of `myl_native_root` records: no stack maps, no safepoint tables, no root registry. |
| — | Trap and frame maps | — | — | not whole-program | Per-function metadata. Frame-map entries sit in a per-batch `mylang_frame_map` section, found through `__start_`/`__stop_` and sorted on the first trap. |

The executable at 200k, default mode (`size -A`; Debug in brackets):

| Section | Bytes | Contents |
| --- | --- | --- |
| `.data.rel.ro` | 51.8 MB (51.7 MB) | per-function records plus per-pc location and message tables, 3.24M relocations |
| `.text` | 33.0 MB (78.0 MB) | guest code: 18,721 functions (step checks in Debug) |
| `mylang_frame_map` | 5.3 MB (—) | 12 bytes per call site, 0.89M relocations in the objects |
| everything else | < 1 MB | runtime, literals, descriptors |
| **total** | **90.4 MB (130.5 MB)** | |

The objects the link reads at 200k add up to 245 MB: code batches 108 MB, including
21 MB of frame-map relocations, and metadata objects 137 MB, including 79 MB of
relocations.

## 4. Module boundaries

**There is no stable compiled interface today.** The candidates each fall short:
- `interfaces.renderContracts` (`list-interfaces --contracts`) renders exported
  signatures as strings, from syntax alone. Only test discovery and provider validation
  read it.
- `semantic_key` declaration fingerprints and the CHECK-SHAPES-1 shape digests are
  validity keys, not content.
- Check summaries (`semantic_summary.zig`) hold per-function facts: effect mask,
  mutation summary, callees, touched records and their shape digest, diagnostics. They
  live in one slot per entry, not per module.
- A stood-in body is re-derived from syntax against the fresh global catalog. A
  dependency is still parsed or replayed, merged and catalogued.

**Can dependents be reused when a module's interface is unchanged?**
- For `check`: yes, per function. Contexts depend on declarations, so a body edit leaves
  callers' contexts unchanged, and 2 bodies are re-checked.
- For `build`, `run` and `test`: no. Every body is checked, and emission re-validates
  every stand-in record against the program's facts.
- In both cases the work to *establish* that nothing changed is proportional to the
  program.

**Does module-as-unit fit mylang's semantics?** The prototype (§10.3) answers it for
this program shape. `m240` was compiled with only signature stubs of `m239`. The stubs
keep the facts a caller's emission reads: the callee allocates, writes no parameter,
and cannot be inlined. The unit keys of all 46 functions of `m240` equal the
whole-program build's, and the batch objects are byte-identical. Whatever else the
whole-program frontend computes, none of it reached this module's code.

**What a module interface must contain** to make that true in general:
- **Resolved exported declarations:** signatures, `mut` positions, effect bounds and
  permissions, deprecations, and constants' values.
- **Types:** every record, class, union and enum the exported signatures reach, by
  stable name plus the CHECK-SHAPES-1 transitive shape digest. It needs the full schema,
  because callers compute layouts and field offsets.
- **Per exported function facts:** effect mask, mutation summary, return origin,
  parameter writes, may-allocate, and the pure flag. These are today's `Fact` plus
  allocation.
- **Inline bodies** of exported functions that `bytecode_inline.eligible` admits.
- **Generic templates** (syntax plus their symbolic contract), so users can instantiate
  locally.
- **The interface hash:** a digest of all of the above, and nothing else. Body edits to
  non-inlinable functions leave it unchanged. That is the early cutoff.

What it would take to make the module the unit of compilation, rather than per-function
units over a whole-program frontend:
1. A module compile that takes its own source plus its imports' interfaces. It is a
   frontend run over one module with a catalog seeded from interfaces. The prototype
   gets this from stub sources today.
2. Module-local IDs everywhere, with cross-module references by stable name. This
   already holds for symbols, descriptors and fragment keys.
3. Per-module outputs: code objects, metadata (compact), module descriptors, literals
   and instantiations (content-named, deduplicated), and the interface file.
4. A DAG scheduler with early cutoff on the interface hash.
5. Whole-program leftovers at link time only: the entry adapter, and in release builds
   the LTO roots.

## 5. Other compilation models

**Go, measured on the same tier** (`go_probe.py`, 280k Go lines, load 1.8, private
`GOCACHE`):

| Step | Wall | Packages compiled | Compile time (sum) | Link | Peak RSS |
| --- | --- | --- | --- | --- | --- |
| cold | 9.16 s | 539 (all of std) | 13.1 CPU-s | 0.18 s | 269 MB |
| no-op | 0.09 s | 0 | — | — | 35 MB |
| body edit | 0.30 s | 2 (`m240`, and `m241`, whose export data changed because Go exports inlinable bodies) | 0.034 s | **0.165 s** | 148 MB |
| interface edit | 0.32–0.34 s | 3 | 0.05 s | 0.17 s | 150 MB |

Go's edit loop is 0.03 s of compiling, 0.17 s of a whole-program static link, and
about 0.1 s of `go` command overhead: hashing inputs and planning 539 actions. The link
is Go's floor, and it grows with the program.

| Model | Unit of work | Interface | Link | 200k edit → build | 1M | Fits mylang? |
| --- | --- | --- | --- | --- | --- | --- |
| **Today** (whole-program frontend, per-function caches) | program (work); function (cache) | none | static `ld.lld` | 1.62 s quiet | does not build without patches; patched, 500k measured 5.6 s (8.9 s while the cache thrashes) and 1M ~10–12 s (§9) | — |
| **Rust** (query DAG within a crate, codegen units) | query / CGU; the crate for everything else | crate metadata | static | Rust itself: 2.76 s on this tier | per-crate bookkeeping grows with the crate | This is what mylang already is: fine-grained reuse, whole-unit bookkeeping. Rust users scale by splitting crates, which is Go's model. |
| **Go** (package unit, export data, parallel package compiles, fast static link) | module | interface file + hash | static | module compile 0.08–0.12 s (prototype) + link 0.19–0.25 s ≈ **0.3–0.4 s** | ~0.2 s + static link ~1.3 s (0.75–1.0 s with compact tables) | **Yes.** Imports are a DAG; effects, mutation and allocation are per-function facts; every symbol is content-named; no stack maps. |
| **Go + dynamic development link** | module | same | one `.so` per module (or a stable `.so` plus a hot one), thin executable; static for release | 0.08–0.12 s + **0.005 s** ≈ **0.1 s** | ≈ 0.15–0.2 s | **Yes.** Worked unmodified with `-Bsymbolic` (§10.4). Costs start-up time (38–109 ms at 200k, mostly position-table relocations). |
| **Zig** (lazy whole-program analysis, in-place patching of the output binary) | declaration | none (whole-program) | patch in place | bounded below by the 5 ms `.so` relink plus frontend work | — | It needs mylang to own its linker and binary layout. The dynamic development link gets the same O(edit) link with the system linker. Zig's own non-incremental build is 2.31 s at 200k. |
| **OCaml / C** (separate compilation, `.cmi`/headers, thin static link) | module | `.cmi` | static | as Go | as Go | Yes. It is Go's model without Go's linker speed. |

**Semantic fit, one concern at a time.**
- **Effects and capabilities.** Transitive, but imports are acyclic. Each module needs
  its imports' exported effect masks, which summaries already store. The capability
  check on `main` reads its callees' masks.
- **Summaries.** They become the interface's fact section.
- **GC.** A shadow stack, with no stack maps or safepoint tables, so there is no
  whole-program root table. The one whole-program GC-adjacent fact is may-allocate,
  which goes in the interface.
- **Frame maps and trap traces.** Per-function records, and per-batch sections found
  by the linker. Only the LTO roots array lists every function.
- **Descriptors, literals, host bridges.** Content-named already; they move from the
  shared C unit into modules.
- **Generics.** Instantiate at use, deduplicated by symbol.
- **Inlining.** Cross-module only for eligible leaves, whose bodies are exported.

## 6. Parallelism

**The frontend is single-threaded**, and in a cold build **emission is 84% of it**:
12.9 of 15.4 s at 200k, 3.7 of 4.5 s at 50k, about 0.7 ms per function at both sizes.

Emission is already per function: each unit has a scratch arena reset after it, and its
own fragment key. The profile of the cold 200k frontend (`perf`, flat) shows:
- `qbe.Emitter.lower` 24%;
- `mem.findScalarPos` 12%: text rewriting passes over each function's 16.6 KB of IL
  (positions, roots, slots, labels);
- `memcpy` 5.6%;
- `loweredAllocates` 4.3%;
- the rest spread thinly.

It is embarrassingly parallel per function except for shared tables: the fragment store,
the analysis caches and the record table.

**Per-module parallel frontend, measured** (`module_compile.py all --frontend-only`).
Each of the 480 modules ran as its own `emit-project-qbe` over its own source plus a
stub of its import:

| Configuration | Wall | Sum of process walls | Largest process | Load |
| --- | --- | --- | --- | --- |
| whole program, 1 process (today) | 15.4 s | — | 1,980 MB | 2–4 |
| 480 module processes, 12 at a time | 5.6 s | 66 s | 13.4 MB | 11–12 |
| 480 module processes, 20 at a time | **2.7 s** | 53 s | 13.6 MB | 12–13 |

Each process also emits its stub's 38 functions and a `main`, so about half of that
work is prototype overhead.

**Cold build on 20 threads, projected.** The module frontends take ≤ 2.7 s. Codegen is
110–119 CPU-s at 200k (user + system, measured on a cold driver run), about 6–9 s over
12–20 threads. It can start per module as soon as that module is emitted, so the two
overlap. Adding a 0.25 s link gives **about 8–10 s**, against 21.8 s today. Codegen volume is the floor: 16.6 KB of IL and 1.77 KB of machine
code per 11-line function.

**Interface edit on 20 threads.** The edited module recompiles; each direct dependent
re-checks (about 15–20 ms each, in parallel) and usually hits the object cache, because
its IL did not change. On this tier that is two module compiles. In a real codebase, an
edit to a widely imported module's interface fans out across the pool.

## 7. Linking

`lld --time-trace` of the 200k link (load 2.2, 256 ms wall):

| lld phase | ms |
| --- | --- |
| scan relocations | 67 |
| markLive (`--gc-sections`) | 51 |
| load input files | 33 |
| write output + sections | 48 |
| parse input files | 22 |
| everything else | < 15 |

Link variants, same objects, fastest of 3 (`linkbench.py`, load 1.8–3.3):

| Variant | Link | Output | Runs correctly |
| --- | --- | --- | --- |
| as built (12 threads) | 0.254 s | 90.4 MB | yes |
| without `--gc-sections` | 0.202 s | 90.9 MB | — |
| `--threads=1` | 0.404 s | 90.4 MB | — |
| without the metadata objects (upper bound for compact tables) | 0.193 s | 40.4 MB | no (tables missing) |
| **prelinked**: `ld -r` of every other module once (0.31 s, 216 MB), then that plus the edited module | **0.361 s** | 90.4 MB | yes, prints the same answer |
| **dynamic, two libraries**: `librest.so` (0.59 s once, 175 MB), `libmod.so` with the edited module | **0.005 s per edit**; executable 0.025 s once | 0.39 MB | yes; start-up 38 ms against 9 ms static |
| **dynamic, one `.so` per module** (481 libraries, 2.5 s serial once) | **0.005 s per edit** | — | yes; start-up 109 ms |

**Findings**
- **Prelinking with `ld -r` makes the link slower,** 0.36 s against 0.25 s. The cost is
  proportional to sections, relocations and output bytes, not to the number of input
  files. Fewer inputs is not a lever.
- **The position tables are the relocation load.** Of 4.6M relocations, 3.28M are in the
  metadata objects. Dropping them saves 60 ms of link at 200k and halves the output.
- **A dynamic development link removes the link from the edit loop.** It worked without
  code changes. `-Bsymbolic` is needed because QBE code refers to its own `_meta` with
  PC-relative relocations. The executable keeps the runtime (`--whole-archive`,
  `--export-dynamic`), and body edits never relink it. The price is start-up:
  - `LD_DEBUG=statistics` shows 3.24M relative relocations, all from the position
    tables;
  - the loader itself spends 28M cycles;
  - the rest of the 100 ms is mapping 481 objects and touching 26 MB of pages.
  With compact tables, start-up should fall to roughly the cost of mapping the
  libraries. That is an estimate, not a measurement.
- **The static link stays for release and `--release`, and it scales with the
  program.**
  - 200k: 0.25 s at load 2, and 0.53–0.76 s at load 8.
  - 1M: 2.8–3.2 s at load 8, for a 452 MB output from 19,007 objects (§9).
  - It is linear in the program and very sensitive to load, because every phase is
    parallel. At 500k inside `build`, it varied from 0.9 to 4.6 s between identical
    samples.
  - In-place patching (Zig's approach) would bound it by the edit too, but only if
    mylang owned its linker. The dynamic link reaches the same bound without that.
- **Test runs.** Each test is its own process, 1.7 ms now. A per-module `.so` layout
  would add the start-up above to every test process. The test runner should keep one
  prelinked `tests.so` per selection, or become a fork server that loads the libraries
  once.

## 8. Memory

Cold 200k frontend, RSS sampled every 20 ms against the phase timings
(`rss_timeline.py`, load 2–4). Nothing is freed until exit:

| Phase | RSS at end | Added |
| --- | --- | --- |
| process start | 25 MB | |
| parse 481 modules (tokens, per-module ASTs, symbol tables) | 521 MB | **+496 MB** for 6.9 MB of source |
| merge (deep copy of every AST) | 698 MB | +177 MB |
| dependency keys | 825 MB | +127 MB |
| body check (1.63M typed nodes, about 128 B each) | 1,159 MB | +334 MB |
| effect / origin passes | 1,235 MB | +76 MB |
| bytecode lowering (1.59M instructions, about 112 B each, kept before and after inlining) | 1,680 MB | **+440 MB** |
| native emission, runtime data, manifest | 1,980 MB peak | +300 MB |

That is **285 bytes of memory per byte of source**, all held to the end.
- Every phase's output stays live after the next phase consumes it: tokens after
  parsing, per-module ASTs after the merge, the pre-inline bytecode after inlining.
- After an edit, the frontend holds 949 MB at 200k (137 bytes per source byte). The
  build's other big process is the driver, whose dynamic JSON tree takes 577 MB.
- The cold link is `ld.lld` at 558 MB, and the cold driver about 435 MB.

**Projection to 1M lines** (35.1 MB of source, 5.06× the 200k tier). 500k measured
2.47× the 200k memory for 2.51× the source, so the growth is linear:

| Process | 200k | 500k measured | 1M projected | 1M measured |
| --- | --- | --- | --- | --- |
| cold frontend | 1.98 GB | 4.80 GB | ~10 GB | fails: `OutOfMemory` at 4.2 GB resident under the 8 GiB address-space ceiling, and at 8.6 GB under 14 GiB |
| frontend after an edit | 0.95 GB | 2.31 GB (3.5 GB while the cache thrashes, §9) | ~4.8 GB | 4.68 GB |
| `check` after an edit | 0.46 GB | 1.12 GB | ~2.3 GB | 2.31 GB (6.3 GB for the first, full check) |
| driver after an edit | 0.58 GB | 1.37 GB | ~2.9 GB | — (link failed, §9) |
| `ld.lld` | 0.56 GB | — | ~2.8 GB | — |

In the module model the largest compiler process holds one module plus its imports'
interfaces: 14 MB for the frontend and 49–75 MB for a whole build in the prototype. The
static linker (0.56 GB at 200k) becomes the largest process. 20 module processes at once
stay under 1.5 GB in total.

Freeing each phase's input after use would lower today's peak, but not its growth. That
is the other agent's memory work, and this audit does not change it.

## 9. Scale beyond 200k

**500k (1,200 modules, 17.4 MB, 46,801 functions) and 1M: seven limits, most of them
reached before memory runs out.**

| Limit | Where | Trips at, on this shape | Configurable? |
| --- | --- | --- | --- |
| `E_PROJECT_BYTES`: 16 MiB of total source | `project.Options.max_total_bytes` | ~470k lines | yes, `mylang.json` `budgets.max_total_bytes` |
| **`E_GENERIC_LIMIT`: "nominal layout expansion exceeds 100000 checking operations"** | `nominal_layouts.Graph.charge`: one graph for the whole program, charged once per type expression | **~240k lines** (it failed at `m581` of 1,200) | **no** |
| **Frontend cache budget: 128 MiB** | `frontend_cache.default_max_bytes` | ~440k lines. At 200k the cache holds 58 MB (8.4 bytes per source byte); at 500k it needs 134 MB, so every run evicts all 1,203 entries it stored (`evicted: 1203`) | no |
| **`mylang test` snapshot: 16 MiB** | `native_test_snapshot.byte_limit` | ~470k lines: `host failure: InvalidTestSnapshot` | no; `mylang.json` does not apply |
| **A second program-wide `E_GENERIC_LIMIT`**: "nominal type expressions exceed checking depth/work budget", 100,000 operations | `nominal_templates.Index.expression` | ~480k lines (`m1147` of the 1M tier) | no |
| **Compiler address space: 8 GiB** (`MYLANG_HOST_MEMORY_LIMIT`) | `memory_budget.guardHost` | between 500k (4.8 GB resident) and 1M, where it fails during dependency keys | yes, by environment; 14 GiB is not enough for a cold 1M build either |
| **Link command line** | the first link of a shape runs `zig cc -###` with every object path | between 500k (2.35 MB of arguments) and 1M (4.66 MB): `execve` returns `E2BIG`, reported as `host failure: Unexpected` | no; needs a response file |

`E_GENERIC_LIMIT` means a real project somewhat larger than the 200k tier cannot compile
at all today. The limit is a per-declaration safeguard applied to the whole program.

To measure beyond the limits, three prototype compilers were built from uncommitted
patches (`patches/prototype-compiler*.patch`):
- **proto** raises the nominal-layout budget and adds the frame-map-roots change (§10.1);
- **proto2** additionally raises the frontend cache budget to 1 GiB and the test
  snapshot limit to 256 MiB;
- **proto3** additionally raises the nominal-templates budget.

The patches are `patches/prototype-compiler.patch` (proto) and
`patches/prototype-compiler-scale.patch` (proto3; proto2 is the same without the
`nominal_templates.zig` hunk). The prototype binaries were taken from `.zig-cache`,
because Guardian's change classification refuses the install step for an untested
behavioural change.

**500k with proto:** the byte budget is raised in `mylang.json`, and the frontend cache
still thrashes. Fastest of 2 samples, load 7–17:

| Step | 500k | 200k (same session) | ratio | size ratio |
| --- | --- | --- | --- | --- |
| cold build | 99 s (frontend 30 s, codegen 67 s, link 1.1 s), 4.80 GB | 27.8–37 s, 1.94 GB | 2.7–3.6× | 2.5× |
| no-op build (with `--report`) | 1.70 s | 0.57 s | 3.0× | |
| edit → build | 8.9 s, 3.5 GB | 1.88 s | **4.7×** | |
| interface → build | 8.5 s | 2.12 s | 4.0× | |
| edit → check | 5.4 s (46,802 bodies, 0 reused), 3.1 GB | 0.51 s | **10.5×** | |
| edit → test | fails (`InvalidTestSnapshot`) | 1.30 s (reference) | — | |
| executable | 226 MB (`.data.rel.ro` 129 MB) | 90 MB | 2.5× | |

The edit rows grow faster than the project because the frontend cache thrashes.
- Syntax is re-parsed: 2.0 s, where 200k replays it in 0.11 s.
- Summaries are gone, so the passes walk everything (0.9–1.2 s against 0.011 s) and
  every body is re-checked.
- The driver takes 3.5–4.7 s and 1.37 GB, and the link 0.9–4.3 s, both at load 8–17.

**500k with proto2 (no thrashing).** Fastest of 2 samples, load 6–18; the second
sample of each edit row was up to 2× slower:

| Step | 500k | 200k | ratio (size 2.5×) |
| --- | --- | --- | --- |
| cold build | 89 s, 4.80 GB | 27.8–37 s, 1.94 GB | 2.4–3.2× |
| no-op build (with `--report`) | 1.47 s | 0.57 s | 2.6× |
| edit → build | 5.6 s, 2.40 GB | 1.88 s, 0.98 GB | 3.0× |
| &nbsp;&nbsp;frontend: replay 0.30–0.46, merge 0.22, keys 0.26–0.29, body check 1.10–1.20, emission 0.42–0.83 | 3.3–3.7 s, 2.31 GB | 1.17–1.23 s | 2.8× |
| &nbsp;&nbsp;driver: bookkeeping 0.48–1.84 s, link 0.93–4.6 s | 3.3–5.8 s, 1.37 GB | 0.65–0.72 s | 5–8× |
| interface → build | 5.1 s | 2.12 s | 2.4× |
| edit → check (4 bodies re-checked) | 1.55 s, 1.12 GB | 0.51 s, 0.46 GB | 3.0× |
| cold `test` | 13.0 s, 3.95 GB | — | |
| no-op `test` | 7.0 s | 0.19 s (reference) | |
| edit → `test` | 4.8–6.1 s, 2.78 GB | 1.30 s (reference) | 3.7–4.7× |

- The frontend and `check` grow a little faster than the project.
- The driver's link varies by 5× between identical samples: 0.93 to 4.6 s. It writes a
  226 MB executable and a 21 MB sidecar on every edit, and on a shared disk that runs
  into write-back throttling.
- 177 of the 1,200 tests fail with `R_FRAME_LIMIT`. That comes from the generated
  project's shape, not from compilation: the test of module *k* recurses *k* modules
  deep, and tests run under a 1,024-frame ceiling.

**1M (2,400 modules, 35.1 MB, 93,601 functions).**
- With proto2, the check fails with a second program-wide budget:
  `E_GENERIC_LIMIT: nominal type expressions exceed checking depth/work budget`
  (`nominal_templates.Index.expression`, 100,000 operations, tripped at `m1147`,
  ~480k lines).
- **proto3** also raises that budget. Its cold frontend then fails at the default
  ceiling: `host failure: OutOfMemory` after 7.4 s, during dependency-key preparation.
  It had 4.24 GB resident (the address-space limit is what trips) and had not yet
  checked a body. The phases by then were load 0.40 s, parse 4.46 s, merge 0.49 s and
  keys 1.42 s.
- With the ceiling raised to 14 GiB (`MYLANG_HOST_MEMORY_LIMIT=14G`, inside a 16 GB
  cgroup), the cold build still fails with `OutOfMemory`, after 20.3 s at 8.6 GB
  resident.
- A retry got further: 158 s, 595 CPU-s, 7.3 GB. Its frontend then succeeds from the
  partly filled caches, but **the link fails: `host failure: Unexpected`**. `strace`
  shows `execve` returning `E2BIG`. The first link of a shape runs
  `zig cc -### … <19,007 object paths>`, which is 4.66 MB of arguments, over the kernel's
  argument limit. The captured 500k link command is already 2.35 MB.

Past these failures, what could be measured at 1M (load 7–9):

| Step | 1M | vs 200k |
| --- | --- | --- |
| edit → check (2 bodies re-checked, warm) | 4.8–5.3 s, 2.31 GB | 9–10× for 5× the source |
| &nbsp;&nbsp;load 0.58, replay 0.84, merge 0.75, keys 1.01, summary store 0.44 | | |
| first check after builds (every body) | 11.7 s, 6.3 GB | |
| edit → frontend child (`emit-project-qbe`) | 6.7 s, 4.68 GB (body check 2.25, emission 0.96, keys 0.58, replay 0.61) | 5.4× |
| static link of the whole program, through a response file (`rebuild_link.py`) | 2.8–3.2 s at load 8 (scan relocations 1.27 s, markLive 0.51 s, write 0.51 s); 452 MB executable, 19,007 objects; it runs and prints the right answer | 5.3× the 200k link at the same load |
| cold build | not reached | |

- **At 1M, the current model's edit → build would be about 10–12 s.** That is the
  frontend plus about 2 s of driver bookkeeping plus the link, if the link argument
  limit is fixed.
- **Edit → check is about 5 s,** so the check alone is 5× the 1 s build target.

## 10. Prototypes

Each prototype has a before and after number and a note on correctness risk. None is
committed; the patches and scripts are in `experiments/compilation-model-20260924/`.

### 10.1 Frame-map roots only under LTO (the interface-edit tax)

- **Change:** `sharedMetadata` emits the `extern` list and the
  `mylang_frame_map_functions[]` array only when the build uses LTO, 7 lines.
- **Why it is the unexplained cost:** in default mode (the frame-map protocol), adding or
  removing any function changes the shared C unit's text. The unit is 3 MB of object
  and carries every descriptor too, so `zig cc` recompiles it on the critical path:
  0.26 s at load 5. Debug builds use the frame-record protocol and never emit the array,
  which is why they did not show the cost.
- **A/B at 200k** (`ab_iface.py`, 4 rounds interleaved, load 7–9):

  | Build | Codegen phase | Shared unit recompiled |
  | --- | --- | --- |
  | baseline, interface edit | 0.31–0.50 s | yes (`metadata_reused: false` in 4/4) |
  | proto, interface edit | 0.18–0.22 s | no (`metadata_reused: true` in 4/4) |
  | both, body edit | 0.17–0.28 s | no |

  Both final programs print the same result (69899). End-to-end walls were dominated by
  link noise at this load (0.36–1.49 s per link), so the deterministic counter and the
  codegen phase are the evidence.
- **Correctness:** the 200k executables of both compilers have identical section sizes
  (`.data.rel.ro` 51,772,104 bytes in each), so no metadata was dropped. On a two-module
  program that divides by zero, both default-mode builds print byte-identical trap
  traces, naming `helper::divide` and `main::main`.
- **Risk:** low. The frame-map section references each `_meta`, so `--gc-sections` keeps
  it. The LTO path keeps the array. The change still needs a ReleaseFast trap-trace
  ratchet in the gate.

### 10.2 Link variants and compact position tables

See §7 for the variants.
- **Compact tables:** 1.59M positions at 200k. Today they take 51.8 MB and 3.24M
  relocations. As zig-zag LEB128 deltas they take 5.08 MB: 10.2× smaller, with one
  reference per function (`meta_size.py`).
- **Link bound:** −60 ms at 200k (0.254 → 0.193 s) and −50 MB of output.
- **Risk:** medium. The runtime decodes a function's positions at trap time rather than
  indexing a table. Trap traces are covered by the QBE trap-trace tests and the Lox
  corpus.

### 10.3 One module as one unit, against stub interfaces

- **Setup:** `module_compile.py stub|one|all`. The stub of an import keeps its records
  and public signatures. Each body becomes a four-line allocating loop, so the callee
  facts match: allocates, no parameter writes, not inlinable.
- **Result, `m240` at 200k:** 46/46 unit keys are identical to the whole-program
  build's. The 5 batch and metadata objects of `m240` are the same files, and `cmp`
  confirms the bytes.
- **Timings:**

  | Step | Wall | Frontend | Codegen | Stub-project link | Peak RSS |
  | --- | --- | --- | --- | --- | --- |
  | cold compile of the stub project | 0.26–0.30 s | 0.08 s | 0.13–0.16 s | 0.04 s | 74 MB |
  | body edit (5 samples, load 10) | **0.08–0.12 s** | 0.012–0.019 s | 0.047–0.075 s | 0.012–0.020 s | 49 MB |

  None of these depends on the project's size. The whole-program build spends 1.2 s in
  the frontend alone for the same edit.
- **Interleaved at 200k** (`ab_module.py`, 6 rounds, the same constant written into
  `m240` in both trees, no `--report`, load 9): the whole-program `build` took 2.68 s
  minimum and 2.89 s median, at 949 MB. The module build took **0.080 s** minimum and
  0.121 s median, at 48 MB. The module build still links its small stub executable;
  the per-module model adds the 5 ms `.so` relink or the static link instead.
- **Risk:** this is the model's central assumption: the interface carries every fact a
  dependent's code reads.
  - Here, a wrong stub fact (a stub that does not allocate) would silently change
    root-protection code. The key comparison is what catches that, which is why it
    belongs in the gate (§12).
  - The ladder exercises no generics, cross-module inlining or function values.
    Before relying on the result, the Lox port and `tests/lang` should be run through
    the same comparison.

### 10.4 Dynamic development link

See §7.
- **Result:** the edited module's `.so` relinks in 5 ms, the executable is not relinked,
  and output is identical to the static build.
- **Risk:** medium.
  - Symbol interposition is off (`-Bsymbolic`).
  - `dlopen`-time failures under `-z now` would surface only at start-up.
  - Start-up costs 29–100 ms more at 200k until the tables are compact.
  - The test runner needs its own arrangement so it does not pay start-up per test.

### 10.5 Parallel per-module frontend

See §6: 2.7 s on 20 threads against 15.4 s. **Risk:** none beyond 10.3. It is the same
separate compile, run concurrently.

## 11. Ranked implementation plan

The items are ranked by their value toward the targets. The order to build them in is
given after the table. *Effect* figures are projections from the measurements above.

| Rank | Item | 200k edit → build | 1M edit → build | 200k cold | Peak memory | Effort | Risk |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | **Module as the unit of compilation**: interface artifact and hash, per-module check/lower/emit/objects, DAG scheduler with early cutoff, per-module descriptors, literals and instantiations | 1.6 → ~0.35 s (static link) | ~10–12 s → ~1.4 s (static link ~1.3 s) | 21.8 → ~9 s (with 5) | 1.9 GB → largest compiler process < 100 MB; linker 0.56 GB | L (4–6 weeks) | high: interface completeness |
| 2 | **Dynamic development link**: one `.so` per module (or stable + hot), thin executable, static for `--release` and when asked | ~0.35 → **~0.1 s** | ~1.2 → **~0.15 s** | +0.5 s once | none | M (1–2 weeks) | medium: start-up, test runner |
| 3 | **Compact, pointer-free position tables** | −0.06 s link | −0.3 s link | −1–2 s (137 MB of metadata objects shrink about 10×) | executable 90 → 43 MB | M (1 week) | medium: trap-trace fidelity |
| 4 | **Lift the scale limits**: per-declaration `E_GENERIC_LIMIT` (both budgets); frontend cache budget scaled to the project; test snapshot bound by `mylang.json` budgets; a larger default byte budget; link inputs through a response file | 500k: 8.9 → 5.6 s (measured, proto2) | makes 1M buildable at all (with a response file for the link) | — | — | S (days) | low |
| 5 | **Frame-map roots only under LTO** | interface edit −0.26 s (load 5) to −0.65 s (reference) | same, growing with the program | — | — | S (hours) | low |
| 6 | **Parallel per-function emission** (interim cold win, subsumed by 1) | — | — | 21.8 → ~12 s (emission 12.9 s ÷ 12) | — | M | medium: deterministic output order |
| 7 | **Driver on module records**: binary or in-process manifest, no per-function sidecar | −0.2–0.4 s now; part of 1 | part of 1 | — | driver 0.58 GB → small | M | low |

**Order to build them:** 5 and 4 (days, independent) → 3 → 1 in stages
(1a interface artifact + hash, emitted and diffed against today's summaries;
1b per-module compile behind a flag, checked against whole-program keys;
1c scheduler and per-module outputs; 1d `check` and `test` on the same artifacts)
→ 2 → 7 folded into 1c. Item 6 only if cold time is needed before 1 lands.

**Acceptance rules** (deterministic counters, as the build-loop lanes use; wall clock
only for the scale ladder):

| Item | Acceptance |
| --- | --- |
| 1 | After a body edit in module *k*: modules compiled = 1, bodies checked = the module's own, driver records touched = that module's objects. An interface edit compiles *k* and re-checks only *k*'s direct importers; an importer whose IL is unchanged compiles no object. The per-module build's unit keys equal a whole-program build's for every function of `tests/lang`, the Lox port and all four tiers. Ladder: 200k edit → build ≤ 0.5 s with a static link; 200k cold ≤ 10 s; largest compiler process ≤ 1 GB at 200k. |
| 2 | A body edit relinks exactly one shared object and not the executable. Dynamic and static builds give identical stdout, stderr, exit status and trap traces on the Lox corpus (254 scripts × 2 engines) and `tests/lang`. Ladder: 1M edit → build ≤ 1 s. |
| 3 | Position-table bytes per instruction ≤ 4, relocations per function O(1) (asserted from the object's relocation count). Trap traces are byte-identical to today's on the trap-trace tests. |
| 4 | 500k and 1M tiers check and build with no `mylang.json` budgets. The adversarial generic and nominal fixtures still report their limits per declaration. `evicted` = 0 on an unchanged 500k rerun. |
| 5 | Adding a function in default mode leaves the shared metadata object key unchanged (`metadata_reused: true`). A ReleaseFast trap test still names the frame. The LTO build still keeps every `_meta`. |
| 6 | Emission output (manifest bytes) identical with 1 and N threads. Cold 200k frontend ≤ 4 s on 12 threads. |
| 7 | The driver's work after a body edit is O(changed modules): records parsed and objects `stat`ed ≤ the edited module's. |

**Can the targets be met?**
- **200k edit → build ≤ 0.5 s:** yes with item 1, even with a static link (~0.35 s).
  Not in the current model, whose floor is about 0.5 s of whole-project reading plus
  the link.
- **1M edit → build ≤ 1 s:** only with item 2, or an in-place patching linker.
  A static link of a 1M-line program is ~1.3 s by itself on a quiet machine, and
  0.75–1.0 s with item 3 and no `--gc-sections`, before any compiling.
- **200k cold ≤ 10 s:** borderline. It needs items 1 and 6-style parallelism, and
  codegen at 110–119 CPU-s sets a floor of about 6 s on 20 threads. Beating it with room
  needs less IL per function: 16.6 KB of IL for an 11-line function is codegen work,
  not compilation-model work.
- **200k peak ≤ 1 GB:** yes with item 1, where the largest process is the linker at
  0.56 GB. In the current model the cold frontend alone is 1.98 GB.

## 12. Correctness strategy: incremental must equal clean

1. **Separate compilation equals whole-program compilation.** Keep the whole-program
   path as an oracle while item 1 lands.
   - For every function, the per-module build's unit key must equal the whole-program
     build's, as §10.3 checks.
   - Run it on `tests/lang`, the Lox port and the tiers.
   - Run it again after every mutation of the check harness's set: rename or retype a
     field, rename a case or def, add a parameter, drop `mut`, un-public, add a
     function, reorder record fields, change a literal.
   - This is stronger than comparing program output, because it catches wrong
     root-protection or effect facts that happen not to change what a test prints.
2. **Interface-hash soundness.** Extend `tests/incremental_diff.py`
   (`zig build test-incremental`) and `experiments/build-loop-20260924/build_diff.py`
   to the per-module path.
   - After each mutation, an incremental per-module build must give the same diagnostics
     and unit keys as a clean one.
   - A mutation that changes only a body must not change the interface hash (early
     cutoff is exercised). A mutation that changes a signature, shape, fact or inline
     body must change it.
   - The false-clean bug of 24 September (a record reached only through `list[Inner]`)
     is the model case: the interface must include transitive shape digests, and the
     harness must mutate through composite types.
3. **Dynamic equals static.** Build both from the same objects and compare stdout,
   stderr, exit status and trap traces on the Lox corpus and `tests/lang`.
4. **Counters as ratchets.** Modules compiled, bodies checked, objects compiled and
   shared objects relinked per edit, each asserted in a CLI test. Wall-clock thresholds
   never go in tests.
5. **Scale tiers in CI, occasionally.** A 500k check-and-build smoke test so that no new
   program-wide budget reappears unnoticed.

## 13. What surprised me

- **The cold frontend is mostly QBE text emission**: 12.9 of 15.4 s at 200k,
  0.7 ms per function. The checker is 0.46 s. Each 11-line function becomes 16.6 KB of
  IL, and the text post-passes scan it repeatedly (`findScalarPos` 12%).
- **The separately compiled module's objects were byte-identical** to the whole-program
  build's on the first try. The whole-program frontend is incidental for code
  generation, at least on this shape.
- **Prelinking made the link slower,** and the number of inputs does not matter.
  Relocations and output bytes do, and 70% of the relocations are position-table
  pointers.
- **The first wall beyond 200k is a program-wide type-expression budget,** not memory.
  Next come a cache budget that silently turns every edit into a cold check, and a test
  snapshot cap that ignores `mylang.json`.
- **The unexplained default-mode interface cost** is a 3 MB C file recompiled because an
  LTO-only array lists every function.
- **Go spends more than half its edit loop in its linker** (0.165 of 0.30 s). Its lead
  is not compile speed; it is that nothing else in its loop is whole-program.

## Reproduction

```bash
python3 experiments/build-loop-20260924/gen_scale.py t200k 480 38
M=/path/to/mylang
python3 experiments/compilation-model-20260924/probe.py t200k --mylang $M --samples 3 > probe.jsonl
python3 experiments/compilation-model-20260924/summarize.py probe.jsonl --min --phases
# one module against stub interfaces, compared with the whole-program build's keys
python3 experiments/compilation-model-20260924/module_compile.py one work-t200k-probe/src m240 mc/m240 \
    --mylang $M --sidecar work-t200k-probe/bin/big.qbe-manifest.json --edits 5
python3 experiments/compilation-model-20260924/module_compile.py all t200k/mylang mcall --mylang $M --jobs 20 --frontend-only
# link variants and the dynamic development link (after an edit build)
python3 experiments/compilation-model-20260924/capture_link.py link.json -- $M build main.my --project -o bin/big --cache-dir=cache
python3 experiments/compilation-model-20260924/linkbench.py link.json lb --module m240 --expect "$(bin/big)" --variants base,nogc,t1,nometa,prelink,dynamic,permodule
python3 experiments/compilation-model-20260924/go_probe.py t200k go200
```
