//! Explicit noalloc contracts checked against unoptimized, ownership-expanded Core.
const std = @import("std");
const language = @import("selka");
const ir = @import("ir.zig");
const cost = @import("cost.zig");
const passes = @import("passes.zig");
const build = @import("build.zig");

/// A static may-allocate site, including unresolved foreign/callback calls.
pub const Violation = struct { function: []const u8, callee: []const u8, span: u32, unresolved: bool, unsupported: ?[]const u8 = null };

/// One diagnostic owner shared by frontend CLI and Core Session rendering.
pub fn diagnostic(a: std.mem.Allocator, failure: Violation) std.mem.Allocator.Error!language.diagnostic.Diagnostic {
    const message = if (failure.unsupported) |reason|
        try std.fmt.allocPrint(a, "cannot verify allocation contract of {s}: Core does not support {s}", .{ failure.function, reason })
    else
        try std.fmt.allocPrint(a, "allocation contract of {s} is exceeded by {s}: static Core site may allocate{s}", .{ failure.function, failure.callee, if (failure.unresolved) " (unresolved call)" else "" });
    return .{ .severity = .err, .code = "E_CORE_ALLOCATION_BOUND", .span = .{ .start = failure.span, .end = failure.span }, .message = message };
}

/// Check all explicitly written noalloc bounds in a built module without changing it.
/// Scratch ownership runs before any release optimization, even for release builds.
pub fn validate(a: std.mem.Allocator, program: language.typed.Program, source: language.source.Source, module: *const ir.Module) std.mem.Allocator.Error!?Violation {
    var scratch = std.heap.ArenaAllocator.init(a);
    defer scratch.deinit();
    const temporary = scratch.allocator();
    var owned = try snapshot(temporary, module);
    _ = try passes.debug(temporary, &owned);
    return validateOwned(temporary, program, source, &owned);
}

fn validateOwned(a: std.mem.Allocator, program: language.typed.Program, source: language.source.Source, module: *const ir.Module) std.mem.Allocator.Error!?Violation {
    const summaries = try summarize(a, program, module);
    for (module.functions.items, 0..) |function, index| {
        if (function.signature.linkage != .internal) continue;
        for (program.functions) |source_function| {
            if (source_function.declaration.start != function.span or !std.mem.eql(u8, source_function.name, function.name)) continue;
            const bound = source_function.policy.effect_bound orelse break;
            if (!language.effect_set.coreAllocationBound(source, bound)) break;
            if (summaries[index]) |failure| return .{ .function = function.name, .callee = failure.callee, .span = failure.span, .unresolved = failure.unresolved, .unsupported = failure.unsupported };
            break;
        }
    }
    return null;
}

/// Check unused concrete bounded functions as well as executable roots.
/// All roots share one lowering and one ownership pass. Unsupported lowering is
/// retried per root solely to attribute the unverifiable contract precisely.
pub fn checkProgram(a: std.mem.Allocator, program: language.typed.Program, source: language.source.Source) std.mem.Allocator.Error!?Violation {
    var scratch = std.heap.ArenaAllocator.init(a);
    defer scratch.deinit();
    const temporary = scratch.allocator();
    var roots: std.ArrayList(language.typed.FunctionId) = .empty;
    for (program.functions, 0..) |function, index| {
        const bound = function.policy.effect_bound orelse continue;
        if (!language.effect_set.coreAllocationBound(source, bound) or function.policy.c_abi or function.policy.host != null) continue;
        try roots.append(temporary, @fromBackingInt(@intCast(index)));
    }
    if (roots.items.len == 0) return null;
    var refusal: build.Refusal = .{};
    var module = build.buildRootsSource(temporary, program, roots.items, source, &refusal) catch |err| switch (err) {
        error.Unsupported => {
            for (roots.items) |root| {
                _ = build.buildRootsSource(temporary, program, &.{root}, source, &refusal) catch |individual| switch (individual) {
                    error.OutOfMemory => return error.OutOfMemory,
                    error.Unsupported => {
                        const function = program.functions[@backingInt(root)];
                        return .{ .function = function.name, .callee = function.name, .span = refusal.span, .unresolved = true, .unsupported = try a.dupe(u8, refusal.reason) };
                    },
                };
            }
            unreachable;
        },
        error.OutOfMemory => return error.OutOfMemory,
    };
    _ = try passes.debug(temporary, &module);
    if (try validateOwned(temporary, program, source, &module)) |failure| return .{
        .function = try a.dupe(u8, failure.function),
        .callee = try a.dupe(u8, failure.callee),
        .span = failure.span,
        .unresolved = failure.unresolved,
        .unsupported = failure.unsupported,
    };
    return null;
}

