# lru-cache

Version: 1. Family: stateful-collections. Kind: feature. Tier: medium.

Request: {"capacity":INT,"operations":[OP,...]}, capacity 0..16.
OP is exactly {"op":"put","key":ID,"value":INT} or {"op":"get","key":ID}.
Initially empty. A successful get returns {"value":INT} and makes that key most
recent; a miss returns {"value":null} and changes nothing. Put replaces/inserts
and makes the key most recent. If insertion of a new key exceeds capacity,
evict the least recent key. Put returns {"evicted":ID-or-null}; replacement
never evicts. Capacity zero stores nothing and put returns evicted=null.
Return {"results":[RESULT],"entries":[{"key":ID,"value":INT}]} with final
entries in least-to-most-recent order.

Apply the shared PROCESS.md transport, type, schema and validation rules.
