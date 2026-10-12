//! Admitted runtime boundary for the zero-RC prototype. Unlisted helpers refuse.
const std = @import("std");
const ir = @import("ir.zig");
const rc_symbols = [_][]const u8{ "@myl_core_retain", "@myl_core_release", "@myl_core_share(", "@myl_core_free_block(" };

/// Keep common allocator templates, removing the legacy count initialization
/// and using the count-free header's kind offset.
pub fn fastPaths(a: std.mem.Allocator, source: []const u8) std.mem.Allocator.Error![]u8 {
    const uncounted = try std.mem.replaceOwned(u8, a, source, "  store i32 1, ptr %head, align 8, !tbaa !3\n", "");
    defer a.free(uncounted);
    return std.mem.replaceOwned(u8, a, uncounted, ", i64 4\n", ", i64 0\n");
}

/// Common declarations are not part of the owned ABI. Compact in place so this
/// does not allocate another copy of an emitted unit.
pub fn stripRcDeclarations(out: *std.ArrayList(u8)) void {
    var lines = std.mem.splitScalar(u8, out.items, '\n');
    var written: usize = 0;
    while (lines.next()) |line| {
        const forbidden = if (std.mem.startsWith(u8, line, "declare ")) for (rc_symbols) |name| {
            if (std.mem.indexOf(u8, line, name) != null) break true;
        } else false else false;
        if (forbidden) continue;
        std.mem.copyForwards(u8, out.items[written..][0..line.len], line);
        written += line.len;
        if (lines.index != null) {
            out.items[written] = '\n';
            written += 1;
        }
    }
    out.shrinkRetainingCapacity(written);
}

/// Runtime inputs borrow unless their bit is set. Managed results are either
/// independent owned storage or the consumed buffer, never a retained alias.
pub const Contract = struct { owned: u64 = 0, views: u64 = 0, result: enum { scalar, fresh, transferred, borrowed } = .scalar };

/// Keep this list explicit: adding a helper requires auditing its complete path.
pub fn contract(symbol: []const u8) ?Contract {
    if (transferContract(symbol)) |boundary| return boundary;
    if (@import("build_render.zig").generated(symbol)) |kind| return if (kind == .show) .{ .result = .fresh } else .{};
    // The item marker writes only thread-local diagnostic context. Task entry
    // saves/restores this context, including when a worker runs a nested map.
    if (std.mem.eql(u8, symbol, "myl_core_task_item")) return .{};
    if (std.mem.eql(u8, symbol, "myl_core_owned_group_end")) return .{ .owned = 1 };
    if (std.mem.eql(u8, symbol, "myl_core_group_open") or std.mem.eql(u8, symbol, "myl_core_owned_group_take")) return .{ .result = .fresh };
    if (std.mem.eql(u8, symbol, "myl_core_owned_file_scope_end") or std.mem.eql(u8, symbol, "myl_core_owned_cap_scope_end")) return .{ .owned = 1 };
    if (std.mem.eql(u8, symbol, "myl_core_clock_advance") or std.mem.eql(u8, symbol, "myl_core_host_check")) return .{};
    if (providerContract(symbol)) |result| return result;
    // Trial transport keeps native FILE/path state, never a managed argument.
    // Register accepts only a compiler-generated static function pointer.
    const test_helpers = [_][]const u8{
        "myl_core_test_register",    "myl_core_test_open",       "myl_core_test_run",
        "myl_core_test_trace",       "myl_core_test_read",       "myl_core_test_write",
        "myl_core_test_read_bool",   "myl_core_test_write_bool", "myl_core_test_read_float",
        "myl_core_test_write_float", "myl_core_test_write_text", "myl_core_test_limits",
        "myl_core_test_tick",        "myl_core_test_ceilings",   "myl_core_test_enter",
        "myl_core_test_leave",
    };
    for (test_helpers) |name| if (std.mem.eql(u8, symbol, name)) return .{};
    if (std.mem.eql(u8, symbol, "myl_core_test_read_text") or std.mem.eql(u8, symbol, "myl_core_test_read_bytes")) return .{ .result = .fresh };
    if (callableDigest(symbol) or std.mem.startsWith(u8, symbol, @import("emit_values.zig").copy_prefix)) return .{ .result = .fresh };
    if (std.mem.eql(u8, symbol, "myl_core_view_slice")) return .{ .views = 1, .result = .borrowed };
    for ([_][]const u8{ "myl_core_view_chars", "myl_core_view_index", "myl_core_view_byte" }) |name| {
        if (std.mem.eql(u8, symbol, name)) return .{ .views = 1 };
    }
    for ([_][]const u8{ "myl_core_view_char", "myl_core_view_copy_text", "myl_core_view_copy_bytes" }) |name| {
        if (std.mem.eql(u8, symbol, name)) return .{ .views = 1, .result = .fresh };
    }
    const readers = [_][]const u8{
        "myl_core_round_float",
        "myl_core_parse_int_range",
        "myl_core_parse_float_range",
        "myl_core_text_bound",
        "myl_core_text_every",
        "myl_core_text_scalar_valid",
        "myl_core_text_search",
        "myl_core_bytes_search",
        "myl_core_bytes_find_any",
        "myl_core_bytes_utf8_count",
        "myl_core_bytes_utf8_count_range",
        "myl_core_from_hex_valid",
        "myl_core_str_chars",
        "myl_core_str_find",
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
        "myl_core_buffer_range_valid",
        "myl_core_buffer_reserve_valid",
        "myl_core_buffer_capacity",
        "myl_core_bytes_index_offset",
        "myl_core_dict_ordinal",
    };
    for (readers) |name| if (std.mem.eql(u8, symbol, name)) return .{};
    const constructors = [_][]const u8{
        "myl_core_format_float",         "myl_core_format_number",
        "myl_core_text_case",            "myl_core_text_trim",
        "myl_core_bytes_trim",           "myl_core_text_replace",
        "myl_core_text_splitlines",      "myl_core_text_zfill",
        "myl_core_text_chr",             "myl_core_text_repr",
        "myl_core_text_format",          "myl_core_bytes_decode_text",
        "myl_core_bytes_hex",            "myl_core_from_hex",
        "myl_core_str_slice_step",       "myl_core_bytes_slice_step",
        "myl_core_str_join",             "myl_core_str_split",
        "myl_core_str_split_whitespace", "myl_core_buffer_new",
        "myl_core_buffer_copy",          "myl_core_cap_restrict",
        "myl_core_cap_dir",              "myl_core_cap_host",
        "myl_core_environment_only",     "myl_core_io_bytes_from_u8_list",
        "myl_core_environment_names",    "myl_core_environment_text",
        "myl_core_environment_raw",      "myl_core_cap_grant",
        "myl_core_stand_in",             "myl_core_environment_fixed",
        "myl_core_external_read",        "myl_core_file_access",
        "myl_core_file_method",          "myl_core_result_take_pointer",
        "myl_core_owned_octets_copy",    "myl_core_str_from_i64",
        "myl_core_str_from_u64",         "myl_core_str_from_f64",
        "myl_core_str_from_bool",        "myl_core_none_text",
        "myl_core_str_concat",           "myl_core_bytes_concat",
        "myl_core_bytes_slice",          "myl_core_buffer_from_list",
        "myl_core_buffer_from_bytes",    "myl_core_buffer_snapshot",
        "myl_core_buffer_reserved",      "myl_core_buffer_reverse",
        "myl_core_text_encode",          "myl_core_bytes_from_list",
        "myl_core_bytes_to_list",
    };
    for (constructors) |name| if (std.mem.eql(u8, symbol, name)) return .{ .result = .fresh };
    const mutations = [_][]const u8{
        "myl_core_buffer_push_checked", "myl_core_buffer_append_checked",
        "myl_core_buffer_append_i64",   "myl_core_buffer_append_f64",
    };
    for (mutations) |name| if (std.mem.eql(u8, symbol, name)) return .{ .owned = 1, .result = .transferred };
    return null;
}

