//! Callback adapters preserve each canonical function's selected mut ABI.
const std = @import("std");
const bytecode = @import("bytecode.zig");
const typed = @import("typed.zig");
const abi = @import("mut_abi.zig");
const Span = @import("source.zig").Span;
const prefix = "@mut_callback:";

/// Allocation or an inconsistent callback target can stop adaptation.
pub const Error = error{ OutOfMemory, InternalError };

/// Whether a synthetic function adapts a canonical mut callback target.
pub fn isAdapter(name: []const u8) bool {
    return std.mem.startsWith(u8, name, prefix);
}

/// Resolve a cached adapter value name to its canonical checked target name.
pub fn canonicalName(name: []const u8) []const u8 {
    return if (isAdapter(name)) name[prefix.len..] else name;
}

/// Reserve adapters for checked or cached function-value targets before
/// selective lowering. Input bodies are unchanged and each reserved ID remains
/// stable when `adapt` rewrites subsequently lowered bodies in this catalog.
pub fn prepare(a: std.mem.Allocator, code: bytecode.Program, targets: []const typed.FunctionId) Error!bytecode.Program {
    var builder = try Builder.init(a, code);
    defer builder.deinit();
    for (targets) |target| _ = try builder.reserve(target);
    return builder.program();
}

/// Rewrite function values to storage-ABI adapters where the target still has
/// mut collection payload parameters. Canonical functions and the input program
/// are unchanged; allocate the returned functions and changed bodies in `a`.
/// Imported canonical signatures must be restored before calling this helper.
pub fn adapt(a: std.mem.Allocator, code: bytecode.Program) Error!bytecode.Program {
    var builder = try Builder.init(a, code);
    defer builder.deinit();
    for (code.functions, 0..) |function, index| {
        var changed: ?[]bytecode.Instruction = null;
        for (function.scope.instructions, 0..) |instruction, pc| {
            if (instruction.op != .function_value) continue;
            const target = instruction.op.function_value.function;
            const wrapper = try builder.reserve(target) orelse continue;
            if (changed == null) changed = try a.dupe(bytecode.Instruction, function.scope.instructions);
            changed.?[pc].op.function_value.function = wrapper;
        }
        if (changed) |body| builder.functions.items[index].scope.instructions = body;
    }
    return builder.program();
}

const Builder = struct {
    a: std.mem.Allocator,
    code: bytecode.Program,
    functions: std.ArrayList(bytecode.Function) = .empty,
    wrappers: std.AutoHashMapUnmanaged(typed.FunctionId, typed.FunctionId) = .empty,

    fn init(a: std.mem.Allocator, code: bytecode.Program) Error!Builder {
        var out: Builder = .{ .a = a, .code = code };
        try out.functions.appendSlice(a, code.functions);
        return out;
    }

    fn deinit(self: *Builder) void {
        self.functions.deinit(self.a);
        self.wrappers.deinit(self.a);
    }

    fn reserve(self: *Builder, target: typed.FunctionId) Error!?typed.FunctionId {
        if (@backingInt(target) >= self.code.functions.len) return error.InternalError;
        if (!try needsAdapter(self.code, self.code.functions[@backingInt(target)])) return null;
        const id = try adapter(self.a, self.code, &self.functions, &self.wrappers, target);
        return id;
    }

    fn program(self: *Builder) Error!bytecode.Program {
        return .{ .functions = try self.functions.toOwnedSlice(self.a), .records = self.code.records, .main = self.code.main };
    }
};

fn storageMask(code: bytecode.Program, function: bytecode.Function) Error!u16 {
    const count = function.signature.parameter_count;
    if (count > 16 or count > function.scope.locals.len) return error.InternalError;
    var mask: u16 = 0;
    for (function.signature.declared_mutates) |position| {
        if (position >= count) return error.InternalError;
        if (abi.collection(code.records, function.scope.locals[position].ty)) mask |= @as(u16, 1) << @intCast(position);
    }
    return mask;
}

fn needsAdapter(code: bytecode.Program, function: bytecode.Function) Error!bool {
    const mask = try storageMask(code, function);
    for (0..function.signature.parameter_count) |position| {
        if (mask & (@as(u16, 1) << @intCast(position)) != 0 and !abi.reference(code.records, function, position)) return true;
    }
    return false;
}

fn adapter(a: std.mem.Allocator, code: bytecode.Program, functions: *std.ArrayList(bytecode.Function), wrappers: *std.AutoHashMapUnmanaged(typed.FunctionId, typed.FunctionId), target: typed.FunctionId) Error!typed.FunctionId {
    if (wrappers.get(target)) |known| return known;
    const canonical = code.functions[@backingInt(target)];
    const name = try std.fmt.allocPrint(a, "{s}{s}", .{ prefix, canonical.name });
    for (functions.items) |function| {
        if (!std.mem.eql(u8, function.name, name)) continue;
        if (!try compatible(code, canonical, function)) return error.InternalError;
        try wrappers.put(a, target, function.id);
        return function.id;
    }
    const id: typed.FunctionId = @fromBackingInt(functions.items.len);
    try functions.append(a, try makeAdapter(a, code, canonical, .{ .id = id, .name = name }));
    try wrappers.put(a, target, id);
    return id;
}

fn compatible(code: bytecode.Program, canonical: bytecode.Function, function: bytecode.Function) Error!bool {
    if (function.signature.parameter_count != canonical.signature.parameter_count or function.signature.return_type != canonical.signature.return_type) return false;
    if (function.signature.parameter_count > function.scope.locals.len) return false;
    if (!std.mem.eql(u16, function.signature.declared_mutates, canonical.signature.declared_mutates)) return false;
    if (!typed.ReturnOrigin.eql(function.signature.return_origin, canonical.signature.return_origin)) return false;
    const expected_mask = canonical.signature.inferred.caller_storage | try storageMask(code, canonical);
    if (function.signature.inferred.caller_storage != expected_mask) return false;
    for (function.scope.locals[0..function.signature.parameter_count], canonical.scope.locals[0..canonical.signature.parameter_count]) |actual, expected| {
        if (actual.ty != expected.ty) return false;
    }
    return true;
}

const Identity = struct { id: typed.FunctionId, name: []const u8 };
const synthetic_span: Span = .{ .start = 0, .end = 0 };

fn makeAdapter(a: std.mem.Allocator, code: bytecode.Program, canonical: bytecode.Function, identity: Identity) Error!bytecode.Function {
    const count = canonical.signature.parameter_count;
    const locals = try a.dupe(typed.Local, canonical.scope.locals[0..count]);
    const body = try a.alloc(bytecode.Instruction, count + 2);
    for (locals, 0..) |*local, position| {
        local.usage = .{ .reads = 1 };
        local.ownership = .{ .initialized = true };
        local.origin = .parameter;
        local.declaration = synthetic_span;
        const slot: typed.LocalId = @fromBackingInt(position);
        body[position] = .{ .span = synthetic_span, .op = if (abi.reference(code.records, canonical, position)) .{ .ref_local = slot } else .{ .load_local = slot } };
    }
    body[count] = .{ .span = synthetic_span, .op = .{ .call = canonical.id } };
    body[count + 1] = .{ .span = synthetic_span, .op = .ret };
    var signature = canonical.signature;
    signature.inferred.caller_storage |= try storageMask(code, canonical);
    var policy = canonical.policy;
    policy.host = null;
    policy.c_abi = false;
    policy.conversion = false;
    if (policy.effect_bound) |*bound| bound.span = synthetic_span;
    return .{ .id = identity.id, .name = identity.name, .policy = policy, .signature = signature, .scope = .{ .locals = locals, .instructions = body } };
}
