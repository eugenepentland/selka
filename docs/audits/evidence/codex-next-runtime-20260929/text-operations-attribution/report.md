# LLVM text_ops: frozen instruction attribution

This read-only investigation compares the approved Phase A LLVM binary with the
combined `5535e5a3f0b67e23d0fc9f92f594d7b3feb12a3f` binary. It does not accept a
runtime candidate or replace the required final corpus measurements. Comparison
builds and Callgrind runs were individually admitted through
`scripts/build-slot.sh build`; Callgrind ran on CPU 0. The scratch C-object
suite ran sequentially inside one admitted Python invocation. No hardware
performance samples or timing-pool
claims were made. Production files remain identical to the frozen source.

## Identity and method

The original control executable has SHA256
`f96fc7a4bd08119cc045e85f3c8cf57381a8c8f96d83661c20347e6cc637e270`;
the candidate has SHA256
`715368e8703cadbcc03d68e7a34f3e4fc2be07efdb380fd8c36b8e1fea64244f`.
The corresponding frozen compilers have SHA256
`4059a85e3d081f8a73b370e03e7d86cba8eb8a47531bfcdd7c09e6cc109d74b1`
and `92af6924d4d80b40b55438b3531243ad4e66b5952e00aaeecd01220de8b6fb24`.
Both executable copies are ET_EXEC. Symbol-bearing rebuilds reproduce every
allocated ELF section's type, flags, address, size and contents exactly in each
arm. `receipt.json` retains the complete section comparison and every admitted
command. Profiling these copies therefore preserves the executed guest/native
code, static data, and code addresses of each original executable.

The source is the same 200,000-iteration `bench/parity/suite/text_ops.my` in all
three size labels. `quick.py` scales Lox, not this source. Source SHA256 is
`bf608ad3843a7763953d8874107dc470d946f459415ef046d0a7a32967f7bcdb`.
Both Callgrind runs exited 0 with byte-exact expected output:

```
10000066287 599994 20000
4066669 3666669 22228
```

## Observed stable cost

Callgrind 3.26.0 counted 1,345,249,062 control instructions and 1,356,946,415
candidate instructions: +11,697,353 (+0.869531%). This capture follows the low
variant. It does not reproduce the extra approximately four million instructions
in the recorded candidate full-size hardware row. Simulator startup/libc costs
are not asserted to equal hardware totals. Both complete raw profiles, symbols,
assembly and parsed instruction/call counts are preserved.

| Function | Control self instructions | Candidate self instructions | Delta |
| --- | ---: | ---: | ---: |
| text_ops main (semantic symbol `myl_f_71cb497e…`) | 163,440,490 | 167,974,745 | +4,534,255 |
| generated pointer-list append (`myl_t_8c25cb36…_rcg_list_append`) | 50,486,074 | 54,857,532 | +4,371,458 |
| myl_rc_edges_release | 66,856,869 | 67,799,721 | +942,852 |
| myl_rc_edge_release | 46,845,577 | 47,455,576 | +609,999 |
| drain_one | 55,459,882 | 56,049,880 | +589,998 |
| myl_rc_storage_retire | 12,145,668 | 12,612,808 | +467,140 |
| myl_rc_hold_edge_release | 24,686,975 | 24,876,974 | +189,999 |

Two integer-format routines appear as different raw address names in the parsed
function table, but each executes exactly 44,933,520 self instructions; their
apparent positive/negative deltas cancel. They are not an added-cost finding.

The pointer-list append executes 1,400,010 times in each arm and makes **zero
executed callee calls** in both profiles. It is generated managed-pointer RC
glue, not the scalar `qbe_rc_append` plain-readiness query. Extending the existing
readiness inlining qualification cannot remove this particular measured cost.

The candidate append's counted-owner path runs 742,862 times; the remaining
657,148 appends follow the immortal/uncounted path. The candidate performs a
UINT64_MAX refusal check and acquires the owner before copying the source into
the appended slot. The old control copies first and increments without that
check. Reverting that order or deleting the refusal would not preserve the
current native count contract. The candidate counted path reloads the source
pointer 742,862 times at `0x10251d9`; its common path executes an epilogue jump
1,400,010 times at `0x10251df`. `*-append-executed.txt` records exact weighted
instruction addresses, and `append.diff` contains the complete comparison.
Native retain fallback, MAX refusal and arena/null branches are unexecuted in
this particular positive workload; they remain required behavior.

## Variable component and scope of conclusion

The preserved root hardware records show candidate LLVM dev/full/smoke totals
1,356,857,034 / 1,360,857,010 / 1,356,857,036. Full minus dev is 3,999,976.
Control LLVM totals are 1,345,157,947 / 1,345,157,600 / 1,345,157,734. The
candidate QBE full-minus-dev difference is 2,000,021. These records were copied;
this reviewer did not repeat hardware measurements.

The low candidate profile calls `myl_rc_edges_release` 399,999 times and never
executes the extra occupied-slot probe in its shape map. A separate typing-agent
investigation reports that each such probe costs ten instructions, so one extra
probe per call gives 3,999,990, within fourteen instructions of the recorded
LLVM full/dev difference. The typing agent also reports six first-100 native
lookup snapshots: five had zero misses, and one had a single occupied-slot miss
on each lookup. Those snapshots demonstrate an address-dependent probe but do
not directly count the entire production four-million-instruction term. That
follow-up is separately owned evidence, not a high-variant capture from this
review. The integrator chose a narrowly proved
canonical registered-shape release helper as the next source path; the public
raw-shape lookup and all count/invariant checks must remain. This report makes
no acceptance claim for that unreviewed continuation.

The induction-hint agent reports only two hinted main-loop counter producers in
the direct text_ops entry closure; other imported hinted helpers are outside
that closure. That static fact alone does not attribute the variable cost.

## Preserved scratch layout experiments

`append-layout-probe` contains the actual captured generated RC C, its retained
original function, and two private copies compiled to standalone C objects with
the inner compiler commands/statuses in `build-receipt.json` and suite logs.
The exact outer stdin Python invocation was not separately serialized. One adds only an unlikely
hint to the existing retain fallback predicate; the other routes that same
fallback through a private cold/noinline wrapper. Both leave native MAX checks,
owner acquisition, source reload, source/destination alias conditions and
publication order present. Their standalone assembly moves the native fallback
after the return and removes the common copy-to-epilogue jump. The standalone
object has a different prologue from the production LTO executable; **no linked
guest, performance or behavioral acceptance claim follows from these objects**.
Neither was applied to compiler/runtime source. A possible cached one-word
source snapshot would require a separate alias/ordering proof and tests; it is
not implemented here. The redundant shape lookup is the sole active correction
path, avoiding simultaneous production patches.

The archive excludes copied compiler prefixes and configure caches. Frozen
compiler identities and prefix file manifests are included, while all original
and symbol-bearing guest executables, raw profiles, code/source snapshots,
inputs, outputs, admission commands and scratch C objects are included. Guardian
was not exercised in this read-only installed-compiler/profiler task.
