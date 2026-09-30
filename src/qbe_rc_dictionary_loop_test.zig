//! Fresh dictionary loop checks preserve fallback ownership and source traps.
const std = @import("std");
const compiler = @import("compiler.zig");
const runtime = @import("runtime_mode.zig");
const t = std.testing;
const Manifest = struct { functions: []const struct { name: []const u8, il: []const u8 } };

fn emitted(path: []const u8, add_main: bool) !std.json.Parsed(Manifest) {
    const library = try std.Io.Dir.cwd().readFileAlloc(t.io, path, t.allocator, .limited(65536));
    defer t.allocator.free(library);
    const source = try std.fmt.allocPrint(t.allocator, "{s}{s}", .{ library, if (add_main) "\ndef main() -> int:\n    return 0\n" else "" });
    defer t.allocator.free(source);
    var compilation = try compiler.Compilation.init(t.allocator, "dictionary_loops.my", source);
    defer compilation.deinit();
    const text = try compilation.emitQbe(t.allocator);
    defer t.allocator.free(text);
    return std.json.parseFromSlice(Manifest, t.allocator, text, .{ .allocate = .alloc_always, .ignore_unknown_fields = true });
}
fn body(manifest: Manifest, name: []const u8) ![]const u8 {
    for (manifest.functions) |function| if (std.mem.eql(u8, function.name, name)) return function.il;
    return error.TestUnexpectedResult;
}
// spec: RC-DICTIONARY-TEXT-LOOP-1
test "RC dictionary loop hoists owning immutable text work without erasing key journals" {
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(.rc);
    var result = try emitted("tests/lang/rc_dictionary_text_loops.my", true);
    defer result.deinit();
    const il = try body(result.value, "frequencies");
    const entry = std.mem.indexOf(u8, il, "\n@ce") orelse return error.TestUnexpectedResult;
    try t.expectEqual(@as(usize, 1), std.mem.count(u8, il[entry..], "call $myl_qbe_rc_unique_local"));
    const slice = std.mem.indexOf(u8, il, "call $myl_native_text_slice") orelse return error.TestUnexpectedResult;
    const tail = std.mem.indexOf(u8, il, "# RC-DICTIONARY-TAIL-1") orelse return error.TestUnexpectedResult;
    try t.expect(std.mem.indexOf(u8, il[slice..tail], "# RC-GLUE-1 retain") != null);
    try t.expect(std.mem.indexOf(u8, il[slice..tail], "@rcslotdrop") != null);
    try t.expect(std.mem.indexOf(u8, il, "# RC-DICTIONARY-EMPTY-DROPS-1") == null);
    try t.expect(std.mem.indexOf(u8, il, "@fi") == null);
    for ([_][]const u8{ "published", "exposed" }) |name|
        try t.expect(std.mem.indexOf(u8, try body(result.value, name), "\n@ce") == null);
    var benchmark = try emitted("bench/parity/suite/knucleotide.my", false);
    defer benchmark.deinit();
    try t.expect(std.mem.indexOf(u8, try body(benchmark.value, "frequencies"), "\n@ce") != null);
}
// spec: RC-DICTIONARY-LOOP-1
test "RC dictionary loop only hoists direct fresh unexposed roots" {
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(.rc);
    var result = try emitted("tests/lang/rc_dictionary_loops.my", true);
    defer result.deinit();
    const il = try body(result.value, "fresh");
    try t.expectEqual(@as(usize, 1), std.mem.count(u8, il, "\n@ce"));
    const entry = std.mem.indexOf(u8, il, "\n@ce") orelse return error.TestUnexpectedResult;
    try t.expectEqual(@as(usize, 1), std.mem.count(u8, il[entry..], "call $myl_qbe_rc_unique_local"));
    try t.expectEqual(@as(usize, 1), std.mem.count(u8, il, "# RC-DICTIONARY-TAIL-1"));
    try t.expectEqual(@as(usize, 2), std.mem.count(u8, il, "# RC-DICTIONARY-KEY-1"));
    try t.expect(std.mem.indexOf(u8, il, "# rc-frame") != null);
    try t.expect(std.mem.indexOf(u8, il, "call $myl_native_dictionary_write") != null);
    try t.expect(std.mem.indexOf(u8, il, "@fi") == null);
    try t.expectEqual(@as(usize, 5), std.mem.count(u8, il, "# RC-DICTIONARY-EMPTY-DROPS-1"));
    for ([_][]const u8{ "shared_empty", "during", "calls", "rebound", "enclosing" }) |name|
        try t.expectEqual(@as(usize, 0), std.mem.count(u8, try body(result.value, name), "\n@ce"));
}

// spec: RC-DICTIONARY-EMPTY-DROPS-1
test "RC dictionary empty drops retain exact benchmark setup later H iteration and journal layout" {
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(.rc);
    var result = try emitted("bench/parity/micro/dict_count.my", false);
    defer result.deinit();
    const il = try body(result.value, "main");
    try t.expectEqual(@as(usize, 5), std.mem.count(u8, il, "# RC-DICTIONARY-EMPTY-DROPS-1"));
    try t.expect(std.mem.indexOf(u8, il, "# rc-frame 13\n") != null);
    const entry = std.mem.indexOf(u8, il, "\n@ce") orelse return error.TestUnexpectedResult;
    const last = std.mem.lastIndexOf(u8, il, "# RC-DICTIONARY-EMPTY-DROPS-1") orelse return error.TestUnexpectedResult;
    try t.expect(std.mem.indexOf(u8, il[0..entry], "@rcslotdrop") != null);
    try t.expect(std.mem.indexOf(u8, il[last..], "# RC-GLUE-1 hold") != null);
    try t.expect(std.mem.indexOf(u8, il[last..], "@rcslotdrop") != null);
}
