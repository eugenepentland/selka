# Plan: test time, ownership costs, capabilities in records, library and test gaps (6 November 2026)

The user asked for four things on 6 November:
1. why the port's tests take so long, when they should rerun only what changed;
2. a plan to lift the language costs the G3 port pays: records that hold a borrow, moving out of a `match`, `take`/`exchange`,
   and copies on store;
3. capabilities that can go inside records;
4. the standard-library items and the gaps in test coverage.

This plan rests on three pieces of work:
- **A measurement on the port.** `~/ai/canopy/mylang-evidence-archive/experiments/g3/test-cost-20261106/`.
- **Research on the ownership items and capabilities.** Opus, read-only, with 27 probes against pin `g3-pin-bc8b74e8` (main
  `8fa46a03e`): `~/ai/.home-cache/plan-20261106/ownership.md`.
- **Research on the library and test gaps.** Sonnet, read-only: `~/ai/.home-cache/plan-20261106/stdlib.md`.

The coordinator spot-checked the two claims that change the plan most:
- a function taking `own fs` returns a record holding it (probe `p07`);
- `math.log10`, `exp`, `atan2` and `pow_float` exist and run on the pin.

Estimates are Sonnet lane-hours with tests and docs, excluding the complete gate.

## 1. Why the tests take long

**The measurement.** The port's 1,443 tests, in 162 entries, after four edits to `eval/env.my` (2,527 lines, reached by most tests):

| Edit | Rerun | Wall | CPU |
| --- | ---: | ---: | ---: |
| none | 0 | 22 s | 8 s |
| a comment reworded, no line added | **0** | 73 s | 228 s |
| one comment line added | **774** | 117 s | 347 s |
| one function body changed (`value_as_number`) | 389 | 69 s | 250 s |

**What it shows.** Reruns follow what changed, with one exception, and there are two separate costs.

- **T1. A line shift reruns tests that did not change.**
  - **The cause.** A test's IR key hashes every span as file, line and column (`test_runner_facts.zig` `factKey` and the test IR
    key). So one added line changes the key of every function below it in the file.
  - **Why a pass can drop positions.** A passing test cannot observe its own source positions, and a failure is never recorded.
    The compiler already has a position-free digest for this: `canonical_ir.plainDigest`, which the engine's parts use.
  - **The design.** Key a pass by the position-free digest. Positions still enter the program key, because the linked objects carry
    debug lines, so `engine-program-hit` stays positioned. Add a test: an added comment line reruns nothing, and a failing test's
    trap still reports the new line.
  - **Expected effect:** the 774 reruns go to about 0.
  - **Estimate:** 3-5 h.
- **T2. Deriving keys costs CPU even when nothing reruns.**
  - **Where it goes.** After the reworded comment, 102 entries each derived their keys again: 85 s, 67 s of it lowering and 13 s
    facts. Each entry runs in its own process and lowers the same changed module's functions again. The other ~140 CPU-s is
    per-entry checking and process start, not profiled yet.
  - **The design.**
    1. Profile one such run first.
    2. Make the derived lowering shared between entries: through the stage store, or by deriving every entry's keys in one
       process of the directory run.
    3. Find why a comment that moves no line re-lowers at all.
  - **Target:** a comment edit costs a few CPU-s, not 228.
  - **Estimate:** 5-9 h.
- **T3. An unchanged run waits.** 22 s of wall time for 8 s of CPU, all served from the stored report. Find the wait: process starts,
  a lock, or serial replay of 162 entries. **Estimate:** 1-2 h.

Lane **T** does T1-T3: 9-16 h.

## 2. Ownership: what the copies cost, and the designs

**Two findings that reframe the request.**
- **Copies are not the main speed lever.**
  - **The ceiling.** In the profile of the port's slowest `build`, its own code is 32% of samples and the kernel 57% (start-up,
    page faults, file reads). Copies are 16% of the port's own code, and allocation and drops 13%. Removing every copy is worth
    at most about 9% of `build`.
  - **What the designs below give.** Expect 2-4% (1.29x to about 1.25x).
  - **The kernel share is the bigger lever.** It gets its own item, P1 below.

  The main gain of the ownership work is shorter, more direct port code, not speed.
- **Capabilities can already go inside records when passed `own`.** The friction entry was stale. See section 3.

**Where the forced copies come from.** The research followed each of the 184 marked sites to the place its copy is stored:
- **45** have an owned source that is dead at the copy. About 20 need no compiler change, only `own x`.
- **62** store into a local or a temporary argument.
- **53** are returned and used while the source is alive.
- **31** are stored where they outlive their source, such as evaluator state. These are real ownership transfers, and no language
  change removes them.

