//! Borrowed aggregate rendering has no temporary managed owner in either emitter.
const std = @import("std");
const ir = @import("ir.zig");
const emit = @import("emit_llvm.zig");
const support = @import("test_support.zig");
const zero = @import("zero_rc.zig");

fn location(_: *const anyopaque, offset: u32) emit.Location {
    return .{ .line = 1, .column = offset + 1 };
}

fn example(a: std.mem.Allocator) !ir.Module {
    var refusal: @import("build.zig").Refusal = .{};
    return support.buildSource(a,
        \\record Label:
        \\    number: int
        \\    word: str
        \\func show(value: Label) -> str:
        \\    return f"{value}"
        \\func main() -> int:
        \\    const value = Label(number=7, word="x")
        \\    return strings.char_count(show(value))
    , &refusal);
}

// spec-case: NEW-CORE-S3-VALUES-1
test "A04 rendering borrows physical values in whole and unit emission" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const module = try example(a);
    var show_count: usize = 0;
    for (module.functions.items) |function| {
        for (function.insts.items) |inst| try std.testing.expect(inst.op != .box_make);
        if (!std.mem.startsWith(u8, function.name, "myl_core_show_")) continue;
        show_count += 1;
        try std.testing.expectEqual(@as(usize, 1), function.signature.params.len);
        try std.testing.expect(module.kind(function.signature.params[0]) == .record);
        try std.testing.expectEqual(@as(u64, 0), function.signature.passing.owned);
    }
    try std.testing.expectEqual(@as(usize, 1), show_count);
    const context: u8 = 0;
    const options: emit.Options = .{ .locator = .{ .context = &context, .locate = location }, .source_path = "render.selka", .main = .{ .parameters = &.{} } };
    const whole = try emit.emitModule(a, &module, options);
    try std.testing.expect(std.mem.indexOf(u8, whole, "call ptr @myl_core_values_render(ptr @myl.render.") != null);
    try std.testing.expect(std.mem.indexOf(u8, whole, "call fastcc ptr @myl_core_show_") == null);
    try std.testing.expect(std.mem.indexOf(u8, whole, "define internal fastcc ptr @myl_core_show_") == null);
    const units = try @import("emit_units.zig").emit(a, &module, options);
    try std.testing.expectEqual(@as(usize, 1), renderCalls(units));
}

fn renderCalls(units: []const @import("emit_units.zig").Unit) usize {
    var calls: usize = 0;
    for (units) |unit| {
        var lines = std.mem.splitScalar(u8, unit.llvm, '\n');
        while (lines.next()) |line| {
            if (std.mem.indexOf(u8, line, "call ptr @myl_core_values_render(") != null) calls += 1;
        }
    }
    return calls;
}

// spec-case: NEW-CORE-S3-VALUES-1
/// The text of a key, as a render id spells it.
const sample_key = "0123456789abcdef0123456789abcdef";

test "A04 rendering registry admits exact borrowed fresh show helpers" {
    for ([_][]const u8{ "myl_core_show_" ++ sample_key, "myl_core_show_" ++ sample_key ++ "_v" }) |name| {
        const contract = zero.contract(name) orelse return error.TestUnexpectedResult;
        try std.testing.expect(contract.result == .fresh);
        try std.testing.expectEqual(@as(u64, 0), contract.owned);
    }
}

// spec-case: NEW-CORE-S3-VALUES-1
test "A04 rendering registry admits exact scalar descriptor helpers" {
    for ([_][]const u8{ "myl_core_render_shape_0_" ++ sample_key, "myl_core_render_shape_0_" ++ sample_key ++ "_v" }) |name| {
        const contract = zero.contract(name) orelse return error.TestUnexpectedResult;
        try std.testing.expect(contract.result == .scalar);
        try std.testing.expectEqual(@as(u64, 0), contract.owned);
    }
}

