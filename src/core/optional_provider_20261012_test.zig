//! Borrowed optional provider calls have an exact envelope and cannot escape.
const std = @import("std");
const language = @import("mylang");
const owner = @import("single_owner.zig");
const build = @import("build.zig");
const borrowed = @import("borrowed_provider.zig");
const ir = @import("ir.zig");
const Hand = @import("test_support.zig").Hand;
const report = std.debug.print;

const Entry = struct {
    bytes: []const u8,
    fn read(context: ?*anyopaque, a: std.mem.Allocator, path: []const u8, _: usize) language.project.ReadError![]u8 {
        const self: *Entry = @ptrCast(@alignCast(context.?));
        if (!std.mem.eql(u8, path, "main.my")) return error.NotFound;
        return a.dupe(u8, self.bytes);
    }
};

fn sourceCheck(parent: std.mem.Allocator, source: []const u8, accept: bool) !void {
    var arena = std.heap.ArenaAllocator.init(parent);
    defer arena.deinit();
    const a = arena.allocator();
    var entry: Entry = .{ .bytes = source };
    var project: language.embedded_project.Program = undefined;
    project.loaded = language.project.Project.init(a);
    defer project.loaded.deinit();
    try project.loaded.load(.{ .context = &entry, .read = Entry.read }, "main", .{});
    project.index = try language.interfaces.build(&project.loaded);
    project.compilation = try language.project_compile.Compilation.init(&project.index);
    const unit = &project.compilation;
    unit.check() catch |err| {
        for (unit.diagnostics.items.items) |diagnostic| report("FRONTEND {s}: {s}\nSOURCE: {s}\n", .{ diagnostic.code, diagnostic.message, source });
        return err;
    };
    var failure: owner.Failure = .{};
    if (!accept) {
        try std.testing.expectError(error.Rejected, owner.checkMode(a, unit.program.?, &failure, true));
        return;
    }
    owner.checkMode(a, unit.program.?, &failure, true) catch |err| {
        report("{s}: {s}\n", .{ failure.code, failure.message });
        return err;
    };
    // A typed temporary match must refuse Some even though read expressions
    // generally permit it as a call argument. The source frontend requires an
    // expected type for a bare Some match, so mutate a valid typed fixture.
    var some: ?language.typed.NodeId = null;
    for (unit.program.?.nodes, 0..) |node, index| {
        if (borrowed.optional(unit.program.?, node.ty) and node.data == .variant and node.data.variant.tag == 1) {
            some = @fromBackingInt(index);
            break;
        }
    }
    for (@constCast(unit.program.?.statements)) |*statement| {
        if (statement.data != .match or some == null) continue;
        const value = statement.data.match.value;
        statement.data.match.value = some.?;
        try std.testing.expectError(error.Rejected, owner.checkMode(a, unit.program.?, &failure, true));
        try std.testing.expectEqualStrings("E_SINGLE_OWNER_BORROW", failure.code);
        statement.data.match.value = value;
        break;
    }
    var optional_count: usize = 0;
    for (@constCast(unit.program.?.records), 0..) |*record, index| {
        const ty: language.typed.Type = @fromBackingInt(language.typed.Type.record_base + index);
        if (!borrowed.optional(unit.program.?, ty)) continue;
        optional_count += 1;
        const name = record.name;
        record.name = "OptionNamed<Clock>";
        try std.testing.expect(!borrowed.optional(unit.program.?, ty));
        record.name = "std_result::Option<clock_cap>";
        try std.testing.expect(borrowed.optional(unit.program.?, ty));
        record.name = name;
    }
    try std.testing.expect(optional_count != 0);
    var refusal: build.Refusal = .{};
    var module = try build.buildExecutable(a, .{ .program = unit.program.?, .single_owner = true, .zero_rc = true }, &refusal);
    try borrowed.validateModule(a, &module);
    const result = try @import("passes.zig").debug(a, &module);
    try owner.verifyLowered(&module, &failure);
    try @import("test_support.zig").verified(a, &module, result.plans);
}

// spec-case: CAPABILITY-FIELD-METHOD-1
test "optional provider 20261012 inline Some and None read calls preserve borrowed match payloads" {
    try sourceCheck(std.testing.allocator,
        \\func inspect(clock: Clock?) -> int:
        \\    match clock:
        \\        case Some(provider):
        \\            return 1
        \\        case None:
        \\            return 0
        \\func main(clock: Clock) -> int:
        \\    return inspect(Some(clock)) + inspect(None)
    , true);
}

// spec-case: CAPABILITY-FIELD-METHOD-1
test "optional provider 20261012 source rejects owning storage returns and temporary matches" {
    for ([_][]const u8{
        \\func escape(clock: Clock) -> Clock?:
        \\    return Some(clock)
        \\func main() -> int:
        \\    return 0
        ,
        \\func main(clock: Clock) -> int:
        \\    const stored: Clock? = Some(clock)
        \\    return 0
        ,
        \\record Runtime:
        \\    clock: Clock?
        \\func main(clock: Clock) -> int:
        \\    const rt = Runtime(clock=Some(clock))
        \\    return 0
        ,
        \\func escape(clock: Clock?, fallback: Clock) -> Clock:
        \\    match clock:
        \\        case Some(provider):
        \\            return provider
        \\        case None:
        \\            return fallback
        \\func main() -> int:
        \\    return 0
    }) |source| try sourceCheck(std.testing.allocator, source, false);
}

