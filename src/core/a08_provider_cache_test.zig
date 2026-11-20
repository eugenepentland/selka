//! A record that holds a capability lowers, caches and replays exactly across catalog edits. Since 5C a capability is a
//! scalar handle, so the build emits no provider pin; the pin marker's validation is still tested on hand-built IR.
const std = @import("std");
const language = @import("selka");
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
    \\    print(out, inspect(value))
    \\    return 0
;

const Entry = struct {
    bytes: []const u8,
    fn read(context: ?*anyopaque, a: std.mem.Allocator, path: []const u8, _: usize) language.project.ReadError![]u8 {
        const self: *Entry = @ptrCast(@alignCast(context.?));
        if (!std.mem.eql(u8, path, "main.selka")) return error.NotFound;
        return a.dupe(u8, self.bytes);
    }
};

const Evidence = struct { lowered: usize, reused: usize };

fn pins(module: *const ir.Module) !usize {
    var count: usize = 0;
    for (module.functions.items) |function| {
        if (try provider.marker(module, &function)) count += 1;
    }
    return count;
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
    try ownership.check(a, program, &failure);
    const input: build.Input = .{
        .program = program,
        .source = project.compilation.src,
    };
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
    try std.testing.expectEqual(@as(usize, 0), try pins(&cached));
    try std.testing.expectEqual(@as(usize, 0), try pins(&fresh));
    if (execute) {
        const result = try passes.debug(a, &cached);
        try support.verified(a, &cached, result.plans);
        const out = program.functions[@backingInt(program.main)].scope.locals[0].ty.capabilityIndex().?;
        const run = try support.runOwned(a, &cached, .{ .own = false, .analysis = support.analysis(&result), .main = .{ .parameters = &.{"out"}, .capabilities = &.{out} } });
        try std.testing.expectEqual(@as(u8, 0), run.status);
        try std.testing.expectEqualStrings("42\n", run.stdout);
        try std.testing.expectEqualStrings("", run.stderr);
        try std.testing.expect(@import("zero_rc.zig").emittedClean(run.llvm));
        try std.testing.expect(std.mem.indexOf(u8, run.llvm, provider.prefix) == null);
    }
    return .{ .lowered = cache.counts.lowered, .reused = cache.counts.reused };
}

// spec-case: NEW-CORE-ZERO-RC-ABI-1
// spec-case: NEW-CORE-STAGE-CACHE-3
// spec: NEW-CORE-ZERO-RC-PROVIDER-FIELDS-1
test "zero RC A08 (5C) a record holding a capability replays with no provider pin across earlier type discovery edits" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var store = try stage.Store.init(std.testing.allocator, std.testing.io, try temporary.dir.realPathFileAlloc(std.testing.io, ".", a));
    defer store.deinit();
    const declarations = try std.mem.replaceOwned(u8, a, source, "record Providers:", "record Earlier:\n    values: bytes[]\nrecord Providers:");
    const edited = try std.mem.replaceOwned(u8, a, declarations, "    const value = Providers", "    const earlier = Earlier(values=[b\"a\", b\"b\"])\n    assert len(earlier.values) == 2\n    const value = Providers");
    for ([_][]const u8{ source, edited }) |text| {
        const cold = try compare(std.testing.allocator, &store, text, false);
        const warm = try compare(std.testing.allocator, &store, text, true);
        try std.testing.expect(cold.lowered > 0);
        try std.testing.expectEqual(@as(usize, 0), warm.lowered);
        try std.testing.expect(warm.reused > 0);
    }
}

// spec-case: NEW-CORE-ZERO-RC-ABI-1
test "zero RC A08 aggregate provider pins refuse a malformed name and ownership signatures" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var module: ir.Module = .{};
    const first = try module.intern(a, .{ .record = &.{ .capability, .str } });
    var function: ir.Function = .{ .name = try support.fixtureName(a, provider.prefix, first), .signature = .{ .params = &.{first}, .ret = .void, .linkage = .runtime_c } };
    try std.testing.expect(try provider.marker(&module, &function));
    const malformed = function.name[0 .. function.name.len - 1];
    function.name = malformed;
    try std.testing.expectError(error.UnsupportedInstruction, provider.marker(&module, &function));
    function.name = try support.fixtureName(a, provider.prefix, first);
    const invalid = [_]ir.Signature{
        .{ .params = &.{first}, .ret = .void, .linkage = .runtime_c, .passing = .{ .owned = 1 } },
        .{ .params = &.{first}, .ret = .void, .linkage = .runtime_c, .passing = .{ .consumes = 1 } },
        .{ .params = &.{first}, .ret = .void, .linkage = .runtime_c, .passing = .{ .views = 1 } },
    };
    for (invalid) |signature| {
        function.signature = signature;
        try std.testing.expectError(error.UnsupportedInstruction, provider.marker(&module, &function));
    }
}
