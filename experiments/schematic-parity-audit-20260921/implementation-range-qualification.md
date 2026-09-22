# Host bridge and byte-range implementation qualification

21 September 2026. Commands ran from the repository root with fresh private
caches. The installed compiler was `zig-out/bin/mylang`, rebuilt from the
implementation tree before the final qualification.

## Byte-range qualification

The focused source fixture is
`tests/lang/byte_ranges_llvm.my`. It checks allocation-free integer and float
range parsing, negative and reversed endpoints, signed 64-bit minimum and
overflow, Unicode scalar counting, malformed UTF-8 and the exact checked error
message. The run used LLVM O3, full LTO, a fresh cache and the stress collector:

```sh
range_cache=$(mktemp -d /tmp/mylang-byte-ranges-llvm-lto.XXXXXX)
MYLANG_QBE_LLVM_OPT=-O3 zig-out/bin/mylang build \
  tests/lang/byte_ranges_llvm.my --run \
  --backend llvm \
  --llvm-adapter /home/epentland/ai/canopy/mylang/experiments/llvm-backend/qbe_llvm.py \
  --llvm-opt 3 --lto --cache-dir="$range_cache" --report -- --gc-stress
```

Result: exit 0; `backend=llvm`, `optimization=3`, `lto=true`; two functions
compiled and none reused.

The QBE unit qualification was:

```sh
zig build test-units -Dtest-filter='range parsing and scalar counting'
zig build test-units -Dtest-filter='PY-BYTES'
```

The focused run explicitly selected
`PY-BYTES-RANGE-1 range parsing and scalar counting clamp without a view
allocation` and passed 12/12 tests. It includes a dynamically allocated empty
byte string, proving that a clamped empty range does not perform null pointer
arithmetic. The wider byte run passed 20/20 tests, including nine named byte
tests and eleven unconditional test blocks.

## S-expression replacement qualification

The five transient expressions replaced in production are four
`view(...).parse_int/parse_float` calls in `sexpr/parser.my` and one
`view(...).scalar_count` call in `sexpr/printer.my`. The ordinary project suite
with the replacements passed completely:

```sh
sexpr_cache=$(mktemp -d /tmp/mylang-sexpr-final.XXXXXX)
zig-out/bin/mylang test experiments/sexpr-port \
  --cache-dir "$sexpr_cache" --force --jobs 1
```

Result: 114 passed, 0 failed, 0 skipped across eight programs.

### GC-stress baseline

The suite under `--gc-stress` exposed printer rooting failures. To determine
whether the range replacements caused them, the project was copied to
`/tmp/mylang-sexpr-prerange.Q0hmSK` and only the five expressions above were
restored to their original transient-view spellings. No compiler or runtime
source changed. Both variants used the same freshly rebuilt compiler, fresh
caches, `--force`, `--gc-stress` and `--jobs 1`:

```sh
current_cache=$(mktemp -d /tmp/mylang-sexpr-range-final.XXXXXX)
zig-out/bin/mylang test experiments/sexpr-port --gc-stress \
  --cache-dir "$current_cache" --force --jobs 1

baseline_cache=$(mktemp -d /tmp/mylang-sexpr-prerange-cache.XXXXXX)
zig-out/bin/mylang test /tmp/mylang-sexpr-prerange.Q0hmSK --gc-stress \
  --cache-dir "$baseline_cache" --force --jobs 1
```

| Sources | Passed | Failed | Result |
| --- | ---: | ---: | --- |
| New direct range calls | 94 | 20 | failure |
| Restored transient views | 90 | 24 | failure |

Every test failing with the direct range calls also failed in the restored-call
baseline. The restored baseline additionally failed these four printer tests,
which passed with direct ranges:

- `test_depth_cutoff_breaks_at_five_levels`
- `test_fixture_nested_depth_cutoff`
- `test_fixture_note_string_is_verbatim`
- `test_indentation_accumulates_through_nesting`

The shared failures are aborts or segmentation faults in printer/round-trip
tests with invalid or misaligned managed pointers. Parser, tokenizer and view
tests pass in both variants. The controlled baseline therefore establishes that
the stress failures predate the five replacements; direct range calls reduce
their observed count but do not fix the underlying printer rooting defect.

The task's retained compiler from before the implementation was then run over
the same restored-call temporary project. Its tool paths had to be supplied
because the retained executable is outside its original install layout:

```sh
before_cache=$(mktemp -d /tmp/mylang-sexpr-beforecompiler-cache.XXXXXX)
.tmp/schematic-implementation-20260921/before-mylang test \
  /tmp/mylang-sexpr-prerange.Q0hmSK --gc-stress \
  --cache-dir "$before_cache" --force --jobs 1 \
  --qbe /home/epentland/ai/canopy/mylang/zig-out/focus/qbe \
  --zig /home/epentland/zig-toolchains/0.17.0-dev.1683+5ceec001b/zig
```

Result: 90 passed and the same 24 named tests failed with the same abort/segfault
classes as the freshly rebuilt compiler over restored sources. This pins the
printer GC-stress defect before both the range-call source replacements and the
compiler/runtime implementation in this task.
