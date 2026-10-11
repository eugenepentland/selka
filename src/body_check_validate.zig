//! Bounded structural validation of scalar body graphs, not a second checker.
const std = @import("std");
const value = @import("body_check_value.zig");
const typed = @import("typed.zig");
const source = @import("source.zig");
const list_validate = @import("body_check_list_validate.zig");
const record_validate = @import("body_check_record_validate.zig");
/// Invalid producer values and allocation failures remain host failures.
pub const Error = error{ ComponentProtocol, OutOfMemory };
/// Maximum scalar expression or statement table length.
pub const table_limit = 262144;
/// Maximum aggregate functions or lexical locals.
pub const local_limit = 65536;
fn span(at: source.Span, size: usize) Error!void {
    if (at.start > at.end or at.end > size) return error.ComponentProtocol;
}
/// Validate raw syntax and namespace storage before starting a producer.
pub fn input(a: std.mem.Allocator, item: value.Input) Error!void {
    try list_validate.catalog(a, item.catalog);
    if (item.context.path.len > 16384 or item.modules.len > 4096) return error.ComponentProtocol;
    const source_limit: usize = if (item.modules.len == 0) 1048576 else 8388608 + 4096;
    if (item.context.source.len > source_limit) return error.ComponentProtocol;
    if (item.program.nodes.items.len > table_limit or item.program.statements.items.len > table_limit) return error.ComponentProtocol;
    if (item.program.functions.len > local_limit) return error.ComponentProtocol;
    try @import("parser_value_validate.zig").validate(a, item.program, item.context.source.len);
    var total: usize = 0;
    var offset: usize = 0;
    var imports: usize = 0;
    var symbols: usize = 0;
    for (item.modules, 0..) |module, id| {
        if (module.context.name.len == 0 or module.context.path.len > 16384) return error.ComponentProtocol;
        if (module.offset != offset) return error.ComponentProtocol;
        if (module.context.module != id or module.context.source.len > 1048576) return error.ComponentProtocol;
        if (module.context.source.len > 8388608 - total) return error.ComponentProtocol;
        total += module.context.source.len;
        offset += module.context.source.len + 1;
        if (module.offset > item.context.source.len or module.context.source.len > item.context.source.len - module.offset) return error.ComponentProtocol;
        if (!std.mem.eql(u8, module.context.source, item.context.source[module.offset..][0..module.context.source.len])) return error.ComponentProtocol;
        if (module.imports.len > local_limit - imports or module.symbols.len > local_limit - symbols) return error.ComponentProtocol;
        imports += module.imports.len;
        symbols += module.symbols.len;
        if (module.import_used.len != module.imports.len or module.imports.len > 4096 or module.symbols.len > local_limit) return error.ComponentProtocol;
        for (module.imports) |import| {
            if (import.target >= item.modules.len) return error.ComponentProtocol;
            try span(import.span, module.context.source.len);
        }
        if (offset > item.context.source.len or item.context.source[offset - 1] != '\n') return error.ComponentProtocol;
        for (module.symbols) |symbol| {
            try span(symbol.span, module.context.source.len);
            if (symbol.re_export) |origin| {
                if (origin.module >= item.modules.len) return error.ComponentProtocol;
                const targets = item.modules[origin.module].symbols;
                if (origin.symbol >= targets.len) return error.ComponentProtocol;
                if (targets[origin.symbol].kind != symbol.kind or targets[origin.symbol].re_export != null) return error.ComponentProtocol;
            }
        }
    }
    if (item.modules.len != 0 and offset != item.context.source.len) return error.ComponentProtocol;
    try record_validate.input(a, item);
}
fn diagnostics(items: []const value.Diagnostic, size: usize, rejecting: bool) Error!void {
    if (items.len > local_limit or (rejecting and items.len == 0)) return error.ComponentProtocol;
    var errors: usize = 0;
    for (items) |item| {
        if (item.code.len == 0 or item.message.len == 0) return error.ComponentProtocol;
        if (item.severity == .err) errors += 1;
    }
    if (rejecting and errors == 0) return error.ComponentProtocol;
    if (!rejecting and errors != 0) return error.ComponentProtocol;
    try @import("parser_value_validate.zig").ranges([]const value.Diagnostic, items, size);
}
/// Validate complete batch associations and located refusal/source diagnostics.
pub fn outcome(a: std.mem.Allocator, request: value.Input, result: value.Outcome) Error!void {
    switch (result) {
        .failure => |items| try diagnostics(items, request.context.source.len, true),
        .profile => |refusal| {
            if (!std.mem.eql(u8, refusal.code, "P_BODY_PROFILE") or refusal.message.len == 0) return error.ComponentProtocol;
            try span(refusal.span, request.context.source.len);
        },
        .success => |output| {
            try record_validate.success(a, request);
            try diagnostics(output.diagnostics, request.context.source.len, false);
            if (output.import_used.len != request.modules.len) return error.ComponentProtocol;
            for (output.import_used, request.modules) |flags, module| {
                if (flags.len != module.import_used.len) return error.ComponentProtocol;
                for (flags, module.import_used) |used, initial| if (initial and !used) return error.ComponentProtocol;
            }
            try list_validate.recipes(a, request, output.lists);
            var expanded = request;
            expanded.catalog = try list_validate.expanded(a, request.catalog, output.lists);
            defer a.free(expanded.catalog.lists);
            try batch(a, expanded, output.batch);
        },
    }
}
const Work = union(enum) { node: usize, statement: usize, finish_node: usize, finish_statement: usize };
const GraphContext = struct { source_len: usize, catalog: value.Catalog, accepted: []const bool };
const Graph = struct {
    allocator: std.mem.Allocator,
    tables: value.Batch,
    context: GraphContext,
    locals: usize,
    function: usize = 0,
    pending: std.ArrayList(Work) = .empty,
    visits: usize = 0,
    fn push(self: *Graph, work: Work) Error!void {
        if (self.visits == 4194304) return error.ComponentProtocol;
        self.visits += 1;
        try self.pending.append(self.allocator, work);
    }
    fn fields(self: *Graph, comptime T: type, item: T) Error!void {
        @setEvalBranchQuota(200000);
        if (T == source.Span) return span(item, self.context.source_len);
        if (T == typed.NodeId) return self.push(.{ .node = @backingInt(item) });
        if (T == typed.StatementId) return self.push(.{ .statement = @backingInt(item) });
        if (T == typed.LocalId) {
            if (@backingInt(item) >= self.locals) return error.ComponentProtocol;
            return;
        }
        if (T == typed.FunctionId) {
            if (@backingInt(item) >= self.tables.functions.len) return error.ComponentProtocol;
            return;
        }
        if (T == typed.Type) {
            if (!admittedType(self.context.catalog, self.context.accepted, item)) return error.ComponentProtocol;
            return;
        }
        switch (@typeInfo(T)) {
            .optional => |info| if (item) |present| try self.fields(info.child, present),
            .pointer => |info| {
                if (info.size != .slice) @compileError("body values require slices");
                if (info.child != u8) for (item) |child| try self.fields(info.child, child);
            },
            .array => |info| for (item) |child| try self.fields(info.child, child),
            .@"struct" => |info| inline for (info.field_names, info.field_types) |name, Field| try self.fields(Field, @field(item, name)),
            .@"union" => |info| inline for (info.field_names, info.field_types) |name, Field| {
                if (std.mem.eql(u8, @tagName(item), name)) try self.fields(Field, @field(item, name));
            },
            else => {},
        }
    }
};
fn batch(a: std.mem.Allocator, request: value.Input, tables: value.Batch) Error!void {
    if (tables.nodes.len > table_limit or tables.statements.len > table_limit) return error.ComponentProtocol;
    if (tables.functions.len != request.program.functions.len or tables.ranges.len != tables.functions.len) return error.ComponentProtocol;
    try ranges(tables);
    const node_owners = try a.alloc(usize, tables.nodes.len);
    defer a.free(node_owners);
    const statement_owners = try a.alloc(usize, tables.statements.len);
    defer a.free(statement_owners);
    @memset(node_owners, std.math.maxInt(usize));
    @memset(statement_owners, std.math.maxInt(usize));
    const node_states = try a.alloc(u8, tables.nodes.len);
    defer a.free(node_states);
    const statement_states = try a.alloc(u8, tables.statements.len);
    defer a.free(statement_states);
    @memset(node_states, 0);
    @memset(statement_states, 0);
    const accepted = try record_validate.policy(a, request.catalog);
    defer a.free(accepted);
    var graph: Graph = .{ .allocator = a, .tables = tables, .context = .{ .source_len = request.context.source.len, .catalog = request.catalog, .accepted = accepted }, .locals = 0 };
    defer graph.pending.deinit(a);
    var locals: usize = 0;
    for (tables.functions, request.program.functions, 0..) |function, raw, id| {
        if (@backingInt(function.id) != id or !std.meta.eql(function.declaration, raw.name)) return error.ComponentProtocol;
        if (function.scope.locals.len > local_limit - locals) return error.ComponentProtocol;
        locals += function.scope.locals.len;
        if (function.signature.parameter_count > function.scope.locals.len) return error.ComponentProtocol;
        if (function.type_arguments.len != 0 or function.signature.constant_arguments.len != 0) return error.ComponentProtocol;
        try functionMetadata(request, function, raw);
        try functionName(request, function);
        graph.locals = function.scope.locals.len;
        graph.function = id;
        const owned = tables.ranges[id];
        try controlFlow(a, tables, owned);
        for (owned.nodes.start..owned.nodes.end) |index| node_owners[index] = id;
        for (owned.statements.start..owned.statements.end) |index| statement_owners[index] = id;
        for (owned.nodes.start..owned.nodes.end) |index| try graph.push(.{ .node = index });
        for (owned.statements.start..owned.statements.end) |index| try graph.push(.{ .statement = index });
        try graph.fields(typed.Function, function);
        while (graph.pending.pop()) |work| switch (work) {
            .node => |index| {
                if (index >= tables.nodes.len) return error.ComponentProtocol;
                if (node_states[index] == 1) return error.ComponentProtocol;
                if (node_owners[index] != id) return error.ComponentProtocol;
                if (node_states[index] == 2) continue;
                node_states[index] = 1;
                try scalarNode(&graph, tables.nodes[index]);
                try graph.push(.{ .finish_node = index });
                try graph.fields(typed.Node, tables.nodes[index]);
            },
            .statement => |index| {
                if (index >= tables.statements.len) return error.ComponentProtocol;
                if (statement_states[index] == 1) return error.ComponentProtocol;
                if (statement_owners[index] != id) return error.ComponentProtocol;
                if (statement_states[index] == 2) continue;
                statement_states[index] = 1;
                try scalarStatement(&graph, tables.statements[index]);
                try graph.push(.{ .finish_statement = index });
                try graph.fields(typed.Statement, tables.statements[index]);
            },
            .finish_node => |index| node_states[index] = 2,
            .finish_statement => |index| statement_states[index] = 2,
        };
    }
    for (node_owners) |owner| if (owner == std.math.maxInt(usize)) return error.ComponentProtocol;
    for (statement_owners) |owner| if (owner == std.math.maxInt(usize)) return error.ComponentProtocol;
}

