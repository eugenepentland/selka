//! Compile nested enum pattern matrices into hygienic exhaustive variant matches.
const std = @import("std");
const ast = @import("ast.zig");
const typed = @import("typed.zig");
const missing_fields = "pattern must specify every enum payload field";
const source = @import("source.zig");
const diagnostic = @import("diagnostic.zig");
const Error = diagnostic.Error;
/// A matrix cell: the pattern at one key, and whether its field was labelled (a labelled
/// nested case keeps its qualifier; see `sema_statements.patternTag`).
const Cell = struct { key: []const u8, pattern: ast.Pattern, labelled: bool = false };
const Alias = struct { name: source.Span, key: []const u8 };
const Row = struct { cells: []const Cell, aliases: []const Alias, body: ast.StatementId };

/// How one match names its hidden bindings: where its first arm sits in the source, and how many names it has issued.
/// Two matches of a function never share an origin, so the names are unique among the locals the function holds at
/// once, and they depend on the match alone. They used to carry the length of the syntax node table, which grows with
/// every nested pattern an earlier body of the same check lowered, so a body that came back from a cache and one that
/// was checked named the same binding differently and stored different bytes under one key.
const Names = struct { origin: usize = 0, issued: usize = 0 };

const Matrix = struct {
    memory: std.mem.Allocator,
    tables: std.mem.Allocator,
    syntax: *ast.Program,
    src: source.Source,
    sink: *diagnostic.Sink,
    resolved: ?*@import("sema_resolved.zig").Resolved = null,
    names: Names,
    const Self = @This();
    fn allocator(self: Self) std.mem.Allocator {
        return self.memory;
    }
    fn program(self: Self) *ast.Program {
        return self.syntax;
    }
    fn key(self: *Self) Error![]const u8 {
        const name = try std.fmt.allocPrint(self.allocator(), "\x00pattern{d}.{d}", .{ self.names.origin, self.names.issued });
        self.names.issued += 1;
        _ = try self.node(name, .{ .start = 0, .end = 0 });
        return name;
    }
    fn equal(self: Self, a: source.Span, b: source.Span) bool {
        return std.mem.eql(u8, self.src.text(a), self.src.text(b));
    }
    fn node(self: Self, key_name: []const u8, span: source.Span) Error!ast.NodeId {
        const syntax = self.program();
        const id: ast.NodeId = @fromBackingInt(syntax.nodes.items.len);
        try syntax.nodes.append(self.tables, .{ .span = span, .data = .{ .synthetic_name = key_name } });
        if (self.resolved) |resolved| {
            // The node list grows geometrically, so `resolved` grows with its capacity
            // rather than by one slot per node: total growth stays linear in the nodes.
            if (resolved.slots.len < syntax.nodes.items.len) try resolved.grow(syntax.nodes.capacity);
            resolved.put(@backingInt(id), null);
        }
        return id;
    }
    fn statement(self: Self, span: source.Span, data: @FieldType(ast.Statement, "data")) Error!ast.StatementId {
        const syntax = self.program();
        const id: ast.StatementId = @fromBackingInt(syntax.statements.items.len);
        try syntax.statements.append(self.tables, .{ .span = span, .data = data });
        return id;
    }
    fn addPattern(self: Self, cells: *std.ArrayList(Cell), aliases: *std.ArrayList(Alias), key_name: []const u8, pattern: ast.Pattern, labelled: bool) Error!void {
        switch (pattern.data) {
            .variant => try cells.append(self.allocator(), .{ .key = key_name, .pattern = pattern, .labelled = labelled }),
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
        return self.sameType(a.data.variant.ty, b.data.variant.ty) and self.equal(a.data.variant.name, b.data.variant.name);
    }
    /// Two case spellings name the same type when one is bare (the matched type) or both spell
    /// the same qualifier. A bare case and a qualified one in one match group together.
    fn sameType(self: Self, a: source.Span, b: source.Span) bool {
        return a.start == a.end or b.start == b.end or self.equal(a, b);
    }
    fn field(self: Self, fields: []const ast.PatternField, exemplar: ast.PatternField, position: usize) Error!ast.PatternField {
        if (exemplar.name) |label| {
            for (fields) |item| if (item.name) |name| {
                if (self.equal(label, name)) return item;
            };
        } else if (position < fields.len) return fields[position];
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
                    const item = try self.field(matched.pattern.data.variant.fields, exemplar, position);
                    try self.addPattern(&cells, &aliases, key_name, item.pattern, item.name != null);
                }
            } else try self.addPattern(&cells, &aliases, column.key, matched.pattern, matched.labelled);
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
        return .{ .ty = variant.ty, .name = variant.name, .bindings = bindings, .binding_names = labels, .internal = .{ .names = keys, .labelled = column.labelled }, .body = try self.compile(group.items) };
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
                const item = try self.field(arm.payload_patterns, exemplar, position);
                try self.addPattern(&cells, &aliases, key_name, item.pattern, item.name != null);
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
        return .{ .ty = arm.ty, .name = arm.name, .bindings = bindings, .binding_names = labels, .internal = .{ .names = keys, .labelled = arm.internal.labelled }, .body = try self.compile(try self.initialRows(arms, fields, keys)) };
    }
};
fn nested(arm: ast.MatchArm) bool {
    for (arm.payload_patterns) |field| if (field.pattern.data == .variant) return true;
    return false;
}
/// Give a concrete checker its own copy of the node and statement lists, made the first
/// time a lowering with a nested pattern needs to append. Every later lowering in the same
/// check appends to that one copy, which grows geometrically; the caller's lists are never
/// written.
fn isolateSourceTables(comptime Checker: type, checker: *Checker, matrix: *Matrix, arms: []const ast.MatchArm) Error!void {
    var has_nested = false;
    for (arms) |arm| has_nested = has_nested or nested(arm);
    if (!has_nested or checker.tables_private) return;
    const syntax = matrix.program();
    // The copy is a snapshot: a program whose bodies are filled on demand is complete before it is taken.
    try ast.ensureAll(syntax.*);
    const allocator = matrix.tables;
    const nodes = try allocator.dupe(ast.Node, syntax.nodes.items);
    const statements = try allocator.dupe(ast.Statement, syntax.statements.items);
    syntax.nodes = .fromOwnedSlice(nodes);
    syntax.statements = .fromOwnedSlice(statements);
    checker.tables_private = true;
}

