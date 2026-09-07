//! Declaration-scoped nominal template expressions, before concrete layout specialization.
const eRequirement = "E_GENERIC_REQUIREMENT";
const std = @import("std");
const ast = @import("ast.zig");
const typed = @import("typed.zig");
const source = @import("source.zig");
const diagnostic = @import("diagnostic.zig");
const requirements = @import("generic_requirements.zig");
const Names = @import("module_names.zig").Names;
const Error = diagnostic.Error;
const Span = source.Span;
/// A type variable is local to its enclosing declaration; named identities index declarations.
pub const Expression = union(enum) {
    callback: *const Callback,
    builtin: typed.Type,
    length: usize,
    parameter: usize,
    named: usize,
    array: *const Array,
    application: *const Application,
};
/// Resolved callable argument/result expressions without representative runtime types.
pub const Callback = struct { syntax: ast.CallbackType, arguments: []const Expression };
/// Retain both numeric and closed-enum array syntax for later concrete layout resolution.
pub const Array = struct { syntax: ast.ArrayType, length: ?usize, length_parameter: ?usize = null, element: Expression, key: ?Expression };
/// Ordered type arguments retain their nominal base identity and diagnostic sites.
pub const Application = struct { syntax: ast.TypeApplication, declaration: usize, arguments: []const Expression };
/// Named record field or closed variant case, including payload-free cases.
pub const Field = struct { name: Span, ty: ?Expression };
/// Declaration category determines equality and owner/result obligations independently of spelling.
pub const Kind = enum { record, variants, result, enumeration, domain, buffer, resource, pool, handle };
/// Template metadata is arena-owned and has no executable placeholder type ID.
pub const Declaration = struct {
    name: Span,
    parameters: []const requirements.Parameter,
    kind: Kind,
    fields: []const Field = &.{},
    guarantees: requirements.Set = .{},
};
const Alias = struct { declaration: ast.TypeAlias, visiting: bool = false };
const Syntax = struct {
    callbacks: std.AutoHashMapUnmanaged(usize, ast.CallbackType) = .empty,
    aliases: std.StringHashMapUnmanaged(Alias) = .empty,
    arrays: std.AutoHashMapUnmanaged(usize, ast.ArrayType) = .empty,
    applications: std.AutoHashMapUnmanaged(usize, ast.TypeApplication) = .empty,
};
const Context = struct { allocator: std.mem.Allocator, src: source.Source, sink: *diagnostic.Sink, names: ?*Names };
const Budget = struct { depth: usize = 0, work: usize = 0 };
/// Reusable declaration identities and symbolic field/payload expressions for specialization.
pub const Index = struct {
    context: Context,
    declarations: std.ArrayList(Declaration) = .empty,
    names: std.StringHashMapUnmanaged(usize) = .empty,
    syntax: Syntax = .{},
    budget: Budget = .{},

    fn add(self: *Index, name: Span, parameters: []const ast.TypeParameter, kind: Kind) Error!void {
        const ctx = self.context;
        for (parameters) |contract| if (contract.field_requirements.len != 0 or contract.operation_requirements.len != 0)
            return ctx.sink.fail(eRequirement, contract.name, "structural requirements currently belong to function templates, not nominal type declarations");
        const key = if (ctx.names) |names| try names.declaration(name) else ctx.src.text(name);
        if (self.names.get(key)) |previous| return ctx.sink.failRelated("E_DUPLICATE_TYPE", name, "type is already declared", .{ .span = self.declarations.items[previous].name, .message = "previous type declaration" });
        const entry: Declaration = .{ .name = name, .parameters = try requirements.resolve(ctx.allocator, ctx.src, parameters, ctx.sink), .kind = kind };
        try self.names.put(ctx.allocator, key, self.declarations.items.len);
        try self.declarations.append(ctx.allocator, entry);
    }
    fn lengthParameter(self: *Index, span: Span, parameters: []const requirements.Parameter) ?usize {
        const id = self.parameter(span, parameters) orelse return null;
        return if (parameters[id].constant_length) id else null;
    }
    fn lengthExpression(self: *Index, span: Span, parameters: []const requirements.Parameter) Error!Expression {
        if (self.parameter(span, parameters)) |index| {
            if (!parameters[index].constant_length) return self.context.sink.fail(diagnostic.generic_length, span, "length argument must be a const length parameter or decimal literal");
            return .{ .parameter = index };
        }
        return .{ .length = try @import("generic_lengths.zig").literal(self.context.src, span, self.context.sink) };
    }
    fn lookup(self: *Index, span: Span) Error!usize {
        const ctx = self.context;
        const key = if (ctx.names) |names| try names.reference(span, .type, null, null, ctx.sink) else ctx.src.text(span);
        return self.names.get(key) orelse ctx.sink.fail("E_UNKNOWN_TYPE", span, "type is not declared");
    }
    fn parameter(self: *Index, span: Span, parameters: []const requirements.Parameter) ?usize {
        for (parameters, 0..) |item, i| if (std.mem.eql(u8, self.context.src.text(span), self.context.src.text(item.name))) return i;
        return null;
    }
    /// Resolve syntax to declaration identities without substituting representative concrete types.
    pub fn expression(self: *Index, span: Span, parameters: []const requirements.Parameter) Error!Expression {
        const ctx = self.context;
        if (self.budget.depth == 256 or self.budget.work == 100000) return ctx.sink.fail("E_GENERIC_LIMIT", span, "nominal type expressions exceed checking depth/work budget");
        self.budget.depth += 1;
        self.budget.work += 1;
        defer self.budget.depth -= 1;
        if (self.syntax.callbacks.get(span.start)) |syntax| {
            const arguments = try ctx.allocator.alloc(Expression, syntax.parameters.len + 1);
            for (syntax.parameters, arguments[0..syntax.parameters.len]) |input, *out| out.* = try self.expression(input, parameters);
            arguments[syntax.parameters.len] = try self.expression(syntax.return_type, parameters);
            for (arguments) |argument| if (depends(argument)) return ctx.sink.fail("E_CALLBACK_TYPE", span, "callback signatures currently require concrete parameter and result types");
            const callback = try ctx.allocator.create(Callback);
            callback.* = .{ .syntax = syntax, .arguments = arguments };
            return .{ .callback = callback };
        }
        if (self.syntax.arrays.get(span.start)) |syntax| {
            const element = try self.expression(syntax.element, parameters);
            var enum_key: ?Expression = null;
            var length_parameter: ?usize = null;
            const length: ?usize = switch (syntax.index) {
                .length => |at| try @import("generic_arrays.zig").length(ctx.src, at, ctx.sink),
                .enum_type => |at| length: {
                    if (self.lengthParameter(at, parameters)) |id| {
                        length_parameter = id;
                        break :length null;
                    }
                    const key = try self.expression(at, parameters);
                    enum_key = key;
                    if (depends(element) or depends(key)) return ctx.sink.fail("E_GENERIC_ARRAY_KEY", syntax.span, "parameterized arrays currently require a fixed numeric length");
                    const id = switch (key) {
                        .named => |id| id,
                        .application => |application| application.declaration,
                        else => return ctx.sink.fail("E_TABLE_KEY", at, "table key must be a closed enum type"),
                    };
                    if (self.declarations.items[id].kind != .enumeration) return ctx.sink.fail("E_TABLE_KEY", at, "table key must be a closed enum type");
                    break :length null;
                },
            };
            const array = try ctx.allocator.create(Array);
            array.* = .{ .syntax = syntax, .length = length, .length_parameter = length_parameter, .element = element, .key = enum_key };
            return .{ .array = array };
        }
        if (self.syntax.applications.get(span.start)) |syntax| {
            if (self.parameter(syntax.name, parameters) != null) return ctx.sink.fail("E_TYPE_APPLICATION", syntax.name, "a type parameter cannot be used as a type constructor");
            const id = try self.lookup(syntax.name);
            if (syntax.arguments.len != self.declarations.items[id].parameters.len) return ctx.sink.fail("E_GENERIC_ARITY", syntax.span, "type application requires exactly the declared number of arguments");
            const arguments = try ctx.allocator.alloc(Expression, syntax.arguments.len);
            for (syntax.arguments, self.declarations.items[id].parameters, arguments) |argument, required, *out| {
                out.* = if (required.constant_length) try self.lengthExpression(argument, parameters) else try self.expression(argument, parameters);
            }
            const application = try ctx.allocator.create(Application);
            application.* = .{ .syntax = syntax, .declaration = id, .arguments = arguments };
            return .{ .application = application };
        }
        if (self.parameter(span, parameters)) |id| {
            if (parameters[id].constant_length) return ctx.sink.fail(diagnostic.generic_length, span, "a const length parameter is a value, not a type");
            return .{ .parameter = id };
        }
        if (typed.Type.fromName(ctx.src.text(span))) |ty| return .{ .builtin = ty };
        if (self.syntax.aliases.count() != 0) {
            const alias_name = if (ctx.names) |names| try names.reference(span, .type, null, null, ctx.sink) else ctx.src.text(span);
            if (self.syntax.aliases.getPtr(alias_name)) |alias| {
                if (alias.visiting) return ctx.sink.fail("E_ALIAS_CYCLE", span, "type aliases must have acyclic dependencies");
                alias.visiting = true;
                defer alias.visiting = false;
                return self.expression(alias.declaration.target, &.{});
            }
        }
        const id = try self.lookup(span);
        if (self.declarations.items[id].parameters.len != 0) return ctx.sink.fail("E_GENERIC_ARITY", span, "nominal template requires explicit type arguments");
        return .{ .named = id };
    }
    fn checkParameters(self: *Index, program: ast.Program) Error!void {
        const ctx = self.context;
        for (self.declarations.items) |declaration| for (declaration.parameters) |item| {
            var shadowed = if (ctx.names) |names| try names.topLevel(item.name) else self.names.contains(ctx.src.text(item.name)) or self.syntax.aliases.contains(ctx.src.text(item.name));
            if (ctx.names == null) for (program.functions) |function| {
                if (function.policy.owner == null and std.mem.eql(u8, ctx.src.text(function.name), ctx.src.text(item.name))) shadowed = true;
            };
            if (shadowed) return ctx.sink.fail(diagnostic.shadowing, item.name, "type parameter shadows a top-level declaration or import");
        };
    }
    fn fields(self: *Index, name: Span, inputs: anytype) Error!void {
        const ctx = self.context;
        const id = try self.lookup(name);
        const declaration = self.declarations.items[id];
        const resolved = try ctx.allocator.alloc(Field, inputs.len);
        var names: std.StringHashMapUnmanaged(Span) = .empty;
        defer names.deinit(ctx.allocator);
        for (inputs, resolved) |input, *out| {
            const is_record = declaration.kind == .record;
            if (names.get(ctx.src.text(input.name))) |previous| return ctx.sink.failRelated(
                if (is_record) "E_DUPLICATE_FIELD" else "E_DUPLICATE_VARIANT",
                input.name,
                "field or variant is already declared",
                .{ .span = previous, .message = "previous declaration" },
            );
            try names.put(ctx.allocator, ctx.src.text(input.name), input.name);
            const span: ?Span = if (@hasField(@TypeOf(input), "ty")) input.ty else input.payload;
            out.* = .{ .name = input.name, .ty = if (span) |at| try self.expression(at, declaration.parameters) else null };
        }
        if (declaration.kind != .record and inputs.len == 0) return ctx.sink.fail("E_EMPTY_VARIANTS", name, "closed enum and union types require at least one variant");
        if (declaration.kind == .result) {
            const named_cases = names.contains("ok") and names.contains("err");
            if (inputs.len != 2 or !named_cases) return ctx.sink.fail("E_RESULT_SCHEMA", name, "a result declares exactly `ok: Value` and `err: Error` payload cases");
            for (resolved) |field| if (field.ty == null) return ctx.sink.fail("E_RESULT_SCHEMA", field.name, "result cases require explicit payload types");
        }
        self.declarations.items[id].fields = resolved;
    }
    fn backing(self: *Index, name: Span, span: Span) Error!void {
        const id = try self.lookup(name);
        const field = try self.context.allocator.alloc(Field, 1);
        field[0] = .{ .name = span, .ty = try self.expression(span, self.declarations.items[id].parameters) };
        self.declarations.items[id].fields = field;
    }
    /// Operation guarantees are independent of layout IDs; aggregate equality is never inferred.
    pub fn guarantees(self: Index, value: Expression, parameters: []const requirements.Parameter) requirements.Set {
        return switch (value) {
            .length => .{},
            .callback => copyGuarantee(),
            .builtin => |ty| builtinGuarantees(ty),
            .parameter => |id| parameters[id].requirements,
            .named => |id| self.declarations.items[id].guarantees,
            .application => |application| self.declarations.items[application.declaration].guarantees,
            .array => |array| array_result: {
                const empty = array.length_parameter == null and array.length == 0;
                if (empty or self.guarantees(array.element, parameters).contains(.copy)) break :array_result copyGuarantee();
                break :array_result if (self.guarantees(array.element, parameters).contains(.storable)) .{ .bits = 16 } else .{};
            },
        };
    }
    fn inferGuarantees(self: *Index) Error!void {
        const allocator = self.context.allocator;
        const reverse = try allocator.alloc(std.ArrayList(usize), self.declarations.items.len);
        @memset(reverse, .empty);
        defer {
            for (reverse) |*edges| edges.deinit(allocator);
            allocator.free(reverse);
        }
        var pending: std.ArrayList(usize) = .empty;
        defer pending.deinit(allocator);
        for (self.declarations.items, 0..) |*declaration, id| {
            declaration.guarantees = switch (declaration.kind) {
                .record, .variants => copyGuarantee(),
                .enumeration, .domain, .handle => .{ .bits = 19 },
                .buffer, .resource, .pool, .result => .{},
            };
            if (!declaration.guarantees.contains(.copy)) try pending.append(allocator, id);
        }
        for (self.declarations.items, 0..) |declaration, id| {
            if (declaration.kind != .record and declaration.kind != .variants) continue;
            for (declaration.fields) |field| if (field.ty) |value| try self.copyDependencies(value, declaration.parameters, id, reverse, &pending);
        }
        // Each declaration loses copy at most once, even with forward references or cycles.
        var cursor: usize = 0;
        while (cursor < pending.items.len) : (cursor += 1) {
            for (reverse[pending.items[cursor]].items) |id| try self.removeCopy(id, &pending);
        }
    }
    fn inferStorable(self: *Index) void {
        for (self.declarations.items) |*declaration| {
            if (declaration.kind != .result and declaration.kind != .resource) declaration.guarantees.include(.storable);
        }
        var changed = true;
        while (changed) {
            changed = false;
            for (self.declarations.items) |*declaration| {
                if (!declaration.guarantees.contains(.storable)) continue;
                for (declaration.fields) |field| if (field.ty) |value| {
                    if (!self.guarantees(value, declaration.parameters).contains(.storable)) {
                        declaration.guarantees.bits &= ~@as(u5, 16);
                        changed = true;
                        break;
                    }
                };
            }
        }
    }
    fn removeCopy(self: *Index, id: usize, pending: *std.ArrayList(usize)) Error!void {
        if (!self.declarations.items[id].guarantees.contains(.copy)) return;
        self.declarations.items[id].guarantees = .{};
        try pending.append(self.context.allocator, id);
    }
    fn copyDependencies(self: *Index, value: Expression, parameters: []const requirements.Parameter, owner: usize, reverse: []std.ArrayList(usize), pending: *std.ArrayList(usize)) Error!void {
        switch (value) {
            .named => |id| try reverse[id].append(self.context.allocator, owner),
            .application => |application| try reverse[application.declaration].append(self.context.allocator, owner),
            .array => |array| if (array.length != 0) {
                try self.copyDependencies(array.element, parameters, owner, reverse, pending);
            },
            else => if (!self.guarantees(value, parameters).contains(.copy)) {
                try self.removeCopy(owner, pending);
            },
        }
    }
    /// Validate nested arguments against the caller's declared guarantees, including unused fields.
    pub fn checkArguments(self: *Index, value: Expression, parameters: []const requirements.Parameter) Error!void {
        switch (value) {
            .application => |application| {
                const required = self.declarations.items[application.declaration].parameters;
                for (application.arguments, required, application.syntax.arguments) |argument, item, at| {
                    try self.checkArguments(argument, parameters);
                    if (!self.guarantees(argument, parameters).implies(item.requirements)) return self.context.sink.failRelated(
                        eRequirement,
                        at,
                        "type argument does not guarantee the nominal template's required operations",
                        .{ .span = item.name, .message = "type parameter requirements are declared here" },
                    );
                }
            },
            .array => |array| {
                if (array.key) |key| try self.checkArguments(key, parameters);
                try self.checkArguments(array.element, parameters);
            },
            else => {},
        }
    }
};
fn copyGuarantee() requirements.Set {
    return .{ .bits = 17 };
}
fn builtinGuarantees(ty: typed.Type) requirements.Set {
    var result: requirements.Set = .{};
    inline for (.{ requirements.Requirement.copy, .equality, .integer }) |requirement| {
        var candidate: requirements.Set = .{};
        candidate.include(requirement);
        if (candidate.accepts(ty, &.{})) result.include(requirement);
    }
    return result;
}
/// Test whether an expression retains a parameter from its declaring scope.
pub fn depends(value: Expression) bool {
    return switch (value) {
        .parameter => true,
        .array => |array| array.length_parameter != null or depends(array.element),
        .application => |application| dependent: {
            for (application.arguments) |argument| if (depends(argument)) break :dependent true;
            break :dependent false;
        },
        else => false,
    };
}
/// Build reusable metadata in the compilation arena; layout finiteness and execution remain separate.
pub fn collect(allocator: std.mem.Allocator, src: source.Source, program: ast.Program, sink: *diagnostic.Sink, module_names: ?*Names) Error!Index {
    var index: Index = .{ .context = .{ .allocator = allocator, .src = src, .sink = sink, .names = module_names } };
    for (program.types.records) |declaration| try index.add(declaration.name, declaration.type_parameters, .record);
    for (program.types.variants) |declaration| try index.add(declaration.name, declaration.type_parameters, if (declaration.fallible) .result else if (declaration.is_union) .variants else .enumeration);
    inline for (.{ "domains", "buffers", "resources" }, .{ Kind.domain, .buffer, .resource }) |category, kind| {
        for (@field(program.types, category)) |declaration| try index.add(declaration.name, declaration.type_parameters, kind);
    }
    for (program.types.pools) |pool| {
        try index.add(pool.name, pool.type_parameters, .pool);
        try index.add(pool.handle, pool.type_parameters, .handle);
    }
    for (program.types.expressions.aliases) |alias| {
        const key = if (module_names) |names| try names.declaration(alias.name) else src.text(alias.name);
        if (index.names.contains(key) or index.syntax.aliases.contains(key)) return sink.fail("E_DUPLICATE_TYPE", alias.name, "alias name conflicts with an existing type declaration");
        try index.syntax.aliases.put(allocator, key, .{ .declaration = alias });
    }
    try index.checkParameters(program);
    for (program.types.expressions.callbacks) |syntax| try index.syntax.callbacks.put(allocator, syntax.span.start, syntax);
    for (program.types.expressions.arrays) |syntax| try index.syntax.arrays.put(allocator, syntax.span.start, syntax);
    for (program.types.expressions.applications) |syntax| try index.syntax.applications.put(allocator, syntax.span.start, syntax);
    for (program.types.records) |declaration| try index.fields(declaration.name, declaration.fields);
    for (program.types.variants) |declaration| try index.fields(declaration.name, declaration.cases);
    for (program.types.buffers) |declaration| try index.backing(declaration.name, declaration.backing);
    for (program.types.pools) |declaration| try index.backing(declaration.name, declaration.element);
    try index.inferGuarantees();
    index.inferStorable();
    for (index.declarations.items) |declaration| {
        if (declaration.parameters.len == 0 or (declaration.kind != .buffer and declaration.kind != .pool)) continue;
        const element = declaration.fields[0];
        if (!index.guarantees(element.ty.?, declaration.parameters).contains(if (declaration.kind == .buffer) .storable else .copy)) return sink.fail(
            eRequirement,
            element.name,
            "buffer elements must guarantee storable; pool elements must guarantee copy",
        );
    }
    for (index.declarations.items) |declaration| for (declaration.fields) |field| if (field.ty) |value| try index.checkArguments(value, declaration.parameters);
    return index;
}
