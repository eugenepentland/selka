//! Explicit noalloc contracts checked against the Core body a build emits for them.
//!
//! A promise is judged on the body the program that is built runs: the function lowered as a callee (borrowed
//! view parameters, `build.Input.callee_roots`), through the same lowering passes and ownership expansion a
//! debug build runs. Lowering it as a root, with owned `str` parameters, would judge a different body (F19).
const std = @import("std");
const language = @import("selka");
const ir = @import("ir.zig");
const cost = @import("cost.zig");
const passes = @import("passes.zig");
const build = @import("build.zig");

const selection_refusal = "invalid borrowed selection ownership marker";

/// A static may-allocate site, including unresolved foreign/callback calls.
pub const Violation = struct { function: []const u8, callee: []const u8, span: u32, unresolved: bool, unsupported: ?[]const u8 = null, bound: language.source.Span = .{ .start = 0, .end = 0 } };

/// One diagnostic owner shared by frontend CLI and Core Session rendering.
pub fn diagnostic(a: std.mem.Allocator, failure: Violation) std.mem.Allocator.Error!language.diagnostic.Diagnostic {
    const message = if (failure.unsupported) |reason|
        try std.fmt.allocPrint(a, "cannot verify allocation contract of {s}: Core does not support {s}", .{ failure.function, reason })
    else
        try std.fmt.allocPrint(a, "allocation contract of {s} is exceeded by {s}: static Core site may allocate{s}", .{ failure.function, failure.callee, if (failure.unresolved) " (unresolved call)" else "" });
    var item = language.diagnostic.ownership(.{ .code = "E_NOALLOC_ALLOCATES", .rule = .C3 }, .{ .start = failure.span, .end = failure.span }, message);
    item.related = .{ .span = failure.bound, .message = "noalloc promise declared here" };
    return item;
}

/// Check all explicitly written noalloc bounds in a built module without changing it.
/// Scratch ownership runs before any release optimization, even for release builds.
pub fn validate(a: std.mem.Allocator, program: language.typed.Program, _: language.source.Source, module: *const ir.Module) std.mem.Allocator.Error!?Violation {
    var scratch = std.heap.ArenaAllocator.init(a);
    defer scratch.deinit();
    const temporary = scratch.allocator();
    var owned = try snapshot(temporary, module);
    _ = passes.debug(temporary, &owned) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.Unsupported => return ownershipRefusal(program),
    };
    return validateOwned(temporary, program, &owned);
}

/// A malformed ownership marker is an unresolved contract, never a noalloc proof.
fn ownershipRefusal(program: language.typed.Program) Violation {
    for (program.functions) |function| {
        const bound = function.policy.noalloc orelse continue;
        return .{ .function = function.name, .callee = function.name, .span = @intCast(function.declaration.start), .unresolved = true, .unsupported = selection_refusal, .bound = bound };
    }
    return .{ .function = "<ownership>", .callee = "<ownership>", .span = 0, .unresolved = true, .unsupported = selection_refusal };
}

