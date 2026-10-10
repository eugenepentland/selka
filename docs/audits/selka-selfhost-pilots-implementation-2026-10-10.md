# Incremental self-hosting pilots: implementation handoff

Date: 10 October 2026. Three GPT-6.1 Sol agents implemented the three immediate
work packages in `selka-incremental-selfhost-parallel-work-2026-10-10.md`.
This is a review branch for qualified pilots, not a production frontend switch.

## Revisions and ownership

The common baseline is `0d9ababf7eb434d2e02e1b2b45fe5c6593715e7a`.
The combined implementation is `d1c931fa40d2577dd61fec5eb5115f83cee77e73`
on `codex/selka-selfhost-pilots-20261010`.

| Work package | Independent commit | Combined commit | Contract and evidence |
| --- | --- | --- | --- |
| A: current lexer | `1f85cdd75b0ef2fedb8ee424f9fb56e189633b9a` | `797ec8e86` | [Lexer README](../../selfhost/components/lexer_pilot/README.md) |
| B: parser slice | `a31c4456f3be2d0abdf8f0aafd57760f2a7c3cd6` | `d1c931fa4` | [Parser README](../../selfhost/components/parser_pilot/README.md) |
| C: compiler library probes | `e87f8decad0476c74251f1e88314bd1bf2469a54` | `e969d2784` | [Probe README](../../selfhost/probes/compiler/README.md) |

The work used separate worktrees, private disk temporary directories and local
Zig caches, shared global cache, and build/gate admission. The active cache Wave
3 checkout was read only. Changes relative to the baseline are confined to new
pilot/probe modules, standalone drivers, fixtures and this handoff. The production
frontend, shared build/cache files, historical lexer and both seed pins retain
their baseline contents. Guardian feedback files were not modified.

## Implementation and executed qualification

All three drivers obtain the seed through the existing coordinator's verified
`--seed-only` path. Its executable SHA-256 in these runs is
`c4f1ea0b6618cb7b146bbb8e035220eb36b99ff078d4a959d8bf0948d0c6d98b`, from
the existing `component-seed.json` source pin. No source migration is used to
build the new modules. The pinned Zig is `0.17.0-dev.1683+5ceec001b`.

The following checks passed both in their independent lanes and in the combined
worktree. Pure tests were forced and uncached; all release runs included fact
verification and `MYL_CORE_LEAKCHECK=1`.

| Check | Debug | Release/fact/leak | Failed / skipped |
| --- | --- | --- | --- |
| Lexer differential | 79 fixtures, 1,714 token/error rows | Same | 0 / 0 |
| Lexer transport | 6 cases | 6 cases | 0 / 0 |
| Lexer component-only edit | Changed artifact, unchanged host; 79 fixtures rechecked | Same | 0 / 0 |
| Lexer pure library | 10 passed | 10 passed | 0 / 0 |
| Parser differential and boundary | 25 cases | 25 cases | 0 / 0 |
| Parser pure library | 10 passed | 10 passed | 0 / 0 |
| Compiler probes | 11 passed | 11 passed | 0 / 0 |

The parser's 25 cases comprise six supported structural comparisons, four
first-error code/span comparisons, five explicit unsupported-grammar refusals,
and ten malformed transport requests. Unsupported refusals are executed tests,
not silently skipped comparisons. Its projection compares kinds, operators,
ordered children and byte spans for the documented slice, not the complete AST
ABI or all grammar and diagnostics.

The lexer compares raw immutable bytes, including invalid UTF-8, boundary-size
literals and malformed layout. Direct `dump-tokens` errors keep parser/checker
failures out of the lexical oracle. Historical live-harness baseline evidence
was 31 fixtures, 450 rows, zero mismatches and three documented skips; the new
lexical corpus compares those cases without skips.

Peer review led to parser statement-boundary and physical-line checks, explicit
unsupported semicolons, digit-containing token tag handling, malformed EOF/span
checks, profile-safe decimal formatting, complete fixture membership checks,
and private oracle compilation caches. Lexer review added the exact accepted
request-size boundary and matching release flags for component edit checks.

Combined formatting passed: 839 live `.my` files checked, 204 deliberate
historical exclusions, zero failures; the formatting-driver tests passed too.
Each lane's commit hook passed 88 whole-tree Guardian checks.
The combined full gate passed at implementation revision `d1c931fa4`:
105/105 steps succeeded. Its 29 Guardian test results sum to 2,599 executed
passes, zero failures and zero selected-test skips. The raw Zig summary is
`2599/26249 tests passed (23650 skipped)` because unselected shard occurrences
are counted as skips by Zig; they are not omitted selected tests. Guest and
Python driver counts are reported separately in the full log. The gate used
ordinary repository cache behavior, not `-Dtest-rerun=true`; the standalone
pilot pure tests above explicitly forced execution without caches.

