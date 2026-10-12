//! Always-on ownership-marker validation, including ordinary SSA control flow.
const std = @import("std");
const ir = @import("ir.zig");
const selection = @import("borrow_selection.zig");
const providers = @import("aggregate_provider.zig");
const contexts = @import("borrowed_provider.zig");
const verify = @import("verify_ir.zig");

pub const Error = std.mem.Allocator.Error || selection.Error;

fn present(module: *const ir.Module, function: *const ir.Function) Error!bool {
    for (function.insts.items) |inst| {
        if (inst.op != .call) continue;
        if (inst.a == .none or inst.a.index() >= module.functions.items.len) return error.UnsupportedInstruction;
        const name = module.functions.items[inst.a.index()].name;
        if (selection.reserved(name) or std.mem.startsWith(u8, name, providers.prefix)) return true;
    }
    return false;
}

/// Check each marker-bearing function once, never once per marker. Local shape
/// checks run first so malformed operand tables cannot reach the general verifier.
pub fn validate(a: std.mem.Allocator, module: *const ir.Module, function: *const ir.Function) Error!void {
    if (!try present(module, function) and !contexts.contains(module, function)) return;
    // Its preflight checks generic block, type and operand bounds for every
    // marker family before a local proof or the verifier follows those tables.
    try providers.validate(module, function);
    try contexts.validate(a, module, function);
    try selection.validate(a, module, function);
    // The general verifier owns scratch tables for one invocation, not the
    // caller's lifetime. Some ownership/cache callers pass a backing allocator.
    var scratch = std.heap.ArenaAllocator.init(a);
    defer scratch.deinit();
    var failure: verify.Failure = .{};
    verify.verifyFunction(scratch.allocator(), module, function, &failure) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.InvalidIr => return error.UnsupportedInstruction,
    };
}

/// Fresh bodies and declarations receive the same proof as decoded cache bodies.
pub fn validateModule(a: std.mem.Allocator, module: *const ir.Module) Error!void {
    for (module.functions.items) |*function| {
        _ = try providers.marker(module, function);
        _ = try contexts.declaration(module, function);
        _ = try selection.declaration(module, function);
        try validate(a, module, function);
    }
}
