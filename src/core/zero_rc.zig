//! Audited runtime ownership contracts. Unlisted helpers refuse.
const std = @import("std");
const ir = @import("ir.zig");
const rc_symbols = [_][]const u8{ "@myl_core_retain", "@myl_core_release", "@myl_core_share(", "@myl_core_free_block(" };

/// Runtime inputs borrow unless their bit is set. Managed results are either
/// independent owned storage or the consumed buffer, never a retained alias.
pub const Contract = struct { owned: u64 = 0, views: u64 = 0, result: enum { scalar, fresh, transferred, borrowed } = .scalar };

/// Text helpers that take their `str` arguments as borrowed `(data, length)` spans (C9): an owned
/// argument lends its octets (`emit_llvm`'s span arguments), a view argument needs no copy.
fn spanTextContract(symbol: []const u8) ?Contract {
    const spans = [_]struct { name: []const u8, contract: Contract }{
        .{ .name = "myl_core_ir_str_byte", .contract = .{ .views = 1 } },
        // A failing assert's compared values (F-18): two texts read in place, positions 3 and 7, before the trap.
        .{ .name = "myl_core_assert_operands", .contract = .{ .views = 0b1000_1000 } },
        .{ .name = "myl_core_str_concat", .contract = .{ .views = 3, .result = .fresh } },
        // The span forms of the read-only text tests (`build.spanRedirect`): both `str` arguments are spans.
        .{ .name = "myl_core_span_starts", .contract = .{ .views = 3 } },
        .{ .name = "myl_core_span_ends", .contract = .{ .views = 3 } },
        .{ .name = "myl_core_span_contains", .contract = .{ .views = 3 } },
        // Sentinel text results (C9 2b): the owner gives the result's family; a view passes the sentinel.
        .{ .name = "myl_core_text_case", .contract = .{ .views = 1, .result = .fresh } },
        .{ .name = "myl_core_text_replace", .contract = .{ .views = 7, .result = .fresh } },
        // The lines and the zero-padded copy of a text read its span in place (lane HC): a borrowed receiver needs no copy.
        .{ .name = "myl_core_text_splitlines", .contract = .{ .views = 1, .result = .fresh } },
        .{ .name = "myl_core_text_zfill", .contract = .{ .views = 1, .result = .fresh } },
        // Sentinel text results (C9 2b, batch 2b): the input's owner gives only the result's ASCII flag, a view passes the sentinel.
        .{ .name = "myl_core_text_trim_span", .contract = .{ .views = 3, .result = .fresh } },
        .{ .name = "myl_core_span_str_split_whitespace", .contract = .{ .views = 1, .result = .fresh } },
        .{ .name = "myl_core_ir_str_slice_bytes", .contract = .{ .views = 1, .result = .fresh } },
        .{ .name = "myl_core_str_slice_step", .contract = .{ .views = 1, .result = .fresh } },
        .{ .name = "myl_core_str_join", .contract = .{ .views = 1, .result = .fresh } },
        // The list-view form of a join (C9 lists): the separator and the parts are both borrowed spans.
        .{ .name = "myl_core_str_join_view", .contract = .{ .views = 3, .result = .fresh } },
        // The integers of a list view (C9 lists): the span forms of the list-to-octets conversions.
        .{ .name = "myl_core_span_bytes_valid_list", .contract = .{ .views = 1 } },
        .{ .name = "myl_core_span_bytes_from_list", .contract = .{ .views = 1, .result = .fresh } },
        .{ .name = "myl_core_span_buffer_from_list", .contract = .{ .views = 1, .result = .fresh } },
        .{ .name = "myl_core_str_split", .contract = .{ .views = 3, .result = .fresh } },
        // Sentinel helpers (C9 3a): a view passes `myl_core_text_no_cache`, an owner its block.
        .{ .name = "myl_core_str_find", .contract = .{ .views = 3 } },
        .{ .name = "myl_core_text_search", .contract = .{ .views = 3 } },
        // Explicit-owner lookups (C9 S1, `text_frame`): the owner is a borrowed block, the text a span (parameter 1,
        // and 3 for a needle). `xc_slice` returns a borrowed view of the span.
        .{ .name = "myl_core_xc_chars", .contract = .{ .views = 2 } },
        .{ .name = "myl_core_xc_index", .contract = .{ .views = 2 } },
        .{ .name = "myl_core_xc_slice", .contract = .{ .views = 2, .result = .borrowed } },
        .{ .name = "myl_core_xc_search", .contract = .{ .views = 10 } },
        // Span forms with no cached facts (C9 str, `build.span_redirects`): each text argument is a span.
        .{ .name = "myl_core_span_encode", .contract = .{ .views = 1, .result = .fresh } },
        .{ .name = "myl_core_span_find_byte", .contract = .{ .views = 3 } },
        .{ .name = "myl_core_span_octets_compare", .contract = .{ .views = 3 } },
        .{ .name = "myl_core_span_from_hex_valid", .contract = .{ .views = 1 } },
        .{ .name = "myl_core_span_from_hex", .contract = .{ .views = 1, .result = .fresh } },
        .{ .name = "myl_core_span_text_repr", .contract = .{ .views = 1, .result = .fresh } },
        .{ .name = "myl_core_span_text_every", .contract = .{ .views = 1 } },
        .{ .name = "myl_core_span_text_ord", .contract = .{ .views = 1 } },
        .{ .name = "myl_core_span_text_search_bytes", .contract = .{ .views = 3 } },
        .{ .name = "myl_core_span_file_access", .contract = .{ .views = 12, .result = .fresh } },
        .{ .name = "myl_core_span_file_method", .contract = .{ .views = 8, .result = .fresh } },
        .{ .name = "myl_core_span_durable_access", .contract = .{ .views = 12, .result = .fresh } },
        .{ .name = "myl_core_span_process_run", .contract = .{ .views = 2, .result = .fresh } },
        .{ .name = "myl_core_span_process_control", .contract = .{ .views = 2, .result = .fresh } },
        .{ .name = "myl_core_span_process_scripted", .contract = .{ .views = 1 } },
        .{ .name = "myl_core_span_environment_text", .contract = .{ .views = 2, .result = .fresh } },
        .{ .name = "myl_core_span_input_memory", .contract = .{ .views = 1 } },
        .{ .name = "myl_core_span_stream_write", .contract = .{ .views = 2 } },
        .{ .name = "myl_core_span_bytes_to_list", .contract = .{ .views = 1, .result = .fresh } },
        .{ .name = "myl_core_span_parse_int_range", .contract = .{ .views = 1 } },
        // The write of a borrowed span reads its octets: the owner is a block, the data a view (C9 bytes).
        .{ .name = "myl_core_span_resource_write", .contract = .{ .views = 2, .result = .fresh } },
        // Span forms of the bytes helpers (C9 bytes): a bytes view is read in place; the results are fresh or scalar.
        .{ .name = "myl_core_span_bytes_hex", .contract = .{ .views = 1, .result = .fresh } },
        .{ .name = "myl_core_span_bytes_blake3", .contract = .{ .views = 1, .result = .fresh } },
        .{ .name = "myl_core_span_bytes_sha256", .contract = .{ .views = 1, .result = .fresh } },
        .{ .name = "myl_core_span_bytes_trim", .contract = .{ .views = 3, .result = .fresh } },
        // The borrowed trims of a comparison or a length (CX-4): both operands are spans, and the result borrows the kept octets.
        .{ .name = "myl_core_span_text_trim_view", .contract = .{ .views = 3, .result = .borrowed } },
        .{ .name = "myl_core_span_bytes_trim_view", .contract = .{ .views = 3, .result = .borrowed } },
        // A slice of a borrowed bytes trim (lane HC): the octets in a range of a span, borrowed from it.
        .{ .name = "myl_core_span_bytes_slice_view", .contract = .{ .views = 1, .result = .borrowed } },
        .{ .name = "myl_core_span_bytes_search", .contract = .{ .views = 3 } },
        .{ .name = "myl_core_span_bytes_find", .contract = .{ .views = 3 } },
        .{ .name = "myl_core_span_bytes_find_any", .contract = .{ .views = 3 } },
        .{ .name = "myl_core_span_bytes_contains_value", .contract = .{ .views = 1 } },
        .{ .name = "myl_core_span_bytes_concat", .contract = .{ .views = 3, .result = .fresh } },
        .{ .name = "myl_core_span_bytes_utf8_count_range", .contract = .{ .views = 1 } },
        .{ .name = "myl_core_span_parse_float_range", .contract = .{ .views = 1 } },
        .{ .name = "myl_core_span_parse_f32_range", .contract = .{ .views = 1 } },
    };
    for (spans) |entry| if (std.mem.eql(u8, symbol, entry.name)) return entry.contract;
    return null;
}

