# A04 public library release inventory

Base: `fbfcaa7a923186a8e773c3760f81c10aa345a432`. This inventory describes intended contracts; execution status is recorded in phase-specific `results.json` files.

The six assigned modules contain **80 public functions and 5 public types**. Every public function is directly called by a retained library fixture or the supplemental ownership fixture. Public aggregates are covered by their constructors/accessors and ownership operations.

| Module | Public functions | Public types | Primary fixtures |
| --- | ---: | ---: | --- |
| json | 21 | 2 | `src/stdlib/fixtures/json.my`, `tests/lang/a04_memory_library_contracts.my` |
| strings | 28 | 1 | `src/stdlib/fixtures/strings.my`, `tests/lang/a04_memory_library_contracts.my` |
| path | 11 | 1 | `src/stdlib/fixtures/path.my`, `tests/lang/a04_memory_library_contracts.my` |
| base64 | 6 | 0 | `src/stdlib/fixtures/codecs.my`, `tests/lang/a04_memory_library_contracts.my` |
| hex | 4 | 0 | `src/stdlib/fixtures/codecs.my`, `tests/lang/a04_memory_library_contracts.my` |
| byte_builder | 10 | 1 | `src/stdlib/fixtures/byte_builder.my`, `tests/lang/a04_memory_library_contracts.my` |

## Contracts

Ordinary managed inputs borrow for the duration of the call. Managed results must survive input replacement and destruction; results use a fresh allocation, explicit deep copy, or ownership transfer from a locally constructed temporary. Literals may remain immortal. Mutable builder operations write back exclusively; `finish` deliberately copies so prior snapshots and later mutations stay independent.

### json

| Export | Contract |
| --- | --- |
| `Json` (enum, line 4) | Owned aggregate; managed children move into constructors; borrowing field access does not transfer ownership. |
| `Error` (enum, line 15) | Owned aggregate; managed children move into constructors; borrowing field access does not transfer ownership. |
| `message` (func, line 20) | Ordinary managed inputs borrowed; managed return independently owned (explicit deep copy, construction or owned temporary transfer). |
| `max_depth` (func, line 33) | Ordinary managed inputs borrowed; scalar or optional-scalar result owns no input storage. |
| `null_value` (func, line 38) | Ordinary managed inputs borrowed; managed return independently owned (explicit deep copy, construction or owned temporary transfer). |
| `boolean` (func, line 43) | Ordinary managed inputs borrowed; managed return independently owned (explicit deep copy, construction or owned temporary transfer). |
| `integer` (func, line 48) | Ordinary managed inputs borrowed; managed return independently owned (explicit deep copy, construction or owned temporary transfer). |
| `number` (func, line 53) | Ordinary managed inputs borrowed; managed return independently owned (explicit deep copy, construction or owned temporary transfer). |
| `text` (func, line 58) | Ordinary managed inputs borrowed; managed return independently owned (explicit deep copy, construction or owned temporary transfer). |
| `array` (func, line 63) | Ordinary managed inputs borrowed; managed return independently owned (explicit deep copy, construction or owned temporary transfer). |
| `object` (func, line 68) | Ordinary managed inputs borrowed; managed return independently owned (explicit deep copy, construction or owned temporary transfer). |
| `type_name` (func, line 73) | Ordinary input borrowed when present; immutable literal result may use immortal storage. |
| `is_null` (func, line 92) | Ordinary managed inputs borrowed; scalar or optional-scalar result owns no input storage. |
| `as_bool` (func, line 111) | Ordinary managed inputs borrowed; scalar or optional-scalar result owns no input storage. |
| `as_int` (func, line 130) | Ordinary managed inputs borrowed; scalar or optional-scalar result owns no input storage. |
| `as_float` (func, line 149) | Ordinary managed inputs borrowed; scalar or optional-scalar result owns no input storage. |
| `as_str` (func, line 168) | Ordinary managed inputs borrowed; managed return independently owned (explicit deep copy, construction or owned temporary transfer). |
| `as_list` (func, line 187) | Ordinary managed inputs borrowed; managed return independently owned (explicit deep copy, construction or owned temporary transfer). |
| `as_dict` (func, line 206) | Ordinary managed inputs borrowed; managed return independently owned (explicit deep copy, construction or owned temporary transfer). |
| `get` (func, line 225) | Ordinary managed inputs borrowed; managed return independently owned (explicit deep copy, construction or owned temporary transfer). |
| `at` (func, line 246) | Ordinary managed inputs borrowed; managed return independently owned (explicit deep copy, construction or owned temporary transfer). |
| `loads` (func, line 612) | Ordinary managed inputs borrowed; managed return independently owned (explicit deep copy, construction or owned temporary transfer). |
| `dumps` (func, line 723) | Ordinary managed inputs borrowed; managed return independently owned (explicit deep copy, construction or owned temporary transfer). |

