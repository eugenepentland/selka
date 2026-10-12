# Checked word iteration

C0: `399013af36d41b78610e5ede22a9102ec5b17ffe`.
Branch: `codex/micro-gaps-20261012-words`.

The old private whitespace split matcher accepts only direct dictionary key uses.
The migrated fixture explicitly copies each word before setting its dictionary
entry. The checked copy lowers to `myl_core_owned_octets_copy`, so the matcher
refuses the whole loop. `baseline-repro.ir` records the minimal reproduction.
`text.my` is a byte-for-byte evidence copy of the existing migrated
fixture; its work and checksums are unchanged.

The matcher now recognizes a bounded chain (at most 15 calls) of compiler
runtime-authorized string copies whose entire use tree consists of dictionary
probes or insertions. It changes those copies to forwarding private views;
probes read the source bytes, and each insertion materializes its own independent
owned string. Escaping copies, non-key uses, owning or view-taking near-match
helpers, deeper chains, and unstable input owners keep the original allocation
path. All split inputs are checked for mutation or transfer, including an
explicit separator. The standalone split ABI/runtime is unchanged.

The shared `single_owner_copy.zig` authority hunk belongs to the coordinator:
use `effectCall` for the compiler-owned octet copy declaration, giving it
`runtime_c` linkage without changing the call operation or runtime behavior.
It is intentionally excluded from this track's commit.

Regression coverage lives in the already registered `emit_text_split_test.zig`
and `iteration_test.zig`, plus `test/core/gap_words.my`. Coverage includes nested
copies, escaped token copies, source mutation refusal, Unicode/non-ASCII
whitespace, empty and all-whitespace input, dictionary independence after source
mutation, early return, break/continue, and standalone explicit split values. Empty separators retain their structured
trap, tested before loop-body effects and an early exit.

Build/test commands use the pinned development environment and shared admission:

```sh
source /home/epentland/.config/mylang/dev-env.sh
export MYLANG_COMPONENT_DIR="$PWD/.tmp/micro-gaps/words/install/libexec/mylang/components"
scripts/build-slot.sh build "$ZIG" build core-test-binary seed-compiler \
  -Dtest-filter='private whitespace split' -Dtest-filter=gap_words \
  -j"$MYLANG_DEV_JOBS" --maxrss "$MYLANG_DEV_MAXRSS" \
  --prefix .tmp/micro-gaps/words/install
scripts/build-slot.sh build .tmp/micro-gaps/words/install/focus/core-tests
```

`qualify.py CANDIDATE OUTPUT` validates every text-group edge/default fixture,
including both word_count sizes, against the independent registry oracle. It
captures stdout/status/counters and requires zero RC events, zero uniqueness
tests, and zero managed exit-live bytes when counters exist. The elapsed CLI
field is retained for protocol validation only; no timing comparison is made.

Initial validation encountered an existing shared component-cache missing
native-link object before tests ran. A private-cache retry reproduced the same deterministic failure. Validation
therefore uses the provisioning-free `core-test-binary` and `seed-compiler` build
targets and a complete copy of the frozen installed components/tools.
`component-inputs.json` records all ten immutable reused file hashes. No shared
cache deletion or seed repinning was performed.

## Qualified outcome

The final focused runner passed all four tests (`test-final.log`). The candidate
compiler is `c8f22c47593ea64a255295507d0cc8bd75d08615921aade67a0623c6a6fd500e`;
`build-manifest.json` records exact guest commands, source and executable hashes.
Both runtime and counted guests passed all 50 text-group edge/default probes.
Their complete protocol/counter records are in `qualification-runtime.json`
and `qualification-counted.json`. Every counted probe has zero RC events,
uniqueness tests and managed exit-live bytes.

Default word-count probes (seed42, three iterations) against the frozen existing
checked qualification records:

| Size | Baseline allocations | Candidate allocations | Baseline cumulative bytes | Candidate cumulative bytes |
| --- | ---: | ---: | ---: | ---: |
| 16 | 184 | 85 | 13,536 | 6,240 |
| 256 | 2,110 | 565 | 151,008 | 46,728 |

`text::word_job` has 18 allocations and 1,440 cumulative bytes for either default
probe (six allocations per job), instead of scaling with token count. Whole
program counters still include fixture setup and `score` encoding. These are
allocation/protocol results; parent integration will measure final timing.

Runtime guest SHA256: `dd1ff73048e7c014c9102c58412e6d4e66cc3a18d29f0508e0d2ec9bcbbc5897`.
Counted guest SHA256: `e5c396c7e5799bd245ba305f8149c52c56e24d2b92da76070a3450c1ff3b6282`.

The frozen compiler's `dump-ir` on the complete text fixture hits recursive
`print.typeName` recursion and aborts; a minimal non-recursive reproduction was
used for raw IR diagnosis. This printer limitation does not affect the native
builds or checksum/counter qualification.

Final Guardian `all . --gate --summary` passed all 88 checks
(`guardian-final.log`). No Guardian feedback entry or feedback commit was made.
A narrow `nm` audit of the runtime guest found no known core retain/release
or uniqueness helper symbols; executed counters remain the runtime evidence.