/// The helpers whose `str` arguments are `(owner, data, length)` triples (C9 3a, 2b): the owner is the
/// argument's block when it is owned, and the static sentinel `myl_core_text_no_cache` for a borrowed view,
/// which carries no cached facts, so the helper reads the octets from `data`/`length` only. Their zero-RC
/// entries are `spanTextContract`'s.
pub fn ownerSpan(symbol: []const u8) bool {
    const owners = [_][]const u8{
        "myl_core_str_find",       "myl_core_text_search",        "myl_core_text_case",      "myl_core_text_replace",
        "myl_core_text_trim_span", "myl_core_ir_str_slice_bytes", "myl_core_str_slice_step", "myl_core_str_join",
        "myl_core_str_split",      "myl_core_text_splitlines",    "myl_core_text_zfill",
    };
    for (owners) |name| if (std.mem.eql(u8, symbol, name)) return true;
    return false;
}

/// Keep this list explicit: adding a helper requires auditing its complete path.
pub fn contract(symbol: []const u8) ?Contract {
    if (spanTextContract(symbol)) |span| return span;
    if (jsonContract(symbol)) |boundary| return boundary;
    if (registersContract(symbol)) |boundary| return boundary;
    return listedContract(symbol);
}

/// The simulated register bank's runtime (`build_registers.zig`, `runtime/core_registers.c`, MCU-B1): a `Registers`
/// is a scalar handle the runtime's bank table keeps until the process or the trial ends, and every other argument and
/// result is a scalar.
fn registersContract(symbol: []const u8) ?Contract {
    const names = [_][]const u8{
        "simulated",          "read8",                  "read16",                  "read32",             "write8",                   "write16",                "write32",
        "poke32",             "write_count",            "write_address",           "write_value",        "write_width",              "pin32",                  "start_core1",
        // The `cpu` operations (MCU-NOC1): the handle and a PRIMASK word in, nothing or a scalar out.
        "cpu_wait_for_event", "cpu_wait_for_interrupt", "cpu_send_event",          "cpu_barrier",        "cpu_breakpoint",           "cpu_interrupts_disable", "cpu_interrupts_set",
        "cpu_event_count",    "cpu_event_kind",         "cpu_event_writes_before", "cpu_interrupts_now", "cpu_write_interrupts_off",
    };
    const prefix = @import("build_registers.zig").runtime_prefix;
    if (!std.mem.startsWith(u8, symbol, prefix)) return null;
    // `script32` reads its list of values as a borrowed `(elements, count)` span and copies them into the bank (MCU-B1D).
    if (std.mem.eql(u8, symbol[prefix.len..], "script32")) return .{ .views = 0b100 };
    for (names) |name| if (std.mem.eql(u8, symbol[prefix.len..], name)) return .{};
    return null;
}