### strings

| Export | Contract |
| --- | --- |
| `digits` (func, line 4) | Ordinary input borrowed when present; immutable literal result may use immortal storage. |
| `Error` (enum, line 9) | Owned aggregate; managed children move into constructors; borrowing field access does not transfer ownership. |
| `message` (func, line 15) | Ordinary managed inputs borrowed; managed return independently owned (explicit deep copy, construction or owned temporary transfer). |
| `letters` (func, line 29) | Ordinary input borrowed when present; immutable literal result may use immortal storage. |
| `whitespace` (func, line 34) | Ordinary input borrowed when present; immutable literal result may use immortal storage. |
| `is_digit` (func, line 57) | Ordinary managed inputs borrowed; scalar or optional-scalar result owns no input storage. |
| `is_alpha` (func, line 62) | Ordinary managed inputs borrowed; scalar or optional-scalar result owns no input storage. |
| `is_alnum` (func, line 67) | Ordinary managed inputs borrowed; scalar or optional-scalar result owns no input storage. |
| `is_space` (func, line 72) | Ordinary managed inputs borrowed; scalar or optional-scalar result owns no input storage. |
| `starts_with` (func, line 77) | Ordinary managed inputs borrowed; scalar or optional-scalar result owns no input storage. |
| `ends_with` (func, line 82) | Ordinary managed inputs borrowed; scalar or optional-scalar result owns no input storage. |
| `find` (func, line 87) | Ordinary managed inputs borrowed; scalar or optional-scalar result owns no input storage. |
| `count` (func, line 95) | Ordinary managed inputs borrowed; scalar or optional-scalar result owns no input storage. |
| `lstrip` (func, line 102) | Ordinary managed inputs borrowed; managed return independently owned (explicit deep copy, construction or owned temporary transfer). |
| `rstrip` (func, line 107) | Ordinary managed inputs borrowed; managed return independently owned (explicit deep copy, construction or owned temporary transfer). |
| `strip` (func, line 112) | Ordinary managed inputs borrowed; managed return independently owned (explicit deep copy, construction or owned temporary transfer). |
| `lines` (func, line 117) | Ordinary managed inputs borrowed; managed return independently owned (explicit deep copy, construction or owned temporary transfer). |
| `repeat` (func, line 133) | Ordinary managed inputs borrowed; managed return independently owned (explicit deep copy, construction or owned temporary transfer). |
| `pad_left` (func, line 149) | Ordinary managed inputs borrowed; managed return independently owned (explicit deep copy, construction or owned temporary transfer). |
| `pad_right` (func, line 159) | Ordinary managed inputs borrowed; managed return independently owned (explicit deep copy, construction or owned temporary transfer). |
| `upper` (func, line 169) | Ordinary managed inputs borrowed; managed return independently owned (explicit deep copy, construction or owned temporary transfer). |
| `lower` (func, line 174) | Ordinary managed inputs borrowed; managed return independently owned (explicit deep copy, construction or owned temporary transfer). |
| `substitute` (func, line 179) | Ordinary managed inputs borrowed; managed return independently owned (explicit deep copy, construction or owned temporary transfer). |
| `to_int` (func, line 186) | Ordinary managed inputs borrowed; scalar or optional-scalar result owns no input storage. |
| `to_float` (func, line 191) | Ordinary managed inputs borrowed; scalar or optional-scalar result owns no input storage. |
| `format_int` (func, line 196) | Ordinary managed inputs borrowed; managed return independently owned (explicit deep copy, construction or owned temporary transfer). |
| `format_float` (func, line 230) | Ordinary managed inputs borrowed; managed return independently owned (explicit deep copy, construction or owned temporary transfer). |
| `ord` (func, line 264) | Ordinary managed inputs borrowed; managed return independently owned (explicit deep copy, construction or owned temporary transfer). |
| `chr` (func, line 285) | Ordinary managed inputs borrowed; managed return independently owned (explicit deep copy, construction or owned temporary transfer). |

