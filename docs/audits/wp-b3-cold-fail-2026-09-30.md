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
