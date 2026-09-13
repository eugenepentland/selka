//! Program-bound host registrations for checked bytecode, with no symbol loading.
const std = @import("std");
const bc = @import("bytecode.zig");
const typed = @import("typed.zig");
const host = @import("host_functions.zig");
/// Registration errors plus invalid bytecode or a different compiled program.
pub const Error = host.Error || error{ InternalError, HostProgramMismatch, ExternRequiresQbe };
/// Owns registry metadata and borrows one immutable compiled program and host contexts.
pub const Registry = struct {
    registry: host.Registry,
    program: bc.Program,
    ids: []const ?host.Id,
    /// Extract only explicit host declarations from independently validated bytecode.
    pub fn init(allocator: std.mem.Allocator, program: bc.Program) Error!Registry {
        try bc.validate(allocator, program);
        var scratch = std.heap.ArenaAllocator.init(allocator);
        defer scratch.deinit();
        const temporary = scratch.allocator();
        var declarations: std.ArrayList(host.Declaration) = .empty;
        for (program.functions) |function| {
            if (function.policy.c_abi) return error.ExternRequiresQbe;
            if (function.policy.host == null) continue;
            const parameters = try temporary.alloc(host.Parameter, function.signature.parameter_count);
            for (parameters, function.scope.locals) |*parameter, local| parameter.* = .{ .ty = local.ty };
            try declarations.append(temporary, .{ .name = function.name, .signature = .{
                .parameters = parameters,
                .result = .{ .ty = function.signature.return_type },
                .effects = function.policy.effects,
            } });
        }
        var registry = try host.Registry.init(allocator, program.records, declarations.items);
        errdefer registry.deinit();
        const ids = try registry.arena.allocator().alloc(?host.Id, program.functions.len);
        for (program.functions, ids) |function, *id| id.* = if (function.policy.host != null) try registry.resolve(function.name) else null;
        return .{ .registry = registry, .program = program, .ids = ids };
    }
    /// Release registration metadata after execution; the compilation must outlive this registry.
    pub fn deinit(self: *Registry) void {
        self.registry.deinit();
    }
    /// Inspect a compiler-resolved contract when building a trusted wrapper for this program.
    pub fn contract(self: *const Registry, name: []const u8) Error!host.Signature {
        const id = try self.registry.resolve(name);
        return self.registry.entries[@backingInt(id)].declaration.signature;
    }
    /// Install a wrapper for an explicit declaration, using exact types and effect grants.
    pub fn register(self: *Registry, name: []const u8, binding: host.Binding, grants: @import("effect_set.zig").Mask) Error!void {
        try self.registry.register(name, binding, grants);
    }
    /// Verify program identity and every link before starting any guest operation.
    pub fn begin(self: *Registry, allocator: std.mem.Allocator, program: bc.Program, limits: host.Limits) Error!host.Session {
        if (program.main != self.program.main or program.functions.ptr != self.program.functions.ptr or program.functions.len != self.ids.len) return error.HostProgramMismatch;
        if (program.records.ptr != self.program.records.ptr or program.records.len != self.program.records.len) return error.HostProgramMismatch;
        for (program.functions, self.ids) |function, id| {
            if (function.policy.host == null) {
                if (id != null) return error.HostProgramMismatch;
                continue;
            }
            const declaration = self.registry.entries[@backingInt(id orelse return error.HostProgramMismatch)].declaration;
            if (!std.mem.eql(u8, declaration.name, function.name)) return error.HostProgramMismatch;
            const signature = declaration.signature;
            if (signature.effects != function.policy.effects or signature.result.ty != function.signature.return_type or signature.parameters.len != function.signature.parameter_count) return error.HostProgramMismatch;
            if (function.scope.locals.len != signature.parameters.len) return error.HostProgramMismatch;
            for (signature.parameters, function.scope.locals) |parameter, local| if (parameter.ty != local.ty) return error.HostProgramMismatch;
        }
        return self.registry.begin(allocator, limits);
    }
    /// Resolve a checked guest callee through its program-local declaration mapping.
    pub fn resolve(self: *const Registry, function: typed.FunctionId) Error!host.Id {
        if (@backingInt(function) >= self.ids.len) return error.HostUnknownFunction;
        return self.ids[@backingInt(function)] orelse error.HostUnknownFunction;
    }
};
