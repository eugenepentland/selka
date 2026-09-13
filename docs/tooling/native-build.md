# Native builds

`mylang build` turns a checked guest program into a Linux x86-64 executable or
shared library. The compiler drives the whole pipeline itself: it emits QBE
intermediate code, runs QBE, assembles and links, and bundles the native runtime
sources it needs. There is no installer script, no `make`, and no compiler source
checkout in the loop. The design record is
[incremental QBE native compilation](../experiments/incremental-qbe.md).

## `mylang build`

`mylang build <file.my> -o <output>` checks the program, lowers it, compiles one
independently cached object per guest function and links those objects with the
bundled runtime. `--run` replaces `-o`: it executes a temporary binary with
inherited stdin, stdout, stderr and working directory, returns that program's
exit status, and removes the binary afterwards while keeping the cached objects;
runtime options go after `--`, including the same `--restrict` and `--allow-*`
capability options `mylang run` takes: a native executable grants every
capability by default and `--restrict` denies them. Build tools resolve from `--qbe`/`--zig` first,
then from executables sitting beside the running `mylang`, then from `PATH`, and
never from the working directory. `amd64_sysv` is the only supported target, a
module entry needs `--project`, `--library` produces a shared library, and a
program using a construct the native backend does not implement fails with
`E_QBE_UNSUPPORTED` before any output is written. `--report` adds one
`qbe-build-v1` JSON line naming every compiled function, its cached object and
whether that object was reused; `zig build test-qbe-build` runs
`tests/qbe_build_cli.py`, which repeats these builds through a relocated
compiler with no Python on `PATH`.

```console
$ mylang build examples/factorial.my -o /tmp/factorial --cache-dir /tmp/qbe-cache
$ /tmp/factorial
120
$ mylang build examples/factorial.my --run --cache-dir /tmp/qbe-cache
120
```