The port has 2,876 lines with `copy(` in all. Most G2 code predates the markers.

**Every recommended design leaves the certificate validator and the Lean proof unchanged.** The certificate already models borrowed
constructors and owned records that hold borrows (A12/A13). The IR already has a non-owning `borrowed(T)`. What grows is the
exporter's trust (A1, A4, A12). The Debug compiler still validates every function, so a wrong exporter fails the gate instead of
being unsound. Each lane adds validator fixtures in its new shapes, as fix 4 did.

| Id | Item | Design | Lane-h | Port sites |
| --- | --- | --- | ---: | --- |
| 2A | match payload move | `match own x:` for any owned value. It consumes the owner, its bindings own their payloads, and `own payload.field` works. The IR is the existing temporary-scrutinee path | 5-7 | 8-17 payload sites |
| 3A | `take` / `exchange` | `exchange` on any type. `take` on any type with a default: an empty collection, `None`, or a record whose fields all default (fix 5 made `Block()` possible). The place may be `xs[i]`, `xs[i].f` or a `match mut` binding | 12-16 | the 3 `move_out_*` helpers and their 11 calls, 5 `lists.exchange` uses, the d-repro |
| 4a | copy of a borrowed loop element on store | **consuming loop** `for x in own xs:`, for an owned source that is dead after the loop: a runtime drain hands out owned elements | 6-9 | about 10 loops |
| 4a' | copy of an owned local at its last use | no language change: a `W_NEEDLESS_COPY` case whose `mylang fix` writes `own x` | 3-4 | about 20, and more port-wide |
| 4b | dictionary and set keys | **copy on insert**: `d[k] = v` and `sets.include(mut s, k)` take a borrowed key and copy it only when it is new | 5-8 | 19 marked; up to about 130 key copies port-wide; the likeliest speed win (per-net and per-pin maps) |
| 4c | `unwrap_or` | a literal default is static, so `-> bytes from r: return r.name.unwrap_or(b"")` passes; `options.take_or(own opt, own default)` after 2A | 3-4 | about 30 marked |
| 4d | `lists.extend` copies | `lists.extend_own(mut xs, own ys)` moves the elements | 2-3 | 5, and the reversed-pop-stack idiom |
| 4e | a `from` accessor cannot return `[]` | accept an empty literal beside a borrow, as `None` and `""` already are: `[]` is a static block | 3-5 | the e-repro; 28 `-> T? from` accessors can return plain lists |
| 4f | **found by the research**: conditional defaults | let a `mut` local hold a borrow when every assignment is a borrow. Retired conditional expressions force `mut x = copy(a)` then `if …: x = copy(b)` | 6-9 | 16-21 |
| 1A | a record holds a borrow (first step) | no syntax: a record built only from borrows of block-backed places is a borrowed value, like a `from` result. It may be a local, a temporary argument, or returned under `from`. The existing P5 provider contexts fold into it | 10-14 | the temporary-argument records (RailSpot, Edge) and local-only constructors |
| 1B | a record holds a borrow (declared fields) | a field declared as a borrow (spelling to choose), with view types through generics, lists and dictionaries, storable view layouts, and loan inference across `mut` calls | 40-55 | the `Member`, `FarEnd` and BlockView families and returned indexes: about 25-35 local sites and part of the 53 returned ones |

**1B waits for a census.** It is the only large item, and its benefit is unmeasured (about 1-2% of `build`). Before choosing it, a
counting release build of the port gives executions and bytes per copy site:
1. `tools/my build … --release --counters` on `build esp32-s31-sdr`;
2. `mylang cost --sites --counters`;
3. `perf` with call graphs inside a timing window.

This census and P1 are lane **M** (measurements), 3-5 h.

**P1. The kernel share of `build`.** Start-up, page faults and file reads take 57% of the slowest `build` case. Profile them with
`perf` (`--call-graph`, page-fault events, syscall counts) and list the causes before any copy work is credited with speed.
Candidates are the binary's size and relocation, zeroing of large allocations, and reading the design tree file by file. This is in
lane M.

## 3. Capabilities inside records

**Today:**
- A non-stream capability is a move-only block that owns its provider state: the memory filesystem, a seeded generator, a
  simulated clock.
- It may sit in a record. A function with `own fs` parameters returns `Ctx(fs=own fs, …)`, and `commands.new_evaluator` does
  exactly that.
