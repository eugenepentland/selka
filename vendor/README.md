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

### Updating

Download the new release archive, verify its published checksum, copy the same
subset over `qbe/`, keep `config.h`, and update `.qbeversion` and this file.
