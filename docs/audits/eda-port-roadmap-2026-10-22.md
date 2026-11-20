# EDA port roadmap: what Selka needs before the Zig EDA moves (plan, 2026-10-22)

Status: **accepted 22 October.** The user accepted all six recommendations of §7 and started phase 1 (§5): kernel K2
then K1, C2/C6/C7 and the F1 scale probe, beside the borrowed-returns R3a/R2 lane. R3a/R2 and lane C (C2, C2b, C7, C6) landed the same day (main `007e6e92d`); the user then started
R3b + R4 early, before phase 1's gate, and set C5 aside (§4.C). Later on 22 October the user added stream H,
self-hosting (§4.I). It starts after G2's language freeze, staged per the 19 October self-hosting plan.

The user's goal (22 October): *port the real, full Zig EDA project into Selka.* The requirements, in their words: fix
the borrow checker, have multithreading, and keep performance similar to Zig on the hot path while doing simulation
or the autorouter.

This plan turns that goal into seven work streams with numeric gates, plus an eighth, self-hosting, that follows
the port's freeze. It reuses the plans already accepted:
- borrowed returns (`docs/audits/borrowed-returns-plan-2026-10-20.md`);
- concurrency plan 2 (`docs/audits/concurrency-plan-2-2026-10-09.md`);
- incremental self-hosting, stage 1 (`docs/audits/selfhost-plan-2026-10-19.md`);
- the eda-bench stages (`~/ai/canopy/eda-bench/STAGES.md`);
- the performance-feedback plan (`docs/audits/performance-feedback-plan-2026-10-20.md`).

It adds the parts those plans leave out.

## 0. Summary

| Stream | What it delivers | Est. agent hours | Starts |
| --- | --- | --- | --- |
| A. Borrowed results | functions return borrows; stdlib accessors stop copying (R2–R5, then R6/R7) | 35–55 | running (R3a/R2) |
| B. EDA kernels as the performance gate | the router search, the thermal solve and the DRC sweep ported from netlisp, Zig as oracle, an instruction gate | 25–40 | now, beside A |
| C. In-place mutation and ownership gaps | `match mut`, the element-exchange idiom, per-field borrows, borrows in records, and a fixer that stops teaching copies | 35–60 | after A's R4 |
| D. Allocation on hot paths | allocator size classes, capacity reuse, then (if still needed) scoped regions | 15–35 | after B's first profiles |
| E. Multithreading | concurrency plan 2 rebased (P1F fixes, zero-tax mode), its P2 surface (`parallel.map`, task groups), parallel kernels | 60–90 | after A's R4, or beside C |
| F. Scale | a 100k and 400k-line probe; fix what grows faster than linear (the release whole-program unit first) | 15–40 | beside B |
| G. Staged port | eda-bench stage 2 (99k Zig lines), then the full netlisp (669k Zig lines, about 400k in Selka) | 200–350 | G2 after A, B, C; G3 after E, F |
| H. Self-hosting | the compiler moves into Selka stage by stage (lexer and parser first). The Zig compiler is the oracle and stays the shipping compiler until each stage passes its gates. | stage 1: 60–100; later stages sized from stage 1 | after G2's freeze, beside G3 |

**Total before the full port starts (A–F plus G2): about 230–370 agent hours.** The full port (G3) itself is a further
150–300. These estimates assume the current working mode: Haiku lanes, Claude reviewing and gating, one to three
lanes at a time. Stream H is outside both totals: it is not a prerequisite of the port, and it starts only once
G2 has frozen the language.

## 1. Where Selka stands (measured 21–22 October; `experiments/language-wave2-20261019/perf-rebaseline/`)

**Speed against Zig ReleaseFast** (lower is faster):

| Program | Selka | Rust | Go |
| --- | --- | --- | --- |
| parity kernels (13) | 0.84 | 1.03 | - |
| Lox bytecode VM | 3.52 | 1.46 | 1.46 |
| EDA port (eda-bench stage 1), wall | 0.96 | 0.65 | 1.26 |
| EDA port, instructions | 3.58 | 1.65 | 3.95 |

- Selka matches Zig on tight numeric kernels, and does 2.5–3.6x Zig's CPU work on record- and container-heavy programs.
- The EDA profile is led by the runtime: `block_alloc`, owned copies and drops. Then come accessors that copy what they
  return (`as_list`, `design_model::form`).
- **Three cliffs** came from copies on hot paths that borrow rules forced or `mylang fix` suggested:
  - the Lox frame write-back, 41x Zig;
  - the EDA tokenizer, which copied the whole source per token;
  - an HTTP helper's body copy, −20%.