/// The derived JSON codec's runtime (`build_json.zig`, `runtime/core_json.c`): a handle is a `u64` the runtime owns, every
/// text argument a borrowed `(data, length)` span, and only the decoded text, the written document and the error's path
/// and sentence are fresh results.
fn jsonContract(symbol: []const u8) ?Contract {
    const prefix = "myl_core_json_";
    if (!std.mem.startsWith(u8, symbol, prefix)) return null;
    const entries = [_]struct { name: []const u8, contract: Contract }{
        .{ .name = "read", .contract = .{ .views = 1 } },
        .{ .name = "object", .contract = .{} },
        .{ .name = "member", .contract = .{ .views = 4 } },
        .{ .name = "close", .contract = .{ .views = 4 } },
        .{ .name = "invariant", .contract = .{ .views = 4 } },
        .{ .name = "array", .contract = .{} },
        .{ .name = "element", .contract = .{} },
        .{ .name = "case", .contract = .{ .views = 4 } },
        .{ .name = "case_value", .contract = .{} },
        .{ .name = "none", .contract = .{} },
        .{ .name = "i64", .contract = .{} },
        .{ .name = "u64", .contract = .{} },
        .{ .name = "f64", .contract = .{} },
        .{ .name = "f32", .contract = .{} },
        .{ .name = "bool", .contract = .{} },
        .{ .name = "str", .contract = .{ .result = .fresh } },
        .{ .name = "writer", .contract = .{} },
        .{ .name = "put_i64", .contract = .{} },
        .{ .name = "put_u64", .contract = .{} },
        .{ .name = "put_f64", .contract = .{} },
        .{ .name = "put_f32", .contract = .{} },
        .{ .name = "put_bool", .contract = .{} },
        .{ .name = "put_null", .contract = .{} },
        .{ .name = "put_str", .contract = .{ .views = 2 } },
        .{ .name = "put_key", .contract = .{ .views = 2 } },
        .{ .name = "put_case", .contract = .{ .views = 2 } },
        .{ .name = "begin_object", .contract = .{} },
        .{ .name = "end_object", .contract = .{} },
        .{ .name = "begin_array", .contract = .{} },
        .{ .name = "end_array", .contract = .{} },
        .{ .name = "written", .contract = .{ .result = .fresh } },
        .{ .name = "ok", .contract = .{} },
        .{ .name = "error_kind", .contract = .{} },
        .{ .name = "error_path", .contract = .{ .result = .fresh } },
        .{ .name = "error_offset", .contract = .{} },
        .{ .name = "error_message", .contract = .{ .result = .fresh } },
        .{ .name = "done", .contract = .{} },
    };
    for (entries) |entry| if (std.mem.eql(u8, symbol[prefix.len..], entry.name)) return entry.contract;
    return null;
}

