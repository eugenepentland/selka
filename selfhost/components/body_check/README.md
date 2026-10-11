# B1 scalar body checking

This producer owns typing and lowering of ordinary nongeneric scalar function
bodies from raw ASTs. It emits complete native typed nodes, statements, functions,
local metadata, and per-function table ranges. It does not consume a native
semantic worklist or native checked bodies.

The admitted types are `int`/`i64`, `bool`, and `Unit`. Supported operations include
integer literals throughout the signed i64 range, booleans and unit, scalar unary
and binary operations, lexical locals and mutable assignments, ordinary forward
and recursive calls, named and default arguments, scalar mutation markers,
branches, while loops, basic integer range loops, break/continue, return, discard,
and assertions with static messages. Signature annotations and local annotations
are checked by the producer. Diagnostics include related sites and source edits.

Generic functions, checked failure signatures, managed values, lambdas, resources,
contracts, nominal declarations, non-i64 literal suffixes, floating division,
chained comparisons, dynamic assertion messages, and explicit range strides are
outside B1. Range variables are read-only: assignment retains the native `E_IMMUTABLE`
source diagnostic. Shadowing an existing outer declaration retains the native
shadowing diagnostic. Scalar alias
declarations can remain in the catalog for name/shadow checking, but alias type
annotations are not resolved by B1. These limits produce a `P_BODY_PROFILE` result;
component mode refuses the program without native body fallback. Malformed graph
transport instead fails the exchange and is not reported as a source diagnostic.

Native code still owns catalog foundations, entry adaptation, effects and origin
analysis, domain codecs, warnings, and cache publication. Shadow mode compares an
uncached native body batch, diagnostics, and import usage. Component mode adopts
the validated batch at the body-checking seam. Reference mode remains available.

`main.my` accepts `--exchange FILE` or an unframed `--request FILE`. The normative
wire contract is [WIRE.md](WIRE.md): protocol/schema 1/1, correlated `SLKBCK01`
envelope, named-field `SLKBKI01` request and `SLKBKR01` reply. Requests contain raw
ASTs, sources and module/declaration facts, not semantic decisions. Replies carry
success, full diagnostic failure, or explicit profile refusal.

The bounded profile allows 64 MiB frames, 1,048,576 graph values, 4,194,304 graph
edges, depth 256, 1 MiB per module source, 8 MiB aggregate sources plus at most
4096 separator bytes, and 4096 modules. Typed nodes and statements are each capped
at 262144; functions and aggregate locals at 65536. Existing parser value helpers
are immutable symlinks and are copied into coordinator snapshots. Seed and
component-v1 language admission remain unchanged.

Pure tests are the six `*_tests.my` modules. Run each using the coordinator-verified
seed under `scripts/build-slot.sh build`, both normally and with
`--release --verify-facts`, `MYL_CORE_LEAKCHECK=1`, private disk `TMPDIR`, and a
worktree-local Zig cache. Installed workflow tests additionally compare complete
native/component/shadow outputs and generated program execution; pure test counts
alone do not establish whole-checker adoption.
