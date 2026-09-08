"""Single-source public prose, also written to brief files for provisioning."""
COMMON = '''# Process contract: bounded-json-batch-v1

The process reads one UTF-8 JSON object from stdin and writes one compact JSON
object plus a newline to stdout, then exits. No logs go to stdout. One process
handles one case group; this is not an interactive multi-request process.
The envelope is exactly {"requests": [...]} with at most 64 request values.
An invalid envelope returns {"error":"invalid-envelope"}. Otherwise return
{"results":[...]} with exactly one result per input request, in input order.
Task schema errors return {"error":"invalid-request"} for that request only.
Validate the entire request before performing operations; no partial result
or earlier semantic error takes precedence over a later schema error.

JSON integers must be integer tokens, excluding booleans, fractional/exponent
forms, and null. All schemas below have exact fields except named optional
fields. Arrays retain order unless sorting is explicitly required. IDs match
[a-z][a-z0-9_-]{0,31}; all ID sorting is ascending ASCII byte order. Unless stated
otherwise, arrays have at most 128 elements and signed integers range from
-1000000 through 1000000 inclusive. Object member order has no meaning.
The coordinator transport domain is at most 2097152 bytes (2 MiB) per process.
Within that domain, valid application input has at most 1048576 bytes (1 MiB),
nesting depth at most 32, no duplicate object keys, and no nonfinite numbers.
Inputs in (1048576, 2097152] bytes return invalid-envelope; inputs above 2097152
bytes are outside this harness contract and carry no application response promise.
Invalid UTF-8, malformed JSON, duplicate keys, excess depth or multiple JSON
values within the coordinator domain also return invalid-envelope. Leading
and trailing JSON whitespace are allowed. Object key order/JSON whitespace in
output are ignored; array order and all values are exact.

Implement application behavior using the supplied standard library and runtime.
Library prerequisites and equivalent starter acceptance must be completed before
clocks start. Do not implement a new JSON parser, map, sorter, encoding library,
or general path utility during timed work. Filesystem tasks use supplied virtual
snapshots; no actual host filesystem access is part of the application contract.
'''