- What fails is a record holding a *borrowed* capability, except a flat read-only local context (P5), and a capability in a list
  (`E_LIST_CAPABILITY`).
- **The soundness reason:** a copy would either duplicate the provider state (two memory filesystems that diverge) or alias it
  with no owner count.

**The pain is in the port, not the rule.** 429 test literals spell the 37-field `Evaluator`. They become `commands.new_evaluator(…)`
calls (S1a review: -41% on one file). That is port work: 2-3 h, the first commit of S1b.

**The user asked for capabilities that go inside records,** so the design question is how freely:
- **5C, recommended: capabilities become plain shareable handles.**
  - **How:** a capability lowers to a handle (an i64), as `Stream` and `Host` already do. The provider state lives in a runtime
    table and is freed when the process or the test trial ends.
  - **What it allows:** a capability can be copied, stored in any record or list, and passed without `own`. P5, the `own fs`
    threading, `E_LIST_CAPABILITY` and the capability rows of T2/T4 go away. Restriction is unchanged: copies keep their origin
    and grants.
  - **What changes:** copies share their state. Two copies of a seeded entropy draw from one stream, which stays deterministic.
    Two copies of a memory filesystem see one tree, as the real filesystem does. Memory filesystems made in a loop live until the
    trial ends.
  - **Validator and Lean:** unchanged, since handles are scalars.
  - **Estimate:** 16-24 h.
- **5B: capabilities stay single-owner values.** Borrowed capability fields come with 1B. No extra cost beyond 1B, but nothing
  changes until 1B lands.

5C is recommended because it is what "capabilities in records" means for an agent writing code: no special rule to remember. It
also removes `own fs` from every signature that only passes a capability along. **This is a decision for the user**, because it
ends the single-owner rule for capabilities.

## 4. Standard library and test coverage

**Already done, so the port's records are stale:**
- `math.log10`, `exp`, `atan2` and `pow_float` differ from Zig in 0 of 400,000 arguments.
- F-S0-5: the suite replays in 1.6 s with no `live-effects`.
- G04, G02, G12, G07/G08 and F-G2c-18 are closed too.

| Lane | Items | Design | Lane-h |
| --- | --- | --- | ---: |
| **A** filesystem | realpath, working directory, chmod, modification time | five more kinds of the durable entry (L1b's template, 7c188f636): `filesystem.realpath`, `cwd` (= realpath of `.`), `chmod`, `touch`, `set_modified`, and `atomic_write_file_mode`; `Stat.mode`; `stat_follow` for Zig's `statFile`. It also fixes `stat` through a symlinked parent and `listdir` of a symlink to a directory | 5 |
| **B** durable memory filesystem (after A) | durable lock in tests, and more | **every** durable call (stat, rename, atomic write, locks) fails on the test filesystem today, so the port's `infra.atomic_write` calls plain `write_file` and the production path is not the tested one. Implement the durable family on the memory filesystem: inodes, modes, an mtime from a logical clock (+1 s per mutation), and locks released on every exit. Deterministic, so tests stay cached | 5 |
| **C** environment and fault stand-ins | `Environment.get` with a computed name | the literal rule is a leftover of the old back end: the runtime already checks names against the allow-list. Accept any `str`. Also fix `env.names()`, which silently stops at 64 names. Add failing `Entropy` and `Clock` stand-ins (F-G2b-11) | 3.5 |
| **D** math | the rest of Zig-exact math | libm is not enough: glibc differs from Zig in 3-55% of arguments, and Selka's `sin`/`cos` in 3.1% (more than the 2% in the port's notes). Port `ln`, `atan`, `acos`, `tan`, `asin`, `expm1`, `sinh`, `cosh`, `tanh`, `cbrt` (M1) and Zig's `sin`/`cos` (M2) in Selka, verified against Zig captures, as the done four were | 7 |
| **E** Process in tests (after A) | `Process` in tests | a scripted stand-in: `process.scripted(rules)` answers by rule and logs each call, and a `proc: Process` test parameter gets an empty script. Deterministic, so cacheable. Real child processes stay in the port's native check programs | 5 |
| port | allocation-failure tests | **not applicable**: Selka cannot catch an allocation failure. About 37 of netlisp's 45 such tests inject one and check cleanup, which Selka can only observe as a trap. The 8 that prove "allocates nothing" port as `@noalloc` or `testing.allocations(…) == 0`. Netlisp's 117 leak-audit tests are covered by running the suite under `MYL_CORE_LEAKCHECK=1` (it passes). Note in `DECISIONS.md` that the S4 server now dies on out-of-memory | 0.5 |
| small | `bytes.replace`, `list + list` | still errors; `lists.concat` exists | 1 |

