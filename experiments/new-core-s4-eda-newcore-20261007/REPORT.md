# EDA Stage 1 under the new core (S4-P EDA lane), 2026-10-07

Port: eda-bench `claude/s4-eda-newcore` (from `codex/s4-eda-stage1` 510c2e2; only
`harness/langs.toml` changed: `mylang-core` and `mylang-core-release` entries).
Compiler: this branch, `claude/s4-p-eda` (base c933cad1b).

## Results

| Check | Result |
|---|---|
| `mylang-core build src/main.my` (debug) | ok |
| `mylang-core build src/main.my --release` | ok |
| `mylang-core test src --jobs 4 --max-frames 30000 --max-steps 4000000000 --max-memory 2G` | 310/310 debug, 310/310 `--release` |
| `bench.py equiv mylang-core` / `mylang-core-release` | 34/34 byte-identical, both |
| `mylang/tools/check_tests.py` | 279/279 Zig counterparts |

Before this lane: 308 passed, 1 failed (`test_parse_rejects_excessively_deep_nesting`,
SIGSEGV: 10,016-deep recursion on the 8 MiB native stack), 1 unsupported
(`test_footprint_mod_export`: assert with a message value).

## Fixes (each with a spec tag and a reduced fixture)

1. `NEW-CORE-S4-ASSERT-MESSAGE-1`: `assert c, value` prints the value and a newline to
   stderr, then traps `R_ASSERT` with no message, as the old core does.
   Fixtures `test/core/v_assert_message.my`, `v_assert_message_err.my` (outputs recorded
   from the pinned old compiler); test in `src/core/value_e2e_test.zig`.
2. `NEW-CORE-S4-FRAMES-1`, `NEW-CORE-S4-MEMORY-1`: `mylang-core test --max-frames N`
   and `--max-memory SIZE` (also `limits.test` in `mylang.json`, `MYLANG_MEMORY_LIMIT`),
   old defaults (1,024 frames, 512 MiB), old trap codes and advice, old frame-fit
   refusal (status 2). Frames: enter/leave calls in original functions of test builds
   only; each trial runs on a stack mapped for the budget (32 KiB/frame + 8 MiB).
   Memory: allocator chunks and live large blocks counted against the ceiling, trap
   `R_MEMORY_BUDGET`; `RLIMIT_AS` = ceiling + 256 MiB. Tests in
   `src/core/test_runner_project_test.zig` (deep recursion under `ulimit -s 1024`).
3. `NEW-CORE-S4-TAKE-1` (found by the goldens: `rds3+flat` took 60 s vs 0.8 s under
   the old core): every `byte_builder` append copied the whole buffer, and so did any
   `mut` record field updated under an `if`. `own.zig` now looks at a join phi's
   edges individually; `byte_buffer` appends are one owned runtime call in the
   statement's block. Fixture `test/core/v_buffer_mut.my` (old-core output), IR test in
   `src/core/own_test.zig`. 100k byte_builder appends: 23.6 s -> 5 ms; 100k
   conditional list appends through `mut`: 5.8 s -> 2 ms.

Also: `value_build_test` "a record holding an unsupported type..." failed at the base
(c933cad1b made `Stream` record fields legal); its fixture now uses a dict-keyed dict.

## Rough, untimed observations (loaded machine, not CPU 10, ReleaseFast compiler)

- Harness `build` cold 18.4 s (includes the runtime object), unchanged 1.4 s, after a
  one-function body edit in `sexpr_parser.my` 1.3 s. Old: 81.1 / 0.017 / 1.15 s.
  The unchanged build does not reach the old 0.017 s.
- Harness `test` cold 15.8 s, unchanged 0.4 s; after the same edit 12.6 s and all 310
  tests re-ran. Old: 234.5 / 1.65 / 1.67 s.
- Release build 25-33 s. Goldens total run time: debug 6.7 s, release 1.5 s.
- One release `test` run with its cache on /tmp (tmpfs shared with other agents)
  failed 239 builds with `build error (WriteFailed)`; rerun with the cache on disk:
  310/310. Treated as an environment failure.
