# Current-fastest LLVM 1.10 reporting

`goal110.py` implements the new LLVM campaign independently of the historical
frozen-target comparator. It reads verified `expanded-v2` **raw reports**, including
`.json.gz` archives. It never consumes old comparison intervals as new acceptance
proof. The anchor is the complete recorded starting six-arm setup; for this
campaign it is `candidates/final-730a86e6-releasefast-20261003.json.gz`.

Every measured case/size gets six medians and ratios to that row's current minimum.
For each MyLang backend, five competitor intervals use the same resampled round
indices within that session, dividing the two resampled medians. Self intervals
are exactly `[1, 1]`. A below-threshold observation has state `P` when every upper
bound is at most 1.10, or `I` when uncertainty crosses 1.10. Decisions use full
precision; four decimals are only display formatting. QBE states are informational.

Analyze observations without declaring confirmation:

```sh
python3 benchmarks/runtime/goal110.py analyze RAW_A.json \
  --anchor benchmarks/runtime/candidates/final-730a86e6-releasefast-20261003.json.gz \
  --evidence-id B1-screen --output /tmp/B1-screen-goal110.json
```

Analyze two independent normal sessions:

```sh
python3 benchmarks/runtime/goal110.py analyze RAW_A.json \
  --anchor benchmarks/runtime/candidates/final-730a86e6-releasefast-20261003.json.gz \
  --evidence-id B1 --confirmation RAW_B.json --checks CHECKS.json \
  --output /tmp/B1-goal110.json
```

`--check-artifacts` additionally verifies live compiler receipts, tools, guest
binaries and sources. Archived evidence remains analyzable without live artifacts;
that limitation is recorded. All outputs require unique names and include a
companion Markdown proposal. Existing files, inputs, and the canonical
`RUNTIME_110_GOAL.md` cannot be overwritten. The coordinator owns dashboard edits.

Both confirmation sessions require at least **15 rounds, 3 warmups, an explicit
ReleaseFast compiler build, six arms, full checksum qualification, identical
case/size/input contracts, different session IDs, and nonoverlapping recorded
measurement periods**. Independent calibration may choose different iteration
counts. Same-session reduced-arm reports, smoke runs and five-round screens
cannot establish confirmation. A failure in either session prevents `C`; two
passing sessions without a correctness receipt remain `P`.

Session compatibility checks the candidate ID, production source bytes, compiler
and runtime assets, every guest hash, benchmark/harness source bytes, compiler
versions and hashes, actual guest backend/optimization flags, build environment,
ISA probe and wrapper policy. Paths for source roots, tools, guests and private
caches are normalized; flags and file identities are retained. Documentation-only
Git commits may have different source SHAs when all production inputs and
compiler/guest bytes match. Production inputs are `src/`, `vendor/qbe/`,
`build.zig`, `build.zig.zon`, `.zigversion`, and `.qbeversion`; `CONTRACT.md` files
remain pinned semantic evidence. Ordinary benchmark Markdown is documentation,
while benchmark programs, inputs, oracle and harness code stay
pinned. The starting Rust/Go/Zig compilers and executable bytes, clock object,
benchmark inputs and guest/ISA policy must match the anchor. A Debug compiler can
produce observations but cannot establish confirmation.

The checks-v1 correctness receipt is a **coordinator-reviewed attestation** of the
linked outcomes and their scope, not an independently authenticated test result.
The tool validates identity, declared status, scope and hashes; it does not parse
heterogeneous historical log formats to prove the declared pass. The coordinator
must read each linked result and verify passing outcomes, applicable artifacts,
coverage and recorded limitations before issuing the receipt.
Take `execution_identity_sha256` from an initial analysis (no checks required),
and bind successful existing qualifications, nearby-input holdouts and relevant
repository gate logs to the exact production/compiler/guest/policy identity:

```json
{
  "schema": "mylang-runtime-goal110-checks-v1",
  "status": "pass",
  "execution_identity_sha256": "SHA256_FROM_ANALYSIS",
  "coverage": ["mutate_nested", "bytes_scan", "string_search"],
  "checks": [
    {"name": "expanded checksum qualification", "kind": "qualification", "status": "pass",
     "path": "/absolute/path/qualification.json", "sha256": "STORED_FILE_SHA256"},
    {"name": "nearby input semantic holdouts", "kind": "holdout", "status": "pass",
     "path": "/absolute/path/holdouts.json.gz", "sha256": "STORED_FILE_SHA256"},
    {"name": "repository correctness gates", "kind": "repository", "status": "pass",
     "path": "/absolute/path/validation.json", "sha256": "STORED_FILE_SHA256"}
  ]
}
```

All named checks must pass and each referenced file's stored bytes must match.
Qualification and holdout kinds are mandatory. Receipt coverage must contain the
analysis coverage and only known cases. For final completion, receipt coverage
must include all 40 cases and a repository gate check. Existing applicable receipts
may be reused when their production/artifact scope is unchanged; reporting does
not trigger new builds. The coordinator must substantiate the declared pass and
scope from the linked outcomes. Failed or irrelevant logs cannot be made passing
by the tool itself. Retain those outcomes in the campaign progress log.

Seed a dashboard with B0 and merge focused analyses:

```sh
python3 benchmarks/runtime/goal110.py dashboard /tmp/B0-goal110.json \
  --output /tmp/dashboard-initial.json
python3 benchmarks/runtime/goal110.py dashboard /tmp/B1-goal110.json \
  --previous /tmp/dashboard-initial.json --output /tmp/dashboard-B1.json
```

The initial analysis must cover all 80 cells. Each update replaces all six ratios,
the absolute winner, both backend states and evidence ID for its measured rows
together. Unmeasured rows retain their values and evidence. Reusing an evidence ID
is rejected. Every stored analysis is recomputed from its hash-checked raw inputs
when merging, so editing an analysis summary cannot manufacture confirmation.
The JSON preserves every update and report/check hash; its companion Markdown
contains a proposed speed table and evidence register. Counts distinguish
observations, confirmation, inconclusive, stale and reopened LLVM targets.

Mark existing confirmations stale immediately after production integration,
before timing the changed source:

```sh
python3 benchmarks/runtime/goal110.py dashboard \
  --previous /tmp/dashboard-B1.json \
  --current-source-revision FULL_COMMIT_SHA --source-root /path/to/integration \
  --output /tmp/dashboard-after-integration.json
```

This reads the committed production bytes with `git archive`, without compiling.
An update that changes the saved current production source requires this explicit
revision argument; importing an older report cannot silently reset a stale dashboard.
Documentation-only source changes keep confirmations current. Production or
compiler/guest/policy changes stale prior `C` cells to `S` while preserving their
measurements. A newly observed above-threshold LLVM cell with earlier `C` evidence
reopens to `R`. The proposed dashboard names the latest complete integrated run
and explicitly marks mixed production evidence. A collection of confirmed focused
subsets never establishes final completion: `goal_complete` requires two full
normal sessions, correctness/holdout/repository receipts for the same artifact
identity, all 80 LLVM cells current and confirmed, and no newer complete run
superseding that full acceptance. QBE performance regressions need same-session
before/after absolute measurements and coordinator investigation; a normalized
ratio change alone is not an absolute regression.

Run the focused tooling tests without a build or timed guests:

```sh
python3 -m unittest discover -s benchmarks/runtime -p test_goal110.py
```
