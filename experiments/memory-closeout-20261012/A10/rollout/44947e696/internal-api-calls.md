# Internal Core call sites

Source revision: `44947e6967d8eb0deeaa86b25ca2bb44bc58803d`. This is inventory, not qualification.

| File | Calls | Required migration review |
| --- | ---: | --- |
| `src/core/a01_native_driver_test.zig` | 2 | link/runtime ABI derives from emitted marker and dependencies |
| `src/core/a01_parallel_map_test.zig` | 1 | explicit owned ABI request; source validation audited separately |
| `src/core/a03_migration_boundaries_test.zig` | 2 | explicit owned ABI request; source validation audited separately; shared helper inherits build.Input or supplied ir.Module, not pipeline default |
| `src/core/a04_render_test.zig` | 5 | emission inherits supplied ir.Module ABI; shared helper inherits build.Input or supplied ir.Module, not pipeline default |
| `src/core/a04_slice_lifetime_test.zig` | 1 | explicit owned ABI request; source validation audited separately |
| `src/core/a06_nested_write_test.zig` | 2 | shared helper inherits build.Input or supplied ir.Module, not pipeline default |
| `src/core/a08_borrow_cache_test.zig` | 6 | emission inherits supplied ir.Module ABI; explicit owned ABI request; source validation audited separately; forwarded build.Input; inspect producer |
| `src/core/a08_provider_cache_test.zig` | 3 | forwarded build.Input; inspect producer; shared helper inherits build.Input or supplied ir.Module, not pipeline default |
| `src/core/a08_zero_rc_test.zig` | 2 | explicit owned ABI request; source validation audited separately; shared helper inherits build.Input or supplied ir.Module, not pipeline default |
| `src/core/a09_version_test.zig` | 4 | shared helper inherits build.Input or supplied ir.Module, not pipeline default |
| `src/core/allocation_contract.zig` | 1 | forwarded ABI expression |
| `src/core/backend_owned_test.zig` | 3 | forwarded build.Input; inspect producer; pipeline options and supplied module must agree |
| `src/core/build_test.zig` | 8 | shared helper inherits build.Input or supplied ir.Module, not pipeline default |
| `src/core/byte_index_test.zig` | 8 | emission inherits supplied ir.Module ABI; shared helper inherits build.Input or supplied ir.Module, not pipeline default |
| `src/core/cap_test.zig` | 4 | implicit build.Input defaults via wrapper; shared helper inherits build.Input or supplied ir.Module, not pipeline default |
| `src/core/ce2_effects_test.zig` | 18 | shared helper inherits build.Input or supplied ir.Module, not pipeline default |
| `src/core/ce2_results_test.zig` | 26 | shared helper inherits build.Input or supplied ir.Module, not pipeline default |
| `src/core/ce_lists_test.zig` | 2 | emission inherits supplied ir.Module ABI; explicit owned ABI request; source validation audited separately |
| `src/core/ce_records_test.zig` | 16 | shared helper inherits build.Input or supplied ir.Module, not pipeline default |
| `src/core/cli.zig` | 1 | pipeline options and supplied module must agree |
| `src/core/consume_test.zig` | 3 | shared helper inherits build.Input or supplied ir.Module, not pipeline default |
| `src/core/cost_command.zig` | 5 | forwarded build.Input; inspect producer; pipeline options and supplied module must agree |
| `src/core/cost_query_test.zig` | 3 | shared helper inherits build.Input or supplied ir.Module, not pipeline default |
| `src/core/cost_test.zig` | 3 | implicit build.Input defaults via wrapper; shared helper inherits build.Input or supplied ir.Module, not pipeline default |
| `src/core/count_test.zig` | 4 | emission inherits supplied ir.Module ABI; shared helper inherits build.Input or supplied ir.Module, not pipeline default |
| `src/core/demand_build_test.zig` | 5 | emission inherits supplied ir.Module ABI; inline build.Input omits mode defaults |
| `src/core/destination_test.zig` | 9 | shared helper inherits build.Input or supplied ir.Module, not pipeline default |
| `src/core/dict_test.zig` | 4 | shared helper inherits build.Input or supplied ir.Module, not pipeline default |
| `src/core/driver_handles_test.zig` | 8 | link/runtime ABI derives from emitted marker and dependencies; shared helper inherits build.Input or supplied ir.Module, not pipeline default |
| `src/core/driver_native_cache_test.zig` | 2 | link/runtime ABI derives from emitted marker and dependencies |
| `src/core/driver_test.zig` | 7 | link/runtime ABI derives from emitted marker and dependencies |
| `src/core/durable_test.zig` | 1 | shared helper inherits build.Input or supplied ir.Module, not pipeline default |
| `src/core/emit_llvm.zig` | 2 | emission inherits supplied ir.Module ABI |
| `src/core/emit_llvm_test.zig` | 9 | emission inherits supplied ir.Module ABI; shared helper inherits build.Input or supplied ir.Module, not pipeline default |
| `src/core/emit_text_split_test.zig` | 1 | shared helper inherits build.Input or supplied ir.Module, not pipeline default |
| `src/core/emit_units.zig` | 6 | emission inherits supplied ir.Module ABI |
| `src/core/emit_units_test.zig` | 40 | emission inherits supplied ir.Module ABI; implicit build.Input defaults via wrapper; link/runtime ABI derives from emitted marker and dependencies; shared helper inherits build.Input or supplied ir.Module, not pipeline default |
| `src/core/f1_facts_test.zig` | 8 | shared helper inherits build.Input or supplied ir.Module, not pipeline default |
| `src/core/f2_index_test.zig` | 10 | shared helper inherits build.Input or supplied ir.Module, not pipeline default |
| `src/core/facts_test.zig` | 10 | shared helper inherits build.Input or supplied ir.Module, not pipeline default |
| `src/core/function_build_test.zig` | 8 | shared helper inherits build.Input or supplied ir.Module, not pipeline default |
| `src/core/fuse_text_scalar_test.zig` | 3 | shared helper inherits build.Input or supplied ir.Module, not pipeline default |
| `src/core/inline_origins_test.zig` | 10 | shared helper inherits build.Input or supplied ir.Module, not pipeline default |
| `src/core/lowering_cache_test.zig` | 19 | emission inherits supplied ir.Module ABI; forwarded build.Input; inspect producer; inline build.Input omits mode defaults |
| `src/core/main.zig` | 3 | forwarded ABI expression; pipeline options and supplied module must agree |
| `src/core/optimization_cache_test.zig` | 29 | emission inherits supplied ir.Module ABI; shared helper inherits build.Input or supplied ir.Module, not pipeline default |
| `src/core/own_test.zig` | 31 | shared helper inherits build.Input or supplied ir.Module, not pipeline default |
| `src/core/owned_payload_test.zig` | 1 | shared helper inherits build.Input or supplied ir.Module, not pipeline default |
| `src/core/owned_record_test.zig` | 2 | explicit owned ABI request; source validation audited separately; shared helper inherits build.Input or supplied ir.Module, not pipeline default |
| `src/core/phi_cleanup_test.zig` | 1 | shared helper inherits build.Input or supplied ir.Module, not pipeline default |
| `src/core/pipeline.zig` | 6 | emission inherits supplied ir.Module ABI; forwarded build.Input; inspect producer; link/runtime ABI derives from emitted marker and dependencies |
| `src/core/pipeline_emission_test.zig` | 4 | implicit build.Input defaults via wrapper; link/runtime ABI derives from emitted marker and dependencies; pipeline options and supplied module must agree |
| `src/core/provider_store_test.zig` | 1 | explicit owned ABI request; source validation audited separately |
| `src/core/r_runtime_test.zig` | 4 | shared helper inherits build.Input or supplied ir.Module, not pipeline default |
| `src/core/row_cow_test.zig` | 4 | shared helper inherits build.Input or supplied ir.Module, not pipeline default |
| `src/core/runtime_threads_test.zig` | 2 | shared helper inherits build.Input or supplied ir.Module, not pipeline default |
| `src/core/s1_views_test.zig` | 7 | shared helper inherits build.Input or supplied ir.Module, not pipeline default |
| `src/core/s2_ir_test.zig` | 7 | shared helper inherits build.Input or supplied ir.Module, not pipeline default |
| `src/core/s2_views_test.zig` | 2 | shared helper inherits build.Input or supplied ir.Module, not pipeline default |
| `src/core/s3_ir_test.zig` | 3 | shared helper inherits build.Input or supplied ir.Module, not pipeline default |
| `src/core/s3_numeric_test.zig` | 2 | shared helper inherits build.Input or supplied ir.Module, not pipeline default |
| `src/core/s3_values_test.zig` | 3 | emission inherits supplied ir.Module ABI; shared helper inherits build.Input or supplied ir.Module, not pipeline default |
| `src/core/shared_counts_test.zig` | 4 | shared helper inherits build.Input or supplied ir.Module, not pipeline default |
| `src/core/single_owner_test.zig` | 2 | inline build.Input omits mode defaults; shared helper inherits build.Input or supplied ir.Module, not pipeline default |
| `src/core/task_ir_test.zig` | 3 | emission inherits supplied ir.Module ABI; link/runtime ABI derives from emitted marker and dependencies |
| `src/core/test_runner.zig` | 5 | forwarded build.Input; inspect producer |
| `src/core/test_runner_affected.zig` | 1 | forwarded build.Input; inspect producer |
| `src/core/test_runner_facts_test.zig` | 2 | forwarded build.Input; inspect producer; implicit build.Input defaults via wrapper |
| `src/core/test_runner_portable.zig` | 1 | forwarded ABI expression |
| `src/core/test_runner_test.zig` | 2 | emission inherits supplied ir.Module ABI; implicit build.Input defaults via wrapper |
| `src/core/test_support.zig` | 8 | emission inherits supplied ir.Module ABI; implicit build.Input defaults via wrapper; link/runtime ABI derives from emitted marker and dependencies |
| `src/core/text_test.zig` | 6 | shared helper inherits build.Input or supplied ir.Module, not pipeline default |
| `src/core/trace_test.zig` | 4 | shared helper inherits build.Input or supplied ir.Module, not pipeline default |
| `src/core/u1_state_test.zig` | 3 | shared helper inherits build.Input or supplied ir.Module, not pipeline default |
| `src/core/u2_test.zig` | 4 | shared helper inherits build.Input or supplied ir.Module, not pipeline default |
| `src/core/value_build_test.zig` | 28 | shared helper inherits build.Input or supplied ir.Module, not pipeline default |
| `src/core/value_emit_test.zig` | 4 | shared helper inherits build.Input or supplied ir.Module, not pipeline default |
| `src/core/value_facts_test.zig` | 12 | shared helper inherits build.Input or supplied ir.Module, not pipeline default |
| `src/core/values_test.zig` | 7 | shared helper inherits build.Input or supplied ir.Module, not pipeline default |
| `src/core/vector_test.zig` | 17 | shared helper inherits build.Input or supplied ir.Module, not pipeline default |
| `src/core/verify_ir_test.zig` | 1 | shared helper inherits build.Input or supplied ir.Module, not pipeline default |
| `src/core/zero_rc_cache_test.zig` | 3 | emission inherits supplied ir.Module ABI; forwarded build.Input; inspect producer |
| `src/core/zero_rc_task_test.zig` | 4 | emission inherits supplied ir.Module ABI; explicit owned ABI request; source validation audited separately; link/runtime ABI derives from emitted marker and dependencies |
| `src/core/zero_rc_test.zig` | 14 | explicit owned ABI request; source validation audited separately; inline build.Input omits mode defaults; shared helper inherits build.Input or supplied ir.Module, not pipeline default |
