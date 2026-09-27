//! Physical borrowed-entry dependencies supplement ordinary unit interfaces.
const std = @import("std");
const contracts = @import("rc_calls.zig");
const bytecode = @import("bytecode.zig");
const native = @import("native_types.zig");
const fragments = @import("qbe_fragments.zig");
const runtime = @import("runtime_mode.zig");
const readonly = @import("rc_readonly_calls.zig");
const shapes = @import("rc_shape.zig");
const model = @import("rc_model.zig");

/// Hash every direct call's complete physical certificate or owned-ABI refusal.
/// GC retains its existing key; RC never trusts a stored semantic alias summary.
pub fn key(allocator: std.mem.Allocator, program: bytecode.Program, layouts: *native.Catalog, index: usize, base: fragments.Digest) native.Error!fragments.Digest {
    if (!runtime.enabled()) return base;
    var catalog = try @import("rc_shape.zig").Catalog.init(allocator, layouts);
    defer catalog.deinit();
    var hash = std.crypto.hash.Blake3.init(.{});
    hash.update("rc-borrow-callers-v4");
    hash.update(runtime.identity());
    hash.update(&base);
    hash.update(@import("rc_readonly_calls.zig").version);
    const plain = try readonly.identity(&catalog, program.functions, program.functions[index], runtime.identity());
    hash.update(&.{@intFromBool(plain != null)});
    if (plain) |identity| hash.update(&identity);
    try immortal(&hash, &catalog, program.functions, program.functions[index]);
    const own = try contracts.borrowedIn(allocator, &catalog, program.functions, program.functions[index], runtime.identity());
    hash.update(&.{@intFromBool(own != null)});
    if (own) |certificate| try entry(&hash, &catalog, program.functions, program.functions[index], certificate);
    for (program.functions[index].scope.instructions) |instruction| {
        if (instruction.op != .call) continue;
        const callee = program.functions[@backingInt(instruction.op.call)];
        var length: [8]u8 = undefined;
        std.mem.writeInt(u64, &length, callee.name.len, .little);
        hash.update(&length);
        hash.update(callee.name);
        try immortal(&hash, &catalog, program.functions, callee);
        const proof = try contracts.borrowedIn(allocator, &catalog, program.functions, callee, runtime.identity());
        hash.update(&.{@intFromBool(proof != null)});
        if (proof) |certificate| {
            var parameter: [4]u8 = undefined;
            std.mem.writeInt(u32, &parameter, certificate.parameter, .little);
            hash.update(&parameter);
            hash.update(&certificate.shape_identity);
            hash.update(&certificate.dependency_identity);
            try entry(&hash, &catalog, program.functions, callee, certificate);
        }
    }
    var result: fragments.Digest = undefined;
    hash.final(&result);
    return result;
}

fn entry(hash: *std.crypto.hash.Blake3, catalog: *shapes.Catalog, functions: []const bytecode.Function, function: bytecode.Function, certificate: model.BorrowCertificate) native.Error!void {
    hash.update("borrowed-entry");
    std.hash.autoHash(hash, certificate.parameter);
    hash.update(&certificate.shape_identity);
    hash.update(&certificate.dependency_identity);
    const raw = try readonly.borrowedEntry(catalog, functions, function, runtime.identity(), certificate);
    hash.update(&.{@intFromBool(raw != null)});
    if (raw) |proof| {
        defer catalog.allocator.free(proof.calls);
        hash.update(&proof.identity);
    }
}

fn immortal(hash: *std.crypto.hash.Blake3, catalog: *shapes.Catalog, functions: []const bytecode.Function, function: bytecode.Function) native.Error!void {
    hash.update(@import("rc_immortal_certificate.zig").version);
    const proof = try contracts.immortalIn(catalog, functions, function, runtime.identity());
    hash.update(&.{@intFromBool(proof != null)});
    if (proof) |certificate| {
        hash.update(&certificate.shape_identity);
        hash.update(&certificate.dependency_identity);
    }
}