### path

| Export | Contract |
| --- | --- |
| `Split` (record, line 4) | Owned aggregate; managed children move into constructors; borrowing field access does not transfer ownership. |
| `separator` (func, line 10) | Ordinary input borrowed when present; immutable literal result may use immortal storage. |
| `is_absolute` (func, line 15) | Ordinary managed inputs borrowed; scalar or optional-scalar result owns no input storage. |
| `join` (func, line 20) | Ordinary managed inputs borrowed; managed return independently owned (explicit deep copy, construction or owned temporary transfer). |
| `join_all` (func, line 31) | Ordinary managed inputs borrowed; managed return independently owned (explicit deep copy, construction or owned temporary transfer). |
| `basename` (func, line 39) | Ordinary managed inputs borrowed; managed return independently owned (explicit deep copy, construction or owned temporary transfer). |
| `dirname` (func, line 47) | Ordinary managed inputs borrowed; managed return independently owned (explicit deep copy, construction or owned temporary transfer). |
| `splitext` (func, line 57) | Ordinary managed inputs borrowed; managed return independently owned (explicit deep copy, construction or owned temporary transfer). |
| `stem` (func, line 69) | Ordinary managed inputs borrowed; managed return independently owned (explicit deep copy, construction or owned temporary transfer). |
| `extension` (func, line 74) | Ordinary managed inputs borrowed; managed return independently owned (explicit deep copy, construction or owned temporary transfer). |
| `components` (func, line 80) | Ordinary managed inputs borrowed; managed return independently owned (explicit deep copy, construction or owned temporary transfer). |
| `normalize` (func, line 89) | Ordinary managed inputs borrowed; managed return independently owned (explicit deep copy, construction or owned temporary transfer). |

### base64

| Export | Contract |
| --- | --- |
| `standard_alphabet` (func, line 2) | Ordinary input borrowed when present; immutable literal result may use immortal storage. |
| `urlsafe_alphabet` (func, line 7) | Ordinary input borrowed when present; immutable literal result may use immortal storage. |
| `b64encode` (func, line 99) | Ordinary managed inputs borrowed; managed return independently owned (explicit deep copy, construction or owned temporary transfer). |
| `b64decode` (func, line 104) | Ordinary managed inputs borrowed; managed return independently owned (explicit deep copy, construction or owned temporary transfer). |
| `urlsafe_b64encode` (func, line 109) | Ordinary managed inputs borrowed; managed return independently owned (explicit deep copy, construction or owned temporary transfer). |
| `urlsafe_b64decode` (func, line 114) | Ordinary managed inputs borrowed; managed return independently owned (explicit deep copy, construction or owned temporary transfer). |

### hex

| Export | Contract |
| --- | --- |
| `encode` (func, line 4) | Ordinary managed inputs borrowed; managed return independently owned (explicit deep copy, construction or owned temporary transfer). |
| `encode_upper` (func, line 9) | Ordinary managed inputs borrowed; managed return independently owned (explicit deep copy, construction or owned temporary transfer). |
| `decode` (func, line 14) | Ordinary managed inputs borrowed; managed return independently owned (explicit deep copy, construction or owned temporary transfer). |
| `is_hex` (func, line 19) | Ordinary managed inputs borrowed; scalar or optional-scalar result owns no input storage. |

