//! Scope and type checking use resolved binding identities, including advisory use counts.
const std = @import("std");
const ast = @import("ast.zig");
const typed = @import("typed.zig");
const source = @import("source.zig");
const diagnostic = @import("diagnostic.zig");
const records = @import("records.zig");
const Error = diagnostic.Error;
const Work = struct { id: ast.NodeId, emit: bool = false };
const CheckedStatement = struct { id: typed.StatementId, terminates: bool };

const Checker = struct {
    allocator: std.mem.Allocator,
    src: source.Source,
    syntax: ast.Program,
    sink: *diagnostic.Sink,
    nodes: std.ArrayList(typed.Node) = .empty,
    statements: std.ArrayList(typed.Statement) = .empty,
    locals: std.ArrayList(typed.Local) = .empty,
    active: std.StringHashMapUnmanaged(typed.LocalId) = .empty,
    resolved: []?typed.NodeId,
    functions: std.StringHashMapUnmanaged(typed.FunctionId) = .empty,
    return_type: typed.Type = .i64,
    catalog: records.Catalog,
    conversion_fields: ?[]bool = null,
    owner: ?typed.Type = null,

    fn ty(self: *Checker, span: source.Span) Error!typed.Type {
        return self.catalog.resolve(self.src, span, self.sink);
    }
    fn requireDomainAccess(self: *Checker, domain_type: typed.Type, span: source.Span) Error!void {
        if (self.owner != domain_type) return self.sink.failRelated("E_PRIVATE_DOMAIN", span, "only functions declared inside this domain can access its representation; use its factories and accessors", .{ .span = self.catalog.records[domain_type.recordIndex()].declaration, .message = "domain representation is private here" });
    }
    fn fields(self: *Checker, record_type: typed.Type, initializers: []const ast.FieldInit, complete: bool, span: source.Span) Error![]const typed.FieldInit {
        const record = if (complete) try self.catalog.constructor(record_type, span, self.sink) else try self.catalog.record(record_type, span, self.sink);
        const table_key = record.tableKey();
        const seen = try self.allocator.alloc(bool, record.fields.len);
        defer self.allocator.free(seen);
        @memset(seen, false);
        const checked = try self.allocator.alloc(typed.FieldInit, initializers.len);
        for (initializers, checked) |field, *out| {
            const index = if (table_key) |key| try self.catalog.variant(key, self.src, field.name, self.sink) else try self.catalog.field(record_type, self.src, field.name, self.sink);
            if (seen[index]) return self.sink.fail(if (table_key != null) "E_DUPLICATE_KEY" else "E_DUPLICATE_FIELD", field.name, "named entry is initialized more than once");
            seen[index] = true;
            const value = self.resolved[@backingInt(field.value)].?;
            try self.require(self.nodes.items[@backingInt(value)].ty, record.fields[index].ty, self.syntax.nodes.items[@backingInt(field.value)].span);
            out.* = .{ .index = index, .value = value };
        }
        if (complete) for (seen, record.fields) |present, field| {
            if (!present) {
                const message = try std.fmt.allocPrint(self.allocator, "missing initializer for {s} `{s}` of `{s}`", .{ if (table_key != null) "key" else "field", field.name, record.name });
                return self.sink.failRelated(if (table_key != null) "E_INCOMPLETE_TABLE" else "E_INCOMPLETE_CONSTRUCTION", span, message, .{ .span = field.declaration, .message = "missing entry declared here" });
            }
        };
        return checked;
    }
    fn queueFields(self: *Checker, work: *std.ArrayList(Work), initializers: []const ast.FieldInit) Error!void {
        var i = initializers.len;
        while (i > 0) {
            i -= 1;
            try work.append(self.allocator, .{ .id = initializers[i].value });
        }
    }
    fn require(self: *Checker, actual: typed.Type, expected: typed.Type, span: source.Span) Error!void {
        if (actual != expected) {
            const message = try std.fmt.allocPrint(self.allocator, "expected {s}, found {s}", .{ typed.typeName(expected, self.catalog.records), typed.typeName(actual, self.catalog.records) });
            return self.sink.fail("E_TYPE", span, message);
        }
    }
    fn resolve(self: *Checker, name: source.Span) Error!typed.LocalId {
        return self.active.get(self.src.text(name)) orelse self.sink.fail("E_UNKNOWN_NAME", name, "name is not defined in this scope");
    }
    const Literal = struct { ty: typed.Type, value: i128 };
    fn literal(self: *Checker, span: source.Span, allow_minimum: bool) Error!Literal {
        const text = self.src.text(span);
        var digits: usize = 0;
        while (digits < text.len and std.ascii.isDigit(text[digits])) digits += 1;
        const literal_type: typed.Type = if (digits == text.len) .i64 else typed.Type.fromName(text[digits..]) orelse
            return self.sink.fail("E_INTEGER_SUFFIX", span, "unknown integer suffix; use i8/i16/i32/i64 or u8/u16/u32/u64");
        if (!literal_type.isInteger()) return self.sink.fail("E_INTEGER_SUFFIX", span, "integer suffix must name an integer type");
        const magnitude = std.fmt.parseUnsigned(u128, text[0..digits], 10) catch
            return self.sink.fail("E_INTEGER_RANGE", span, "integer literal magnitude is too large");
        const maximum: u128 = @intCast(literal_type.max() + @as(i128, if (allow_minimum and literal_type.integer().?.signed) 1 else 0));
        if (magnitude > maximum) return self.sink.fail("E_INTEGER_RANGE", span, "integer literal does not fit its type; signed minimum magnitudes must be directly negated");
        return .{ .ty = literal_type, .value = @intCast(magnitude) };
    }
    fn minimum(self: *Checker, node: ast.Node) Error!?Literal {
        if (node.data != .unary or node.data.unary.op != .neg) return null;
        const child = self.syntax.nodes.items[@backingInt(node.data.unary.operand)];
        if (child.data != .integer) return null;
        const parsed = try self.literal(child.data.integer, true);
        if (parsed.ty.integer().?.signed and parsed.value == -parsed.ty.min()) return .{ .ty = parsed.ty, .value = -parsed.value };
        return null;
    }
    fn requireIndex(self: *Checker, array: typed.Array, actual: typed.Type, span: source.Span) Error!void {
        if (array.key) |key| try self.require(actual, key, span) else try self.requireInteger(actual, span);
    }
    fn requireInteger(self: *Checker, actual: typed.Type, span: source.Span) Error!void {
        if (!actual.isInteger()) return self.sink.fail("E_TYPE", span, "operation requires an integer type");
    }
    fn expression(self: *Checker, root: ast.NodeId) Error!typed.NodeId {
        var work: std.ArrayList(Work) = .empty;
        defer work.deinit(self.allocator);
        try work.append(self.allocator, .{ .id = root });
        while (work.pop()) |task| {
            const index = @backingInt(task.id);
            if (self.resolved[index] != null) continue;
            const node = self.syntax.nodes.items[index];
            const minimum_literal = try self.minimum(node);
            if (!task.emit and minimum_literal == null) {
                switch (node.data) {
                    .variant => |variant| {
                        if (variant.value) |value| {
                            try work.append(self.allocator, .{ .id = task.id, .emit = true });
                            try work.append(self.allocator, .{ .id = value });
                            continue;
                        }
                    },
                    .array => |array| {
                        try work.append(self.allocator, .{ .id = task.id, .emit = true });
                        var i = array.values.len;
                        while (i > 0) {
                            i -= 1;
                            try work.append(self.allocator, .{ .id = array.values[i] });
                        }
                        continue;
                    },
                    .index => |access| {
                        try work.append(self.allocator, .{ .id = task.id, .emit = true });
                        try work.append(self.allocator, .{ .id = access.index });
                        try work.append(self.allocator, .{ .id = access.base });
                        continue;
                    },
                    .replace => |replace| {
                        try work.append(self.allocator, .{ .id = task.id, .emit = true });
                        try work.append(self.allocator, .{ .id = replace.value });
                        try work.append(self.allocator, .{ .id = replace.index });
                        try work.append(self.allocator, .{ .id = replace.base });
                        continue;
                    },
                    .length, .unwrap => |base| {
                        try work.append(self.allocator, .{ .id = task.id, .emit = true });
                        try work.append(self.allocator, .{ .id = base });
                        continue;
                    },
                    .cast, .wrap => |cast| {
                        try work.append(self.allocator, .{ .id = task.id, .emit = true });
                        try work.append(self.allocator, .{ .id = cast.value });
                        continue;
                    },
                    .record => |record| {
                        try work.append(self.allocator, .{ .id = task.id, .emit = true });
                        try self.queueFields(&work, record.fields);
                        continue;
                    },
                    .update => |update| {
                        try work.append(self.allocator, .{ .id = task.id, .emit = true });
                        try self.queueFields(&work, update.fields);
                        try work.append(self.allocator, .{ .id = update.base });
                        continue;
                    },
                    .field => |field| {
                        try work.append(self.allocator, .{ .id = task.id, .emit = true });
                        try work.append(self.allocator, .{ .id = field.base });
                        continue;
                    },
                    .call => |call| {
                        try work.append(self.allocator, .{ .id = task.id, .emit = true });
                        var i = call.arguments.len;
                        while (i > 0) {
                            i -= 1;
                            try work.append(self.allocator, .{ .id = call.arguments[i] });
                        }
                        continue;
                    },
                    .unary => |u| {
                        try work.append(self.allocator, .{ .id = task.id, .emit = true });
                        try work.append(self.allocator, .{ .id = u.operand });
                        continue;
                    },
                    .binary => |b| {
                        try work.append(self.allocator, .{ .id = task.id, .emit = true });
                        try work.append(self.allocator, .{ .id = b.right });
                        try work.append(self.allocator, .{ .id = b.left });
                        continue;
                    },
                    else => {},
                }
            }
            var out: typed.Node = .{ .span = node.span, .ty = .i64, .data = undefined };
            if (minimum_literal) |parsed| {
                out.ty = parsed.ty;
                out.data = .{ .integer = parsed.value };
            } else switch (node.data) {
                .variant => |variant| {
                    out.ty = try self.ty(variant.ty);
                    const tag = try self.catalog.variant(out.ty, self.src, variant.name, self.sink);
                    const schema = (try self.catalog.variants(out.ty, node.span, self.sink)).cases[tag];
                    const value = if (variant.value) |input| self.resolved[@backingInt(input)].? else null;
                    if ((schema.payload != null) != (value != null)) return self.sink.failRelated("E_VARIANT_PAYLOAD", node.span, "construction must supply exactly the payload declared for this variant", .{ .span = schema.declaration, .message = "variant declared here" });
                    if (value) |input| try self.require(self.nodes.items[@backingInt(input)].ty, schema.payload.?, self.syntax.nodes.items[@backingInt(variant.value.?)].span);
                    out.data = .{ .variant = .{ .tag = tag, .value = value } };
                },
                .array => |array| {
                    out.ty = try self.ty(array.ty);
                    const schema = try self.catalog.array(out.ty, array.ty, self.sink);
                    if (schema.key != null) return self.sink.fail("E_TABLE_CONSTRUCTION", node.span, "enum-indexed tables require named initializers for every enum case");
                    if (array.values.len != schema.length) return self.sink.fail("E_ARRAY_ARITY", node.span, "array construction must initialize exactly its declared number of elements");
                    const values = try self.allocator.alloc(typed.NodeId, array.values.len);
                    for (array.values, values) |input, *value| {
                        value.* = self.resolved[@backingInt(input)].?;
                        try self.require(self.nodes.items[@backingInt(value.*)].ty, schema.element, self.syntax.nodes.items[@backingInt(input)].span);
                    }
                    out.data = .{ .array = values };
                },
                .index => |access| {
                    const base = self.resolved[@backingInt(access.base)].?;
                    const index_value = self.resolved[@backingInt(access.index)].?;
                    const schema = try self.catalog.array(self.nodes.items[@backingInt(base)].ty, node.span, self.sink);
                    try self.requireIndex(schema, self.nodes.items[@backingInt(index_value)].ty, self.syntax.nodes.items[@backingInt(access.index)].span);
                    out.ty = schema.element;
                    out.data = .{ .index = .{ .base = base, .index = index_value } };
                },
                .replace => |replace| {
                    const base = self.resolved[@backingInt(replace.base)].?;
                    const index_value = self.resolved[@backingInt(replace.index)].?;
                    const value = self.resolved[@backingInt(replace.value)].?;
                    out.ty = self.nodes.items[@backingInt(base)].ty;
                    const schema = try self.catalog.array(out.ty, node.span, self.sink);
                    try self.requireIndex(schema, self.nodes.items[@backingInt(index_value)].ty, self.syntax.nodes.items[@backingInt(replace.index)].span);
                    try self.require(self.nodes.items[@backingInt(value)].ty, schema.element, self.syntax.nodes.items[@backingInt(replace.value)].span);
                    out.data = .{ .replace = .{ .base = base, .index = index_value, .value = value } };
                },
                .length => |input| {
                    const base = self.resolved[@backingInt(input)].?;
                    _ = try self.catalog.array(self.nodes.items[@backingInt(base)].ty, node.span, self.sink);
                    out.ty = .u64;
                    out.data = .{ .length = base };
                },
                .record => |record| {
                    out.ty = try self.ty(record.name);
                    out.data = .{ .record = try self.fields(out.ty, record.fields, true, node.span) };
                },
                .update => |update| {
                    const base = self.resolved[@backingInt(update.base)].?;
                    out.ty = self.nodes.items[@backingInt(base)].ty;
                    out.data = .{ .update = .{ .base = base, .fields = try self.fields(out.ty, update.fields, false, node.span) } };
                },
                .field => |field| {
                    const base = self.resolved[@backingInt(field.base)].?;
                    const record_type = self.nodes.items[@backingInt(base)].ty;
                    const field_index = try self.catalog.field(record_type, self.src, field.name, self.sink);
                    if (self.conversion_fields) |seen| {
                        const base_node = self.nodes.items[@backingInt(base)];
                        if (base_node.data == .local and @backingInt(base_node.data.local) == 0) seen[field_index] = true;
                    }
                    out.ty = self.catalog.records[record_type.recordIndex()].fields[field_index].ty;
                    out.data = .{ .field = .{ .base = base, .index = field_index } };
                },
                .integer => |token| {
                    const parsed = try self.literal(token, false);
                    out.ty = parsed.ty;
                    out.data = .{ .integer = parsed.value };
                },
                .wrap => |wrap| {
                    const value = self.resolved[@backingInt(wrap.value)].?;
                    out.ty = try self.ty(wrap.ty);
                    const backing = try self.catalog.domain(out.ty, wrap.ty, self.sink);
                    try self.requireDomainAccess(out.ty, node.span);
                    try self.require(self.nodes.items[@backingInt(value)].ty, backing, self.syntax.nodes.items[@backingInt(wrap.value)].span);
                    out.data = .{ .wrap = value };
                },
                .unwrap => |input| {
                    const value = self.resolved[@backingInt(input)].?;
                    const domain_type = self.nodes.items[@backingInt(value)].ty;
                    out.ty = try self.catalog.domain(domain_type, node.span, self.sink);
                    try self.requireDomainAccess(domain_type, node.span);
                    out.data = .{ .unwrap = value };
                },
                .cast => |cast| {
                    const value = self.resolved[@backingInt(cast.value)].?;
                    out.ty = try self.ty(cast.ty);
                    try self.requireInteger(out.ty, cast.ty);
                    try self.requireInteger(self.nodes.items[@backingInt(value)].ty, node.span);
                    out.data = .{ .cast = value };
                },
                .boolean => |value| {
                    out.ty = .bool;
                    out.data = .{ .boolean = value };
                },
                .name => |name| {
                    const slot = try self.resolve(name);
                    self.locals.items[@backingInt(slot)].reads += 1;
                    out.ty = self.locals.items[@backingInt(slot)].ty;
                    out.data = .{ .local = slot };
                },
                .call => |call| {
                    const owner = if (call.owner) |name| try self.ty(name) else null;
                    if (owner) |domain_type| _ = try self.catalog.domain(domain_type, call.owner.?, self.sink);
                    const name = try functionName(self.allocator, self.src, call.owner, call.name);
                    const function = self.functions.get(name) orelse
                        return self.sink.fail("E_UNKNOWN_FUNCTION", call.name, "no function has this qualified name");
                    const signature = self.syntax.functions[@backingInt(function)];
                    if (signature.restricted and self.owner != owner) return self.sink.failRelated("E_PRIVATE_FUNCTION", call.name, "private domain function is only callable from the same domain", .{ .span = signature.name, .message = "private function declared here" });
                    if (signature.parameters.len != call.arguments.len)
                        return self.sink.fail("E_ARITY", node.span, "argument count does not match function parameters");
                    const arguments = try self.allocator.alloc(typed.NodeId, call.arguments.len);
                    for (call.arguments, signature.parameters, arguments) |arg, parameter, *out_arg| {
                        out_arg.* = self.resolved[@backingInt(arg)].?;
                        try self.require(self.nodes.items[@backingInt(out_arg.*)].ty, try self.ty(parameter.ty), self.syntax.nodes.items[@backingInt(arg)].span);
                    }
                    out.ty = try self.ty(signature.return_type);
                    out.data = .{ .call = .{ .function = function, .arguments = arguments } };
                },
                .unary => |u| {
                    const operand = self.resolved[@backingInt(u.operand)].?;
                    out.ty = if (u.op == .neg) self.nodes.items[@backingInt(operand)].ty else .bool;
                    if (u.op == .neg) try self.requireInteger(out.ty, u.op_span) else try self.require(self.nodes.items[@backingInt(operand)].ty, .bool, u.op_span);
                    out.data = .{ .unary = .{ .op = if (u.op == .neg) .neg else .not, .operand = operand, .op_span = u.op_span } };
                },
                .binary => |b| {
                    const left = self.resolved[@backingInt(b.left)].?;
                    const right = self.resolved[@backingInt(b.right)].?;
                    const lt = self.nodes.items[@backingInt(left)].ty;
                    const rt = self.nodes.items[@backingInt(right)].ty;
                    try self.require(rt, lt, b.op_span);
                    switch (b.op) {
                        .logical_and, .logical_or => {
                            try self.require(lt, .bool, b.op_span);
                            out.ty = .bool;
                        },
                        .eq, .ne => {
                            if (!lt.isInteger() and lt != .bool and !(lt.isAggregate() and self.catalog.records[lt.recordIndex()].isEnum())) return self.sink.fail("E_TYPE", b.op_span, "aggregate equality is not defined; compare the relevant elements explicitly");
                            out.ty = .bool;
                        },
                        .lt, .le, .gt, .ge => {
                            try self.requireInteger(lt, b.op_span);
                            out.ty = .bool;
                        },
                        else => {
                            try self.requireInteger(lt, b.op_span);
                            out.ty = lt;
                        },
                    }
                    out.data = .{ .binary = .{
                        .op = std.meta.stringToEnum(typed.BinaryOp, @tagName(b.op)).?,
                        .left = left,
                        .right = right,
                        .op_span = b.op_span,
                    } };
                },
            }
            self.resolved[index] = @fromBackingInt(self.nodes.items.len);
            try self.nodes.append(self.allocator, out);
        }
        return self.resolved[@backingInt(root)].?;
    }
    fn statement(self: *Checker, id: ast.StatementId) Error!CheckedStatement {
        const stmt = self.syntax.statements.items[@backingInt(id)];
        var terminates = false;
        const data: @FieldType(typed.Statement, "data") = switch (stmt.data) {
            .block => |children| block: {
                const first_local = self.locals.items.len;
                defer for (self.locals.items[first_local..]) |local| {
                    _ = self.active.remove(local.name);
                };
                var checked: std.ArrayList(typed.StatementId) = .empty;
                for (children) |child| {
                    if (terminates) return self.sink.fail("E_UNREACHABLE", self.syntax.statements.items[@backingInt(child)].span, "statement follows a structurally terminating statement");
                    const result = try self.statement(child);
                    terminates = result.terminates;
                    try checked.append(self.allocator, result.id);
                }
                break :block .{ .block = try checked.toOwnedSlice(self.allocator) };
            },
            .match => |match| match: {
                const value = try self.expression(match.value);
                const value_type = self.nodes.items[@backingInt(value)].ty;
                const variants = try self.catalog.variants(value_type, stmt.span, self.sink);
                const seen = try self.allocator.alloc(?source.Span, variants.cases.len);
                @memset(seen, null);
                const arms = try self.allocator.alloc(typed.MatchArm, match.arms.len);
                terminates = true;
                for (match.arms, arms) |arm, *out_arm| {
                    try self.require(try self.ty(arm.ty), value_type, arm.ty);
                    const tag = try self.catalog.variant(value_type, self.src, arm.name, self.sink);
                    if (seen[tag]) |previous| return self.sink.failRelated("E_DUPLICATE_ARM", arm.name, "variant has more than one match arm", .{ .span = previous, .message = "previous arm" });
                    seen[tag] = arm.name;
                    const payload = variants.cases[tag].payload;
                    if ((payload != null) != (arm.binding != null or arm.discard_payload)) return self.sink.failRelated("E_PATTERN_PAYLOAD", arm.name, "payload variants require a binding or (discard); empty variants take neither", .{ .span = variants.cases[tag].declaration, .message = "variant declared here" });
                    const first_local = self.locals.items.len;
                    defer for (self.locals.items[first_local..]) |local| {
                        _ = self.active.remove(local.name);
                    };
                    var slot: ?typed.LocalId = null;
                    if (arm.binding) |binding| {
                        const name = self.src.text(binding);
                        if (self.functions.contains(name) or self.catalog.names.contains(name) or self.active.contains(name)) return self.sink.fail("E_SHADOWING", binding, "payload binding shadows an active binding or top-level name");
                        slot = @fromBackingInt(self.locals.items.len);
                        try self.locals.append(self.allocator, .{ .name = name, .declaration = binding, .ty = payload.?, .mutable = false });
                        try self.active.put(self.allocator, name, slot.?);
                    }
                    const body = try self.statement(arm.body);
                    terminates = terminates and body.terminates;
                    out_arm.* = .{ .tag = tag, .slot = slot, .body = body.id };
                }
                for (seen, variants.cases) |covered, variant| if (covered == null) {
                    const message = try std.fmt.allocPrint(self.allocator, "match does not handle variant `{s}`; every variant requires an explicit arm", .{variant.name});
                    return self.sink.failRelated("E_INCOMPLETE_MATCH", stmt.span, message, .{ .span = variant.declaration, .message = "unhandled variant declared here" });
                };
                break :match .{ .match = .{ .value = value, .arms = arms } };
            },
            .discard => |expr| .{ .discard = try self.expression(expr) },
            .branch => |branch| branch: {
                const condition = try self.expression(branch.condition);
                try self.require(self.nodes.items[@backingInt(condition)].ty, .bool, self.syntax.nodes.items[@backingInt(branch.condition)].span);
                const then_body = try self.statement(branch.then_body);
                const else_body = if (branch.else_body) |other| try self.statement(other) else null;
                terminates = then_body.terminates and if (else_body) |other| other.terminates else false;
                break :branch .{ .branch = .{ .condition = condition, .then_body = then_body.id, .else_body = if (else_body) |other| other.id else null } };
            },
            .loop => |loop| loop: {
                const condition = try self.expression(loop.condition);
                try self.require(self.nodes.items[@backingInt(condition)].ty, .bool, self.syntax.nodes.items[@backingInt(loop.condition)].span);
                const body = try self.statement(loop.body);
                break :loop .{ .loop = .{ .condition = condition, .body = body.id } };
            },
            .ret => |expr| ret: {
                const value = try self.expression(expr);
                try self.require(self.nodes.items[@backingInt(value)].ty, self.return_type, stmt.span);
                terminates = true;
                break :ret .{ .ret = value };
            },
            .binding => |b| binding: {
                const name = self.src.text(b.name);
                if (self.functions.contains(name) or self.catalog.names.contains(name) or self.active.contains(name))
                    return self.sink.fail("E_SHADOWING", b.name, "binding shadows an active local or top-level function");
                const value = try self.expression(b.value);
                const value_type = self.nodes.items[@backingInt(value)].ty;
                if (b.annotation) |annotation| try self.require(value_type, try self.ty(annotation), annotation);
                const slot: typed.LocalId = @fromBackingInt(self.locals.items.len);
                try self.locals.append(self.allocator, .{ .name = name, .declaration = b.name, .ty = value_type, .mutable = b.mutable });
                try self.active.put(self.allocator, name, slot);
                break :binding .{ .initialize = .{ .slot = slot, .value = value } };
            },
            .assignment => |a| assignment: {
                const slot = try self.resolve(a.name);
                if (!self.locals.items[@backingInt(slot)].mutable)
                    return self.sink.fail("E_IMMUTABLE", a.name, "assignment requires a let mut binding");
                var value = try self.expression(a.value);
                if (a.op != .set) {
                    try self.requireInteger(self.locals.items[@backingInt(slot)].ty, a.op_span);
                    try self.require(self.nodes.items[@backingInt(value)].ty, self.locals.items[@backingInt(slot)].ty, a.op_span);
                    self.locals.items[@backingInt(slot)].reads += 1;
                    const read: typed.NodeId = @fromBackingInt(self.nodes.items.len);
                    try self.nodes.append(self.allocator, .{ .ty = self.locals.items[@backingInt(slot)].ty, .span = a.name, .data = .{ .local = slot } });
                    const combined: typed.NodeId = @fromBackingInt(self.nodes.items.len);
                    try self.nodes.append(self.allocator, .{ .ty = self.locals.items[@backingInt(slot)].ty, .span = stmt.span, .data = .{ .binary = .{
                        .op = if (a.op == .add) .add else .sub,
                        .left = read,
                        .right = value,
                        .op_span = a.op_span,
                    } } });
                    value = combined;
                }
                try self.require(self.nodes.items[@backingInt(value)].ty, self.locals.items[@backingInt(slot)].ty, stmt.span);
                self.locals.items[@backingInt(slot)].writes += 1;
                break :assignment .{ .assign = .{ .slot = slot, .value = value } };
            },
        };
        const result: typed.StatementId = @fromBackingInt(self.statements.items.len);
        try self.statements.append(self.allocator, .{ .span = stmt.span, .terminates = terminates, .data = data });
        return .{ .id = result, .terminates = terminates };
    }
};
fn warningLess(_: void, a: diagnostic.Diagnostic, b: diagnostic.Diagnostic) bool {
    if (a.span.start != b.span.start) return a.span.start < b.span.start;
    return std.mem.lessThan(u8, a.code, b.code);
}
pub fn check(allocator: std.mem.Allocator, src: source.Source, program: ast.Program, sink: *diagnostic.Sink) Error!typed.Program {
    const resolved = try allocator.alloc(?typed.NodeId, program.nodes.items.len);
    @memset(resolved, null);
    const catalog = try records.collect(allocator, src, program.records, program.domains, program.variants, program.array_types, sink);
    var checker: Checker = .{ .allocator = allocator, .src = src, .syntax = program, .sink = sink, .resolved = resolved, .catalog = catalog };
    for (program.functions, 0..) |function, i| {
        const name = try functionName(allocator, src, function.owner, function.name);
        if (catalog.names.contains(name)) return sink.fail("E_DUPLICATE_NAME", function.name, "function name conflicts with a declared type");
        if (checker.functions.get(name)) |previous| return sink.failRelated("E_DUPLICATE_FUNCTION", function.name, "function name is already declared", .{ .span = program.functions[@backingInt(previous)].name, .message = "previous function declaration" });
        try checker.functions.put(allocator, name, @fromBackingInt(i));
    }
    const main = checker.functions.get("main") orelse return sink.fail("E_MAIN", .{ .start = 0, .end = 0 }, "the program requires fn main() -> i64");
    const entry = program.functions[@backingInt(main)];
    if (entry.parameters.len != 0) return sink.fail("E_MAIN", entry.name, "main must have no parameters");
    if (try checker.ty(entry.return_type) != .i64) return sink.fail("E_TYPE", entry.return_type, "main must return i64");
    const functions = try allocator.alloc(typed.Function, program.functions.len);
    for (program.functions, functions, 0..) |function, *out, i| {
        checker.locals = .empty;
        checker.active.clearRetainingCapacity();
        checker.owner = if (function.owner) |owner| try checker.ty(owner) else null;
        checker.return_type = try checker.ty(function.return_type);
        for (function.parameters) |parameter| {
            const name = src.text(parameter.name);
            if (checker.active.get(name)) |previous| return sink.failRelated("E_DUPLICATE_PARAMETER", parameter.name, "parameter name is already declared", .{ .span = checker.locals.items[@backingInt(previous)].declaration, .message = "previous parameter declaration" });
            if (checker.functions.contains(name) or checker.catalog.names.contains(name)) return sink.fail("E_SHADOWING", parameter.name, "parameter shadows a top-level function");
            const slot: typed.LocalId = @fromBackingInt(checker.locals.items.len);
            try checker.locals.append(allocator, .{ .name = name, .declaration = parameter.name, .ty = try checker.ty(parameter.ty), .mutable = false });
            try checker.active.put(allocator, name, slot);
        }
        checker.conversion_fields = null;
        if (function.conversion) {
            if (function.parameters.len != 1) return sink.fail("E_CONVERSION_SIGNATURE", function.name, "a complete conversion requires one source record parameter");
            const source_record = try catalog.record(checker.locals.items[0].ty, function.parameters[0].ty, sink);
            _ = try catalog.record(checker.return_type, function.return_type, sink);
            try conversionBody(src, program, function, sink);
            checker.conversion_fields = try allocator.alloc(bool, source_record.fields.len);
            @memset(checker.conversion_fields.?, false);
        }
        const body = try checker.statement(function.body);
        if (checker.conversion_fields) |seen| {
            const source_record = catalog.records[checker.locals.items[0].ty.recordIndex()];
            for (seen, source_record.fields) |accounted, field| {
                if (!accounted) {
                    const message = try std.fmt.allocPrint(allocator, "source field `{s}` is not accounted for; use it in the destination or explicitly discard that named field", .{field.name});
                    return sink.failRelated("E_INCOMPLETE_CONVERSION", function.name, message, .{ .span = field.declaration, .message = "unaccounted source field declared here" });
                }
            }
        }
        if (!body.terminates) return sink.fail("E_MISSING_RETURN", function.name, "function may fall through without returning its declared type; loops are conservatively treated as falling through, even while true");
        out.* = .{ .owner = checker.owner, .restricted = function.restricted, .conversion = function.conversion, .id = @fromBackingInt(i), .name = try functionName(allocator, src, function.owner, function.name), .declaration = function.name, .return_type = checker.return_type, .parameter_count = function.parameters.len, .body = body.id, .locals = try checker.locals.toOwnedSlice(allocator) };
    }
    for (functions) |function| {
        for (function.locals) |local| {
            if (local.reads == 0) try sink.items.append(allocator, .{
                .severity = .warning,
                .code = "W_UNUSED_BINDING",
                .span = local.declaration,
                .message = "binding is never read; use it or remove it, preserving initializer effects with discard when needed",
            });
            if (local.mutable and local.writes == 0) try sink.items.append(allocator, .{
                .severity = .warning,
                .code = "W_UNNECESSARY_MUT",
                .span = local.declaration,
                .message = "binding is never assigned after initialization; remove mut",
            });
        }
    }
    std.mem.sort(diagnostic.Diagnostic, sink.items.items, {}, warningLess);
    return .{ .nodes = try checker.nodes.toOwnedSlice(allocator), .statements = try checker.statements.toOwnedSlice(allocator), .functions = functions, .main = main, .records = catalog.records };
}