fn listedContract(symbol: []const u8) ?Contract {
    if (transferContract(symbol)) |boundary| return boundary;
    if (@import("build_render.zig").generated(symbol)) |kind| {
        if (kind != .show) return .{};
        // A show of a list view borrows its `{data, count}` span (CX2): one view parameter, no owner.
        return .{ .result = .fresh, .views = if (@import("build_render.zig").borrowsListView(symbol)) 1 else 0 };
    }
    if (scopeContract(symbol)) |boundary| return boundary;
    if (formatContract(symbol)) |boundary| return boundary;
    if (providerContract(symbol)) |result| return result;
    // Trial transport keeps native FILE/path state, never a managed argument.
    // Register accepts only a compiler-generated static function pointer.
    const test_helpers = [_][]const u8{
        "myl_core_test_register",    "myl_core_test_open",        "myl_core_test_run",
        "myl_core_test_trace",       "myl_core_test_read",        "myl_core_test_write",
        "myl_core_test_compared",    "myl_core_test_read_bool",   "myl_core_test_write_bool",
        "myl_core_test_read_float",  "myl_core_test_write_float", "myl_core_test_write_text",
        "myl_core_test_limits",      "myl_core_test_tick",        "myl_core_test_ceilings",
        "myl_core_test_enter",       "myl_core_test_leave",       "myl_core_test_blocks",
        "myl_core_test_allocations",
    };
    for (test_helpers) |name| if (std.mem.eql(u8, symbol, name)) return .{};
    if (std.mem.eql(u8, symbol, "myl_core_test_read_text") or std.mem.eql(u8, symbol, "myl_core_test_read_bytes")) return .{ .result = .fresh };
    if (callableDigest(symbol) or std.mem.startsWith(u8, symbol, @import("emit_values.zig").copy_prefix)) return .{ .result = .fresh };
    if (std.mem.eql(u8, symbol, "myl_core_view_slice") or std.mem.eql(u8, symbol, "myl_core_view_slice_text")) return .{ .views = 1, .result = .borrowed };
    if (std.mem.eql(u8, symbol, "myl_core_text_trim_view")) return .{ .views = 1, .result = .borrowed };
    // Two borrowed spans compare their octets in place (`==` and `!=` of a piece, `build.spanEquality`).
    if (std.mem.eql(u8, symbol, "myl_core_span_eq")) return .{ .views = 3 };
    for ([_][]const u8{ "myl_core_view_chars", "myl_core_view_index", "myl_core_view_byte", "myl_core_span_bytes_index_offset", "myl_core_span_utf8_count" }) |name| {
        if (std.mem.eql(u8, symbol, name)) return .{ .views = 1 };
    }
    for ([_][]const u8{ "myl_core_view_char", "myl_core_view_copy_text", "myl_core_view_copy_bytes", "myl_core_span_decode_text" }) |name| {
        if (std.mem.eql(u8, symbol, name)) return .{ .views = 1, .result = .fresh };
    }
    const readers = [_][]const u8{
        "myl_core_owned_same_block",
        "myl_core_round_float",
        "myl_core_saturating_integer",
        "myl_core_parse_int_range",
        "myl_core_parse_float_range",
        "myl_core_parse_f32_range",
        "myl_core_text_bound",
        "myl_core_text_every",
        "myl_core_text_scalar_valid",
        "myl_core_text_search",
        "myl_core_text_search_bytes",
        "myl_core_bytes_search",
        "myl_core_bytes_find_any",
        "myl_core_bytes_utf8_count",
        "myl_core_bytes_utf8_count_range",
        "myl_core_from_hex_valid",
        "myl_core_str_chars",
        "myl_core_str_find",
        "myl_core_str_find_byte",
        "myl_core_str_offset",
        "myl_core_str_index_offset",
        "myl_core_text_ord",
        "myl_core_str_eq",
        "myl_core_octets_compare",
        "myl_core_str_contains",
        "myl_core_str_starts",
        "myl_core_str_ends",
        "myl_core_bytes_find",
        "myl_core_bytes_contains_value",
        "myl_core_bytes_valid_list",
        "myl_core_span_bytes_valid_list",
        "myl_core_buffer_range_valid",
        "myl_core_buffer_reserve_valid",
        "myl_core_buffer_capacity",
        "myl_core_bytes_index_offset",
        "myl_core_ir_str_byte",
        "myl_core_dict_ordinal",
        "myl_core_f64_bits",
        "myl_core_format_bool_print",
        // A plain format-string hole's direct paths (PY-FSTRING-1): a stream
        // write that reads only its scalar, or the length its spelling knows.
        "myl_core_print_i64",
        "myl_core_print_u64",
        "myl_core_print_i64_count",
        "myl_core_print_u64_count",
        "myl_core_print_bool",
        "myl_core_print_str",
        "myl_core_print_f64",
        "myl_core_print_f64_count",
    };
    for (readers) |name| if (std.mem.eql(u8, symbol, name)) return .{};
    const constructors = [_][]const u8{
        "myl_core_format_float",              "myl_core_format_number",
        "myl_core_format_float32",            "myl_core_text_case",
        "myl_core_text_trim",                 "myl_core_bytes_trim",
        "myl_core_text_replace",              "myl_core_text_chr",
        "myl_core_text_repr",                 "myl_core_text_format",
        "myl_core_bytes_decode_text",         "myl_core_bytes_hex",
        "myl_core_bytes_blake3",              "myl_core_from_hex",
        "myl_core_str_slice_step",            "myl_core_bytes_slice_step",
        "myl_core_str_join",                  "myl_core_str_split",
        "myl_core_str_join_view",             "myl_core_str_split_whitespace",
        "myl_core_span_str_split_whitespace", "myl_core_buffer_new",
        "myl_core_buffer_copy",               "myl_core_io_bytes_from_u8_list",
        "myl_core_environment_names",         "myl_core_environment_text",
        "myl_core_environment_raw",           "myl_core_external_read",
        "myl_core_file_access",               "myl_core_file_method",
        "myl_core_result_take_pointer",       "myl_core_owned_octets_copy",
        "myl_core_str_from_i64",              "myl_core_str_from_u64",
        "myl_core_str_from_f64",              "myl_core_str_from_f32",
        "myl_core_str_from_bool",             "myl_core_none_text",
        "myl_core_str_concat",                "myl_core_bytes_concat",
        "myl_core_bytes_slice",               "myl_core_buffer_from_list",
        "myl_core_span_buffer_from_list",     "myl_core_buffer_from_bytes",
        "myl_core_buffer_snapshot",           "myl_core_text_encode",
        "myl_core_bytes_from_list",           "myl_core_span_bytes_from_list",
        "myl_core_bytes_to_list",             "myl_core_ir_str_slice_bytes",
        "myl_core_str_reserve",               "myl_core_bytes_sha256",
        "myl_core_buffer_split",              "myl_core_buffer_slice",
    };
    for (constructors) |name| if (std.mem.eql(u8, symbol, name)) return .{ .result = .fresh };
    if (bufferSpanContract(symbol)) |boundary| return boundary;
    const mutations = [_][]const u8{
        "myl_core_buffer_push_checked",  "myl_core_buffer_append_checked",
        "myl_core_buffer_append_i64",    "myl_core_buffer_append_f64",
        "myl_core_buffer_append_octets",
        // The two fixed bool spellings appended the way a format-string hole is.
        "myl_core_format_bool_append",
        // A plain scalar hole's spelling, appended to the block the caller holds.
        "myl_core_str_append_i64",       "myl_core_str_append_u64",
        "myl_core_str_append_f64",
    };
    for (mutations) |name| if (std.mem.eql(u8, symbol, name)) return .{ .owned = 1, .result = .transferred };
    return null;
}

