#!/usr/bin/env python3
"""Render the retained comparison from its raw build and runtime receipts."""
import json
import statistics
from build_hashes import HERE

builds = json.loads((HERE / 'compiler-builds.json').read_text())
builds += json.loads((HERE / 'compiler-llvm-builds.json').read_text())
runtime = json.loads((HERE / 'frontend-summary.json').read_text())
hashes = json.loads((HERE / 'hash-summary.json').read_text())
coordinators = json.loads((HERE / 'coordinator-measurements.json').read_text())
followup = json.loads((HERE / 'coordinator-followup.json').read_text())
qualification = json.loads((HERE / 'qualification.json').read_text())
names = ['custom-Debug', 'release-Debug', 'pinned-Debug', 'custom-ReleaseSafe',
         'release-ReleaseSafe', 'pinned-ReleaseSafe', 'release-llvm-ReleaseSafe', 'pinned-llvm-ReleaseSafe']
labels = {'custom': 'Custom EDA', 'release': 'Official 0.17.0', 'pinned': 'Pinned dev.1683'}
lines = ['# Zig 0.17.0 versus the pinned and custom toolchains', '',
         'Local measurements on the Intel i7-12700H, 9–10 October 2026. Official release',
         'metadata and the verified download checksum are in `metadata.json`.',
         'The release index lists 0.17.0 on 1 October 2026:',
         '[official index](https://ziglang.org/download/index.json).', '',
         '## Compiler build time and runtime', '',
         'The native x86 rows force `-fno-llvm` on every toolchain. The LLVM rows',
         'force `-fllvm`, the official compiler’s normal optimized configuration.',
         'The custom EDA package has no LLVM backend. Compiler build mode is',
         'independent of the optimization mode of any Selka program it compiles.', '',
         '| Toolchain | Mode/backend | Clean build | Build peak RSS | Type check | Core IR generation | IR peak RSS |',
         '| --- | --- | ---: | ---: | ---: | ---: | ---: |']
summary = {}
for name in names:
    rows = [x for x in builds if x['name'] == name and x['state'] == 'clean' and x['exit'] == 0]
    wall = statistics.median(x['wall_s'] for x in rows)
    rss = statistics.median(x['rss_kib'] for x in rows) / 1024
    check, ir = runtime[name + '/check'], runtime[name + '/ir']
    mode = name.split('-')[-1] + (' / LLVM' if '-llvm-' in name else ' / native x86')
    lines.append(f'| {labels[name.split("-")[0]]} | {mode} | {wall:.2f} s | {rss:.1f} MiB | {check["median_s"]*1000:.1f} ms | {ir["median_s"]*1000:.1f} ms | {ir["median_rss_kib"]/1024:.1f} MiB |')
    summary[name] = {'build_s': wall, 'build_mib': rss, 'check_ms': check['median_s']*1000,
                     'ir_ms': ir['median_s']*1000, 'ir_mib': ir['median_rss_kib']/1024}
lines += ['', '### Method and limits', '',
          '- Three clean-project-cache build samples for each native row; one for each LLVM row.',
          '  Each successful build was followed by an unchanged build. Native unchanged builds',
          '  took roughly 20–40 ms. The shared Zig global cache and OS file cache were warm.',
          '  Initial compatibility attempts and build-runner provisioning are excluded.',
          '- This measures compiler-only construction through a matching standalone module',
          '  graph, excluding Guardian, component provisioning, and test execution. The',
          '  embedded number-formatting helper uses native x86 code generation in every arm.',
          '  No strip flag is used, matching the current Selka build; this does not measure',
          '  the custom compiler’s best-case stripped EDA application configuration.',
          '- Runtime uses seven alternating-order samples after a warmup, pinned to CPU 2.',
          '  CPU 2 is locked for these timings; sibling CPU activity is recorded per sample.',
          '  No project builds ran in the final window, but another prebuilt benchmark',
          '  used the separate reserved CPU 10. This is a shared-machine comparison,',
          '  not whole-machine isolation. No filesystem cache eviction or governor change.',
          '- `frontend.my` is 256 functions plus `main`, 3,078 lines / 99,181 bytes.',
          '  Type checking passes `--no-cache`. `dump-ir` performs a fresh frontend check',
          '  and Core lowering/rendering in a new process, without external code generation.',
          '  All arms have byte-identical outputs. These timings do not measure linked',
          '  guest-program execution, an entire project gate, or incremental compiler edits.',
          '- Peak RSS comes from GNU time: the largest process including child usage,',
          '  not the sum of simultaneous processes. Runtime includes process startup.',
          '- All arms use one frozen source snapshot from the self-hosting wave worktree.',
          '  0.17 adds `ArrayList.pointer_stability`, so eight direct initializers in five',
          '  files were expressed through `.empty` / `fromOwnedSlice` in **every** arm.',
          '  `compatibility.patch` records the exact adjustment. No production source or',
          '  toolchain pin was changed. This is a comparison, not upgrade qualification.', '',
          '## SHA-256 transition regression', '',
          'The SHA-256 source file is byte-identical across all three toolchains.',
          'All probes stream through 64 KiB buffers and match an independent Python',
          'SHA-256 digest. The following are three-run medians for the same 16 MiB file,',
          'after warmup, using each toolchain’s default backend for that mode.', '',
          '| Toolchain | Mode | Native CPU | Baseline CPU |',
          '| --- | --- | ---: | ---: |']
