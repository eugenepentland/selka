//! Explicit noalloc contracts checked against unoptimized, ownership-expanded Core.
const std = @import("std");
const language = @import("mylang");
const ir = @import("ir.zig");
const cost = @import("cost.zig");
const passes = @import("passes.zig");
const build = @import("build.zig");

/// The source ownership and runtime ABI whose allocation sites are inspected.
pub const Ownership = struct { single_owner: bool = false, zero_rc: bool = false };

const selection_refusal = "invalid borrowed selection ownership marker";

/// A static may-allocate site, including unresolved foreign/callback calls.
pub const Violation = struct { function: []const u8, callee: []const u8, span: u32, unresolved: bool, unsupported: ?[]const u8 = null, bound: language.source.Span = .{ .start = 0, .end = 0 } };

/// One diagnostic owner shared by frontend CLI and Core Session rendering.
pub fn diagnostic(a: std.mem.Allocator, failure: Violation) std.mem.Allocator.Error!language.diagnostic.Diagnostic {
    const message = if (failure.unsupported) |reason|
        try std.fmt.allocPrint(a, "cannot verify allocation contract of {s}: Core does not support {s}", .{ failure.function, reason })
    else
        try std.fmt.allocPrint(a, "allocation contract of {s} is exceeded by {s}: static Core site may allocate{s}", .{ failure.function, failure.callee, if (failure.unresolved) " (unresolved call)" else "" });
    return .{ .severity = .warning, .code = "W_NOALLOC_ALLOCATES", .span = .{ .start = failure.span, .end = failure.span }, .message = message, .related = .{ .span = failure.bound, .message = "noalloc promise declared here" } };
}

/// Check all explicitly written noalloc bounds in a built module without changing it.
/// Scratch ownership runs before any release optimization, even for release builds.
pub fn validate(a: std.mem.Allocator, program: language.typed.Program, source: language.source.Source, module: *const ir.Module) std.mem.Allocator.Error!?Violation {
    var scratch = std.heap.ArenaAllocator.init(a);
    defer scratch.deinit();
    const temporary = scratch.allocator();
    var owned = try snapshot(temporary, module);
    _ = passes.debug(temporary, &owned) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.Unsupported => return ownershipRefusal(program, source),
    };
    return validateOwned(temporary, program, source, &owned);
}