// The item marker writes only thread-local diagnostic context. Task entry
// saves/restores this context, including when a worker runs a nested map. The
// rest are group, scope and clock adapters that own or hand back one value.
fn scopeContract(symbol: []const u8) ?Contract {
    if (std.mem.eql(u8, symbol, "myl_core_task_item")) return .{};
    // The pool's size and the process's CPU count are scalars the runtime reads (`parallel.threads`, `parallel.cpus`).
    if (std.mem.eql(u8, symbol, "myl_core_threads") or std.mem.eql(u8, symbol, "myl_core_cpus")) return .{};
    if (std.mem.eql(u8, symbol, "myl_core_stream_text")) return .{ .result = .fresh };
    if (std.mem.eql(u8, symbol, "myl_core_stream_memory")) return .{};
    // An `Input` handle is a scalar: building one copies its borrowed octets, and each read answers a fresh value.
    if (std.mem.eql(u8, symbol, "myl_core_input_memory")) return .{};
    // A `Stop` handle is a scalar too (FR5b): listening, standing in and the flag's channel take and answer scalars.
    if (std.mem.eql(u8, symbol, "myl_core_stop_listen") or std.mem.eql(u8, symbol, "myl_core_stop_simulated") or std.mem.eql(u8, symbol, "myl_core_stop_control")) return .{};
    if (std.mem.eql(u8, symbol, "myl_core_input_read") or std.mem.eql(u8, symbol, "myl_core_input_read_exact") or std.mem.eql(u8, symbol, "myl_core_input_read_line")) return .{ .result = .fresh };
    if (std.mem.eql(u8, symbol, "myl_core_owned_group_end")) return .{ .owned = 1 };
    if (std.mem.eql(u8, symbol, "myl_core_group_open") or std.mem.eql(u8, symbol, "myl_core_owned_group_take")) return .{ .result = .fresh };
    if (std.mem.eql(u8, symbol, "myl_core_owned_file_scope_end") or std.mem.eql(u8, symbol, "myl_core_owned_cap_scope_end")) return .{ .owned = 1 };
    const scalar_stand_ins = [_][]const u8{ "myl_core_clock_advance", "myl_core_clock_monotonic", "myl_core_clock_sleep", "myl_core_stand_in_fail", "myl_core_host_check" };
    for (scalar_stand_ins) |name| if (std.mem.eql(u8, symbol, name)) return .{};
    // A capability is a scalar handle (5C): granting, standing in for and narrowing one answer a handle the runtime's
    // table keeps until the process or the trial ends, and borrow their byte inputs (the script, the pairs, the scope).
    const handles = [_][]const u8{
        "myl_core_cap_grant",    "myl_core_stand_in", "myl_core_environment_fixed", "myl_core_process_scripted",
        "myl_core_cap_restrict", "myl_core_cap_dir",  "myl_core_cap_host",          "myl_core_environment_only",
    };
    for (handles) |name| if (std.mem.eql(u8, symbol, name)) return .{};
    return null;
}

