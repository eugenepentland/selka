//! `selka-core dump-typed`: an indented listing of the checked tree the IR
//! builder reads, so a refusal or a wrong lowering can be traced to the exact
//! typed node shape the checker produced.
const std = @import("std");
const typed = @import("selka").typed;

const Writer = std.ArrayList(u8);

/// Render every function with a body (or only those whose name contains `filter`).
pub fn render(allocator: std.mem.Allocator, program: typed.Program, filter: ?[]const u8) std.mem.Allocator.Error![]u8 {
    var out: Writer = .empty;
    var dumper: Dumper = .{ .allocator = allocator, .out = &out, .program = program };
    for (program.functions) |function| {
        if (filter) |wanted| if (std.mem.indexOf(u8, function.name, wanted) == null) continue;
        const ret = typed.typeName(function.signature.return_type, program.records);
        try out.print(allocator, "fn {s} #{d} params={d} ret={s}", .{ function.name, @backingInt(function.id), function.signature.parameter_count, ret });
        try out.print(allocator, " cabi={} host={}\n", .{ function.policy.c_abi, function.policy.host != null });
        for (function.scope.locals, 0..) |local, slot| {
            try out.print(allocator, "  local %{d} {s}: {s}{s}\n", .{ slot, local.name, typed.typeName(local.ty, program.records), if (local.mutable) " mut" else "" });
        }
        try dumper.statement(function.scope.body, 1);
    }
    return out.toOwnedSlice(allocator);
}

