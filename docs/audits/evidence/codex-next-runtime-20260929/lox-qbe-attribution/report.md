# Frozen QBE Lox attribution

Read-only comparison of approved A5 `m17-codex` against composed source
`255cf730604cb6023ad5701165a100358d9c0cfe`. Both symbol-preserving counterparts
match every allocated ELF section of the copied originals, including addresses,
flags, sizes and payloads. Compiler/input/binary hashes are verified again after
all executions. All four guest runs exit zero and each control/candidate pair
has identical output. Slot-admitted Callgrind uses CPU 6 and owned tools/cache;
no reserved timing CPU, Guardian, source edit or quantitative acceptance claim.

| Dev case | Simulated control | Simulated candidate | Delta |
| --- | ---: | ---: | ---: |
| properties | 3,116,015,790 | 3,148,951,293 | +32,935,503 (1.057%) |
| string_equality | 2,638,272,336 | 2,667,024,077 | +28,751,741 (1.090%) |

Properties is dominated by `vm::load_frame` (+10,800,027), Value loan glue
(+9,600,008) and a second aggregate loan (+8,400,630). String equality is
dominated by `vm::run` (+24,200,305), string loan (+5,762,880) and retain
(+4,473,515), partly offset by other routines. These are exact self instruction
deltas, not unique source-change attribution. VM MIN/MAX constant load counts
are identical across each pair: 4,960,043 for properties and 8,976,005 for
string equality. String VM MOV instructions add 30,032,152 while XCHG counts
fall 7,655,985; XCHG can include real register swaps, so those counts are not
labelled padding. Per-address data and complete disassembly are preserved.

QBE manifests have no function-name entries. `semantic-name-map.json` uses
verified same-source companion LLVM manifests, matching exact symbol names;
unknown native/glue/anonymous symbols retain their actual names. No guest code
or benchmark input was modified. Package-local Valgrind is a copied previously
verified tool, version 3.26.0; it was not installed system-wide.

Callgrind emulation/library redirection changes absolute totals and allocator
behavior. The original root hardware measurements remain authoritative:
properties +1.058405% and string_equality +1.451761% at dev. The simulated
string delta differs from that hardware delta; these profiles do not replace
it. No actionable source correction or inliner/alias causality is claimed by
this routine-level receipt. Final composed corpus acceptance remains required.
