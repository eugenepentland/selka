# Wave 7a: an application memo library in Selka

Baseline `cf3578c67` (qualified Wave 6), branch `codex/selka-cache-wave7`.
Local main remains `1d202d41b`, already integrated into this history. There is
no configured remote. The separate primary integration checkout is not changed.

The Wave 7 plan starts with a bounded application library, then adds persistent
identity and durable steps as subsequent milestones. Implement the first
milestone here: a Selka `memo` standard module with an explicit bounded FIFO,
exact tagged integer/text/byte arguments, allocation-only compute callbacks,
independent value snapshots and observable hit/miss results. Zero capacity is a
supported forced-execution reference. Reject invalid limits through a typed
module error. Bound entries and backing slots; arbitrary payload bytes remain
subject to the application's runtime memory budget.

Each entry binds its actual callable. Add a small native `same_function`
comparison, restricted to compatible function values, so replacing a cache's
computation cannot reuse another function's result. The comparison is local to
the running program and supplies neither a raw address nor a persistent digest.
Keep ordinary callable equality/hashing ineligible and preserve effect and
capture restrictions. Cache retention, eviction and lookup stay written in
Selka; build/install/use remain Python-free.

Qualification compares normal calls with zero-capacity execution, covers exact
key kinds, same-signature different functions, callback replacement, nested
managed results, key/result/cache-copy mutation isolation, deterministic FIFO
replacement, limits 0/1/2/65536, repeated replacement and clear. Reject callbacks
with external effects, captured locals and unsupported result types; preserve
traps without inserting before completion. Run native debug/release with fact
and leak checks, executable documentation, input coverage, formatting and the
complete verification inventory. Use Sol 6.1 agents for the library, compiler
primitive and independent qualification lanes.

Later Wave 7 milestones remain explicit:

- **7b:** compiler-issued reachable implementation identities, actual higher-order
  callable roots, canonical argument/result encodings and schemas, compiler/
  runtime/target context, bounded persistent storage and edit/revert oracles.
  Names, signatures, manual versions and local function pointers are insufficient.
- **7c:** capability-checked atomic publication, synchronization and run ownership;
  retained journals; captured CSV input and committed chunk outputs; serializable
  aggregation; crash injection around artifacts, journal commits and publication;
  competing recovery, code/input incompatibility, corruption and storage failure.
  State separately which process-crash/power-loss guarantees were qualified.

Current guest filesystem APIs lack durable rename/sync/locking operations, and
current guest code has no compiler-issued implementation-closure digest. Neither
Wave 6 retention pins nor `File.flush()` is a durable-commit substitute. This
milestone exposes no persistent-cache or restart guarantee.
