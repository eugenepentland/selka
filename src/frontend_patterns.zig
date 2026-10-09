//! Compile nested enum pattern matrices into hygienic exhaustive variant matches.
const std = @import("std");
const ast = @import("ast.zig");
const typed = @import("typed.zig");
const missing_fields = "pattern must specify every enum payload field";
const source = @import("source.zig");
const diagnostic = @import("diagnostic.zig");
const Error = diagnostic.Error;
const Cell = struct { key: []const u8, pattern: ast.Pattern };
const Alias = struct { name: source.Span, key: []const u8 };
const Row = struct { cells: []const Cell, aliases: []const Alias, body: ast.StatementId };

const Matrix = struct {
    memory: std.mem.Allocator,
    syntax: *ast.Program,
    src: source.Source,
    sink: *diagnostic.Sink,
    resolved: ?struct { pointer: *[]?typed.NodeId, allocator: std.mem.Allocator } = null,
    serial: usize,
    const Self = @This();
    fn allocator(self: Self) std.mem.Allocator {
        return self.memory;
    }
    fn program(self: Self) *ast.Program {
        return self.syntax;
    }
    fn key(self: *Self) Error![]const u8 {
        self.serial = self.program().nodes.items.len;
        const name = try std.fmt.allocPrint(self.allocator(), "\x00pattern{d}", .{self.serial});
        _ = try self.node(name, .{ .start = 0, .end = 0 });
        return name;
    }
    fn equal(self: Self, a: source.Span, b: source.Span) bool {
        return std.mem.eql(u8, self.src.text(a), self.src.text(b));
    }
    fn node(self: Self, key_name: []const u8, span: source.Span) Error!ast.NodeId {
        const syntax = self.program();
        const id: ast.NodeId = @fromBackingInt(syntax.nodes.items.len);
        try syntax.nodes.append(self.allocator(), .{ .span = span, .data = .{ .synthetic_name = key_name } });
        if (self.resolved) |resolved| {
            resolved.pointer.* = try resolved.allocator.realloc(resolved.pointer.*, syntax.nodes.items.len);
            resolved.pointer.*[@backingInt(id)] = null;
        }
        return id;
    }
    fn statement(self: Self, span: source.Span, data: @FieldType(ast.Statement, "data")) Error!ast.StatementId {
        const syntax = self.program();
        const id: ast.StatementId = @fromBackingInt(syntax.statements.items.len);
        try syntax.statements.append(self.allocator(), .{ .span = span, .data = data });
        return id;
    }
    fn addPattern(self: Self, cells: *std.ArrayList(Cell), aliases: *std.ArrayList(Alias), key_name: []const u8, pattern: ast.Pattern) Error!void {
        switch (pattern.data) {
            .variant => try cells.append(self.allocator(), .{ .key = key_name, .pattern = pattern }),
            .binding => |binding| if (binding) |name| {
                try aliases.append(self.allocator(), .{ .name = name, .key = key_name });
            },
        }
    }
    fn selected(rows: []const Row) ?Cell {
        for (rows) |row| for (row.cells) |cell| if (cell.pattern.data == .variant) return cell;
        return null;
    }
    fn findCell(row: Row, key_name: []const u8) ?Cell {
        for (row.cells) |item| if (std.mem.eql(u8, item.key, key_name)) return item;
        return null;
    }
    fn sameVariant(self: Self, a: ast.Pattern, b: ast.Pattern) bool {
        if (a.data != .variant or b.data != .variant) return false;
        return self.equal(a.data.variant.ty, b.data.variant.ty) and self.equal(a.data.variant.name, b.data.variant.name);
    }
    fn field(self: Self, fields: []const ast.PatternField, exemplar: ast.PatternField, position: usize) Error!ast.Pattern {
        if (exemplar.name) |label| {
            for (fields) |item| if (item.name) |name| {
                if (self.equal(label, name)) return item.pattern;
            };
        } else if (position < fields.len) return fields[position].pattern;
        return self.sink.fail(diagnostic.pattern_payload, exemplar.pattern.span, missing_fields);
    }
    fn leaf(self: Self, rows: []const Row) Error!ast.StatementId {
        if (rows.len != 1) return self.sink.fail("E_DUPLICATE_ARM", self.program().statements.items[@backingInt(rows[1].body)].span, "nested variant combinations overlap");
        const row = rows[0];
        var statements: std.ArrayList(ast.StatementId) = .empty;
        for (row.aliases) |alias| {
            const value = try self.node(alias.key, alias.name);
            try statements.append(self.allocator(), try self.statement(alias.name, .{ .binding = .{ .name = alias.name, .annotation = null, .mutable = false, .value = value } }));
        }
        try statements.append(self.allocator(), row.body);
        return self.statement(self.program().statements.items[@backingInt(row.body)].span, .{ .block = try statements.toOwnedSlice(self.allocator()) });
    }
    fn expand(self: Self, row: Row, column: Cell, pattern: ast.Pattern, keys: []const []const u8) Error!Row {
        var cells: std.ArrayList(Cell) = .empty;
        var aliases: std.ArrayList(Alias) = .empty;
        try aliases.appendSlice(self.allocator(), row.aliases);
        for (row.cells) |item| if (!std.mem.eql(u8, item.key, column.key)) try cells.append(self.allocator(), item);
        if (findCell(row, column.key)) |matched| {
            if (matched.pattern.data == .variant) {
                if (matched.pattern.data.variant.fields.len != pattern.data.variant.fields.len)
                    return self.sink.fail(diagnostic.pattern_payload, matched.pattern.span, missing_fields);
                for (pattern.data.variant.fields, keys, 0..) |exemplar, key_name, position| {
                    try self.addPattern(&cells, &aliases, key_name, try self.field(matched.pattern.data.variant.fields, exemplar, position));
                }
            } else try self.addPattern(&cells, &aliases, column.key, matched.pattern);
        }
        return .{ .cells = try cells.toOwnedSlice(self.allocator()), .aliases = try aliases.toOwnedSlice(self.allocator()), .body = row.body };
    }
    fn variantArm(self: *Self, rows: []const Row, column: Cell, pattern: ast.Pattern) Error!ast.MatchArm {
        const variant = pattern.data.variant;
        const keys = try self.allocator().alloc([]const u8, variant.fields.len);
        const bindings = try self.allocator().alloc(?source.Span, keys.len);
        const labels = try self.allocator().alloc(?source.Span, keys.len);
        for (variant.fields, keys, bindings, labels) |item, *key_name, *binding, *label| {
            key_name.* = try self.key();
            binding.* = item.pattern.span;
            label.* = item.name;
        }
        var group: std.ArrayList(Row) = .empty;
        for (rows) |row| {
            if (findCell(row, column.key)) |matched| if (!self.sameVariant(matched.pattern, pattern)) continue;
            try group.append(self.allocator(), try self.expand(row, column, pattern, keys));
        }
        return .{ .ty = variant.ty, .name = variant.name, .bindings = bindings, .binding_names = labels, .internal = .{ .names = keys }, .body = try self.compile(group.items) };
    }
    fn compile(self: *Self, rows: []const Row) Error!ast.StatementId {
        const column = selected(rows) orelse return self.leaf(rows);
        var arms: std.ArrayList(ast.MatchArm) = .empty;
        var patterns: std.ArrayList(ast.Pattern) = .empty;
        for (rows) |row| {
            const matched = findCell(row, column.key) orelse continue;
            var duplicate = false;
            for (patterns.items) |pattern| if (self.sameVariant(pattern, matched.pattern)) {
                duplicate = true;
                break;
            };
            if (duplicate) continue;
            try patterns.append(self.allocator(), matched.pattern);
            try arms.append(self.allocator(), try self.variantArm(rows, column, matched.pattern));
        }
        var fallback: std.ArrayList(Row) = .empty;
        for (rows) |row| if (findCell(row, column.key) == null) try fallback.append(self.allocator(), row);
        if (fallback.items.len != 0) try arms.append(self.allocator(), .{
            .ty = .{ .start = column.pattern.span.start, .end = column.pattern.span.start },
            .name = column.pattern.span,
            .internal = .{ .wildcard = true },
            .body = try self.compile(fallback.items),
        });
        const value = try self.node(column.key, column.pattern.span);
        return self.statement(column.pattern.span, .{ .match = .{ .value = value, .arms = try arms.toOwnedSlice(self.allocator()) } });
    }
    fn initialRows(self: Self, arms: []const ast.MatchArm, fields: []const ast.PatternField, keys: []const []const u8) Error![]const Row {
        var rows: std.ArrayList(Row) = .empty;
        for (arms) |arm| {
            if (arm.payload_patterns.len != fields.len)
                return self.sink.fail(diagnostic.pattern_payload, arm.name, missing_fields);
            var cells: std.ArrayList(Cell) = .empty;
            var aliases: std.ArrayList(Alias) = .empty;
            for (fields, keys, 0..) |exemplar, key_name, position| {
                try self.addPattern(&cells, &aliases, key_name, try self.field(arm.payload_patterns, exemplar, position));
            }
            try rows.append(self.allocator(), .{ .cells = try cells.toOwnedSlice(self.allocator()), .aliases = try aliases.toOwnedSlice(self.allocator()), .body = arm.body });
        }
        return rows.toOwnedSlice(self.allocator());
    }
    fn normalizeGroup(self: *Self, arms: []const ast.MatchArm) Error!ast.MatchArm {
        const arm = arms[0];
        const fields = arm.payload_patterns;
        const keys = try self.allocator().alloc([]const u8, fields.len);
        const bindings = try self.allocator().alloc(?source.Span, fields.len);
        const labels = try self.allocator().alloc(?source.Span, fields.len);
        for (fields, keys, bindings, labels) |item, *key_name, *binding, *label| {
            key_name.* = try self.key();
            binding.* = item.pattern.span;
            label.* = item.name;
        }
        return .{ .ty = arm.ty, .name = arm.name, .bindings = bindings, .binding_names = labels, .internal = .{ .names = keys }, .body = try self.compile(try self.initialRows(arms, fields, keys)) };
    }
};
fn nested(arm: ast.MatchArm) bool {
    for (arm.payload_patterns) |field| if (field.pattern.data == .variant) return true;
    return false;
}
fn isolateSourceTables(matrix: *Matrix, arms: []const ast.MatchArm) Error!void {
    var has_nested = false;
    for (arms) |arm| has_nested = has_nested or nested(arm);
    if (!has_nested) return;
    const syntax = matrix.program();
    const allocator = matrix.allocator();
    const nodes = try allocator.dupe(ast.Node, syntax.nodes.items);
    const statements = try allocator.dupe(ast.Statement, syntax.statements.items);
    syntax.nodes = .{ .items = nodes, .capacity = nodes.len };
    syntax.statements = .{ .items = statements, .capacity = statements.len };
}

