//! A compact bridge from validated semantic summaries to raw lowering artifacts.
//! The frontend may omit a tree only when this entry has a previous body digest
//! or completed discovery proved that its declaration was unreachable.
//! Lowering still validates its exact catalog, discovery order and artifact; any
//! missing artifact asks the pipeline to repeat with complete checked trees.
const std = @import("std");
const language = @import("mylang");
const stage = @import("stage_store.zig");

const Receipt = struct {
    key: []const u8,
    context: stage.Digest,
    region: stage.Digest,
    kind: union(enum) { lowered: stage.Digest, @"unreachable" },
};
const Inputs = struct {
    prepared: ?language.semantic_summary.Prepared = null,
    omitted: []const bool = &.{},
    reached: ?[]const bool = null,
};

/// One build's manifest and selected checked-body omissions. All memory belongs
/// to the build arena; no function tree is stored in this index.
pub const Context = struct {
    arena: std.mem.Allocator,
    store: *const stage.Store,
    key: stage.Digest,
    previous: std.StringHashMapUnmanaged(Receipt) = .empty,
    input: Inputs = .{},
    next: std.ArrayList(Receipt) = .empty,

    /// Load the last complete lowering manifest for this entry and debug policy.
    pub fn init(arena: std.mem.Allocator, store: *const stage.Store, entry: []const u8, drop_debug: bool) std.mem.Allocator.Error!Context {
        const key = store.key("lowering-demand-v2", &.{ entry, &.{@intFromBool(drop_debug)} });
        var self: Context = .{ .arena = arena, .store = store, .key = key };
        errdefer self.previous.deinit(arena);
        const receipts = try store.loadValue(arena, key, []const Receipt) orelse return self;
        for (receipts) |receipt| {
            const found = try self.previous.getOrPut(arena, receipt.key);
            if (found.found_existing) {
                self.previous.clearRetainingCapacity();
                return self;
            }
            found.value_ptr.* = receipt;
        }
        return self;
    }

    /// Offer constant-time receipt lookup to the frontend's dependency planner.
    /// Keep this context at a stable address until checking finishes.
    pub fn callback(self: *const Context) language.semantic_summary.Demand {
        return .{ .context = self, .allow = allows };
    }

    fn allows(context: *const anyopaque, key: []const u8, dependency: stage.Digest, region: stage.Digest) bool {
        const self: *const Context = @ptrCast(@alignCast(context));
        const receipt = self.previous.get(key) orelse return false;
        return std.mem.eql(u8, &receipt.context, &dependency) and std.mem.eql(u8, &receipt.region, &region);
    }

    /// Attach fresh declaration identities and the bodies actually omitted by
    /// checking, after its dependency and cross-function consistency checks.
    pub fn attach(self: *Context, prepared: language.semantic_summary.Prepared, skipped: []const bool) void {
        self.input = .{ .prepared = prepared, .omitted = skipped };
    }

    /// Whether this function has no checked body and must restore raw lowering
    /// if discovery reaches it, or request a complete frontend retry.
    pub fn omitted(self: *const Context, id: language.typed.FunctionId) bool {
        const index = @backingInt(id);
        return index < self.input.omitted.len and self.input.omitted[index];
    }

    /// Number of checked trees the frontend avoided materializing in this build.
    pub fn count(self: *const Context) usize {
        var result: usize = 0;
        for (self.input.omitted) |value| result += @intFromBool(value);
        return result;
    }

    /// The previously computed typed-tree digest, after semantic validation.
    pub fn body(self: *const Context, id: language.typed.FunctionId) ?stage.Digest {
        if (!self.omitted(id)) return null;
        const current = self.identity(id) orelse return null;
        const receipt = self.previous.get(current.key) orelse return null;
        if (!allows(self, current.key, current.context, current.region)) return null;
        return switch (receipt.kind) {
            .lowered => |digest| digest,
            .@"unreachable" => null,
        };
    }

    fn identity(self: *const Context, id: language.typed.FunctionId) ?Receipt {
        const prepared = self.input.prepared orelse return null;
        const index = @backingInt(id);
        if (index >= prepared.ordinary_ast.len) return null;
        const ast = prepared.ordinary_ast[index];
        return .{ .key = prepared.keys[ast], .context = prepared.contexts[ast], .region = prepared.recalled.digests[ast], .kind = .@"unreachable" };
    }

    /// Remember only a body with relocatable local positions. Nonordinary and
    /// unsupported summaries remain on the complete checked-tree path.
    pub fn record(self: *Context, id: language.typed.FunctionId, digest: stage.Digest) std.mem.Allocator.Error!void {
        var receipt = self.identity(id) orelse return;
        receipt.kind = .{ .lowered = digest };
        try self.next.append(self.arena, receipt);
    }

    /// Discard the current receipt if lowering discovered source metadata that
    /// cannot be reconstructed from the declaration and fresh function catalog.
    pub fn reject(self: *Context, id: language.typed.FunctionId) void {
        const receipt = self.identity(id) orelse return;
        if (self.next.items.len == 0) return;
        if (std.mem.eql(u8, self.next.items[self.next.items.len - 1].key, receipt.key)) _ = self.next.pop();
    }

    /// Capture every typed declaration reached by successful lowering discovery.
    /// Reached declarations without safe body receipts must remain unavailable.
    pub fn recordReachable(self: *Context, ids: []const language.typed.FunctionId) std.mem.Allocator.Error!void {
        const prepared = self.input.prepared orelse return;
        const reached = try self.arena.alloc(bool, prepared.ordinary_ast.len);
        @memset(reached, false);
        for (ids) |id| {
            const index = @backingInt(id);
            if (index < reached.len) reached[index] = true;
        }
        self.input.reached = reached;
    }

    /// Publish only after every reachable function restored or lowered safely.
    /// An absent completed-discovery mask never admits an unknown declaration.
    pub fn finish(self: *Context) std.mem.Allocator.Error!void {
        if (self.input.reached) |reached| {
            for (reached, 0..) |visited, index| {
                if (visited) continue;
                const receipt = self.identity(@fromBackingInt(@intCast(index))) orelse continue;
                try self.next.append(self.arena, receipt);
            }
        }
        try self.store.storeValue(self.key, []const Receipt, self.next.items);
    }
};
