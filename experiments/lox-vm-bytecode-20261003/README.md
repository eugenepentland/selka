# Checked bytecode storage experiment

The VM stores opcode and operand bytes in `list[u8]` instead of `list[int]`.
`Chunk.code` and `ExecFrame.code` change together. Byte producers use normal
checked `u8` conversions; the two jump patch writes retain their original
255 masks. Reads widen to `int` before arithmetic or dispatch. This follows
pinned Lox SPEC §8.1's byte storage, one-byte indices, and two-byte big-endian
jumps. The 37 opcodes, compilation algorithms, instruction order, runtime
checks, COW snapshots and Lox collector accounting remain intact.

The selected source candidate is `octets-shape-v3.patch`, relative to the exact
accepted combined84 source. Its additional scalar `opcode: u8` temporary
exposes a read-only field consumer to the existing compiler proof and removes
an extra owning `List<u8>` receiver copy. The checked read still precedes the
widening and IP increment. It adds no callback, allocation, cache or opcode.
The compiler is the unchanged selected d14a7040 binary with adjacent QBE99ad919d.
The separate proposed compiler byte-index guard has no role in these results.

## Variants and negative evidence

- `octets-v1.patch` reproduces the initial production source. It passes 348
  fresh tests in the separately extended `octets-qualified` test source and
  the bounded native matrix, but is rejected. Compiling a call with 256
  arguments diagnosed the Lox error and then trapped converting the discarded
  count to u8, changing status65 to status1. The original and build-slot replay
  failure receipts are preserved in the compressed archive and raw scratch.
  The first four direct diagnostic invocations preceded the build-slot replay;
  only the separate slot receipt is a wrapper-compliant replay.
- `octets-v2.patch` corrects all three direct/invoke/super argument-count
  emission sites with `bit_and(count,255)`. The unchanged argument parser has
  already reported counts over255. Valid counts retain their value; the failed
  chunk is discarded by the existing `NO_OBJ` path. No diagnostic or recovery
  parsing changes. The checked byte cast remains present.
- `octets-shape-v3.patch` adds only the scalar dispatch read to v2. V2 and V3
  sources, ELFs, public/native receipts and manifests remain separate.

`chunk.write_byte(int)` has the internal opcode/operand-byte contract 0..255.
Direct malformed API writes outside that range now raise the ordinary checked
cast trap. This is an API representation limit; it does not exempt malformed
Lox source from matching its original diagnostics. Constants, locals,
upvalues, closure pairs, jump and loop emitters were reviewed for this range.
The argument overflow recovery was fixed and compared explicitly.

## Qualification

Each corrected variant independently passed 352 fresh public executions:
88 exact discovered names on LLVM release RC, QBE ReleaseFast RC, and both
native tracing-GC stress configurations. Every configuration reports zero
cached, failed, skipped or dropped tests across10 programs. All accepted84
names remain, with four additions: byte-list COW snapshot/line preservation,
constant index255, multi-byte forward/backward jumps and argument overflow.
Directory invocations omit `--cases`; their provider is empty. The declared
Clock fixtures in `driver_cases.json` are preserved structurally and were not
executed by those directory receipts.

Each corrected variant also passed exact unaccounted native comparisons against
accepted combined84 controls on both engines and backends:

- 1192 bounded observations:424 RC,424 ordinary tracing GC,344 native GC stress,
  including ordinary and Lox collector stress modes;80 expensive native-GC
  stress smoke cells are explicitly unrun.
- 12 additional VM constant-index255 boundary pairs.
- 192 argument boundary/recovery pairs covering direct, invoke and super calls;
  trailing statements, nested valid clock calls and malformed comma recovery;
  and the valid255-argument/last-local-slot boundary. Both engines, backends,
  Lox stress modes and all three native modes compare exact status, stdout,
  diagnostics and abstract Lox GC statistics.
- Eight RC native-GC-stress requests compare exact checked refusals.

Native stress uses `MYLANG_OPTIONS=--gc-stress`; the guest `--gc-stress` argument
independently selects Lox collection stress. Before/after manifests cover all37
candidate/control files, compiler/QBE, actual RC/GC ELFs, runtime objects,
linked build manifests/receipts, helper, focused and pinned benchmark inputs.
No new compiler GC result is inferred from an old guest. V3 replay into a fresh
private source directory also reproduced all37 hashes exactly.

## Generated code diagnostics

`static-final.json` in the compressed receipts derives from exact accepted84
emission and `objdump` of actual ELFs. These are static instruction/call counts
for `vm::run`, not performance measurements:

| Source | LLVM instructions/calls | QBE instructions/calls |
| --- | ---: | ---: |
| accepted84 | 5586 /486 | 8606 /440 |
| v1 | 5710 /487 | 9070 /454 |
| corrected v2 | 5710 /487 | 9070 /454 |
| scalar-read v3 | 5605 /485 | 8606 /440 |

The initial QBE increase440→454 includes the owning byte-list receiver created
around `int(frame.code[frame.ip])`. In emitted IL, v3 removes that list take,
three RC status calls, one take-failure call and16 cleanup calls. The final
QBE dispatch drops464 static instructions and14 calls against v2. LLVM drops
105 instructions and2 calls. The widening is a plain scalar copy and adds no
cast trap. Read helper cast/bounds/overflow call counts remain unchanged.
`read_byte` and `read_short` still refuse the stride≥2 positive-index shortcut
for byte storage; their original negative normalization stays present. The
constant Value-pool read retains its existing certificate.

The historical `static-v1.json` helper comparison used unchanged helpers from
a separate constant-readonly diagnostic; its dispatch control was distinct.
The later exact control emission and `static-final.json` are the attribution
source. `shape-v3-static.json` is an initial diagnostic whose unused trap-site
keys searched different symbol spellings; use final named trap counts instead.
No lane performance runs or speed claims were made. Root owns selection after
central timing against the unchanged controls.

## Replay

Use the same private paths described in `sources.json`/`qualification.json`, or
set `--base` explicitly to a hash-identical accepted combined84 directory.
Reconstruct a fresh source:

```bash
python3 experiments/lox-vm-bytecode-20261003/reconstruct.py \
  --variant octets-shape-v3 \
  --output .tmp-lox-vm-bytecode-20261003/octets-shape-v3
mkdir -p .tmp-lox-vm-bytecode-20261003/{tmp,v3-gc/tmp,v3-native/tmp}
python3 experiments/lox-vm-bytecode-20261003/build.py octets-shape-v3
python3 experiments/lox-vm-bytecode-20261003/test-v2.py octets-shape-v3
python3 experiments/lox-vm-bytecode-20261003/build-gc-v3.py
scripts/build-slot.sh build python3 experiments/lox-vm-bytecode-20261003/validate-v3.py
```

`static.py` and `archive.py` additionally require the preserved v1/v2 sources
and receipts; they reconcile the complete experiment history. Replay in new
scratch or preserve the original scratch elsewhere; controllers
refuse to overwrite completed receipt files. Build/test controllers invoke
`build-slot.sh` internally with private caches/output/TMPDIR. Native validation
uses that wrapper for the whole matrix. Reserved CPUs2,3,10,11 were excluded.
`sources.json` records all source hashes; `qualification.json` records exact
builds, public names, counts and archive identity. `receipts.json.gz` stores
original JSON/stdout/stderr text and hashes, including rejected observations.
Raw sources, emissions, disassemblies and receipts remain in
`.tmp-lox-vm-bytecode-20261003`. Main, canonical migration and accepted84 source
were untouched. Guardian commit-gate outcomes are sent to root for its
consolidated feedback entry.
