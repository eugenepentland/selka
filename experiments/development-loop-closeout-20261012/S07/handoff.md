# S07 golden preparation handoff

Base: `fbfcaa7a923186a8e773c3760f81c10aa345a432` (C0).
Branch: `codex/dl-closeout-20261012-S07`.
Owned implementation: `test/golden_parity.zig`. No shared build, Guardian,
configuration, source, runtime, ownership, or component-harness files changed.

## Change and preserved controls

The golden harness interns exact source byte payloads into run-local scratch
`src-<first-index>/case.my` files. Subsequent identical payloads borrow that
prepared path. It still invokes the current Core/LLVM compiler for every case,
passes every replayed option, and compares each recorded outcome independently.
It never retains a test verdict. A new process gets a new temporary tree and
source map. Corruption, cold/bootstrap, and allocation-failure harnesses are
untouched.

Every case retains its own new mutable `work-<index>` directory with freshly
written `greeting.txt` and `lines.txt`. Source directories and compiler cache
remain outside that working directory. The source basename remains `case.my`;
only its already incidental scratch ancestor is shared for identical bytes.
Diagnostic absolute paths were already excluded from golden signatures; exit
status, clean stdout, and runtime diagnostic code comparisons are unchanged.
The checked corpus does not inspect `case.my`, `src-`, `__file__`, or argv.
Relative file effects act on fresh working directories. Two added focused
regressions prove exact-byte reuse/change separation and mutable fixture
isolation after a preceding case overwrites a fixture and creates a file.

## Exact corpus and work evidence

`audit_corpus.py` inventories all checked-in golden documents using the fixture
map and retired keys from the harness. `corpus-manifest.tsv` records all 604
corpus/key/classification/entry-SHA256 rows, including skipped entries. Its
SHA256 is `d6f7becc53109d2560ed40de4e2c5fd2a27a6b58c33ca8a682163bbd00ba655b`.
`corpus-work.json` also records each complete document's SHA256.

| Quantity | Before | After |
| --- | ---: | ---: |
| Classified cases | 604 | 604 |
| Checked cases | 222 | 222 |
| Checked source / repository fixture | 167 / 55 | 167 / 55 |
| Skipped docs / unmatched / data / retired | 27 / 345 / 1 / 9 | 27 / 345 / 1 / 9 |
| Live compiler invocations | 222 | 222 |
| Source files written / source directories | 222 | 165 |
| Source bytes written | 90,182 | 66,752 |
| Fresh mutable work directories | 222 | 222 |
| Mutable fixture file writes | 444 | 444 |

This removes 57 source preparations (25.7%) and 23,430 written source bytes
(26.0%). These are deterministic work counts, not a wall-clock speed claim.
The unchanged existing coverage minimums and outcome assertions remain intact.

No prepared artifact is persisted or authenticated as a compiler producer.
Scratch source disk use decreases by 23,430 payload bytes and 57 files/directories
before filesystem overhead. The run now retains 66,752 source-key bytes, 165
absolute paths, and hash-table storage until cleanup; before, one source path
was freed after each case. This additional bounded host memory and hashing cost
requires paired RSS/cold-cost qualification. No measured memory delta is claimed.

## Component audit and dependencies

`selfhost/test_components.py` has 18 tests exercising cold private fake seed
archives, source/embedded input/toolchain/seed changes, corruption and missing
artifacts, failed publication, reproducibility, abandonment/recovery, malformed
receipts, and seed digest authentication. Per-test preparation is intentionally
mutable. Sharing its caches, seed receipt, archive, or working directory across
tests would weaken those controls; it is unchanged.

`selfhost/test_component_native.py` performs debug and release tests with
`--no-cache --verify-facts` and `MYL_CORE_LEAKCHECK=1` for both test-index and
cache-plan. It builds each live release component with `--no-cache`, runs its
oracle, then runs the installed authenticated component's oracle. Those fresh
builds and authentication remain unchanged. No component ownership transfer was
requested. Further component optimization awaits owner-approved measurements.

The golden declared fixture closure and discovery are unchanged: all golden
JSON documents (including directory membership), 14 named repository sources,
selected compiler/Zig and their existing environment/authentication dependencies.
S03 received the file claim; S09 received the component control audit. S04 needs
no producer adapter for ephemeral source files.

## Validation and qualification

Pinned Zig: `0.17.0-dev.1683+5ceec001b`, resolved by
`/home/epentland/.local/bin/zig`. Native checks use `scripts/build-slot.sh build`,
private worktree `.zig-cache`, disk `.tmp/S07`, and shared
`/home/epentland/ai/canopy/.zig-global-cache`. No CPU pinning or timing admission
was requested. Raw commands/output are `focused-preparation.log` and
`full-golden.log`. Operational durations in those logs are not isolated timing.

Focused command: `zig build test-golden -Dtest-filter='golden preparation' --summary all`.
Result: PASS, 2/2 tests and 20/20 build steps. Guardian diff-scoped checks passed.

Full forced golden command: `zig build test-golden -Dtest-rerun=true --summary all`.
Result: PASS, 4/4 tests and 20/20 build steps; zero mismatches. Live counters
confirm 222 executions, 165 source writes, 66,752 source bytes, and 222 fresh
work directories. Reported action MaxRSS was 73 MiB operationally; no matched
baseline or isolated memory delta has been qualified. Formatting and diff checks
passed.

Full integrated verification and paired cold/warm latency/RSS qualification belong
to S10. Requested paired command selects the unchanged corpus test using
`-Dtest-filter='checked-in golden corpora'` (one named Zig test, 222 case launches)
under exclusive timing after matching artifact preparation. Full root changes
from two named Zig tests to four because it adds the two preparation regressions.
No performance ratio, p95, cold/RSS acceptance, or overall DL closeout is claimed.
