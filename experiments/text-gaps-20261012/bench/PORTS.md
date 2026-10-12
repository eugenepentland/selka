# Reference policy and contract observations

The fixed ports agree with the documented fixture/output contract; no repeatable
checksum mismatch was observed in fresh baseline warmups, samples, RSS or
counted runs. These comparisons include their existing representation/library
policies and do not isolate identical underlying allocations.

- `string_split`: Rust materializes `Vec<&str>` and Zig materializes an array of
  borrowed byte slices, then folds every field. Go uses `strings.Split` and
  folds the string results. Checked MyLang returns independent owned fragments.
  The canonical contract permits normal native representations. Matching this
  benchmark's observable fold does not make these full ownership APIs identical;
  no port was changed to copy or drop fragments merely to influence timing.
- `json_transform`: Rust uses `serde_json::Value`; Zig uses `std.json.Value` and
  shallowly copies selected values into output object maps while the parse tree
  remains alive; Go uses `[]map[string]any`, decoding numbers as float64 then
  converting bounded fixture integers back to int64. MyLang uses its stdlib JSON
  values. These fixture integers are exactly represented. Serialization key order
  differs legally: byte sum plus length is order-independent. UTF8 is emitted
  directly and the fixture avoids HTML/control escape policy differences.
- `csv_aggregate`: ports parse every field, including quote/doubled-quote names,
  reject malformed numeric fields even for inactive rows, and aggregate valid
  active records. The fixture subset excludes embedded newlines, CRLF, comments,
  malformed CSV syntax and surrounding whitespace. Whole-library CSV semantics
  outside that subset are not claimed equivalent or benchmarked here.

The observations are supported by the pinned `text/main.rs`, `text/main.zig`,
`text/main.go`, migrated `text.my` and canonical text CONTRACT.md in each run's
input identities. Rust Cargo dependencies/default portable release policy,
Zig Safe/Fast modes and Go baseline policy retain their original manifest
identities. No reference rebuild or instruction-set normalization was performed.