The seven small decisions (D1-D7), with the recommended answers:
- **D1:** `realpath` under `--restrict` answers relative to the grant.
- **D2:** `atomic_write_file` keeps 0600, and a `_mode` variant serves the port.
- **D3:** `process.executable_path` goes in `process`.
- **D4:** `env.only` stays literal.
- **D5:** `math.sin`/`cos` change in place to the Zig-exact routines.
- **D6:** no real child processes in `mylang test`.
- **D7:** `filesystem.memory()` becomes durable, and three tests in `tests/lang/filesystem_paths.my` flip.

## 5. Port-side work (no compiler change)

These are S1b's first commits, 5-7 h:
- the 429 evaluator literals become `new_evaluator(...)` calls;
- `own x` at the dead-source copies, about 20, and with 4a' landed, `mylang fix` finds the rest;
- borrowed returns on the `Some(copy(...))` accessors;
- `pin_names` takes the rules directly (13 sites);
- the stale FRICTION rows updated;
- `MYL_CORE_LEAKCHECK=1` added to the port's test command;
- `pll_loop` uses `math.*` instead of `support_math`.

## 6. Order and lanes (at most three at once)

| Wave | Lanes | Lane-h | Why this order |
| --- | --- | ---: | --- |
| 1 | **T** test time · **A→C** filesystem, then environment · **D** math | 9-16 · 8.5 · 7 | T speeds every later lane's loop. A, C and M1 are what S1b's `check` (impedance, thermal, disk memo) needs |
| 2 | **O** ownership checker: 2A, 4f, 4c, the 4a' lint, then 1A · **L** front end and lowering: 3A, 4a, 4d, 4e · **B→E** memory filesystem, then the Process stand-in | 27-38 · 23-33 · 10 | O and L touch different files (`single_owner.zig` and the lint against `sema_exchange.zig`, `build.zig` and the list runtime). 1A follows 2A and 4f because they share the borrowed-local state |
| 3 | **K** copy-on-insert keys · **CAP** 5C, if chosen · **M** census and P1 | 5-8 · 16-24 · 3-5 | K and CAP touch the runtime regions that wave 2's B and E edit, so they follow them. The census decides 1B |
| later | 1B, only if the census shows hot view-shaped copies | 40-55 | |

**Totals.** About 110-150 lane-hours without 1B. At three lanes that is about 40-55 h of wall time, plus review, gates and pins.

**S1b.** Under the three-lane limit, running all of this first delays S1b by about two days. The recommendation:
- **Now:** wave 1, about 16 h of wall time on three compiler lanes. Its items are what S1b needs or speeds.
- **After it:** S1b on two lanes beside one compiler lane, which works through waves 2 and 3 in order (O, L, B→E, K, CAP, M).
- **The port** picks up each landed fix in S1b's next integration: a new pin, then `mylang fix` and the marked sites.

The alternative is all compiler work first, then S1b on three lanes. It gives the cleanest ports, but S1b starts about two days
later.

## 7. Decisions for the user

1. **Capabilities:** 5C, shareable handles that go anywhere (recommended), or 5B, single-owner with borrowed fields later through
   1B.
2. **The consuming loop's spelling:** `for x in own xs:` (recommended).
3. **`take` of a record place** leaves the record's field defaults behind (recommended).
4. **The library decisions D1-D7** as recommended in section 4.
5. **The order against S1b:** wave 1 now and S1b beside one compiler lane after it (recommended), or all compiler work first.
6. **1B's syntax** (`name: borrow T` or `view record`) is deferred until the census says 1B is worth doing.

## 8. The user's decisions (6 November, 13:14 UTC)

- **Accepted as recommended:**
  - 5C: capabilities become shareable handles;
  - the consuming loop is spelled `for x in own xs:`;
  - `take` of a record place leaves the field defaults;
  - D1-D7 as in section 4;
  - 1B waits for lane M's census.
- **The order changes.** All three waves land first, with at most three lanes at once. Then the port is redone from scratch on a pin
  of the fixed compiler: fresh agents, section by section, to find the problems agents still run into. S1b does not run beside the
  compiler lanes.
- **The redo's scope (13:2x UTC):** everything ported so far. That is G2's stage 2 code plus S0 and S1a, written fresh against
  the same goldens and tests.

## 9. The overnight plan (approved 6 November, 20:4x UTC)

