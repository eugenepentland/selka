//! Always-on ownership-marker validation, including ordinary SSA control flow.
const std = @import("std");
const ir = @import("ir.zig");
const selection = @import("borrow_selection.zig");
const verify = @import("verify_ir.zig");

pub const Error = std.mem.Allocator.Error || selection.Error;

fn present(module: *const ir.Module, function: *const ir.Function) bool {
    for (function.insts.items) |inst| {
        if (inst.op != .call or inst.a.index() >= module.functions.items.len) continue;
        if (std.mem.startsWith(u8, module.functions.items[inst.a.index()].name, selection.prefix)) return true;
    }
    return false;
}

/// Check each marker-bearing function once, never once per marker. Local shape
/// checks run first so malformed operand tables cannot reach the general verifier.
pub fn validate(a: std.mem.Allocator, module: *const ir.Module, function: *const ir.Function) Error!void {
    if (!present(module, function)) return;
    try selection.validate(a, module, function);
    var failure: verify.Failure = .{};
    verify.verifyFunction(a, module, function, &failure) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.InvalidIr => return error.UnsupportedInstruction,
    };
}

/// Fresh bodies and declarations receive the same proof as decoded cache bodies.
pub fn validateModule(a: std.mem.Allocator, module: *const ir.Module) Error!void {
    for (module.functions.items) |*function| {
        _ = try selection.declaration(module, function);
        try validate(a, module, function);
    }
}
