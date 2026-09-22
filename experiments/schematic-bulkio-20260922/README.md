# Owned-payload host calls for the schematic tool — 2026-09-22

Evidence for [`docs/audits/schematic-lane-bulkio-2026-09-22.md`](../../docs/audits/schematic-lane-bulkio-2026-09-22.md),
lane 4 of [the parity-gap plan](../../docs/audits/schematic-parity-gap-2026-09-22.md).

## Sanitizer harness

`provider_checks.c` drives the schematic provider's `read_document_packed`,
`write_bytes_packed` and `payload_only` callbacks directly, outside any
generated program, so the payload contracts are checked without a guest:

```sh
cc -std=c11 -Wall -Wextra -Werror -fsanitize=address,undefined \
   -fno-omit-frame-pointer -Isrc experiments/schematic-bulkio-20260922/provider_checks.c \
   -o .tmp/san/provider-checks-san
ASAN_OPTIONS=detect_leaks=1 .tmp/san/provider-checks-san
```

The gated bridge test runs under the same sanitizers:

```sh
cc -std=c11 -Wall -Wextra -Werror -UNDEBUG -fsanitize=address,undefined \
   -fno-omit-frame-pointer -Isrc tests/qbe_host_bridge.c -o .tmp/san/host-bridge-san
ASAN_OPTIONS=detect_leaks=1 .tmp/san/host-bridge-san
```

Covered contracts, provider side: the published payload is the provider's own
storage charged at one work unit per byte plus one; an unsupplied document is
refused without charging; exhausted work refuses before publication; an output
span the runtime did not hand over empty is a contract break; a buffered write
into `/dev/full` succeeds and `finish` reports the failure; a payload past the
remaining output capacity and a payload the work budget cannot cover are both
refused before any octet is written; an empty payload is a charged call that
writes nothing; the node-bridge fallback for a payload declaration refuses.

Covered contracts, runtime side (`tests/qbe_host_bridge.c`): a published payload
is copied into a fresh guest byte string; a `bytes` argument reaches the
callback as a copy whose mutation leaves guest storage untouched; a written
count that disagrees with the span, a null span with a nonzero size, a callback
failure, reentry from a payload callback and a refused guest allocation all
publish nothing; an empty payload publishes an empty byte string; the payload
ceiling rejects an oversized argument before the callback runs and an oversized
result before it is published; a registry ceiling above 64 MiB is refused; a
payload schema whose guest width is not one pointer falls back to the checked
node bridge and is rejected there.

## Arms

The timing harness is the parity audit's
[`experiments/schematic-parity-gap-20260922/scripts`](../schematic-parity-gap-20260922/README.md),
reused unchanged. `spec-arms.json` builds the two arms this lane needs
(`gc-lto` for wall time, non-LTO `o3` for per-phase probes). Two source trees
are built with the *same* compiler and the *same* provider, differing only in
`src/schematic/guest/io.my`, so the comparison isolates the guest change:

```sh
W=/path/to/lane-worktree
AUDIT_TREE=$W AUDIT_WORK=$W/.tmp/audit \
  python3 ../schematic-parity-gap-20260922/scripts/build_arms.py \
  --compiler $W/.tmp/install/bin/mylang --work $W/.tmp/audit/arms --arms spec-arms.json
# and the same with AUDIT_TREE pointing at a copy whose io.my is the base one
```

`build_arms.py` writes each arm's `.declared` file from the emitted manifest, so
the new `io::read_document` and `io::write_bytes` reach the provider
registration without being named anywhere in the harness.

## What is measured

| script | question |
|---|---|
| `make_arms.py` | assembles the `bench_svg.py` arms file for the wall-clock batch |
| `phases_ab.py` | interleaved per-phase CPU comparison of two `phases_my.py` probe binaries, with a paired bootstrap on each phase's difference |
| `count_host_calls.py` + `run_count.py` | how many host calls one fixture render makes, from an instrumented throwaway copy of the provider |
| `differential_ab.py` | the malformed-input contract: both arms must agree on status, printed result, located issue code/file/byte position and published SVG, over the mutation set `experiments/full-svg-benchmark/differential.py` defines |

`results/` holds the raw rounds: `results-bulkio.json` (wall clock against the
Zig and Rust ports and the parity audit's retained `gc-lto`),
`results-ab.json` and `results-ab2.json` (same-compiler wall A/B, 31 and 61
rounds, both taken on a loaded machine and kept only as provenance),
`phases-ab.json` and `differential-ab.json`. See the
[audit report](../../docs/audits/schematic-lane-bulkio-2026-09-22.md) for the
numbers and their caveats.
