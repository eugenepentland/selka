//! Closed readonly composition with explicit public borrowed-call routes.
const std = @import("std");
const bytecode = @import("bytecode.zig");
const shapes = @import("rc_shape.zig");
const native = @import("native_types.zig");
const body = @import("rc_readonly_body.zig");
const model = @import("rc_model.zig");
const typed = @import("typed.zig");
const Hash = std.crypto.hash.Blake3;
/// Proof identities bind the exact closed grammar, including call restrictions.
pub const version = "mylang-rc-readonly-calls-v2";
/// A checked direct call must use this independently emitted alternate entry.
pub const Route = struct { pc: usize, target: typed.FunctionId, certificate: model.BorrowCertificate };
/// Complete raw-body proof and its caller-local immutable managed call routes.
pub const Certificate = struct { identity: [32]u8, calls: []const Route };

/// Hash the same complete proof used by emission, including managed routes.
pub fn identity(catalog: *shapes.Catalog, functions: []const bytecode.Function, function: bytecode.Function, abi: []const u8) native.Error!?[32]u8 {
    const proof = (try certify(catalog, functions, function, abi)) orelse return null;
    defer catalog.allocator.free(proof.calls);
    return proof.identity;
}

/// Managed helpers require the public standalone query, never internal Answers.
/// The returned route storage belongs to the catalog allocator's caller.
pub fn certify(catalog: *shapes.Catalog, functions: []const bytecode.Function, function: bytecode.Function, abi: []const u8) native.Error!?Certificate {
    var proof: Proof = .{ .catalog = catalog, .functions = functions, .abi = abi };
    defer proof.memo.routes.deinit(catalog.allocator);
    const digest = (try proof.analyze(function)) orelse return null;
    return .{ .identity = digest, .calls = try proof.memo.routes.toOwnedSlice(catalog.allocator) };
}

const Completed = struct { function: usize, identity: [32]u8 };
const Managed = struct { function: usize, certificate: model.BorrowCertificate };
const Memo = struct {
    entries: [16]Completed = undefined,
    count: usize = 0,
    managed: [16]Managed = undefined,
    managed_count: usize = 0,
    routes: std.ArrayList(Route) = .empty,
    physical: @import("rc_readonly_plan.zig").Budget = .{},
};
const Proof = struct {
    catalog: *shapes.Catalog,
    functions: []const bytecode.Function,
    abi: []const u8,
    active: [16]?[*]const bytecode.Instruction = @splat(null),
    depth: usize = 0,
    remaining: usize = 65536,
    memo: Memo = .{},

    fn analyze(self: *Proof, function: bytecode.Function) native.Error!?[32]u8 {
        const code = function.scope.instructions;
        for (self.memo.entries[0..self.memo.count]) |entry| if (entry.function == @backingInt(function.id)) return entry.identity;
        if (self.depth == self.active.len or code.len > self.remaining) return null;
        for (self.active[0..self.depth]) |active| if (active == code.ptr) return null;
        if (!try body.admissible(self.catalog, function)) return null;
        self.remaining -= code.len;
        self.active[self.depth] = code.ptr;
        self.depth += 1;
        defer self.depth -= 1;
        var hash = Hash.init(.{});
        part(&hash, version);
        part(&hash, self.abi);
        part(&hash, function.name);
        std.hash.autoHash(&hash, function.signature.parameter_count);
        std.hash.autoHash(&hash, function.scope.locals.len);
        hash.update(&(try self.catalog.native.layout(function.signature.return_type)).hash);
        for (function.scope.locals) |local| hash.update(&(try self.catalog.native.layout(local.ty)).hash);
        for (code, 0..) |instruction, pc| {
            const op = instruction.op;
            if (op == .call and op.call != function.id) {
                const index = @backingInt(op.call);
                if (index >= self.functions.len) return null;
                const callee = self.functions[index];
                if ((try self.catalog.get(callee.signature.return_type)).counted) {
                    const certificate = (try self.managed(index)) orelse return null;
                    std.hash.autoHash(&hash, pc);
                    std.hash.autoHash(&hash, certificate.parameter);
                    hash.update(&certificate.shape_identity);
                    hash.update(&certificate.dependency_identity);
                    if (self.depth == 1) try self.memo.routes.append(self.catalog.allocator, .{ .pc = pc, .target = op.call, .certificate = certificate });
                } else {
                    const dependency = (try self.analyze(callee)) orelse return null;
                    hash.update(&dependency);
                }
            } else if (!body.allowed(self.catalog, function, op)) return null;
            std.hash.autoHashStrat(&hash, op, .Deep);
        }
        if (!try @import("rc_readonly_plan.zig").certify(self.catalog, self.functions, function, &self.memo.physical)) return null;
        var result: [32]u8 = undefined;
        hash.final(&result);
        // A full memo declines, so a successful root never silently evicts an
        // earlier dependency and reinterprets it under a different work budget.
        if (self.memo.count == self.memo.entries.len) return null;
        self.memo.entries[self.memo.count] = .{ .function = @backingInt(function.id), .identity = result };
        self.memo.count += 1;
        return result;
    }

    // Shared by the entire plain-helper graph. Each distinct managed query has
    // exactly the standalone alternate emitter's budget; repeated calls reuse
    // only its completed immutable public certificate.
    fn managed(self: *Proof, index: usize) native.Error!?model.BorrowCertificate {
        for (self.memo.managed[0..self.memo.managed_count]) |entry| if (entry.function == index) return entry.certificate;
        if (self.memo.managed_count == self.memo.managed.len) return null;
        const callee = self.functions[index];
        const certificate = (try @import("rc_calls.zig").borrowedIn(self.catalog.allocator, self.catalog, self.functions, callee, self.abi)) orelse return null;
        if (certificate.parameter >= callee.signature.parameter_count) return null;
        const authority = @import("rc_field_authority.zig");
        const result_safe = authority.safe(self.catalog, callee.signature.return_type) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else error.InvalidType;
        const anchor_safe = authority.safe(self.catalog, callee.scope.locals[certificate.parameter].ty) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else error.InvalidType;
        if (!result_safe or !anchor_safe) return null;
        self.memo.managed[self.memo.managed_count] = .{ .function = index, .certificate = certificate };
        self.memo.managed_count += 1;
        return certificate;
    }
};

fn part(hash: *Hash, text: []const u8) void {
    var length: [8]u8 = undefined;
    std.mem.writeInt(u64, &length, text.len, .little);
    hash.update(&length);
    hash.update(text);
}