/// Compile all nested payload discriminators, retaining each source row's own binders.
pub fn normalize(comptime Checker: type, checker: *Checker, input: []const ast.MatchArm) Error![]const ast.MatchArm {
    var matrix: Matrix = .{
        .memory = if (@hasField(Checker, "field_arena")) checker.field_arena.allocator() else checker.allocator,
        .syntax = if (@hasField(Checker, "syntax")) &checker.syntax else &checker.program,
        .src = checker.src,
        .sink = checker.sink,
        .resolved = if (@hasField(Checker, "resolved")) .{ .pointer = &checker.resolved, .allocator = checker.allocator } else null,
        .serial = 0,
    };
    // Concrete checking borrows source tables; append only to isolated storage.
    // Generic checking already owns its tables in the function arena.
    if (@hasField(Checker, "syntax")) try isolateSourceTables(&matrix, input);
    var output: std.ArrayList(ast.MatchArm) = .empty;
    const used = try matrix.allocator().alloc(bool, input.len);
    @memset(used, false);
    for (input, 0..) |arm, index| {
        if (used[index]) continue;
        var group: std.ArrayList(ast.MatchArm) = .empty;
        var has_nested = false;
        for (input[index..], index..) |candidate, candidate_index| {
            if (!matrix.equal(arm.ty, candidate.ty) or !matrix.equal(arm.name, candidate.name)) continue;
            used[candidate_index] = true;
            has_nested = has_nested or nested(candidate);
            try group.append(matrix.allocator(), candidate);
        }
        if (!has_nested) {
            try output.appendSlice(matrix.allocator(), group.items);
            continue;
        }
        try output.append(matrix.allocator(), try matrix.normalizeGroup(group.items));
    }
    return output.toOwnedSlice(matrix.allocator());
}
