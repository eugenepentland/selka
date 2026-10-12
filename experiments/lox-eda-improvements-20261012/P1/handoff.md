# P1 scalar VM frames

Implementation replaces owned function/code/upvalue payloads in `CallFrame` with closure/function object handles and scalar `ip`/`base`. Shared `heap.my` readers access the original function/closure payload in a scoped match and return a selected integer, object handle or Value. `vm_queries.my` supplies only a VM call discriminator and bound-method receiver/method scalar readers. No native address or borrowed storage survives the helper call. The runtime's existing frame closure roots retain the function and captured upvalues through normal GC tracing.

The VM publishes its scalar frame after fetching an opcode (error location), before dispatching a call (caller continuation), and after each successful handler. It returns immediately after a failing handler resets the frame stack, avoiding the old bottom writeback with frame_count zero. Closure creation queries only upvalue_count and selected parent upvalues. Call dispatch avoids all whole-object snapshots. VM class/instance read paths also use the P3 selected readers.

`heap-layout.patch` is the explicitly approved local frame test patch; the coordinator also applied P3 helpers locally for final API validation; heap.my is coordinator-owned and excluded from the P1 commit. Integration must apply the scalar layout before compiling P1 vm.my. Existing object snapshot API semantics remain intact.

Pinned compiler: `/home/epentland/ai/canopy/mylang-text-gaps-main-20261012/.tmp/text-gaps/coordinator/common-002/install/bin/mylang`, SHA256 `2dcba1cb1a98846bb8c1319575da1b3564e60af70162e195c2fbb6ec3af0f329`.
Frozen counted checked baseline: coordinator `.tmp/lox-eda-rerun-20261012/lox/zero-rc-counted`, SHA256 `43914d2e558b27fdeccf931047775c95f639ad83a0001f20b3569861203203e0`.

All queued native work sources `/home/epentland/.config/mylang/dev-env.sh`, exports `MYLANG_SLOT_DIR=/home/epentland/.cache/mylang/slots` and uses private `TMPDIR=$PWD/.tmp/lox-eda-improvements/P1/tmp`. Commands run through `scripts/build-slot.sh build`.

Commands:

```
mylang build experiments/lox-eda-improvements-20261012/P1/scalar_frame.my --experimental-zero-rc --release --cache-dir .tmp/lox-eda-improvements/P1/probe-cache -o .tmp/lox-eda-improvements/P1/scalar-frame
mylang build experiments/lox-eda-improvements-20261012/source/lox/main.my --experimental-zero-rc --release --counters --emit-llvm .tmp/lox-eda-improvements/P1/candidate.ll --cache-dir .tmp/lox-eda-improvements/P1/cache -o .tmp/lox-eda-improvements/P1/candidate
python3 experiments/lox-eda-improvements-20261012/P1/verify.py .tmp/lox-eda-improvements/P1/candidate /home/epentland/ai/canopy/mylang-text-gaps-main-20261012/.tmp/lox-eda-rerun-20261012/lox/zero-rc-counted .tmp/lox-eda-improvements/P1/verify
```

Scalar probe build has 120-second compile ceiling; candidate compile has 240-second ceiling. Focused verifier has 30-second absolute timeout per child. Its eight cases cover recursion, open/shared/closed/transitively captured upvalues, inheritance/classes, GC stress, runtime/call error locations, stack overflow and return cleanup. It compares both binaries in normal/stress modes. Separately labelled N=10/100 arithmetic and single-call loops collect allocation traffic, managed peak and exit-live counters. They are reduced probes, not full benchmark replacements. No runtime/RSS timing is collected here. Candidate counters include the coordinator-approved P3 heap readers and their VM read-path adoption; the comparison measures this P1+P3 application snapshot, not an isolated compiler or frame-only effect.

Explicit runtime coverage is not implied by a directory test run: `driver_tests.my` uses `_tests.my`. Run its 13 public tests explicitly with `mylang test source/lox/driver_tests.my --cases source/lox/driver_cases.json` plus the requested ownership-mode flags. Their SHA256 identities are `7de9d76e841420434c3ee6195cd31cb3acfebd23d45c290b6ef49077bd87e99a` and `da7be595d0c9ef93fe12fd6e7b732eb8bc6b955a796e43d7e375b52be45cc37a`.

For five-mode CLI checks, run `python3 P1/verify.py MODE_BINARY BASELINE_BINARY PRIVATE_CASE_DIR --correctness-only`. This executes 32 explicit checks (8 cases × normal/stress × two arms), with no counters or scalar-probe requirement. The frozen verifier SHA256 is `1e2f8aaa55c74345791a89cac717a4bf048a9ef388a085856ae975104e40f4b8`.

Status: pinned checked release candidate compiled; frozen build input hashes verified after build. Scalar frame probe compiled and executed successfully. All 32 explicit CLI correctness checks passed, including both normal and GC-stress runs of each case on candidate/baseline. All eight reduced counter runs exit with zero live managed bytes and zero ownership retain/release/unique-test events.

Candidate binary SHA256: `c9a9bf6bfcfd1012745a09f0d620d34311c209c35f20c3e991dbd8031d7f0eaa`. LLVM inspection confirms a four-i64 frame ABI and no allocation/copy/retain/release callees in selected instruction/constant/upvalue readers or `call`. Raw counter evidence and hashes are archived beside `verification.json`.

Reduced arithmetic-loop allocation slope fell from 54,272 to 0 bytes per added iteration (18 opcodes), or 3,015.111 to 0 bytes per added opcode. Single-call-loop slope fell from 71,488 to 0 bytes per added iteration/call, including dispatch/global work. At N=100, arithmetic cumulative traffic fell from 7,032,040 to 1,515,544 bytes; call-loop traffic fell from 8,844,168 to 1,592,568 bytes. Arithmetic managed peak fell from 830,768 to 799,200 bytes; call-loop peak fell from 832,112 to 800,544 bytes. These are native managed counters for reduced P1+P3 snapshots, not timing/RSS claims.

Owned commit pending normal Guardian hook. Coordinator owns full conformance, ownership matrix, integration gate and full-input timings/cutoffs.
