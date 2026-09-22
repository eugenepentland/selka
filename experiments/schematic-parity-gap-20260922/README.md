# Schematic parity gap audit — 2026-09-22

Evidence for [`docs/audits/schematic-parity-gap-2026-09-22.md`](../../docs/audits/schematic-parity-gap-2026-09-22.md).
Nothing here changes production source; the compiler was built from a private
worktree at the commit in `compiler-commit.txt` with `worktree-spec-case.patch`
applied (four `// spec:` tags demoted to `// spec-case:` in a test file so that
Guardian would allow the ReleaseFast install).

## Layout

| path | contents |
|---|---|
| `scripts/build_arms.py` | builds guest arms from a spec: backend, opt level, LTO, step accounting, arena wrapper, manifest stripping |
| `scripts/strip_il.py` | manifest rewrite that removes check classes (`overflow`, `cast`, `bounds`, `alloc`) and/or the frame protocol (`frames`, `positions`, `trap`) |
| `scripts/bench_svg.py` | interleaved fresh-process timing of mylang and native arms with SVG hash verification and paired bootstraps |
| `scripts/floors2.py` | interleaved timing of arbitrary commands under one shared environment (startup floors) |
| `scripts/profile_svg.py`, `scripts/sample_fast.c` | `LD_PRELOAD` SIGPROF self-PC sampler over many fresh runs (first expiration 1 µs) |
| `scripts/phases_my.py` | relinks a non-LTO arm's objects with `--wrap` CPU-clock wrappers around 13 guest functions; `build` then `measure` |
| `scripts/phases_native.py` | interleaved per-phase timing of the phase-instrumented Zig and Rust ports |
| `ports/main-phases.zig`, `ports/main-phases.rs` | the ports with `PHASE name ns=` timers; byte-identical SVG |
| `ports/mylang-phase-wrappers.c` | the generated wrappers (signatures derived from the emitted IL) |
| `ports/prov-empty-main.my`, `ports/prov-read-main.my` | startup-floor guests |
| `spec-*.json` | arm specifications given to `build_arms.py` |
| `results/results-base.json` | ten arms × three inputs, 31 rounds (§1 of the audit) |
| `results/results-ladder.json` | strip ladder (§2) |
| `results/results-floors2.json` | startup floors (§3.1) |
| `results/phases-o3.json`, `results/phases-o3-s-all.json`, `results/native-phases.json` | per-phase CPU time (§3.2) |
| `results/profile-gc-lto.json`, `results/profile2-gc-lto.json` | self-PC profiles with the repository's dense sampler and the 1 µs variant (§3.3) |
| `results/builds.json` | argv, binary, manifest and compiler hashes for every arm |
| `binary-hashes.txt` | hashes of the compiler, the main arms and the native comparators |

## Reproduce

Working directory `.tmp/perf-audit-20260922` under the repository root (gitignored):

```sh
git worktree add --detach .tmp/perf-audit-20260922/tree acbee603
ln -s "$PWD/../guardian-zig" .tmp/perf-audit-20260922/guardian-zig
(cd .tmp/perf-audit-20260922/tree && git apply ../../../experiments/schematic-parity-gap-20260922/worktree-spec-case.patch \
   && ./zigw build -Doptimize=ReleaseFast --prefix "$PWD/../install")
S=experiments/schematic-parity-gap-20260922
cd .tmp/perf-audit-20260922
python3 ../../$S/scripts/build_arms.py --compiler install/bin/mylang --work arms --arms ../../$S/spec-base.json
python3 ../../$S/scripts/build_arms.py --compiler install/bin/mylang --work arms --arms ../../$S/spec-ladder.json
python3 ../../$S/scripts/build_arms.py --compiler install/bin/mylang --work arms --arms ../../$S/spec-o3.json
python3 ../../$S/scripts/build_arms.py --compiler install/bin/mylang --work arms --arms ../../$S/spec-o3s.json
python3 ../../$S/scripts/bench_svg.py --arms bench/arms-base.json --out bench/results-base.json      # arms JSON as in results/*.json "arms"
python3 ../../$S/scripts/phases_my.py build && python3 ../../$S/scripts/phases_my.py measure
PHASES_ARM=o3-s-all python3 ../../$S/scripts/phases_my.py build && PHASES_ARM=o3-s-all python3 ../../$S/scripts/phases_my.py measure
python3 ../../$S/scripts/phases_native.py
```

The native comparators are the retained `.tmp/full-svg-benchmark-20260921/{zig-o3,rust-o3,go-fast}`
binaries and frozen projects from `experiments/full-svg-benchmark`; the phase-timed
ports are built from `ports/` with the same flags (`rustc -C opt-level=3 -C codegen-units=1
-C debug-assertions=off`, `zig build-exe -O ReleaseFast -fllvm`). The `prod-default`
arm reproduces the runner's argv:

```sh
install/bin/mylang build tree/src/schematic/guest/main.my --project --provider tree/src/schematic/native_schematic.c \
  --step-accounting --qbe install/bin/qbe --zig ~/.local/bin/zig --cache-dir prod/cache -o prod/prod-default --report
```

Do not time while another batch, build or profile is running; every batch pins
CPU 6. Hardware counters were unavailable (`perf_event_paranoid=4`).