The user approved these before a six-hour absence:
1. **Landing.** The coordinator lands lanes M, F and G after review and a green main gate.
2. **1B.** The bar is 5% of `build` wall time on the three slowest cases, counting what 1B removes on top of K and 1A. Under it,
   1B is dropped for now. Over it, the coordinator writes a 1B plan with a proposed spelling but does not start it; the redo
   starts anyway.
3. **P1.** The kernel-share fixes wait until after the redo. They change no language.
4. **The pin.** It is built from main once M, F and G have landed. If F or G is unfinished at 00:30 UTC, the pin takes what has
   landed, and the gap is noted.
5. **The redo.**
   - A new repository, `~/ai/canopy/netlisp-selka-redo`; the old port stays untouched for comparison.
   - Kept: the harness, goldens, oracle, tools (`tools/my`, `bench.py`, the test checker) and the skeleton generator. Rewritten:
     all Selka source. A new porting guide is written from today's language docs, without the old workarounds.
   - Three fresh Sonnet lanes, split by module as G2 was. They may not read the old port's `src/`, `FRICTION.md` or `docs/`.
     Every compiler or language problem is logged with a repro.
   - Order: stage 2, then S0's base, then S1a's command shell. Exits: every test passes, `equiv` 217/217, and the release
     build within 1.25x of netlisp's ReleaseFast build (geomean).
   - A compiler bug that blocks a lane is fixed on main and the pin moves, as in S1a; others are logged.
   - The redo stops at the end of S1a's scope with a report comparing its friction with the old port's. Nothing further starts
     until the user reviews it.
6. **New bugs.** Before the redo starts, an agent-facing bug gets a fix lane if a slot is free. After it starts, bugs are
   logged unless one blocks a lane.

## 10. Lane M's census and what it decided (6 November, 21:40 UTC)

`experiments/census-p1-20261106/status.md` has the numbers.
- **1B is dropped for now** (rule 2 of section 9). On the three slowest `build` cases, 1B would remove at most 3.0 / 3.1 / 2.6%
  of wall time (4.2 / 4.1 / 3.3% counting generously), about 1.5-2% realistically, under the 5% bar. K is worth 0.1% and 1A
  1.2%. The larger share, 7-12%, can be removed by port and library edits that need no language change; four of them, tried on a
  copy, cut wall time by 6-12% with identical output.
- **P1 does not reproduce as start-up.** The kernel is 25-33% of cycles, and the oracle is about as kernel-heavy. The cause is
  `infra.fs::list_dir`, 12-21% of the run (65% on the fastest design): the design tree is walked twice, each directory listed
  twice, and the runtime makes one `fstatat` per entry although `readdir` gives its kind. The fixes wait until after the redo
  (rule 3): a listing that returns entry kinds (library, 3-5 h, saves 8-17% of wall), kinds from `d_type` (runtime, 1 h).
- Two `mylang fix` and lint defects M found go to lane I before the pin: the `W_LITERAL_MATCH` repair on an option scrutinee
  breaks the program, and `W_NEEDLESS_COPY` misses two last-use shapes.

## 11. The redo's result (7 November, 04:45 UTC)

The redo is done and meets all four exits on `~/ai/canopy/netlisp-selka-redo` main `e544370`:
- **Tests:** 1,452 tests pass with the leak check.
- **Equivalence:** `equiv s1a` gives 217/217.
- **Speed:** the release build runs at 1.01x netlisp's ReleaseFast wall time over 205 cases. The first port was 1.12x.
- **Clean:** there are no holes and `fmt` is clean.
- **Effort:** about 6 hours of wall time on three Sonnet lanes plus forks and helpers, on two pins: `be8ef8fc2`, then
  `ef1c27d43`. No blocking bug was reported.

The report is the redo's `REPORT.md`; the friction comparison is its `docs/FRICTION-COMPARISON.md`.
- **What 6 November removed.** The first port's two largest friction groups do not recur: capabilities in records, and missing
  I/O functions.
- **Where the redo's agent time went.** Ownership:
  - records cannot hold borrows (1B's shape): 8.2 h, 1,508 sites;
  - other borrow-checker refusals: 8.2 h;
  - shared mutable places: 3.5 h.

  The edit loop and the check-versus-build disagreements come next.
- **New defects** the redo found are the `listdir` 256-entry cap and the cost of a stat per listed entry. The only atomic write
  fsyncs, and `--release` refuses unreachable holes.
- **Recommendations, for the user:**
  - a fix batch before S1b;
  - `mylang fix` writing store copies, ahead of 1B;
  - guide fixes;
  - adopting the redo as the port;
  - then S1b.