const Dumper = struct {
    allocator: std.mem.Allocator,
    out: *Writer,
    program: typed.Program,

    fn indent(self: *Dumper, depth: usize) !void {
        for (0..depth) |_| try self.out.appendSlice(self.allocator, "  ");
    }

    fn rangeStatement(self: *Dumper, range: typed.RangeLoop, depth: usize) std.mem.Allocator.Error!void {
        const header = range.plan();
        try self.out.print(self.allocator, " binding={d} id={d}\n", .{ header.binding.start, range.plan().loop.id });
        try self.label("start:", depth + 1);
        try self.node(header.start.value, depth + 2);
        try self.label("end:", depth + 1);
        try self.node(header.end.value, depth + 2);
        try self.label("setup:", depth + 1);
        for (header.setup) |setup| try self.statement(setup, depth + 2);
        try self.label("loop:", depth + 1);
        try self.label("condition:", depth + 2);
        try self.node(range.plan().loop.condition, depth + 3);
        try self.label("body:", depth + 2);
        try self.statement(range.plan().loop.body, depth + 3);
        if (range.plan().loop.step) |step| {
            try self.label("step:", depth + 2);
            try self.statement(step, depth + 3);
        }
    }

    fn label(self: *Dumper, text: []const u8, depth: usize) std.mem.Allocator.Error!void {
        try self.indent(depth);
        try self.out.print(self.allocator, "{s}\n", .{text});
    }

    fn statement(self: *Dumper, id: typed.StatementId, depth: usize) std.mem.Allocator.Error!void {
        const s = self.program.statements[@backingInt(id)];
        try self.indent(depth);
        try self.out.print(self.allocator, "{s}", .{@tagName(s.data)});
        switch (s.data) {
            .block => |items| {
                try self.out.appendSlice(self.allocator, "\n");
                for (items) |item| try self.statement(item, depth + 1);
            },
            .ret, .discard => |value| {
                try self.out.appendSlice(self.allocator, "\n");
                try self.node(value, depth + 1);
            },
            .initialize, .assign => |store| {
                try self.out.print(self.allocator, " %{d}{s}\n", .{ @backingInt(store.slot), if (store.element) " element" else "" });
                try self.node(store.value, depth + 1);
            },
            .branch => |branch| {
                try self.out.appendSlice(self.allocator, "\n");
                try self.node(branch.condition, depth + 1);
                try self.statement(branch.then_body, depth + 1);
                if (branch.else_body) |other| try self.statement(other, depth + 1);
            },
            .range_loop => |range| try self.rangeStatement(range, depth),
            .loop => |loop| {
                try self.out.print(self.allocator, " id={d}\n", .{loop.id});
                try self.node(loop.condition, depth + 1);
                try self.statement(loop.body, depth + 1);
                if (loop.step) |step| {
                    try self.indent(depth + 1);
                    try self.out.appendSlice(self.allocator, "step:\n");
                    try self.statement(step, depth + 2);
                }
            },
            .loop_exit => |exit| try self.out.print(self.allocator, " target={d} continue={}\n", .{ exit.target, exit.continuing }),
            .match => |match| {
                try self.out.print(self.allocator, " borrowed={}\n", .{match.borrowed});
                try self.node(match.value, depth + 1);
                for (match.arms) |arm| {
                    try self.indent(depth + 1);
                    if (arm.slot) |slot| try self.out.print(self.allocator, "arm tag={d} bind=%{d}\n", .{ arm.tag, @backingInt(slot) }) else try self.out.print(self.allocator, "arm tag={d}\n", .{arm.tag});
                    try self.statement(arm.body, depth + 2);
                }
            },
            .assertion => |assertion| {
                try self.out.print(self.allocator, " {s}\n", .{assertion.message});
                try self.node(assertion.condition, depth + 1);
            },
            .with_scope => |scope| {
                try self.out.print(self.allocator, " %{d}\n", .{@backingInt(scope.slot)});
                try self.statement(scope.body, depth + 1);
            },
        }
    }

    fn fieldInit(self: *Dumper, field: typed.FieldInit, depth: usize) std.mem.Allocator.Error!void {
        try self.indent(depth);
        try self.out.print(self.allocator, "field .{d}\n", .{field.index});
        try self.node(field.value, depth + 1);
    }

    fn node(self: *Dumper, id: typed.NodeId, depth: usize) std.mem.Allocator.Error!void {
        const n = self.program.nodes[@backingInt(id)];
        try self.indent(depth);
        try self.out.print(self.allocator, "{s} : {s}", .{ @tagName(n.data), typed.typeName(n.ty, self.program.records) });
        switch (n.data) {
            .integer => |value| try self.out.print(self.allocator, " {d}\n", .{value}),
            .boolean => |value| try self.out.print(self.allocator, " {}\n", .{value}),
            .local => |slot| try self.out.print(self.allocator, " %{d}\n", .{@backingInt(slot)}),
            .unary => |unary| {
                try self.out.print(self.allocator, " {s}\n", .{@tagName(unary.op)});
                try self.node(unary.operand, depth + 1);
            },
            .binary => |binary| {
                try self.out.print(self.allocator, " {s}\n", .{@tagName(binary.op)});
                try self.node(binary.left, depth + 1);
                try self.node(binary.right, depth + 1);
            },
            .call => |call| {
                try self.out.print(self.allocator, " {s}\n", .{self.program.functions[@backingInt(call.function)].name});
                for (call.arguments) |argument| try self.node(argument, depth + 1);
                if (call.evaluation) |evaluation| try self.statement(evaluation.body, depth + 1);
            },
            .block_value => |block| {
                try self.out.appendSlice(self.allocator, "\n");
                try self.statement(block.body, depth + 1);
                try self.node(block.value, depth + 1);
            },
            .buffer_operation => |operation| {
                try self.out.print(self.allocator, " {s} owner=%{d}\n", .{ @tagName(operation.kind), @backingInt(operation.owner) });
                for (operation.arguments) |argument| try self.node(argument, depth + 1);
            },
            .acquire_buffer => |acquire| {
                try self.out.appendSlice(self.allocator, "\n");
                try self.node(acquire.capacity, depth + 1);
            },
            .index => |index| {
                try self.out.print(self.allocator, " from_end={}\n", .{index.from_end});
                try self.node(index.base, depth + 1);
                try self.node(index.index, depth + 1);
            },
            .length, .cast, .wrap, .unwrap, .arena_escape, .complete_resource => |operand| {
                try self.out.appendSlice(self.allocator, "\n");
                try self.node(operand, depth + 1);
            },
            .variant => |variant| {
                try self.out.print(self.allocator, " tag={d}\n", .{variant.tag});
                if (variant.value) |value| try self.node(value, depth + 1);
            },
            .print => |print| {
                try self.out.print(self.allocator, " sink={s} debug={}\n", .{ @tagName(print.sink), print.debug });
                if (print.stream) |stream| try self.node(stream, depth + 1);
                for (print.arguments) |argument| try self.node(argument, depth + 1);
            },
            .propagate => |propagate| {
                try self.out.appendSlice(self.allocator, "\n");
                try self.node(propagate.value, depth + 1);
            },
            .field => |field| {
                try self.out.print(self.allocator, " .{d}\n", .{field.index});
                try self.node(field.base, depth + 1);
            },
            .array => |items| {
                try self.out.appendSlice(self.allocator, "\n");
                for (items) |item| try self.node(item, depth + 1);
            },
            .record => |fields| {
                try self.out.appendSlice(self.allocator, "\n");
                for (fields) |field| try self.fieldInit(field, depth + 1);
            },
            .update => |update| {
                try self.out.appendSlice(self.allocator, "\n");
                try self.node(update.base, depth + 1);
                for (update.fields) |field| try self.fieldInit(field, depth + 1);
            },
            .replace => |replace| {
                try self.out.print(self.allocator, " from_end={}\n", .{replace.from_end});
                try self.node(replace.base, depth + 1);
                try self.node(replace.index, depth + 1);
                try self.node(replace.value, depth + 1);
            },
            else => try self.out.appendSlice(self.allocator, " ...\n"),
        }
    }
};