fn scalarNode(graph: *Graph, node: typed.Node) Error!void {
    switch (node.data) {
        .integer => |number| {
            const valid = switch (node.ty) {
                .i64 => std.math.cast(i64, number) != null,
                .u8 => number >= 0 and number <= 255,
                .u64 => number >= 0 and number <= std.math.maxInt(i64),
                .u32 => number >= 0 and number <= 0x10ffff and !(number >= 0xd800 and number <= 0xdfff),
                else => false,
            };
            if (!valid) return error.ComponentProtocol;
        },
        .boolean => if (node.ty != .bool) return error.ComponentProtocol,
        .unit => if (node.ty != .unit) return error.ComponentProtocol,
        .local => |slot| {
            if (@backingInt(slot) >= graph.locals) return error.ComponentProtocol;
            if (node.ty != graph.tables.functions[graph.function].scope.locals[@backingInt(slot)].ty) return error.ComponentProtocol;
        },
        .call => |call| {
            if (@backingInt(call.function) >= graph.tables.functions.len) return error.ComponentProtocol;
            const target = graph.tables.functions[@backingInt(call.function)];
            if (call.arguments.len != target.signature.parameter_count or node.ty != target.signature.return_type) return error.ComponentProtocol;
            if (target.scope.locals.len < call.arguments.len) return error.ComponentProtocol;
            for (call.arguments, 0..) |argument, index| {
                if (try nodeType(graph, argument) != target.scope.locals[index].ty) return error.ComponentProtocol;
            }
            try permutation(graph.allocator, call.evaluation_order, call.arguments.len);
        },
        .block_value => |block| if (node.ty != try nodeType(graph, block.value)) return error.ComponentProtocol,
        .cast => |operand| {
            const input_type = try nodeType(graph, operand);
            const scalar_conversion = node.ty == .i64 and (input_type == .bool or input_type == .u8 or input_type == .u64);
            if (node.ty != input_type and !scalar_conversion) return error.ComponentProtocol;
        },
        .acquire_buffer => |operation| {
            if (list_validate.listElement(graph.context.catalog, node.ty) == null or try nodeType(graph, operation.capacity) != .i64) return error.ComponentProtocol;
        },
        .buffer_operation => |operation| try bufferNode(graph, node, operation),
        .record => |fields| try recordNode(graph, node.ty, fields, true),
        .update => |update| {
            if (node.ty != try nodeType(graph, update.base)) return error.ComponentProtocol;
            try recordNode(graph, node.ty, update.fields, false);
        },
        .field => |field| {
            const record = try recordSchema(graph, try nodeType(graph, field.base));
            if (field.index >= record.fields.len or node.ty != record.fields[field.index].ty) return error.ComponentProtocol;
        },
        .array => |items| {
            const element = sequenceElement(graph.context.catalog, node.ty) orelse return error.ComponentProtocol;
            for (items) |item| if (try nodeType(graph, item) != element) return error.ComponentProtocol;
        },
        .length => |operand| {
            if (node.ty != .i64 or sequenceElement(graph.context.catalog, try nodeType(graph, operand)) == null) return error.ComponentProtocol;
        },
        .index => |operation| {
            const owner = try nodeType(graph, operation.base);
            const element = sequenceElement(graph.context.catalog, owner) orelse return error.ComponentProtocol;
            const expected = if (element == .u32) owner else element;
            if (node.ty != expected or try nodeType(graph, operation.index) != .i64 or operation.from_end) return error.ComponentProtocol;
        },
        .unary => |operation| {
            const expected: typed.Type = switch (operation.op) {
                .neg => .i64,
                .not => .bool,
                else => return error.ComponentProtocol,
            };
            if (node.ty != expected or try nodeType(graph, operation.operand) != expected) return error.ComponentProtocol;
        },
        .binary => |operation| try binaryNode(graph, node, operation),
        else => return error.ComponentProtocol,
    }
}

