//! Physical borrowed-entry dependencies supplement ordinary unit interfaces.
const std = @import("std");
const bytecode = @import("bytecode.zig");
const native = @import("native_types.zig");
const fragments = @import("qbe_fragments.zig");
const runtime = @import("runtime_mode.zig");

/// Hash every direct call's complete physical certificate or owned-ABI refusal.
/// GC retains its existing key; RC never trusts a stored semantic alias summary.
pub fn key(allocator: std.mem.Allocator, program: bytecode.Program, layouts: *native.Catalog, index: usize, base: fragments.Digest) native.Error!fragments.Digest {
    if (!runtime.enabled()) return base;
    var catalog = try @import("rc_shape.zig").Catalog.init(allocator, layouts);
    defer catalog.deinit();
    var hash = std.crypto.hash.Blake3.init(.{});
    hash.update("rc-borrow-callers-v2");
    hash.update(runtime.identity());
    hash.update(&base);
    hash.update(@import("rc_readonly_calls.zig").version);
    const readonly = try @import("rc_readonly_calls.zig").identity(&catalog, program.functions, program.functions[index], runtime.identity());
    hash.update(&.{@intFromBool(readonly != null)});
    if (readonly) |identity| hash.update(&identity);
    for (program.functions[index].scope.instructions) |instruction| {
        if (instruction.op != .call) continue;
        const callee = program.functions[@backingInt(instruction.op.call)];
        var length: [8]u8 = undefined;
        std.mem.writeInt(u64, &length, callee.name.len, .little);
        hash.update(&length);
        hash.update(callee.name);
        const proof = try @import("rc_calls.zig").borrowedIn(allocator, &catalog, program.functions, callee, runtime.identity());
        hash.update(&.{@intFromBool(proof != null)});
        if (proof) |certificate| {
            var parameter: [4]u8 = undefined;
            std.mem.writeInt(u32, &parameter, certificate.parameter, .little);
            hash.update(&parameter);
            hash.update(&certificate.shape_identity);
            hash.update(&certificate.dependency_identity);
        }
    }
    var result: fragments.Digest = undefined;
    hash.final(&result);
    return result;
}
