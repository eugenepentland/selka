Exact source `730a86e62b47c922dc1411d24b5868c3bd2132f3` and final RF
compiler/guests passed 516 new oracle checks: 86 plans across all six arms.
Independent holdout replay also passed 516 cells. Manifest/source/compiler/
asset/clock/binary/helper hashes were verified before and after, exit and clock
protocol were checked, and all elapsed values discarded. This is correctness
and robustness evidence, not acceptance timing.

Every one of the 40 cases uses nearby non-power-of-two sizes: small minus3
(floor3) with unseen seed12347 and 7 iterations; large plus5 with unseen seed65521
and 11 iterations. Six selected larger plans use seed104729 and 3 iterations:
list_scan, bytes_scan, dict_lookup, dict_lookup_str, alloc_retained and mutate_nested,
with size min(65533, four times frozen large plus5). The exact plans are in JSON.
Larger size parameters preserve each original generator and do not promise a
new key cardinality, value/alias topology or distribution.

The frozen runner contract cannot express empty size, arbitrary malformed
Unicode/error input, altered alias graphs or sorting distributions. Separate
final-source semantic evidence supplies specific shapes, without becoming timed
holdout-distribution evidence. The independent validation receipt is
validation/730a86e6-validation.json: fresh uncached LLVM1579/1579, RC1579 and
GCstress1579, 68 native-boundary agreements, no module-oracle differences;
docs228 executed and57 checked. Four-shard gate exited0/97 steps despite a
2.34GB >2GiB Zig memory diagnostic; the same source passed default12 shards,
109/109 steps with unchanged limits and no overrun. Repeated host/shard totals
must not be added as independent tests.

Concrete source-pinned semantic fixtures include:

- tests/lang/standard_json.my: test_json_quotes_every_control_and_preserves_unicode_spans
  checks all32 controls, ASCII/λ/日本語/😀, surrogate pairs and empty string;
  test_json_malformed_offsets_follow_the_original_cursor_contract checks malformed
  escapes/controls/truncated Unicode/surrogates/trailing/duplicate keys with exact
  messages. The other two tests preserve grammar/order/number spelling and
  results after source/builder release. src/stdlib_json_test.zig includes full
  grammar/depth fixtures and GC stress.
- tests/lang/text_views.my: test_non_ascii_pieces_index_by_scalar and
  test_pieces_at_the_policy_edges cover nonASCII and empty/policy edges;
  receiver lifetime, short-piece retention and arena escapes are separately tested.
- tests/lang/rc_plain_appends.my: scalar widths, plain/managed snapshots,
  alias growth, callback-mutated receivers, arena/tuple backing and aliased tail
  removal. tests/lang/scalar_dictionary_publication.my preserves owned/view keys,
  deletion history, snapshots, set order and plain structural keys.

These named fixtures passed under the final semantic receipt; this holdout
artifact does not claim all possible error, Unicode, alias, data distributions,
ISA policies or working-set sizes are covered. The guard/join semantic matrices
and P7 admission/failure evidence are separate campaign archives.

Raw holdout JSON SHA256: `702377e7b1e8b82042d82c4bb4345d481231f4dd7dc797728b2ec651a49f97f1`.
Source hashes of the cited semantic fixtures are included in the receipt archive.