// A format-string hole renders into the caller's sink: measuring and printing
// read the value and the text span they are handed. Appending to a text block
// the caller reserved owns that block and answers it. The plain hole paths
// (PY-FSTRING-1) take the same shapes: a stream write or a measurement reads a
// borrowed span, and an append owns the block it fills.
fn formatContract(symbol: []const u8) ?Contract {
    if (std.mem.eql(u8, symbol, "myl_core_format_len")) return .{ .views = 1 << 3 };
    if (std.mem.eql(u8, symbol, "myl_core_format_print")) return .{ .views = 1 << 4 };
    if (std.mem.eql(u8, symbol, "myl_core_format_write")) return .{ .views = 1 << 4 };
    if (std.mem.eql(u8, symbol, "myl_core_format_append")) return .{ .owned = 1, .views = 1 << 4, .result = .transferred };
    // The text is the second parameter (after the stream): `print_view(stream, text)`.
    if (std.mem.eql(u8, symbol, "myl_core_print_view")) return .{ .views = 1 << 1 };
    if (std.mem.eql(u8, symbol, "myl_core_print_span_count")) return .{ .views = 1 << 1 };
    if (std.mem.eql(u8, symbol, "myl_core_format_octets_len")) return .{ .views = 1 };
    if (std.mem.eql(u8, symbol, "myl_core_format_octets_print")) return .{ .views = 1 << 1 };
    if (std.mem.eql(u8, symbol, "myl_core_format_octets_append")) return .{ .owned = 1, .views = 1 << 1, .result = .transferred };
    if (std.mem.eql(u8, symbol, "myl_core_str_append_bytes") or std.mem.eql(u8, symbol, "myl_core_str_append_ascii")) return .{ .owned = 1, .views = 1 << 1, .result = .transferred };
    return null;
}

