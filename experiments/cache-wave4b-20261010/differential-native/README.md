# Direct differential native smoke — 2026-10-10

All eight commands exited 0: two exploratory attempts and exact replay of those
same two attempts for each of `incremental`, `module-projects`, `interfaces`, and
`interfaces-generic`. This is eight explored attempts plus eight replayed
attempts. The four JSON corpora retain full copied baselines, including root
`mylang.json`, and concrete mutation cases. Original results, logs, and corpora
are copied unchanged; paths inside `results.json` name their original cache
locations. The corresponding logs now sit beside this README.

The run used the existing installed Wave 4A compiler and pinned Zig
`0.17.0-dev.1683+5ceec001b`, with direct driver commands admitted by
`scripts/build-slot.sh build`. It did not run the coordinator or a nested gate.
The executable digest was not captured at execution, so no current binary hash
is asserted as the identity of that run. This tiny smoke is not a performance
measurement or broad compiler fuzz coverage.

`provenance.json` lists all eight argument vectors and environment overrides.
Those command vectors are reconstructed from the execution transcript, rather
than command echoes in the logs. Other inherited environment values were not
recorded. Their explicit seed was `1984496162`; the seed helper changed later,
so re-deriving it using the current helper would not reconstruct this run.

The command shape, run from the worktree root, was:

```sh
scripts/build-slot.sh build /usr/bin/python3 -B DRIVER --strict-campaign \
  --steps 2 --seed 1984496162 --project FIXTURE --corpus-out BUNDLE \
  "$PWD/zig-out/bin/mylang"
scripts/build-slot.sh build /usr/bin/python3 -B DRIVER --strict-campaign \
  --steps 0 --replay-corpus BUNDLE "$PWD/zig-out/bin/mylang"
```

| Target | DRIVER | FIXTURE |
| --- | --- | --- |
| incremental | tests/incremental_diff.py | tests/fixtures/incremental |
| module-projects | tests/incremental_diff.py | tests/fixtures/module_projects |
| interfaces | tests/interface_diff.py | tests/fixtures/interfaces |
| interfaces-generic | tests/interface_diff.py | tests/fixtures/interfaces_generic |

`BUNDLE` was the absolute worktree path under
`.mylang-cache/cache-wave4b/producer-smoke-isolated/TARGET.corpus.json`.

To test ancestor-config isolation, `TMPDIR` was deliberately set to
`.mylang-cache/cache-wave4b/tmp/producer-ambient-boundary`, whose `mylang.json`
referenced a missing `unbound-missing-policy.json`. That exact outer file is
preserved as `ambient-mylang.json`. Strict private baselines supplied their own
nearest config: existing fixture config was retained, or the explicit default
`{"version":2}` was created before capture. All explore and replay commands
passed despite the invalid outer config, and every retained baseline includes
its own root config.

`evidence-sha256.json` checksums the preserved files. No binaries are included.