// spec-case: NEW-CORE-S3-VALUES-1
test "A04 rendering registry rejects malformed generated helper identities" {
    for ([_][]const u8{
        "myl_core_show_",                     "myl_core_show_7",                     "myl_core_show_" ++ sample_key ++ "_",
        "myl_core_show_x",                    "myl_core_show_" ++ sample_key ++ "0", "myl_core_show_" ++ sample_key ++ "_v_x",
        "myl_core_show_" ++ sample_key[1..],  "myl_core_render_shape_",              "myl_core_render_shape_0",
        "myl_core_render_shape_x_7",          "myl_core_render_shape_0_7",           "myl_core_render_shape_0_" ++ sample_key ++ "_p",
        "myl_core_render_shape_4294967296_7",
    }) |name| try std.testing.expect(zero.contract(name) == null);
}

// spec-case: NEW-CORE-S3-VALUES-1
test "A04 rendering rejects wrong generated helper signatures" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var module = try example(a);
    const context: u8 = 0;
    const options: emit.Options = .{ .locator = .{ .context = &context, .locate = location }, .source_path = "render.selka", .main = .{ .parameters = &.{} } };
    for (module.functions.items) |*function| {
        if (!std.mem.startsWith(u8, function.name, "myl_core_show_")) continue;
        function.signature.passing.owned = 1;
        try std.testing.expectError(error.UnsupportedInstruction, emit.emitModule(a, &module, options));
        function.signature.passing.owned = 0;
        function.signature.params = &.{.i64};
        try std.testing.expectError(error.UnsupportedInstruction, emit.emitModule(a, &module, options));
        break;
    }
    var metadata: ir.Module = .{};
    try metadata.functions.append(a, .{ .name = "myl_core_render_shape_0_" ++ sample_key, .signature = .{ .params = &.{.i64}, .ret = .void, .linkage = .runtime_c } });
    var text: std.ArrayList(u8) = .empty;
    try std.testing.expectError(error.UnsupportedInstruction, @import("emit_render.zig").descriptors(a, &metadata, &text));
}

test "O3 rendering descriptors separate owned and borrowed wrapper layouts in either discovery order" {
    try wrapperDescriptors(std.testing.allocator, false);
    try wrapperDescriptors(std.testing.allocator, true);
}

