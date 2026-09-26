# Flat release diagnostics

`native-drop.json` measures three interleaved depth-12 binary-tree instruction
runs per backend, with the unchanged source/output from
`../d9-rc-pointer-fastpath-20260926/`. The baseline is `5acc3f20`; the candidate
adds only the cached native-drop path. Both compilers are Debug. LLVM is
explicitly `--backend=llvm --llvm-opt=3 --lto` without later QBE overrides;
manifests are checked. Instrumented artifacts separately prove exact complete
counter equality. These private CPU0 diagnostics are not corpus acceptance.

`copy-drop.c` isolates 500,000 production-runtime copies/drops of eight repeated
ordinary owner leaves under a closed allocation budget. It retains real source
owners, checks the resulting count on every iteration, and retires everything.
`micro.json` records three interleaved before/after instruction runs using C
`-O2`, strict warnings, function/data sections and linker section collection.
Build against the ordinary native heap/arena/collection/text/dictionary/equality/
bytes and RC source closure. All sources are identical except
`native_rc_values.c` and `native_rc_walk.c`, taken from `5acc3f20` for the baseline.
The measurement includes both copy and drop; it is not a pure-drop estimate.

`object-body.json` repeats all three arms after extending the same cached plan
to ordinary object bodies in the drain. Each arm retains its own compiler
binary and runtime-source identity. This join changes no compiler lowering.
`object-body-profile.txt` samples 24 QBE runs at 997 Hz with `perf record -e
cycles:u`, filters the guest executable DSO, and reports self symbols; about
3,000 samples were retained with none lost. The `make` symbol begins
`myl_f_d05aa2a1`; `check` begins `myl_f_20f65c28`. The profile remains diagnostic,
not timing/corpus evidence.

`cumulative.json` joins the compiler integration at `c09fce2b` and compares RC
with fresh GC from that same compiler, plus the frozen GC control.
`cumulative-profile.txt` uses the same 24-run sampling method, with no lost
samples. `cumulative-make.asm.gz` and `cumulative-make-profile.txt.gz` retain the
actual generated constructor and its local-period annotated profile.
