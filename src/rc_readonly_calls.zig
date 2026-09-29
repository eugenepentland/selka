//! Closed readonly composition with explicit public borrowed-call routes.
const std = @import("std");
const contracts = @import("rc_calls.zig");
const bytecode = @import("bytecode.zig");
const shapes = @import("rc_shape.zig");
const native = @import("native_types.zig");
const body = @import("rc_readonly_body.zig");
const model = @import("rc_model.zig");
const typed = @import("typed.zig");
const physical = @import("rc_readonly_plan.zig");
const Hash = std.crypto.hash.Blake3;
/// Proof identities bind the exact closed grammar, including call restrictions.
pub const version = "mylang-rc-readonly-calls-v5";
/// A checked direct call must use this independently emitted alternate entry.
pub const Route = struct { pc: usize, target: typed.FunctionId, certificate: model.EntryCertificate };
/// Complete raw-body proof and its caller-local immutable managed call routes.
pub const Certificate = struct { identity: [32]u8, calls: []const Route, entry: ?model.EntryCertificate = null };

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

/// Independently validate the supplied alternate ABI before a root-only exception.
/// This extra public query does not consume or enlarge the 16 managed-call budget.
pub fn borrowedEntry(catalog: *shapes.Catalog, functions: []const bytecode.Function, function: bytecode.Function, abi: []const u8, supplied: model.BorrowCertificate) native.Error!?Certificate {
    const actual = (try contracts.borrowedIn(catalog.allocator, catalog, functions, function, abi)) orelse return null;
    if (!std.meta.eql(actual, supplied)) return null;
    const output = try catalog.get(function.signature.return_type);
    if (!output.counted or output.unique_drop) return null;
    if (!try safeCertificate(catalog, function, actual)) return null;
    var proof: Proof = .{ .catalog = catalog, .functions = functions, .abi = abi };
    proof.memo.entry = .{ .function = function.id, .certificate = .{ .borrowed = actual } };
    defer proof.memo.routes.deinit(catalog.allocator);
    const digest = (try proof.analyze(function)) orelse return null;
    return .{ .identity = digest, .calls = try proof.memo.routes.toOwnedSlice(catalog.allocator), .entry = .{ .borrowed = actual } };
}

/// Revalidate the complete constant-body authority before raw alternate emission.
pub fn immortalEntry(catalog: *shapes.Catalog, functions: []const bytecode.Function, function: bytecode.Function, abi: []const u8, supplied: model.ImmortalCertificate) native.Error!?Certificate {
    const actual = (try contracts.immortalIn(catalog, functions, function, abi)) orelse return null;
    if (!std.meta.eql(actual, supplied)) return null;
    return .{ .identity = actual.dependency_identity, .calls = try catalog.allocator.alloc(Route, 0), .entry = .{ .immortal = actual } };
}

const Completed = struct { function: usize, identity: [32]u8 };
const Managed = struct { function: usize, certificate: model.EntryCertificate };
const Entry = struct { function: typed.FunctionId, certificate: model.EntryCertificate };
const Memo = struct {
    entries: [16]Completed = undefined,
    count: usize = 0,
    managed: [16]Managed = undefined,
    managed_count: usize = 0,
    routes: std.ArrayList(Route) = .empty,
    physical: physical.Budget = .{},
    entry: ?Entry = null,
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
        const passes: usize = if (self.memo.entry != null) 2 else 1;
        if (self.depth == self.active.len or code.len > self.remaining / passes) return null;
        for (self.active[0..self.depth]) |active| if (active == code.ptr) return null;
        const entry = if (self.depth == 0) self.memo.entry else null;
        const admitted = if (entry != null) try body.borrowedBoundary(self.catalog, function) else try body.admissible(self.catalog, function);
        if (!admitted) return null;
        if (self.memo.entry != null and !physical.quietReturns(self.catalog.native.records, function)) return null;
        self.remaining -= code.len * passes;
        self.active[self.depth] = code.ptr;
        self.depth += 1;
        defer self.depth -= 1;
        var hash = Hash.init(.{});
        part(&hash, version);
        part(&hash, self.abi);
        part(&hash, function.name);
        std.hash.autoHash(&hash, entry != null);
        if (entry) |root| {
            std.hash.autoHashStrat(&hash, root.certificate, .Deep);
        }
        std.hash.autoHash(&hash, function.signature.parameter_count);
        std.hash.autoHash(&hash, function.scope.locals.len);
        hash.update(&(try self.catalog.native.layout(function.signature.return_type)).hash);
        for (function.scope.locals) |local| hash.update(&(try self.catalog.native.layout(local.ty)).hash);
        for (code, 0..) |instruction, pc| {
            const op = instruction.op;
            if (op == .call) if (self.memo.entry) |root| {
                if (op.call == root.function) return null;
            };
            if (op == .call and op.call != function.id) {
                const index = @backingInt(op.call);
                if (index >= self.functions.len) return null;
                const callee = self.functions[index];
                if ((try self.catalog.get(callee.signature.return_type)).counted) {
                    const certificate = (try self.managed(index)) orelse return null;
                    std.hash.autoHash(&hash, pc);
                    std.hash.autoHashStrat(&hash, certificate, .Deep);
                    if (self.depth == 1) try self.memo.routes.append(self.catalog.allocator, .{ .pc = pc, .target = op.call, .certificate = certificate });
                } else {
                    const dependency = (try self.analyze(callee)) orelse return null;
                    hash.update(&dependency);
                }
            } else if (!body.allowed(self.catalog, function, op)) return null;
            try @import("rc_proof_identity.zig").operation(&hash, self.catalog, self.functions, op);
        }
        if (!try physical.certify(self.catalog, self.functions, function, &self.memo.physical)) return null;
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
    fn managed(self: *Proof, index: usize) native.Error!?model.EntryCertificate {
        for (self.memo.managed[0..self.memo.managed_count]) |entry| if (entry.function == index) return entry.certificate;
        if (self.memo.managed_count == self.memo.managed.len) return null;
        const callee = self.functions[index];
        const certificate: model.EntryCertificate = if (callee.signature.parameter_count == 0) blk: {
            const immortal = (try contracts.immortalIn(self.catalog, self.functions, callee, self.abi)) orelse return null;
            if (!physical.charge(callee, &self.memo.physical)) return null;
            break :blk .{ .immortal = immortal };
        } else blk: {
            const borrowed = (try contracts.borrowedIn(self.catalog.allocator, self.catalog, self.functions, callee, self.abi)) orelse return null;
            if (!try safeCertificate(self.catalog, callee, borrowed)) return null;
            break :blk .{ .borrowed = borrowed };
        };
        self.memo.managed[self.memo.managed_count] = .{ .function = index, .certificate = certificate };
        self.memo.managed_count += 1;
        return certificate;
    }
};

fn safeCertificate(catalog: *shapes.Catalog, function: bytecode.Function, certificate: model.BorrowCertificate) native.Error!bool {
    if (certificate.parameter >= function.signature.parameter_count) return false;
    const authority = @import("rc_field_authority.zig");
    const result = authority.safe(catalog, function.signature.return_type) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else error.InvalidType;
    const anchor = authority.safe(catalog, function.scope.locals[certificate.parameter].ty) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else error.InvalidType;
    return result and anchor;
}

fn part(hash: *Hash, text: []const u8) void {
    var length: [8]u8 = undefined;
    std.mem.writeInt(u64, &length, text.len, .little);
    hash.update(&length);
    hash.update(text);
}
