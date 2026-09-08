# inventory-reservations

Version: 1. Family: multi-module-maintenance. Kind: feature. Tier: medium.

Request: {"stock":[{"id":ID,"quantity":INT}],
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
the supplied baseline without moving all modules into one file.

Apply the shared PROCESS.md transport, type, schema and validation rules.