**Borrow checker.**
- Landed:
  - nothing is taken or copied unless written (rules T and C);
  - `own` and `mut` parameters;
  - plain parameters take views (C9);
  - a `const` of a place borrows (R1).
- Missing:
  - borrowed results (R2–R4);
  - stdlib accessors still copy (R5);
  - in-place update of a union payload in a list element (`match mut` is not a form; Lox F5). Moving an element
    out by index works through `exchange(index, placeholder)`, which the Lox port missed;
  - borrows held in records;
  - per-field borrows (FR-350, FR-107) and "entry" accessors that return a mutable place.

**Multithreading.**
- On `main`: the task runtime (concurrency P1, 9 October) and `parallel.map` over a list. Owned arguments are free;
  a plain list parameter needs `copy(xs)`, which is CX2's trade-off.
- Stale: `codex/concurrency-2` (P1F review fixes, plus the zero-tax `single` mode, implemented but not gated) is 30
  commits ahead of an old `main` and unmerged since 10 October.
- Open review finding A1: frees on a different thread grow memory without bound.
- Not started: the P2 language surface (task groups, fallible map).

**Scale.**
- The checker's memory is now linear (lane Q).
- The 22k-line EDA port checks in 0.2 s after an edit and builds cold in 13 s.
- Nothing at 100k+ lines has been measured on the new core.
- The release build compiles the whole program as one LLVM unit (S4-1a), which will not scale to 400k lines without
  partitioning.

**The target codebase.** netlisp at `~/ai/canopy/eda` is 669k lines of Zig in 792 files under `src/`. Nearly every
root sits in one large strongly connected import component (eda-bench `STAGES.md`). Hot paths:
- **The autorouter:** `src/placement/router.zig`, `router_ctx.zig`, `router_direct.zig`, `route_cleanup.zig` and the
  `*_route.zig` family, about 83k lines. It has a whole-corpus benchmark in `src/bench_route.zig`.
- **The thermal field solver** (simulation): `src/placement/thermal_field.zig`, 5.6k lines, `solveScenario`.
- **The DRC sweep:** `src/drc_sweep.zig`, already multi-threaded with `std.Thread`. 17 files use `std.Thread`, mostly
  the server's caches and jobs.

## 2. Requirements, made measurable