fn ranges(tables: value.Batch) Error!void {
    var node: usize = 0;
    var statement: usize = 0;
    for (tables.ranges) |range| {
        if (range.nodes.start != node or range.statements.start != statement) return error.ComponentProtocol;
        if (range.nodes.end < node or range.nodes.end > tables.nodes.len) return error.ComponentProtocol;
        if (range.statements.end < statement or range.statements.end > tables.statements.len) return error.ComponentProtocol;
        node = range.nodes.end;
        statement = range.statements.end;
    }
    if (node != tables.nodes.len or statement != tables.statements.len) return error.ComponentProtocol;
}

fn functionMetadata(request: value.Input, function: typed.Function, raw: @import("ast.zig").Function) Error!void {
    if (function.signature.parameter_count != raw.signature.parameters.len) return error.ComponentProtocol;
    if (function.scope.parameter_labels.len != function.signature.parameter_count) return error.ComponentProtocol;
    if (function.policy.c_abi or function.policy.owner != null or function.policy.host != null) return error.ComponentProtocol;
    if (function.policy.restricted != raw.policy.restricted or function.policy.conversion != raw.policy.conversion) return error.ComponentProtocol;
    if (!std.meta.eql(function.policy.effect_bound, raw.policy.effect_bound)) return error.ComponentProtocol;
    for (raw.signature.parameters, function.scope.parameter_labels, 0..) |parameter, label, index| {
        const expected = if (parameter.named) request.context.source[parameter.name.start..parameter.name.end] else "";
        if (!std.mem.eql(u8, label, expected)) return error.ComponentProtocol;
        const local = function.scope.locals[index];
        if (!std.meta.eql(local.declaration, parameter.name) or local.mutable != parameter.mut) return error.ComponentProtocol;
        const parameter_origin = local.origin == .parameter or (parameter.mut and local.origin == .local);
        if (!parameter_origin) return error.ComponentProtocol;
        if (!std.mem.eql(u8, local.name, request.context.source[parameter.name.start..parameter.name.end])) return error.ComponentProtocol;
    }
    if (!std.mem.eql(u16, function.signature.declared_mutates, raw.signature.mut_positions)) return error.ComponentProtocol;
    for (function.scope.locals) |local| {
        if (local.ownership.scoped_file or local.ownership.transfer_span != null or local.ownership.transfer_available) return error.ComponentProtocol;
    }
    if (function.signature.return_origin == .params) {
        var prior: ?u16 = null;
        for (function.signature.return_origin.params) |parameter| {
            if (parameter >= function.signature.parameter_count) return error.ComponentProtocol;
            if (prior) |previous| if (parameter <= previous) return error.ComponentProtocol;
            prior = parameter;
        }
    }
}
fn permutation(a: std.mem.Allocator, order: []const usize, size: usize) Error!void {
    if (order.len == 0) return;
    if (order.len != size) return error.ComponentProtocol;
    const seen = try a.alloc(bool, size);
    defer a.free(seen);
    @memset(seen, false);
    for (order) |index| {
        if (index >= size or seen[index]) return error.ComponentProtocol;
        seen[index] = true;
    }
}
fn nodeType(graph: *Graph, id: typed.NodeId) Error!typed.Type {
    if (@backingInt(id) >= graph.tables.nodes.len) return error.ComponentProtocol;
    return graph.tables.nodes[@backingInt(id)].ty;
}
fn scalarStatement(graph: *Graph, statement: typed.Statement) Error!void {
    switch (statement.data) {
        .ret => |id| if (try nodeType(graph, id) != graph.tables.functions[graph.function].signature.return_type) return error.ComponentProtocol,
        .branch => |branch| if (try nodeType(graph, branch.condition) != .bool) return error.ComponentProtocol,
        .loop => |loop| if (try nodeType(graph, loop.condition) != .bool) return error.ComponentProtocol,
        .assertion => |assertion| if (try nodeType(graph, assertion.condition) != .bool) return error.ComponentProtocol,
        .initialize, .assign => |store| {
            if (store.element or @backingInt(store.slot) >= graph.locals) return error.ComponentProtocol;
            if (try nodeType(graph, store.value) != graph.tables.functions[graph.function].scope.locals[@backingInt(store.slot)].ty) return error.ComponentProtocol;
        },
        .range_loop => |loop| if (loop.parts.len != 1) return error.ComponentProtocol,
        .block, .discard, .loop_exit => {},
        else => return error.ComponentProtocol,
    }
}

