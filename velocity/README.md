# velocity/

The closed loop that measures and improves agent development speed. The design is
[`docs/velocity-loop.md`](../docs/velocity-loop.md); the goal, metrics and baselines are
[`goal.json`](goal.json) (user-owned); the ranked work is [`backlog.json`](backlog.json);
an iteration starts from [`LOOP-PROMPT.md`](LOOP-PROMPT.md). `suites/idioms/` holds the
110 first-try probes with their oracle tags and the 17 September baseline in
`manifest.json`. `gen_project.py` and `solve.py` are backlog items V1 and V2 and do not
exist yet.

## Lane C scorer — `score.py`

Measures C1 (first-try fidelity), C2 (silent wrong answers, a gate) and C3 (rejections
carrying a fix) over the probes in `suites/idioms/`. The oracle tag comes from each
probe's first line, so the suite can grow without editing the scorer; accepted programs
are compared with CPython (`runpy`, `main()`, exit `& 0xFF`, stdout) by the oracle runner
shared with `tests/idiom_probes.py`. Every run re-executes every probe; nothing is cached.

```sh
python3 velocity/score.py                                  # human table, current binary
python3 velocity/score.py --json --write velocity/suites/idioms/current.json
python3 velocity/score.py --baseline velocity/suites/idioms/score-baseline-2026-09-20.json
python3 velocity/score.py --binary zig-out/bin/mylang-baseline-20260920 --probe 'a6*'
python3 velocity/score.py --gate                           # exit 1 if C2 > 0
```

Flags: `--binary PATH` (default `zig-out/bin/mylang`), `--json`, `--baseline PATH`,
`--write PATH`, `--write-manifest PATH`, `--probe GLOB`, `--jobs N` (default
`min(8, cpus)`), `--timeout SECONDS` (default 60), `--gate`, `--self-test`. Exit status:
0 measured, 1 gate failed, 2 setup failed. The result JSON is `lane-c-score-v1` and
records the binary path, its sha256 and the compiler identity, so a stale binary is
visible. `python3 velocity/score.py --self-test` checks the C3 detectors and the shared
CPython oracle without measuring anything.

`--write-manifest PATH` writes a `manifest.json`-shaped file for the run (this is how the
suite manifest is regenerated after D1/D2/S1 land):

```sh
python3 velocity/score.py --binary zig-out/bin/mylang \
    --write-manifest velocity/suites/idioms/manifest.json
```

Current limits, stated so the numbers are not over-read:

- **C3 counts only the structured field**: a non-null `fix` or a note whose `role` is
  `alternative`. The field now exists: `C3` is 0.304 (24/79) on the tree as D1 and D2
  landed it, and 0.633 (50/79) after the follow-up that extended the shared hint table,
  against 0.000 on the frozen baseline where the field did not exist yet. A secondary
  reading of the prose the compiler already prints is reported beside it as
  `C3_text_any` and is never merged into `C3`; it is 0.354 and 0.506 at those two points.
  Use `C3` for the package verdict. The per-form account of what still carries no
  alternative is in `docs/audits/agent-usefulness-reports/idiom-coverage.md`.
- **Rejections include traps before any output.** Two of the 80 frozen-baseline
  rejections are runtime traps (`a57_assert_fstring.my`, a probe that asserts a false
  condition on purpose, and `a60_overflow.my`), not compile errors.
- **C2 only sees probes that run to completion.** `d05_round_half.my` was the recorded
  silent wrong answer, but the frozen binary rejects it with `E_OUTPUT_CAPABILITY`
  before it runs, so `C2 = 0` there does not mean the `round(2.5)` bug is fixed.
- The suite is 110 probes: the directory, the manifest and the baseline document's table
  all hold 110 rows. That document's heading and correction 4 say 111; the plan says 110.
  The heading is a counting slip, not a missing probe.

Relationship to backlog item V0: V0 asks for one lane C instrument that extends
`tests/idiom_probes.py` with the CPython oracle rather than a second runner. That driver
now owns `cpython_oracle()` and the "did this run complete" classifier, and `score.py`
imports both; the recorded-expectation corpus under `tests/fixtures/idioms` stays where
it is. The other lanes (B, D, the gate list) are still unbuilt, so `score.py` is lane C
only and does not write `velocity/current.json`.
