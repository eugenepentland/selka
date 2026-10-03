# Unaccounted constant-read ELF qualification

This stage checks the actual native guest ELFs for source candidate 58fe1925,
separately from the earlier 340 accounted public-test passes. It uses immutable
compiler d14a7040 and adjacent QBE 99ad919d. The existing readonly RC LLVM/QBE
binaries are reused byte-for-byte; new GC binaries have separate scratch paths.
No prototype, root source, canonical patch, or prior binary is overwritten.

`build-gc.py` builds GC guests with the same source 37 snapshot as the frozen RC
build receipt. LLVM uses O3 and full LTO; both backends retain native symbols.
`validate.py` invokes the known root tree-validation helper without resume,
using the same 16 focused VM-callee programs, 13 smoke programs and 23 historical
errors per evaluator. It records exact status, stdout, stderr and Lox statistics
against selected combined84 RC controls, with Lox stress off/on in every cell.

The expected bounded matrix is 1168 unique candidate/control comparisons:
416 RC, 416 ordinary tracing-GC and 336 native-GC-stress. Native stress means
`MYLANG_OPTIONS=--gc-stress`; guest `--gc-stress` separately enables Lox stress.
All focused programs and errors run under native stress. Only closures,
instantiation and properties smokes run with native stress: 80 other native-smoke
cells are explicitly unrun. They are omissions, never passes.

An additional 12 comparisons execute all constant operand bytes 0..255 on the
actual unaccounted VM ELFs across both backends, all three runtime modes and
Lox stress off/on. Eight separate RC native-stress pairs must produce the same
checked refusal as their controls (status 2, empty stdout, diagnostic requiring
`--gc-runtime`); they are refusals, never program passes.

The runner snapshots all 37 files of each frozen source, compiler and QBE,
every actual ELF and its manifest/receipt/runtime archive, harnesses, focused
cases, pinned bench inputs, historical errors and the pinned SPEC before and
after. It asserts full pair equality, unique/disjoint run and unrun identities,
complete matrix coverage and unchanged hashes. The build-slot launcher excludes
CPUs 2, 3, 10, 11. This stage runs behavior checks only, with no timing or counter
claims. Native helper attribution for malformed internal bytecode retains the
source-refactor limitation already recorded in the primary candidate review.

Completed qualification: 1168 bounded comparisons, 12 operand-boundary comparisons
and 8 checked refusal pairs passed, with all frozen identities unchanged. Raw
observations and full before/after identity maps are retained in deterministic
gzip receipts. `validation.json` gives counts, binary/source identities, runner
affinity, explicit omissions and receipt hashes. Generated input files were also
rehashed after completion against every recorded sample/omission.
