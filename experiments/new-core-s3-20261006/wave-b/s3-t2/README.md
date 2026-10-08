# S3-T2: mutable bytes and exact number text

Source commits: implementation `71cfa45aecf9a81027494989d0c4bdb17a613b00`, final fixture/qualification `52a9e1ef8ca00775a5d4ac1e24b6f920eacf9766`, cut from the qualified
8-shard bootstrap `8918de74720f0832dabe5802c110cd0518324cf5`. This package has not
been merged into `main` or pushed. Qualification below uses that frozen source;
only evidence under `experiments/` is written afterwards.

## Implementation and ownership

Mutable bytes use the frozen kind-5 leaf pointer and 32-byte block header. Push,
set, pop and copy use the S3-0 operations and ordinary one-count COW pass; existing
verify-mode uniqueness assertions still guard the pass's premises. Buffer copies,
conversions and immutable snapshots preserve independent value semantics, including
record-place write-back. Reserve, valid/invalid append, UTF-8, integer/float append,
hex and decoding operate on octet lengths. Readonly methods reuse the qualified
T1 borrowed helpers without asserting text cache facts for mutable buffers.

Embedded blobs resolve the checked length/digest against `Source.embeds` and source
origins. Immutable constants preserve NULs, non-UTF-8 octets, empty content and
text scalar lengths. Missing content produces a precise refusal. Source-aware
builder/coverage wrappers keep the old entry points valid; pipeline, CLI and the
two test-runner root-building callsites forward the loaded Source.

The separately compiled Zig unit ports the complete old `number_text.zig` and
`format_spec.zig` algorithms into the Core namespace. Float spelling follows the
old Zig formatter, including integral `.0`, signed zero, nonfinite values and
rounding. No old runtime object or `native_format` unit is linked. Integer-only
programs keep the S2 inline parser and decimal formatter. Rendering declares no
false ASCII fact when a format's fill may contain Unicode; parsed floats have no
finite/non-NaN premise.

The coordinator approved a narrow improvement to the design's initial output-slot
strategy: scalar `Option[int]` and `Option[float]` helpers return 16-byte C/Zig
structs directly through the existing frozen `runtime_c` external-call lowering.
The low byte of the integer tag register is 0/1, and the scalar payload uses
`rdx`/`xmm0` on the frozen x86-64 SysV target. Emitted LLVM returns `{i8,i64}` or
`{i8,double}` without `sret` or a hidden heap box. Explicit C layout assertions,
`noalloc` source functions and signed-limit/None/nonfinite ABI fixtures cover both
returns. This does not extend source `extern` signatures or change frozen IR.
`scalar-option-abi.json` and the retained parser functions record the evidence.

Dependencies copied for qualification are the M scalar checkpoint `8535295d` and
conversion-facts fix `dcc3841c`, plus the exact T1 helper files from `ade0ce29`.
The T1 verify-only length snapshots prevent reloading a bound from a block whose
ordinary RC lifetime has ended. T2 adds only dispatch/type/source/driver hooks,
byte lowering and byte-typed immortal constants around those shared dependencies.
`dependencies-final.json`, `shared-review-final.patch` and `runner-source.patch`
identify the exact combined source and small runner patch for deduplication.
The root coordinates the full old gate; no shared checker, old compiler,
persisted format, `tests/lang` fixture or frozen IR file changed here.

## Qualification

All build commands use `scripts/build-slot.sh build`. Core rebuilds and test-core
hold gate and build locks together; the meaningful rebuild also excludes every
other build through `wave-a/exclusive_core.py`. Command times exclude admission.
The qualified D2 oracle is copied into the private cache with SHA256
`feb7914ba50d0649180a5257b11f1a821930b40afd18b4f48f0d503127a80073` and its adjacent QBE.
Every command has a separate log. Preview failures and earlier cache measurements
remain evidence, and are not substituted for the final frozen-source runs.

Final source and qualification gates are green; the evidence-only commit accompanies this report.

The initial default-8 run retained in `67-cheap-gates.log` reported 225/226 passing
fixtures in 94.83 s, with its slowest shard 92.44 s. The single failure was a stale
S3-0 assertion: the fresh buffer fixture printed its intentionally read byte,
`42`, while the expectation still described the unimplemented runtime. The
follow-up source commit changes only that stdout expectation. In accordance with
plan §5, the final core gate uses 16 shards.

## Final gates on the frozen source

