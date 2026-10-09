# Lox performance audit, 2026-10-02

Current main still has a substantial Lox execution gap. Over all 13 scripts,
LLVM averages **5.39× Zig ReleaseFast on the VM** and **11.16× on the tree
interpreter**. QBE averages **10.04× / 17.34×**. The highest-priority VM work is
active-frame ownership and materialization, followed by stack/property/table
operations and the additional code QBE emits. The tree interpreter needs its
own performance target and ownership work.

The branch audit found **no demonstrated Lox speedup awaiting a merge**. The
major RC/LLVM performance series are already in main. The unmerged large-return
cleanup patch builds byte-identical Lox executables to main, including forced
uncached builds. Other pending work includes compiler checking/memory repairs,
old build-cache experiments, unqualified prototypes, and improvements to the
reference languages.

## Scope and controls

- Compiler source: main `6df58b02554401f9d37564cceffd14277a835ae1`, built
  ReleaseFast in `codex/lox-perf-audit-20261002`. Compiler SHA-256:
  `45d05b554849bf3c12553549d9138556ba0204f9d59ba3aaa2ecb2327eb39ac4`.
- Lox source: `docs/audits/d9-stage3d-migrations/apply-lox.sh --optimized`.
  This includes the landed scalar readers, direct active-frame reads, tree
  dispatch helpers, assignment/RHS fixes, and indexed setter. All 26 module
  hashes are recorded. Reference Zig/Rust/Go sources and benchmark inputs come
  from `bench/lox-20260922` at `4e48a09220c2e018eba8c4b1eb3fe1137a3dae73`.
- Guests: RC default, ReleaseFast, explicit LLVM O3/full LTO or QBE, with
  `--keep-symbols`. GC LLVM is a separate diagnostic control. Zig ReleaseFast,
  Rust release, and Go use their original port defaults.
- Three interleaved timing rounds over **13 scripts × both engines × five
  binaries = 390 successful executions** at the benchmark's original engine
  sizes. Every run matches the complete checked-in expected stdout.
- Smoke output checks: 130/130. A separate 130/130 smoke sweep also matches
  Lox `allocations`, `collections`, `freed`, and `live` across all five builds.
  This checks the interpreter's logical collector work; it does not equate the
  host languages' physical allocation traffic.
- VM counters: 156 successful executions, three rounds, 13 scripts × four
  binaries, at the unchanged D9 calibrated `tree` sizes. Tree counters: 78
  executions, three rounds, 13 scripts × LLVM and Zig. Inputs and executable
  hashes are checked again after each sweep.
- Wall time uses CPU 2, counters/profiles CPU 10, on the i7-12700H. Siblings
  3/11 are reserved too; build-slot excludes those four CPUs. A quiet check
  precedes each group. Counters record user instructions, cycles, branches,
  and branch misses, with 100% running time for the instruction events.
- Toolchains: Zig `0.17.0-dev.1683+5ceec001b`, Rust `1.98.1`, Go `1.27.0`.

The primary ratios below divide each arm's median wall time by Zig's median,
then take a geometric mean across scripts. Median ratios paired within each
round give **5.38× / 11.33× LLVM** and **10.04× / 17.46× QBE**, confirming the
same conclusion. Absolute times drifted: median `(max-min)/median` is 21.2%
across arm/case cells. The median spread of paired ratios is 6.1%. This is a
focused diagnostic, not the frozen full 43-program performance acceptance.

## Current runtime results

| Engine | mylang LLVM | mylang QBE | Rust | Go | Zig ReleaseFast |
|---|---:|---:|---:|---:|---:|
| VM | 5.39× | 10.04× | 1.46× | 1.45× | 1.00× |
| Tree | 11.16× | 17.34× | 1.32× | 1.32× | 1.00× |

| Script | VM LLVM seconds | VM LLVM/Zig | VM QBE/Zig | Tree LLVM/Zig | Tree QBE/Zig |
|---|---:|---:|---:|---:|---:|
| binary_trees | 4.036 | 6.43× | 10.69× | 12.93× | 19.94× |
| closures | 4.877 | 5.12× | 9.04× | 14.12× | 22.47× |
| equality | 2.219 | 1.94× | 5.10× | 8.73× | 15.49× |
| fib | 3.748 | 5.05× | 9.55× | 11.20× | 17.99× |
| instantiation | 4.440 | 8.75× | 12.67× | 11.64× | 16.46× |
| invocation | 6.828 | 7.87× | 12.12× | 9.70× | 14.73× |
| method_call | 7.186 | 7.62× | 13.30× | 13.36× | 20.03× |
| properties | 7.489 | 8.11× | 11.25× | 11.06× | 16.42× |
| string_equality | 1.495 | 2.73× | 8.50× | 13.61× | 23.81× |
| strings | 1.955 | 3.27× | 7.37× | 8.65× | 14.44× |
| trees | 6.018 | 5.39× | 9.29× | 9.99× | 14.39× |
| zoo | 6.566 | 7.29× | 13.15× | 10.62× | 15.80× |
| zoo_batch | 5.293 | 6.70× | 12.73× | 11.20× | 16.39× |