DESCRIPTIONS = {
'data-rollup': '''Request: {"rows":[{"key":ID,"delta":INT}], "minimum":INT?}.
minimum is optional, defaults to -128000000, and ranges -128000000..128000000.
Group all rows by key, preserving zero totals; return {"groups":[{"key":ID,
"count":INT,"total":INT}]} sorted by key, including only groups with total >=
minimum. Counts include every row. Empty input yields an empty groups array.''',
'ascii-table': '''Request: {"columns":INT,"rows":[[TEXT,...],...]}. columns ranges
0..8; there are at most 64 rows and exactly columns cells per row. TEXT has
0..32 printable ASCII bytes (32..126), including spaces. Compute each column's
maximum cell byte length, defaulting to zero when no rows. Return {"widths":[INT],
"lines":[TEXT]}: pad every cell on the RIGHT with ASCII spaces to its column
width, including the final column, and join with exactly " | ". Do not trim.
A row with zero columns emits an empty string. No Unicode display-width rule.''',
'config-layers': '''Request: {"layers":[OBJECT,...]}, at most 64 layers. A layer
may contain any subset of timeout, retries, enabled, label and no other fields.
Defaults are timeout=1000, retries=3, enabled=true, label="default". Non-null
values require timeout integer 0..60000, retries integer 0..10, enabled boolean,
and label ID. Null explicitly resets that field to its default. Apply layers
in source order; omitted fields preserve prior values. Return {"config":OBJECT,
"changed":[ID]} containing all four final fields and sorted field names whose
final value differs from its default.''',
'quota-boundary': '''Request: {"limit":INT,"used":INT,"requests":[INT,...]}.
limit ranges 0..1000000, used ranges 0..limit, and request amounts range
0..1000000. Process amounts in order: accept exactly when used+amount <= limit;
on acceptance increase used, otherwise leave it unchanged. Zero is accepted
at full capacity. Return {"accepted":[BOOL],"used":INT,"remaining":limit-used}.
Repair the supplied equivalent starter's inclusive-boundary defect; preserve
its interface and unchanged behavior away from equality.''',
'lru-cache': '''Request: {"capacity":INT,"operations":[OP,...]}, capacity 0..16.
OP is exactly {"op":"put","key":ID,"value":INT} or {"op":"get","key":ID}.
Initially empty. A successful get returns {"value":INT} and makes that key most
recent; a miss returns {"value":null} and changes nothing. Put replaces/inserts
and makes the key most recent. If insertion of a new key exceeds capacity,
evict the least recent key. Put returns {"evicted":ID-or-null}; replacement
never evicts. Capacity zero stores nothing and put returns evicted=null.
Return {"results":[RESULT],"entries":[{"key":ID,"value":INT}]} with final
entries in least-to-most-recent order.''',
'ttl-boundary': '''Request: {"operations":[OP,...]}. OP is exactly
{"op":"put","at":INT,"key":ID,"value":INT,"ttl":INT} or
{"op":"get","at":INT,"key":ID}. at values are nondecreasing, 0..1000000;
ttl ranges 0..1000000. A put replaces the key and expires at at+ttl. At each
operation keys with expiry <= at are expired. A zero-TTL put is immediately
unavailable, including to a following get at the same time. Put result is null;
get result is the stored integer or null. Return {"results":[INT-or-null],
"live":[ID]} with sorted live keys at the last operation's timestamp (empty
for no operations). Fix the starter's expiry-boundary defect, preserving its
interface and non-boundary behavior.''',
'record-frames': '''Request: {"records":[{"tag":INT,"data":HEX},...]}, at most
32 records. tag ranges 0..255; data is an even-length lowercase hexadecimal
string encoding at most 32 bytes (empty allowed). Each frame is one tag byte,
a two-byte unsigned LITTLE-ENDIAN payload length, then the payload. Concatenate
frames without separators. Return {"hex":HEX,"offsets":[INT]} with lowercase
wire hex and the starting byte offset of every frame. No checksum or terminator.
Empty records gives empty hex and offsets.''',
'little-endian-read': '''Request: {"hex":HEX,"offsets":[INT,...]}. HEX is
even-length lowercase hexadecimal encoding 0..512 bytes. Offsets range 0..512.
After complete schema validation, if any offset lacks two available bytes,
return {"error":"out-of-bounds"}, without partial values. Otherwise return
{"values":[INT]} by reading unsigned LITTLE-ENDIAN 16-bit values at each
requested offset, retaining duplicate/overlapping offsets and source order.
Empty offsets succeeds even for empty hex. Fix only the supplied starter's
byte-order defect using the standard encoding facility.''',
'snapshot-diff': '''Request: {"before":[ENTRY,...],"after":[ENTRY,...]} where
ENTRY is exactly {"path":PATH,"digest":ID}. Each side has unique paths;
duplicate paths are invalid even if digests agree. Return {"added":[PATH],
"removed":[PATH],"changed":[PATH]}, each sorted ASCII, for paths present only
after, only before, or on both sides with unequal digest. Input order is ignored.
PATH is / or an absolute slash-separated sequence of components matching
[a-z0-9_.-]{1,32}, except . and .. are forbidden components. No empty component,
trailing slash except /, or repeated slash. Total length is at most 256 bytes.
Paths are virtual names; digests are opaque IDs, not hashes to compute.''',
'mount-routing': '''Request: {"mounts":[{"prefix":PATH,"target":PATH}],
"paths":[PATH,...]}; at most 32 mounts, with unique prefixes. PATH has exactly
the same normalized ASCII grammar as snapshot-diff: / or slash-separated
[a-z0-9_.-]{1,32} components, excluding . and .., no repeated/trailing slashes,
at most 256 bytes. A prefix matches its exact path or descendants separated by
/, with / matching all paths. Choose the longest matching prefix. Replace it
with target and join the remaining suffix with exactly one slash. Exact matches
produce target; no match produces null. Return {"paths":[PATH-or-null]} in
input order. Result length may exceed 256 (up to 512); do not revalidate it as
an input. No host filesystem or symlink resolution.''',
'inventory-reservations': '''Request: {"stock":[{"id":ID,"quantity":INT}],
"operations":[OP,...]}. At most 32 unique stock IDs; quantity is 0..1000000.
OP is {"op":"reserve","token":ID,"id":ID,"quantity":INT} with positive
quantity <=1000000, or {"op":"release","token":ID}. Initially all stock is
available, no active reservations. Reserve error precedence: active duplicate
token, unknown item, insufficient available quantity. Return status strings
"duplicate-token", "unknown-item", "insufficient", or subtract quantity,
activate token and return "reserved". Release restores quantity, removes the
token and returns "released", or returns "unknown-token" without change.
A released token can be reused. Return {"results":[STATUS],"available":[
{"id":ID,"quantity":INT}],"active":[ID]}, available and active sorted by ID.
Work across the supplied model, ledger and process/report modules, retaining
owned state and explicit error propagation; implement reservation behavior in
the supplied baseline without moving all modules into one file.''',
'atomic-transfers': '''Request: {"accounts":[{"id":ID,"balance":INT}],
"batches":[[TRANSFER,...],...]}. At most 32 unique accounts, balances 0..1000000;
at most 32 batches with at most 32 transfers each. TRANSFER is exactly
{"from":ID,"to":ID,"amount":INT}, amount 0..1000000. Evaluate each batch in
order against tentative balances, and commit ONLY if all transfers succeed.
For each transfer check both accounts exist first, then sufficient source funds,
then debit source and credit target. Self-transfer still checks funds and has
zero net change. On the first failure discard ALL changes in that batch and
return "unknown-account" or "insufficient"; later batches use last committed
balances. Empty batches commit. Return {"results":[STATUS],"balances":[
{"id":ID,"balance":INT}]} with statuses "committed" or first error and final
balances sorted by ID. Repair the seeded partial-commit defect in the supplied
three-module starter, preserving generic state, module boundaries and errors.''',
}
