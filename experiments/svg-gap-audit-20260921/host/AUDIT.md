# Host I/O gap audit

The qualified SVG guest makes 105,060 host calls for `fixture` and
`changed-value`, and 105,266 for `changed-net`. Only six calls per run establish
the three document identities and lengths. The rest are scalar byte traffic.

| case | input bytes | `io::byte` | read amplification | SVG bytes / `io::put` |
|---|---:|---:|---:|---:|
| fixture | 25,845 | 55,437 | 2.145x | 49,617 |
| changed-net | 25,863 | 55,613 | 2.150x | 49,647 |
| changed-value | 25,845 | 55,437 | 2.145x | 49,617 |

The Rust, Go, and Zig ports use whole-file reads and build the SVG in memory
before one whole-file write. This comparison does not prove that host calls
account for the full native gap: the guest also repeatedly indexes source spans,
whereas the ports' owned byte arrays make those accesses ordinary loads.

## Reproduction

From the repository root:

```sh
experiments/svg-gap-audit-20260921/host/build.sh
python3 experiments/svg-gap-audit-20260921/host/qualify.py
```

For measurement, use the same environment and invocation as
`experiments/svg-arenas-20260921/run.py`, replacing its executable with one of:

```text
.tmp/svg-gap-audit-20260921/host/control
.tmp/svg-gap-audit-20260921/host/unchecked
.tmp/svg-gap-audit-20260921/host/memory-output
.tmp/svg-gap-audit-20260921/host/metadata-control
.tmp/svg-gap-audit-20260921/host/typed-host
```

The counter arm is deliberately separate from timed binaries. Set
`MYLANG_HOST_COUNTS=1` when invoking `counts`; it emits `HOST_COUNT` records on
stderr at exit.

## Production directions

The highest-value API change is a borrowed, bounded input view. A provider can
load each document once, and the guest can index its bytes without a callback.
That needs a lifetime-bearing capability or an opaque handle plus a compiler
intrinsic; exposing a raw pointer through the copied-value host ABI would break
isolation and make provider lifetime errors memory-safety errors. Bounds must
remain checked, and work accounting needs to charge either acquisition bytes or
indexed accesses according to the intended denial-of-service policy.

For output, add a bounded block write that accepts a byte slice or a fixed block
plus count. The existing byte-I/O pilot demonstrates fixed-array host values,
but applying that shape directly would serialize every element into
`MylangHostNode`s and would require padding. A useful implementation needs a
special packed-byte bridge in generated host wrappers. Guest SVG code then needs
a small buffer and explicit flush. Error timing changes at flush boundaries, so
the API must define partial writes and preserve the current `HostFailure` path.

The compiler can also emit typed wrappers for scalar-only declarations. Today
every byte builds `MylangHostNode`s, calls through a registry function pointer,
compares result type strings, and copies bits back. Initialization already
checks the registry signatures, so a generated, program-specific adapter could
cache a typed thunk after that check. The thunk must retain reentry, call/work,
capability, output-count, and scalar-range checks. This is less likely to match
the benefit of eliminating roughly 105,000 crossings, and it expands the ABI
surface and test matrix across QBE/LLVM and LTO modes.

The `typed-host` diagnostic prices that direction for the two dominant calls.
It uses the exact same retained LTO guest objects as `metadata-control`; only
the regenerated metadata and provider objects differ. Its typed helpers keep
document/output bounds and I/O failures, while the wrapper keeps call/work and
reentry state. The removed copied-node checks are listed in `README.md`.

`unchecked` and `memory-output` are ceilings only. Their removed contracts are
documented in `README.md` and are intentionally unacceptable for production.