The largest LLVM VM gaps are `instantiation` (8.75×), `properties` (8.11×),
`invocation` (7.87×), and `method_call` (7.62×). On the tree engine every
script is between 8.65× and 14.12× LLVM. The historical 43-program gate
includes only Lox VM cases, so its green result did not establish tree parity.

## What the gap is made of

### 1. Active-frame reconstruction and ownership are the first VM target

Uninstrumented LLVM cycle profiles put `vm::load_frame` at **22.89% of fib**,
**18.63% of properties**, and **14.42% of instantiation**. `vm::run` accounts
for another 40.95%, 37.52%, and 15.09%, respectively; that includes inlined
operations, so these percentages are function locations rather than mutually
exclusive categories such as checking versus ownership.

Separate sites builds explain the repeated work. At properties N=100,000,
`load_frame` publishes each of the three `ExecFrame` lists 6,000,003 times:
**18,000,009 owner acquisitions**, about **74.7%** of the process's 24,108,727
acquisitions. Two frame replacement/drop sites release those edges 18,000,003
times. Fib N=28 similarly acquires the three lists 6,170,745 times. These
diagnostic counts are not timing evidence: sites mode changes generated code.
Both reports balance allocations/retirements and holds; releases equal owner
acquisitions plus fresh heap allocations.

`load_frame` is already the direct nested-match optimization from September
26. This audit is not proposing to repeat that patch. Its current LLVM body
still contains 486 assembly instructions, including cold traps, and reserves
536 stack bytes. The static call-site count includes error paths and is not
a count of calls executed on each invocation.

**Next experiment:** keep active-frame code/constants/upvalues as lifetime-backed
read views rooted in the saved closure, or move/reuse the existing frame data
across call/return transitions. Prove root lifetime, snapshots, receiver
mutation, and error traces before eliminating ownership. Use the current
unchanged source as the control and measure fib, closures, invocation,
method_call, and properties. Eliminating the whole sampled frame loader would
at most give roughly 30% on fib; it would not close a 5× gap by itself.

### 2. Stack operations and property lookup retain avoidable work

`heap::push` is **12.06% of LLVM fib**, and `heap::peek` 5.29%. The sites
report records 3,599,604 uniqueness checks in `push` for that input; just one
is marked slow. Properties N=100,000 has 6,500,071 `push` uniqueness checks,
again with one slow case. The repeated fast-path checks are therefore an
actionable target even though generic cloning is not prominent in those
profiles.

Properties spends **13.36% in `table::get`** and **8.40% in `find_entry`**.
The ordinary match bindings in `get_property` and `invoke` also create
instance/table ownership traffic: the sites report shows 3,000,000 instance
retains and corresponding object/table loan operations at each of these
paths. The source should preserve normal snapshot semantics where required;
read-only helper results or a stronger borrow proof are candidates here.

**Next experiment:** prove the stack backing stays unique over an admitted
instruction region and carry the checked capacity/length facts; specialize
read-only instance-field/method lookups so the caller receives the scalar
result rather than a retained instance/table carrier. Keep mutation-capable
and refused cases on the existing path. Measure each change separately.

### 3. LLVM materially helps, but the base generated work remains excessive

Across the 13 VM counter cases, LLVM retires **5.63× Zig's instructions**;
QBE retires **13.22×**, or **2.35× LLVM**. The timing geomeans similarly put
QBE at **1.86× LLVM** on the VM and **1.55×** on the tree engine. A ReleaseFast
compiler already selects LLVM for release guests; ensure an evaluation actually
uses that compiler/backend.

This is substantial extra work, rather than just a low-IPC result. For fib,
LLVM IPC is 3.16 versus Zig 3.27, while instructions are 4.90× Zig. For
properties, LLVM IPC is 2.65 versus Zig 3.00 and instructions are 6.61×.
The current LLVM `vm::run` body is about 50.5 KB, with 10,577 statically
disassembled instructions including cold/error paths. QBE properties has
8.21% self samples in out-of-line generated ownership glue, compared with
2.44% LLVM; LLVM can inline and simplify much more of that work.

