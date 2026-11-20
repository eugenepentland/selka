# Stage 3f handoff: full guest corpus under value semantics

At stage 3d tip `f1265a0b`, run from the repository root:

```sh
export TMPDIR="$PWD/.tmp-stage3d" ZIG_LOCAL_CACHE_DIR="$PWD/.cache-stage3d"
scripts/build-slot.sh build -- ./zig-out/bin/mylang test tests/lang \
  --value-semantics --force --cache-dir .cache-stage3d/lang-switch --jobs 4
```

This ran all 114 guest programs: **595 passed, 20 failed, 4 dropped**. The same
corpus in the normal stage 3d gate passed **654/654** (29 fresh, 625 cached),
with no failures or drops. The full switch output is preserved at
`.tmp-stage3d/tests-lang-switch.log` in the stage 3d worktree. The switch run
is an inventory, not an acceptance claim for stage 3f. Do not loosen value
semantics to make old sharing assertions pass.

## Checker refusals (4 dropped programs)

| Program | First diagnostic | Migration action |
| --- | --- | --- |
| `builtin_context.my` | `E_MUTATION_MARKER` at 38:19 | Store the changed `xs` into `value.values`, or remove the unused `mut` marker. |
| `migrated/managed_cell.my` | `E_VALUE_CELL` at 4:20 | Intentional legacy Cell diagnostic input. Move it to a checker-only test when the default flips. |
| `python_collections.my` | `E_VALUE_TEMPORARY_WRITE` at 130:5 | Save the returned collection, mutate its element, then store it back. Preserve evaluation order. |
| `python_core.my` | `E_VALUE_TEMPORARY_WRITE` at 114:5 | Save the returned collection, mutate it, then store it back. Preserve evaluation order. |

## Guest failures (20 individual tests)

Eighteen tests still assert shared aliasing or mutate through a copy and need
source-level value/handle rewrites. These are not evidence that the old alias
contract should survive:

| Program | Failing tests (suffix after `test_`) | Observed failure |
| --- | --- | --- |
| `arena_managed` | `escape_preserves_a_cycle_through_a_record_field`; `escape_shares_objects_that_already_live_in_the_enclosing_region` | false; `R_LIST_BOUNDS` |
| `byte_buffer` | `a_buffer_alias_observes_appends_while_a_snapshot_does_not`; `buffers_are_traced_through_record_fields_lists_and_generics`; `growth_past_the_segment_threshold_keeps_every_octet` | false; old aliases and method receivers no longer write through |
| `dictionary_hashing` | `a_missed_read_never_shadows_a_key_inserted_before_the_write` | false |
| `field_augmented` | `augmented_addition_to_a_list_field_extends_in_place` | false |
| `keyed_sorting` | `sort_key_orders_in_place_and_keeps_equal_keys_in_input_order` | false |
| `managed_values` | `managed_dictionary_source_literals_indexing_1` | false |
| `surface_collections` | `list_methods_indexing_and_indexed_assignment` | `R_LIST_BOUNDS` |
| `option_narrowing` | `option_narrowing_collection_methods_and_index_writes` | `R_LIST_BOUNDS` |
| `option_niche` | `an_escaped_graph_keeps_its_optional_links` | false |
| `python_values` | `python_values_dictionary_literal_growing_aliases_and_arbitrary_method_receivers` | false |
| `scalable_sorting` | `in_place_sort_scales_and_preserves_aliases`; `text_sort_in_place_matches_sorted_through_aliases_and_fields` | false |
| `sets` | `a_set_is_shared_on_assignment_and_written_through_mut` | false |
| `stable_sorting` | `sort_orders_a_large_list_in_place_for_every_alias`; `text_sorts_in_place_through_every_alias` | false |

Two failures require separate performance/correctness investigation:

| Program and test | Failure | Current interpretation |
| --- | --- | --- |
| `gc_footprint::test_trees_built_across_minor_collections_keep_every_node` | `R_STEP_LIMIT` | COW/value tree work exceeded the existing step budget; inspect before changing the budget. |
| `recursive_values::test_deep_values_compare_hash_and_escape_without_recursion` | `OutOfMemory` | The stage 3b cycle-aware reachability fix at `54edf716` passes this test 1/1 under the switch in 0.51 s. That tip is not in stage 3d and must be included in stage 3f integration. |

## Embedded Zig-source follow-up

Zig unit/integration files still embed guest sources that explicitly expect
legacy sharing. Review at least `src/managed_lists_test.zig`,
`src/managed_frontend_test.zig`, `src/compiler_test.zig`,
`src/python_core_test.zig`, `src/array_places_test.zig`,
`src/io_print_test.zig`, `src/qbe_test.zig`, and `src/effects_test.zig`.
The class syntax in parser, type, ABI and intentional rejection tests remains
useful diagnostic input; classify each before deleting it. The velocity
suite's CPython oracle also needs explicit adaptation for list-alias idioms.
