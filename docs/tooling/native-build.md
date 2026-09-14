# Native builds

`mylang build` turns a checked guest program into a Linux x86-64 executable or
shared library. The compiler drives the whole pipeline itself: it lowers the
checked program to bytecode, renders that as QBE intermediate code, runs QBE,
assembles and links, and bundles the native runtime sources it needs. There is no
installer script, no `make`, and no compiler source checkout in the loop. The
design record is
[incremental QBE native compilation](../experiments/incremental-qbe.md).

Bytecode is still part of the compiler, but only as that internal IR. Nothing
executes it: there is no interpreter, and QBE is the only backend. `mylang run`
is this same pipeline followed by running the result, and `dump-bytecode`
disassembles the IR for inspection rather than for execution.

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

## Object cache and link

Everything a build compiles is content addressed under `--cache-dir`
(`.mylang-cache/qbe` by default): one object per guest function, one for the
generated typed-metadata unit, and one for the generated entry adapter. Their
keys cover the compiler's own build-time identity, the runtime content hash, the
Zig and QBE tool stamps, and the target and optimize mode, so a changed tool or
mode never reuses an object built by another one.

The fixed runtime translation units are not linked as loose objects. A single
`zig build-obj` compiles all of them in one process into one relocatable object —
a cold build pays one toolchain start rather than one per unit — and that object
becomes the single member of an archive published beside the objects. The link
places the archive after every object that can reference it. Because the merge
keeps every unit's function and data sections and the link collects unreferenced
ones, a program that never prints still carries no printing runtime. A build that
changes nothing relinks nothing observable: the candidate
and the published executable are compared by length and then by bytes, and an
identical result keeps its inode and modification time, which `--report` shows as
`"output_changed": false`.

A cached object or archive is accepted only when a fingerprint over its length
and contents matches the one stored beside it in a `.digest` file. Damaged bytes
and a damaged fingerprint are both misses, so a corrupt cache repairs the one
entry it lost rather than failing the build or silently linking rubble. Cache
keys stay on SHA-256 because they name small inputs; verification uses the
cheaper fingerprint because a warm build re-reads megabytes of stored objects and
a cryptographic pass over them costs more than the link it protects.

```console
$ mylang build examples/factorial.my -o /tmp/factorial --cache-dir /tmp/qbe-cache --report
{"version":"qbe-build-v1","output":"/tmp/factorial","output_changed":true,...}
$ mylang build examples/factorial.my -o /tmp/factorial --cache-dir /tmp/qbe-cache --report
{"version":"qbe-build-v1","output":"/tmp/factorial","output_changed":false,...}
```

## Prebuilt runtime archive

Compiling the runtime is the only real work a cold build does — everything else
is codegen and a link measured in tens of milliseconds. So `zig build` does that
work once, when it builds the compiler: it prebuilds the runtime archive and the
text-formatter object for each optimize mode and installs them beside the compiler
under `zig-out/lib/mylang-runtime/`, each named by a portable hash of the runtime
content hash, the pinned Zig version, the optimize mode and the target. `mylang`
finds this directory relative to its own executable, the same way it finds the
sibling `qbe`.

A cold `mylang build` computes the hash its runtime needs and, if a matching
archive is installed, links it directly and skips compiling the runtime from
source — `--report` shows `"runtime_installed": true`. The prebuilt hash excludes
the Zig and QBE tool file stamps that object-cache keys carry, so an installed
archive still matches a build that resolved those tools from a different path. A
missing archive (a cross-target build, or a relocated compiler with no `lib`
beside it), a mode with no matching install, or a corrupted file whose fingerprint
no longer matches the `.digest` published beside it all fall back cleanly to
compiling the runtime from source in one `zig build-obj`.

## Runtime source tree and shared caches

The build also needs the runtime C sources and headers on disk, because the
generated entry and metadata objects `#include` them. That tree materializes once
per content hash, and where it lands follows the cache selection:

- **`--cache-dir DIR`** keeps everything hermetically under `DIR`: objects in
  `DIR`, the runtime tree in `DIR/runtime/<hash>`. Nothing outside `DIR` is read
  or written, which is what the test suite relies on for isolation.
- **The default (no `--cache-dir`)** keeps the per-project object cache at
  `.mylang-cache/qbe` but shares the runtime tree at a user-level location —
  `$XDG_CACHE_HOME/mylang/runtime/<hash>`, falling back to
  `$HOME/.cache/mylang/runtime/<hash>`, and to the per-project cache only when
  neither variable names an absolute home. A brand-new project therefore reuses a
  runtime tree another project already derived, and the installed archive means it
  compiles no runtime at all on its first build.

Concurrent builds sharing either location stage the tree into a private directory
and rename it into place, so no build ever observes a partial tree.