for tool in ['pinned', 'custom', 'release']:
    for mode in ['Debug', 'ReleaseSafe', 'ReleaseFast']:
        native = hashes[f'{tool}-{mode}-native']['median_s']
        baseline = hashes[f'{tool}-{mode}-baseline']['median_s']
        lines.append(f'| {labels[tool]} | {mode} | {native*1000:.1f} ms | {baseline*1000:.1f} ms |')
lines += ['', 'The actual ReleaseFast coordinator was also rebuilt with each toolchain.',
          'Each row below is one CPU-pinned `--seed-only` verification of the same',
          'existing qualified seed and the same pinned Zig files, including `perf`.',
          'All returned the same seed executable; no seed compilation is included.', '',
          '| Coordinator compiler/CPU | Verification | Peak RSS | SSE/AVX transition assists |',
          '| --- | ---: | ---: | ---: |']
for row in coordinators:
    assists = next(line.split(',')[0] for line in row['perf'].splitlines() if 'assists.sse_avx_mix' in line)
    lines.append(f'| {row["name"]} | {row["wall_s"]:.2f} s | {row["rss_kib"]/1024:.1f} MiB | {int(assists):,} |')
lines += ['', 'A followup alternated three uninstrumented samples after warmup:', '',
          '| Coordinator | Median verification | Median peak RSS |', '| --- | ---: | ---: |']
for name in ['pinned-baseline', 'pinned-safe-native', 'release-native']:
    samples = [row for row in followup if row['name'] == name and row['rep'] > 0]
    lines.append(f'| {name} | {statistics.median(row["wall_s"] for row in samples):.3f} s | {statistics.median(row["rss_kib"] for row in samples)/1024:.1f} MiB |')
lines += ['', '`pinned-safe-native` uses LLVM ReleaseSafe instead of ReleaseFast. It is',
          'the build-mode workaround now selected for the production coordinator with',
          'the existing pin and explicit LLVM. The separate perf run reports',
          'one transition assist over the entire seed verification, versus hundreds of',
          'millions in the old native-CPU ReleaseFast build. Neither workaround changes',
          'the pinned Zig compiler or constitutes a general fix to its native backend.']
lines += ['', 'The released compiler eliminates the observed ReleaseFast/LLVM coordinator',
          'regression: roughly 592 million transition assists become zero. This is',
          'an empirical result for these reproductions, not a claim that all related',
          'code-generation cases are fixed. Its Debug native backend still produces',
          'about 29.36 million assists on the 16 MiB probe. Explicit ReleaseSafe',
          '`-fno-llvm` reproduces the same issue on both official snapshots; the custom',
          'compiler also reproduces it. Optimized LLVM and native x86 must therefore',
          'be distinguished when describing the fix.', '',
          'The old LLVM ReleaseFast probe holds 256-bit YMM state across legacy SHA',
          'instructions. The release’s corresponding SHA round uses 128-bit state.',
          'Both toolchains report clang 22.1.8, so this report does not attribute the',
          'difference to a particular upstream LLVM release or commit.', '',
          '## Validation and reproduction', '',
          f'- {len(qualification["checks"])} representative source checks passed across all eight compiler artifacts.',
          '- Frozen sources and the final retained binary for each build configuration',
          '  were checked against their latest successful build receipts.',
          '- All timed compiler outputs and hash outputs match across toolchains.',
          '- No Guardian gate was exercised by this isolated experiment.', '',
          'From the worktree root:', '', '```sh',
          'scripts/build-slot.sh build python3 experiments/zig017-toolchain-20261009/build_hashes.py',
          'scripts/build-slot.sh build python3 experiments/zig017-toolchain-20261009/build_compilers.py',
          'scripts/build-slot.sh build python3 experiments/zig017-toolchain-20261009/build_compilers.py --llvm',
          'scripts/build-slot.sh build python3 experiments/zig017-toolchain-20261009/build_coordinators.py',
          'python3 experiments/zig017-toolchain-20261009/qualify.py',
          'python3 experiments/zig017-toolchain-20261009/quiet.py python3 experiments/zig017-toolchain-20261009/measure.py frontend',
          'python3 experiments/zig017-toolchain-20261009/measure.py hash',
          'python3 experiments/zig017-toolchain-20261009/measure_coordinators.py',
          'python3 experiments/zig017-toolchain-20261009/measure_coordinator_followup.py',
          'python3 experiments/zig017-toolchain-20261009/summarize.py', '```', '',
          'Toolchain paths are in `build_hashes.py`; binary hashes and host information',
          'are in `metadata.json`. `source-manifest.json` covers the frozen compiler',
          'snapshot. Commands, results and raw counters are retained in the adjacent',
          'JSON, log and perf files. Build caches and binaries remain under the worktree’s',
          'ignored `.mylang-cache/zig017-toolchain-20261009/` directory.', '']
(HERE / 'README.md').write_text('\n'.join(lines))
(HERE / 'comparison-summary.json').write_text(json.dumps(summary, indent=2) + '\n')
print(json.dumps(summary, indent=2))
