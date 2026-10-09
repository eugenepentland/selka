# WP-B3 QBE subtraction address selection — 2026-09-30

Source checkpoint `ae291a848bc2758310e25fef52456734bef4f008` starts from
`cfee0070`. The compiler is frozen under `.tmp/sub-address/compiler`:

- mylang SHA-256: `4d842721f801cc927a278ff68ff052080b5b209d4fbc301535b03539043c25df`.
- QBE SHA-256: `1cbf4f4850741c7a8a0ecfee5845082f46a6e6bc5b5f141ce702a66938aedc76`.

The approved QBE control is root's frozen `phase-b-targeted-combined` tool,
SHA-256 `6ccecf27cda0378f59d7dc60cee74a6558a7d25a0c88fb877b5755136f0500de`.
Compiler, QBE control/candidate and changed selector bytes were checked before
and after actual production compilation/execution. The compiler digest also
fixes its embedded runtime inputs. There is no runtime, frontend or LLVM edit.

## Trigger and change

The frozen prior Lox properties profile identified three ordinary COPY count
updates in `vm::load_frame`. Each executed 1,200,003 times and materialized
`payload - 32` separately for its load and store. The emitter already used one
SSA address; QBE's address numbering recognized constant addition but not this
subtraction. Removing saturation checks would change the ownership contract.

The amd64 selector now gives its private `Num` address representation the
equivalent negative constant only for a long temporary minus a nonnegative
integer constant at most 2147483648. The original instruction remains intact.
Displacement accumulation accepts only signed 32-bit intermediate offsets and
scales 1/2/4/8, checking bounds before arithmetic can overflow. Unsupported
parts retain their original temporaries. Existing use counting and instruction
selection preserve arithmetic users and live flags; there is no general SUB
rewrite and no change to LLVM prefix GEP/alias classification.

`QBE-SUB-ADDRESS-1` has an executable fixture and a reachable tagged Zig test.
Both unit and native-root test input declarations cover the fixture directory.

## Verification

Every build, executable oracle and guest run used `scripts/build-slot.sh`,
owned TMPDIR and owned local/global Zig caches. No timing or profiling run was
performed in this lane.

| Check | Result |
| --- | --- |
| Address oracle, control and candidate, UBSan | 323/323 each |
| Existing zero-branch oracle, both tools | 140/140 each |
| Full backend gate | 141/141 tests, 29/29 steps |
| Whole-tree Guardian | 88/88 checks |
| Formatting and test input coverage | 27/27 steps |
| Actual Lox properties / string equality | `20000` / `2000`, exit zero |

The address oracle covers load/store prefixes, scaled indexes, both signed
displacement boundaries, composed and scaled overflow fallback, negative,
dynamic and reversed subtraction, multiple users, word/float subtraction,
high bits, wrapping arithmetic and live SUB flags. The existing 140-case
selector regression also exercises register pressure and an external symbol
plus eight bytes after a comparison.

Root independently reviewed the source and replayed the supplied 323 cases
plus 784 new memory/alias/address cases: 14 signed offsets × 4 scales × 7
wide/wrapped indexes × 2 alias modes. Both tools passed 1107/1107 under UBSan.
Its receipt SHA-256 is
`00207cee8a81cdcee9eac9c07cd32caa9cb91bb6bdc4fa52b0d92ebbe0faa2a0`;
the retained receipt identifies the precise independent inputs and outputs.

One filtered run selected one named address test and twelve unnamed imports.
Its executable cases passed, but an assembly assertion expected commas without
spaces. The next run exposed a second assertion mistake: inherited selection
already used NEG+ADD for an unencodable large subtraction. Both failed logs
remain retained. A separate strict C link attempt rejected `-UNDEBUG` as unused
for the assembler input; the corrected oracle suppresses only that driver
warning. No production failure or coverage removal resulted.

## Actual production code shape

Identical actual Lox production IL was selected by both frozen QBE tools.
Counts below are static instructions in QBE's selected assembly, before any
assembler padding; they are not execution counts or timing estimates.

| Function | Control | Candidate | Removed |
| --- | ---: | ---: | ---: |
| `vm::load_frame` | 696 | 663 | 33: 15 MOVq and 18 SUBq |
| `vm::run` | 14933 | 14363 | 570: 260 MOVq, 309 SUBq and 1 MOVl |

Every compare, branch and call opcode count matches for each function. Each
of the three count updates now loads at `-32(payload)`, computes `old + 1`,
branches to refusal on zero and stores at `-32(payload)` only after admission.
Four generated loan-glue texts also match the prior frozen source byte for
byte. Its required count preflight, status return and transactional ordering
remain in place. The separately observed VM spill and argument-shuffle costs
are not claimed fixed by this change.

The root retains authority for dev/full corpus acceptance, caps, smoke
correctness and its final broad gate. This lane neither repeats that corpus
nor claims an accepted performance gain from static instruction counts.

## Attribution erratum

Root's original `.tmp/lox-qbe-attribution/report.md` called the
`myl_t_702a6d907b417100aec372fbe640be7c932b6dc514fc7e2a91fc18f6ebf00bd0`
loan a string loan. The frozen descriptor proves a 392-byte record with ten
direct fields; generated glue contains nineteen edge preflights, with seventeen
count acquisitions on the profiled path. Its field offsets match
`compiler.Parser`. The retained `compiler::current_chunk` IL associates that
392-byte argument and its release glue with the source's Parser parameter.
This is compiler/parser work, not a text payload operation. Observed routine
and instruction counts do not change.

`attribution-erratum/provenance.json` pins the original metadata, compiler
source, instruction JSON, report and raw archive. The extracted descriptor
SHA-256 is `1805669f234bc445a69b77f06192bc7fde32abc10a907fb5bf8053a8b11ff6cd`;
the glue SHA-256 is
`8c307cea83926443b1a4815a6888edb049eea0f48904f97adf13880667828ef1`.
The original report/archive remain untouched; this later interpretation alone
corrects the label. General aggregate admission must retain preflight of all
edges before any count update, including repeated aliases; reusing cached
count values for aliased edges would lose increments.

Evidence lives in `experiments/wp-b3-layout-20260929/sub-address/receipt.json`,
including command receipts, source/tool hashes, original failed logs, both
executable oracle assemblies, production IL/assembly/output and the metadata
erratum. Scratch binaries and installed prefix remain frozen in this worktree.
Centralized Guardian feedback was committed in `guardian-zig` as
`214d0cc016bf287dd84fc55c5715abd145244a54`, recording the smooth checks and
the explicitly counted unnamed imports. No waiver or baseline changed.