fn functionName(request: value.Input, function: typed.Function) Error!void {
    const at = function.declaration;
    try span(at, request.context.source.len);
    const name = request.context.source[at.start..at.end];
    if (request.modules.len == 0) {
        if (!std.mem.eql(u8, name, function.name)) return error.ComponentProtocol;
        return;
    }
    var low: usize = 0;
    var high = request.modules.len;
    while (low < high) {
        const middle = low + (high - low) / 2;
        if (request.modules[middle].offset <= at.start) low = middle + 1 else high = middle;
    }
    if (low == 0) return error.ComponentProtocol;
    const module = request.modules[low - 1];
    if (at.end > module.offset + module.context.source.len) return error.ComponentProtocol;
    const prefix = module.context.name;
    if (function.name.len != prefix.len + 2 + name.len) return error.ComponentProtocol;
    if (!std.mem.eql(u8, function.name[0..prefix.len], prefix)) return error.ComponentProtocol;
    if (!std.mem.eql(u8, function.name[prefix.len..][0..2], "::")) return error.ComponentProtocol;
    if (!std.mem.eql(u8, function.name[prefix.len + 2 ..], name)) return error.ComponentProtocol;
}

fn controlFlow(a: std.mem.Allocator, tables: value.Batch, owned: @import("semantic_copy.zig").Range) Error!void {
    var loops: std.AutoHashMapUnmanaged(usize, void) = .empty;
    defer loops.deinit(a);
    for (tables.statements[owned.statements.start..owned.statements.end]) |statement| {
        switch (statement.data) {
            .loop => |loop| try loops.put(a, loop.id, {}),
            .range_loop => |loop| {
                if (loop.parts.len != 1) return error.ComponentProtocol;
                try loops.put(a, loop.parts[0].loop.id, {});
            },
            else => {},
        }
    }
    for (tables.statements[owned.statements.start..owned.statements.end]) |statement| {
        if (statement.data == .loop_exit and !loops.contains(statement.data.loop_exit.target)) return error.ComponentProtocol;
    }
}

