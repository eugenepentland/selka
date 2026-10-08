# Copy-local names preserve LLVM memory facts

Candidate production commit: `d14e26f4473d6c50f56751736ed8ef325adcaecd`,
following the bounded-copy selection commit `5dc31c3a`. The earlier candidate's
rejected screen remains immutable in `../runtime-goal110-calls-20261004`.
This candidate is **rejected for integration** after the focused paired screen.
Direct calls improve, but the original fallback and large record-update paths
still regress. This is not a current-fastest acceptance result.

The rejected candidate copied labels while retaining every temporary name.
LLVM's memory-class and element-chain analysis requires one definition for a
temporary, so the duplicated body lost otherwise valid memory facts. The actual
cached compute IL changed record temporaries such as `%v8324` and `%v8326` from
one definition to two. A replay through the actual LLVM analysis after sticky
versioning confirms that they changed from element memory class with alias
metadata to unknown class without metadata. External frame allocations retained
their original facts. `alias-analysis.tsv`, `alias-proof.zig` and its log pin
that diagnosis; the replay does not measure runtime performance.

The new transform renames only region temporaries with exactly one definition
and no operand or recognized hint reference outside the copied region. It keeps
external state, parameters, allocations outside the region, multiple definitions
and live-out values shared. Quoted data and unrelated comments stay intact;
the existing object, element, reference-count and affine hint tokens follow the
renamed value. An occupied copy namespace refuses the transform. Original
fallback temporaries retain their original names, so selected copies no longer
duplicate their definitions. Actual renamed byte costs drive the same bounded,
deterministic selection, with no budget increases or certification changes.

The actual compute guest selects nine of eleven certified values, in order
`0,1,7,6,8,4,9,10,5`, with 174,885 copied bytes. Record-update value 5 is
selected. Certified values 2 and 11, plus unknown value 3, use the complete
original fallback. The changed membership follows actual renamed text costs;
packet decoding is excluded by the unchanged budget.

Both compiler hosts used for the revised paired screen are Debug, while guests
are ReleaseFast and actual LLVM uses optimization 3 with full LTO. The Debug
730 LLVM compute control is byte-identical to the preserved ReleaseFast-host
730 LLVM control (`366d46cc759592fd6d21f23e5a786d98516c29492b9c55a0c766f126c705f8b3`).
The Debug 730 QBE control differs from its ReleaseFast-host counterpart; revised
QBE observations use the Debug control, and the old screen remains unchanged.

Completed qualification:

- Three focused copy-name tests plus twelve imported tests passed (15 total).
  The broader invariant-loop command passed 20 tests again on the final source
  after the parameter bundle (exit 0; 14.24 seconds). Coverage includes external/shared references, live-out values,
  multiple definitions, occupied namespaces, all recognized hint forms, quoted
  data, unrelated comments, exact rewritten costs and allocation failure.
- The canonical final compiler build passed all 88 Guardian checks. The commit
  gate first rejected a seven-parameter helper; bundling its related arguments
  satisfied the existing gate without a configuration change.
- The exact final guests passed 216 independent compute checksum inputs,
  including selected, excluded and unknown selectors, both frozen sizes,
  multiple seeds and nearby dimensions. Commands, guest backend policies,
  compiler/source/clock hashes and outcomes are in
  `guest-build-qualification.json`.

The focused Zig logs include a listener `failed command` line after their PASS
summary although the enclosing command returned exit 0. This is preserved as
observed tooling output; no test failure is inferred from that line. Guardian
feedback is consolidated by the parent agent in the Guardian repository.

The unchanged eight-form Boolean/CFG producer-join diagnostic passed 144 inputs
and 432 executions on the final source across accounted QBE, fast QBE and actual
LLVM optimization 3/full LTO. All forms were admitted; process status, stdout,
full stderr, independent oracles and accounting-mode probes matched. This is
Boolean producer joining, not native text joining.

