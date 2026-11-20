//! Conservative tuple retirement: atomic signatures and their known consumers.
const std = @import("std");
const ast = @import("ast.zig");
const typed = @import("typed.zig");
const source = @import("source.zig");
const diagnostic = @import("diagnostic.zig");
const support = @import("migration_support.zig");
const Names = @import("module_names.zig").Names;
const moves = @import("migration_moves.zig");
const own_parameters = @import("own_parameters.zig");
const typed_walk = @import("typed_walk.zig");
const Span = source.Span;
const Edit = diagnostic.Edit;
pub const removed_code = "E_TUPLE_REMOVED";
/// What a tuple diagnostic says when the program did not check, so no repair is made until its other diagnostics are repaired.
/// `selka fix` does not read it: a tuple diagnostic that publishes no `fix` is how it learns the repair is deferred.
pub const deferred_message = "tuple migration is deferred until other diagnostics are repaired";
const message = "tuples were removed; use a named record with explicit fields; enumerate, zip and dictionary items remain two-name loop forms";

/// Reject surface tuples after checking legacy forms to retain migration facts.
pub fn reject(allocator: std.mem.Allocator, src: source.Source, program: ast.Program, names: ?*Names, sink: *diagnostic.Sink, checked: ?*const typed.Program) diagnostic.Error!void {
    // A program that knows what it holds is scanned only when it holds a tuple value or a tuple type.
    if (program.facts.retired) |held| if (!held.tuple and program.types.expressions.tuples.len == 0) return;
    try ast.ensureAll(program);
    var pass: Pass = .{ .allocator = allocator, .src = src, .program = program, .names = names, .sink = sink, .checked = checked };
    try pass.run();
}
const Pass = struct {
    allocator: std.mem.Allocator,
    src: source.Source,
    program: ast.Program,
    names: ?*Names,
    sink: *diagnostic.Sink,
    checked: ?*const typed.Program,
    covered: std.ArrayList(Span) = .empty,

    fn publish(self: *Pass, span: Span, edits: []const Edit) !void {
        const item: diagnostic.Diagnostic = .{
            .code = removed_code,
            .span = span,
            // `deferred_message` is true only for a program that did not check: another diagnostic is why no repair is made. A
            // checked program with no certain repair says what every tuple says, and its note says why nothing is repaired.
            .message = if (self.checked == null) deferred_message else message,
            .related = if (self.checked != null and edits.len == 0) .{
                .span = span,
                .message = "no certain automatic repair: use a nominal record and update every consumer manually. " ++
                    "For pending Results, prefer Result[Record, E]; transfer move-only providers explicitly.",
            } else null,
        };
        if (self.checked == null or edits.len == 0) return self.sink.items.append(self.allocator, item);
        try self.sink.appendFix(item, edits[0]);
        self.sink.items.items[self.sink.items.items.len - 1].provenance.fix.?.more = edits[1..];
        for (edits) |edit| if (edit.span.start != edit.span.end) try self.covered.append(self.allocator, edit.span);
    }
    fn isCovered(self: Pass, span: Span) bool {
        for (self.covered.items) |outer| if (outer.start <= span.start and outer.end >= span.end) return true;
        return false;
    }
    fn node(self: Pass, id: ast.NodeId) ast.Node {
        return self.program.nodes.items[@backingInt(id)];
    }
    fn run(self: *Pass) diagnostic.Error!void {
        // A signature and every call site form one fix. Never change a shared
        // declaration while leaving an independent consumer without tuple facts.
        if (self.checked != null) {
            for (self.program.functions) |function| try self.migrateFunction(function);
            for (self.program.statements.items) |statement| {
                if (statement.data != .discard) continue;
                const value = self.node(statement.data.discard);
                if (value.data != .field_assignment or self.isCovered(value.span)) continue;
                const assignment = value.data.field_assignment;
                if (self.node(assignment.target).data != .tuple or self.node(assignment.value).data != .tuple) continue;
                if (try self.swap(statement, value)) |edit| try self.publish(value.span, &.{edit});
            }
        }
        for (self.program.types.expressions.tuples) |tuple| if (!self.isCovered(tuple.span)) try self.publish(tuple.span, &.{});
        for (self.program.nodes.items) |value| if (value.data == .tuple and !self.isCovered(value.span)) try self.publish(value.span, &.{});
    }
    fn tupleType(self: Pass, span: Span) ?ast.TupleType {
        for (self.program.types.expressions.tuples) |tuple| if (std.meta.eql(tuple.span, span)) return tuple;
        return null;
    }
    fn returns(self: Pass, function: ast.Function) ![]const ast.NodeId {
        var work: std.ArrayList(ast.StatementId) = .empty;
        var values: std.ArrayList(ast.NodeId) = .empty;
        try work.append(self.allocator, function.body);
        var i: usize = 0;
        while (i < work.items.len) : (i += 1) {
            const statement = self.program.statements.items[@backingInt(work.items[i])];
            if (statement.data == .ret) try values.append(self.allocator, statement.data.ret);
            try ast.appendNested(self.allocator, &work, statement);
        }
        return values.items;
    }
    fn targetPlaces(self: Pass, target: ast.NodeId, count: usize) ?[]const ast.NodeId {
        const value = self.node(target);
        if (value.data != .tuple or value.data.tuple.len != count) return null;
        for (value.data.tuple) |id| switch (self.node(id).data) {
            .name, .field, .index => {},
            else => return null,
        };
        return value.data.tuple;
    }
    fn callOf(self: Pass, value: ast.Node, declaration: Span) bool {
        const checked = self.checked orelse return false;
        if (value.data != .call) return false;
        for (checked.nodes) |item| {
            if (!std.meta.eql(item.span, value.span) or item.data != .call) continue;
            if (std.meta.eql(checked.functions[@backingInt(item.data.call.function)].declaration, declaration)) return true;
        }
        return false;
    }
    fn migrateFunction(self: *Pass, function: ast.Function) diagnostic.Error!void {
        const tuple = self.tupleType(function.signature.return_type) orelse return;
        const values = try self.returns(function);
        if (values.len == 0 or function.policy.owner != null or function.policy.host != null or function.policy.c_abi) return;
        for (values) |id| if (self.node(id).data != .tuple or self.node(id).data.tuple.len != tuple.elements.len) return;
        for (tuple.elements) |element| if (self.tupleType(element) != null) return;
        // Source annotations preserve generic binders, independent of whichever
        // concrete specialization the checker visited first.
        if (!simpleGenerics(function) or !self.copyableReturn(function)) return;
        const fields = try self.fieldNames(values, tuple.elements.len);
        const transfers = try self.transferredFields(function, tuple);
        const record = try self.recordName(function);
        var edits: std.ArrayList(Edit) = .empty;
        // All direct calls must be destructured; all function-value uses must
        // be sort key arguments. Stored/passed/printed tuples get no repair.
        for (self.program.nodes.items) |value| {
            if (self.callOf(value, function.name)) {
                const assignment = self.destructuringConsumer(value.span) orelse return;
                const statement = support.enclosingStatement(self.program, assignment.span) orelse return;
                const replacement = try self.unpack(statement, assignment, fields) orelse return;
                try edits.append(self.allocator, replacement);
            }
        }
        if (self.checked) |checked| for (checked.nodes) |value| {
            if (value.data != .function_value or !std.meta.eql(checked.functions[@backingInt(value.data.function_value)].declaration, function.name)) continue;
            if (!self.sortKeyUse(value.span)) return;
        };
        var definition: std.ArrayList(u8) = .empty;
        // Export the result record so public function signatures remain usable.
        try definition.appendSlice(self.allocator, "public record ");
        try definition.appendSlice(self.allocator, record);
        const generics = try self.genericNames(function);
        try definition.appendSlice(self.allocator, generics);
        try definition.appendSlice(self.allocator, ":\n");
        for (fields, tuple.elements) |field, ty| {
            try definition.print(self.allocator, "    {s}: {s}\n", .{ field, self.src.text(ty) });
        }
        try definition.appendSlice(self.allocator, "\n\n");
        const start = self.functionStart(function);
        try edits.append(self.allocator, .{ .span = .{ .start = start, .end = start }, .text = definition.items });
        try edits.append(self.allocator, .{ .span = function.signature.return_type, .text = try std.fmt.allocPrint(self.allocator, "{s}{s}", .{ record, generics }) });
        for (values) |id| {
            var replacement: std.ArrayList(u8) = .empty;
            try replacement.print(self.allocator, "{s}{s}(", .{ record, generics });
            for (self.node(id).data.tuple, fields, transfers, 0..) |item, field, transfer, index| {
                if (index != 0) try replacement.appendSlice(self.allocator, ", ");
                const text = try moves.capture(self.allocator, self.src, self.program, item, transfer);
                try replacement.print(self.allocator, "{s}={s}", .{ field, text });
            }
            try replacement.append(self.allocator, ')');
            try edits.append(self.allocator, .{ .span = self.node(id).span, .text = replacement.items });
        }
        try self.publish(tuple.span, edits.items);
    }
    /// Parameter-dependent fields keep one spelling across scalar and managed
    /// instances. Concrete fields use their checked recursive storage shape.
    fn transferredFields(self: Pass, function: ast.Function, tuple: ast.TupleType) ![]const bool {
        const result = try self.allocator.alloc(bool, tuple.elements.len);
        for (tuple.elements, result) |element, *transfer| transfer.* = own_parameters.mentionsTypeParameter(self.src, element, function.signature.type_parameters);
        if (self.checked) |checked| for (checked.functions) |instance| {
            if (!std.meta.eql(instance.declaration, function.name) or !instance.signature.return_type.isAggregate()) continue;
            const record = checked.records[instance.signature.return_type.recordIndex()];
            if (!record.shape.tuple or record.fields.len != result.len) continue;
            for (record.fields, result) |field, *transfer| transfer.* = transfer.* or own_parameters.managed(checked.records, field.ty);
        };
        return result;
    }
    fn transferredOperand(self: Pass, id: ast.NodeId) bool {
        const checked = self.checked orelse return false;
        for (checked.nodes) |node_value| {
            if (!std.meta.eql(node_value.span, self.node(id).span)) continue;
            if (node_value.type_dependent or own_parameters.managed(checked.records, node_value.ty)) return true;
        }
        return false;
    }
    fn unpackedFields(self: Pass, id: ast.NodeId, count: usize) ![]const bool {
        const transfers = try self.allocator.alloc(bool, count);
        @memset(transfers, false);
        if (self.checked) |checked| for (checked.nodes) |node_value| {
            if (!std.meta.eql(node_value.span, self.node(id).span) or !node_value.ty.isAggregate()) continue;
            const record = checked.records[node_value.ty.recordIndex()];
            if (!record.shape.tuple or record.fields.len != count) continue;
            for (record.fields, transfers) |field, *transfer| transfer.* = transfer.* or own_parameters.managed(checked.records, field.ty);
        };
        return transfers;
    }
    fn copyableReturn(self: Pass, function: ast.Function) bool {
        const checked = self.checked orelse return false;
        for (checked.functions) |instance| {
            if (!std.meta.eql(instance.declaration, function.name)) continue;
            const ty = instance.signature.return_type;
            if (typed.moveOnly(ty, checked.records) or typed.requiresHandling(ty, checked.records)) return false;
        }
        return true;
    }
    fn simpleGenerics(function: ast.Function) bool {
        for (function.signature.type_parameters) |parameter| {
            if (parameter.constant_length or parameter.requirements.len != 0) return false;
            if (parameter.field_requirements.len != 0 or parameter.operation_requirements.len != 0 or parameter.named_requirements.len != 0) return false;
        }
        return true;
    }
    fn fieldNames(self: Pass, values: []const ast.NodeId, count: usize) ![]const []const u8 {
        const fields = try self.allocator.alloc([]const u8, count);
        var fields_found = true;
        for (self.node(values[0]).data.tuple, fields) |id, *field| {
            const item = self.node(id);
            if (item.data != .name) {
                fields_found = false;
                break;
            }
            field.* = self.src.text(item.data.name);
        }
        if (fields_found) for (values[1..]) |id| {
            for (self.node(id).data.tuple, fields) |item, field| {
                if (self.node(item).data != .name or !std.mem.eql(u8, self.src.text(self.node(item).data.name), field)) {
                    fields_found = false;
                    break;
                }
            }
        };
        if (fields_found) for (fields, 0..) |field, i| {
            if (std.mem.eql(u8, field, "_")) fields_found = false;
            for (fields[0..i]) |previous| if (std.mem.eql(u8, field, previous)) {
                fields_found = false;
                break;
            };
        };
        if (!fields_found) {
            // Consumer-local names differ between independent roots. A shared
            // declaration must generate the same record fields in every closure.
            for (fields, 0..) |*field, i| field.* = try std.fmt.allocPrint(self.allocator, "field_{d}", .{i + 1});
        }
        return fields;
    }
    fn functionStart(self: Pass, function: ast.Function) usize {
        var start = ast.declarationStart(self.program, function.name);
        while (start > 0 and self.src.bytes[start - 1] != '\n') : (start -= 1) {}
        return start;
    }
    fn genericNames(self: Pass, function: ast.Function) ![]const u8 {
        if (function.signature.type_parameters.len == 0) return "";
        var result: std.ArrayList(u8) = .empty;
        try result.append(self.allocator, '[');
        for (function.signature.type_parameters, 0..) |parameter, i| {
            if (i != 0) try result.appendSlice(self.allocator, ", ");
            try result.appendSlice(self.allocator, self.src.text(parameter.name));
        }
        try result.append(self.allocator, ']');
        return result.items;
    }
    fn pascalName(self: Pass, function: ast.Function) ![]const u8 {
        var stem: std.ArrayList(u8) = .empty;
        var upper = true;
        for (self.src.text(function.name)) |char| {
            if (char == '_') {
                upper = true;
                continue;
            }
            try stem.append(self.allocator, if (upper) std.ascii.toUpper(char) else char);
            upper = false;
        }
        return stem.items;
    }
    fn recordName(self: Pass, function: ast.Function) ![]const u8 {
        const stem = try self.pascalName(function);
        const original = if (self.src.origins.len == 0) self.src else blk: {
            const span = self.src.originalSpan(function.name) catch return error.InternalError;
            break :blk self.src.origins[span.input].original;
        };
        const module = if (self.src.origins.len == 0) 0 else (self.src.originalSpan(function.name) catch return error.InternalError).input;
        for (self.program.functions) |other| {
            if (std.meta.eql(other.name, function.name)) continue;
            const other_module = if (self.src.origins.len == 0) 0 else (self.src.originalSpan(other.name) catch return error.InternalError).input;
            if (module != other_module) continue;
            if (std.mem.eql(u8, stem, try self.pascalName(other))) return support.freshOriginNameAt(self.allocator, self.src, stem, function.name.start) catch return error.InternalError;
        }
        return support.freshName(self.allocator, original, stem);
    }
    fn destructuringConsumer(self: Pass, span: Span) ?ast.Node {
        for (self.program.nodes.items) |value| {
            if (value.data != .field_assignment) continue;
            const assignment = value.data.field_assignment;
            if (self.node(assignment.target).data == .tuple and std.meta.eql(self.node(assignment.value).span, span)) return value;
        }
        return null;
    }
    fn sortKeyUse(self: Pass, span: Span) bool {
        for (self.program.nodes.items) |value| switch (value.data) {
            .call => |call| {
                if (!std.mem.eql(u8, self.src.text(call.name), "sorted")) continue;
                for (call.arguments, 0..) |argument, i| {
                    if (call.argument_names.len <= i or call.argument_names[i] == null) continue;
                    if (std.mem.eql(u8, self.src.text(call.argument_names[i].?), "key") and std.meta.eql(self.node(argument).span, span)) return true;
                }
            },
            .method_call => |call| {
                if (!std.mem.eql(u8, self.src.text(call.name), "sort")) continue;
                for (call.arguments, 0..) |argument, i| {
                    if (call.argument_names.len <= i or call.argument_names[i] == null) continue;
                    if (std.mem.eql(u8, self.src.text(call.argument_names[i].?), "key") and std.meta.eql(self.node(argument).span, span)) return true;
                }
            },
            else => {},
        };
        return false;
    }
    fn unpack(self: Pass, statement: Span, value: ast.Node, fields: []const []const u8) !?Edit {
        const assignment = value.data.field_assignment;
        const targets = self.targetPlaces(assignment.target, fields.len) orelse return null;
        const transfers = try self.unpackedFields(assignment.value, fields.len);
        if (statement.start != value.span.start) return null;
        const saved = support.freshOriginNameAt(self.allocator, self.src, "tuple_result", value.span.start) catch return null;
        var replacement: std.ArrayList(u8) = .empty;
        const indent = support.indentation(self.src, statement.start);
        try replacement.print(self.allocator, "const {s} = {s}", .{ saved, self.src.text(self.node(assignment.value).span) });
        // Stage all fields before any destination write, preserving simultaneous
        // assignment and managed receiver snapshots.
        const temporaries = try self.allocator.alloc([]const u8, fields.len);
        for (fields, temporaries, transfers, 0..) |field, *temporary, transfer, i| {
            const stem = try std.fmt.allocPrint(self.allocator, "tuple_field_{d}", .{i});
            temporary.* = support.freshOriginNameAt(self.allocator, self.src, stem, value.span.start) catch return null;
            // A nominal carrier cannot give away multiple fields independently:
            // snapshot each managed field before any destination changes.
            try replacement.print(self.allocator, "\n{s}const {s} = {s}{s}.{s}{s}", .{ indent, temporary.*, if (transfer) "copy(" else "", saved, field, if (transfer) ")" else "" });
        }
        for (targets, temporaries) |target, temporary| {
            const destination = self.node(target);
            if (destination.data != .name or !std.mem.eql(u8, self.src.text(destination.span), "_")) continue;
            try replacement.print(self.allocator, "\n{s}_ = {s}", .{ indent, temporary });
        }
        for (targets, temporaries, transfers) |target, temporary, transfer| {
            const destination = self.node(target);
            const name = self.src.text(destination.span);
            if (destination.data == .name and std.mem.eql(u8, name, "_")) continue;
            try replacement.print(self.allocator, "\n{s}{s}{s} = {s}{s}", .{ indent, if (assignment.declaration) |mutable| if (mutable) "mut " else "const " else "", name, if (transfer) "own " else "", temporary });
        }
        if (value.span.end > value.span.start and self.src.bytes[value.span.end - 1] == '\n') try replacement.append(self.allocator, '\n');
        return .{ .span = value.span, .text = replacement.items };
    }
    fn swap(self: Pass, statement: ast.Statement, value: ast.Node) !?Edit {
        const assignment = value.data.field_assignment;
        const inputs = self.node(assignment.value).data.tuple;
        const targets = self.targetPlaces(assignment.target, inputs.len) orelse return null;
        const temporaries = try self.allocator.alloc([]const u8, inputs.len);
        const transfers = try self.allocator.alloc(bool, inputs.len);
        var replacement: std.ArrayList(u8) = .empty;
        const indent = support.indentation(self.src, statement.span.start);
        for (inputs, temporaries, transfers, 0..) |input, *temporary, *transfer, i| {
            _ = self.snapshotBeforeReuse(input, inputs[i + 1 ..]) orelse return null;
            transfer.* = self.transferredOperand(input);
            const stem = try std.fmt.allocPrint(self.allocator, "tuple_value_{d}", .{i});
            temporary.* = support.freshOriginNameAt(self.allocator, self.src, stem, value.span.start) catch return null;
            if (i != 0) try replacement.print(self.allocator, "\n{s}", .{indent});
            const text = try self.captureOperand(input, transfer.*) orelse return null;
            try replacement.print(self.allocator, "const {s} = {s}", .{ temporary.*, text });
        }
        for (targets, temporaries) |target, temporary| {
            const destination = self.node(target);
            if (destination.data != .name or !std.mem.eql(u8, self.src.text(destination.span), "_")) continue;
            try replacement.print(self.allocator, "\n{s}_ = {s}", .{ indent, temporary });
        }
        for (targets, temporaries, transfers) |target, temporary, transfer| {
            const destination = self.node(target);
            const name = self.src.text(destination.span);
            if (destination.data == .name and std.mem.eql(u8, name, "_")) continue;
            try replacement.print(self.allocator, "\n{s}{s}{s} = {s}{s}", .{ indent, if (assignment.declaration) |mutable| if (mutable) "mut " else "const " else "", name, if (transfer) "own " else "", temporary });
        }
        if (value.span.end > value.span.start and self.src.bytes[value.span.end - 1] == '\n') try replacement.append(self.allocator, '\n');
        return .{ .span = value.span, .text = replacement.items };
    }

    /// Pending Results already transfer an obligation into the retired tuple.
    /// Preserve that transfer instead of inventing a copy of the obligation.
    fn captureOperand(self: Pass, input: ast.NodeId, transfer: bool) !?[]const u8 {
        const original = self.src.text(self.node(input).span);
        if (transfer and try self.pendingLocalTransfer(input)) {
            const captured = try std.fmt.allocPrint(self.allocator, "own {s}", .{original});
            return captured;
        }
        const text = try moves.capture(self.allocator, self.src, self.program, input, transfer);
        if (!std.mem.eql(u8, text, original) and !self.copyableOperand(input)) return null;
        return text;
    }

    /// Every concrete instance must prove the same named source owns its Result.
    /// The walk associates function-local slots with their actual function body.
    fn pendingLocalTransfer(self: Pass, input: ast.NodeId) !bool {
        const checked = self.checked orelse return false;
        const value = self.node(input);
        if (value.data != .name) return false;
        var found = false;
        for (checked.functions) |function| {
            if (!function.scope.body_complete) continue;
            var body = try typed_walk.Walker.init(self.allocator, checked.*, function.scope.body);
            defer body.deinit();
            while (try body.next()) |item| {
                if (item != .expression) continue;
                const node_value = checked.nodes[@backingInt(item.expression)];
                if (!std.meta.eql(node_value.span, value.span)) continue;
                if (!try self.ownedPendingOperand(checked, function, node_value)) return false;
                found = true;
            }
        }
        return found;
    }

    fn ownedPendingOperand(self: Pass, checked: *const typed.Program, function: typed.Function, value: typed.Node) !bool {
        if (value.data != .local) return false;
        if (!typed.requiresHandling(value.ty, checked.records)) return false;
        if (!own_parameters.managed(checked.records, value.ty)) return false;
        const slot = value.data.local;
        const local = function.scope.locals[@backingInt(slot)];
        if (local.origin == .parameter) return local.ownership.owned_parameter;
        if (local.origin != .local or local.ownership.view) return false;
        if (local.usage.temporary or local.usage.writes != 0) return false;
        var definition: ?typed.NodeId = null;
        var body = try typed_walk.Walker.init(self.allocator, checked.*, function.scope.body);
        defer body.deinit();
        while (try body.next()) |item| {
            if (item != .statement) continue;
            const statement = checked.statements[@backingInt(item.statement)].data;
            if (statement != .initialize or statement.initialize.slot != slot) continue;
            if (definition != null) return false;
            definition = statement.initialize.value;
        }
        return freshPendingDefinition(checked, definition orelse return false);
    }

    fn copyableOperand(self: Pass, input: ast.NodeId) bool {
        const checked = self.checked orelse return false;
        var found = false;
        for (checked.nodes) |node_value| {
            if (!std.meta.eql(node_value.span, self.node(input).span)) continue;
            found = true;
            var path: [64]usize = undefined;
            if (!snapshotSafe(checked, node_value.ty, &path, 0)) return false;
        }
        return found;
    }

    /// Staging a local must not move it before a later operand reads or mutates
    /// it. Copy only a checked, copyable aggregate; ambiguous generic shapes and
    /// affine values require a manual repair instead of a speculative copy.
    fn snapshotBeforeReuse(self: Pass, input: ast.NodeId, later: []const ast.NodeId) ?bool {
        const value = self.node(input);
        if (value.data != .name or !self.reusedName(value, later)) return false;
        const checked = self.checked orelse return null;
        var aggregate = false;
        var scalar = false;
        var found = false;
        for (checked.nodes) |node_value| {
            if (!std.meta.eql(node_value.span, value.span) or node_value.data != .local) continue;
            found = true;
            const ty = node_value.ty;
            var path: [64]usize = undefined;
            if (!snapshotSafe(checked, ty, &path, 0)) return null;
            if (ty.isAggregate()) {
                const schema = checked.records[ty.recordIndex()];
                if (schema.contract.callback != null or schema.isEnum() or schema.shape.domain != null) continue;
                aggregate = true;
            } else scalar = true;
        }
        if (!found or (aggregate and scalar)) return null;
        return aggregate;
    }

    fn reusedName(self: Pass, value: ast.Node, later: []const ast.NodeId) bool {
        for (later) |id| {
            const span = self.node(id).span;
            for (self.program.nodes.items) |candidate| {
                if (candidate.span.start < span.start or candidate.span.end > span.end or candidate.data != .name) continue;
                if (std.mem.eql(u8, self.src.text(value.span), self.src.text(candidate.span))) return true;
            }
        }
        return false;
    }
};

