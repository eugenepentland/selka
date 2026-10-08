# Expanded text contract v1

Each executable accepts `CASE SIZE ITERATIONS SEED`, with SIZE>=2,
ITERATIONS>=1, 1<=SEED<=1000000, and prints exactly `CHECKSUM ELAPSED_NS\n`.
Construct all input fixtures before the monotonic timestamp. Every iteration
selects fixture `(SEED+step)%cycle_length`, performs the operation below, and
adds its contribution to checksum modulo 1000000007. Finish timing after the
last operation/fold; print afterward. No per-operation barriers or custom
allocators. Python `oracle.py` specifies the fixtures independently and exports
CASES metadata and checksum(). Integer arithmetic stays signed 64-bit.

String comparisons use exact UTF-8 contents; search indexes are Unicode scalar
indexes in every port. `score(text)` is UTF-8 byte length plus the sum of its
unsigned bytes, including all constructed output bytes. MyLang's native string
UTF-8 conversion is included where required to fold results. Strings have normal
native representations and allocation behavior. Small/large micro profiles use
SIZE 64/4096, application profiles 16/256. One iteration's unit is declared in
CASES; do not compare ns/op across different cases.

* bytes_scan: bytes[j]=(SEED+j*37)%256, length SIZE. Sum every byte XOR the
  selected mask; cycle length256, mask=(SEED+step)%256.
* string_equal: four pairs, selected in order: `a` repeated SIZE equal to an
  independently constructed identical string; `é` repeated SIZE versus its last
  scalar changed to `ê`; `a` repeated SIZE versus first scalar `b`; and two
  independently constructed `café`+decimal(SEED) strings. Contribution1 equal,
  otherwise0. Includes long/short, equal, early/late mismatch and Unicode.
* string_search: haystack=`a` repeated SIZE+`;café;needle;`+decimal(SEED).
  Four needles `a`, `needle`, `absentΩ`, `é`. Contribution first scalar index+1,
  or0 for missing. Includes early/late/Unicode hit and miss.
* string_split/string_join: SIZE fragments selected from
  `["", "alpha", "café", "x", "naïve"]` by (SEED+j)%5. Alternate separators
  `|` and `::`. Split the two preconstructed documents, preserving empty fields;
  contribution7*number_of_parts+sum(score(part)). Join constructs a fresh string
  from the preconstructed fragments; contribution score(output).
* int_parse: SIZE strings, n=(SEED+j*137)%1000003; select by j%6:
  decimal(n), `-`+decimal(n), `00`+decimal(n), decimal(n)+`x`, `oops`, empty.
  One iteration parses selected string as a whole signed decimal integer.
  Contribution parsed value or97 on error. No whitespace/base prefixes allowed
  by these fixtures; malformed data must be rejected. Valid values include zero,
  negative zero, negatives and leading zeroes. Invalid contributions are positive;
  checksum modulo is mathematical nonnegative modulo in every port.
* int_format: SIZE integers n=(SEED+j*137)%1000003, negate where j%3==0.
  Format one selected integer to decimal; contribution score(formatted string).
* word_count: SIZE words from `[red,blue,café,red,green,blue,naïve,red]`, selected
  by (SEED+j)%8, each followed by `[space,tab,newline,two spaces][j%4]`.
  Preconstruct two documents by appending `red` or `blue`. Split ASCII whitespace,
  count all tokens in a native dictionary/map, and contribute
  sum(score(word)*frequency²). Tokenization, map creation/update and fold are timed.
* csv_aggregate: SIZE CSV records with no header, LF ending, fields id,name,
  region,amount,active. id=SEED+j; name is `café,"item"` for even j and
  `naïve,item` for odd j, followed by decimal(j). Region `[east,west,north]`
  indexed (SEED+j)%3; amount `oops` where j%11==0, otherwise decimal of
  (SEED+j*19)%100003; active `1` when (SEED+j)%3!=0 else `0`.
  Quote names and double embedded quotes. Use equivalent quote-aware parsers
  supporting quoted commas and doubled quotes, rejecting malformed numeric data.
  The documented fixture subset has no embedded newlines, no CRLF, no comments,
  no whitespace around fields and no malformed CSV syntax. Parse every field;
  reject invalid amounts and count rejections even if inactive. For valid active
  rows aggregate amounts by region, count accepted rows and sum score(name).
  Contribution east+2*west+3*north+17*accepted+101*rejected+name_scores.
  Parsing, validation, map aggregation and fold are timed.
* json_transform (native-library application): input is a compact JSON array
  of SIZE records with id/name/amount/active as above, except every amount is the
  valid integer and active is a JSON bool. Parse with MyLang stdlib json, Rust
  serde_json, Go encoding/json, Zig std.json. Retain active rows, build new objects
  with id/name/amount, add bump=(SEED+step)%17 to amount, serialize compact JSON,
  and contribute score(output). Output key order can differ because byte sum and
  length are order-independent; Unicode is emitted directly, required quotes
  escaped, and strings avoid HTML/control-character escape policy differences.
  Parsing, filtering, object construction, serialization and byte fold are timed.

Rust is built by Cargo --release --locked with checked-in dependency lockfile,
without native CPU tuning or nondefault release overrides. serde_json is pinned
exactly in Cargo.toml; Cargo.lock fingerprints every transitive crate. Remaining
ports use the baseline native toolchains and native-clock helper unchanged.
These are optimized default build policies, not matched instruction sets.