// This initial conversion form is declarative. Restricting its body avoids
// pretending arbitrary control/data flow proves source-field accounting.
fn conversionBody(src: source.Source, program: ast.Program, function: ast.Function, sink: *diagnostic.Sink) Error!void {
    const statements = program.statements.items[@backingInt(function.body)].data.block;
    for (statements) |id| {
        const stmt = program.statements.items[@backingInt(id)];
        switch (stmt.data) {
            .ret => |value| {
                if (program.nodes.items[@backingInt(value)].data != .record)
                    return sink.fail("E_CONVERSION_BODY", stmt.span, "conversion must return an explicit complete record construction");
            },
            .discard => |value| {
                const expression = program.nodes.items[@backingInt(value)];
                if (expression.data != .field) return sink.fail("E_CONVERSION_BODY", stmt.span, "conversion discard must name a direct source field");
                const base = program.nodes.items[@backingInt(expression.data.field.base)];
                if (base.data != .name or !std.mem.eql(u8, src.text(base.data.name), src.text(function.parameters[0].name)))
                    return sink.fail("E_CONVERSION_BODY", stmt.span, "conversion discard must name a direct source field");
            },
            else => return sink.fail("E_CONVERSION_BODY", stmt.span, "conversion bodies contain named source-field discards followed by a complete record construction; use helpers for transformations"),
        }
    }
}

fn functionName(allocator: std.mem.Allocator, src: source.Source, owner: ?source.Span, name: source.Span) Error![]const u8 {
    if (owner) |domain_name| return std.fmt.allocPrint(allocator, "{s}.{s}", .{ src.text(domain_name), src.text(name) });
    return src.text(name);
}
