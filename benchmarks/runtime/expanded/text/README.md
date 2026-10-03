These ten cases extend the baseline to bytes, text/conversion micros, and three
complete text applications. See CONTRACT.md and oracle.py CASES for exact fixtures,
units, sizes and checksum rules. The console protocol remains two decimal integers.

Native-library JSON is an application benchmark of each language's supplied JSON
implementation, rather than a parser implementation contest: MyLang stdlib json,
Rust serde_json::Value, Go encoding/json maps, and Zig std.json.Value. Every port
builds a dynamic JSON tree, filters active rows, constructs new objects, serializes
compact JSON and consumes every output byte. Allocations, parse failures handled by
library validation, field access, transformations, serialization and destruction
are timed. Rust serde_json is pinned to 1.0.151; Cargo.lock records exact transitive
versions/checksums. Build with Cargo's default portable release profile, --locked,
and no RUSTFLAGS; use `--target-dir` outside the tracked source directory.

CSV uses hand-written native quote-aware parsers for the documented record subset;
Python uses csv.reader independently. All ports preserve quoted commas and doubled
quotes, allocate parsed fields/rows and aggregate a native map. The fixtures include
invalid amount strings that are counted and rejected, rather than silently parsed.
They deliberately exclude embedded LF/CRLF and malformed CSV quoting syntax.

Short/long equality compares independently constructed inputs and rotates equality,
early/late mismatch and UTF-8 cases. Search returns scalar indexes, converting byte
positions in Rust/Go/Zig. Split preserves empty fields; join creates fresh output.
Every output fold uses UTF-8 byte length plus byte sum, including MyLang's normal
encode conversion where its native string API requires it. Signed parse includes
valid negative/zero/leading-zero and malformed input. Map word counts include café
and naïve tokens and ASCII whitespace. Case selection occurs once per kernel, not
once per inner iteration; ordinary helpers may inline naturally.

Input fixtures and all console output are excluded from kernel time. Result parsing,
construction/folding and temporary destruction are included. Normal native allocation
and runtime policies apply: no custom allocators, unsafe indexing, per-operation
barriers, forced noinline, forced target tuning, or disabled MyLang checks. Default
optimized target policies can use different instruction sets across language arms.

The independent oracle computes one complete fixture cycle, then repeats its sum
algebraically for large iteration counts. It does not import port code or the timed
program's result, and uses Python's CSV/JSON parsers for the applications.
