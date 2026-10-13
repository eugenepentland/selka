# P4 tree execution and environment construction

Tree interpreter routes fresh environment, instance and class construction to
P1 scalar-input constructors. Constructor references retain the same stack,
current/saved environment and parser permanent roots across collection. Heap
charging remains 32 + 16 * slots for environments and 48 for classes/instances.

Instance assignment checks the target before evaluating the RHS, then reads its
stable handle and invokes the heap field helper afterward. This preserves alias
writes performed by the RHS and removes the full instance/fields snapshots from
the interpreter. Class declaration invokes inherited-method and single-method
heap helpers, removing the interpreter's retained local method-table owner and
repeated table replacement. P1 helper contracts currently use one independent
snapshot pending qualified bounded extraction; no claim of zero-copy mutation.

Four focused normal/stress tests cover separate captured environments, closure
survival after block exit, instance alias/self references and table growth, RHS
mutations, inheritance/override/super/bound methods, and field-validation order
and error lines. The native-clock fixture is carried in cases.json because the
unit runner lacks a Clock provider, matching the historical P2 fixture.

source-identity.json pins the compiler, all guest source, helper dependency and
provider cases. commands.json records exact native test/build commands. The
P1 heap dependency is local and excluded from this owner's commit. Historical
source/evidence, compiler implementation and GC/closure algorithms are untouched.

Verified release tests passed 4/4 with failed/skipped/unsupported/cached zero.
The counted release build passed. Source bytes remained unchanged after both
checks. LLVM inspection found no direct copy/retain/release calls in new_env,
set, instantiate or class_declaration. First attempts failed on a P1 helper
borrow overlap; retained raw logs document that failure before its corrected
dependency was installed. Bounded allocation measurements remain queued.
The env-instance100 probe is an explicitly bounded traffic diagnostic; it is
not a full performance cell and establishes no runtime/RSS or Zig parity claim.
Coordinator owns full60 conformance, integrated modes and full timing with the
unchanged 3x Zig cutoff. No feedback-log additions, pushes or peer merges.
