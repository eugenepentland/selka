# List optimization oracle migration — review, not qualification

A09 owns `ce_lists_test.zig` by coordinator reservation. The existing optimized
fixtures preserve outputs, trap locations, element writes and cleanup. Their
source migrations are owned by A02 (`ce_appends`) and A06 (`ce_cow`,
`ce_elements`). No release denominator may lose those fixtures.

The current IR helpers (`support.ownedText`, `support.llvmText`) build the legacy
ownership mode internally regardless of the command default. Merely changing CLI
flags or deleting assertions would not qualify checked ownership. A converted
helper must call eager `single_owner.checkMode`, build with both `single_owner`
and `zero_rc`, run the selected pipeline, verify source/IR ownership and then
render the result. A07 owns the shared ownership implementation; A09 can keep the
small renderer local to its reserved test file.

| Existing check | Required owned replacement |
| --- | --- |
| `field_stores` one in-place field store | Keep exact `list_set_field` counts and absence of whole-element get/set; copy borrowed replacement `s` explicitly and make `before` independent when retained across mutation. |
| `whole_store` old child destruction | Keep one whole-element write, original children destroyed once, stored borrowed parameter copied explicitly; migrate reused `f` and `frame` source owners. |
| `ce_cow` uniqueness-test/list-copy equality | Assert no uniqueness/retain operations and no legacy RC LLVM symbols; Core `release` remains the required direct destruction operation in a checked module. Identify each intentional source `.copy()` and reject additional intermediate container copies. Exact counts depend on A06's final admitted migration. |
| `snapshot_then_store` old-value independence | Keep independent explicit copy and unchanged output; do not claim a compiler-only reduction if source-copy semantics changed. |
| `call_value` one retained match payload | Freeze independent selected-object snapshot before mutating `rt`; ensure no owner borrow crosses mutation and no whole runtime-list copy occurs. Count only the source-required object copy. |
| `big_part` one retained wide element | Copy the selected element before a mutating call and assert selected-child copies/direct cleanup, not a retained memory count. |
| `ce_cow` three exact output lines and leak check | Preserve unchanged outputs and successful cleanup across debug/release/verified modes; extend affected zero-RC matrix. |
| `ce_appends` memory-budget trap | A02 source moves the append from 60:17 to 62:17; update only once that exact source is integrated, preserving error/index budget and output. |

No production/test retirement is applied by this review. A06's final `ce_cow`
source is still pending admission, so no new exact IR count is invented here.
