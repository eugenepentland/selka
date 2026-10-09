# Lane 4: owned `bytes` payloads across the host bridge — 2026-09-22

Item 4 of [the parity-gap plan](schematic-parity-gap-2026-09-22.md): the guest's
document reads and its SVG write crossed the host boundary in 256-byte blocks
and were then re-copied one octet at a time (§3.1, §4 "Byte-granular I/O
bridges"). This lane gives the packed host-call ABI a whole-`bytes` payload in
both directions and rewrites `io.load` and `io.flush` to use it.

**The fixture render now makes 8 host calls instead of 303** and produces the
identical 49,617-byte SVG. Inside the guest, `io::load` falls **32%** and
`io::flush` **40%** — together about **79 µs** of CPU on a loaded machine, or
about 50 µs scaled to the parity audit's quiet-machine baseline. That is 3–4% of
the render, which the wall-clock batch cannot separate from noise on this
machine; the integrator should re-measure the wall time on a quiet one.

Evidence, scripts and raw rounds:
[`experiments/schematic-bulkio-20260922`](../../experiments/schematic-bulkio-20260922/README.md).

## 1. The ABI change

Native provider ABI **6 → 7** (`MYLANG_NATIVE_PROVIDER_ABI`,
`mylang_native_providers_v7`). External C providers must recompile; the factory
symbol is versioned so an old binding layout cannot link silently. Every bundled
provider is in-tree and updated.

A host declaration may now name the immutable `bytes` byte string **at the
boundary itself** — as a parameter or as the result, but not nested inside a
copied record, which the node graph cannot carry. `data_type.checkHost` is the
one place that decides this, and both `sema` (source) and `bytecode`
(validation) go through it, so a forged bytecode signature is refused exactly
where a source one is. `qbe_host.describe` gives the type schema kind `bytes`,
which `qbe_build_host` emits as kind 6 in the generated C table. Nothing in the
guest ABI lowering changed: `bytes` is already one scalar pointer word, so the
existing host wrapper stores it like any other scalar argument and reads it like
any other scalar result.

### Contracts the runtime enforces

The packed path is selected exactly as before — schema, grant, effect, logical
node/depth quota, call and work checks all run first — with these additions:

| contract | where |
|---|---|
| A `bytes` **argument** is a runtime-owned copy of the guest byte string's exact octets, so a provider that writes through it cannot reach guest storage. | `qbe_host_payload_of` and the copy loop |
| Every argument is **measured before any is copied**, so an oversized payload is refused before the callback observes the call. | first loop of `qbe_host_invoke_packed` |
| A `bytes` **result** is the one output the callback owns: the runtime hands over an empty span (`NULL`, size 0) and the callback sets `output.bytes`, `output.size` and an equal `output_written`. Every fixed-size shape still receives zeroed runtime scratch whose pointer and size must not change. | `qbe_host_invoke_packed` |
| The published octets are **copied into a fresh guest byte string** before the runtime returns; the runtime never writes through them and the provider can never alias guest memory. | `qbe_host_publish_payload` |
| An inconsistent span (written ≠ size, or a null pointer with a nonzero size), a sticky trap, a callback failure, exhausted work and a refused guest allocation all **publish nothing**. | `qbe_host_publish_payload` |
| Payload octets are bounded by the registry's `max_payload` (zero selects 1 MiB), on arguments before the call and on the result before publication. A registry above 64 MiB is refused as `HostInvalidBudget`. | `myl_qbe_host_begin`, `qbe_host_payload_of`, `qbe_host_publish_payload` |
| A declaration naming `bytes` has **no node-bridge fallback** — copied nodes cannot carry managed storage — so a provider that offers no packed callback is rejected by the node bridge as `NotDataType`. | `qbe_host_write` |

The scratch buffer is still frame-registered, so unwinding releases it, and the
guest byte string is allocated **before** the scratch is released, so a provider
that echoes its argument back as the result stays valid. The fixed-size scratch
is no longer zeroed twice: only the value headers and the fixed output region
are cleared, because every argument region is fully overwritten by its copy.

`SPEC.md` carries this as `[HOST-PACKED-2]` and the guest change as
`[SCHEMATIC-BULK-2]`. The shapes are documented with a runnable provider example
in [packed host calls](../tooling/packed-host-calls.md).

## 2. The guest change

The schematic provider gains two operations beside the block ones, which are
kept so the existing `[256]u8` shapes stay under test:

```
public host def read_document(host: Host, file: int) -> bytes effects(host)
public host def write_bytes(host: Host, payload: bytes) -> int effects(host)
```

`io.load` is one call — the payload becomes `Document.source` directly, with no
buffer, no reservation and no per-byte loop:

```
def load(host: Host, identity: int) -> Result[Document, int]:
    return Ok(Document(identity=identity, source=read_document(host, identity)))
```

`io.flush` is one call on the buffer's snapshot (`bytes(buffer)` copies no
octet), keeping the failure and limit semantics where they were: `out.failed`
still reports the 4 MiB overflow through `output_limit(host)` before any output
is written, a nonzero write status still short-circuits, and `finish(host)`
still reports buffered write failures.

