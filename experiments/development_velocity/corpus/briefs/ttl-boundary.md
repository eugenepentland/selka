# ttl-boundary

Version: 1. Family: stateful-collections. Kind: bugfix. Tier: medium.

Request: {"operations":[OP,...]}. OP is exactly
{"op":"put","at":INT,"key":ID,"value":INT,"ttl":INT} or
{"op":"get","at":INT,"key":ID}. at values are nondecreasing, 0..1000000;
ttl ranges 0..1000000. A put replaces the key and expires at at+ttl. At each
operation keys with expiry <= at are expired. A zero-TTL put is immediately
unavailable, including to a following get at the same time. Put result is null;
get result is the stored integer or null. Return {"results":[INT-or-null],
"live":[ID]} with sorted live keys at the last operation's timestamp (empty
for no operations). Fix the starter's expiry-boundary defect, preserving its
interface and non-boundary behavior.

Apply the shared PROCESS.md transport, type, schema and validation rules.
