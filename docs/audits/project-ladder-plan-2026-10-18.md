# Project ladder: build real programs, fix what they find (2026-10-18)

Prepared 18 October 2026 by Claude as the execution handoff for one Codex
coordinator and its lanes. The user approved the shape in conversation the same
day: a cheap landing path for fixes, one friction ledger shared by every
project, projects in their own repository, then three projects in order — an
HTTP server, an EDA tool (a KiCad library converter checked against netlisp),
and a project built by several agents at once.

The guest edit loop is fast: the HTTP session measured `mylang check` at 0.08 s
and ten guest tests at 0.83 s (0.05 s cached), and the CSV session 20 tests at
0.56 s (0.04 s cached). The next gaps are the ones only real programs show. This
plan finds them with programs people would actually use, records each one once,
and lands fixes fast enough that later projects run on the fixed compiler.

## 1. Evidence this plan builds on

| Fact | Source |
| --- | --- |
| The CSV module took five blind trials; the F1–F11 friction table was mostly fixed (`--local-stdlib`, f-string copies, move-site diagnostics) | `experiments/csv-stdlib-20261017/NOTES.md` on `main` |
| An HTTP/1.1 codec is in the standard library on its branch; its log lists two runtime blockers (a connection that serves several reads and writes, and `listen`/`accept`), one tooling bug (tests declared after `func main` are not discovered) and five paper cuts | `codex/http-codec-20261018` (`a20c8ff03d`, `3a8d2c049e`), `experiments/http-codec-20261018/NOTES.md` there |
| That branch's Codex session was implementing `--allow-listen=IP:PORT` and listen/accept, uncommitted, at 13:11 UTC on 18 October | `git -C ~/ai/canopy/mylang-http-codec-20261018 status` |
| The last complete verification took **3,527 s (59 min)** on 17 October. CLAUDE.md quotes the original complete gate at about 530 s. (Corrected 19 October: the HTTP session's "about 80 minutes" described the old QBE gate, and "dominated by historical audit corpora" came from the CSV notes; neither described this gate.) | `~/ai/canopy/mylang-ownership-default-20261015-integration/.mylang-cache/verification-v3/last-run.json` (`elapsed_seconds`); `CLAUDE.md` "Full gate"; the HTTP notes, item 9 |
| In that run the four big Zig roots took 288 s (`core`), 63 s (`cli`), 46 s (`golden`) and 38 s (`unit`). The Python-driver groups (`embedded_migration` 28 members, `cleanup_tooling` 72, `verification_cache` 34, `fuzz_campaign` 8, `ownership_corpus`, `removed_forms_audit`, …) record no wall time, and they account for the rest | the same report, `actions[].test_telemetry[].runner_interval` |
| By commit subject, 433 of `main`'s 766 commits since 14 October are audit, binding or fixture work | `git log --since=2026-10-14 main` |
| Two problems recur across both trials: borrowed strings that need `.copy()` (CSV F1, HTTP 3), and promoting a module to the standard library means editing nine registration points (CSV F8, HTTP 9) | both notes |
| Decided but not landed: wave 2 (methods on built-in types become functions, punning, unqualified case names, scalar `match`, the lints, one-lookup dictionaries, buffered `write`) and wave 3 (`str` as bytes, slices as views). Of the §7.2 parallel-work tools, today's compiler has dotted imports to subdirectories, `mylang api-diff --write/--against` and `todo[T]()` holes, but no directory modules, no `mylang merge`, no rename attributes and no runnable holes | `docs/design/surface-simplification-2026-10-13.md` (waves table); `docs/modules.md`, `docs/tooling/api-diff.md`, `docs/typed-holes.md` |
| Instruments that already exist: `mylang check --friction-log=PATH` (or `MYLANG_FRICTION_LOG`) writes one `friction-log-v1` line per check; `velocity/friction/harvest.py` folds a log into repair rounds per diagnostic code; `mylang profile on` keeps command timing history (`profile history`, `profile trends`) | `velocity/friction/README.md`, `docs/tooling/timings.md` |
| `main` is checked out in the primary checkout `~/ai/canopy/mylang` since 18 October. The Codex tree `.gate-speedup-batch3-20261015/mylang`, which used to hold `main`, is detached | `git worktree list` |

## 2. Decisions this plan takes

The user approves these by approving the plan.

- **D1. Two landing tiers.** Friction fixes land on a long-lived branch,
  `projects/fixes`, through a *patch gate* (P0.2). The projects build with a
  compiler from that branch. `main` moves only by fast-forward to a
  `projects/fixes` tip that has passed the complete verification. This way `main`
  never sees a weaker gate, and a fix reaches the projects in minutes instead of
  an hour.
- **D2. Projects live in their own repository,** `~/ai/canopy/selka-projects`. It
  is a new local git repository with no remote. Projects build with an installed
  ReleaseFast compiler pinned by commit, not under `experiments/` with a compiler
  from the same tree. That way install, upgrade and "the compiler's docs are not
  next to me" gaps show up too, and project code does not add to the compiler
  repository's twelve thousand tracked `.my` files.
- **D3. One ledger, with counts.** Every gap goes in `selka-projects/LEDGER.md`
  once, with a stable id (`FR-NNN`), a class, the projects that hit it and a
  status. A project does not wait for its fix: it writes a workaround marked
  `# FR-NNN:` and carries on. When the fix lands and the pin moves, it removes the
  marker. A project's own `NOTES.md` keeps the narrative, as the CSV notes do.
- **D4. Fix by class (triage).**

  | Class | Meaning | Rule |
  | --- | --- | --- |
  | `bug` | the compiler, runtime or a tool does the wrong thing | fix now |
  | `diagnostic` | right verdict, but the message, span, related location or fix is missing or misleading | fix now |
  | `docs` | a guide is missing, wrong or hard to find | fix now |
  | `stdlib` | a missing function or module | add it when a project needs it. Promote a project-local module to the standard library only after a second project uses it |
  | `surface` | a missing host or runtime capability (listening sockets, a process handle, …) | add it when a project is blocked, following an existing pattern (the endpoint grant for the listen grant). Changing an existing capability's meaning is a hard stop |
  | `loop` | a slow tool step (more than 5 s where the edit loop expects less than 1 s) | record the measurement; fix it if a single cause is found |
  | `perf` | the guest program is slow next to its oracle | record it; not fixed in this program unless a project is unusable |
  | `shape` | a change to syntax, semantics or the ownership rules | **never implemented here.** Count it. At three projects it becomes a written proposal in the final report |
  | `wave2` / `wave3` | already decided in the surface design | tag it; do not patch |
  | `declined` | the user has already decided against it (for example, `mut` at call sites, tuples) | tag it with the decision |

- **D5. Every project has an oracle.** A differential check against an existing
  implementation is how the CSV trial found its empty-field bug (F11). The
  oracles here are Python's `http.client` and `http.server`, `curl`, the user's
  Zig EDA (netlisp, built from a pinned export), and the CommonMark spec examples with `markdown-it-py` 3.0.0 (all
  installed or fetchable). Python is fine here: it sits in tests and drivers,
  never in the install graph.
- **D6. One before-and-after measurement.** In R0 the coordinator freezes a small
  calibration task: a 200–400-line program that touches strings, bytes, files,
  dictionaries and results. A fresh agent does it with the R0 compiler. In R3 a
  fresh agent does it again with the final compiler. The friction log's repair
  rounds and the time to first green are the program's headline outcome.

## 3. Operating rules

The default is **decide, log, continue**. Write every decision to
`experiments/project-ladder-20261018/DECISIONS.md` on `projects/fixes`: the
question, the options, the evidence, the choice, and whether it can be reversed.
Commit at every step, with a progress section in
`experiments/project-ladder-20261018/status.md`, so the run can be inspected
without interrupting it. Investigate and fix a gate failure within the run, for
up to about 6–8 h. Early measurements are checkpoints; only the final one binds.

**Hard stops.** Stop and ask only for:

1. a `shape` change, or anything that reverses or pre-empts a decided item (the
   13 October decisions, waves 2 and 3);
2. relaxing a gate on `main`, or retiring or moving any verification group
   (measuring a group better is allowed);
3. a broken premise, for example the HTTP branch abandoned with work that cannot
   be recovered, or the EDA tool's oracle not being deterministic;
4. a failure that cannot be fixed within the bound;
5. anything outside the branches this plan names: pushes, `origin`, `claude/*`
   branches and Claude worktrees, another active Codex lane's tree;
6. resources: free space on `/` under 25 GB (58 GB on 18 October), or the
   machine swapping.

**Authority.**

- Fast-forwarding `main` to a `projects/fixes` tip is authorized when that tip
  has passed `python3 scripts/verify_cache.py --profile complete` and `main` has
  not moved since the batch's base. Do it only in the primary checkout:
  `git -C ~/ai/canopy/mylang merge --ff-only projects/fixes`, after
  `git -C ~/ai/canopy/mylang status --porcelain` prints nothing. Never use
  `update-ref`, and never use the detached batch3 tree. If `main` has moved,
  merge `main` into `projects/fixes`, verify again, then fast-forward.
- The user's EDA repository `~/ai/canopy/eda` is **read-only**: another session
  commits there constantly. Pin one commit and export it with
  `git -C ~/ai/canopy/eda archive <sha> | tar -x -C ~/.cache/selka-projects/eda-<sha>`.
  Build the oracle from that copy. Never add a worktree to that repository and
  never edit its checkout.
- Servers bind `127.0.0.1` only. The only external fetches are the CommonMark
  `spec.json` and the Zig dependencies the pinned EDA build declares.

**Machine rules from `CLAUDE.md`.** Every compiler tree runs
`source ~/.config/mylang/dev-env.sh`. Builds and focused tests go through
`scripts/build-slot.sh build …`. Complete verification runs through
`scripts/verify_cache.py`, which owns its own admission. At most four agents
build the compiler at once. Project lanes only run the installed compiler, which
is light. Put caches, `TMPDIR` and install prefixes under `~/.cache/`, never
`/tmp`. Every new behavioural line under `src/` gets a `// spec: TAG` test and a
`SPEC.md` bullet. A breaking fix lands with its `mylang fix` migration. Keep
committed evidence under 10 MB per package; large logs stay in `~/.cache`.

## 4. Lanes

| Lane | Role | Tree | Builds the compiler |
| --- | --- | --- | --- |
| C | Coordinator: P0, ledger triage, batches, pin bumps, final report | `~/ai/canopy/mylang-projects-fixes` (`projects/fixes`) | yes |
| F | Fixer: works the ledger on `projects/fixes` | its own worktree, branch `projects/fix-<FR>` per fix | yes |
| H | HTTP server project | `selka-projects/http-server` | only through F, unless it takes over the HTTP branch (P1.0) |
| E | KiCad library converter | `selka-projects/kicad-convert` | no |
| M1–M4 | Multi-agent project workers, coordinated by C | `selka-projects` worktrees, branch per lane | no |

Project lanes never fix the compiler themselves. They file the ledger entry with
a minimal repro and keep going. This keeps the friction honest (a project lane's
time shows what using the language costs) and keeps compiler changes on one
reviewed path. If F would idle, it may take the next `loop` item.

## 5. P0 — Landing path and project repository (lane C, about half a day to a day)

**P0.1 Fixes branch.** Create `projects/fixes` from `main` and its worktree
`~/ai/canopy/mylang-projects-fixes`, with its own `ZIG_LOCAL_CACHE_DIR`.
Claim the tree with `git worktree lock --reason "codex: project ladder C"`.

**P0.2 Patch gate.** Add `scripts/patch_gate.py`, a developer script outside the
install graph. It runs, each through the build slot and in this order, and stops
at the first failure:

1. `zig build` (the Debug install);
2. Guardian (`zig build guardian -- all . --gate --full`);
3. `python3 scripts/affected_tests.py --base main`;
4. `zig build test-units`, `test-core`, `test-cli`, `test-lang` and
   `test-docs`, then `zig-out/bin/mylang doc-coverage .` and
   `zig build fmt-check`.

It writes one JSON line per run to
`experiments/project-ladder-20261018/gates.jsonl`: the commit, the steps, each
step's wall time, the verdict, and the `FR` ids in the commits since the last
batch. The target is under 15 minutes after a compiler edit on a warm tree. If it
misses that, profile it (the §6.1 rule from the front-end plan: a step over
5 minutes gets its own speed investigation) instead of dropping steps.

The patch gate is enough only for a diff confined to `src/` (excluding the
verification machinery), `docs/`, `tests/`, `test/`, `examples/` and `SPEC.md`.
Any other path (`scripts/`, `build*.zig`, `guardian.toml`, `selfhost/`,
`.guardian/`) needs the complete verification before the commit lands on
`projects/fixes`.

**P0.3 Gate profile (a report only).** Run the complete verification once on the
`projects/fixes` base, recording each group's wall time. The driver groups record
none today: wrap them or add timing capture, since measuring better is allowed.
Write `experiments/project-ladder-20261018/gate-profile.md` with one row per
group:

- its wall time;
- what it protects;
- the last commit in which it caught a real defect (from `git log` of the fixes
  that touched its inputs);
- a recommendation: keep it in the patch gate, run it per batch only, or make it
  a candidate to retire.

Retiring or moving a group is the user's decision (hard stop 2). The report is
the input for that decision.

**P0.4 Project repository and compiler pin.** Create:

```text
~/ai/canopy/selka-projects/
  README.md            how to build and test each project; how the pin moves
  COMPILER             the pinned compiler: projects/fixes commit and install prefix
  LEDGER.md            the shared friction ledger (D3)
  tools/install-compiler.sh   builds -Doptimize=ReleaseFast --prefix ~/.cache/selka-projects/compilers/<sha12>
  tools/mylang         a wrapper that execs the pinned compiler
  tools/check-all.sh   runs every project's tests and oracle drivers against the pin
  calibration/         D6's frozen task statement and its two runs
  http-server/  kicad-convert/  markdown/   one directory per project
```

A pin bump reinstalls the compiler, runs `tools/check-all.sh`, removes the
workarounds whose ledger items are now `fixed`, and commits.

`tools/mylang` sets two variables for the project it runs in:

- `MYLANG_FRICTION_LOG=<project>/friction/<yyyy-mm-dd>.jsonl`, which `check`
  records. Commit these logs: they contain no source text.
- `MYLANG_PROFILE_DIR=~/.cache/selka-projects/profile/<project>`, so command
  timing history is kept per project. Summarize it in `NOTES.md`.

Do not run `mylang profile on`: it is a per-user setting and would record every
other agent's commands too.

**P0.5 Seed the ledger.** Enter the still-open items from the two trials. Before
filing each one, reproduce it on the `projects/fixes` base; the HTTP session may
already have fixed some.

| Seed | Class | From |
| --- | --- | --- |
| `mylang test` misses tests declared after `func main` | bug | HTTP 1 |
| `if try f():` is `E_TRY_POSITION`; a protocol parser binds first | shape | HTTP 2 |
| An element taken from a `str[]`/`bytes[]` result is a borrow; parsers repeat `.copy()` | shape (count 2 with CSV F1) | HTTP 3, CSV F1 |
| A parameter may not share a top-level function's name (`E_SHADOWING`) | shape | HTTP 4 |
| `mut` repeated at every `byte_builder` call site | declined (12–13 Oct) | HTTP 5 |
| `ord` is not shown beside byte indexing in the parsing guides | docs | HTTP 6 |
| One connection cannot serve several reads and writes | surface | HTTP 7 |
| No `listen`/`accept` or listening grant | surface | HTTP 8 |
| Adding a standard module touches nine registration points | loop (count 2) | CSV F8, HTTP 9 |
| The complete gate takes about an hour | loop | HTTP 9, §1 |
| A successful `check` prints nothing | diagnostic | CSV trial 5 |
| A cursor helper wants tuples | declined (13 Oct) | CSV trial 5 |

**P0.6 Calibration task (D6).** Write `calibration/TASK.md`: the program
statement, a hidden oracle (a Python script and expected outputs), and the
scoring. Scoring counts rounds to first success, wall time, and repair rounds by
diagnostic code from the friction log. Then run it once with a fresh agent that
gets only the installed compiler and its guides. Record the run in
`calibration/r0/`.

**P0 is done when:**

- `projects/fixes` exists;
- the patch gate has run green once and its time is recorded;
- `gate-profile.md` is written;
- `selka-projects` exists with the compiler pinned;
- the ledger is seeded and every seed is reproduced or closed;
- the R0 calibration run is recorded.

## 6. Lane F — the fix loop (continuous from R1)

1. Take the highest-priority open item: a blocking `bug` first, then `bug`,
   `diagnostic`, `docs`, then `stdlib`/`surface` items an active project waits
   on, then anything with a count of 2 or more.
2. Turn its repro into a test (`tests/lang` for guest behaviour, the Zig roots for
   diagnostics and CLI, per `CLAUDE.md` "Where tests live"). Fix it on
   `projects/fix-FR-NNN`, run the patch gate, and merge into `projects/fixes`
   with a commit subject that starts with `FR-NNN:`. Set the ledger status to
   `fixed@<sha>`.
3. Coordinator batch: after five fixes or 24 hours, whichever comes first, run
   the complete verification on the `projects/fixes` tip.
   - If it is green, fast-forward `main` (see Authority) and bump the pin.
   - If it is red, land no further fixes until it is green.
   - A blocking fix may bump the pin before its batch, from a patch-gated tip.
4. Promoting a module to the standard library goes through F, and it carries the
   nine registration points until the `loop` item that derives them is fixed.
   That item is worth fixing early: it already has a count of 2.

## 7. P1 — HTTP server (lane H)

**P1.0 Take over the branch.** `codex/http-codec-20261018` is active. Wait until
its session hands off: its tree is clean, or its notes say it is done. Then merge
its commits into `projects/fixes` and run a complete verification, because they
add a standard module.

- If its listen/accept work is unfinished, H takes it over in a compiler
  worktree as a `surface` item. H builds the compiler for this part only.
- Follow the existing endpoint-grant pattern: `--allow-listen=IP:PORT`, at most
  eight grants, IPv4 only, rejected when combined with `--allow-all`. Also add a
  connection session in `network` that serves several reads and writes, which is
  that branch's next item 1.
- Do not touch that tree while its session runs.

**P1.1 Program.** In `selka-projects/http-server`:

- `serve DIR --port N`, a static file server:
  - `GET` and `HEAD`;
  - `Content-Type` by extension;
  - `400`, `404`, `405`, `413` and `431`, using the codec's limits;
  - persistent HTTP/1.1 connections and `Connection: close`;
  - an access log on `err`.
- `/kv/<key>`, a JSON key-value API (`GET`, `PUT`, `DELETE`) held in memory,
  using the `json` module.
- `fetch URL [-o FILE]`, a client that handles `Content-Length`, chunked and
  close-delimited bodies.

It is single-threaded. Concurrency is out of scope, because the concurrency plan
owns it; file a `surface` item if the server is unusable without it.

**P1.2 Oracles (Python drivers, outside the install graph).**

- Python `http.client` and `urllib` against `serve`.
- `python3 -m http.server` against `fetch`.
- `curl -v` for header conformance.
- Byte comparison of every served file in a 200-file tree that includes empty,
  1 MiB and binary files.
- A malformed-request corpus of at least 25 cases with the expected status codes.

**P1.3 Soak.** Run 10,000 sequential requests, with and without keep-alive.
Sample `VmRSS` and the count in `/proc/PID/fd` at the start and the end. RSS
growth must stay under 1 MiB and the descriptor count must not change.

**P1.4 Performance (informational).** Measure requests per second for a 1 KiB
file next to a minimal Go `net/http` server (Go is installed), both on one
connection loop. Record the load average and the compiler commit. This is not
gated.

**P1 is done when** the oracle drivers and the project's `mylang test` suite
pass on the pin, the soak passes, `NOTES.md` has its friction narrative, and
every gap is in the ledger.

## 8. P2 — KiCad library converter (lane E)

**Why this tool.** It is the library-intake step the user's EDA already runs. It
converts vendor `.kicad_mod` footprints and `.kicad_sym` symbols into netlisp
S-expressions.

- **Four deterministic oracle commands.** The converter is four netlisp
  commands, each writing to stdout:
  - `convert-footprint <f.kicad_mod>`;
  - `convert-symbol <f.kicad_sym> [--filter N]`;
  - `convert-pinout <f.kicad_sym> [--filter N]`;
  - `convert-package <sym> <mod> [--name n] [--filter f]`.

  They are dispatched at `src/main.zig:232`, `:237`, `:249` and `:242` in
  `~/ai/canopy/eda`, with handlers at `:580`, `:654`, `:640` and `:594`. There
  is no clock or randomness, and the hash maps in `src/convert/symbol.zig:152,213`
  are only looked up, never iterated. So byte-for-byte comparison is meaningful.
- **The right size.** Its Zig closure is 12 files and about 2,760 non-test
  lines:
  - `src/convert/footprint.zig` 525;
  - `src/convert/symbol.zig` 235;
  - `src/convert/symbol_helpers.zig` 253;
  - `src/board_layers.zig` 259;
  - `src/kicad_pcb/format.zig`, `numeric.zig` and `allocating_writer.zig`;
  - the four `src/sexpr/` files (tokenizer 365, parser 206, ast 124,
    printer 151).

  Expect 3–4k lines of Selka.
- **It stresses what the earlier trials did not:** a real S-expression parser
  over 6 MB of input, fixed-precision float output, sorting, dictionaries, and
  sin/cos for rotated pads.

Write it as a Selka program, not a line-by-line translation. Read the Zig for
the output rules, then design the modules yourself. The tool is one executable,
`kicad-convert`, with subcommands `fmt`, `footprint`, `symbol`, `pinout`,
`package` and, optionally, `alts`. It reads through `Filesystem` and writes to
`out`.

**The oracle.**

- The installed `eda/zig-out/bin/netlisp` is dated 6 September, older than the
  converter's last change (`f69fd2cb`, 5 October). Do not use it.
- Pin one `eda` commit, export it with `git archive` (section 3), and build
  netlisp there with the same pinned Zig (`0.17.0-dev.1683+5ceec001b`). The
  build may fetch its declared Zig dependencies (`guardian-zig` v0.2.2) if the
  global cache lacks them.
- The corpus lives in `~/ai/canopy/eda/projects/designs`, a separate git
  repository (`c21ef1dd` on 18 October):
  - `lib/sources` has 186 `.kicad_mod` and 266 `.kicad_sym` (2.6 MB). Only 3
    and 31 of them are tracked;
  - `kicad/` has 16 tracked footprints and one symbol library;
  - `lib/` has 1,564 tracked `.sexp` files (3.8 MB);
  - `~/ai/canopy/eda-bench/golden` has 172 more `.kicad_sym`.
- Read inputs by path. Never copy them into a repository. Every oracle run
  writes a manifest (path, size, sha256) beside its results, and runs netlisp and
  `kicad-convert` on the same bytes in the same run. That way an input someone
  edits later does not invalidate the comparison, and the counts can be
  reproduced.
- netlisp's own corpus differential, `scripts/corpus_diff.sh`, masks `#` lines
  (`diff -I '^#'`). Compare whole bytes. If an output line names the build,
  mask only that line and say so in `NOTES.md`.

**Milestones.**

- **E0: `fmt`.** This equals `netlisp parse <file>` (`main.zig:223` →
  `cmdParse`, `:559`), the canonical S-expression printer.
  - Byte-identical on all 1,564 `lib` `.sexp` files and every KiCad input
    netlisp parses.
  - On 30 or more malformed inputs (truncations, bad strings, overdeep nesting),
    the error verdict matches `path:line:col: error: msg`.
- **E1–E4: `footprint`, `symbol`, `pinout`, `package`.** Byte-identical stdout
  on at least 99% of the corpus for each command. Every mismatch is classified in
  `NOTES.md` (tie order, float ulp, or a real bug), and anything that is not this
  tool's own bug has a ledger id.
- **E5 (optional): `alts`, matching `merge-alt-functions` (`main.zig:254`).**
  Its CSV handling is a plain comma split plus trim
  (`src/convert/alt_functions.zig`, about line 110), not RFC 4180. Hand-roll the
  same split; using the `csv` module would change the output. The corpus has one
  real CSV (`lib/sources/esp32-s31nrv16-alts.csv`), so add synthetic ones.

**Float output.** First use the language's own formatting for the Zig `{d}`,
`{d:.2}`, `{d:.3}` and `{d:.4}` outputs. Every difference is a ledger item
(`stdlib` or `docs`). Only then fall back to `support_float_fmt` from the
`eda-bench` stage-1 port (`~/ai/canopy/eda-bench/mylang/src`). It matches Zig on
300,012 values but is written in the old `def` syntax: migrate it with
`mylang fix` and file what the migration misses.

**Known risks.**

- `std.mem.sortUnstable` (pdq) orders pins in `symbol_helpers.zig:253-266`.
  Equal coordinates on a side with more than about 24 pins depend on pdq's exact
  tie order.
  - If mismatches come only from ties, port pdq's order, using
    `eda-bench/stage2/tools/zig_std_vectors.zig` as test vectors.
  - Or list those cases as known divergences with a ledger id.
  - If ties explain more than 5% of a command's corpus, that is a broken premise
    (hard stop 3).
- Rounding ties at four decimals.
- One-ulp sin/cos differences on rotated custom pads (`footprint.zig:295,848`).

**Performance (informational).** Time the whole corpus per command for
`mylang build --release` against the ReleaseFast netlisp, recording the load
average and the compiler commit.

**P2 is done when** E0–E4 meet their criteria on the pin, the project's
`mylang test` suite and its oracle driver pass, `NOTES.md` has its friction
narrative and mismatch classification, and every gap is in the ledger.

## 9. P3 — A project several agents build at once (lanes C + M1–M4)

**Why CommonMark.** The project is a CommonMark-to-HTML library plus a
static-site command (`site build SRC OUT`).

- **An objective oracle.** The 0.31.2 spec's 652 examples give the expected HTML,
  and `markdown-it-py` 3.0.0 (installed) renders whole pages for the site
  command.
- **Clean seams.** Block structure, leaf blocks, inlines, and rendering plus the
  site command split naturally.
- **The right size:** about 5–8k lines.
- **It hits the recurring friction.** It does heavy byte and text slicing (the
  `.copy()` problem, and wave 3's subject) and recursive containers.

Fetch `spec.json` once into `markdown/oracle/`.

**P3.1 Skeleton (C, before any worker starts).** This follows §7.2, using only
the tools that exist today.

- One directory per lane, imported with dotted paths (`import blocks.container`).
- The shared types in full: block and inline node enums, `Document`, source
  positions and the reference map.
- Every public signature, with its `fails` clause.
- Bodies that compile and trap: `assert False, "M2: <function>"` followed by a
  minimal return. Today's `todo[T]()` blocks publishing, and runnable holes
  (§7.2 item 4) do not exist.
- Each spec section's examples as the owning lane's test cases.
- Freeze the interface with
  `mylang api-diff <entry> --write=api/baseline.txt`. Its names are qualified by
  module (`app::parse`). Before every merge request, a worker runs
  `--against api/baseline.txt --json` and must show no change outside its own
  modules.

The skeleton checks clean before M1–M4 start, and the user may review it.

**P3.2 Workers.**

The sections are `spec.json`'s `section` field. The counts are from 0.31.2,
which has 652 examples.

| Lane | Owns | Spec sections (examples) |
| --- | --- | --- |
| M1 | Container blocks: block quotes, lists, list items, lazy continuation, paragraphs, tab expansion | Block quotes, List items, Lists, Paragraphs, Precedence, Tabs (119) |
| M2 | Leaf blocks | Thematic breaks, ATX headings, Setext headings, Indented code blocks, Fenced code blocks, HTML blocks, Blank lines (150) |
| M3 | Emphasis and text inlines: the delimiter algorithm, code spans, escapes, the HTML5 entity table, line breaks | Emphasis and strong emphasis, Code spans, Backslash escapes, Entity and numeric character references, Hard line breaks, Soft line breaks, Textual content, Inlines (205) |
| M4 | Links and output: reference definitions, links, images, autolinks, raw HTML, the HTML renderer, and the `site` command (directory walk, front matter, templates, index page) | Link reference definitions, Links, Images, Autolinks, Raw HTML (178), plus site tests against `markdown-it-py` |

Each worker uses its own `selka-projects` worktree and branch. A worker may not
change the frozen `api/baseline.txt`. A shared-type change goes through C's queue, and C
applies it to every lane. C merges in dependency order (M2, then M1, then M3,
then M4), runs the whole spec suite after each merge, and keeps a scoreboard of
passing examples per section in `markdown/SCOREBOARD.md`.

**P3.3 What to measure.** This is the point of the project.

- Wall time from the skeleton to the first all-lanes-merged green.
- Merge conflicts: count, files, and resolution time.
- Interface change requests: count and waiting time.
- Time each worker spent blocked.
- The spec pass rate over time.
- Repair rounds by diagnostic code.
- For every ledger item about working in parallel, which §7.2 tool (items 1–6)
  would have prevented it. That count decides whether those tools get built.

**P3 is done when:**

- at least 95% of the 652 examples pass, and every failure is listed in
  `NOTES.md`, with a ledger id when the cause is a language or tool gap;
- the `site` command renders a 50-page sample site whose page bodies match
  `markdown-it-py`, compared after the CommonMark test suite's HTML
  normalization;
- `NOTES.md` reports the P3.3 measurements.

## 10. Rounds

| Round | Work | Expected wall time (estimate, not measured) |
| --- | --- | --- |
| R0 | P0 (C) | 0.5–1 day |
| R1 | H and E in parallel, F continuous, C batching | 2–4 days |
| R2 | P3: skeleton, then M1–M4 in parallel; F continuous | 2–3 days |
| R3 | The R3 calibration run with the final compiler; harvest every friction log; final report | 0.5 day |

E may start during R0 once the pin and the ledger exist, because it needs no
compiler change. M starts only after H and E are done, so it runs on a compiler
with their fixes in it.

## 11. Final report

Write `experiments/project-ladder-20261018/REPORT.md` on `projects/fixes`:

- what each project does and how to run it;
- the ledger totals by class and by status;
- the fixes that landed, with their commits;
- the calibration task before and after (rounds to first success, wall time,
  repair rounds by code);
- the gate profile and the patch gate's times across the run;
- the P3 measurements;
- every `shape` item with a count of 3 or more, written up as a proposal for the
  user;
- the list of `wave2` and `wave3` tags, with counts, as evidence for those waves'
  order;
- what remains open.

## 12. Copy-and-paste instruction for the coordinator

```text
You are the coordinator (lane C) of the project-ladder plan,
docs/audits/project-ladder-plan-2026-10-18.md on main in ~/ai/canopy/mylang.
Read it fully, then CLAUDE.md. Decide, log in
experiments/project-ladder-20261018/DECISIONS.md, and continue; stop only for
the hard stops in section 3. Start with P0 in a new worktree
~/ai/canopy/mylang-projects-fixes on branch projects/fixes from main. Create
~/ai/canopy/selka-projects (local git, no remote). Run lane F yourself, or as a
separate Codex lane, from R1. Start lane E once the pin and the ledger exist.
Start lane H only after the codex/http-codec-20261018 session has handed off
(its tree is clean or its notes say done). Never push. Never edit
~/ai/canopy/eda (export a pinned commit with git archive). Fast-forward main
only from the primary checkout after a green complete verification, as section
3 says. Commit at every step with a progress section in status.md. Finish with
REPORT.md (section 11).
```