`renamed-alias-proof.zig` replays the actual cached IL through sticky processing
and the translator's own memory analysis (two tests passed, exit 0). The rejected
candidate loses 103 baseline facts, while the renamed candidate retains all but
five. Those five are foreign-address argument-list loads before kernel setup
(`v24`, `v2890`, `v3586`, `v3661`, `v3736`). The original record temporaries and
`u4_` copied counterparts again have element/frame facts and one definition.
This does not assert that every unclassified address is optimized.

The retained actual LLVM input contains the restored frame field GEP in copied
record block `bb_us553_4_i800`. The selected record inner loop at
`0x102e299`–`0x102e3d4` no longer has the rejected candidate's repeated 16-byte
aggregate copies. It still writes three scalar record fields, checks bounds and
overflow, and has extra scalar scratch stores at `0x8(%rsp)` compared with the
baseline. The scratch slot remains a ptrtoint/inttoptr chain in translated LLVM;
that is a subsequent lowering hypothesis, not a diagnosed cause of its runtime
regression.

`static-dispatch.py` verifies the pinned actual LLVM table and direct graph.
All nine frontend-selected graphs contain no indirect jump between the outer
batch dispatch (`0x102d07b`) and common fold (`0x102e791`). Values 2 and 3 retain
inner dispatch at `0x102d8d0`. LLVM gives excluded frontend value 11 a separate
machine-code loop; its static direct graph is recorded rather than assumed to
share the other fallback target. Counts include untaken setup paths and exclude
cold external edges, helper bodies and indirect targets.

| Whole-entry static artifact | Debug 730 control | Candidate |
|---|---:|---:|
| LLVM entry bytes | 20,050 | 25,026 |
| LLVM whole guest `.text` bytes | 169,554 | 174,530 |
| LLVM entry instructions | 4,148 | 5,221 |
| LLVM entry stack allocation bytes | 728 | 760 |
| QBE entry bytes | 43,823 | 59,235 |
| QBE whole guest `.text` bytes | 204,125 | 219,549 |
| QBE entry instructions | 9,429 | 12,718 |
| QBE entry stack allocation bytes | 2,968 | 4,072 |

These measurements cover the whole entry, including untaken paths. They do not
measure executed kernel instructions or stack traffic.

The parent-approved paired screen ran 2026-10-04 02:37:09–02:37:40 UTC, with
five measured rounds and one warmup per case/size/arm on CPU 2. All 144 outcomes
matched the independent checksum; the command returned exit 0. Raw samples,
order, wall/kernel times, hashes and per-sample host cgroup/frequency snapshots
are retained in `regression-screen.json`. The following ratios are
candidate/before; intervals are exploratory paired-bootstrap 95% intervals.

| Case / size | LLVM ratio [interval] | QBE ratio [interval] |
|---|---:|---:|

| record_update / small | 1.013 [1.002, 1.028] | 0.814 [0.813, 0.817] |
| record_update / large | 1.066 [1.046, 1.082] | 0.810 [0.794, 0.810] |
| branch_predictable / small | 1.127 [1.111, 1.151] | 0.966 [0.964, 0.970] |
| branch_predictable / large | 1.122 [1.110, 1.345] | 0.943 [0.940, 0.947] |
| call_direct / small | 0.726 [0.717, 0.742] | 0.269 [0.268, 0.270] |
| call_direct / large | 0.678 [0.672, 0.686] | 0.252 [0.250, 0.253] |

Only the exact historical iteration/seed plans are reused. Every timing sample
is fresh and paired within this session. Current-fastest reference arms were
not measured, historical measurements are never paired, and these selected
screens do not establish the 1.10 goal or independent confirmation. Option and
result timing did not run because the prior-regression screen did not clear.

Large raw files are archived with deterministic gzip. `archive-index.json`
records raw and compressed hashes; `gzip -dk FILE.gz` restores a local raw copy.
The original rejected `5dc31c3a` evidence is unchanged.