/// Places and declared from-results cannot establish an owning local capture.
fn freshPendingDefinition(program: *const typed.Program, id: typed.NodeId) bool {
    const node = program.nodes[@backingInt(id)];
    if (node.view) return false;
    if (node.own) return true;
    return switch (node.data) {
        .variant => true,
        .call => |call| program.functions[@backingInt(call.function)].signature.return_origin == .fresh,
        else => false,
    };
}

/// Explicit value copies cannot preserve shared class identity or provider
/// ownership. Inspect nested payloads too, including recursive value records.
fn snapshotSafe(program: *const typed.Program, ty: typed.Type, path: *[64]usize, depth: usize) bool {
    if (ty.isFile() or ty.capabilityIndex() != null) return false;
    if (!ty.isAggregate()) return true;
    if (typed.moveOnly(ty, program.records) or typed.requiresHandling(ty, program.records)) return false;
    const index = ty.recordIndex();
    const schema = program.records[index];
    if (schema.isManagedRecord()) return false;
    for (path[0..depth]) |seen| if (seen == index) return true;
    if (depth == path.len) return false;
    path[depth] = index;
    for (schema.fields) |field| if (!snapshotSafe(program, field.ty, path, depth + 1)) return false;
    if (schema.shape.buffer) |element| if (!snapshotSafe(program, element, path, depth + 1)) return false;
    if (schema.collection.key) |key| if (!snapshotSafe(program, key, path, depth + 1)) return false;
    if (schema.shape.array) |array| if (!snapshotSafe(program, array.element, path, depth + 1)) return false;
    if (schema.shape.variants) |variants| for (variants.cases) |case| {
        if (case.payload) |payload| if (!snapshotSafe(program, payload, path, depth + 1)) return false;
    };
    return true;
}
