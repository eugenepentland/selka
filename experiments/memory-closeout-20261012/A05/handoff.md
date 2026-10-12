# A05 handoff (qualification in progress)

Base is `fbfcaa7a923186a8e773c3760f81c10aa345a432`; worker branch is
`codex/memory-closeout-20261012-A05`. No peer merges, pushes, default promotion,
legacy-RC deletion or Guardian feedback edits were performed.

## Scope and inventory

Owned remaining 13 standard modules and their corresponding fixtures, runtime
`core_dict.c`, `core_sort.c`, `core_io.c`, `core_host.c`, `core_durable.c`.
Coordinator additionally reserved `src/core/durable_test.zig` and the seven
resource/persistence guest fixtures listed in `migrations.json`. The export inventory contains all 120 public
 declarations (95 functions, 25 types); every function has at least one explicit
source reference in the fixture map. A source reference is not execution proof.
`exports.json` preserves C0 signatures/source hashes and records ownership
contracts; `inventory.md` gives module totals.

## Commits and proposed implementation

- `27737ea037cec92ee7b722c0d6f15354dd78e4df`: borrowed provider lifetime marker,
  a no-op lifetime use with no count/storage ownership. Requested and approved by
  coordinator/A07 for dependent-resource cleanup. Guardian 88 checks passed.
- `278538395`: library snapshot migrations, fixtures, inventory and C0/overlay
  evidence. Guardian 88 checks passed; source resource/scalar blockers remain.
- `a34f073ef`: registered owned durable native fixture. Guardian 88 checks passed.
  The focused registered test passed 1/1; raw log is retained in evidence.


`memo` now copies retained keys/values, returns independent hit values, and copies
borrowed error details. `persistent_memo` copies values retained in temporary
record/entry lists. `durable` copies persistent record fields and state snapshots,
and validates its borrowed output path in a helper without an intermediate copy.
These preserve existing independent-snapshot semantics under checked ownership;
no allocation reduction is claimed. Dynamic error-message functions declare
managed allocation because independent text can allocate.

Current pool/time/random and registered memo fixture aliases use explicit
`.copy()`. The pool mutation argument is bound before the mutable loan. Original
and migrated source hashes are recorded in `migrations.json`.

`durable_test.zig` adds an owned-ABI variant of the registered native fixture.
The ordinary fixture is retained. Owned fixture adaptation transfers acquired
lock pointers out of their result box, transfers root providers, and uses direct
destruction. The existing fault/SIGKILL/directory-ownership scenarios are preserved.

## Evidence recorded so far

C0 full installation was rebuilt by A09 on this host. Compiler:
`../mylang-memory-20261012-A09/.tmp/memory-closeout/A09/C0/bin/mylang`, SHA256
`324e0023f643e4949f72086d13744054f4b5bf7a38975822807f1d74ead2ec4a`.

- `evidence/C0-check.json`: deterministic env/filesystem/file/clock/entropy source
  checks pass; memo borrowed message and network generic acquisition refuse.
- `evidence/C0-independent-check.json`: cache record/hash checker passes;
  denied network acquisition still refuses.
- `evidence/overlay-check.json`: migrated memo and cache record checker pass;
  durable scoped fallible lock is refused. Overlay is labelled explicitly and is
  not an integrated compiler qualification.
- `evidence/native-durable.json`: the owned native runtime passes all existing
  short/zero-write, fsync/uncertain-publication, path/listing, actual SIGKILL,
  concurrent-writer and lease cleanup checks. Runtime hash
  `d5c393bd561ad2ca363d983209b187d4d823e5f2de7e13312a7f6ce6f960f36e`, binary hash
  `a7a002f173899fdc1365ecbd838726592cc32c8ca7eb1352115a7f008df949e8`.
  Leak checking is clean and no legacy RC symbols occur. This is native evidence;
  it does not qualify source resource lifetimes.

Fresh release runs pass for all five remaining mandatory migrated standard
fixtures: sort, math, integer_extrema, pool, time_random. Expanded math, cache-record,
container replacement/pop/copy/set, deterministic filesystem/environment/clock/entropy,
and migrated managed-value memo samples also pass. Every counted passing run has
zero RC events, zero exit-live managed bytes and no legacy LLVM/symbol entries.
The exact binaries, source files, counters and compiler identities occur in
`evidence/*release*.json` and `evidence/C0-independent*.json`; raw counters are
preserved under `evidence/raw`. These are baseline/overlay results, not C1.

