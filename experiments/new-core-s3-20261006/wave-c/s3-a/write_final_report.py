#!/usr/bin/env python3
"""Put the checked final qualification first while retaining development receipts."""
import json
from pathlib import Path

AREA = Path(__file__).resolve().parent


def main():
    qualification = json.loads((AREA / 'qualification-final-01.json').read_text())
    assert qualification['qualified']
    report = AREA / 'REPORT.md'
    history = report.read_text()
    assert history.startswith('# S3-A: application admission and measurement foundation\n')
    old_steps = '\n'.join(f"| `{result['step']}` | {result['command_seconds']:.2f} s | Pass; exit 0, successful summary, RSS inspection |"
                          for result in qualification['full_old_gate']['results'])
    compiler = qualification['compiler_sha256']
    table = (AREA / 'all40-combined-final-table-03.md').read_text()
    final = f'''# S3-A: qualified standard library and applications

The combined application package qualifies on frozen source
`{qualification['source']}`. All 40 rows pass both new/old and new/Zig ReleaseSafe
limits at 4096 and 64, with zero misses. Standard-library imports, literal split
fidelity, strict native semantics, Core, conformance and the full old-core gate
also pass. This is the A handoff; the coordinator still owns final integrated
S3-X qualification and the section 7/S4 decision.

`qualification-final-01.json` checks the receipts and records SHA-256 provenance
for the source inputs, fresh compiler, corrected oracle/QBE, reference workload
sources/binaries, all 80 measured old/new binaries and all 40 fresh LLVM modules.
The installed new compiler SHA-256 is `{compiler}`. It was built from this
worktree's source; guests link their independent Core runtime and the benchmark
clock port. No copied new compiler or old-runtime object link is used.

| Final combined check | Result | Evidence |
|---|---|---|
| Exclusive own-source install | 2.33 s actual command; all three build slots held; no other-build wait | `logs/core-trace-combined-11.*` |
| Core64 | 276/276; exactly 64 verdicts; 125.95 s; maximum shard 52.87 s; maximum test RSS 249 MiB; no overrun | `trace-combined-core64-review-04.json`, `logs/trace-combined-test-core64-06.*` |
| Full strict conformance | 1518 matching in each debug/release mode; zero mismatch/refusal; leak/fact verification; 52.00 s | `logs/trace-combined-full-conformance-06.*` |
| All40 performance | 80 size cells pass both ratios; strict four-program checks; 283.10 s after admission | `all40-combined-final-03.json`, `logs/all40-combined-final-03.*` |
| Imports/original/split native | 137 exact native executions; old/debug/release/verify; zero leaks, nonzero statuses or unexpected output; 54.58 s | `qualification-combined-final-02/summary.json` and per-build/native records |
| Pinned managed split | Seven exact lines in all four modes; zero exit and empty leak stderr; 15.26 s | `split-qualification-combined-final-03/summary.json` |
| Split-key transformation sweep | Fresh cursor source: 50 sources, 750 exact comparisons, zero mismatches; 145.83 s | `fuzz-split-cursor-50-02/summary.json`, `cursor-qualification-01.json` |
| Original35 instructions | All 343 actual definitions; exactly six approved scalar stores plus two trace calls; all remaining instructions/operands/CFG/phis/traps and site metadata match; full module remainder exact after trace declaration replacement | `combined35-final-04/summary.json`, all complete before/after LLVM and raw diffs |
| Fixture fidelity/tool checks | All five literal extractions unchanged; parser/registry smoke passes; Python syntax and diff checks pass | `split_apps.py --check`, `logs/final-tool-smoke-02.txt`, `logs/llvm-parser-smoke-01.txt` |

The combined old gate is required by the character package's SPEC update. The
final four-step run held both gate/build slots for each step on this frozen source:

| Old gate | Actual command time | Result |
|---|---:|---|
{old_steps}

`old-gate-combined-final-03/summary.json` retains each exact command, source,
exit status, wall/admission time, successful summary, shard RSS and overrun
inspection. Its old-unit/QBE times are separate from the Core compiler/test
limits. Default Core sharding remains eight; explicit 64-shard qualification
keeps the native fixture work below the 90-second shard limit. The trace
package's functional-but-over-time Core32 receipt is retained alongside its
qualified Core64 replacement.

The first combined old run failed NATIVE-ZIG-CACHE-4 because the inherited gate
tool placed TMPDIR inside the project's .zig-cache; the unit assertion requires
private scratch outside it. That 945.07-second failed run is retained as
`old-gate-combined-final-01`. A second tool-only correction put scratch under
.mylang-cache, which made two incremental-test harnesses exclude every copied
source by an absolute-path cache filter; that 820.59-second failed run02 is also
retained, with all 3002 unit tests passed. The final tool uses unique private
/var/tmp scratch, avoiding both cache ancestors; both exact failed incremental
commands pass their focused scratch preflight. Fresh four-step
run03 above qualifies. No compiler/runtime/test changes were made for these
scratch corrections.
The original combined35 checker also miskeyed dotted LLVM helper names by
searching the whole function body. Its incomplete run03 is retained; the corrected
header-anchored parser accepts full LLVM symbols, rejects duplicate headers,
and proves all 343 definitions in run04. Neither tool correction changed
the compiler/runtime or required a repeat of already valid performance samples.

The generic repairs are whitespace cursor fusion with borrowed lookup and owned
insertion keys, exact small-dictionary span probing and scalar value stores,
trusted byte-index normalization, complete scalar-use fusion with checked text
diagnostics/direct short append/guarded ASCII decoding, bounded trusted cursor
emission, and compiler-owned preserving error-trace twins. Reference algorithms,
input distributions, timed work and checksums remain unchanged. The frozen IR,
ownership implementation and tests/lang are unchanged from the qualified base;
module-interface-v5, check-summaries-v6, mutation-v2 and first-64 aggregate masks
remain intact. The sibling reports under `s3-packet`, `s3-char` and
`s3-packet-trace` retain their focused authority, diagnostics, ownership and
native sweeps. These packages were qualified before their A merges; combined
Core/conformance and fresh all40/native receipts establish the final composition.

Every performance pair below is 4096/64, in cycles per unit. Units and iteration
counts are the inherited S1/S2 registry; application units are dataset elements.
Timing uses CPU10 only, seven shuffled interleaved rounds, and subtraction of
three one-iteration startup medians. Every sample requires zero exit, exactly
two integer stdout fields, matching four-program checksums and one positive
finite cycle counter. Both CPU locks are acquired external EDA first, S2 second.
Neither size nor either ratio is averaged away.

{table}

The first combined full sweep and its paired repeat remain failed evidence:
word64/Zig 1.103086/1.103926 and packet64/old 1.101765/1.106961. Profiles and exact
LLVM/assembly comparisons guided the cursor and trace repairs; neither failure
was waived or overwritten. The final independent full sweep above passes.

Normal commits use the whole-tree Guardian gate. Its source/evidence receipts
and local feedback candidate are retained; the coordinator owns the required
shared FEEDBACK.md append/commit. No pushes or integration/main merge are made
by this package owner. Final integrated operation-count auditing, coverage,
nine-kind 200-source matrix, separate split-key 200 sweep, full conformance,
all40 and old gates remain the coordinator's S3-X work.

## Retained qualification history

The following checkpoints preserve admission receipts, real failures, profiles,
approved repairs and their package-level qualifications. Pending statements
describe those earlier checkpoints; the combined qualification above is final.

'''
    history = history.replace('# S3-A: application admission and measurement foundation\n',
                              '## Application admission and measurement foundation\n', 1)
    report.write_text(final + history)


if __name__ == '__main__':
    main()
