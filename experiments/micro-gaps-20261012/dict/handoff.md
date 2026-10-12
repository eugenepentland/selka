# Dictionary update copy handoff

Implementation commit: `57cd3e115` (`Avoid owned string key copies on dictionary update hits`). Base: `399013af36d41b78610e5ede22a9102ec5b17ffe`. Branch: `codex/micro-gaps-20261012-dict`. The following evidence commit contains this handoff and receipts; its SHA is supplied in the agent handoff message.

Owned implementation files are `src/core/fuse_dict.zig` and `src/core/dict_test.zig`. No runtime C/helper/header changes or new test-root registration are required. Apply the two coordinator-owned hunks in `coordinator-required.patch`: trust the compiler-generated octet copy via `effectCall`, and invoke `fuse_dict.updateCopies` before probe folding in `lowering_finish`. These shared files remain uncommitted in this checkout.

The bounded local pass recognizes a trusted independent string copy from a list element when the copied key has only dictionary probe uses and one insertion with unmanaged values. Probes borrow the original immutable string. The independent copy executes immediately before insertion, followed by a fresh key-matched probe so the existing exact-SSA insertion verifier remains unchanged. Update hits allocate no copied key. Source mutation/replacement, observable calls, escaping uses, additional consuming uses, cyclic regions, and later probes retain the original copy. Managed-value dictionaries retain their original path. The original indexed source read and its bounds check remain in place. Owner lifetimes and cleanup are handled by the existing checked ownership pass.

Analysis falls back for functions above 4,096 instructions or 256 blocks, stops after 32 string-returning call candidates, and rejects region depth above 64. Copies that supply independent snapshots are not removed. There is no RC/COW fallback, new ownership syntax, escaping view, or benchmark-specific specialization. The miss path performs one additional lookup to preserve the existing verifier contract.

The original migrated source is unchanged, SHA256 `85f4031385261de61c57208a1ed38dbe65a5018f46338eeb16c675439fe49bec`. Both counted and uncounted release guests print `779967`, exit zero, and pass leak checking. No source-ergonomics variant was needed.

| Same-source checked arm | C0 | Candidate |
| --- | ---: | ---: |
| Allocations | 2,003,014 | 4,014 |
| Cumulative allocated bytes | 128,234,288 | 298,288 |
| Managed peak bytes | 152,720 | 152,656 |
| Managed exit-live bytes | 0 | 0 |
| RC events / uniqueness tests | 0 / 0 | 0 / 0 |

C0 migrated RC has 3,014 allocations and 234,288 cumulative bytes. The candidate's remaining 1,000 additional independent key allocations preserve insertion storage independence. `c0-counted.json` retains the frozen recorded controls; `candidate-counters.json` is the raw final counted run. `pre-match-counters.json` records an early host artifact whose LLVM still contained the loop copy, and is not a qualified final candidate.

`qualification.json` records exact compiler/guest/source/LLVM identities, final counters, native symbol results and every reused package file hash. The host uses default Debug, matching C0; guests use `--release --experimental-zero-rc`. The LLVM has exactly one octet-copy call, in miss block `b15`; hit block `b14` directly stores the scalar value. `ir-miss-block.txt` preserves that excerpt. `nm --defined-only` finds no known `myl_core_retain*`, `myl_core_release*` or `myl_core_unique*` symbols in the uninstrumented candidate. This narrow audit is separate from zero executed RC counters.

Final compiler: `/home/epentland/ai/canopy/mylang-micro-gaps-20261012-dict/.tmp/micro-gaps/dict/package/bin/mylang`, SHA256 `89863c690537fa80bef0cbd4b0773b9537f7ffb64838e66deac7024972b767c5`.

Final uncounted guest: `/home/epentland/ai/canopy/mylang-micro-gaps-20261012-dict/.tmp/micro-gaps/dict/bin/dict_count-final`, SHA256 `83f8396918bbf166629adad1c5e4c20855adfb07c4b9ed980d3c9b7859bae144`. Counted guest: same directory, `dict_count-final-count`, SHA256 `921e1b9059e81dd243481a4fb93e701b09609b4607e51dfe17f5126d765a7778`.

Four registered `gap_dict` tests pass: positive and seven conservative-refusal hand-IR cases; large-function budget fallback; native repeated inserts/hits, source replacement/clear, early return, and managed value replacement; and the exact original migrated source's verified raw insertion shape. Native tests run optimized and unoptimized with leak checking and zero-RC emitted-code checks. The standalone `gap_dict_updates.my` fixture additionally verifies an observation call before update. `qualification.log` retains outputs: both benchmark checksums, then `100 100`, `18`, `1`, `effect-1`, `9`.

Final build/qualification route (all under the shared build-slot admission, private TMPDIR/cache/output, pinned Zig, four jobs):

```sh
zig build core-test-binary seed-compiler -Dtest-filter=gap_dict --prefix "$PWD/.tmp/micro-gaps/dict/install" -j4
MYLANG_COMPONENT_DIR=/home/epentland/ai/canopy/mylang-memory-20261012/.tmp/lox-eda-20261012/gate-4034-install/libexec/mylang/components .tmp/micro-gaps/dict/install/focus/core-tests
# Copy the complete frozen installation; replace only its local bin/mylang
# with install/focus/mylang, keeping bin/libexec/tools together.
.tmp/micro-gaps/dict/package/bin/mylang build experiments/micro-ownership-20261012/parity/migrated/dict_count.my --release --experimental-zero-rc --counters --emit-llvm .tmp/micro-gaps/dict/dict_count-final.ll -o .tmp/micro-gaps/dict/bin/dict_count-final-count --cache-dir .tmp/micro-gaps/dict/guest-cache/final-count
MYLANG_COUNTERS="$PWD/experiments/micro-gaps-20261012/dict/candidate-counters.json" MYL_CORE_LEAKCHECK=1 .tmp/micro-gaps/dict/bin/dict_count-final-count
zig build guardian -- all . --gate --full
```

Guardian's final run passes all 88 checks (`guardian-final.log`); no feedback log was appended or committed. Ordinary `test-core` provisioning failed with the preexisting legacy seed's missing native-object bug, also reproduced in a private component cache. The focused route reused unchanged qualified frozen components, with matching hashes, and did not alter any seed or pin. The coordinator identified the prior green checked-owned pin/archive route for the integrated full gate.

No timing samples were collected here. Allocation reductions are measured; elapsed-time improvement awaits the coordinator's integrated paired timing and full verification gate. Expanded dictionary cases remain the coordinator's integration qualification responsibility.