| # | Requirement | Gate (all must hold before G3, the full port) |
| --- | --- | --- |
| R-1 | The borrow checker does not force copies a careful Zig port would not make | Every kernel of §4.B passes with **zero `copy(...)` on a per-element or per-iteration path**; borrowed-returns R1–R5 landed; the matrix in `experiments/borrowed-returns-20261020/matrix/` passes in every mode. (User decision, 5 November: R3b-R4.md D10 stands, so a borrowed binding assigned in both arms of an `if` is refused at the join; the matrix's `expected.md` records those ten cells as refusals and cites D10.) |
| R-2 | Zig-class speed on hot paths | Each kernel K1–K3 single-threaded: **≤ 1.25x Zig ReleaseFast wall time**, outputs byte-identical; instructions are tracked as a diagnostic, not gated (user decision, 23 October: the extra instructions are mostly the checks Selka keeps in release, and they overlap useful work). Interim gate after A and B: ≤ 1.5x |
| R-3 | Multithreading | K3, the DRC sweep, and K1 run on N threads (1, 2, 4, 8) with output byte-identical to one thread, and **Selka's wall time is within 1.25x of an equivalent Zig parallel program at the same thread count**. K1 is parallel at snapshot level, because netlisp's router places nets one after another (`router.zig:1247`). Zero-tax: a program with no task construct is unchanged to the instruction (plan 2's T). (User decision, 5 November: package T was not built, so this is met by measurement: a program with no task construct emits no task call and no atomic, and its instruction count is the same with `MYLANG_THREADS` set to 1 and to 8; `experiments/eda-roadmap-20261022/p4-recheck-20261105/gate/` row 8.) (User decision, 23 October: the earlier "speedup ≥ 0.7·N" line was not reachable at 8 threads on this 6-performance-core, 8-efficiency-core machine for Zig either.) (User decision, 5 November, closing phase 4: R-3 is judged as lane E2 measured it, with threads unpinned, where K3 is 0.67–1.07x Zig at 1 to 8 threads. Pinned to the performance cores, K3 is 1.10–1.30x and above 1.25x at 8 threads on two boards, because the program gives the pool one task per lattice row; follow-up FU-1 in §5.2.) |
| R-4 | The port stays correct | Every stage's golden corpus is byte-identical to netlisp's, as eda-bench's `equiv` checks today |
| R-5 | The edit loop survives scale | At 400k lines: check after an edit ≤ 2 s; debug build after an edit ≤ 5 s; release build ≤ 10 min with ≤ 8 GB; tests after an edit ≤ 10 s for one module |
| R-6 | The language holds still | From G2 on: no breaking change without a certain `mylang fix` migration and a version note (§4.H) |

## 3. The shape of the work

```
A borrowed results ──► C in-place mutation ──► G2 stage-2 port ──► G3 full port
       │                       ▲                     ▲                 ▲
       ▼                       │                     │                 │
B kernels (gate) ──► D allocation ───────────────────┘                 │
       │                                                               │
       └──► E concurrency (rebase, P2, parallel kernels) ──────────────┤
F scale probe ──► F fixes (release partitioning) ──────────────────────┘
```

B runs from the start, because it is the measuring stick for A, C, D and E. Each of those lands only when the kernel
numbers say it helped and nothing regressed.

H, self-hosting, hangs off G2's freeze (R-6) and runs beside G3. It needs no other stream's result, only a language
that holds still and kernels close enough to Zig that its parity gate (§4.I) is reachable.

## 4. Streams

### 4.A Borrowed results (the accepted plan, reordered)

Order as the user approved on 22 October:
1. **R3a**, the mixed-return refusal (running).
2. **R2**, borrow-set inference (running, no acceptance change).
3. **R3b and R4 together.** The checker accepts borrowed results at call sites and returns, and Core lowers them
   (never dropped; sources kept alive; the verifier). R0's spike proved that accepting them before Core is a
   use-after-free, so the two land as one batch.
   - Acceptance: every R0 spike probe either works without a copy (`direct_return`, `option_return`) or is refused
     (`mixed_return_heap`, `store_of_borrow`, `source_change_while_live`).
   - The whole matrix passes in debug, release, `--verify-facts` and the leak check.
4. **R5**, standard-library accessors (`dicts.find`, `lists.last`, `pool.get`, the json accessors): zero allocations
   per call.
5. **R6 and R7** (needless-copy repairs, copy messages), then selka-projects and the measurement (R8).

Add to the plan (from R0):
- **Constructors:** a borrowed value placed in a constructor must not be consumed. `union_make` consumes today.
- **A `match` on a borrowed temporary:** bind the temporary first, or give it a rule in R4.
- **The borrow set's representation in `ir.Signature`:** a `u64` bitset in place of `view_source`, within Guardian's
  field cap.

Exit: R-1's matrix condition; the EDA port's `as_list` / `form` callers return borrows with no rewrite; the Lox VM's
remaining forced copies (`class_obj`, `instance_fields_copy`) gone.

### 4.B Kernels from the real EDA as the performance gate

Port three hot paths from netlisp into Selka, as standalone programs under eda-bench (a `kernels/` tree, one directory
each). Each kernel has the same inputs as the Zig original, cut from the corpus. Zig is the oracle: byte-identical
output.

| Kernel | From netlisp | Input | Measures |
| --- | --- | --- | --- |
| K1 router search | the core of `placement/router.zig` / `router_ctx.zig` (grid build, candidate search, path commit); the lane cuts the slice at `bench_route.zig`'s entry | 3 boards from the routing corpus | records in grids, priority queues, in-place cell updates |
| K2 thermal solve | `placement/thermal_field.zig` `solveScenario` (grid assembly, iterative solve) | 3 scenarios from `thermal_scenarios.zig` | f64 arrays, stencil loops, reductions |
| K3 DRC sweep | `drc_sweep.zig`'s check loop | 3 saved layouts | spatial queries over geometry, and the parallel split (for E) |

- **Rules for the port.**
  - Idiomatic Selka with the R3 Lox idioms: write back a single field, read through a borrowing `match`, no
    `copy(...)` on per-element paths.
  - Every remaining copy is listed with the language reason that forces it. That list feeds C.
- **Measure.**
  - `perf stat -e instructions:u` pinned, plus wall median of 5, against Zig ReleaseFast and ReleaseSafe.
  - Run them in `scripts/build-slot.sh timing` windows, with gaps between windows: last night's back-to-back windows
    starved builds.
  - A script `kernels/run.sh` prints one table, and its JSON goes to the evidence archive.
- **Gate.** Every later landing in A, C, D and E reports the three kernels' instructions against the previous `main`.
  - A rise over 3% needs a named cause.
  - The R-2 targets decide when a stream is done.
- **Order.** K2 first (smallest, numeric, the fastest signal), then K1, then K3. K3 waits for E's surface to measure
  the parallel half.

### 4.C In-place mutation and ownership gaps

Each item lands with a guest test, a matrix row and a kernel number, the way wave 2's lanes did.

| # | Gap | Found in | Proposed form (decide per item) |
| --- | --- | --- | --- |
| C1 | update a union payload in place inside a list or dictionary element | Lox `instance_fields_copy` | `match mut xs[i]:` with payload bindings writable, or `case Kind(value=mut v)` |
| C2 | move an element out of a list by index | Lox F4 (the port missed that `pop(index)` and `exchange(index, replacement)` exist) | mostly an idiom: `exchange` the element for a cheap placeholder variant, update it, `exchange` it back. Prove it on the Lox `instance_fields_copy` site (it may remove that copy before C1 lands), document it, and teach it to `mylang fix` (C6). Add `lists.swap` only if a kernel needs it |
| C2b | `lists.exchange` and `lists.pop_at` copied the element (`copy(values[index])`) | K2 (found 22 October) | landed with lane C: `pop_at` moves; `exchange` moves its old element but still copies the replacement, which needs an `own replacement` signature (a breaking change with a `mylang fix` migration) |
| C3 | disjoint field borrows and field moves: `f(mut r.a, r.b)` is `E_SINGLE_OWNER_OVERLAP` (FR-350); a field cannot move out of a local record that is dead afterwards (FR-107); a `match` on an element keeps all of `rt` borrowed for the whole arm (Lox F3) | markdown, kicad-convert, http-server, Lox | borrows tracked per field path, and a last-use field move. Each is a checker change with matrix rows |
| C4 | an "entry" accessor: a function that returns a mutable place | router cell updates | a `mut` result with a borrow set (borrowed returns §8 "mutable borrow"); design after R4 |
| C5 | a borrow held inside a record (views in records) | 45 constructor sites in selka (R0 census), parser ASTs | a record field holding a view of a parameter, refused to escape. Largest design item; decide whether the EDA needs it after K1. **Not planned for now** (user, 22 October): netlisp has 4,931 struct fields typed `[]const u8` (461 files); they port as owned copies where cold and as spans into the source or interned ids where hot. Revisit only as "views into a region" if D3 regions happen |
| C6 | `mylang fix` suggests `copy(...)` for a read-modify-write of an element | all three cliffs | the repair writes the field store or element path; `copy` only when it is the only certain repair |
| C7 | a lint for `copy(...)` in a loop or per-element path | the cliffs | `L_COPY_IN_LOOP`, reported by `mylang lint` and `cost --sites`, waivable with a reason |
| C8 | no `f32` storage type and no SIMD vector type: Selka has only `float` (binary64) and scalar loops | netlisp's thermal solver stores `f32` streams and solves four scenarios as `@Vector(4, f64)` lanes (found 22 October while scoping K2; only 2 of netlisp's 792 files use `@Vector`) | decide after K2 reports `zig/f64` against `zig/real`, which is what `f32` storage and explicit SIMD buy. Options: an `f32` type with explicit conversions; a fixed-width lane type; or relying on LLVM's vectorizer with a layout guide. **K2 measured it (22 October):** `zig/f64` is 3.65x `zig/real` per solve in instructions, so `f32` storage plus SIMD is the largest single gap on the thermal kernel. **Decided (user, 22 October):** first split the 3.65x into its `f32` and SIMD parts with two extra Zig variants; then add an `f32` type; add an explicit lane type only if the remaining gap stays above 1.5x. **The split (22 October, instructions per solve):** SIMD alone 3.8–3.9x; `f32` storage alone 0.91x (the conversions cost more than they save); LLVM does not vectorize the Selka port. **Extended by the user (22 October):** add both `f32` and SIMD to the language: a vector type (proposed `Simd[T, N]` with a `simd` module) and a checked `@vectorize` loop promise like `@noalloc`. One lane, `c8/f32-simd`, does `f32` first, then SIMD once the user approves the syntax; estimate 43 h. **Syntax approved (user, 22 October 16:20):** `Simd[T, N]` (`T` = `float`, `f32` or a fixed-width integer; `N` = 2, 4, 8, 16; a value type lowered to LLVM vectors; elementwise operators; comparisons give `Simd[bool, N]`; integer lanes follow the scalar checked rules); the `simd` module (`splat`, `load`, `store`, `select`, `sum`, `min`, `max`, `fma`); lane reads `v[k]`; and `@vectorize` above a `for` loop, checked in `--release` builds like `@noalloc` with LLVM's missed-optimization reason in the error |

C2 (an idiom and a doc), C6 and C7 are cheap and should land early, beside A. C1 and C3 follow A's R4. C4 and C5
wait for the kernels to show they are needed. C8 waits for K2's numbers.

### 4.D Allocation on hot paths

Do this after B's first profiles, because the profile decides it.
1. **D1, allocator size classes.** Small blocks of 16–256 bytes come from per-size free lists instead of the general
   allocator. Measure K1–K3 and the EDA port.
2. **D2, capacity reuse.** A list cleared and refilled in a loop keeps its capacity (`clear` versus a new list).
   Document the idiom, and lint the per-iteration `xs = []` pattern.
3. **D3, scoped regions** (only if D1 and D2 leave allocation above about 20% of a kernel's samples). A
   `with region():` block whose allocations are freed together. Checked ownership makes escape checking possible:
   nothing allocated in the region may outlive it, so the region is a compile-time borrow. This revisits the retired
   `with arena():` with a sound rule. It is the user's decision (D2 in §7).

4. **D4, checks in hot loops** (found by K2, 22 October). `--release` keeps every bounds, overflow and division check:
   about 90 M per solve on the thermal kernel, 22% of its instructions. Cost them first with an unchecked build
   variant (an experiment, not a language feature), then decide between hoisting or eliminating checks the compiler can
   prove and leaving them.

Exit: allocation and drop helpers below 15% of samples on K1–K3.

### 4.E Multithreading

1. **E0, rebase concurrency plan 2.** `codex/concurrency-2` (10 October) cannot merge onto today's `main`: wave 2 and
   C9 rewrote the files it touches.
   - Re-apply its P1F fixes as a lane, using the branch as a reference: A1, cross-thread frees growing memory; A2–A6;
     B1–B3.
   - Then the zero-tax `single` mode (package T), with an LLVM-identity proof and `perf` against a `main` without
     threads.
   - The TSan suite: 300 runs, as P1 used.
2. **E1, the P2 surface.**
   - `parallel.map` with fallible functions (D3 of plan 2).
   - `with parallel.group() as g:` and `g.submit(fn, ARGS)`, with the checker rules of plan 2 §6.2.
   - Built in the current syntax and the current ownership rules:
     - arguments to tasks are lent read-only or given with `own`;
     - results come back by value;
     - a `mut` argument is refused.
   - With C9 views, read-only shared data, such as the whole design model, can be lent to every task without a copy.
     Make that the rule and test it.
   - Also lift CX2's `parallel.map` trade-off with a view ABI for the capture record (deferred from CX2).
3. **E2, parallel kernels.**
   - K3 split across threads.
   - K1's independent nets, if the router's structure allows it; the lane reads `router.zig` and reports.
   - Meet R-3.
4. **E3, shared mutable state** (the server's caches and job queues, 17 netlisp files). Not needed for the CLI tools.
   **In scope (user, 23 October): the full port includes the server.** Design it after G2, and land it before G3
   reaches the server's files. Mutex-guarded records are the likely form. Decision D3 in §7.

### 4.F Scale

1. **F1, the probe.** Build three projects, check, test, debug build and release build each, and record wall time
   and peak RSS:
   - eda-bench stage 2 ported (from G2);
   - a generated 100k-line project;
   - a generated 400k-line project of the same shape (many modules, one large strongly connected import component,
     like netlisp).

   Compare with R-5.
2. **F2, fixes**, expected by measurement:
   - **The release build:** one LLVM unit for the whole program will not meet R-5 at 400k lines. Partition release
     into a few units by import component, with cross-unit inlining limited to small functions, and measure the
     runtime cost on K1–K3. Accept at most 3%.
   - **Interface cutoff and digests at depth:** the import component is mostly one strongly connected component, so an
     interface change re-checks most of it. Measure, and design a finer cutoff if needed.
3. **F3, the shared-machine reality.** The compiler's ReleaseFast build needs 4.5–6.5 GB, and earlyoom killed it three
   times (FR-438). Reduce its peak or document a Debug compiler for release checks.

### 4.G The staged port

| Stage | Program | Size | Gate |
| --- | --- | --- | --- |
| G1 (done) | eda-bench stage 1: dumped model → KiCad schematic set + netlist | 26k Zig, 22k Selka | 34/34 goldens; 0.96x Zig wall, 3.6x instructions |
| G2 | eda-bench stage 2: design sources → resolved sexp, KiCad set, netlist, ERC JSON, HTML/SVG page | 99k Zig (the slice exists, with goldens) | 34/34 goldens; ≤ 1.5x Zig instructions on the stage's own benchmark (user decision, 5 November: tracked as a diagnostic, not gated, as R-2's instructions are since 23 October; 1.65x on 5 November, with wall time 1.06x geomean and every case ≤ 1.25x); edit loop within R-5 |
| G3 | the full netlisp, in slices along the import component (CLI tools first, the server last) | 669k Zig, about 400k Selka | every netlisp golden and test that has a Selka counterpart; R-1 to R-5. (5 November: planned in `g3-plan-2026-11-05.md`, sections S0 to S5 with a review stop after each; the autorouter is out of scope, user decision 5 November.) |

- **How the port is done.**
  - Agents port module by module, skeleton first: interfaces and holes, then bodies (the audit's §7.2 workflow).
  - Netlisp's own tests port with the code.
  - The Selka idiom guide (the Lox R3 idioms, the EDA tokenizer lesson, the view and borrow rules) is a document the
    porting agents read first. Write it in G2, from what G2 teaches.
- **Where the port lives.** eda-bench for G2 (the slice and harness exist). For G3, a new repository whose structure
  mirrors netlisp's. Decision D5.

### 4.H Stability

From G2 on:
- every breaking language change carries a certain `mylang fix` migration and an entry in a `CHANGES.md` with a version
  number;
- the porting agents pin a compiler;
- a migration that needs hand edits at more than about 20 sites in the ported code is a stop and a user decision.

This is plan-level policy, not code.

### 4.I Self-hosting (stream H; added 22 October, at the user's request)

**Why.** It gives the language a second large program in a different domain from the EDA port: trees, symbol
tables, interning, caches and incremental rebuilds, where the port is numeric and geometric work. It also tests the
agent-speed goal on the language's own code. It does not buy independence from Zig: the back end still drives
`zig cc` and LLVM, and the runtime is C.

**When.** It starts after G2, when §4.H freezes the language. Until then every breaking change would also have to
migrate a self-hosted compiler and re-seed it. It runs beside G3 and goes only as fast as its parity gate allows.

**How.** It follows `docs/audits/selfhost-plan-2026-10-19.md` (accepted 19 October), stage by stage:

| Stage | Boundary | Gate |
| --- | --- | --- |
| H1 | lexer and parser, returning the existing `StoredSyntax` payload and the parser's diagnostics | that plan's G1–G5 |
| H2 | declarations and the type interface | its own plan, written from H1's measurements |
| H3 | bodies, generics, effects, origins, contracts, incremental retention (the long pole) | its own plan |
| H4 | lowering to Core IR; after it the Zig front end is gone | its own plan |
| H5 | the back end | last, or never: it is the most performance-critical part |

Every stage keeps the 19 October plan's rules:
- **The Zig compiler is the oracle, byte for byte.** That means the live Zig code, not a frozen copy, run over the
  corpus. It remains the shipping compiler until the stage passes every gate.
- **The parity gate.**
  - Each ported section runs within 1.10x of its Zig twin, at the median and at p95, in an exclusive timing window.
  - End to end, a cold `mylang check` and the edit loop stay within 1.05x.
  - A gap is fixed in the compiler, runtime or standard library, never worked around in the ported code.
- **Shadow, then delete.**
  - The Selka stage becomes the default, with the Zig stage shadowing it.
  - During shadow, a change lands in both in one commit.
  - The Zig code is deleted after 14 days without a mismatch.
- **Per-stage plans.** Each stage after H1 gets its own plan, written from the previous stage's measurements of
  throughput, worker cost and diagnostics parity.

The 19 October plan assigned Codex as implementer (U5). Revisit that at H1's start, together with D6. H1 begins
with that plan's prerequisite lanes (P0: oracle and corpus, standard input if it has not landed, seed builds).

**What it changes for the language.**
- Once H1 lands, a breaking change after the freeze also migrates `selfhost/`. `mylang fix` writes that migration
  and the re-seed script rebuilds the seed.
- A compiler will press for features the language has declined: references inside records, interning by pointer,
  unchecked indexing. Meet them with the same rules as the port: pool handles and indices, as Zig's own compiler
  uses. Decide C5 only on evidence, and never add unchecked access.

Exit: H1 deletes the Zig lexer and parser. Later stages exit by their own plans.

**Not scheduled: proofs.** A concept for after self-hosting, recorded at the user's request on 22 October:
`docs/audits/proofs-concept-2026-10-22.md`. It covers three tiers: what the ownership checker already proves,
properties as capability types (such as "no data access without auth"), and an opt-in `mylang prove` over the
existing contracts. Nothing in it is planned.

## 5. Order and parallelism

| Phase | Lanes running together | Lands when |
| --- | --- | --- |
| 1 (now) | A: R3a/R2; B: K2, then K1; C2, C6, C7 (the exchange idiom, the fixer, the lint); F1 probe on generated projects | A's R2 gated; K2 and K1 ported with their Zig comparison; C2, C6, C7 gated; F1 table written |
| 2 | A: R3b + R4, then R5; E0 rebase; D1 (if the K-profiles call for it) | R-1's matrix passes; E0's TSan and zero-tax proofs pass; kernels within 1.5x |
| 3 | C1, C3; E1 surface; F2 release partitioning | kernels within 1.25x single-threaded; E1 checker rules and tests |
| 4 | G2 port; E2 parallel kernels; D2/D3 as measured | G2's goldens and gates; R-1 to R-5 hold (R-3 included), so G3 may start. **Closed 5 November (user decision, §5.2).** |
| 5 | G3 port, slice by slice; E3 (the server is in scope) before G3's server slices; H1 self-hosting stage 1, then H2–H4 from their own plans | every netlisp golden with a Selka counterpart matches; R-1 to R-6 still hold; each H stage passes its parity and shadow gates |

### 5.1 Item estimates and the review rule (added 22 October, at the user's request)

Each item has an estimate in wall-clock hours for one lane, from the lane's start to landing on `main` (eda-bench work:
to the coordinator accepting it), including builds, gates and review. The doc "EDA port roadmap" tracks each item's
start, finish and elapsed time.

**Review rule.** When an item's elapsed time passes its estimate, it is flagged. Past 1.5x, the coordinator stops
and reviews it with the user. The review splits the item, rethinks it, or extends it with a stated reason.

| Item | Estimate | | Item | Estimate |
| --- | --- | --- | --- | --- |
| R3a mixed-return refusal | 2 h | | C1, C3 | 16 h |
| R2 borrow-set inference | 4 h | | C4, C5 (only if needed) | 20 h |
| R3b + R4 | 16 h | | D1 allocator size classes | 8 h |
| R5 stdlib accessors | 6 h | | D2, D3 (as measured) | 12 h |
| R6, R7 | 6 h | | E0 review fixes, zero-tax mode | 20 h |
| K2 thermal kernel | 6 h | | E1 task groups | 20 h |
| K1 router kernel | 10 h | | E2 parallel kernels | 12 h |
| K3 DRC kernel | 8 h | | E3 shared mutable state | after G2 |
| C2 exchange idiom | 2 h | | F1 scale probe | 5 h |
| C7 copy-in-loop lint | 3 h | | F2 release partitioning | 16 h |
| C6 fixer repairs | 5 h | | G2 stage-2 port | 60 h |
| C8 f32/SIMD | 2 h to decide | | G3 full port | 225 h |
| | | | H1 self-hosting stage 1 | 80 h, plus 14 days of shadow |
| | | | H2–H5 | sized from H1's measurements |

A phase's estimate is its longest chain in one lane:
- phase 1: 16 h (K2, then K1);
- phase 2: 22 h (R3b + R4, then R5);
- phase 3: 20 h (E1);
- phase 4: 60 h (G2);
- phase 5: 225 h (G3).

Phases 1 to 4 total about 118 h of wall-clock time if nothing overruns. Recalibrate the estimates after phase 1
from its actual times.

### 5.2 Phase 4 closed (5 November)

The user closed phase 4 on 5 November, so G3 may start. The evidence is in
`experiments/eda-roadmap-20261022/p4-recheck-20261105/` (`gate/`, `perf/` and `release/`), measured on main `10a8a7902`
and `3e517cc00`. Speed rows are `--release` against Zig ReleaseFast wall time.

| Gate | Result | Ruling |
| --- | --- | --- |
| R-1 | the matrix 422/422 in every mode after R1M; 0 hidden copies in the kernels | D10's ten branch refusals accepted (user, 5 November); K2's per-solve copy is the harness artifact its `NOTES.md` D6 names |
| R-2 | K1 1.09–1.15x; K2 SIMD 1.15–1.16x per solve; K3 SIMD 1.10–1.11x per field | pass |
| R-3 | K1 1.05–1.11x at 1 to 8 threads; K3 0.67–1.07x unpinned; zero tax by measurement | judged unpinned, as E2 measured it (user, 5 November); zero tax accepted (user, 5 November) |
| R-4, G2 | 34/34 goldens, 1,250 tests, native 11/11; wall 1.06x geomean, worst case 1.245x | pass; G2's instruction line (1.65x) is a diagnostic (user, 5 November) |
| R-5 | at 400k: check after an edit 1.75 s, debug build 4.04 s, one module's tests 1.31 s, cold release 250 s in 6.0 GB | pass |

Follow-ups. None is a gate and none blocks G3:
- **FU-1, K3's parallel split.** Pinned to the performance cores, K3 at 8 threads is 1.27x Zig on Cyclops-Flex and
  1.30x on black-canyon. The program gives the pool one task per lattice row: 1,160–1,360 context switches against
  Zig's ~160, since Zig gives each thread 4 chunks. `row_values` also runs 1.33x Zig's instructions. Batch rows into
  chunks, in the program or in the runtime's work split, and re-measure pinned, before G3's DRC slices.
- **FU-2, two parity slowdowns.** In release, `fib` is 1.96x Zig (its threshold's baseline is 1.666x, 17 October) and
  `list_append_sum` 1.01x (baseline 0.83x). Find the commit that slowed each, then fix it or re-baseline.
- **FU-3, three parity thresholds crossed below 1x.** `knucleotide-tuned` 0.64x, `bytes_scan-wrapping` 0.48x and
  `dict_count` 0.66x exceed their thresholds while still faster than Zig. Explain each, then fix it or re-baseline.

## 6. Risks

- **The record- and container-heavy gap may not close to 1.25x with copies alone.** The EDA profile shows
  allocator and drop helpers, not just copies. D1 and D3 exist for that. If after phase 3 K1 is still above 1.5x,
  report the residue by cause before G2.
- **The concurrency rebase is large.** Wave 2 and C9 changed the files P1F touches. Treat the old branch as a
  reference, not a merge. The A1 flaw is a design problem in the runtime's free path, not a patch.
- **C5 (borrows in records) is a big language change.** Don't start it on speculation; let K1 and G2 show the need.
- **Scale may hide other superlinear pieces** besides release and the checker. F1 is cheap; run it early.
- **Language churn burns porting work.** §4.H applies from G2, and A–C should finish their breaking changes before
  G2's code grows.
- **Self-hosting could slow every user's edit loop.** A Selka compiler stage slower than its Zig twin makes R-5
  worse for everyone. The Zig stage keeps shipping until the Selka stage passes its 1.10x and 1.05x gates (§4.I).
- **Self-hosting could pull the language toward compiler-shaped features** (references in records, unchecked
  indexing). §4.I meets those needs with the port's rules instead.
- **The machine.** Gates, timing windows and ReleaseFast builds compete on one laptop. Keep timing windows separated
  by gaps, and keep at most three building lanes.

## 7. Decisions for the user

Accepted 22 October: every recommendation below, as written.

1. **D1, the performance target.** R-2 says ≤ 1.25x Zig ReleaseFast on the kernels, single-threaded. Alternatives:
   1.1x, a stricter target with more allocator and layout work, or 1.5x, which is reachable sooner. **Recommended:
   1.25x, with 1.5x as the interim gate for G2.**
2. **D2, scoped regions.** Allow D3 (`with region():`) if the profile demands it, or keep allocation tuning only.
   **Recommended: decide after D1 and D2's numbers**, with D3 pre-approved if allocation stays above 20% of a kernel.
3. **D3, shared mutable state across threads** (E3). In scope for the full port, which needs it for the server, or
   later. **Recommended: later.** Port the CLI tools first and design E3 after G2. **Decided (user, 23 October): the
   server is in scope**, so E3 is planned rather than conditional: designed after G2, landed before G3 reaches the
   server's files.
4. **D4, the language freeze** (§4.H). From G2, or now. **Recommended: from G2.** A and C still need breaking changes.
5. **D5, where G3 lives.** A new repository mirroring netlisp, or inside netlisp beside the Zig. **Recommended: a new
   repository**, with eda-bench's harness pattern for goldens.
6. **D6, who implements.** The current mode (Haiku lanes, Claude coordinating and gating) or Codex runs with Claude
   reviewing. **Recommended: the current mode for A–F**, which proved itself on 21–22 October. Revisit for G3's bulk
   porting.

## 8. Operating rules

As in wave 2's second half (`experiments/language-wave2-20261019/lanes/briefs/LANE-RULES.md`):
- one worktree per lane;
- Claude merges into an integration branch and runs the complete verification on the merged tree before
  fast-forwarding `main`;
- evidence stays out of git;
- decisions are logged in each stream's `DECISIONS.md`.

New for this roadmap:
- **Kernel numbers** (§4.B) are reported with every landing in A, C, D and E.
- **Timing windows run one at a time with gaps.** Last night's back-to-back windows starved builds for hours.
- **An idiom note.** A lane that removes a hot copy by idiom writes the idiom into the porting guide (§4.G).