| Gate | Result | Evidence |
|---|---|---|
| Meaningful uncontended core rebuild | 2.60 s on implementation source; test-only follow-up cached 0.01 s | `67-cheap-gates.log`, `69-cheap-gates.log`, `qualified-gates/core-build.txt` |
| Held core tests | 226 pass, 67.45 s, 16 shards; longest 65.81 s; compiler 336M / runner 207M | `qualified-gates/test-core.txt` |
| Full old/new conformance | debug and release each 1,397 matching, 0 mismatching, 121 precise refusals / 1,518; 155.94 s | `qualified-gates/conformance.txt` |
| Own strict leak/verify | debug and verified release each 67 matching, 0 mismatching, 1 existing refusal / 68; 6.01 s; process status and stdout checked | `70-own-strict-final.log` |
| Extended number fuzz | seed 731, 50 accepted, 750 comparisons, 1,000 native runs; 293.16 s; zero wrong answers, refusals, old rejects, build failures, fact failures, leaks or crashes | `74-fuzz-final.log`, `fuzz-final/summary.json` |
| Existing definitions | all 35 S0/S1/S2 benchmark programs identical to 92590700, 4.30 s | `72-code-identity-final.log` |
| Affected rows | all checksums agree; every row <=1.10 versus Zig ReleaseSafe and old core at both sizes | `75-rows-final.log`, `rows-final.json`, `rows-both-gates.json` |
| Coverage | 3,456 / 3,595 functions accepted; 5,538 proven / 4,216 exact checks; 2.73 s; every remaining first-refusal reason retained | `73-coverage-final.log` |
| Guardian | 88 checks pass, including ordinary hooks on both source commits | `61-guardian.log`, `66-source-commit.log`, `68-fixture-commit.log` |

Final rows use seven interleaved rounds on CPU 10 with the accepted startup subtraction,
the shared CPU lock and the unchanged Rust/Zig runtime-baseline checkout:

| Row | New/Zig, 4096 | New/Zig, 64 | New/old, 4096 | New/old, 64 |
|---|---:|---:|---:|---:|
| int_parse | 0.978 | 1.089 | 0.617 | 0.641 |
| int_format | 0.319 | 0.317 | 0.310 | 0.289 |
| bytes_scan | 0.038 | 0.136 | 0.632 | 0.986 |

Strict own files are `byte_buffer`, `byte_buffer_from_list`, `python_bytes`,
`byte_ranges_llvm`, `integer_text`, `float_constants`, `float_nan`, `format_specs`
and the five new number/buffer/blob/packet/ABI fixture files. All required byte,
number and formatter files are fully supported; the one extra `float_nan.contains`
refusal is aggregate membership owned by S3-M. All ten public new fixture pins
match the oracle, including the copied packet decoder's frame/checksum logic.
Full conformance's remaining 121 refusals are recorded by name/reason and await
the other packages/integration. This package does not claim the final S3 exit.

## Float runtime cold cost and cache

`71-float-cold-final.log` and `float-cold-final/` measure three different fresh
program sources. The first uses both a fresh runtime-object directory and a fresh
Zig global cache for `build-obj`: total program 3.11696 s, of which compiling the
independent float-text unit takes 0.96559 s. The next program reuses the same keyed
object, builds in 0.11394 s and launches zero formatter compilations. An explicitly
simulated Zig version suffix forces a new object key and a new compile (0.88146 s);
the actual compiler remains `0.17.0-dev.1683+5ceec001b`. The experiment does not
claim that a second real Zig installation was used. Pure tests independently show
helper-content, target and build-option invalidation. Every measurement's native
program exits 0, prints exactly `-0.0 0.12 True\n`, and has no leak/fact output.

`runtime-cache-key.json` lists every complete helper hash and every explicit
compiler option. The final object key is
`714db03fe3fa391c9b5a852fe8b845a55a788be7cbede44ff2b90ac1dbe77348`.
Per-program source staging and unique partial objects avoid concurrent miss writes;
atomic publication shares the final complete content/toolchain-keyed object.
The driver checks LLVM declarations as well as calls, so M's aggregate renderer's
float dependency also triggers the object. Integer-only row definitions stay exact.

## Commands and limits

`wave-a/check_merge.py --root . --stage s3-t2-qualified-16 --core-shards 16
--mylang .mylang-cache/s3/d2-oracle/mylang` runs the final retained core rebuild,
held tests and full strict conformance. The logs retain its exact wrapped argv,
source commit, command duration and admission duration. `70-own-wrapper.log`
accompanies the strict own/float-cold/identity/coverage sequence. The fuzz command
is `scripts/build-slot.sh build -- nice -n 10 python3
experiments/new-core-s2-20261005/wave-a/integration/fuzz_qualification.py --kind
number --cases 50 --seed 731 --mylang .mylang-cache/s3/d2-oracle/mylang --core
zig-out/bin/mylang-core --evidence experiments/new-core-s3-20261006/wave-b/s3-t2/fuzz-final
--cache-root .mylang-cache/s3/t2-fuzz-final`. Row JSON retains every timed argv,
status, checksum and cycle measurement. No timing CPU 2, 3 or 11 was used.

No remaining T2 feature refusal is introduced. The direct scalar Option runtime
ABI is restricted to the frozen x86-64 SysV target; the source foreign boundary
remains scalar/pointer only. First float use pays the separately measured unit
compile. Coverage's scratch copies still report four missing embedded paths;
those existing harness frontend counts do not invalidate actual embedded assets,
which pass the two direct public blob tests. No new facts/stack promotion,
record-phi emptying, persisted-format change or language-rule change was made.
The coordinator appends and commits the shared Guardian feedback entry serially.