fn bufferSpanContract(symbol: []const u8) ?Contract {
    if (std.mem.eql(u8, symbol, "myl_core_span_buffer_range_valid")) return .{ .views = 1 };
    if (std.mem.eql(u8, symbol, "myl_core_buffer_append_span_checked")) return .{ .views = 2, .owned = 1, .result = .transferred };
    return null;
}

fn transferContract(symbol: []const u8) ?Contract {
    if (std.mem.eql(u8, symbol, "myl_core_owned_list_rotate") or
        std.mem.eql(u8, symbol, "myl_core_owned_list_reverse")) return .{ .owned = 1, .result = .transferred };
    // The buffer helpers consume their receiver and return it changed (no copy; see core_bytes.c).
    if (std.mem.eql(u8, symbol, "myl_core_buffer_reserved") or std.mem.eql(u8, symbol, "myl_core_buffer_reverse") or
        std.mem.eql(u8, symbol, "myl_core_buffer_clear")) return .{ .owned = 1, .result = .transferred };
    if (std.mem.eql(u8, symbol, "myl_core_owned_sort_keyed") or std.mem.eql(u8, symbol, "myl_core_owned_sort_keyed_record")) return .{ .owned = 3, .result = .transferred };
    if (std.mem.eql(u8, symbol, "myl_core_owned_map")) return .{ .owned = 64, .result = .transferred };
    if (std.mem.eql(u8, symbol, "myl_core_owned_map_with")) return .{ .owned = 256, .result = .transferred };
    if (std.mem.eql(u8, symbol, "myl_core_owned_task_submit")) return .{ .owned = 4 };
    // E1b: the environment box is transferred; the group stays borrowed. The index is a scalar read back by `group_take`.
    if (std.mem.eql(u8, symbol, "myl_core_owned_task_submit_indexed")) return .{ .owned = 4 };
    // E1b: the thunk takes one environment slot out: the block it returns is owned by the thunk (the slot reads NULL after).
    if (std.mem.eql(u8, symbol, "myl_core_task_take")) return .{ .result = .transferred };
    return null;
}

