# Aggregate provider qualification inputs

Prepared for the coordinator's bounded aggregate-root implementation. These
fixtures are not yet qualified on that implementation. C0 identities of the
mandatory capability-field fixture remain in `migrations.json`.

Run the existing A05 counted/structural harness under one admitted build batch;
use the exact new compiler revision and an unused output directory:

```bash
scripts/build-slot.sh build python3 -B experiments/memory-closeout-20261012/A05/qualify.py \
  --compiler "$COMPILER" --compiler-revision "$REVISION" --zig "$ZIG" \
  --output "$OUTPUT" --modes release \
  --cases provider_record provider_tuple guest_capability_fields \
  provider_root_move_negative provider_root_replace_negative \
  provider_copy_negative provider_parameter_result_negative \
  provider_field_move_negative capability_array_negative
```

The three positives execute and require expected results, zero RC events, no
managed exit-live bytes, and clean LLVM/symbol audits. The six negatives use
source checking; their rejection never counts as guest execution. The harness
records exact arguments, input/compiler hashes, diagnostics and raw artifact
paths. All three positives must pass before aggregate support is claimed. Run the
positive cases in the remaining four modes at final C1; use `--ordinary-command`
after default promotion/retirement. These scripts never select compatibility RC.

- `provider_record`: independently owned nested filesystem/environment fields,
  helper borrowing, nested directory/read-only/file scopes, early error cleanup,
  whole-root move after scopes join, and retained provider state afterward.
- `provider_tuple`: two independent filesystem owners in a returned tuple,
  a whole-root move and complete tuple unpack, simultaneous open scopes with
  distinct file contents, and independent providers after both scopes join.
  Tuple indexing is not part of the source language.
- `guest_capability_fields`: every existing field-method and value assertion;
  scoped narrowing and ordinary borrowed-helper alias observation preserve the
  original behavior. No provider fields are flattened away.
- Root move and replacement negatives keep a file live while attempting to
  invalidate its whole owning record.
- Aggregate copy refuses to duplicate a provider. Field move refuses arbitrary
  partial ownership extraction.
- Aggregate-parameter file return refuses provider inference through the whole
  record; direct single provider/resource parameters retain the existing contract.
- `capability_array_negative` is the exact original C0 owning-array source.

`negative/dictionary_get_view.my` is a separate ambiguous-origin view reproducer,
not part of the aggregate support claim. Its source-check and native-build
outcomes are recorded separately pending A07's explicit refusal fix.