**Next experiment:** compare emitted hot paths for bytecode reads, stack
push/pop, frame reload, and property lookup; preserve overflow/bounds/trap
semantics while eliminating repeated materialization, ownership, and checks
whose facts remain valid. Price QBE-specific inlining or glue changes against
those paths instead of pursuing a generic allocator rewrite first.

### 4. Changing collectors does not explain most of the VM gap

Current RC LLVM / current GC LLVM instructions have a **1.084× geomean**
across the 13 VM rows. GC LLVM is still **5.19× Zig's instructions**. Switching
collectors would save about 7.8% on average under this protocol; it would
leave most of the gap intact. Individual rows vary: RC is better on equality
and strings, and costs about 21% more instructions on instantiation.

The tree counter geomean is **9.64× LLVM instructions versus Zig**. A tree
binary_trees LLVM profile attributes 19.28% to out-of-line generated RC glue,
7.27% to RC runtime functions, and 10.94% to library/other symbols. Its guest
functions also contain inlined ownership work. `evaluate`, `execute`,
`set`, environment-slot writes, function calls, allocation and sweeping are
spread across the remaining work. Tree work needs a separate source/lowering
experiment and inclusion in future performance coverage.

### 5. Peak memory still has a premium

Peak RSS was measured once per selected full-size case with GNU time;
these are diagnostic samples, not a memory acceptance distribution.

| VM script | LLVM MiB | QBE MiB | Zig MiB | Rust MiB | Go MiB |
|---|---:|---:|---:|---:|---:|
| binary_trees | 26.85 | 27.04 | 15.03 | 17.53 | 33.76 |
| closures | 8.48 | 8.70 | 2.38 | 4.41 | 9.55 |
| instantiation | 7.81 | 8.05 | 1.91 | 3.73 | 8.89 |
| string_equality | 4.38 | 4.65 | 0.81 | 2.49 | 2.48 |

VM binary_trees is about 26.9 MiB LLVM versus 15.0 MiB Zig, approximately
1.79×. The old September 23 report quoted 68 MiB mylang; it used another
compiler and port source, so that is historical context rather than a matched
before/after claim. This audit's call-heavy profiles support prioritizing
ownership and emitted hot-path work over heap size as the first lever.

## Branches and worktrees

The starting repository has **586 local branches**, **427 reachable from
main and 159 not reachable**, plus **294 existing worktrees**. Nineteen
worktrees have tracked changes. The inventory records paths, locks, dirty
files, tips, ancestry, and source paths changed since each merge base.
No Git remote is configured, so this is an audit of locally available refs.
The two worktrees created for this audit are excluded from those counts.

| Branch or group | Result | Performance implication |
|---|---|---|
| All 22 `claude/rc*` branches | Already in main | Includes glue, allocator/slabs, writeback moves, scopes, loops, sites, LLVM aliasing, Lox VM changes and the RC default. |
| All 9 `codex/d9-lox*` branches | Already in main | Accepted source work is in the optimized migration; the upvalue accessor lane records a rejection. |
| `codex/next-runtime*` | 19/20 in main; the remaining images branch changes only evidence/docs | The unmerged ref is not an unmerged runtime improvement. |
| `perf/*` | 35/39 in main | Remaining refs are the check report, a docs-only integration tip, and the two paused schematic lanes below. |
| `codex/eda-friction-large-return-glue-20261002`, `50286aca` | Unmerged; cherry-picked alone to `7b283ab2` for this audit | Lox binaries are byte-identical to main on both backends, including `--whole-program --no-cache`. Five named focused tests plus 12 harness tests pass. No Lox speedup. |
| `codex/eda-friction-merge-repairs-20261002`, `0b333f67` | 41 commits ahead of main, zero behind | Pending compiler/stdlib/correctness/checking/memory work. It contains the same cleanup patch as `023b9d02` (equal stable patch ID), and empty-constructor work. The whole candidate was not benchmarked here; do not claim a Lox runtime win from this audit. |
| `codex/compact-qbe-delta-20260923`, `9996f456` | Old branch, 129 ahead / 1,678 behind | A pre-emission cache-key experiment affects rebuild work. Adapt and qualify separately if needed; it does not address the measured interpreter execution gap. |
| `perf/schematic-6-output-emission`, `377f2964` | Paused; its report explicitly has no performance measurements | SVG emission work, not the Lox path; not a qualified performance merge. |
| `perf/schematic-8-invocation-cache`, `0913e935` | Paused and incomplete; report says no gate or measurements | Host invocation/build reuse, not execution of these already-built Lox binaries. |
| `dot/lox-rust-runtime-*`, `dot/lox-zig-runtime-20261002`, `dot/lox-go-runtime-20261002` | Unmerged reference-port work | Improves competitors/reference ports, not mylang. Some changes are reverted. Consider benchmark-branch integration independently. |
| `bench/lox-*` | Benchmark assets are on separate historical branches | The measurement harness still defaults to a September 23 compiler pin. Refresh the evaluation pin and current source migration before relying on that report. |