fn wrapperDescriptors(backing: std.mem.Allocator, owned_first: bool) !void {
    var arena = std.heap.ArenaAllocator.init(backing);
    defer arena.deinit();
    const a = arena.allocator();
    const declarations =
        \\record Link:
        \\    label: str
        \\    next: Link?
        \\func borrowed_link(value: Link?) -> str:
        \\    return f"{value}"
        \\func owned_link(own value: Link?) -> str:
        \\    return f"{value}"
        \\func borrowed_text(value: str??) -> str:
        \\    return f"{value}"
        \\func owned_text(own value: str??) -> str:
        \\    return f"{value}"
        \\func borrowed_bytes(value: bytes?) -> str:
        \\    return f"{value}"
        \\func owned_bytes(own value: bytes?) -> str:
        \\    return f"{value}"
        \\func borrowed_list(value: int[]?) -> str:
        \\    return f"{value}"
        \\func owned_list(own value: int[]?) -> str:
        \\    return f"{value}"
        \\func main() -> int:
        \\    const link: Link? = Some(Link(label="owned-" + str(1), next=None))
        \\    const text: str?? = Some(Some("owned-" + str(2)))
        \\    const octets: bytes? = Some(b"ab")
        \\    const rows: int[]? = Some([1, 2])
        \\    const other_link: Link? = Some(Link(label="borrowed-" + str(3), next=None))
        \\    const other_text: str?? = Some(Some("borrowed-" + str(4)))
        \\    const other_octets: bytes? = Some(b"cd")
        \\    const other_rows: int[]? = Some([3, 4])
        \\
    ;
    const owned =
        \\    const a = owned_link(own link)
        \\    const b = owned_text(own text)
        \\    const c = owned_bytes(own octets)
        \\    const d = owned_list(own rows)
        \\
    ;
    const borrowed =
        \\    const e = borrowed_link(other_link)
        \\    const f = borrowed_text(other_text)
        \\    const g = borrowed_bytes(other_octets)
        \\    const h = borrowed_list(other_rows)
        \\
    ;
    const source = try std.mem.concat(a, u8, &.{
        declarations,
        if (owned_first) owned else borrowed,
        if (owned_first) borrowed else owned,
        "    return len(a) + len(b) + len(c) + len(d) + len(e) + len(f) + len(g) + len(h)\n",
    });
    var refusal: @import("build.zig").Refusal = .{};
    const module = try support.buildSource(a, source, &refusal);
    var helpers: usize = 0;
    for (module.functions.items) |function| {
        if (!std.mem.startsWith(u8, function.name, "myl_core_show_")) continue;
        helpers += 1;
        // The checked Option type alone cannot identify its physical layout, so the id keys both; it holds no position.
        try std.testing.expect(@import("build_render.zig").generated(function.name) == .show);
    }
    try std.testing.expectEqual(@as(usize, 8), helpers);
    var kinds: [15]bool = @splat(false);
    const metadata = @import("build_render.zig");
    for (module.strings.items) |string| {
        if (!std.mem.startsWith(u8, string, metadata.prefix)) continue;
        const at = std.mem.indexOfScalar(u8, string, '|').?;
        const parsed = try std.json.parseFromSlice(metadata.Shape, a, string[at + 1 ..], .{});
        defer parsed.deinit();
        try std.testing.expect(parsed.value.kind < kinds.len);
        kinds[parsed.value.kind] = true;
    }
    for ([_]usize{ 3, 4, 5, 6, 7, 12, 14 }) |kind| try std.testing.expect(kinds[kind]);
    const context: u8 = 0;
    _ = try emit.emitModule(a, &module, .{ .locator = .{ .context = &context, .locate = location }, .source_path = "render.selka", .main = .{ .parameters = &.{} } });
}

test "O3 rendering whole borrowed records and dictionaries shares storage helpers in either discovery order" {
    try rootDescriptors(std.testing.allocator, false);
    try rootDescriptors(std.testing.allocator, true);
}

fn rootDescriptors(backing: std.mem.Allocator, owned_first: bool) !void {
    var arena = std.heap.ArenaAllocator.init(backing);
    defer arena.deinit();
    const a = arena.allocator();
    const declarations =
        \\record Item:
        \\    label: str
        \\func loan_record(value: Item) -> Item from value:
        \\    return value
        \\func loan_table(value: dict[str, str]) -> dict[str, str] from value:
        \\    return value
        \\func main() -> int:
        \\    const item = Item(label="item-" + str(1))
        \\    const table = {"key": "value-" + str(2)}
        \\
    ;
    const owned = "    const owned = f\"{item}|{table}\"\n";
    const borrowed = "    const borrowed = f\"{loan_record(item)}|{loan_table(table)}\"\n";
    const source = try std.mem.concat(a, u8, &.{
        declarations,
        if (owned_first) owned else borrowed,
        if (owned_first) borrowed else owned,
        "    return len(owned) + len(borrowed)\n",
    });
    var refusal: @import("build.zig").Refusal = .{};
    const module = try support.buildSource(a, source, &refusal);
    var helpers: usize = 0;
    for (module.functions.items) |function| {
        if (!std.mem.startsWith(u8, function.name, "myl_core_show_")) continue;
        helpers += 1;
        const physical = function.signature.params[0];
        try std.testing.expect(!module.isBorrowed(physical));
    }
    try std.testing.expectEqual(@as(usize, 2), helpers);
    const context: u8 = 0;
    _ = try emit.emitModule(a, &module, .{ .locator = .{ .context = &context, .locate = location }, .source_path = "render.selka", .main = .{ .parameters = &.{} } });
}
