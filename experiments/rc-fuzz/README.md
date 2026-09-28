# RC differential fuzzer

A standing check that the reference-counting runtime (the default) computes what
the tracing collector (`--gc-runtime`) computes. It is not part of `zig build
test`; run it when changing ownership analysis, RC lowering or the RC runtime.

`gen.py SEED` and `gen2.py SEED` print one random, well-typed program that moves,
borrows, snapshots and mutates lists, dictionaries, strings, records, lists of
records and unions through `mut` parameters, element and field paths and loops,
printing a checksum of every value after each statement. `gen2.py` adds lists of
records and a union with managed payloads. The generators came from the RC
close-out's adversarial review (`docs/audits/rc-perf-closeout-2026-09-27.md`).

`run.py` checks each program, runs it under `--gc-runtime` as the baseline and
then under the RC modes, and compares exit status, stdout and stderr (warnings
and trace lines filtered):

| Mode | Flags | Failing? |
| --- | --- | --- |
| `rc` | none (the default runtime) | yes |
| `stats` | `--rc-runtime=stats`, and its `MYLANG_RC_COUNTS` must balance | yes |
| `rcrel` | `--release` (default RC, LLVM O3 + LTO), every `--release-every` seeds | yes |
| `stress` | `--gc-stress` (selects the collector) | no: collector findings are reported only |

An RC divergence makes `run.py` exit 1; a program that diverges only under
`--gc-stress` is a collector finding, printed as `stress-only` and counted in the
summary. Every diverging program is kept under `out/found/`, and `out/summary.json`
lists the tally and findings. `out/` (work files, found programs, the build cache
and `TMPDIR`) is gitignored.

```console
$ zig build test-rc-fuzz -Dfuzz-seeds=200           # seeds 1..200 with the installed compiler
$ python3 experiments/rc-fuzz/run.py --compiler zig-out/bin/mylang --start 1000 --count 50 --jobs 4
$ python3 experiments/rc-fuzz/gen2.py 7 > /tmp/s7.my  # one program, to reproduce a finding
```

`--gen gen.py|gen2.py|both` picks the generator (`both` alternates by seed
parity), `--no-stress` skips the collector lane, and `MYLANG` names the compiler
when `--compiler` is absent. A seed's program depends only on the seed and the
generator, so a finding reproduces from its seed alone.
