# Component protocol v1

The first operation is `test-index-v1`, implemented by
`selfhost/components/test_index/main.my`. Invoke the built executable as
`COMPONENT --request FILE`. It reads at most 16 MiB plus one sentinel byte from
one immutable binary file, validates the entire request, and writes one framed
binary reply to stdout. A failure exits nonzero and diagnoses on stderr. No
success frame precedes validation or computation. The native host captures both
streams, applies timeout and output limits, and accepts a reply only after zero
exit and complete frame validation. There is no stdin or persistent-worker
protocol in this version.

All integers are unsigned little-endian. Counts and graph IDs are u32. The
header is exactly 64 bytes; payload lengths exclude it.

| Byte offset | Width | Meaning |
| --- | --- | --- |
| 0 | 8 | ASCII magic `SLKIDX01` |
| 8 | 4 | Envelope protocol version, exactly 1 |
| 12 | 4 | Operation schema `test-index-v1`, exactly 1 |
| 16 | 4 | Message kind: 0 request, 1 reply |
| 20 | 4 | Exact payload byte length |
| 24 | 8 | Request ID, echoed unchanged |
| 32 | 32 | Snapshot identity bytes, echoed unchanged |

The magic assigns the component/operation family; this version has no extra
operation tag. The schema version is independent of the envelope version and
component implementation digest. The host validates the selected executable
against its artifact manifest separately. Request IDs and snapshot bytes are
opaque to the component, including zero bytes and high-bit bytes.

The request payload is `node_count`, `test_count`, `test_count` function IDs,
then `node_count` adjacency lists. Each list starts with its edge count followed
by that many callee function IDs. Node IDs range from zero to `node_count - 1`.
Test IDs preserve discovery order and duplicates. Function names remain on the
native host; integer IDs have meaning only within this snapshot.

The reply payload is `node_count`, then one direct list and one reached list
for each node in node order. Each list starts with its count followed by test
function IDs. For each discovered test occurrence, every direct callee edge
adds that test to the callee's direct list, preserving repeated edges. Every
reachable node adds the test once to its reached list, including the test root.
Cycles terminate. Repeated test occurrences contribute repeatedly. Both list
orders follow test discovery order. The pure graph implementation assumes
validated graph IDs; the codec enforces this boundary.

Limits are 100,000 nodes, 100,000 test occurrences, 1,000,000 total adjacency
edges, 16,777,216 request bytes and 67,108,864 reply bytes, including headers.
The component checks the response budget while collecting results, before a
large result can be fully accumulated. The codec rejects unknown versions and
message kinds, bad magic, invalid indices, truncated counts or lists,
inconsistent payload length, oversize frames and trailing bytes. It consumes
exactly one frame; concatenated frames are invalid. No recursive nesting exists.

The empty request golden frame consists of the header with payload length 8,
followed by two zero u32 counts. Its reply has kind 1, payload length 4 and one
zero u32 node count. `tests.my:test_empty_protocol_golden` pins these octets and
uses all-255 identity bytes to cover unsigned identity echo. Host boundary tests
also exercise the native process and malformed frames. Run the pure library and
codec tests with `mylang test selfhost/components/test_index/tests.my --force`.
