# Vendored third-party sources

## `qbe/` — QBE 1.3

The QBE backend, MIT licensed (see `qbe/LICENSE`). Upstream release archive:
<https://c9x.me/compile/release/qbe-1.3.tar.xz>
(`sha256 d587905d620dc5e1d2bfa7c2cc642b9b837aa89a3188c6e37b53d756cf66e320`).

`zig build` compiles this tree into `zig-out/bin/qbe` with the repository's pinned
Zig toolchain, so a native `mylang build` needs no separate QBE installation and no
Python. The pinned version is recorded in `.qbeversion`; `build.zig` refuses to
build if that file and the vendored tree disagree.

Only the compiler sources are vendored: the release's root `*.c`/`*.h`, the
`amd64/`, `arm64/` and `rv64/` backends, `LICENSE` and `README`. The upstream test
corpus, `doc/`, `minic/`, `tools/` and the `Makefile` are not vendored. `config.h`
is written here rather than generated, pinning the default target to `amd64_sysv`.

### Local changes

These changes depart from the 1.3 release, marked `mylang local change` in the
source; reapply them when updating:

- `rega.c`: the parallel-move table `pm` grows on demand instead of dying with
  `no more pm slots` past 64 copies. A block edge moves one value per phi of
  its successor plus one per temporary live into it, which valid IL can push
  past any fixed bound (a loop header carrying 65 phis is enough).
- `copy.c`: phi reuse preserves the result class. Phis with identical incoming
  values reuse a previous phi only when their classes match, and a dominating
  word boolean branch argument replaces only a word phi. Replacing a long phi
  with a word result otherwise leaves half of a spill undefined or narrows a
  64-bit value; executable regressions cover both rules in `tests/qbe_phi_width.*`.

### Updating

Download the new release archive, verify its published checksum, copy the same
subset over `qbe/`, keep `config.h`, reapply the local changes above, and update `.qbeversion` and this file.