/// A malformed ownership marker is an unresolved contract, never a noalloc proof.
fn ownershipRefusal(program: language.typed.Program, source: language.source.Source) Violation {
    for (program.functions) |function| {
        const bound = function.policy.effect_bound orelse continue;
        if (!language.effect_set.coreAllocationBound(source, bound)) continue;
        return .{ .function = function.name, .callee = function.name, .span = @intCast(function.declaration.start), .unresolved = true, .unsupported = selection_refusal, .bound = bound.span };
    }
    return .{ .function = "<ownership>", .callee = "<ownership>", .span = 0, .unresolved = true, .unsupported = selection_refusal };
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

/// Return the first bounded-function witness for callers inspecting a single contract.
pub fn checkProgram(a: std.mem.Allocator, program: language.typed.Program, source: language.source.Source) std.mem.Allocator.Error!?Violation {
    const failures = try collectProgram(a, program, source);
    defer a.free(failures);
    return if (failures.len == 0) null else failures[0];
}

/// Collect a witness for every violated concrete noalloc declaration, including unused roots.
/// Unsupported lowering is retried per root so other contracts still receive diagnostics.
pub fn collectProgram(a: std.mem.Allocator, program: language.typed.Program, source: language.source.Source) std.mem.Allocator.Error![]Violation {
    return collectProgramWithOwnership(a, program, source, .{});
}

/// Inspect the selected lowering contract, including its explicit-copy allocations.
pub fn collectProgramWithOwnership(a: std.mem.Allocator, program: language.typed.Program, source: language.source.Source, ownership: Ownership) std.mem.Allocator.Error![]Violation {
    var scratch = std.heap.ArenaAllocator.init(a);
    defer scratch.deinit();
    const temporary = scratch.allocator();
    var roots: std.ArrayList(language.typed.FunctionId) = .empty;
    for (program.functions, 0..) |function, index| {
        const bound = function.policy.effect_bound orelse continue;
        if (!language.effect_set.coreAllocationBound(source, bound) or function.policy.c_abi or function.policy.host != null) continue;
        try roots.append(temporary, @fromBackingInt(@intCast(index)));
    }
    var failures: std.ArrayList(Violation) = .empty;
    if (roots.items.len != 0) try collectRoots(temporary, .{ .program = program, .source = source, .ownership = ownership }, roots.items, &failures);
    // Core names and refusal reasons belong to the scratch arena; copy all escaping text.
    const result = try a.dupe(Violation, failures.items);
    for (result) |*failure| {
        failure.function = try a.dupe(u8, failure.function);
        failure.callee = try a.dupe(u8, failure.callee);
        if (failure.unsupported) |reason| failure.unsupported = try a.dupe(u8, reason);
    }
    return result;
}

const CheckedSource = struct { program: language.typed.Program, source: language.source.Source, ownership: Ownership };

fn collectRoots(a: std.mem.Allocator, checked: CheckedSource, roots: []const language.typed.FunctionId, failures: *std.ArrayList(Violation)) std.mem.Allocator.Error!void {
    var refusal: build.Refusal = .{};
    var module = build.buildRootsCached(a, roots, .{
        .program = checked.program,
        .source = checked.source,
        .single_owner = checked.ownership.single_owner,
        .zero_rc = checked.ownership.zero_rc,
    }, &refusal, null) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.CacheMiss => unreachable,
        error.Unsupported => {
            if (roots.len > 1) {
                for (roots) |root| try collectRoots(a, checked, &.{root}, failures);
            } else {
                const function = checked.program.functions[@backingInt(roots[0])];
                try appendUnique(a, failures, .{ .function = function.name, .callee = function.name, .span = refusal.span, .unresolved = true, .unsupported = refusal.reason, .bound = function.policy.effect_bound.?.span });
            }
            return;
        },
    };
    _ = passes.debug(a, &module) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.Unsupported => {
            if (roots.len > 1) {
                for (roots) |root| try collectRoots(a, checked, &.{root}, failures);
            } else {
                const function = checked.program.functions[@backingInt(roots[0])];
                try appendUnique(a, failures, .{
                    .function = function.name,
                    .callee = function.name,
                    .span = @intCast(function.declaration.start),
                    .unresolved = true,
                    .unsupported = selection_refusal,
                    .bound = function.policy.effect_bound.?.span,
                });
            }
            return;
        },
    };
    const summaries = try summarize(a, checked.program, &module);
    for (module.functions.items, 0..) |function, index| {
        const failure = summaries[index] orelse continue;
        if (function.signature.linkage != .internal) continue;
        for (checked.program.functions) |source_function| {
            if (source_function.declaration.start != function.span or !std.mem.eql(u8, source_function.name, function.name)) continue;
            const bound = source_function.policy.effect_bound orelse break;
            if (!language.effect_set.coreAllocationBound(checked.source, bound)) break;
            var diagnostic_failure = failure;
            diagnostic_failure.function = function.name;
            diagnostic_failure.bound = bound.span;
            try appendUnique(a, failures, diagnostic_failure);
            break;
        }
    }
}

/// A root retry may include a bounded callee already seen through another root.
fn appendUnique(a: std.mem.Allocator, failures: *std.ArrayList(Violation), failure: Violation) std.mem.Allocator.Error!void {
    for (failures.items) |existing| {
        if (existing.bound.start == failure.bound.start and std.mem.eql(u8, existing.function, failure.function)) return;
    }
    try failures.append(a, failure);
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
