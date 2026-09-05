//! Iterative traversal of one checked function body; calls do not traverse callees.
const std = @import("std");
const typed = @import("typed.zig");
pub const Item = union(enum) { expression: typed.NodeId, statement: typed.StatementId };
pub const Walker = struct {
    allocator: std.mem.Allocator,
    program: typed.Program,
    pending: std.ArrayList(Item) = .empty,
    pub fn init(allocator: std.mem.Allocator, program: typed.Program, body: typed.StatementId) !Walker {
        var walker: Walker = .{ .allocator = allocator, .program = program };
        try walker.pending.append(allocator, .{ .statement = body });
        return walker;
    }
    pub fn deinit(self: *Walker) void {
        self.pending.deinit(self.allocator);
    }
    fn expr(self: *Walker, id: typed.NodeId) !void {
        try self.pending.append(self.allocator, .{ .expression = id });
    }
    fn stmt(self: *Walker, id: typed.StatementId) !void {
        try self.pending.append(self.allocator, .{ .statement = id });
    }
    fn arguments(self: *Walker, values: []const typed.NodeId) !void {
        var i = values.len;
        while (i != 0) {
            i -= 1;
            try self.expr(values[i]);
        }
    }
    fn fields(self: *Walker, values: []const typed.FieldInit) !void {
        var i = values.len;
        while (i != 0) {
            i -= 1;
            try self.expr(values[i].value);
        }
    }
    pub fn next(self: *Walker) !?Item {
        const item = self.pending.pop() orelse return null;
        switch (item) {
            .expression => |id| switch (self.program.nodes[@backingInt(id)].data) {
                .integer, .boolean, .local, .read_ref, .read_field, .len_slice => {},
                .restrict_resource => |restrict| try self.expr(restrict.value),
                .resource_io => |io| if (io.value) |value| try self.expr(value),
                .environment_get => |get| {
                    try self.expr(get.name);
                    try self.expr(get.capability);
                },
                .complete_resource => |value| try self.expr(value),
                .acquire_resource => |acquire| {
                    try self.expr(acquire.request);
                    try self.expr(acquire.capability);
                },
                .external_read => |read| try self.expr(read.capability),
                .acquire_buffer => |acquire| {
                    try self.expr(acquire.capacity);
                    try self.expr(acquire.allocator);
                },
                .cast, .wrap, .unwrap, .length => |value| try self.expr(value),
                .propagate => |p| try self.expr(p.value),
                .read_slice => |r| try self.expr(r.index),
                .variant => |v| if (v.value) |value| try self.expr(value),
                .array => |values| try self.arguments(values),
                .record => |values| try self.fields(values),
                .buffer_operation => |op| try self.arguments(op.arguments),
                .call => |call| try self.arguments(call.arguments),
                .field => |field| try self.expr(field.base),
                .unary => |u| try self.expr(u.operand),
                .binary => |b| {
                    try self.expr(b.right);
                    try self.expr(b.left);
                },
                .index => |a| {
                    try self.expr(a.index);
                    try self.expr(a.base);
                },
                .replace => |r| {
                    try self.expr(r.value);
                    try self.expr(r.index);
                    try self.expr(r.base);
                },
                .update => |u| {
                    try self.fields(u.fields);
                    try self.expr(u.base);
                },
            },
            .statement => |id| switch (self.program.statements[@backingInt(id)].data) {
                .block => |children| {
                    var i = children.len;
                    while (i != 0) {
                        i -= 1;
                        try self.stmt(children[i]);
                    }
                },
                .ret, .discard, .acknowledge => |value| try self.expr(value),
                .ret_ref => {},
                .initialize, .assign => |s| try self.expr(s.value),
                .borrow_call => |b| {
                    try self.stmt(b.body);
                    try self.expr(b.call);
                },
                .borrow => |b| {
                    try self.stmt(b.body);
                    if (b.range) |r| {
                        try self.expr(r.end);
                        try self.expr(r.start);
                    }
                },
                .write_ref => |w| try self.expr(w.value),
                .write_slice => |w| {
                    try self.expr(w.value);
                    try self.expr(w.index);
                },
                .branch => |b| {
                    if (b.else_body) |body| try self.stmt(body);
                    try self.stmt(b.then_body);
                    try self.expr(b.condition);
                },
                .loop => |l| {
                    try self.stmt(l.body);
                    try self.expr(l.condition);
                },
                .match => |m| {
                    var i = m.arms.len;
                    while (i != 0) {
                        i -= 1;
                        try self.stmt(m.arms[i].body);
                    }
                    try self.expr(m.value);
                },
            },
        }
        return item;
    }
};
