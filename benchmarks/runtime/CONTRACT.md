# Runtime microbenchmark contract v1

Scope: standalone, single-threaded guest programs; main mylang compiler revision
6df58b02554401f9d37564cceffd14277a835ae1. Do not change compiler/runtime code.

Each port is one executable accepting four positional arguments:
`CASE SIZE ITERATIONS SEED`. CASE is `record_reads`, `tagged_stack`,
`mutate_unique`, or `mutate_shared`. SIZE >= 2, ITERATIONS >= 1, and
1 <= SEED <= 1000000. Benchmark fixtures stay within signed 64-bit arithmetic.
Output exactly `CHECKSUM ELAPSED_NS\n` (two decimal integers). Nonzero status,
nonpositive elapsed time or any unexpected output invalidates a measurement.

Prepare input before the monotonic start timestamp. Take the finish timestamp
after the kernel and before final result formatting. Initialization and final
validation/folding are excluded unless explicitly included below. Keep elapsed
measurement native and in-process. Results and argument-dependent input must be
observable; do not insert per-operation optimization barriers or force noinline.

## record_reads

Before timing, build SIZE records at index j in [0,SIZE):
- code = (SEED + j * 17) % 1009
- bias = (SEED * 3 + j * 7) % 257
- payload = [j + SEED, j + SEED + 1, j + SEED + 2, j + SEED + 3]

Initialize index = SEED % SIZE and checksum = 0. For ITERATIONS repetitions:
read a record by value in mylang (a readonly borrow/reference in the other
languages is equivalent because no records are mutated); call an ordinary helper
that returns record.code + record.bias + record.payload[0]; set
checksum = (checksum + helper_result) % 1000000007 and
index = (index + 2 * SEED + 1) % SIZE.
The odd stride visits every record at the measured power-of-two sizes.
Return checksum. The helper may inline naturally. Payloads use each language's
normal dynamic list/vector/slice representation, allocated outside timing.

## tagged_stack

Before timing, build SIZE opcodes: opcode[j] = (j + SEED) % 4.
Initialize a dynamic stack with tagged Int(SEED) and Bool(false), and cursor = 0.
Int and Bool are declared variant/enum alternatives (an explicit tagged struct
in Go). During each of ITERATIONS steps, pop the top value, read the remaining
Int base, then dispatch opcode[cursor]:
0: delta = 3 if popped is Bool(true), 1 if Bool(false), otherwise popped Int % 5;
1: delta = 7 if popped is Bool, otherwise popped Int % 7;
2: delta = 11 if popped is Bool, otherwise popped Int % 11;
3: delta = 13 if popped is Bool, otherwise popped Int % 13.
Set new_base = (base + delta + opcode + 1) % 1000003.
Replace stack[0] with Int(new_base).
Push Bool(new_base % 2 == 0) for opcodes 0 or 2; otherwise push Int(new_base % 97).
Set cursor = (cursor + 1) % SIZE.
The stack stays length two but real dynamic stack pop/push operations express
this workload. After timing, checksum = base * 101 + (1 or 0 for the top Bool,
or the top Int). No boxing, custom allocators, or unsafe indexing.

## mutate_unique and mutate_shared

Before timing, values[j] = (SEED + j * 13) % 1009 for j in [0,SIZE).
For each of ITERATIONS batches, set index = (SEED + batch * 17) % SIZE.
`mutate_unique`: mutate values[index] = (values[index] + batch + 1) % 1000003;
checksum = (checksum + values[index]) % 1000000007.
`mutate_shared`: retain a logical snapshot of the whole values collection,
perform the same mutation on values, then observe snapshot[index] and
values[index]; checksum = (checksum + snapshot[index] + values[index]) %
1000000007; release the snapshot before the next batch.
Snapshot preservation/materialization and destruction are INSIDE timing.
Use language-native list value/COW semantics in mylang, an explicit Vec clone
in Rust, slice copy in Go, allocator duplication in Zig. No pooled/custom
allocators. This deliberately compares equivalent snapshot behavior using
native facilities, not identical physical copying strategies. Each snapshot
must preserve every element; no replacement of the snapshot with a scalar.
After timing add the sum of final values to checksum, modulo 1000000007.

## Initial profiles and evidence

Use small/large sizes (proposed 64/4096; mutation 64/1024), fixed seed 42.
Choose iteration counts after a pilot, identically across language arms per
case. Include edge correctness probes (size 2/3/17, seeds 1/42/999983, and odd
iteration counts); Python reference implementations supply independent expected
checksums. Timing: 3 warmups then 15 rounds, arms interleaved deterministically,
CPU 2 pinned with its sibling 3 reserved. Record CPU/environment/toolchain,
source/binary/compiler hashes, commands, per-sample values and memory metrics.
Capture separate process wall time as a secondary metric, never kernel time.
