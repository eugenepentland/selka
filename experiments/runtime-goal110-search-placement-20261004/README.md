# Diagnostic placement sensitivity above0311796e

This experiment is diagnostic only and is not a production candidate or goal
confirmation. Production/benchmark sources, ordinary LLVM O3/full-LTO flags,
the031 compiler/assets and G4 controls remain unchanged. No exact padding or
benchmark symbol predicate is proposed for production.

A transparent private Zig wrapper captured the normal full-LTO assembly and
first reproduced the031 ELF exactly: SHA892b089c25a316f80d8ad000d93125f59ffa871893d3d15526e7b05bb29319a0.
Disposable zero-byte symbol aliases mapped .LBB3_192 to offset0xd60 of the
linked kernel. A separate private build inserted32 one-byte NOPs immediately
before that verified label, before existing frame-map annotation. Its SHA is
93e203f451cf110a702dbb60ce7d47d8075b2faa50577a2df35b6a45ff8856ef.

Complete raw and annotated assembly are otherwise byte-identical. The final
whole caller and scanner/index-walk/large-octet-equality helpers normalize
identically, including loaded constant bytes. The repeated backedge skips
the fill; the first fallthrough may execute it once. The caller loop returns
to address0x104f550/mod64=16 from0x104f530/mod64=48. The scanner's entry stays
fixed. Another167 text symbols move+32, and the kernel grows32 bytes; all
symbol movement/size changes are listed. No data-symbol movement was found.
Frame metadata retains identical assembly labels/directives and relocates
through the ordinary assembler/linker. Two hundred ordinary frozen text
oracle records pass, with complete process streams and clock protocol.

The approved immutable three-artifact diagnostic ran two unchanged031
six-arm plans, CPU2,15 rounds/3 warmups, randomized paired order and the
internal timing lock. It retained108 full process outcomes and host/cgroup
snapshots. UTC interval:2026-10-04T10:52:52.552766Z through10:52:57.796596Z;
session5157a204-eead-4030-a6c7-a374f5112514. Exact command/helper bindings are
in commands.json.gz (SHA589e6d2744a11b71b3f7484a618283f453c3aef2bc961af0e8d6afacd515ba58).

| Row | G4 ns/op | 031 ns/op | Fill32 ns/op | 031/G4 | Fill32/G4 (paired95%) |
|---|---:|---:|---:|---:|---:|
| Equality, small | 3.8982275 | 3.5647516 | 3.5551870 | 0.914454 | 0.912001 [0.904731,0.916645] |
| Search, large | 82.3331953 | 94.6079074 | 82.9904362 | 1.149086 | 1.007983 [1.000123,1.011086] |

Fill32/031 is0.997317 [0.993198,1.003151] for equality and0.877204
[0.873740,0.880073] for search. `analyze.py` replays all108 outcomes and
resamples the same15 paired round indices,20,000 deterministic draws per
ratio, seeded by case/profile/numerator/denominator. These are pointwise
95% percentile intervals, excluding multiplicity and systematic host noise.
Root independently replayed assembly identity,8 live objdumps, tool/artifact
bindings and200 closed-form text oracles before timing.

The counterfactual establishes placement sensitivity while retaining the
annotation's equality benefit. Because later text moves too, it does not
uniquely attribute the recovery to caller address. A future general policy
must use natural-loop analysis and supported LLVM alignment metadata, with
code-size and regression controls; these exact NOPs cannot become production.
The original031 candidate remains unintegrated pending that separate work.

`evidence.json` binds all raw gzip files and helpers. Actual argv, real Zig,
RSP files, tool stdout/stderr, raw/final assembly, source-bound build reports,
mapping proof, code proof, text outcomes, before/after artifact validation,
timing streams and intervals are preserved. Live immutable ELF/bitcode/archive
inputs are bound and retained in private caches, not committed as executables.
Source evidence is additionally pinned by031 archive641506e1 and its index
SHA5cdcf0b6053ee09a9d325f837fbc168c4311188b2b699ed1d5282f281d939e3b.

General alignment interface references:
[LLVM llvm.loop.align](https://llvm.org/docs/LangRef.html#llvm-loop-align-metadata)
and [Clang code_align](https://clang.llvm.org/docs/AttributeReference.html#clang-code-align).