Tracked worktree changes also matter. The runtime-layout worktree retains an
acquisition-order draft; equivalent source-before-copy ordering is already
present in main's generated glue. LLVM affine/literal worktrees retain drafts
that differ from the accepted structural-induction-only lowering. Old D9
box-borrow/lazy-box worktrees retain prototypes. None comes with a newly
demonstrated Lox win in this audit, and none should be merged merely because
its branch/worktree name mentions performance.

The user's original checkout remains `local-reasoning/integration` at
`acbee603`, **1,678 commits behind main**, with its existing uncommitted
changes. Its local compiler binary is dated September 21, 23:51 EDT and has SHA-256
`693a83ef57914bc2b9de3c5133d043c53d21183432568e5407e1043fa1f6708c`.
It is not the freshly built audited compiler. Updating an evaluation to use
existing main is a separate, immediate way to pick up already-landed work.

## Validation and evidence

Main ReleaseFast install succeeded: 19/19 steps. Guardian passed 88 checks
in its declared diff-scoped mode: zero modified Zig files in scope and 38
whole-tree checks. The isolated cleanup candidate's focused gate passed
17/17 tests (five matching names, 12 unnamed harness blocks). No baselines or
waivers changed. All completed measurement sweeps match expected output and
verify input/executable hashes after execution.

The initial A/B counter sweep was stopped when exact binary identity made
further timing redundant. Its completed rows are retained as **partial**
diagnostics, not acceptance data. Forced uncached whole-program builds then
independently confirmed the same executable hashes:

| Backend | Main, ordinary whole-program, cleanup candidate, uncached cleanup |
|---|---|
| LLVM | `993fa8ed2daf8a0e43018f559a8f97a53fa72bb977908dda27558a6ffe4fa3fd` |
| QBE | `55063355c019d0f33131d7dbc01586e2ee4dbcaa112d72b336e6817dea9885de` |

Zig ReleaseFast, Rust release, Go and mylang have different host checking
policies and value representations. Output/collector equivalence on this
corpus establishes matched Lox work, not identical host-language safety
semantics. The focused diagnostic below provides additional checking context.

A separate three-round counter sweep of fib, instantiation, properties, and
string_equality compares the same source with Zig ReleaseSafe. LLVM uses
**2.90× the checked Zig instructions** across these four cases, with a range
of 1.95×–4.30×. The port passes `std.process.Init.gpa` to its runtime; this
Zig toolchain's `std/start.zig` selects `SafeAllocator` for ReleaseSafe and
`smp_allocator` for this ReleaseFast build. This comparison therefore includes
allocator changes as well as arithmetic/bounds checks. Different checking
policies account for part of the baseline gap, but a substantial gap remains.

| VM case, calibrated tier | Zig Safe/Fast instructions | LLVM/Zig Safe instructions |
|---|---:|---:|
| fib | 1.77× | 2.78× |
| instantiation | 1.71× | 4.30× |
| properties | 2.19× | 3.02× |
| string_equality | 1.83× | 1.95× |

Raw evidence is at
[/home/epentland/ai/canopy/evidence/lox-performance-audit-20261002](/home/epentland/ai/canopy/evidence/lox-performance-audit-20261002/).
It includes every sample, system and source identities, build commands, profiles
and assembly, ownership-site reports, binary equivalence, and the complete Git
inventory and exact guest executables. All **93 payloads** are sealed by
[`MANIFEST.sha256`](/home/epentland/ai/canopy/evidence/lox-performance-audit-20261002/MANIFEST.sha256),
whose SHA-256 is
`94bd7e6d817d832ec3c46003709436523be26a7df4395bf206e3bc0d98313dd2`.
The
[measurement scripts](../../experiments/lox-performance-audit-20261002/README.md)
remain in the audit branch. No language implementation or main ref was changed
by this audit.