/// Shared call-graph fixed point. Reverse edges propagate each first witness
/// once, so many explicit bounds reuse the same static classification work.
fn summarize(a: std.mem.Allocator, program: language.typed.Program, module: *const ir.Module) std.mem.Allocator.Error![]?Violation {
    const count = module.functions.items.len;
    const failures = try a.alloc(?Violation, count);
    @memset(failures, null);
    const parents = try a.alloc(std.ArrayList(usize), count);
    @memset(parents, .empty);
    var pending: std.ArrayList(usize) = .empty;
    for (module.functions.items, 0..) |*function, index| {
        for (program.functions) |source_function| {
            if (source_function.declaration.start != function.span or !std.mem.eql(u8, source_function.name, function.name)) continue;
            const body = program.statements[@backingInt(source_function.scope.body)];
            if (body.terminates and body.data == .block and body.data.block.len == 0) {
                failures[index] = .{ .function = function.name, .callee = function.name, .span = function.span, .unresolved = true, .unsupported = "summary body without allocation proof" };
                try pending.append(a, index);
            }
            break;
        }
        for (function.blocks.items) |block| for (block.insts.items) |ref| {
            const inst = function.inst(ref);
            const allocation = cost.allocation(module, function, inst);
            if (allocation != .never and failures[index] == null) {
                failures[index] = .{ .function = function.name, .callee = function.name, .span = inst.span, .unresolved = allocation == .unresolved };
                try pending.append(a, index);
            }
            if (internalTarget(module, function, inst)) |callee| try parents[callee].append(a, index);
        };
    }
    while (pending.pop()) |callee| for (parents[callee].items) |caller| {
        if (failures[caller] == null) {
            failures[caller] = failures[callee];
            try pending.append(a, caller);
        }
    };
    return failures;
}

fn internalTarget(module: *const ir.Module, function: *const ir.Function, inst: ir.Inst) ?usize {
    const target: ?usize = switch (inst.op) {
        .call => inst.a.index(),
        .call_indirect => blk: {
            const value = function.inst(function.resolve(inst.a));
            break :blk if (value.op == .func_ref) @intCast(value.data) else null;
        },
        else => null,
    };
    const index = target orelse return null;
    return if (index < module.functions.items.len and module.functions.items[index].signature.linkage == .internal) index else null;
}

/// Visit every block, including disconnected/cold blocks, and every internal callee.
/// A visited set terminates mutually recursive graphs without losing later sites.
pub fn witness(a: std.mem.Allocator, module: *const ir.Module, root: usize) std.mem.Allocator.Error!?Violation {
    const seen = try a.alloc(bool, module.functions.items.len);
    defer a.free(seen);
    @memset(seen, false);
    var pending: std.ArrayList(usize) = .empty;
    defer pending.deinit(a);
    try pending.append(a, root);
    while (pending.pop()) |index| {
        if (seen[index]) continue;
        seen[index] = true;
        const function = &module.functions.items[index];
        for (function.blocks.items) |block| for (block.insts.items) |ref| {
            const inst = function.inst(ref);
            const allocation = cost.allocation(module, function, inst);
            if (allocation != .never) return .{ .function = module.functions.items[root].name, .callee = function.name, .span = inst.span, .unresolved = allocation == .unresolved };
            const target: ?usize = switch (inst.op) {
                .call => inst.a.index(),
                .call_indirect => blk: {
                    const value = function.inst(function.resolve(inst.a));
                    break :blk if (value.op == .func_ref) @intCast(value.data) else null;
                },
                else => null,
            };
            if (target) |callee| if (callee < seen.len and module.functions.items[callee].signature.linkage == .internal and !seen[callee]) try pending.append(a, callee);
        };
    }
    return null;
}

/// Copy mutable ownership buffers; interned types and immutable names are shared.
fn snapshot(a: std.mem.Allocator, module: *const ir.Module) std.mem.Allocator.Error!ir.Module {
    var result = module.*;
    result.functions = .empty;
    try result.functions.appendSlice(a, module.functions.items);
    for (result.functions.items) |*function| {
        function.insts = .empty;
        function.blocks = .empty;
        function.extra = .empty;
        function.loops = .empty;
    }
    for (result.functions.items, module.functions.items) |*function, original| {
        try function.insts.appendSlice(a, original.insts.items);
        try function.extra.appendSlice(a, original.extra.items);
        try function.loops.appendSlice(a, original.loops.items);
        try function.blocks.appendSlice(a, original.blocks.items);
        for (function.blocks.items) |*block| {
            const original_insts = block.insts.items;
            const original_preds = block.preds.items;
            block.insts = .empty;
            block.preds = .empty;
            try block.insts.appendSlice(a, original_insts);
            try block.preds.appendSlice(a, original_preds);
        }
    }
    return result;
}
