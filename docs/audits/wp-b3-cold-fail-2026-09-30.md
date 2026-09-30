# Private runtime cold failure candidate, 2026-09-30

Source `c9ad8375605a5bb4575ba6773b14ff70bd63e169` adds only `cold` to private `fail`'s existing `noinline` declaration. The function body, header, callers and ordinary C convention are unchanged. The returning-context, sticky first trap/detail, armed longjmp and heap-teardown behavior remain authoritative; no count/MAX guard was removed. This is scoped correctness and code-shape evidence. Independent review, root composition, broad gates and measured performance acceptance remain pending.

The earlier `preserve_all` candidate was rejected: it lost required located LLVM trap frames. Its actual FDE saved XMM0–XMM15, which the pinned Linux x86-64 libunwind register restore does not support (`UNW_EBADREG`). Rejected sources, original CLI failure and CFI/toolchain excerpts are preserved separately by docs-only commit `933ed15c`; no CFI, trace expectation or shared toolchain was altered.

In the cold-only actual LLVM3 full-LTO raytrace binary, the normal checked primary hold (`0x10134cc` load → `0x10134d1` increment → `0x10134d4` zero/refusal → `0x10134da` admitted store) and shadow hold (`0x10138aa` → `0x10138af` → `0x10138b2` → `0x10138b8`) no longer execute the excess floating-zero reset. Both refuse to shared cold block `0x1013abc`. Other resets remain after actual failure/sqrt/scope calls. The private fail FDE contains no saved FP-register rules. This establishes machine shape; no new profile, instruction-count reduction or timing claim is made.

Validation, all heavy commands admitted through build-slot:

- Compiler install: 12/12 steps, scoped Guardian pass.
- Frozen supporting-test unit run: 14/14 (two named tests plus twelve mandatory unnamed blocks), zero failed/skipped. The new actual Zig owner invokes the real C runtime to verify an unarmed failure returns, records overflow operands, and preserves the first trap/detail across subsequent failures. Existing frame test exercises actual armed longjmp, scope detachment and teardown.
- Exact located overflow CLI: 3/3 (one named test plus two unnamed), twelve QBE/LLVM boundary pairs compare stdout, trap operands, located calculate/main frames and machine-readable records.
- Actual raytrace: QBE and LLVM3 full/Thin/no-LTO output all match `203351956\n`, status0, empty stderr (four executables).
- Official native execution driver: Clang and GCC each success/trap/fast; all six actual modes pass existing exact RC traffic checks under UBSan.
- Whole-tree Guardian: 88/88. A spec-case-only intermediate link was rejected, then corrected to a primary spec link on the executed Zig owner. A no-match comma-filter invocation was also rejected; repeated filters selected the two intended tests. Both rejected harness logs are retained separately and contribute no passing count.

Raw input sources, source patch, exact admission commands, installed compiler/QBE identities, actual guest/native executables, assemblies/CFI and logs are in [the verified archive](evidence/wp-b3-cold-hint-20260930/raw.tar.gz); [receipt](evidence/wp-b3-cold-hint-20260930/receipt.json). Compiler prefix and regenerable guest cache are excluded from the archive; their executable hashes remain bound and the owned installed prefix is retained. Every raw archive member's length/SHA256 was verified after writing.

Root subsequently completed independent source/ABI and evidence review: all 77 cold-hint and 67 rejected-preserve-all raw members matched their lengths/hashes; production source differs from `cfee0070` only by the private declaration attribute, and the header is byte-identical. Root independently reran Clang and GCC UBSan `native_rc_execution` success/trap/fast, six actual modes, with the official exact RC traffic checks. Existing replay scripts, logs, receipts and both native executables are retained without a new replay in this docs-only task.

Root also measured the focused LLVM raytrace and float_loop pairs at development, smoke and full sizes (six output pairs, all exact). Their hardware instruction counts relative to the archived A5 originals are:

| Program | Size | A5 RC instructions | Cold-hint RC instructions | Change |
| --- | --- | ---: | ---: | ---: |
| raytrace | dev | 1,261,221,624 | 1,260,954,309 | -0.021195% |
| float_loop | dev | 164,220,409 | 168,218,325 | +2.434482% |
| raytrace | full | 1,261,221,449 | 1,260,954,294 | -0.021182% |
| float_loop | full | 164,220,230 | 168,218,326 | +2.434594% |
| raytrace | smoke | 1,261,221,723 | 1,260,954,288 | -0.021204% |
| float_loop | smoke | 164,220,432 | 168,218,313 | +2.434460% |

Raytrace passes this focused comparison; the cold hint does not improve float_loop, whose development/full regression remains +2.434482%/+2.434594%. This evidence covers six focused output pairs, with no full 258-pair or final combined gate claim. Root composition and broad/performance acceptance remain the integrator's responsibility.

The additive [root independent archive](evidence/wp-b3-cold-hint-20260930/root-independent.tar.gz) and [receipt](evidence/wp-b3-cold-hint-20260930/root-independent-receipt.json) bind source/ABI checks, copied native executables, candidate guest binaries/manifests, published A5 control binaries/results, six-row comparison and original build/measurement logs. Every comparison scalar was cross-checked against its actual archived candidate and A5 JSON row; every raw archive member's length/SHA256 was verified. Source and the owned compiler prefix remain frozen. Central Guardian feedback is committed at `4ec25313c6f1fabddf195250121b920e143590ed`; this agent made no Guardian-repository writes.
