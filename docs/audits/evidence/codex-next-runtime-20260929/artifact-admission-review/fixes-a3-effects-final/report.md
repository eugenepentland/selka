# Independent explicit-effects declaration review

Frozen module correction `a3fb19fcf8bbe59ee72266a7fce96093b52d8b84` applied after96b05480/9789436d in the owned review tree based on root3fe434c9. Final normalization source exactly matchesa3fb19fc. **14 passed,0 skipped,0 failed**, from a fresh direct test execution through the build slot; no timing/broad gate/Guardian/shared source edits.

The original8 cases remain green: payload/blob rejection, duplicate type/ABI declarations, forged ID proof refusal, normalized valid duplicates, and declared mutation negative/equal positive. Six new cases test host effect conflicts, C ABI effect conflicts, explicit allowed-effect conflicts plus explicit-vs-omitted bounds, matching host effects with source-span/body-local differences, matching C ABI effects with inferred-body differences, and matching explicit bound with different spans/ordinary inferred effects. Each negative rejects both orders and against the original declaration. Each positive accepts both orders and against the original; host/C ABI effects and explicit bound values remain in the restored declaration.

Normalization now retains explicit policy.effect_bound including its allowed mask; codec erases source spans. It retains policy.effects forhost orC ABI functions and projects onlyordinary inferred effects. Declared mutation, parameter types/count/constant arguments and other ABI policy fields remain retained. The tested source-local/inferred differences still accept. No remaining actionable declaration-normalization defect was found within these cases.

The original fixture SHA163bbc43... and all originalfailed logs are unchanged. Intermediate7-case failure and978 eight-pass receipt remain frozen in separate directories. This supplementary receipt does not modify or expand the older receipt's claim.

Command: `scripts/build-slot.sh build zig test src/review_runtime_contracts.zig --test-filter 'review:' --cache-dir .tmp/review-local`, owned TMPDIR/global cache. Standalone tests did not exercise Guardian. This is module-admission review only, independent of native count/prefix width; combined lane/gate/performance acceptance remains with parent.