// spec-case: CAPABILITY-FIELD-METHOD-1
test "optional provider 20261012 marker rejects ABI corruption borrowed payload escapes and cleanup" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var module: ir.Module = .{ .zero_rc = true };
    const ty = try module.intern(a, .{ .@"union" = &.{ .void, .capability } });
    const marker = try borrowed.declare(a, &module, ty);
    var h = try Hand.init(a, &module, "optional", .{ .params = &.{.capability}, .ret = .i64 });
    const parameter = try h.param(0);
    const optional = try h.emit(.{ .op = .call, .ty = ty, .a = @fromBackingInt(marker), .data = try h.extra(&.{parameter}) });
    const payload = try h.emit(.{ .op = .union_payload, .ty = .capability, .a = optional, .data = 1 });
    _ = try h.emit(.{ .op = .ret, .ty = .void, .a = try h.int(.i64, 1) });
    const index = try h.finish();
    try borrowed.validateModule(a, &module);
    const declaration = &module.functions.items[marker];
    const original = declaration.*;
    declaration.signature.owned = 1;
    try std.testing.expectError(error.UnsupportedInstruction, borrowed.validateModule(a, &module));
    declaration.* = original;
    declaration.signature.params = &.{.cap};
    try std.testing.expectError(error.UnsupportedInstruction, borrowed.validateModule(a, &module));
    declaration.* = original;
    const reversed = try module.intern(a, .{ .@"union" = &.{ .capability, .void } });
    declaration.name = try std.fmt.allocPrint(a, "{s}{d}", .{ borrowed.optional_prefix, @backingInt(reversed) });
    declaration.signature.ret = reversed;
    try std.testing.expectError(error.UnsupportedInstruction, borrowed.validateModule(a, &module));
    declaration.* = original;
    const function = &module.functions.items[index];
    const last = function.insts.items.len - 1;
    function.insts.items[last].a = payload;
    try std.testing.expectError(error.UnsupportedInstruction, borrowed.validate(a, &module, function));
    function.insts.items[last] = .{ .op = .release, .ty = .void, .a = payload };
    try std.testing.expectError(error.UnsupportedInstruction, borrowed.validate(a, &module, function));
    function.insts.items[last] = .{ .op = .release, .ty = .void, .a = optional };
    try std.testing.expectError(error.UnsupportedInstruction, borrowed.validate(a, &module, function));
}

fn locate(_: *const anyopaque, span: u32) @import("emit_llvm.zig").Location {
    return .{ .line = 1, .column = span + 1 };
}

// spec-case: CAPABILITY-FIELD-METHOD-1
test "optional provider 20261012 cache restores exact helper and refuses consuming source root" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var module: ir.Module = .{ .zero_rc = true };
    const ty = try module.intern(a, .{ .@"union" = &.{ .void, .capability } });
    const marker = try borrowed.declare(a, &module, ty);
    var h = try Hand.init(a, &module, "cached_optional", .{ .params = &.{.capability}, .ret = .i64 });
    _ = try h.emit(.{ .op = .call, .ty = ty, .a = @fromBackingInt(marker), .data = try h.extra(&.{try h.param(0)}) });
    _ = try h.emit(.{ .op = .ret, .ty = .void, .a = try h.int(.i64, 1) });
    const index = try h.finish();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const snapshot = @import("ir_snapshot.zig");
    const cache = @import("optimization_cache.zig");
    var storage = try @import("stage_store.zig").Store.init(std.testing.allocator, std.testing.io, try temporary.dir.realPathFileAlloc(std.testing.io, ".", a));
    defer storage.deinit();
    const context = try snapshot.Context.init(a, &module, null);
    const token: u8 = 0;
    var optimizer = cache.Context.init(&storage, context, .{ .context = &token, .locate = locate });
    var ancestry: @import("inline_origins.zig").Table = .{};
    const provenance = try cache.Provenance.capture(a, context, &ancestry, index);
    var wire = try snapshot.capture(a, context, module.functions.items[index]);
    try std.testing.expect((try optimizer.restore(a, index, wire, provenance, &ancestry)) != null);
    wire.function.signature.consumes = 1;
    const key = storage.key("optional-provider-20261012-corrupted-root", &.{});
    try storage.storeValue(key, snapshot.Wire, wire);
    const decoded = (try storage.loadValue(a, key, snapshot.Wire)).?;
    const malformed = try snapshot.restore(a, context, decoded);
    try std.testing.expectError(error.UnsupportedInstruction, @import("marker_validation.zig").validate(std.testing.allocator, &module, &malformed));
    try std.testing.expect((try optimizer.restore(a, index, decoded, provenance, &ancestry)) == null);
}
