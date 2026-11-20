//! A digest of one checked function that does not depend on where anything sits in the program (spec
//! `docs/design/incremental-engine.md` §17.2, `module-check`): the function's name, signature, locals and every node and
//! statement of its body, with a callee named by its name, a type by its structural name, and no source span at all.
//!
//! Two checks of the same function that number the program's functions, records and nodes differently (the whole program,
//! and one module against its imports' interfaces) give the same digest, and an edit to any part of the checked tree changes
//! it. It is built by reflection over the checked tree's types, so a node kind added later is hashed without a rule; a type
//! that needs one makes the compiler say so.
const std = @import("std");
const typed = @import("typed.zig");
const source = @import("source.zig");
const Blake3 = std.crypto.hash.Blake3;

/// A BLAKE3-256 digest.
pub const Digest = [32]u8;

/// The domain string every digest starts with.
pub const domain = "selka-typed-function-v1";

/// Digests the functions of one checked program, remembering the digest of each node and statement it reached so a tree that
/// shares a subtree is hashed once.
pub const Hasher = struct {
    allocator: std.mem.Allocator,
    program: typed.Program,
    nodes: std.AutoHashMapUnmanaged(usize, Digest) = .empty,
    statements: std.AutoHashMapUnmanaged(usize, Digest) = .empty,

    /// A hasher over `program`; release it with `deinit`.
    pub fn init(allocator: std.mem.Allocator, program: typed.Program) Hasher {
        return .{ .allocator = allocator, .program = program };
    }

    /// Release the memo.
    pub fn deinit(self: *Hasher) void {
        self.nodes.deinit(self.allocator);
        self.statements.deinit(self.allocator);
    }

    /// The digest of `function`.
    pub fn function(self: *Hasher, function_value: typed.Function) std.mem.Allocator.Error!Digest {
        var state = Blake3.init(.{});
        state.update(domain);
        try self.put(&state, function_value.name);
        try self.put(&state, function_value.policy);
        try self.put(&state, function_value.type_arguments);
        try self.put(&state, function_value.signature);
        try self.put(&state, function_value.scope);
        var out: Digest = undefined;
        state.final(&out);
        return out;
    }

    fn node(self: *Hasher, id: typed.NodeId) std.mem.Allocator.Error!Digest {
        if (self.nodes.get(@backingInt(id))) |known| return known;
        var state = Blake3.init(.{});
        state.update("node");
        try self.put(&state, self.program.nodes[@backingInt(id)]);
        var out: Digest = undefined;
        state.final(&out);
        try self.nodes.put(self.allocator, @backingInt(id), out);
        return out;
    }

    fn statement(self: *Hasher, id: typed.StatementId) std.mem.Allocator.Error!Digest {
        if (self.statements.get(@backingInt(id))) |known| return known;
        var state = Blake3.init(.{});
        state.update("statement");
        try self.put(&state, self.program.statements[@backingInt(id)]);
        var out: Digest = undefined;
        state.final(&out);
        try self.statements.put(self.allocator, @backingInt(id), out);
        return out;
    }

    fn put(self: *Hasher, state: *Blake3, v: anytype) std.mem.Allocator.Error!void {
        const T = @TypeOf(v);
        if (T == source.Span) return;
        if (T == typed.Type) return text(state, typed.typeName(v, self.program.records));
        if (T == typed.FunctionId) return text(state, self.program.functions[@backingInt(v)].name);
        if (T == typed.NodeId) {
            const digest = try self.node(v);
            return state.update(&digest);
        }
        if (T == typed.StatementId) {
            const digest = try self.statement(v);
            return state.update(&digest);
        }
        // `address`, `freestanding` and `ram` are hashed only when set, so a function without them digests exactly as
        // before the fields existed.
        if (T == typed.FunctionPolicy) {
            inline for (@typeInfo(T).@"struct".field_names) |name| if (comptime !typed.FunctionPolicy.keyedWhenSet(name)) try self.put(state, @field(v, name));
            if (v.address) state.update("address");
            if (v.freestanding) |span| {
                state.update("freestanding");
                try self.put(state, span);
            }
            if (v.ram) state.update("ram");
            return;
        }
        switch (@typeInfo(T)) {
            .int => {
                var little = std.mem.nativeToLittle(T, v);
                state.update(std.mem.asBytes(&little));
            },
            .float => try self.put(state, @as(@Int(.unsigned, @bitSizeOf(T)), @bitCast(v))),
            .bool => state.update(&.{@intFromBool(v)}),
            .void => {},
            .@"enum" => try self.put(state, @backingInt(v)),
            .optional => {
                try self.put(state, v != null);
                if (v) |present| try self.put(state, present);
            },
            .pointer => |ptr| {
                if (ptr.size != .slice) @compileError("a checked tree's slices must be owned: " ++ @typeName(T));
                try self.put(state, @as(u64, v.len));
                if (ptr.child == u8) state.update(v) else for (v) |item| try self.put(state, item);
            },
            .array => for (v) |item| try self.put(state, item),
            .@"struct" => |s| inline for (s.field_names) |name| try self.put(state, @field(v, name)),
            .@"union" => |u| {
                const tag = std.meta.activeTag(v);
                try self.put(state, tag);
                inline for (u.field_names) |name| if (tag == @field(std.meta.Tag(T), name)) try self.put(state, @field(v, name));
            },
            else => @compileError("a checked tree's field needs a hashing rule: " ++ @typeName(T)),
        }
    }
};

fn text(state: *Blake3, bytes: []const u8) void {
    var length: [8]u8 = undefined;
    std.mem.writeInt(u64, &length, bytes.len, .little);
    state.update(&length);
    state.update(bytes);
}
