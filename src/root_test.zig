//! Unit test entry point, separate from the production compiler module.
test {
    _ = @import("native_test_cli_test.zig");
    _ = @import("native_test_cases.zig");
    _ = @import("native_test_snapshot.zig");
    _ = @import("native_test_plan.zig");
    _ = @import("native_test_dependencies.zig");
    _ = @import("native_test_execute.zig");
    _ = @import("native_test_wire.zig");

    _ = @import("doc_coverage.zig");
    _ = @import("doc_coverage_command.zig");

    _ = @import("native_execute.zig");
    _ = @import("wiring/native_session.zig");
    _ = @import("qbe_build_test.zig");
    _ = @import("qbe_build.zig");
    _ = @import("qbe_build_cache.zig");
    _ = @import("qbe_build_host.zig");
    _ = @import("qbe_build_value.zig");
    _ = @import("qbe_build_options.zig");
    _ = @import("qbe_build_outputs.zig");
    _ = @import("qbe_build_io.zig");

    _ = @import("python_core_test.zig");
    _ = @import("python_calls_test.zig");
    _ = @import("python_syntax_test.zig");
    _ = @import("python_variants_test.zig");
    _ = @import("python_generics_test.zig");
    _ = @import("python_arrays_test.zig");
    _ = @import("python_assert_test.zig");
    _ = @import("python_strings_test.zig");
    _ = @import("python_format_test.zig");
    _ = @import("python_comprehension_test.zig");
    _ = @import("python_surface_test.zig");
    _ = @import("unit_test.zig");
    _ = @import("declarations_test.zig");
    _ = @import("vm_fusion_test.zig");
    _ = @import("stdlib_time_random_test.zig");
    _ = @import("stdlib_math_test.zig");
    _ = @import("stdlib_strings_test.zig");
    _ = @import("stdlib_sort_test.zig");
    _ = @import("stdlib_path_test.zig");
    _ = @import("stdlib_codecs_test.zig");
    _ = @import("stdlib_json_test.zig");
    _ = @import("stdlib_pool_test.zig");
    _ = @import("const_lengths_test.zig");
    _ = @import("source_evaluation_test.zig");
    _ = @import("callbacks_test.zig");
    _ = @import("vm_trace_test.zig");
    _ = @import("host_replay_test.zig");
    _ = @import("typed_holes_test.zig");
    _ = @import("allocation_budget_test.zig");
    _ = @import("float_operations_test.zig");
    _ = @import("integer_operations_test.zig");
    _ = @import("scoped_providers_test.zig");
    _ = @import("io_print_test.zig");
    _ = @import("io_files_test.zig");
    _ = @import("byte_literal_test.zig");
    _ = @import("nominal_provider_contracts_test.zig");
    _ = @import("nominal_environment_test.zig");
    _ = @import("generic_codecs_test.zig");
    _ = @import("nominal_providers_test.zig");
    _ = @import("nominal_instances_test.zig");
    _ = @import("nominal_bodies_test.zig");
    _ = @import("nominal_layouts_test.zig");
    _ = @import("nominal_templates_test.zig");
    _ = @import("nominal_type_syntax_test.zig");
    _ = @import("generic_arrays_test.zig");
    _ = @import("domain_equality_test.zig");
    _ = @import("host_functions_test.zig");
    _ = @import("vm_host_test.zig");
    _ = @import("host_declarations_test.zig");
    _ = @import("host_invocation_test.zig");
    _ = @import("diagnostic_output_test.zig");
    _ = @import("diagnostic_recovery_test.zig");
    _ = @import("generic_inference_test.zig");
    _ = @import("generic_execution_test.zig");
    _ = @import("generic_instances_test.zig");
    _ = @import("generic_calls_test.zig");
    _ = @import("generic_bodies_test.zig");
    _ = @import("generic_concrete_test.zig");
    _ = @import("generic_results_test.zig");
    _ = @import("generic_providers_test.zig");
    _ = @import("generic_requirements_test.zig");
    _ = @import("generic_syntax_test.zig");
    _ = @import("syntax_cache_test.zig");
    _ = @import("check_cache_test.zig");
    _ = @import("semantic_cache_test.zig");
    _ = @import("semantic_project_test.zig");
    _ = @import("import_policy_test.zig");
    _ = @import("source_map_test.zig");
    _ = @import("project_test.zig");
    _ = @import("interfaces_test.zig");
    _ = @import("compiler_test.zig");
    _ = @import("duplicates_test.zig");
    _ = @import("near_duplicates_test.zig");
    _ = @import("quality_test.zig");
    _ = @import("navigation_test.zig");
    _ = @import("generic_api_test.zig");
    _ = @import("syntax_cache_large_test.zig");
    _ = @import("structural_constraints_test.zig");
    _ = @import("formatter_test.zig");
    _ = @import("value_test.zig");
    _ = @import("records_test.zig");
    _ = @import("integers_test.zig");
    _ = @import("arrays_test.zig");
    _ = @import("domains_test.zig");
    _ = @import("variants_test.zig");
    _ = @import("tables_test.zig");
    _ = @import("arena_managed_test.zig");
    _ = @import("gc_regions.zig");
    _ = @import("effects_test.zig");
    _ = @import("evaluation_test.zig");
    _ = @import("input_manifest_test.zig");
    _ = @import("typed_json_test.zig");
    _ = @import("external_capabilities_test.zig");
    _ = @import("external_resources_test.zig");
    _ = @import("resource_source_test.zig");
    _ = @import("environment_test.zig");
    _ = @import("resource_io_test.zig");
    _ = @import("results_test.zig");
    _ = @import("propagation_test.zig");
    _ = @import("invocation_test.zig");
    _ = @import("domain_codecs_test.zig");
    _ = @import("codec_json_test.zig");
    _ = @import("call_json_test.zig");
    _ = @import("runtime_values_test.zig");
    _ = @import("gc_heap_test.zig");
    _ = @import("managed_values_test.zig");
    _ = @import("managed_bytes_test.zig");
    _ = @import("python_values_test.zig");
    _ = @import("python_bytes_test.zig");
    _ = @import("managed_lists_test.zig");
    _ = @import("python_collections_test.zig");
    _ = @import("managed_frontend_test.zig");
    _ = @import("surface_collections_test.zig");
    _ = @import("builtin_context_test.zig");
    _ = @import("json_document_test.zig");
    _ = @import("standard_library_test.zig");
    _ = @import("loop_exit_test.zig");
    _ = @import("constants_test.zig");
    _ = @import("for_range_test.zig");
    _ = @import("type_aliases_test.zig");
}
test {
    _ = @import("surface_statements_test.zig");
}
test {
    _ = @import("dotted_modules_test.zig");
}

test {
    _ = @import("qbe_test.zig");
    _ = @import("qbe_text_test.zig");
}

test {
    _ = @import("native_ir_test.zig");
    _ = @import("native_types_test.zig");
    _ = @import("native_format.zig");
    _ = @import("number_text.zig");
    _ = @import("number_text_test.zig");
    _ = @import("native_types.zig");
    _ = @import("native_descriptors.zig");
}

test {
    _ = @import("qbe_build_embed.zig");
    _ = @import("qbe_build_shapes.zig");
}

test {
    _ = @import("native_test_options.zig");
    _ = @import("native_test_receipts.zig");
}

test {
    _ = @import("c_abi_test.zig");
}
