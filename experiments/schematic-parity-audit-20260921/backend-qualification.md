# Native LLVM backend qualification

21 September 2026. This evidence qualifies backend selection, cache identity,
installed-package discovery and the checked full-LTO path on `examples/sum.my`.
It is a build-path qualification, not a schematic performance measurement. The
relocation probe covers the installed compiler package (`bin/mylang` beside
`lib/mylang-llvm`); it does not claim a separate relocated schematic-host test.
Machine-readable hashes and observed keys are in `backend-qualification.json`.

The explicit optimization probe used one cache for LLVM O3, LLVM O2 and a second
LLVM O2 build. O3 to O2 compiled both functions and reused none; the repeat O2
build compiled none and reused both. The legacy-compatible form, naming
`qbe_llvm.py` through `--qbe` and changing only `MYLANG_QBE_LLVM_OPT=-O3` to
`-O2`, also compiled both functions and reused none. Both receipts identified
the effective backend as LLVM and recorded the effective optimization.

The adapter dependency probe copied the installed four-file adapter package,
built once, changed only a comment in the imported `llvm_emit.py`, and built
again in the same cache. Both function keys changed and both functions rebuilt.
The installed-package probe copied `mylang` and `lib/mylang-llvm` into a new
prefix and successfully built with `--backend llvm --llvm-opt 3` without an
explicit adapter path.

The full-LTO probe recorded `backend=llvm`, `optimization=3`, `lto=true` and
`runtime_installed=false`. The guest function object was LLVM bitcode. All 19
members of the rebuilt runtime archive began with `42 43 c0 de`; no native ELF
member was found. The linked executable ran and returned 86, the low byte of
`sum_to(100)`.

## Reproduction

Use a fresh cache directory for each group if prior local evidence is not being
reused. Every build below emits its receipt on stdout and writes an adjacent
`.qbe-manifest.json` sidecar.

```sh
# Explicit optimization invalidation and stable reuse.
zig-out/bin/mylang build examples/sum.my -o /tmp/mylang-llvm-o3 \
  --backend llvm --llvm-opt 3 --report --cache-dir /tmp/mylang-llvm-cache
zig-out/bin/mylang build examples/sum.my -o /tmp/mylang-llvm-o2 \
  --backend llvm --llvm-opt 2 --report --cache-dir /tmp/mylang-llvm-cache
zig-out/bin/mylang build examples/sum.my -o /tmp/mylang-llvm-o2-repeat \
  --backend llvm --llvm-opt 2 --report --cache-dir /tmp/mylang-llvm-cache

# Legacy adapter environment invalidation. COPY is a copied installed adapter package.
MYLANG_QBE_LLVM_OPT=-O3 zig-out/bin/mylang build examples/sum.my \
  -o /tmp/mylang-legacy-o3 --qbe "$COPY/qbe_llvm.py" --report \
  --cache-dir /tmp/mylang-legacy-cache
MYLANG_QBE_LLVM_OPT=-O2 zig-out/bin/mylang build examples/sum.my \
  -o /tmp/mylang-legacy-o2 --qbe "$COPY/qbe_llvm.py" --report \
  --cache-dir /tmp/mylang-legacy-cache

# Full LTO and installed-runtime bypass.
zig-out/bin/mylang build examples/sum.my -o /tmp/mylang-llvm-lto \
  --backend llvm --llvm-opt 3 --lto --report \
  --cache-dir /tmp/mylang-llvm-lto-cache
```

Verify every archive member, rather than sampling only the first:

```sh
runtime=$(python3 -c 'import json; print(json.load(open("/tmp/mylang-llvm-lto.qbe-manifest.json"))["runtime_object"])')
count=0
bad=0
for member in $(ar t "$runtime"); do
  count=$((count + 1))
  magic=$(ar p "$runtime" "$member" | xxd -p -l 4)
  test "$magic" = 4243c0de || bad=$((bad + 1))
done
test "$count" = 19
test "$bad" = 0
```

For dependency invalidation, copy all four installed Python files together,
build with `--llvm-adapter COPY/qbe_llvm.py`, make a content-only edit to copied
`llvm_emit.py`, and repeat with the same cache. For relocation, reproduce an
independent prefix containing `bin/mylang` and `lib/mylang-llvm/*.py`, then run
the explicit LLVM build without `--llvm-adapter`.
