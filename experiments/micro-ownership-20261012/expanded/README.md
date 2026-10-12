# Expanded checked-ownership preparation

This evidence retains all 40 registry cases (35 micros, five applications), both prescribed sizes, independent Python checksums, and the original in-process monotonic kernel timing boundaries. No timing campaign or calibration is performed here.

`original/` contains the four historical source groups migrated only to the current language surface: `func`, explicit writable local declarations, array type syntax, source-first comprehensions, reading-order conditionals, named enum payloads and `parse_int`. The frozen compiler's structured `fix` command supplied syntax, parsing and mut-argument repairs. `migrated/` adds only ownership admission changes; each exact delta is in `*-ownership.patch`. The compute pair is identical.

The legacy record read passes `records[index]` straight to the ordinary helper, which borrows its input in checked mode; the original contract permits this readonly equivalent. Full list and nested-list snapshots use `.copy()` and continue to preserve every element. Dictionary string keys, borrowed CSV region strings, reused fragment selections and JSON fields are explicitly copied before owned storage. Case selection copies the borrowed CLI string outside timing. No snapshot is reduced to a scalar, no algorithm is optimized, and no RC fallback is used.

The existing C clock is linked with `--link benchmarks/runtime/ports/native_clock.c`. Its modern declaration `extern func runtime_bench_now(host: Host) -> i64 effects(host)` is supported directly: Host is erased from the C ABI, and CLOCK_MONOTONIC remains unchanged. The wall-clock-only `time.now` API is unsuitable for this contract.

`prepare.py` builds original RC, migrated RC and migrated checked ownership with the archived compiler and `--release`; separate counted builds add `--counters`. Each build goes through the shared `scripts/build-slot.sh build` admission wrapper after sourcing `/home/epentland/.config/mylang/dev-env.sh`, with private TMPDIR/frontend cache/Zig caches. The compiler binary SHA-256 is asserted before use. The compiler installation is complete and is never rebuilt.

`manifest.json` records all 24 requested binary entries, their flags, commands, status, source and binary hashes. `qualification.json` records exact command/stdout/stderr/status and oracle expected values for the three registry EDGE_PROBES and both default sizes with three iterations, for every successful variant. Counter builds write JSON through `MYLANG_COUNTERS=FILE`; its version is `mylang-counters-v1`, with `totals`, `kinds`, `functions`, and `sites`. Captured stderr remains separate from checksum stdout. Counter values include fixture preparation and process startup/cleanup, not just the timed kernel, and must not be interpreted as kernel-only operation counts.

The original checked-mode diagnostics are saved as `*-original-zero-check.txt`; original sources are intentionally built only in RC. Successful migrated checks do not substitute for native qualification. Any native build refusal or checksum failure remains recorded in the complete inventory.

Run preparation from this worktree root:

```sh
source /home/epentland/.config/mylang/dev-env.sh
python3 experiments/micro-ownership-20261012/expanded/prepare.py
```

Absolute paths identify live scratch artifacts in this worktree; source paths are also checked into this evidence directory. Historical benchmarks/oracles/contracts and production compiler/runtime are unmodified.