The library-only guest fixtures now have generated main adapters preserving their
public zero-argument test assertions; the two provider-argument tests receive
explicit deterministic stand-ins. `guest-overlay-check.json` retains all refusals.
An earlier direct-check probe in `guest-migration-C0.json` encountered E_MAIN on
library-only sources; it is not counted as an ownership defect.

Raw guest outputs/counters/LLVM/binaries are under `.tmp/memory-closeout/A05/`.
No historical reports are overwritten. Initial per-case admission runs were
canceled only while queued and resumed in bounded batches; canceled missing cases
are not counted as source failures. Final C1/mode qualification remains pending.

## Open correctness blockers and owners

- A07: `list(values.keys())` and `list(values.items())` compile through a borrowed
  frontend field extraction and refuse. `samples/containers.my` is the reproducer;
  A07 has the reserved frontend fix. `containers_core.my` independently exercises
  replacement/pop/copy/set cleanup without dropping the refused snapshot case.
- A07: `network.connect` reaches `acquire_resource` at standard network line 71
  and refuses. `samples/network.my` includes read/write/close and bounded local
  loopback provider cleanup; `network_denied.my` is the minimal deterministic
  acquisition failure. Source resource ownership must be handled before native
  helpers are admitted.
- A07: `durable.run` / `persistent_memo.call` lexical `with try lock_directory`
  needs provider-lifetime propagation and audited `myl_core_durable_access`
  admission. `samples/storage.my` reproduces. `runtime-contract-audit.md` records
  complete native contracts and limitations; no helper whitelist was added here.

- Coordinator: generic scalar `.copy()` inside a record constructor aborts the
  compiler at `sema_expressions.zig:1109`. `samples/scalar_copy.my` is the 10-line
  minimized reproducer; full stack is `evidence/scalar-copy-C0.stderr`. This blocks
  the mandatory full memo fixture, while enum and nested-record instances check.
- A07: compiler-generated byte repetition loop refuses `b"a" * 1` in the original
  application-cache hash oracle. `samples/byte_repeat.my` preserves the minimal
  case; confirmed refusal is in `evidence/byte-repeat-C0.json` and the original
  parent fixture refusal is in `evidence/guest-overlay-check.json`.
- A07/coordinator: capability-field aggregates and returned TextFile Results in
  `tests/lang/capability_fields.my` / `rc_contract_results.my` remain exact C0
  originals and explicit blockers. They were not weakened or rewritten away.

All owned library exports and these API failures remain in the release inventory.
Correctness refusals are blockers, not measured tradeoffs. Integrated C1 and its
five requested build modes remain required; any C2/C3 changes must be requalified.

## Reproduction

Source the shared development environment. `qualify.py --admit` owns admission
per compilation. For source-only probes, run the harness under one build slot
without `--admit`. `native_runtime.py` owns admission for its native compilation.

```bash
python3 -B experiments/memory-closeout-20261012/A05/qualify.py \
  --compiler "$COMPILER" --zig "$ZIG" --output "$OUTPUT" --admit \
  --modes release debug verified optimized-debug no-facts
python3 -B experiments/memory-closeout-20261012/A05/native_runtime.py \
  --zig "$ZIG" --output "$NATIVE_OUTPUT"
scripts/build-slot.sh build "$ZIG" build test-core \
  -Dtest-filter='zero RC durable native' -j"$MYLANG_DEV_JOBS" \
  --maxrss "$MYLANG_DEV_MAXRSS"
```

The complete coordinator verification and Guardian checks remain required on
final inputs. No final milestone is claimed by this in-progress handoff.

## Guest migration integration

The separate guest migration changes borrowed payload returns to explicit copies,
independent cache/pool/builder aliases to `.copy()`, and dependent capability
locals to lexical scopes. Application numeric formatting binds its temporary
before encoding. The simulated-clock shared-reading assertion uses an ordinary
borrowed helper (coordinator-approved), because capabilities are not copyable.
Every original test assertion is preserved; capability aggregate and returned-file
fixtures remain unchanged. `migrations.json` records C0/current hashes, copy counts
and changed-line counts for all seven assigned files and two stdlib fixtures.

The source-only generated-main batch still refuses at library/compiler blockers;
these source migrations are integration inputs, not guest pass claims.