fn transferContract(symbol: []const u8) ?Contract {
    if (std.mem.eql(u8, symbol, "myl_core_owned_list_rotate") or
        std.mem.eql(u8, symbol, "myl_core_owned_list_reverse")) return .{ .owned = 1, .result = .transferred };
    if (std.mem.eql(u8, symbol, "myl_core_owned_sort_keyed")) return .{ .owned = 3, .result = .transferred };
    if (std.mem.eql(u8, symbol, "myl_core_owned_map")) return .{ .owned = 64, .result = .transferred };
    if (std.mem.eql(u8, symbol, "myl_core_owned_task_submit")) return .{ .owned = 4 };
    return null;
}

// These adapters synchronously borrow every input. A completion either closes
// its native handle or leaves the owner available for the emitted failure move.
fn providerContract(symbol: []const u8) ?Contract {
    if (@import("aggregate_provider.zig").markerType(symbol) != null) return .{};
    const readers = [_][]const u8{ "myl_core_provider_keepalive", "myl_core_resource_complete", "myl_core_stream_write_bytes", "myl_core_stream_write_buffer" };
    for (readers) |name| if (std.mem.eql(u8, symbol, name)) return .{};
    const constructors = [_][]const u8{
        "myl_core_resource_acquire", "myl_core_resource_read",        "myl_core_resource_write",
        "myl_core_durable_access",   "myl_core_octets_repeat_signed", "myl_core_octets_repeat_unsigned",
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

/// A final emitted-code guard supplements IR verification and runtime tripwires.
pub fn emittedClean(text: []const u8) bool {
    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |line| {
        if (std.mem.indexOf(u8, line, "load atomic i32") != null) return false;
        if (std.mem.indexOf(u8, line, "store i32") != null and std.mem.indexOf(u8, line, "!tbaa !3") != null) return false;
        const declaration = std.mem.startsWith(u8, line, "declare ") or std.mem.startsWith(u8, line, "define ");
        if (!declaration and std.mem.indexOf(u8, line, "call ") == null) continue;
        for (rc_symbols) |name| {
            if (std.mem.indexOf(u8, line, name) != null) return false;
        }
    }
    return true;
}

/// Native container copies duplicate only slots. Managed children require the
/// explicit recursive-copy helpers, never a residual ownership-pass COW copy.
pub fn shallowManagedCopy(module: *const ir.Module, inst: ir.Inst) bool {
    if (!module.zero_rc or !module.valid(inst.ty)) return false;
    return switch (inst.op) {
        .list_copy => if (module.kind(inst.ty) == .list) module.managed(module.compound(inst.ty).list) else false,
        .dict_copy => if (module.kind(inst.ty) == .dict) blk: {
            const dict = module.compound(inst.ty).dict;
            break :blk module.managed(dict.key) or module.managed(dict.value);
        } else false,
        else => false,
    };
}