### byte_builder

| Export | Contract |
| --- | --- |
| `Builder` (record, line 8) | Owned aggregate; managed children move into constructors; borrowing field access does not transfer ownership. |
| `create` (func, line 13) | Ordinary managed inputs borrowed; managed return independently owned (explicit deep copy, construction or owned temporary transfer). |
| `append_byte` (func, line 20) | Exclusive mutable builder writeback; ordinary data/text arguments borrowed for the call; scalar success or Unit returned. |
| `append_range` (func, line 29) | Exclusive mutable builder writeback; ordinary data/text arguments borrowed for the call; scalar success or Unit returned. |
| `append` (func, line 34) | Exclusive mutable builder writeback; ordinary data/text arguments borrowed for the call; scalar success or Unit returned. |
| `append_text` (func, line 40) | Exclusive mutable builder writeback; ordinary data/text arguments borrowed for the call; scalar success or Unit returned. |
| `append_int` (func, line 48) | Exclusive mutable builder writeback; ordinary data/text arguments borrowed for the call; scalar success or Unit returned. |
| `append_float` (func, line 57) | Exclusive mutable builder writeback; ordinary data/text arguments borrowed for the call; scalar success or Unit returned. |
| `append_spaces` (func, line 63) | Exclusive mutable builder writeback; ordinary data/text arguments borrowed for the call; scalar success or Unit returned. |
| `reserve` (func, line 81) | Exclusive mutable builder writeback; ordinary data/text arguments borrowed for the call; scalar success or Unit returned. |
| `finish` (func, line 89) | Builder borrowed; immutable bytes snapshot owns a fresh copy and survives builder mutation/destruction. |

## Explicit boundaries

- Ordinary source parameters borrow; returning that borrowed storage requires explicit .copy().
- Borrowed text/byte views may not escape their owner, be stored in aggregates, or survive owner mutation/replacement.
- Text classification/case conversion in strings is ASCII as documented; ord/chr and UTF-8 operations cover Unicode scalars.
- Malformed input is an API Result/Option error, not an unsupported ownership shape.

No export is excluded from the denominator because a compiler rejects it. A refusal of an in-scope public call remains a release blocker.

## Reproduction

Run `qualify.py --inventory` to refresh the machine-readable declaration/source-hash inventory. Capture owns shared build admission separately for each lane; the harness accepts separate compiler, Zig, scratch-output, evidence-output and source-commit identities. It imports read-only historical helper functions but never invokes their report-writing entrypoints. Refusals and failures remain in the output. Completed evidence directories cannot be overwritten. `--resume` preserves completed lanes in an interrupted phase only after checking compiler, export inventory and source identities.

```sh
. "$HOME/.config/mylang/dev-env.sh"
python3 -B experiments/memory-closeout-20261012/A04/qualify.py \
  --compiler "$A04_COMPILER" --zig "$ZIG" --source-commit "$A04_COMMIT" \
  --output .tmp/memory-closeout/A04/c0 \
  --evidence experiments/memory-closeout-20261012/A04/c0
```

All five guest modes are selected by default: release, unoptimized debug, release with verified facts, optimized debug and release without facts. Each admitted run checks expected exit status, managed leaks, emitted/runtime RC counters, LLVM and native symbols. Negative view cases check exact diagnostic identifiers. Build wall observations are not controlled compile-time measurements; A09 owns runtime/RSS measurement.

For a baseline without production A04 changes, `--baseline` keeps all eight release fixtures and runs the new public ownership supplement in all five modes (12 lanes). The integrated candidate uses the full 40-lane matrix. Baseline selection was approved by the coordinator; it does not remove any public export from coverage.
