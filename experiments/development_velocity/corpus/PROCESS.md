# Process contract: bounded-json-batch-v1

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