`read_document_packed` publishes the provider's own start-up copy of the
document and charges one work unit per byte plus one; `write_bytes_packed`
enforces the remaining output capacity and charges the same way, both before any
effect. `max_payload` is the provider's 4 MiB output capacity, which also covers
the driver's 1 MiB document ceiling.

## 3. Measurements

Machine: i7-12700H, CPU 10 pinned, `powersave` governor. **Other lanes were
building throughout**, so absolute times run 1.5–1.9× the parity audit's and the
wall intervals are far too wide to resolve a 3% effect. The per-phase numbers
use `CLOCK_PROCESS_CPUTIME_ID` inside the process and survive the load much
better; they are the load-bearing evidence here.

### Host calls

Counted with an instrumented copy of the provider
([`count_host_calls.py`](../../experiments/schematic-bulkio-20260922/count_host_calls.py)),
one counter increment per registered callback:

| arm | host calls, fixture | SVG |
|---|---:|---|
| block I/O (base guest) | **303** | 49,617 bytes, `68157ea7…` |
| payload I/O (this lane) | **8** | 49,617 bytes, `68157ea7…` |

The 8 are three named-input identities, three `read_document`, one
`write_bytes` and one `finish`. `io::length` is no longer called at all, and the
102 `read_block` plus 194 `write_block` calls are gone.

### Per phase

Both arms were built by the same ReleaseFast compiler from the same provider,
with only `io.my` differing; non-LTO O3 relink with `--wrap` CPU-clock probes
around 13 guest functions; 31 interleaved rounds, every run's SVG hash checked
([`phases_ab.py`](../../experiments/schematic-bulkio-20260922/phases_ab.py)).
Inclusive microseconds, medians, 95% paired bootstrap on the difference:

| phase | block I/O | payload I/O | delta | 95% interval |
|---|---:|---:|---:|---|
| `io::load` (×3) | 117.7 | 80.1 | **−37.6** | [−43.2, −35.2] |
| `io::flush` | 104.0 | 62.3 | **−41.7** | [−59.7, −38.3] |
| `sexpr::parse` (×3) | 281.3 | 279.9 | −1.3 | [−15.3, +9.4] |
| `svg::render` | 944.2 | 925.1 | −19.1 | [−72.5, +17.7] |
| `schematic::build` | 563.6 | 598.0 | +34.4 | [+14.7, +54.6] |
| `main::main` | 1924.8 | 1889.5 | −35.2 | [−91.3, +34.6] |

`io::load` and `io::flush` are the only phases whose interval excludes zero in
the intended direction. `schematic::build` moved the other way by a similar
amount although nothing in it changed — that is the machine load, and it is why
`main::main` cannot be resolved in this batch.

Scaling by the batch's own inflation factor (this batch's `main::main` is 1.56×
the parity audit's 1,232 µs) puts the two phases at roughly **75 → 51 µs** for
reading and **67 → 40 µs** for flushing, against the audit's 71 and 59. The
plan predicted 71 → ~25 and 59 → ~15, so the realised saving is about half. What
remains is real work rather than bridge overhead: each document's octets are
still zero-filled and then copied into a fresh managed byte string, and the
flush still copies ~50 KB into runtime scratch before the provider's single
`fwrite`.

### Wall clock

31 interleaved rounds, 3 warmups, three inputs, every SVG hash checked
([`results-bulkio.json`](../../experiments/schematic-bulkio-20260922/results/results-bulkio.json)).
This batch ran while the machine was comparatively quiet:

| arm | fixture, ms | changed-net | changed-value | × Zig (fixture) |
|---|---:|---:|---:|---:|
| `zig-o3` | 1.239 | 1.283 | 1.285 | 1.00 |
| `rust-o3` | 1.399 | 1.361 | 1.386 | 1.13 [1.08, 1.19] |
| before (audit compiler, block I/O) | 2.334 | 2.444 | 2.373 | 1.88 [1.84, 2.01] |
| after (this lane, payload I/O) | 2.332 | 2.387 | 2.351 | 1.88 [1.83, 2.03] |

The difference is inside the interval on all three inputs. Two same-compiler A/B
batches run later, while three other lanes were compiling, are noisier still and
are retained only as provenance: 31 rounds at 3.610 vs 3.689 ms on the fixture
([`results-ab.json`](../../experiments/schematic-bulkio-20260922/results/results-ab.json))
and 61 rounds at 4.979 vs 4.924 ms, payload I/O at ×0.99 [0.97, 1.01] of block
I/O
([`results-ab2.json`](../../experiments/schematic-bulkio-20260922/results/results-ab2.json)).
Both are consistent with no regression and with an effect below their noise
floor; neither can resolve it.
**The wall-clock claim for this lane is "no measurable regression, with a
phase-level saving of about 50 µs"; a quiet machine is needed to see it in the
process time.**

