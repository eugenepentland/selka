# Borrowed byte index forwarding

Source checkpoint: `33eb654785f1f41951d825ec4caf3de470aaf0ed`, based on actual main `1994cb76e266080d971be6f41e98fba5707234dd`.

The existing final-analysis pass now recognizes only the exact compiler-authorized runtime-C span normalizer: `myl_core_span_bytes_index_offset`, return u64, parameters str/i64, views=1, consumes=0, owned=0. Forwarding requires checked ownership, a str_view receiver, an i64 raw operand proven nonnegative, and a complete use set consisting only of u8 list_get reads of the same receiver with ordinary flags. The original byte-read bounds checks remain. Unknown and negative indices retain normalization. The public owned adapter remains separate because its emitter uses a pointer/header ABI.

Span analysis is limited to 32 candidates and 4096 instructions; existing owned-byte forwarding remains available beyond that limit. No pipeline rescheduling, declarations, runtime changes, or benchmark-source changes were made. prepareOptimizer already performs encode borrowing before final byte-index analysis.

Qualification: eight focused tests pass, including exact ABI/mask/symbol negatives, escaping/extra uses, different receivers, negative/unknown operands, span-only analysis bounds, and identical uncached/cold/warm LLVM with actual final-stage cache hits. Seven native modes cover default, unoptimized, optimize-debug, release, release/no-facts, verify-facts, and release/verify-facts. Unicode, extreme signed indices, empty source, and ordered located bounds traps pass. Empty-source index zero exercises the actually forwarded literal index path. Guardian passes all 88 checks. Initial Guardian repeated-string findings were resolved by factoring test literals; no feedback file was changed.

Build command, after sourcing the dev environment:

```sh
scripts/build-slot.sh build "$ZIG" build seed-compiler core-test-binary -Dtest-filter='byte index' -p .tmp/text-gaps/span-index/host -j"$MYLANG_DEV_JOBS" --maxrss "$MYLANG_DEV_MAXRSS"
```

Tests reuse frozen components from `/home/epentland/ai/canopy/mylang-text-gaps-main-20261012/.tmp/text-gaps/coordinator/common-001/install/libexec/mylang/components` via MYLANG_COMPONENT_DIR. No seeds or provisioning inputs were changed. Literal-only final rebuild used core-test-binary; tests.log and guardian.log preserve final results.

The retained release guest was built under admission using the private host, the same frozen component environment, `--release --experimental-zero-rc --cache-dir .tmp/text-gaps/span-index/proof-cache --emit-llvm .tmp/text-gaps/span-index/proof.ll`, from the unique fixture. readers.ll shows no normalizer in walk or at_zero; unknown-signed at retains it. native-main.asm shows direct byte loads in the scan and one normalizer call in the unknown-index branch. This establishes generated-code behavior, not a timing claim. BENCH will qualify integrated performance.

SHA256 identities:

| Artifact | SHA256 |
| --- | --- |
| private host focus/mylang | dc55ca95be8ac4e18ed9e852c1fb695519281e9b63025a408833ea72759006da |
| retained proof-native | e7ac1ae36a008ed168986d1c060719c26571db96adc49b0bbae39d6444c73f5f |
| full proof.ll | c9dca17ec50650a213fc27c7a47689e7d7cbe21bbb828885d001a329cd23aa2f |
| byte_index.zig | cdcfee8f17497a17547bf5f50a98f2ca4bd18b5cf708097260ace920c0f41684 |
| native source fixture | 8dd7bbeaa05549f683a140464a9ae52a0334ccf610c21cad41c090b1c6802128 |
