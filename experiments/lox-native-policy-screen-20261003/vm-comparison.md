Frozen native policy QBE VM comparison

This host-only inspection used the existing selected root ast-qbe and the actual
qualified native-policy-v2-rc-qbe ELF. No compiler/QBE emission, guest execution,
performance run or frozen source/prefix/package mutation occurred. Commands ran
on CPU14. The exact source878/source37/package/ELF/object/fragment identities and
all 1,297 read files before/after are in final/comparison.json.

All 41 VM IL units, object function bytes and relocation records are identical.
40 survive linking in both arms; the other function is omitted in both. All 40
linked functions are identical outside existing relocation fields. Their shared
descriptors, renderers, owner/glue bodies and runtime-data text also match. The
same comparison passes for all41 heap/all4 value/all11 table units (38/2/10 linked).
Interpreter differs in30/53 IL units, consistent with this source policy target.

Hot function sizes are unchanged: run42,797 bytes; numeric2,260; call_value2,941;
load_frame2,824. All four move by +0x4e10 (19,984 bytes). Their mod64 entry positions
change respectively48->0,0->16,32->48,32->48. load_frame has identical raw linked
bytes; run19, numeric2 and call_value11 changed bytes are all existing relocation
fields. Their opcodes, registers, stack offsets, local branches, checks and loans
remain unchanged. Static full-function instruction/call counts are in
host-postflight.json and match both arms.

This rules out changed instructions within these VM function bodies as a source
of the measured difference. Address/layout differences are real; instruction
fetch, branch alignment or code-footprint effects remain possible inferences,
not established causal explanations. The comparison is not a dynamic trace and
does not isolate linker placement or whole-program cache effects.

compare-final.command.json records host status0 and exact script hash. Prior
host-parser attempts remain intact: unsupported relocation42, then an assumption
that every manifest function survived link garbage collection. Both were analysis
harness errors, with scripts and stderr preserved; no guest failure occurred.
The final owned16-file compiler prefix and committed qualification package were
rehash-checked unchanged after inspection; this postflight is explicitly current,
not a prospective full-prefix run-window receipt. No Guardian gate was invoked.
