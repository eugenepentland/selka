# EDA standard-library parity preparation

Status: untimed baseline migration implemented, 2026-09-07. No fresh participant
trial has launched. This audit covers the public EDA v1 contract, not hidden tasks.
Readiness requires the shared capability matrix, independent review and new freeze.

## Actual comparator dependencies

Toolchains inspected locally: Python 3.14.4; Zig 0.17.0-dev.1683+5ceec001b.
Dependency evidence is the checked-in baseline source, not a hypothetical list of
what languages might supply. Python's runtime application imports are `json`,
`math`, `re`, `sys`, `collections.Counter`, and `itertools.combinations` in
[inspector.py](../../experiments/application_comparison/baselines/eda/python/inspector.py).
Zig's equivalent APIs are visible in
[main.zig](../../experiments/application_comparison/baselines/eda/zig/src/main.zig).

| Required capability | Python / Zig actual use | `.my` disposition |
| --- | --- | --- |
| Strict UTF-8 JSON, duplicate keys, integer range, finite numbers, depth | `json.loads` hooks, `math.isfinite`; `std.json.parseFromSlice`, `std.unicode.utf8ValidateSlice`, `std.fmt.parseInt/parseFloat` | Migrated to `std_json::parse`, decoded tape queries; transport regression probes include overflow midpoint and underflow. The restricted `std_format::parse_float` is not used. |
| Standard output and integer formatting | `sys.stdin.buffer`, `json.dumps`, f-strings; `std.Io.File`, `std.Io.Writer`, JSON stringify | `std_text::read/emit/number`; raw-byte-only host. Application owns report structure and SVG attribute order. |
| Sort with record key/context | `sorted`; `std.mem.sort` with comparator context | Migrated to `std_order::sort` with precomputed decoded key ranges; domain-specific key selection remains local. |
| Exact identifier grammar | `re.fullmatch`; manual Zig ASCII predicate | `[a-z][a-z0-9_-]{0,31}` remains domain configuration passed to `std_ascii::matches<i64>`. |
| Counts and unique references | `Counter`, sets/dictionaries; Zig sorted lists | Counts can be obtained through sorted runs. General counter/set APIs are available or in preparation; domain resolution remains application logic. |
| Unordered pairs | `itertools.combinations`; Zig nested iteration | General pair iterator being prepared. Pair geometry itself is application work. |
| Variable storage | Python list/dict; Zig allocator, `ArrayList`, arena | Owned buffers, standard JSON document and explicit allocator. Workspace 17,536 i64 plus 16,384 sort descriptors covers 128 components, 128 nets, 16,384 refs and cached rectangles. |
| Test execution | `unittest` and subprocess fixture drivers; `std.testing` | Public CLI acceptance and independent oracle are external evaluator tooling for all arms; source-level tests/verification must be frozen separately. |

Both comparator language sources implement domain validation and geometry locally.
Python's general regex engine is not required if a reusable standard primitive
expresses the exact agreed ASCII grammar; this does not imply full regex parity.
Likewise this workload does not require filesystem traversal, timezone handling,
networking, cryptography, arbitrary Unicode identifiers or floating geometry.

## Migration and limits

The baseline now imports `std_json` and `std_text`, following the existing
`experiments/ergonomics/pin-roles` example without taking its domain feature.
It uses `std_order::sort` with one reusable descriptor workspace and `std_ascii::matches` for the domain grammar. It no longer contains its handwritten JSON/UTF-8 parser, number lexer, duplicate-key
hash table, source escape decoder, or decimal formatter. Existing EDA semantics and
64-case/1-MiB limits remain unchanged. Input is decoded into the standard document;
query results are checked by application schema before identifier emission.

The generic JSON parser is implemented by the language runtime. It is shared
standard-library functionality, not an EDA-aware host callback. The freeze must
explicitly permit this standard dependency under the updated fairness contract;
old prose saying every parser byte must reside in application source is stale.

Output identifiers are limited to 32 ASCII bytes by the common contract, so the
256-byte standard hash-key limit is sufficient for individual IDs and 65-byte
component/pin encodings if those collections are used. JSON can contain arbitrary
valid Unicode in schema-invalid values: rejecting non-ASCII at transport level
would be incorrect, and tests retain this distinction. General JSON builders are
bounded owners; streaming the 55-MiB stress report avoids allocating that report
again in the guest. A whole-output builder is not required for equivalent results.

## Evidence and cost accounting

Validation evidence is retained under
[`evidence/stdlib-parity-eda`](../../experiments/application_comparison/evidence/stdlib-parity-eda).
The original calibration/evidence files are unchanged. The public construction
oracle comparison uses three fixed seeds (192 boards) plus seven transport probes;
its receipt pins executable, source, request and output hashes. These are baseline
preparation checks, not hidden scored acceptance or development-speed evidence.

Library/compiler preparation and baseline migration remain separate from application
timing. Development wall time, agent turns, tokens, compute cost, and human effort
were not comprehensively metered and are **unknown**; test subprocess elapsed time
is verification runtime only. No speed, defect-rate or quality improvement is claimed
from deleting duplicated parser code or passing these checks. Independent review
must assess architecture, error behavior, and remaining library substitutions before
new tasks are sealed.

The first migrated-parser stress run used the previously installed Debug host and
passed 1-MiB whitespace, 50,000 unique keys and long duplicate keys, then exceeded
the existing 60-second repeated-reference fixture timeout. That failure is retained
in `initial-debug-stress.log`; it did not reach the high-output fixture. This run
also preceded descriptor sorting and direct string-key query migration, so it cannot
isolate any single cause. The follow-up uses a pinned ReleaseFast host copy, the
same fixture timeouts and no changed application limits. It is verification, not a
performance comparison between language versions. Temporary ordinary source copies
of the new standard modules were used to validate against the installed compiler;
final integration must rerun with embedded standard modules and pin their hashes.

The final source passed the existing CLI suite and all stress fixtures, including
16,384 repeated references and an 841,355-byte input producing 57,692,813 output
bytes. The output fixture completed in 40.908 verification seconds. The final
independent oracle comparison passed 192 generated boards and seven transport
probes; `validation.json` and `stress-receipt.json` pin the exact source, host and
temporary module copies. This remains provisional evidence until root integration
revalidates the embedded modules. No Guardian gate was exercised by this worktree;
only the prebuilt compiler and host were used.