/// Compile all nested payload discriminators, retaining each source row's own binders.
/// Synthetic syntax is appended to the checker's private tables: its own copy for a
/// concrete check, or the copy the generic driver shares across bodies.
pub fn normalize(comptime Checker: type, checker: *Checker, input: []const ast.MatchArm) Error![]const ast.MatchArm {
    return normalizeInArena(Checker, checker, input, checker.allocator);
}

/// The arena owns temporary matrices, returned arms and nested syntax payloads,
/// and must outlive all uses of the appended syntax. Node and statement list
/// storage continues to use the checker's allocator, including existing tables.
pub fn normalizeInArena(comptime Checker: type, checker: *Checker, input: []const ast.MatchArm, arena: std.mem.Allocator) Error![]const ast.MatchArm {
    var matrix: Matrix = .{
        .memory = arena,
        .tables = checker.allocator,
        .syntax = if (@hasField(Checker, "syntax")) &checker.syntax else &checker.program,
        .src = checker.src,
        .sink = checker.sink,
        .resolved = if (@hasField(Checker, "resolved")) &checker.resolved else null,
        .names = .{ .origin = if (input.len == 0) 0 else input[0].name.start },
    };
    if (@hasField(Checker, "syntax")) try isolateSourceTables(Checker, checker, &matrix, input);
    var output: std.ArrayList(ast.MatchArm) = .empty;
    const used = try matrix.allocator().alloc(bool, input.len);
    @memset(used, false);
    for (input, 0..) |arm, index| {
        if (used[index]) continue;
        var group: std.ArrayList(ast.MatchArm) = .empty;
        var has_nested = false;
        for (input[index..], index..) |candidate, candidate_index| {
            if (!matrix.sameType(arm.ty, candidate.ty) or !matrix.equal(arm.name, candidate.name)) continue;
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