fn sequenceElement(item: value.Catalog, ty: typed.Type) ?typed.Type {
    if (item.string) |entry| if (ty == entry.id) return entry.element;
    if (item.bytes) |entry| if (ty == entry.id) return entry.element;
    return list_validate.listElement(item, ty);
}
fn admittedType(item: value.Catalog, accepted: []const bool, ty: typed.Type) bool {
    if (ty.isAggregate()) return ty.recordIndex() < accepted.len and accepted[ty.recordIndex()];
    return switch (ty) {
        .i64, .bool, .unit, .u8, .u32, .u64 => true,
        else => sequenceElement(item, ty) != null,
    };
}

fn binaryNode(graph: *Graph, node: typed.Node, operation: @FieldType(@FieldType(typed.Node, "data"), "binary")) Error!void {
    const left = try nodeType(graph, operation.left);
    const right = try nodeType(graph, operation.right);
    if (left != right) return error.ComponentProtocol;
    if (list_validate.listElement(graph.context.catalog, left) != null) {
        const result: typed.Type = switch (operation.op) {
            .add => left,
            .eq, .ne => .bool,
            else => return error.ComponentProtocol,
        };
        if (node.ty != result) return error.ComponentProtocol;
        return;
    }
    if (sequenceElement(graph.context.catalog, left) != null) {
        const result: typed.Type = switch (operation.op) {
            .add => left,
            .eq, .ne, .lt, .le, .gt, .ge => .bool,
            else => return error.ComponentProtocol,
        };
        if (node.ty != result) return error.ComponentProtocol;
        return;
    }
    const result: typed.Type = switch (operation.op) {
        .logical_and, .logical_or => if (left == .bool) .bool else return error.ComponentProtocol,
        .eq, .ne => .bool,
        .lt, .le, .gt, .ge => if (left == .i64) .bool else return error.ComponentProtocol,
        .f64_add, .f64_sub, .f64_mul, .f64_div, .f64_eq, .f64_lt, .f64_le => return error.ComponentProtocol,
        else => if (left == .i64) .i64 else return error.ComponentProtocol,
    };
    if (node.ty != result) return error.ComponentProtocol;
}

