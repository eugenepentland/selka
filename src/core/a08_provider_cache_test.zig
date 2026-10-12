//! Provider pin identities stay exact across durable lowering and catalog edits.
const std = @import("std");
const language = @import("mylang");
const ir = @import("ir.zig");
const build = @import("build.zig");
const lowering = @import("lowering_cache.zig");
const stage = @import("stage_store.zig");
const provider = @import("aggregate_provider.zig");
const ownership = @import("single_owner.zig");
const support = @import("test_support.zig");
const passes = @import("passes.zig");

const source =
    \\import filesystem
    \\record Providers:
    \\    fs: Filesystem
    \\    label: str
    \\func inspect(value: Providers) -> int:
    \\    with value.fs.read_only() as frozen:
    \\        if frozen.exists("absent"):
    \\            return 1
    \\        return 42
    \\func main(out: Stream) -> int:
    \\    const value = Providers(fs=filesystem.memory(), label="owner-" + str(1))
    \\    out.print(inspect(value))
    \\    return 0
;

const Entry = struct {
    bytes: []const u8,
    fn read(context: ?*anyopaque, a: std.mem.Allocator, path: []const u8, _: usize) language.project.ReadError![]u8 {
        const self: *Entry = @ptrCast(@alignCast(context.?));
        if (!std.mem.eql(u8, path, "main.my")) return error.NotFound;
        return a.dupe(u8, self.bytes);
    }
};

const Evidence = struct { lowered: usize, reused: usize, physical: ir.Type };

fn pinType(module: *const ir.Module) !ir.Type {
    var found: ?ir.Type = null;
    for (module.functions.items) |function| {
        if (!try provider.marker(module, &function)) continue;
        const actual = provider.markerType(function.name).?;
        try std.testing.expectEqual(actual, function.signature.params[0]);
        if (found) |previous| try std.testing.expectEqual(previous, actual);
        found = actual;
    }
    return found orelse error.TestUnexpectedResult;
}

fn compare(parent: std.mem.Allocator, store: *stage.Store, text: []const u8, execute: bool) !Evidence {
    var arena = std.heap.ArenaAllocator.init(parent);
    defer arena.deinit();
    const a = arena.allocator();
    var entry: Entry = .{ .bytes = text };
    var project: language.embedded_project.Program = undefined;
    try project.init(a, .{ .context = &entry, .read = Entry.read });
    const program = project.compilation.program.?;
    var failure: ownership.Failure = .{};
    try ownership.checkMode(a, program, &failure, true);
    const input: build.Input = .{ .program = program, .source = project.compilation.src, .single_owner = true, .zero_rc = true };
    var refusal: build.Refusal = .{};
    var cache = lowering.Cache.init(store);
    var cached = try build.buildExecutableCached(a, input, &refusal, &cache);
    const fresh = try build.buildExecutable(a, input, &refusal);
    try std.testing.expectEqualDeep(fresh.compounds.items, cached.compounds.items);
    try std.testing.expectEqual(fresh.functions.items.len, cached.functions.items.len);
    for (fresh.functions.items, cached.functions.items) |expected, actual| {
        try std.testing.expectEqualStrings(expected.name, actual.name);
        try std.testing.expectEqualDeep(expected.signature, actual.signature);
    }
    try std.testing.expectEqualStrings(try @import("print.zig").module(a, &fresh), try @import("print.zig").module(a, &cached));
    const physical = try pinType(&cached);
    try std.testing.expectEqual(try pinType(&fresh), physical);
    if (execute) {
        const result = try passes.debug(a, &cached);
        try ownership.verifyLowered(&cached, &failure);
        try support.verified(a, &cached, result.plans);
        const out = program.functions[@backingInt(program.main)].scope.locals[0].ty.capabilityIndex().?;
        const run = try support.runOwned(a, &cached, .{ .own = false, .analysis = support.analysis(&result), .main = .{ .parameters = &.{"out"}, .capabilities = &.{out} } });
        try std.testing.expectEqual(@as(u8, 0), run.status);
        try std.testing.expectEqualStrings("42\n", run.stdout);
        try std.testing.expectEqualStrings("", run.stderr);
        try std.testing.expect(@import("zero_rc.zig").emittedClean(run.llvm));
        try std.testing.expect(std.mem.indexOf(u8, run.llvm, provider.prefix) == null);
    }
    return .{ .lowered = cache.lowered, .reused = cache.reused, .physical = physical };
}

// spec-case: NEW-CORE-ZERO-RC-ABI-1
// spec-case: NEW-CORE-STAGE-CACHE-3
// spec: NEW-CORE-ZERO-RC-PROVIDER-FIELDS-1
test "zero RC A08 aggregate provider pins survive cache replay and earlier type discovery edits" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var store = try stage.Store.init(std.testing.allocator, std.testing.io, try temporary.dir.realPathFileAlloc(std.testing.io, ".", a));
    defer store.deinit();
    const declarations = try std.mem.replaceOwned(u8, a, source, "record Providers:", "record Earlier:\n    values: bytes[]\nrecord Providers:");
    const edited = try std.mem.replaceOwned(u8, a, declarations, "    const value = Providers", "    const earlier = Earlier(values=[b\"a\", b\"b\"])\n    assert len(earlier.values) == 2\n    const value = Providers");
    var types: [2]ir.Type = undefined;
    for ([_][]const u8{ source, edited }, 0..) |text, index| {
        const cold = try compare(std.testing.allocator, &store, text, false);
        const warm = try compare(std.testing.allocator, &store, text, true);
        try std.testing.expect(cold.lowered > 0);
        try std.testing.expectEqual(@as(usize, 0), warm.lowered);
        try std.testing.expect(warm.reused > 0);
        try std.testing.expectEqual(cold.physical, warm.physical);
        types[index] = cold.physical;
    }
    try std.testing.expect(types[0] != types[1]);
}

// spec-case: NEW-CORE-ZERO-RC-ABI-1
test "zero RC A08 aggregate provider pins refuse stale physical type and ownership signatures" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var module: ir.Module = .{ .zero_rc = true, .single_owner = true };
    const first = try module.intern(a, .{ .record = &.{ .capability, .str } });
    const second = try module.intern(a, .{ .record = &.{ .capability, .i64 } });
    var function: ir.Function = .{ .name = try std.fmt.allocPrint(a, "{s}{d}", .{ provider.prefix, @backingInt(first) }), .signature = .{ .params = &.{first}, .ret = .void, .linkage = .runtime_c } };
    try std.testing.expect(try provider.marker(&module, &function));
    const valid = function.signature;
    const invalid = [_]ir.Signature{
        .{ .params = &.{second}, .ret = .void, .linkage = .runtime_c },
        .{ .params = &.{first}, .ret = .void, .linkage = .runtime_c, .owned = 1 },
        .{ .params = &.{first}, .ret = .void, .linkage = .runtime_c, .consumes = 1 },
        .{ .params = &.{first}, .ret = .void, .linkage = .runtime_c, .views = 1 },
    };
    for (invalid) |signature| {
        function.signature = signature;
        try std.testing.expectError(error.UnsupportedInstruction, provider.marker(&module, &function));
    }
    function.signature = valid;
    module.zero_rc = false;
    try std.testing.expectError(error.UnsupportedInstruction, provider.marker(&module, &function));
}
