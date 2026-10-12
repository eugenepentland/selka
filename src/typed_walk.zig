//! Iterative traversal of one checked function body; calls do not traverse callees.
const std = @import("std");
const typed = @import("typed.zig");
/// Expression or statement identity yielded by an iterative checked-body traversal.
pub const Item = union(enum) { expression: typed.NodeId, statement: typed.StatementId };
/// Owns a pending traversal stack while borrowing the checked program.
pub const Walker = struct {
    allocator: std.mem.Allocator,
    program: typed.Program,
    pending: std.ArrayList(Item) = .empty,
    /// Seed an iterative traversal at one function body; release pending storage with deinit.
    pub fn init(allocator: std.mem.Allocator, program: typed.Program, body: typed.StatementId) std.mem.Allocator.Error!Walker {
        var walker: Walker = .{ .allocator = allocator, .program = program };
        try walker.pending.append(allocator, .{ .statement = body });
        return walker;
    }
    /// Seed an iterative traversal at one expression, visiting it and every
    /// node and statement it contains; release pending storage with deinit.
    pub fn initExpression(allocator: std.mem.Allocator, program: typed.Program, root: typed.NodeId) std.mem.Allocator.Error!Walker {
        var walker: Walker = .{ .allocator = allocator, .program = program };
        try walker.pending.append(allocator, .{ .expression = root });
        return walker;
    }
    /// Release the pending traversal stack.
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
    fn orderedArguments(self: *Walker, values: []const typed.NodeId, order: []const usize) !void {
        if (order.len == 0) return self.arguments(values);
        var i = order.len;
        while (i != 0) {
            i -= 1;
            try self.expr(values[order[i]]);
        }
    }
    fn fields(self: *Walker, values: []const typed.FieldInit) !void {
        var i = values.len;
        while (i != 0) {
            i -= 1;
            try self.expr(values[i].value);
        }
    }
    pub fn next(self: *Walker) std.mem.Allocator.Error!?Item {
        const item = self.pending.pop() orelse return null;
        switch (item) {
            .expression => |id| switch (self.program.nodes[@backingInt(id)].data) {
                .function_value, .unit, .integer, .boolean, .local, .blob => {},
                .restrict_resource => |restrict| try self.expr(restrict.value),
                .dir_resource => |dir| {
                    try self.expr(dir.path);
                    try self.expr(dir.capability);
                },
                .host_resource => |host| {
                    try self.expr(host.name);
                    try self.expr(host.capability);
                },
                .resource_io => |io| if (io.value) |value| try self.expr(value),
                .environment_get => |get| {
                    try self.expr(get.name);
                    try self.expr(get.capability);
                },
                .environment_only => |only| {
                    try self.expr(only.names);
                    try self.expr(only.capability);
                },
                .environment_names => |capability| try self.expr(capability),
                .complete_resource => |value| try self.expr(value),
                .acquire_resource => |acquire| {
                    try self.expr(acquire.request);
                    try self.expr(acquire.capability);
                },
                .external_read => |read| try self.expr(read.capability),
                .stand_in => |stand| {
                    if (stand.second) |second| try self.expr(second);
                    try self.expr(stand.first);
                },
                .acquire_buffer => |acquire| try self.expr(acquire.capacity),
                .file_access => |call| try self.arguments(call.arguments),
                .file_method => |call| if (call.argument) |value| try self.expr(value),
                .print => |output| {
                    if (output.terminator) |value| try self.expr(value);
                    if (output.separator) |value| try self.expr(value);
                    try self.arguments(output.arguments);
                    if (output.stream) |value| try self.expr(value);
                },
                .stream_write => |write| {
                    try self.expr(write.text);
                    try self.expr(write.stream);
                },
                .arena_escape, .cast, .wrap, .unwrap, .length => |value| try self.expr(value),
                .propagate => |p| try self.expr(p.value),
                .block_value => |block| {
                    try self.expr(block.value);
                    try self.stmt(block.body);
                },
                .borrow_selection => |selection| {
                    try self.expr(selection.second);
                    try self.expr(selection.first);
                },
                .variant => |v| if (v.value) |value| try self.expr(value),
                .array => |values| try self.arguments(values),
                .record => |values| try self.fields(values),
                .buffer_operation => |op| try self.arguments(op.arguments),
                .invoke => |call| {
                    try self.orderedArguments(call.arguments, call.evaluation_order);
                    if (call.evaluation) |evaluation| try self.stmt(evaluation.body);
                    try self.expr(call.callee);
                },
                .call => |call| {
                    try self.orderedArguments(call.arguments, call.evaluation_order);
                    if (call.evaluation) |evaluation| try self.stmt(evaluation.body);
                },
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
                .with_scope => |scope| {
                    try self.stmt(scope.body);
                    if (scope.resource) |value| try self.expr(value);
                },
                .block => |children| {
                    var i = children.len;
                    while (i != 0) {
                        i -= 1;
                        try self.stmt(children[i]);
                    }
                },
                .ret, .discard => |value| try self.expr(value),
                .assertion => |check| {
                    if (check.message_value) |value| try self.expr(value);
                    try self.expr(check.condition);
                },
                .loop_exit => {},
                .initialize, .assign => |s| try self.expr(s.value),
                .branch => |b| {
                    if (b.else_body) |body| try self.stmt(body);
                    try self.stmt(b.then_body);
                    try self.expr(b.condition);
                },
                .range_loop => |range| {
                    if (range.plan().loop.step) |step| try self.stmt(step);
                    try self.stmt(range.plan().loop.body);
                    try self.expr(range.plan().loop.condition);
                    var i = range.plan().setup.len;
                    while (i != 0) {
                        i -= 1;
                        try self.stmt(range.plan().setup[i]);
                    }
                    try self.expr(range.plan().end.value);
                    try self.expr(range.plan().start.value);
                },
                .loop => |l| {
                    if (l.step) |step| try self.stmt(step);
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