fn bufferNode(graph: *Graph, node: typed.Node, operation: @FieldType(@FieldType(typed.Node, "data"), "buffer_operation")) Error!void {
    if (@backingInt(operation.owner) >= graph.locals) return error.ComponentProtocol;
    const owner = graph.tables.functions[graph.function].scope.locals[@backingInt(operation.owner)].ty;
    const element = list_validate.listElement(graph.context.catalog, owner) orelse return error.ComponentProtocol;
    if (operation.arguments.len != operation.kind.arity()) return error.ComponentProtocol;
    if (operation.kind == .sort and !sortableListElement(graph.context.catalog, element)) return error.ComponentProtocol;
    const expected: typed.Type = switch (operation.kind) {
        .length, .capacity => .u64,
        .read, .pop, .pop_at => element,
        .contains => .bool,
        .index_of => .i64,
        .copy => owner,
        .append, .write, .iteration_check, .extend, .insert, .remove, .reverse, .sort, .clear => .unit,
        else => return error.ComponentProtocol,
    };
    if (node.ty != expected) return error.ComponentProtocol;
    for (operation.arguments, 0..) |argument, index| {
        const wanted: typed.Type = switch (operation.kind) {
            .read, .pop_at => .i64,
            .iteration_check => .i64,
            .write, .insert => if (index == 0) .i64 else element,
            .extend => owner,
            .append, .contains, .remove, .index_of => element,
            else => return error.ComponentProtocol,
        };
        if (try nodeType(graph, argument) != wanted) return error.ComponentProtocol;
    }
}

fn sortableListElement(catalog: value.Catalog, element: typed.Type) bool {
    if (element == .i64) return true;
    if (catalog.string) |sequence| if (sequence.id == element) return true;
    if (catalog.bytes) |sequence| if (sequence.id == element) return true;
    return false;
}

fn recordSchema(graph: *Graph, ty: typed.Type) Error!typed.Record {
    if (!ty.isAggregate() or ty.recordIndex() >= graph.context.catalog.records.len) return error.ComponentProtocol;
    if (!graph.context.accepted[ty.recordIndex()]) return error.ComponentProtocol;
    const record = graph.context.catalog.records[ty.recordIndex()];
    if (!record_validate.ordinary(record)) return error.ComponentProtocol;
    return record;
}
fn recordNode(graph: *Graph, ty: typed.Type, fields: []const typed.FieldInit, complete: bool) Error!void {
    const record = try recordSchema(graph, ty);
    if (fields.len > record.fields.len or (complete and fields.len != record.fields.len)) return error.ComponentProtocol;
    const seen = try graph.allocator.alloc(bool, record.fields.len);
    defer graph.allocator.free(seen);
    @memset(seen, false);
    for (fields) |field| {
        if (field.index >= record.fields.len) return error.ComponentProtocol;
        if (seen[field.index] or try nodeType(graph, field.value) != record.fields[field.index].ty) return error.ComponentProtocol;
        seen[field.index] = true;
    }
}