## Reproduction

Run from the combined worktree with the pinned Zig on PATH. The actual combined
run used a private disk TMPDIR under `~/.cache/mylang-tmp/selka-selfhost-pilots`
and a private local cache under `~/.cache/mylang/zig-local-cache-selka-selfhost-pilots`.
Equivalent worktree-private configuration and commands are:

```sh
export TMPDIR="$PWD/.tmp/selfhost-pilots"
export ZIG_LOCAL_CACHE_DIR="$PWD/.zig-cache"
export ZIG_GLOBAL_CACHE_DIR=/home/epentland/ai/canopy/.zig-global-cache
mkdir -p "$TMPDIR"
scripts/build-slot.sh build zig build -j2
scripts/build-slot.sh build python3 selfhost/tests/run_compiler_probes.py --zig "$(command -v zig)"
scripts/build-slot.sh build python3 selfhost/tests/run_lexer_pilot.py --edit-check
MYL_CORE_LEAKCHECK=1 scripts/build-slot.sh build python3 selfhost/tests/run_lexer_pilot.py --release --edit-check
scripts/build-slot.sh build python3 selfhost/tests/run_parser_pilot.py --zig "$(command -v zig)"
MYL_CORE_LEAKCHECK=1 scripts/build-slot.sh build python3 selfhost/tests/run_parser_pilot.py --zig "$(command -v zig)" --release
SEED_COMPILER=$(scripts/build-slot.sh build zig-out/tools/selka-components --root . --zig "$(command -v zig)" --seed-only)
scripts/build-slot.sh build "$SEED_COMPILER" test selfhost/components/lexer_pilot/tests.my --force --no-cache
MYL_CORE_LEAKCHECK=1 scripts/build-slot.sh build "$SEED_COMPILER" test selfhost/components/lexer_pilot/tests.my --release --verify-facts --force --no-cache
scripts/build-slot.sh build "$SEED_COMPILER" test selfhost/components/parser_pilot/tests.my --force --no-cache
MYL_CORE_LEAKCHECK=1 scripts/build-slot.sh build "$SEED_COMPILER" test selfhost/components/parser_pilot/tests.my --release --verify-facts --force --no-cache
scripts/build-slot.sh gate zig build test --summary all -j4 --maxrss 8589934592
scripts/build-slot.sh build zig build fmt-check
```

Text logs from the combined run are under
`~/.cache/mylang-tmp/selka-selfhost-pilots/`: `baseline-build.log`,
`probes.log`, `lexer-debug.log`, `lexer-release.log`, `lexer-pure.log`,
`parser-debug.log`, `parser-release.log`, `parser-pure.log`, `fmt-check.log`
and `full-gate.log`. Timings were deliberately not measured because isolated
timing admission was not obtained. There is no speedup or physical-copy
complexity claim.

## Remaining stages and integration requirements

1. Register these standalone drivers and pure tests in the shared gate after
   coordination with the cache owner. Declare the complete source, fixture,
   coordinator and seed input closures. The parser oracle also reads current
   `src/` content. The exact lane additions are listed in the linked READMEs.
2. Add a separately reviewed lexer Zig adapter/comparison mode, artifact identity
   and process supervision. Qualify end-to-end consumers and measure transport
   and component edit-loop cost before adoption.
3. Expand the parser's documented grammar, diagnostics and metadata, then build
   one validated production syntax boundary. Its README inventories single-file,
   project/import/interface, formatter, interpolation, embed, navigation and
   syntax-cache consumers. Component identities must bind every relevant cache
   lookup before any production switch.
4. Migrate contained analyses and then checking/lowering slices after those
   boundaries are ready. This implementation does not transplant historical
   checker, lowerer, QBE backend or runtime code.
5. Pursue staged self-compilation and reproducibility when enough stages are in
   Selka. The initial pilots do not establish that milestone.

The probe report separates dictionary qualification and the written native-sort
profile discrepancy from actual runtime limitations. Profile-safe alternatives
work, but linear name lookup and insertion sorting are deliberately small-scale
examples. Allocation/copy behavior still needs instrumentation; repeated source
location scans should become indexed lookups for bulk diagnostics.
