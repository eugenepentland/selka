# Independent guarded byte-index review

Isolated compiler commit `ee1f99f0aacb842872527c28652b129f0da55b03` passes this
proof review with the qualification limits below. No actionable compiler defect
was found. The compiler remains unselected; this review changes only its own
experiment and runs no builds, units, public/native guests or performance tests.

`review.json` SHA256 is
`d246268f8e48bbe1f40159eb9782565932f11bbb345cc49e688e0e61a82a94b2`.
All 14 committed files and the four qualified compiler/SPEC hashes match.
The original canonical normalizer, quietness checks and CFG entry checks are
unchanged. The certificate still rejects reference/caller storage, pending
captures, COW work, hidden releases, managed/live-view elements, extra incoming
edges, step accounting and both versioned/original loop bodies. Its only new
one-byte admission is a native non-boxed `list[u8]`; bytes, bool, zero-sized
leaves and writes remain outside that admission.

For bytes, unsigned `length <= I64_MAX` precedes unsigned `index < length`.
Together they prove `0 <= signed_index < length`; a negative signed index's
unsigned encoding is at least 2^63. The independent 30-case admission algebra
covers zero, I64_MAX, 2^63, larger lengths, minimum/maximum indices and -1.
Either guard failure targets the unchanged normalizer start. A huge length
therefore causes **fallback, not a new trap**: a nonnegative canonical read
still skips length-to-i64 conversion; only the original negative branch checks
that cast. No huge object was allocated or assumed to trap.

Before these guards, lowering loads the already captured owner/index and the
header length. `markObject` emits alias metadata comments, not a runtime
ownership callback. Element storage/address calculation and payload loading
remain after both guards. The unchanged original read's result-slot clearing
runs on the successful path. The source uses the same owner, canonical u8 load,
snapshot lifetime, fallback casts/overflow/bounds diagnostics and original
receiver/capture/quiet/CFG restrictions. The expected fallback and diagnostic
behavior has focused and native evidence; this is not a proof of every malformed
ABI or internal native trace.

Frozen compiler `f89c339c…` and adjacent QBE `99ad919d…` match all four newly built
LLVM/QBE RC/GC source-v3 guests, their native manifests/receipts and actual runtime
objects. Checked LLVM O3/full LTO and checked QBE commands remain distinct from
the separate SSA emission command that drops step/frame checks. The installed
QBE `4f650da7…` is preserved and explicitly distinguished from the pinned guest
tool. Focused units use the separate built focus tool.

The 41-file compressed archive matches its raw hashes and private originals.
Final focused qualification passes 22 tests. Public qualification has 88 actual
names on each of four configurations: **352 executed passes**, zero cached,
failed, skipped or dropped results. These directory commands omit `--cases`
and retain step accounting, so they do not exercise the new fast path. Driver
provider fixtures are structurally preserved; no new provider execution claim
is added. The exact LLVM release/QBE ReleaseFast command modes are retained.

Unaccounted native coverage is **1,396 exact pairs**: 1,192 bounded observations
(424 RC, 424 ordinary GC, 344 native GC stress), 12 operand-255 pairs and 192
argument-limit/recovery pairs. Every actual command selects the newly built
candidate ELF, including both actual GC guests. Full status/stdout/stderr match
the source-v3 control, including Lox collector statistics. Eight checked RC
native-stress refusals are separate from successful programs. **80 native-GC
stress smoke cells remain unrun**. All source/proof/tool/ELF/runtime/input hashes
remain unchanged. These guests do not qualify a composition with the newer
selected AST source.

The broad unit history is deliberately split. The original command exited 1:
2,461/2,485 passed, 24 tests failed through missing focus-tool paths and one
failure path leaked. Its failed names belong to five modules. After the private
install-layout symlink correction, the affected-module replay exits 0 with
60/60 passes (48 declared named tests plus 12 unnamed blocks), covering every
prior failure and reporting no leak. This is not a single full-suite green
rerun. The first bad bytes-result fixture and first Guardian
`test-no-conditional` rejection remain historical; final proof/test hashes and
the subsequent qualified build are used for acceptance evidence.

`static-coverage.json` SHA256 is
`ec40e402f7dc345d753b12a542705a405f27677bfae0ce9554e2c01717932ff5`.
It independently enumerates all 106 bounded case identities from 13 benchmark
scripts, 23 error cases per engine and 17 regression fixtures, and verifies
all 1,192 executed input bytes. It also recounts saved assembly: the declared
common read-byte path grows **21 → 26 instructions**. Both standalone compare
result-width variants have **70 instructions**; their SSA differs only in one
`=w culel` → `=l culel` result width. The connected path follows the stated
nonnegative/in-bounds assumptions and saved branch choices, not a measured
trace. No second compiler was built or qualified. The width experiment supplies
no static improvement, and neither diagnostic supports a speed claim.

Whole-function assembly counts remain explicitly author diagnostic receipts;
this review reads saved common-path/width assembly without new disassembly.
The extra guard's static cost makes its performance value doubtful. Dynamic
measurement and selection belong to root. No current canonical/main source,
sealed archive or Guardian feedback file was changed, and Rust/Go parity is
not established.

Reproduce both host-only checks with fresh output paths:

```bash
taskset -c 16 python3 -B experiments/lox-byte-positive-independent-review-20261003/review.py \
  --lane /home/epentland/ai/canopy/mylang-worktrees/codex-lox-byte-positive-20261003 \
  --out .tmp-lox-round3-review-20261003/recheck-byte-proof.json
taskset -c 16 python3 -B experiments/lox-byte-positive-independent-review-20261003/static-coverage.py \
  --lane /home/epentland/ai/canopy/mylang-worktrees/codex-lox-byte-positive-20261003 \
  --out .tmp-lox-round3-review-20261003/recheck-byte-static.json
```

The commit hook runs Guardian for these review files. Root consolidates its
feedback together with the preserved initial test/build friction.