## 4. Validation

| suite | result |
|---|---|
| `zig build test-schematic` | 18/18 pass, including the whole fixture rendered byte-identically **under GC stress at every allocation safepoint** |
| `zig build test-byte-io` | 11/11 pass |
| `zig build test-qbe-build` (includes `tests/qbe_host_bridge.c`) | pass |
| malformed-input differential, 19 cases | before and after agree on **status, printed result, located issue code/file/byte position and published SVG** for every mutant |
| `tests/qbe_host_bridge.c` under ASan + UBSan | pass, no diagnostics, `allocations == frees` |
| `experiments/schematic-bulkio-20260922/provider_checks.c` under ASan + UBSan | pass, no diagnostics |

The differential covers located issues 1, 3, 4, 6, 11, 12, 13, 14, 15, 17, 18,
19, 20 and 21 over 18 mutants plus the valid fixture; byte positions are part of
the comparison, which is what proves `read_document` reproduces each document
exactly where the block loop did.

New runtime-contract coverage in `tests/qbe_host_bridge.c`: copied-argument
isolation, an empty published payload, a written count that disagrees with the
span, a null span with a nonzero size, callback failure, reentry from a payload
callback, a refused guest allocation, the payload ceiling on an argument (before
the callback) and on a result (before publication), a registry ceiling above
64 MiB, and a payload schema whose guest width is not one pointer falling back
to the node bridge and being rejected there. Provider-side coverage in
`provider_checks.c`: per-byte charging, an unsupplied document, exhausted work
before publication, a prefilled output span, a buffered `/dev/full` write whose
failure `finish` reports, a payload past the remaining output capacity, an empty
payload, and the refusing node-bridge fallback.

## 5. Gate

Run through `ZIG_LOCAL_CACHE_DIR=… ~/capbuild`:

| command | exit | note |
|---|---|---|
| `zig build test --summary all` | **1** | 48 failing tests, all pre-existing (see below) |
| `zig build test-qbe --summary all` | **1** | 2 failing tests, both pre-existing, identical on base |
| `zig build test-qbe-build --summary all` | 0 | includes the host-bridge C test |
| `zig build fmt-check` | 0 | |
| `zig build test-schematic --summary all` | 0 | 18/18 |
| `zig build test-byte-io --summary all` | 0 | 11/11 |

`zig build` itself is Guardian-green, so the compiler installs.

### The base branch is red, and this lane is strictly greener

`base/schematic-20260922` does not pass its own gate: an in-flight mutation and
effect-footprint migration leaves `zig build test` at exit 1 with **50** failing
tests plus **2** failing documentation examples, and `zig build test-qbe` at
exit 1 with **2** failing tests and 11 golden mismatches. The same commands were
run on unmodified base sources in this worktree, with the same toolchain and the
same cache, to establish that; both failing sets are retained in
[`base-gate-failures.txt`](../../experiments/schematic-bulkio-20260922/results/base-gate-failures.txt).

Against that reference the lane's results are:

| | base | this lane |
|---|---:|---:|
| `zig build test` failing tests | 50 | **48** (a strict subset — no new failure) |
| `zig build test` failing doc examples | 2 | **0** |
| `zig build test-qbe` failing tests | 2 | 2 (identical set) |
| golden-parity mismatches | 11 | 11 (identical) |
| `zig build test-qbe-build` | pass | pass |

The two tests this lane fixes are `schematic byte callbacks reject positions and
documents the host never supplied` and `schematic bulk buffer boundaries hold
normally and under collection stress`: both staged a `def main(host: Host)`
whose body calls nothing, which the tightened unused-capability rule now rejects
as `E_UNUSED_CAPABILITY`. The two documentation examples are
`docs/experiments/unit-procedures.md` (now spelled `values: mut list[int]` and
`add(mut values, 42)`) and a frozen proposal in `docs/audits/wave3-notes.md`
(now `notest`, because it demonstrates a diagnostic that has since become an
error). Those four fixes are the only changes here outside the lane's own
subject, and they touch files another session is also editing in the main
checkout.

## 6. Known limits

- The saving is about half the plan's estimate. What is left is the managed
  allocation (zero-fill plus copy) for each document and the 50 KB copy into
  runtime scratch on the flush. Removing the argument copy would mean letting a
  provider read guest storage directly, which this ABI deliberately refuses.
- `bytes` is accepted only at the boundary itself. A record containing `bytes`,
  a `list[bytes]` or a `byte_buffer` still has no host representation.
- The payload ceiling is registry-wide rather than per declaration, and a
  `bytes` payload counts as one logical value against the node quota rather than
  one per octet; the octet bound is `max_payload` alone.
- `read_block`, `write_block`, `length`, `byte` and `put` are still declared and
  registered although the guest no longer calls the first three on its own path.
  Each costs one signature check at start-up and keeps the block shapes covered.
- Timing was taken on a machine running three other lanes' builds. Every number
  in §3 should be re-measured on a quiet machine before it is quoted as a
  process-level result.
