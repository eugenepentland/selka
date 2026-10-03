# Independent checked bytecode source review

No actionable defect found in author commit
`beaaf97c7397beafb0988f5ed73dde0bf4813ebb`, within the scope below.
Reviewed frozen corrected v2 and scalar-shaped v3 source and their full completed
receipts in `codex-lox-vm-bytecode-20261003/.tmp-lox-vm-bytecode-20261003`.
The rejected v1 is excluded from acceptance: its preserved argument count 256
observations show control exit 65 versus native cast-trap exit 1 on both backends.
No guest tests, builds or performance workloads were executed by this review.

`review.py` independently rechecks the actual 37 files of each source and
accepted84 control, all committed author experiment bytes, and exact unified
overlay bytes. Only chunk, compiler, compiler_test, driver_cases, driver_tests
and vm differ; 31 files are unchanged. V3 differs from v2 only in its dispatch
load. Both candidates retain the original interpreter and read_constant, with
no AST or constant-read runtime overlay. This review does not certify the
reviewer's earlier constant optimization.

Pinned SPEC section 8.1 names byte opcodes/operands, two-byte big-endian jumps and
one line per code byte. `Chunk.code` and `ExecFrame.code` use checked `list[u8]`
storage, with ordinary integer casts when reading; opcode constants/order,
operand layout, line maps and algorithms are retained. `read_byte` and dispatch
still perform their checked load before the IP increment. `read_short` retains
its original two-byte IP increment before the two reads, with each octet widened
before multiplication by 256/addition. Thus its maximum result remains 65535;
the change adds no truncating arithmetic or reordered malformed-bytecode checks.
Jump patching retains both existing masks, then performs checked u8 conversions
of values already in 0..255. Loop/jump size errors and clox high-byte/low-byte order
remain unchanged.

The compiler's three new low-byte count masks occur only at CALL, INVOKE and
SUPER_INVOKE emission, after the unchanged argument_list has parsed and diagnosed
the arguments. Valid counts 0..255 are identity conversions. For oversized counts
the compiler still parses every argument, records the same diagnostic/recovery
state, and returns NO_OBJ instead of executing the rejected chunk. Encoding a
discarded count's low byte prevents the unrelated native narrowing trap that
rejected v1. It does not cap parsing, suppress errors, wrap the argument counter
or alter the scanner/token/diagnostic logic. Constants, locals, upvalues and other
byte producers remain bounded, masked or return the existing overflow sentinel.
The public internal Chunk/write_byte representation now enforces its existing
documented 0..255 byte contract; out-of-contract arbitrary integer callers are
not covered by the Lox behavior contract.

V3's `opcode:u8 = frame.code[frame.ip]`, followed by `instruction=int(opcode)`
and the original IP increment, introduces only a plain scalar local. Widening an
octet to signed 64 is total and cannot allocate, invoke a callback, capture a
managed value or trap. Exact source transformations show every handler, frame
root/IP publication, call/return, upvalue traversal and error path unchanged.
Source snapshots retain ordinary list COW: the explicit Chunk snapshot regression
checks earlier byte/line values after replacement and append. Existing roots,
Lox allocation charges and heap sweeps are unchanged; native memory representation
has changed, as permitted by the bytecode design.

For each frozen version, independent receipt checks reconcile 352 fresh public
passes (88 tests across LLVM/QBE×RC/native-GC-stress), with zero cached/failing/
skipped/dropped tests. All 84 prior public test names remain, with four added
tests. Existing provider entries are unchanged and the three new fixtures use
the existing Clock provider bytes. Directory commands omit --cases, so these
receipts establish provider-free execution and structural fixture preservation;
they do not establish provider-backed execution.

Each version also has 1396 exact actual unaccounted ELF program comparisons:
1192 bounded, 12 constant-operand0..255, and 192 argument-limit/recovery comparisons.
The bounded cases cover 13 smokes, 17 focused programs and 23 historical errors per
engine, with both backends and Lox stress off/on. Runtime counts are 424 RC,
424 ordinary tracing-GC and 344 native-GC-stress. Run/omission identities are unique,
disjoint and complete. Eight argument programs cover direct/invoke/super count 256,
malformed tails/comma/nested recovery, and legal 255 arguments reading the last
parameter slot; all full exit/stdout/stderr/statistics tuples equal their controls.
Eight additional RC/native-stress pairs preserve the checked status 2 refusal.
Eighty bounded native-stress smoke cells per version remain explicitly unrun.
Omissions and refusals are not counted as program passes.

The reviewer rehashed every generated input, every before/after frozen source,
compiler/QBE, ELF/sidecar/runtime archive and harness/historical input. All identities
remain unchanged. All 45 raw files in the author's deterministic receipt archive
match their declared hashes and current frozen raw bytes. `review.json` records
exact source37, binary, receipt and committed-file identities and the review's
limits. The author compiler is d14a7040 with QBE 99ad919d; selected d14 is unchanged.

Independent static recount agrees with the author's recorded vm.run disassembly:
v2 LLVM 5710 instructions/487 calls and QBE 9070/454; v3 LLVM 5605/485 and QBE 8606/440.
Accepted84 had LLVM 5586/486 and QBE 8606/440, so v3 removes the v2 QBE expansion,
while the LLVM body still has 19 more static instructions. These structural counts
do not establish execution cost, wall speed or Rust/Go parity. Central measurement
remains necessary for source selection.

The separate proposed generic byte-positive compiler guard remains unimplemented
and outside this source acceptance. A sound extension must test length unsigned
<=I64_MAX before unsigned index<length, retain the captured receiver and every
existing ownership/quiet/CFG/accounting/version refusal, and retain the original
result-slot protocol. That conjunction proves nonnegative/in-bounds access without
assuming byte-list capacity is below 2^63 across both runtimes. Failure must enter
the unchanged canonical normalizer: a huge length with a nonnegative index can
still be a valid canonical read, while a negative index may encounter the checked
length-to-i64 cast. Synthetic huge-length tests should verify admission/fallback,
not impose invented traps. No compiler implementation is certified here.
