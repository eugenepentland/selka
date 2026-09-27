//! Bounded composition of canonical read-only bodies with plain-result helpers.
const std = @import("std");
const bytecode = @import("bytecode.zig");
const shapes = @import("rc_shape.zig");
const native = @import("native_types.zig");
const body = @import("rc_readonly_body.zig");
const Hash = std.crypto.hash.Blake3;
/// Proof identities bind the exact closed grammar, including call restrictions.
pub const version = "mylang-rc-readonly-calls-v1";

/// Return an identity only after every helper proves a plain owning-free result.
/// Managed returns are deliberately refused: canonical raw bodies have no
/// result journal and cannot assume a managed borrowed alternate is selected.
pub fn identity(catalog: *shapes.Catalog, functions: []const bytecode.Function, function: bytecode.Function, abi: []const u8) native.Error!?[32]u8 {
    var proof: Proof = .{ .catalog = catalog, .functions = functions, .abi = abi };
    return proof.analyze(function);
}

const Completed = struct { function: usize, identity: [32]u8 };
const Memo = struct { entries: [16]Completed = undefined, count: usize = 0 };
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
        for (code) |instruction| {
            const op = instruction.op;
            if (op == .call and op.call != function.id) {
                const index = @backingInt(op.call);
                if (index >= self.functions.len) return null;
                const dependency = (try self.analyze(self.functions[index])) orelse return null;
                hash.update(&dependency);
            } else if (!body.allowed(self.catalog, function, op)) return null;
            std.hash.autoHashStrat(&hash, op, .Deep);
        }
        var result: [32]u8 = undefined;
        hash.final(&result);
        // A full memo declines, so a successful root never silently evicts an
        // earlier dependency and reinterprets it under a different work budget.
        if (self.memo.count == self.memo.entries.len) return null;
        self.memo.entries[self.memo.count] = .{ .function = @backingInt(function.id), .identity = result };
        self.memo.count += 1;
        return result;
    }
};

fn part(hash: *Hash, text: []const u8) void {
    var length: [8]u8 = undefined;
    std.mem.writeInt(u64, &length, text.len, .little);
    hash.update(&length);
    hash.update(text);
}
