//! Plain field publication must preserve its exact caller-slot commit boundary.
const std = @import("std");
const compiler = @import("compiler.zig");
const runtime = @import("runtime_mode.zig");
const t = std.testing;
const Manifest = struct { functions: []const struct { name: []const u8, il: []const u8 } };
const marker = "# RC-PLAIN-RECORD-WRITE-1";
const source =
    \\record State:
    \\    items: list[int]
    \\    count: int
    \\def increment(state: mut State, times: int):
    \\    i = 0
    \\    while i < times:
    \\        state.count = state.count + 1
    \\        i += 1
    \\def local_value(state: State) -> State:
    \\    state.count = state.count + 1
    \\    return state
    \\def managed_field(state: mut State, values: list[int]):
    \\    state.items = values
    \\record Held:
    \\    view: DictValues[int, int]
    \\    count: int
    \\def held_field(state: mut Held):
    \\    state.count = state.count + 1
    \\record ResourceState:
    \\    file: TextFile
    \\    count: int
    \\def unique_field(state: mut ResourceState):
    \\    state.count = state.count + 1
    \\def main() -> int:
    \\    state = State([7], 0)
    \\    increment(mut state, 3)
    \\    return state.count
;
fn emitted(steps: bool) !std.json.Parsed(Manifest) {
    var compilation = try compiler.Compilation.init(t.allocator, "plain_record_write.my", source);
    defer compilation.deinit();
    const text = try compilation.emitQbeWithOptions(t.allocator, .{ .step_checks = steps });
    defer t.allocator.free(text);
    return std.json.parseFromSlice(Manifest, t.allocator, text, .{ .ignore_unknown_fields = true, .allocate = .alloc_always });
}
fn body(manifest: Manifest, name: []const u8) ![]const u8 {
    for (manifest.functions) |function| if (std.mem.eql(u8, function.name, name)) return function.il;
    return error.TestUnexpectedResult;
}

// spec: RC-PLAIN-RECORD-WRITE-1
test "RC-PLAIN-RECORD-WRITE-1 exact counter loop leaves managed siblings untouched" {
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(.rc);
    var result = try emitted(false);
    defer result.deinit();
    const il = try body(result.value, "increment");
    try t.expectEqual(@as(usize, 1), std.mem.count(u8, il, marker));
    try t.expect(std.mem.indexOf(u8, il, "call $myl_rc_native_loan") == null);
    try t.expect(std.mem.indexOf(u8, il, "call $myl_rc_native_retain") == null);
    try t.expect(std.mem.indexOf(u8, il, "call $myl_rc_native_drop") == null);
    try t.expect(std.mem.indexOf(u8, il, "call $myl_qbe_fail_overflow_op") != null);
}

// spec-case: RC-PLAIN-RECORD-WRITE-1
test "RC-PLAIN-RECORD-WRITE-1 owned copy managed update and live view keep general paths" {
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(.rc);
    var result = try emitted(false);
    defer result.deinit();
    try t.expect(std.mem.indexOf(u8, try body(result.value, "local_value"), marker) == null);
    try t.expect(std.mem.indexOf(u8, try body(result.value, "managed_field"), marker) == null);
    try t.expect(std.mem.indexOf(u8, try body(result.value, "held_field"), marker) == null);
    try t.expect(std.mem.indexOf(u8, try body(result.value, "unique_field"), marker) == null);
}

// spec-case: RC-PLAIN-RECORD-WRITE-1
test "RC-PLAIN-RECORD-WRITE-1 publication follows the final store step check" {
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(.rc);
    var result = try emitted(true);
    defer result.deinit();
    const il = try body(result.value, "increment");
    const publication = std.mem.indexOf(u8, il, marker) orelse return error.TestUnexpectedResult;
    const commit = std.mem.lastIndexOf(u8, il[0..publication], "storel 18, %position") orelse return error.TestUnexpectedResult;
    const update = std.mem.lastIndexOf(u8, il[0..commit], "storel 17, %position") orelse return error.TestUnexpectedResult;
    try t.expect(std.mem.indexOf(u8, il[commit..publication], ", @step_limit,") != null);
    try t.expect(std.mem.indexOf(u8, il[update..commit], "call $myl_rc_") == null);
    try t.expect(std.mem.indexOf(u8, il[publication..], "storel") != null);
}

const Change = enum { external_entry, wrong_root, capture_escape };
fn changed(change: Change) !std.json.Parsed(Manifest) {
    var compilation = try compiler.Compilation.init(t.allocator, "changed_record_write.my", source);
    defer compilation.deinit();
    try compilation.emit();
    const code = @constCast(compilation.code.?.functions[0].scope.instructions);
    // Keep the typed stack valid while breaking a physical-tail obligation.
    switch (change) {
        .external_entry => code[5].op = .{ .jump_if_false = 13 },
        .wrong_root => code[18].op = .{ .store_local = code[12].op.store_local },
        .capture_escape => code[6].op = .{ .load_local = code[12].op.store_local },
    }
    const text = try compilation.emitQbe(t.allocator);
    defer t.allocator.free(text);
    return std.json.parseFromSlice(Manifest, t.allocator, text, .{ .ignore_unknown_fields = true, .allocate = .alloc_always });
}
fn refused(change: Change) !void {
    var result = try changed(change);
    defer result.deinit();
    try t.expect(std.mem.indexOf(u8, try body(result.value, "increment"), marker) == null);
}

// spec-case: RC-PLAIN-RECORD-WRITE-1
test "RC-PLAIN-RECORD-WRITE-1 entered tails wrong commits and earlier capture uses refuse" {
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(.rc);
    try refused(.external_entry);
    try refused(.wrong_root);
    try refused(.capture_escape);
}
