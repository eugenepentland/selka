# Numeric body component qualification

The B9 candidate is an independent, strict source corpus. It requires body-check protocol 1/schema 9 for selected admission, while lexer/parser, declaration and type-interface retain their existing protocols. Reference remains the default. This corpus does not qualify compiler bootstrap or whole-language coverage.

`selfhost/tests/run_body_numeric_admission.py` requires all 40 committed source cases: eight fixed-width matrices, eleven other successful numeric programs, nineteen exact source refusals and two compile-valid runtime traps. The latter distinguish checked unsigned overflow from a narrowing conversion failure, including operands, widths, source locations and stack order. The eight widths are i8/i16/i32/i64/u8/u16/u32/u64. Other controls cover full-u64 values through records, lists and calls, operand evaluation order, signed floor/remainder, negative-zero and negative binary64 literals, arithmetic, casts, NaN comparisons, and numeric parsing of text and byte ranges.

Every source parses and checks in reference, shadow and component modes. Successful checks also produce typed output and execute a generated release program with facts and leak checks. Parsing explicitly selects the parser while leaving body checking in reference; subsequent phases select body checking with the other boundaries in reference. Shadow's complete batch/catalog comparison is required; dump-typed is supplementary. This yields exactly 366 selected operations, with no profile exemptions, skipped cases or source-success substitutions. The reference-only native-control lane has exactly 122 operations and remains explicitly pending for selected B9 support.

```sh
scripts/build-slot.sh build python3 selfhost/tests/run_body_numeric_admission.py \
  --compiler /absolute/install/bin/mylang \
  --builder /absolute/install/tools/selka-components \
  --component-dir /absolute/install/libexec/mylang/components \
  --source-root /absolute/source --zig /absolute/pinned/zig \
  --report /absolute/private/numeric.json --release
```

Checks use `--no-cache --diagnostics=json`. Build optimization and fact flags belong to runtime commands, not check-project. Generated runtimes always use `--release --verify-facts`, `MYL_CORE_LEAKCHECK=1`, and an empty PATH with an explicit Zig path. Runtime failures are matched to the full native diagnostic structure after replacing only the exact fixture path; arbitrary status-one failures cannot satisfy a trap. The report retains commands and raw outputs before assertions and reauthenticates host/package identities at completion.

A native-control run requires `--native-controls --native-body-schema N`, where N names the actual frozen historical deployment. This does not accept that schema for selected B9 execution. Selected runs require coordinator qualified-seed verification and schema 9 exactly.

The body-only unsigned integer row kind 8 is a separate native wire admission obligation: only canonical upper-half-u64 values in typed i128 payloads may use it. IDs, source spans, counts, lower-half values, syntax profiles, malformed rows and stale schema-8 packages must remain rejected. This source runner supplements, rather than replaces, native codec/validator hostile tests. No wire/layout budget is widened: body 2M logical rows, 4M edges/visits, depth 256, 64MiB and 512MiB decode policy remain unchanged.

Native donor anchors are `src/integer_operations_test.zig`, `src/integers_test.zig`, `src/integer_literal.zig`, `src/numeric_surface.zig`, and the language tests `checked_arithmetic.my`, `float_integer_casts.my`, `float_nan.my`, `integer_float_rounding.my` and `byte_views.my`. Native controls are preparatory evidence only until a genuine installed schema-9 producer passes all selected operations. No timings are collected by this harness.
