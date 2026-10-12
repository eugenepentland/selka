# Local main integration checkpoint

Status: final verification running; local `main` has not yet advanced.

The user requested merging the current work before continuing performance work,
and explicitly selected the local main / development line. Its starting commit
is `4892aaba4e3fa9076cc5f2c8590f3f2f89500cb9`. GitHub's unrelated Selka `main`
snapshot is outside this merge.

The feature checkpoint is `5b2da3a90`; integration commit `bdb22087a` retains both
histories and resolves four files: build input registration, verification
coordination, platform qualification comments, and Core test registration.
All newer verification telemetry/cache identities and external component
pin/archive identities are retained. Independent review found no issue in these
resolutions.

The initial main-first hook encountered Guardian's 64 MiB Git-output bound on a
222,286,870-byte evidence diff. The feature-first merge reduced that diff to
41,127,648 bytes and passed the normal 88-check hook. `merge-identity.json` proves
that both directions produce exactly the same resolved Git tree. No check or
hook was disabled.

The complete first gate on `bdb22087a` ran with stable inputs and finished with
one failed step: formatting of `test/core/textgap_snapshot.my`. All runtime and
compiler test steps passed. Commit `0301b1b3c` adds the missing blank separator
and updates this evidence adapter for main's `verification-v2` report path.
The underlying first-run report was recovered unchanged from that path.
The second complete gate on `0301b1b3c` passed formatting but failed two native
tests (numeric fixtures and live iteration) that passed the first run. Neither
wrapper printed child diagnostics, so those diagnostics have been added without
changing assertions. Both tests then passed one focused run and 12 concurrent
repetitions; see `diagnostics-01/`. The cause remains unproven. A third complete
gate will run with failure capture enabled before main advances.

Both gates use the unchanged qualified component pin and archive recorded in
`../component-route.json`; no immutable bootstrap seed was repinned. This
checkpoint makes no claim that default promotion or legacy guest RC retirement
is complete.

Five existing documentation edits in the local-main checkout were backed up
before integration. The merge will preserve those edits. Verification runs in
the isolated integration checkout, not over that edited checkout.

## Performance state at checkpoint

These are independent short screens of worker artifacts, not final results for
one integrated compiler. Lower ratios are faster.

| Workload | Small | Large | Comparator |
| --- | ---: | ---: | --- |
| String splitting, SPLIT05 | 0.8599 | 0.9610 | Rust |
| CSV aggregation, CSV05 | 0.9677 | 0.9032 | Zig ReleaseFast |
| JSON transformation, JSON09 | 1.0798 | 1.0668 | Rust |

JSON10's direct leaf cleanup passed 144 native qualification checks, but its
timing admission was canceled before any samples to prioritize this merge.
Its frozen receipt and unmeasured record are preserved. After local main
advances, the next step is measurement using the combined compiler, followed
by further optimization only where the measured target remains unmet.
Full application performance reruns remain deferred until user review.
