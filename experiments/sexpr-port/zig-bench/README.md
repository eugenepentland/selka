# zig-bench — the Zig side of the speed comparison

A deliberately tiny Zig project that compiles **only the S-expression closure**
of the sibling `eda` checkout, so `zig build` measures building this reader
rather than the whole EDA application.

```
main.zig            census / --render driver (mirrors experiments/sexpr-port/main.my)
build.zig           one executable; -Doptimize=ReleaseFast|ReleaseSafe|Debug
src/sexpr/*.zig     verbatim copies from eda/src/sexpr (ast, tokenizer, parser, printer)
src/infra/fs.zig    verbatim copy of the one infra file printer.zig imports
sync_from_eda.sh    re-copies the above and records the source revision
EDA_REVISION        the eda commit the copies came from
```

## Build

Zig 0.17's `zig build` has no `--cache-dir`; the cache roots are environment
variables. `bench.py` sets both so its "cold" is genuinely cold and your own
`~/.cache/zig` is untouched:

```sh
ZIG_LOCAL_CACHE_DIR=/tmp/local ZIG_GLOBAL_CACHE_DIR=/tmp/global \
  zig build -Doptimize=ReleaseFast -p /tmp/out
/tmp/out/bin/zig-bench /path/to/input.sexp            # census
/tmp/out/bin/zig-bench /path/to/input.sexp --render    # canonical rendering
```

`infra/fs.zig` reads `@import("root").process_io`, so `main.zig` declares
`pub var process_io` and takes `std.process.Init` — the same non-negotiable pair
the golden harness documents.

## Why this is the fair comparison

The mylang side (`experiments/sexpr-port/sexpr/*.my` plus `main.my`) is ~1000
lines that compile to one executable. Building the *whole* `eda` binary would
charge the Zig reader for the other ~200k lines of the application, so the
benchmark vendors just the reader and its one import instead. The corpus is the
same file, the workloads are the same two (walk the tree; render it), and the
compiler is the same installed Zig toolchain for both sides.
