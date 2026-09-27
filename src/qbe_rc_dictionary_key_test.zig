//! Anchored immutable keys compose with a retained dictionary write boundary.
const std = @import("std");
const compiler = @import("compiler.zig");
const runtime = @import("runtime_mode.zig");
const t = std.testing;
const Manifest = struct { functions: []const struct { name: []const u8, il: []const u8 } };
const marker = "# RC-DICTIONARY-KEY-1";

// spec: RC-DICTIONARY-KEY-1
test "RC dictionary key admits exact benchmark and preserves real iterator holds" {
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(.rc);
    const source = try std.Io.Dir.cwd().readFileAlloc(t.io, "bench/parity/micro/dict_count.my", t.allocator, .limited(65536));
    defer t.allocator.free(source);
    var compilation = try compiler.Compilation.init(t.allocator, "dict_count.my", source);
    defer compilation.deinit();
    const text = try compilation.emitQbe(t.allocator);
    defer t.allocator.free(text);
    var result = try std.json.parseFromSlice(Manifest, t.allocator, text, .{ .allocate = .alloc_always, .ignore_unknown_fields = true });
    defer result.deinit();
    const il = try body(result.value, "main");
    try t.expectEqual(@as(usize, 2), std.mem.count(u8, il, marker));
    try t.expectEqual(@as(usize, 1), std.mem.count(u8, il, "# RC-DICTIONARY-TAIL-1"));
    try t.expect(std.mem.indexOf(u8, il, "call $myl_rc_hold_acquire") != null);
    try t.expect(std.mem.indexOf(u8, il, "call $myl_qbe_rc_frame_enter") != null);
    try t.expect(std.mem.indexOf(u8, il, "call $myl_native_dictionary_write") != null);
}
fn body(manifest: Manifest, name: []const u8) ![]const u8 {
    for (manifest.functions) |function| if (std.mem.eql(u8, function.name, name)) return function.il;
    return error.TestUnexpectedResult;
}

fn fixture() !std.json.Parsed(Manifest) {
    const library = try std.Io.Dir.cwd().readFileAlloc(t.io, "tests/lang/rc_dictionary_keys.my", t.allocator, .limited(65536));
    defer t.allocator.free(library);
    const source = try std.fmt.allocPrint(t.allocator, "{s}\ndef main() -> int:\n    return 0\n", .{library});
    defer t.allocator.free(source);
    var compilation = try compiler.Compilation.init(t.allocator, "dictionary_keys.my", source);
    defer compilation.deinit();
    const text = try compilation.emitQbe(t.allocator);
    defer t.allocator.free(text);
    return std.json.parseFromSlice(Manifest, t.allocator, text, .{ .allocate = .alloc_always, .ignore_unknown_fields = true });
}
// spec-case: RC-DICTIONARY-KEY-1
test "RC dictionary key whole-local lifetime and role controls" {
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(.rc);
    var result = try fixture();
    defer result.deinit();
    const Case = struct { name: []const u8, markers: usize };
    for ([_]Case{
        .{ .name = "test_repeated_negative_index_keys_and_real_iterator", .markers = 2 },
        .{ .name = "test_view_backed_keys_survive_dictionary_growth", .markers = 2 },
        .{ .name = "test_preexisting_list_and_dictionary_snapshots", .markers = 2 },
        .{ .name = "inherited_work", .markers = 2 },
        .{ .name = "test_rhs_callback_keeps_original_named_key", .markers = 0 },
        .{ .name = "test_later_key_use_keeps_ordinary_publication", .markers = 0 },
        .{ .name = "test_string_iterator_role_is_not_elided", .markers = 0 },
        .{ .name = "parameter_work", .markers = 0 },
        .{ .name = "test_user_loop_binding_is_not_an_ordinary_home_proof", .markers = 0 },
        .{ .name = "test_rebound_source_and_empty_loop_keep_fallback", .markers = 0 },
        .{ .name = "test_preowned_key_reassigned_on_loop_backedges", .markers = 0 },
    }) |case| try t.expectEqual(case.markers, std.mem.count(u8, try body(result.value, case.name), marker));
}

// spec-case: RC-DICTIONARY-KEY-1
test "RC dictionary key rejects implicit writers and middle CFG entries" {
    const bytecode = @import("bytecode.zig");
    const proof = @import("rc_dictionary_key.zig");
    const span: @import("source.zig").Span = .{ .start = 0, .end = 0 };
    var code = [_]bytecode.Instruction{
        .{ .span = span, .op = .push_unit },
        .{ .span = span, .op = .{ .store_local = @fromBackingInt(0) } },
        .{ .span = span, .op = .{ .load_local = @fromBackingInt(0) } },
        .{ .span = span, .op = .{ .store_local = @fromBackingInt(1) } },
        .{ .span = span, .op = .{ .jump_if_false = 5 } },
        .{ .span = span, .op = .push_unit },
        .{ .span = span, .op = .{ .jump = 2 } },
    };
    const key: @import("rc_dictionary_tail.zig").Key = .{
        .anchor = .{ .storage = @fromBackingInt(0) },
        .receiver = 1,
        .capture = 3,
        .projection = 5,
    };
    try t.expect(proof.flow(&code, key, 1, 5));
    code[6].op = .{ .jump = 3 };
    try t.expect(!proof.flow(&code, key, 1, 5));
    code[6].op = .{ .jump = 5 };
    try t.expect(!proof.flow(&code, key, 1, 5));
    code[6].op = .{ .drop_local = @fromBackingInt(0) };
    try t.expectEqual(@as(?usize, null), proof.definition(&code, 0));
    code[6].op = .{ .switch_variant = .{ .ty = .unit, .arms = &.{.{ .target = 2, .slot = @fromBackingInt(1) }} } };
    try t.expectEqual(@as(?usize, null), proof.definition(&code, 1));
}
