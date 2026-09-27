//! A private owning record lends a list field only through a closed scalar read.
const std = @import("std");
const compiler = @import("compiler.zig");
const runtime = @import("runtime_mode.zig");
const t = std.testing;
const marker = "# RC-RECORD-FIELD-READ-1";
const Manifest = struct { functions: []const struct { name: []const u8, il: []const u8 } };
const source =
    \\record State:
    \\    items: list[int]
    \\    index: int
    \\def read(index: int) -> int:
    \\    state = State([7, 11, 13], index)
    \\    value = state.items[state.index]
    \\    return value + state.index
    \\def external(state: mut State) -> int:
    \\    value = state.items[state.index]
    \\    state.index += 1
    \\    return value + state.index
    \\def callback(state: mut State) -> int:
    \\    state.items = [17]
    \\    return 0
    \\def changed() -> int:
    \\    state = State([7], 0)
    \\    value = state.items[callback(mut state)]
    \\    return value + state.index
    \\record Nested:
    \\    items: list[list[int]]
    \\    index: int
    \\def managed() -> int:
    \\    state = Nested([[7]], 0)
    \\    value = state.items[state.index]
    \\    return len(value) + state.index
    \\def floating(number: float) -> int:
    \\    state = State([7, 11, 13], 0)
    \\    value = state.items[int(sqrt(number))]
    \\    return value + state.index
    \\def main() -> int:
    \\    return read(1)
;

fn emitted(steps: bool) !std.json.Parsed(Manifest) {
    var compilation = try compiler.Compilation.init(t.allocator, "record_read.my", source);
    defer compilation.deinit();
    const text = try compilation.emitQbeWithOptions(t.allocator, .{ .step_checks = steps });
    defer t.allocator.free(text);
    return std.json.parseFromSlice(Manifest, t.allocator, text, .{ .allocate = .alloc_always, .ignore_unknown_fields = true });
}
fn body(manifest: Manifest, name: []const u8) ![]const u8 {
    for (manifest.functions) |function| if (std.mem.eql(u8, function.name, name)) return function.il;
    return error.TestUnexpectedResult;
}

// spec: RC-RECORD-FIELD-READ-1
test "RC record field reads lend named homes but refuse caller storage callbacks and managed leaves" {
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(.rc);
    var manifest = try emitted(false);
    defer manifest.deinit();
    const il = try body(manifest.value, "read");
    try t.expect(std.mem.indexOf(u8, il, marker) != null);
    try t.expect(std.mem.indexOf(u8, il, "call $myl_qbe_fail_normalized_index_bounds") != null);
    try t.expect(std.mem.indexOf(u8, il, "call $myl_qbe_rc_frame_cleanup") != null);
    for ([_][]const u8{ "external", "changed", "managed", "floating" }) |name| {
        try t.expect(std.mem.indexOf(u8, try body(manifest.value, name), marker) == null);
    }
}

// spec-case: RC-RECORD-FIELD-READ-1
test "RC record field reads keep generated helper fallback and later ordinary publication" {
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(.rc);
    var manifest = try emitted(false);
    defer manifest.deinit();
    const il = try body(manifest.value, "floating");
    try t.expect(std.mem.indexOf(u8, il, marker) == null);
    try t.expect(std.mem.indexOf(u8, il, "call $myl_qbe_float_unary") != null);
    try t.expect(std.mem.indexOf(u8, il, "call $myl_rc_native_loan") != null);
    try t.expect(std.mem.indexOf(u8, il, "call $myl_qbe_fail_normalized_index_bounds") != null);
}

// spec-case: RC-RECORD-FIELD-READ-1
test "RC record field reads retain every original checked instruction and step boundary" {
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(.rc);
    var manifest = try emitted(true);
    defer manifest.deinit();
    const il = try body(manifest.value, "read");
    const at = std.mem.indexOf(u8, il, marker) orelse return error.TestUnexpectedResult;
    try t.expect(std.mem.indexOf(u8, il[at..], ", @step_limit,") != null);
    try t.expect(std.mem.indexOf(u8, il[at..], "call $myl_qbe_fail_normalized_index_bounds") != null);
}