// These adapters synchronously borrow every input. A completion either closes
// its native handle or leaves the owner available for the emitted failure move.
fn providerContract(symbol: []const u8) ?Contract {
    if (@import("aggregate_provider.zig").isMarker(symbol)) return .{};
    // Output boundaries accept only the scalar fd. They change TLS staging
    // depth and flush raw bytes under the stream lock, never managed values.
    const readers = [_][]const u8{
        "myl_core_output_begin",        "myl_core_output_end",   "myl_core_provider_keepalive",
        "myl_core_resource_complete",   "myl_core_stream_write", "myl_core_stream_write_bytes",
        "myl_core_stream_write_buffer", "myl_core_stream_flush",
    };
    for (readers) |name| if (std.mem.eql(u8, symbol, name)) return .{};
    const constructors = [_][]const u8{
        "myl_core_resource_acquire", "myl_core_resource_accept", "myl_core_resource_read",   "myl_core_resource_write",
        "myl_core_durable_access",   "myl_core_process_run",     "myl_core_process_control",
    };
    for (constructors) |name| if (std.mem.eql(u8, symbol, name)) return .{ .result = .fresh };
    return null;
}

// Prepared digest adapters accept only a scalar function pointer and return an
// immutable static string. Admit the generated schema hash, never an open prefix.
fn callableDigest(symbol: []const u8) bool {
    const prefix = @import("callable_digest_contract.zig").prefix;
    if (!std.mem.startsWith(u8, symbol, prefix) or symbol.len != prefix.len + 64) return false;
    for (symbol[prefix.len..]) |byte| {
        const digit = byte >= '0' and byte <= '9';
        const letter = byte >= 'a' and byte <= 'f';
        if (!digit and !letter) return false;
    }
    return true;
}

/// A final emitted-code guard supplements IR verification and runtime tripwires. A line is
/// unclean when it loads an atomic i32, stores an i32 with the `!tbaa !3` tag, or is a
/// declaration, definition or call that names a reference-count symbol. Each needle is
/// searched once over the whole text and the line around a hit is examined, not every
/// needle in every line: the per-line search built a search table for each of about ten
/// needles in each of a unit's many thousand lines, and that was a tenth of a test run's CPU.
pub fn emittedClean(text: []const u8) bool {
    if (std.mem.indexOf(u8, text, "load atomic i32") != null) return false;
    var from: usize = 0;
    while (std.mem.indexOfPos(u8, text, from, "store i32")) |at| {
        const line = lineAround(text, at);
        if (std.mem.indexOf(u8, line, "!tbaa !3") != null) return false;
        from = lineEnd(text, at);
    }
    // Every name starts with `@`, so one pass over the `@` signs finds every occurrence of every name. The verdict is
    // the same as one scan per name: an occurrence on a declaration or a call line decides it, whichever name it is.
    var sign: usize = 0;
    while (std.mem.indexOfScalarPos(u8, text, sign, '@')) |at| {
        sign = at + 1;
        for (rc_symbols) |name| {
            if (!std.mem.startsWith(u8, text[at..], name)) continue;
            const line = lineAround(text, at);
            const declaration = std.mem.startsWith(u8, line, "declare ") or std.mem.startsWith(u8, line, "define ");
            if (declaration or std.mem.indexOf(u8, line, "call ") != null) return false;
        }
    }
    return true;
}

/// The end of the line holding `at`: the index of its newline, or the end of the text.
fn lineEnd(text: []const u8, at: usize) usize {
    return std.mem.indexOfScalarPos(u8, text, at, '\n') orelse text.len;
}

/// The line of `text` holding the byte at `at`, without its newline.
fn lineAround(text: []const u8, at: usize) []const u8 {
    const start = if (std.mem.lastIndexOfScalar(u8, text[0..at], '\n')) |newline| newline + 1 else 0;
    return text[start..lineEnd(text, at)];
}

/// Native container copies duplicate only slots. Managed children require the
/// explicit recursive-copy helpers, never a residual ownership-pass COW copy.
pub fn shallowManagedCopy(module: *const ir.Module, inst: ir.Inst) bool {
    if (!module.valid(inst.ty)) return false;
    return switch (inst.op) {
        .list_copy => if (module.kind(inst.ty) == .list) module.managed(module.compound(inst.ty).list) else false,
        .dict_copy => if (module.kind(inst.ty) == .dict) blk: {
            const dict = module.compound(inst.ty).dict;
            break :blk module.managed(dict.key) or module.managed(dict.value);
        } else false,
        else => false,
    };
}
