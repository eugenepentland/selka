//! Persisted borrowed-provider records must repeat their parameter-root proof.
const std = @import("std");
const language = @import("mylang");
const borrowed = @import("borrowed_provider.zig");
const ir = @import("ir.zig");
const cache = @import("optimization_cache.zig");
const snapshot = @import("ir_snapshot.zig");
const store = @import("stage_store.zig");
const origins = @import("inline_origins.zig");
const emit = @import("emit_llvm.zig");

fn locate(_: *const anyopaque, span: u32) emit.Location {
    return .{ .line = 1, .column = span + 1 };
}

// spec-case: CAPABILITY-FIELD-METHOD-1
test "borrowed provider checksum-valid cache body refuses corrupted owning parameter roots" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const source =
        \\record Context:
        \\    fs: Filesystem
        \\    env: Environment
        \\    value: int
        \\func main(fs: Filesystem, env: Environment) -> int:
        \\    const ctx = Context(fs=fs, env=env, value=7)
        \\    return ctx.value
    ;
    var unit = try language.Compilation.init(a, "cached-provider.my", source);
    try unit.check();
    var failure: @import("single_owner.zig").Failure = .{};
    try @import("single_owner.zig").checkMode(a, unit.program.?, &failure, true);
    var refusal: @import("build.zig").Refusal = .{};
    var module = try @import("build.zig").buildExecutable(a, .{ .program = unit.program.?, .single_owner = true, .zero_rc = true }, &refusal);
    const index = markerFunction(&module).?;
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var storage = try store.Store.init(std.testing.allocator, std.testing.io, try temporary.dir.realPathFileAlloc(std.testing.io, ".", a));
    defer storage.deinit();
    const context = try snapshot.Context.init(a, &module, null);
    const token: u8 = 0;
    var optimizer = cache.Context.init(&storage, context, .{ .context = &token, .locate = locate });
    var ancestry: origins.Table = .{};
    const provenance = try cache.Provenance.capture(a, context, &ancestry, index);
    var wire = try snapshot.capture(a, context, module.functions.items[index]);
    try std.testing.expect((try optimizer.restore(a, index, wire, provenance, &ancestry)) != null);
    wire.function.signature.owned |= 1;
    const key = storage.key("borrowed-provider-corrupted-root-v1", &.{});
    try storage.storeValue(key, snapshot.Wire, wire);
    const decoded = (try storage.loadValue(a, key, snapshot.Wire)).?;
    const malformed = try snapshot.restore(a, context, decoded);
    // The snapshot is structurally decodable; the ownership marker alone must refuse it.
    try std.testing.expectError(error.UnsupportedInstruction, @import("marker_validation.zig").validate(std.testing.allocator, &module, &malformed));
    try std.testing.expect((try optimizer.restore(a, index, decoded, provenance, &ancestry)) == null);
}

fn markerFunction(module: *const ir.Module) ?u32 {
    for (module.functions.items, 0..) |*function, index| {
        if (borrowed.contains(module, function)) return @intCast(index);
    }
    return null;
}