fn validateOwned(a: std.mem.Allocator, program: language.typed.Program, module: *const ir.Module) std.mem.Allocator.Error!?Violation {
    const summaries = try summarize(a, program, module);
    for (module.functions.items, 0..) |function, index| {
        if (function.signature.linkage != .internal) continue;
        for (program.functions) |source_function| {
            if (source_function.declaration.start != function.span or !std.mem.eql(u8, source_function.name, function.name)) continue;
            const bound = source_function.policy.noalloc orelse break;
            if (summaries[index]) |failure| return .{ .function = function.name, .callee = failure.callee, .span = failure.span, .unresolved = failure.unresolved, .unsupported = failure.unsupported, .bound = bound };
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
    var scratch = std.heap.ArenaAllocator.init(a);
    defer scratch.deinit();
    const temporary = scratch.allocator();
    var roots: std.ArrayList(language.typed.FunctionId) = .empty;
    for (program.functions, 0..) |function, index| {
        if (function.policy.noalloc == null) continue;
        if (function.policy.c_abi or function.policy.host != null) continue;
        try roots.append(temporary, @fromBackingInt(@intCast(index)));
    }
    var failures: std.ArrayList(Violation) = .empty;
    if (roots.items.len != 0) try collectRoots(temporary, .{ .program = program, .source = source }, roots.items, &failures, null);
    // Core names and refusal reasons belong to the scratch arena; copy all escaping text.
    const result = try a.dupe(Violation, failures.items);
    for (result) |*failure| {
        failure.function = try a.dupe(u8, failure.function);
        failure.callee = try a.dupe(u8, failure.callee);
        if (failure.unsupported) |reason| failure.unsupported = try a.dupe(u8, reason);
    }
    return result;
}

/// A function Core reached from a root: its name and the start of its declaration in the merged source.
pub const Reached = struct { name: []const u8, span: u32 };

/// What the allocation check concluded about one `@noalloc` root and the functions the conclusion depends on: the root itself and
/// every function Core reaches from it through internal calls (the closure the promise is judged over).
pub const Root = struct { function: language.typed.FunctionId, failure: ?Violation, reached: []const Reached };

/// The conclusion about each `@noalloc` root of `program`, in program order, with the closure each was judged over. The failures are
/// the ones `collectProgram` reports; a root whose Core could not be built or checked has a failure and no closure. Everything is
/// allocated in `a`.
pub fn analyzeProgram(a: std.mem.Allocator, program: language.typed.Program, source: language.source.Source) std.mem.Allocator.Error![]Root {
    var scratch = std.heap.ArenaAllocator.init(a);
    defer scratch.deinit();
    const temporary = scratch.allocator();
    var roots: std.ArrayList(language.typed.FunctionId) = .empty;
    for (program.functions, 0..) |function, index| {
        if (function.policy.noalloc == null) continue;
        if (function.policy.c_abi or function.policy.host != null) continue;
        try roots.append(temporary, @fromBackingInt(@intCast(index)));
    }
    var failures: std.ArrayList(Violation) = .empty;
    var found: std.ArrayList(Root) = .empty;
    if (roots.items.len != 0) try collectRoots(temporary, .{ .program = program, .source = source }, roots.items, &failures, &found);
    const result = try a.alloc(Root, found.items.len);
    for (found.items, result) |root, *slot| {
        const reached = try a.alloc(Reached, root.reached.len);
        for (root.reached, reached) |one, *copy| copy.* = .{ .name = try a.dupe(u8, one.name), .span = one.span };
        slot.* = .{ .function = root.function, .failure = null, .reached = reached };
        if (root.failure) |failure| {
            var copy = failure;
            copy.function = try a.dupe(u8, failure.function);
            copy.callee = try a.dupe(u8, failure.callee);
            if (failure.unsupported) |reason| copy.unsupported = try a.dupe(u8, reason);
            slot.failure = copy;
        }
    }
    return result;
}

const CheckedSource = struct { program: language.typed.Program, source: language.source.Source };

/// Every Core function reachable from `root` through internal calls and function references, `root` included, as the check
/// follows them (`witness`).
fn reachedFrom(a: std.mem.Allocator, module: *const ir.Module, root: usize, out: *std.ArrayList(Reached)) std.mem.Allocator.Error!void {
    const seen = try a.alloc(bool, module.functions.items.len);
    @memset(seen, false);
    var pending: std.ArrayList(usize) = .empty;
    try pending.append(a, root);
    while (pending.pop()) |index| {
        if (seen[index]) continue;
        seen[index] = true;
        const function = &module.functions.items[index];
        try out.append(a, .{ .name = function.name, .span = function.span });
        for (function.blocks.items) |block| for (block.insts.items) |ref| {
            if (internalTarget(module, function, function.inst(ref))) |callee| if (!seen[callee]) try pending.append(a, callee);
        };
    }
}

/// The index in `module` of the Core function lowered from the typed function `source_function`, or null.
fn coreIndexOf(module: *const ir.Module, source_function: language.typed.Function) ?usize {
    for (module.functions.items, 0..) |function, index| {
        if (function.signature.linkage != .internal) continue;
        if (source_function.declaration.start == function.span and std.mem.eql(u8, source_function.name, function.name)) return index;
    }
    return null;
}

fn collectRoots(a: std.mem.Allocator, checked: CheckedSource, roots: []const language.typed.FunctionId, failures: *std.ArrayList(Violation), analysis: ?*std.ArrayList(Root)) std.mem.Allocator.Error!void {
    var refusal: build.Refusal = .{};
    var module = build.buildRootsCached(a, roots, .{
        .program = checked.program,
        .source = checked.source,
        .callee_roots = true,
    }, &refusal, null) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.CacheMiss => unreachable,
        error.Unsupported => {
            if (roots.len > 1) {
                for (roots) |root| try collectRoots(a, checked, &.{root}, failures, analysis);
            } else {
                const function = checked.program.functions[@backingInt(roots[0])];
                const failure: Violation = .{ .function = function.name, .callee = function.name, .span = refusal.span, .unresolved = true, .unsupported = refusal.reason, .bound = function.policy.noalloc.? };
                try appendUnique(a, failures, failure);
                if (analysis) |list| try list.append(a, .{ .function = roots[0], .failure = failure, .reached = &.{} });
            }
            return;
        },
    };
    _ = passes.debug(a, &module) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.Unsupported => {
            if (roots.len > 1) {
                for (roots) |root| try collectRoots(a, checked, &.{root}, failures, analysis);
            } else {
                const function = checked.program.functions[@backingInt(roots[0])];
                const failure: Violation = .{
                    .function = function.name,
                    .callee = function.name,
                    .span = @intCast(function.declaration.start),
                    .unresolved = true,
                    .unsupported = selection_refusal,
                    .bound = function.policy.noalloc.?,
                };
                try appendUnique(a, failures, failure);
                if (analysis) |list| try list.append(a, .{ .function = roots[0], .failure = failure, .reached = &.{} });
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
            const bound = source_function.policy.noalloc orelse break;
            var diagnostic_failure = failure;
            diagnostic_failure.function = function.name;
            diagnostic_failure.bound = bound;
            try appendUnique(a, failures, diagnostic_failure);
            break;
        }
    }
    const list = analysis orelse return;
    for (roots) |root| {
        const source_function = checked.program.functions[@backingInt(root)];
        const index = coreIndexOf(&module, source_function) orelse {
            const missing: Violation = .{
                .function = source_function.name,
                .callee = source_function.name,
                .span = @intCast(source_function.declaration.start),
                .unresolved = true,
                .unsupported = "a root with no Core function",
                .bound = source_function.policy.noalloc.?,
            };
            try list.append(a, .{ .function = root, .failure = missing, .reached = &.{} });
            continue;
        };
        var reached: std.ArrayList(Reached) = .empty;
        try reachedFrom(a, &module, index, &reached);
        var failure: ?Violation = null;
        if (summaries[index]) |found| {
            var named = found;
            named.function = source_function.name;
            named.bound = source_function.policy.noalloc.?;
            failure = named;
        }
        try list.append(a, .{ .function = root, .failure = failure, .reached = reached.items });
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
            const empty = body.terminates and body.data == .block and body.data.block.len == 0;
            if (empty and !registersOperation(module, source_function, function)) {
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

/// Whether `function` is a `registers` operation (MCU-B1): a `builtin func` whose empty checked body Core replaced with
/// calls of the simulated bank's runtime functions only. Its built instructions are its proof, judged like any body's:
/// the reads and writes are on the audited list and `simulated()` is not (`cost.zig`). Every other empty body stays
/// unresolved.
fn registersOperation(module: *const ir.Module, source_function: language.typed.Function, function: *const ir.Function) bool {
    if (!source_function.policy.builtin) return false;
    var calls: usize = 0;
    for (function.blocks.items) |block| for (block.insts.items) |ref| {
        const inst = function.inst(ref);
        if (inst.op != .call) continue;
        const index = inst.a.index();
        if (index >= module.functions.items.len) return false;
        const callee = module.functions.items[index];
        if (callee.signature.linkage != .runtime_c or !std.mem.startsWith(u8, callee.name, @import("build_registers.zig").runtime_prefix)) return false;
        calls += 1;
    };
    return calls == 1;
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

/// Check an explicit source promise through the ownership-expanded Core path.
fn expectNoalloc(a: std.mem.Allocator, source: []const u8, allocates: bool) !void {
    var compilation = try language.Compilation.init(a, "noalloc-attribute.selka", source);
    defer compilation.deinit();
    try compilation.check();
    const failures = try collectProgram(a, compilation.program.?, compilation.src);
    defer {
        for (failures) |failure| {
            a.free(failure.function);
            a.free(failure.callee);
            if (failure.unsupported) |reason| a.free(reason);
        }
        a.free(failures);
    }
    try std.testing.expectEqual(allocates, failures.len != 0);
}

// spec: NOALLOC-ATTRIBUTE-1
test "noalloc attribute checks allocation independently of capability signatures" {
    try expectNoalloc(std.testing.allocator, "@noalloc\nfunc subject(value: int) -> int:\n    return value + 1\n\nfunc main() -> int:\n    return subject(4)\n", false);
    try expectNoalloc(std.testing.allocator, "@noalloc\nfunc subject() -> int:\n    mut values = [1, 2]\n    return len(values)\n\nfunc main() -> int:\n    return subject()\n", true);
}

// spec-case: NOALLOC-ATTRIBUTE-1
test "noalloc attribute follows cold allocating callees" {
    try expectNoalloc(std.testing.allocator, "func allocating() -> int:\n    mut values = [1]\n    return len(values)\n\n@noalloc\n" ++
        "func subject(flag: bool) -> int:\n    if flag:\n        return allocating()\n    return 0\n\n" ++
        "func main() -> int:\n    return subject(False)\n", true);
}
