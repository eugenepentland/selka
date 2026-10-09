//! Declaration-scoped nominal template expressions, before concrete layout specialization.
const eGenericArity = diagnostic.generic_arity;
const eRequirement = "E_GENERIC_REQUIREMENT";
const eResultSchema = "E_RESULT_SCHEMA";
const std = @import("std");
const ast = @import("ast.zig");
const typed = @import("typed.zig");
const source = @import("source.zig");
const diagnostic = @import("diagnostic.zig");
const requirements = @import("generic_requirements.zig");
const value_semantics = @import("value_semantics.zig");
const Names = @import("module_names.zig").Names;
const Error = diagnostic.Error;
const Span = source.Span;
/// The builtin mutable octet buffer's spelling. Only the in-place append methods
/// belong to it, so this name is what the checker matches a receiver against.
pub const byte_buffer_name = "byte_buffer";
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
/// `default_value` is the backing node id of a record field's declared default,
/// or null for a case and for a required field.
pub const Field = struct { name: Span, ty: ?Expression, builtin_name: ?[]const u8 = null, default_value: ?usize = null };
/// Declaration category determines equality and owner/result obligations independently of spelling.
pub const Kind = enum { record, variants, result, enumeration, domain, buffer, resource, tuple };
/// Template metadata is arena-owned and has no executable placeholder type ID.
pub const Declaration = struct {
    builtin_name: ?[]const u8 = null,
    managed: bool = false,
    name: Span,
    parameters: []const requirements.Parameter,
    kind: Kind,
    fields: []const Field = &.{},
    guarantees: requirements.Set = .{},
};
const Alias = struct { declaration: ast.TypeAlias, visiting: bool = false };
const Syntax = struct {
    suffixes: []const ast.TypeSuffix = &.{},
    callbacks: std.AutoHashMapUnmanaged(usize, ast.CallbackType) = .empty,
    aliases: std.StringHashMapUnmanaged(Alias) = .empty,
    arrays: std.AutoHashMapUnmanaged(usize, ast.ArrayType) = .empty,
    applications: std.AutoHashMapUnmanaged(usize, ast.TypeApplication) = .empty,
    tuples: std.AutoHashMapUnmanaged(usize, ast.TupleType) = .empty,
};
const Context = struct { allocator: std.mem.Allocator, src: source.Source, sink: *diagnostic.Sink, names: ?*Names };
/// NOMINAL-TEMPLATE-BUDGET-1: the depth and visits of the one top-level type
/// expression being resolved, and where it is spelled. Each top-level
/// expression starts a fresh budget, so the bound is per declaration site and
/// the total work stays proportional to the source, however large the program.
const Budget = struct { depth: usize = 0, work: usize = 0, site: Span = .{ .start = 0, .end = 0 } };
/// Reusable declaration identities and symbolic field/payload expressions for specialization.
pub const Index = struct {
    context: Context,
    declarations: std.ArrayList(Declaration) = .empty,
    names: std.StringHashMapUnmanaged(usize) = .empty,
    syntax: Syntax = .{},
    budget: Budget = .{},
    /// Declaration indices of synthesized case-payload records, which name no
    /// source type and therefore never become spellable type names.
    synthetic: std.AutoHashMapUnmanaged(usize, void) = .empty,
    /// Declaration index of the arity-two tuple, or null before `addTuples` runs.
    /// The seven tuple declarations are appended consecutively, so arity n is
    /// `tuple_base + n - 2`.
    tuple_base: ?usize = null,

    /// Whether a declaration index names a synthesized case-payload record.
    pub fn isSynthetic(self: Index, declaration: usize) bool {
        return self.synthetic.contains(declaration);
    }

    /// The synthetic declaration index for one tuple arity, or null outside the
    /// two-to-eight range the language accepts.
    pub fn tupleDeclaration(self: Index, arity: usize) ?usize {
        if (arity < 2 or arity > 8) return null;
        return (self.tuple_base orelse return null) + arity - 2;
    }

    /// Whether a declaration index is one of the synthetic tuple declarations.
    pub fn isTuple(self: Index, declaration: usize) bool {
        const base = self.tuple_base orelse return false;
        return declaration >= base and declaration < base + 7;
    }

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
    fn addBuiltin(self: *Index, name: []const u8, count: usize, kind: Kind) Error!void {
        if (self.names.contains(name) or self.syntax.aliases.contains(name)) return;
        const allocator = self.context.allocator;
        const standard_name: ?[]const u8 = if (std.mem.eql(u8, name, "Result")) "std_result::Result" else if (std.mem.eql(u8, name, "Option")) "std_result::Option" else null;
        if (standard_name) |key| if (self.names.get(key)) |id| {
            self.declarations.items[id].builtin_name = name;
            try self.names.put(allocator, name, id);
            return;
        };
        const span: Span = .{ .start = 0, .end = 0 };
        const parameters = try allocator.alloc(requirements.Parameter, count);
        const fields_out = try allocator.alloc(Field, count);
        var copy_required: requirements.Set = .{};
        copy_required.include(.copy);
        for (parameters, fields_out, 0..) |*parameter_out, *field, i| {
            parameter_out.* = .{ .name = span, .requirements = copy_required };
            field.* = .{ .name = span, .ty = .{ .parameter = i }, .builtin_name = if (kind == .result) (if (i == 0) "ok" else "err") else null };
        }
        try self.names.put(allocator, name, self.declarations.items.len);
        try self.declarations.append(allocator, .{
            .builtin_name = name,
            .name = span,
            .parameters = parameters,
            .kind = kind,
            .fields = fields_out,
            .managed = kind == .buffer,
        });
    }
    fn addOption(self: *Index) Error!void {
        try self.addBuiltin("Option", 1, .variants);
        const id = self.names.get("Option") orelse return;
        const declaration = &self.declarations.items[id];
        if (declaration.builtin_name == null or declaration.name.end != 0) return;
        const fields_out = try self.context.allocator.alloc(Field, 2);
        const span: Span = .{ .start = 0, .end = 0 };
        fields_out[0] = .{ .name = span, .ty = null, .builtin_name = "none" };
        fields_out[1] = .{ .name = span, .ty = .{ .parameter = 0 }, .builtin_name = "some" };
        declaration.fields = fields_out;
    }
    fn addFixedArrayError(self: *Index) Error!void {
        const name = @import("frontend_type_names.zig").fixed_length_error;
        try self.addBuiltin(name, 0, .enumeration);
        const declaration = &self.declarations.items[self.names.get(name).?];
        if (declaration.name.end != 0) return;
        declaration.fields = try self.context.allocator.dupe(Field, &.{.{
            .name = .{ .start = 0, .end = 0 },
            .ty = null,
            .builtin_name = "wrong_length",
        }});
    }
    fn addPrelude(self: *Index, program: ast.Program) Error!void {
        try self.addFixedArrayError();
        try self.addCell();
        try self.addBuiltin("List", 1, .buffer);
        if (!self.names.contains("list")) try self.names.put(self.context.allocator, "list", self.names.get("List").?);
        try self.addBuiltin("Result", 2, .result);
        try self.addOption();
        _ = program;
        try self.addFloat();
        try self.addBuiltin("str", 0, .buffer);
        const text_declaration = &self.declarations.items[self.names.get("str").?];
        if (text_declaration.builtin_name != null) text_declaration.fields = try self.context.allocator.dupe(Field, &.{.{ .name = .{ .start = 0, .end = 0 }, .ty = .{ .builtin = .u32 } }});
        try self.addByteString();
        try self.addByteBuffer();
        try self.addBuiltin("dict", 2, .buffer);
        try self.addBuiltin("set", 1, .buffer);
        try self.addDictionaryViews();
        try self.addTuples();
    }
    /// Register the seven anonymous tuple declarations, arity two to eight. They
    /// are synthetic: no source name reaches them and their parameters carry no
    /// requirements, so `tuple[T, int]` stays spellable for an unbounded `T` and
    /// the element contract is enforced where the value is used. The layout graph
    /// turns each spelling into the one interned record per element-type list.
    fn addTuples(self: *Index) Error!void {
        const allocator = self.context.allocator;
        const span: Span = .{ .start = 0, .end = 0 };
        self.tuple_base = self.declarations.items.len;
        for (2..9) |arity| {
            const parameters = try allocator.alloc(requirements.Parameter, arity);
            for (parameters) |*slot| slot.* = .{ .name = span, .requirements = .{} };
            try self.synthetic.put(allocator, self.declarations.items.len, {});
            try self.declarations.append(allocator, .{
                .builtin_name = "tuple",
                .name = span,
                .parameters = parameters,
                .kind = .tuple,
            });
        }
    }
    fn addDictionaryViews(self: *Index) Error!void {
        const allocator = self.context.allocator;
        const empty: Span = .{ .start = 0, .end = 0 };
        try self.addBuiltin("DictItem", 2, .record);
        const item = &self.declarations.items[self.names.get("DictItem").?];
        if (item.builtin_name != null) item.fields = try allocator.dupe(Field, &.{
            .{ .name = empty, .ty = .{ .parameter = 0 }, .builtin_name = "key" },
            .{ .name = empty, .ty = .{ .parameter = 1 }, .builtin_name = "value" },
        });
        const mapping = try allocator.create(Application);
        mapping.* = .{
            .syntax = .{ .span = empty, .name = empty, .arguments = try allocator.dupe(Span, &.{ empty, empty }) },
            .declaration = self.names.get("dict").?,
            .arguments = try allocator.dupe(Expression, &.{ .{ .parameter = 0 }, .{ .parameter = 1 } }),
        };
        for ([_][]const u8{ "DictKeys", "DictValues", "DictItems" }) |name| {
            try self.addBuiltin(name, 2, .record);
            const declaration = &self.declarations.items[self.names.get(name).?];
            if (declaration.builtin_name != null) declaration.fields = try allocator.dupe(Field, &.{
                .{ .name = empty, .ty = .{ .application = mapping }, .builtin_name = "mapping" },
            });
        }
    }
    fn addCell(self: *Index) Error!void {
        try self.addBuiltin("Cell", 1, .record);
        const declaration = &self.declarations.items[self.names.get("Cell") orelse return];
        if (declaration.builtin_name == null) return;
        declaration.managed = true;
        declaration.fields = try self.context.allocator.dupe(Field, &.{.{ .name = declaration.name, .ty = .{ .parameter = 0 }, .builtin_name = "value" }});
    }
    /// Materialize the managed byte string for an operation that needs its schema
    /// without the source naming `bytes`; a declared type of that name still wins.
    pub fn addByteString(self: *Index) Error!void {
        try self.addBuiltin("bytes", 0, .buffer);
        const declaration = &self.declarations.items[self.names.get("bytes") orelse return];
        if (declaration.builtin_name == null) return;
        declaration.fields = try self.context.allocator.dupe(Field, &.{.{ .name = .{ .start = 0, .end = 0 }, .ty = .{ .builtin = .u8 } }});
        // Guarantees are inferred once; a byte string registered from a later type lookup sets its own.
        declaration.guarantees.include(.copy);
        declaration.guarantees.include(.storable);
    }
    /// Materialize the mutable octet buffer on demand, for a source that names
    /// `byte_buffer` or an operation that produces one. It shares the managed
    /// one-byte element buffer of `bytes`, so length, indexing, iteration,
    /// comparison and search read a buffer exactly like a byte string; the
    /// distinct name is what restricts the in-place append methods to a buffer
    /// and leaves the byte string immutable, so a view of a byte string can never
    /// observe a later write through an alias.
    pub fn addByteBuffer(self: *Index) Error!void {
        try self.addBuiltin(byte_buffer_name, 0, .buffer);
        const declaration = &self.declarations.items[self.names.get(byte_buffer_name) orelse return];
        if (declaration.builtin_name == null) return;
        declaration.fields = try self.context.allocator.dupe(Field, &.{.{ .name = .{ .start = 0, .end = 0 }, .ty = .{ .builtin = .u8 } }});
        declaration.guarantees.include(.copy);
        declaration.guarantees.include(.storable);
    }
    fn addFloat(self: *Index) Error!void {
        if (self.names.contains("float") or self.syntax.aliases.contains("float")) return;
        const span: Span = .{ .start = 0, .end = 0 };
        const fields_out = try self.context.allocator.dupe(Field, &.{.{ .name = span, .ty = .{ .builtin = .u64 } }});
        try self.names.put(self.context.allocator, "float", self.declarations.items.len);
        try self.declarations.append(self.context.allocator, .{ .builtin_name = "float", .name = span, .parameters = &.{}, .kind = .domain, .fields = fields_out });
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
        const text = ctx.src.text(span);
        _ = try @import("removed_names.zig").reject(ctx.sink, span, text);
        // The mutable octet buffer is a prelude type that a program only pays for
        // when it names one; a declared type of that name still wins.
        if (std.mem.eql(u8, text, "byte_buffer") and !self.syntax.aliases.contains(text)) try self.addByteBuffer();
        if (self.names.get(text)) |id| {
            if (self.declarations.items[id].builtin_name != null) {
                if (ctx.names == null or !try ctx.names.?.topLevel(span)) {
                    try self.rejectRetiredType(id, span);
                    return id;
                }
            }
        }
        const key = if (ctx.names) |names| try names.reference(span, .type, null, null, ctx.sink) else text;
        const id = self.names.get(key) orelse return ctx.sink.fail("E_UNKNOWN_TYPE", span, "type is not declared");
        try self.rejectRetiredType(id, span);
        return id;
    }
    fn rejectRetiredType(self: *Index, id: usize, span: Span) Error!void {
        const builtin = self.declarations.items[id].builtin_name orelse return;
        // D2: explicit view types would make storage/call boundaries possible.
        // Inferred immediate projections instantiate the prelude internally.
        inline for (.{ "DictKeys", "DictValues", "DictItems" }) |view| if (std.mem.eql(u8, builtin, view)) return self.context.sink.fail(
            "E_VIEW_STORED",
            span,
            "dictionary views cannot appear in type declarations or annotations; use list snapshots instead",
        );
        if (std.mem.eql(u8, builtin, "Cell")) return self.context.sink.fail(
            "E_VALUE_CELL",
            span,
            "builtin Cell is shared mutable state under value semantics; use a value record with `mut` and store-back, or a pool handle for identity",
        );
    }
    /// Resolve one array or enum-keyed table spelling, including its const
    /// length parameter when the spelling names one.
    fn arrayExpression(self: *Index, syntax: ast.ArrayType, parameters: []const requirements.Parameter) Error!Expression {
        const ctx = self.context;
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
    /// Resolve one `tuple[...]` spelling into a tuple application. Arity is a
    /// checker rule, not a parse rule, so a wrong arity is rejected here at the
    /// whole spelling rather than at one element.
    fn tupleExpression(self: *Index, syntax: ast.TupleType, parameters: []const requirements.Parameter) Error!Expression {
        const ctx = self.context;
        if (syntax.elements.len < 2 or syntax.elements.len > 8) return ctx.sink.fail(
            "E_TUPLE_ARITY",
            syntax.span,
            "a tuple has between 2 and 8 elements; declare a record for a larger group",
        );
        const arguments = try ctx.allocator.alloc(Expression, syntax.elements.len);
        for (syntax.elements, arguments) |element, *out| out.* = try self.expression(element, parameters);
        const application = try ctx.allocator.create(Application);
        application.* = .{
            .syntax = .{ .span = syntax.span, .name = syntax.span, .arguments = syntax.elements },
            .declaration = self.tupleDeclaration(syntax.elements.len) orelse return error.InternalError,
            .arguments = arguments,
        };
        return .{ .application = application };
    }
    fn parameter(self: *Index, span: Span, parameters: []const requirements.Parameter) ?usize {
        for (parameters, 0..) |item, i| if (std.mem.eql(u8, self.context.src.text(span), self.context.src.text(item.name))) return i;
        return null;
    }
    /// Report the budget at the top-level expression that exceeded it, naming
    /// where its resolution stood when that differs.
    fn limit(self: *Index, span: Span) Error {
        const site = self.budget.site;
        const message = "nominal type expression exceeds the checking budget of 256 levels and 100000 visits";
        if (site.start == span.start and site.end == span.end) return self.context.sink.fail("E_GENERIC_LIMIT", site, message);
        return self.context.sink.failRelated("E_GENERIC_LIMIT", site, message, .{ .span = span, .message = "resolution reached this type" });
    }
    fn applicationExpression(self: *Index, syntax: ast.TypeApplication, parameters: []const requirements.Parameter) Error!Expression {
        const ctx = self.context;
        if (self.parameter(syntax.name, parameters) != null) return ctx.sink.fail("E_TYPE_APPLICATION", syntax.name, "a type parameter cannot be used as a type constructor");
        if (std.mem.eql(u8, ctx.src.text(syntax.name), "FixedArray")) {
            if (syntax.arguments.len != 2) return ctx.sink.fail(eGenericArity, syntax.span, "FixedArray requires an element type and a constant length");
            const length = syntax.arguments[1];
            const array_syntax: ast.ArrayType = .{
                .span = syntax.span,
                .element = syntax.arguments[0],
                .index = if (self.lengthParameter(length, parameters) != null) .{ .enum_type = length } else .{ .length = length },
            };
            return self.arrayExpression(array_syntax, parameters);
        }
        const id = try self.lookup(syntax.name);
        if (syntax.arguments.len != self.declarations.items[id].parameters.len) return ctx.sink.fail(eGenericArity, syntax.span, "type application requires exactly the declared number of arguments");
        const arguments = try ctx.allocator.alloc(Expression, syntax.arguments.len);
        for (syntax.arguments, self.declarations.items[id].parameters, arguments) |argument, required, *out| {
            out.* = if (required.constant_length) try self.lengthExpression(argument, parameters) else try self.expression(argument, parameters);
        }
        const application = try ctx.allocator.create(Application);
        application.* = .{ .syntax = syntax, .declaration = id, .arguments = arguments };
        return .{ .application = application };
    }
    fn callbackExpression(self: *Index, syntax: ast.CallbackType, parameters: []const requirements.Parameter) Error!Expression {
        const allocator = self.context.allocator;
        const arguments = try allocator.alloc(Expression, syntax.parameters.len + 1);
        for (syntax.parameters, arguments[0..syntax.parameters.len]) |input, *out| out.* = try self.expression(input, parameters);
        const success = try self.expression(syntax.return_type, parameters);
        var result = success;
        if (syntax.failure_type) |failure| {
            const error_type = try self.expression(failure, parameters);
            const payloads = try allocator.dupe(Expression, &.{ success, error_type });
            const sites = try allocator.dupe(Span, &.{ syntax.return_type, failure });
            result = try self.preludeExpression("Result", payloads, sites, syntax.span);
        }
        arguments[syntax.parameters.len] = result;
        const callback = try allocator.create(Callback);
        callback.* = .{ .syntax = syntax, .arguments = arguments };
        return .{ .callback = callback };
    }
    fn preludeExpression(self: *Index, name: []const u8, arguments: []const Expression, sites: []const Span, span: Span) Error!Expression {
        const application = try self.context.allocator.create(Application);
        application.* = .{ .syntax = .{ .span = span, .name = span, .arguments = sites }, .declaration = self.names.get(name) orelse return error.InternalError, .arguments = arguments };
        return .{ .application = application };
    }
    /// Resolve syntax to declaration identities without substituting representative concrete types.
    pub fn expression(self: *Index, span: Span, parameters: []const requirements.Parameter) Error!Expression {
        const ctx = self.context;
        if (self.budget.depth == 0) self.budget = .{ .site = span };
        if (self.budget.depth == 256 or self.budget.work == 100000) return self.limit(span);
        self.budget.depth += 1;
        self.budget.work += 1;
        defer self.budget.depth -= 1;
        for (self.syntax.suffixes) |suffix| if (suffix.span.start == span.start and suffix.span.end == span.end) {
            const arguments = try ctx.allocator.alloc(Expression, 1);
            arguments[0] = try self.expression(suffix.base, parameters);
            return self.preludeExpression(if (suffix.kind == .growable) "list" else "Option", arguments, &.{suffix.base}, span);
        };
        if (self.syntax.callbacks.get(span.start)) |syntax| return self.callbackExpression(syntax, parameters);
        if (self.syntax.tuples.get(span.start)) |syntax| return self.tupleExpression(syntax, parameters);
        if (self.syntax.arrays.get(span.start)) |syntax| return self.arrayExpression(syntax, parameters);
        if (self.syntax.applications.get(span.start)) |syntax| return self.applicationExpression(syntax, parameters);
        if (self.parameter(span, parameters)) |id| {
            if (parameters[id].constant_length) return ctx.sink.fail(diagnostic.generic_length, span, "a const length parameter is a value, not a type");
            return .{ .parameter = id };
        }
        if (typed.Type.fromName(ctx.src.text(span))) |ty| return .{ .builtin = ty };
        // Canonical capability/file spellings are scalar builtins, not nominal
        // declarations, so a record field or array element reaches them here.
        // A declared type of the same name still wins.
        if (@import("prelude.zig").reservedType(ctx.src.text(span))) |reserved| {
            const claimed = if (ctx.names) |names| (try names.symbolKind(span)) != null else self.names.contains(ctx.src.text(span));
            if (!claimed) return .{ .builtin = reserved };
        }
        if (self.syntax.aliases.count() != 0 and !(self.names.contains(ctx.src.text(span)) and self.declarations.items[self.names.get(ctx.src.text(span)).?].builtin_name != null)) {
            const alias_name = if (ctx.names) |names| try names.reference(span, .type, null, null, ctx.sink) else ctx.src.text(span);
            if (self.syntax.aliases.getPtr(alias_name)) |alias| {
                if (alias.visiting) return ctx.sink.fail("E_ALIAS_CYCLE", span, "type aliases must have acyclic dependencies");
                alias.visiting = true;
                defer alias.visiting = false;
                return self.expression(alias.declaration.target, &.{});
            }
        }
        const id = try self.lookup(span);
        if (self.declarations.items[id].parameters.len != 0) return ctx.sink.fail(eGenericArity, span, "nominal template requires explicit type arguments");
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
            if (@hasField(@TypeOf(input), "fields") and input.fields.len != 0) {
                out.* = .{ .name = input.name, .ty = .{ .named = try self.caseRecord(id, input.name, input.fields) } };
                continue;
            }
            const span: ?Span = if (@hasField(@TypeOf(input), "ty")) input.ty else input.payload;
            out.* = .{
                .name = input.name,
                .ty = if (span) |at| try self.expression(at, declaration.parameters) else null,
                .default_value = if (@hasField(@TypeOf(input), "default_value"))
                    (if (input.default_value) |value| @backingInt(value) else null)
                else
                    null,
            };
        }
        if (declaration.kind != .record and inputs.len == 0) return ctx.sink.fail("E_EMPTY_VARIANTS", name, "closed enum and union types require at least one variant");
        if (declaration.kind == .result) {
            for (inputs) |input| if (@hasField(@TypeOf(input), "fields") and input.fields.len != 0)
                return ctx.sink.fail(eResultSchema, input.name, "a result case takes one payload type, not named fields");
            const named_cases = names.contains("ok") and names.contains("err");
            if (inputs.len != 2 or !named_cases) return ctx.sink.fail(eResultSchema, name, "a result declares exactly `ok: Value` and `err: Error` payload cases");
            for (resolved) |field| if (field.ty == null) return ctx.sink.fail(eResultSchema, field.name, "result cases require explicit payload types");
        }
        self.declarations.items[id].fields = resolved;
    }
    /// Synthesize the payload record a parenthesized case declares. The record
    /// shares the union's own resolved type parameters, so a generic union's
    /// case fields instantiate with the union's arguments; its display name is
    /// `Union.case` and it is marked synthetic so it never becomes spellable.
    fn caseRecord(self: *Index, union_id: usize, case_name: Span, inputs: []const ast.Parameter) Error!usize {
        const ctx = self.context;
        const parameters = self.declarations.items[union_id].parameters;
        const resolved = try ctx.allocator.alloc(Field, inputs.len);
        var names: std.StringHashMapUnmanaged(Span) = .empty;
        defer names.deinit(ctx.allocator);
        for (inputs, resolved) |input, *out| {
            if (names.get(ctx.src.text(input.name))) |previous| return ctx.sink.failRelated("E_DUPLICATE_FIELD", input.name, "field is already declared", .{ .span = previous, .message = "previous declaration" });
            try names.put(ctx.allocator, ctx.src.text(input.name), input.name);
            out.* = .{
                .name = input.name,
                .ty = try self.expression(input.ty, parameters),
                .default_value = if (input.default_value) |value| @backingInt(value) else null,
            };
        }
        const display = try std.fmt.allocPrint(ctx.allocator, "{s}.{s}", .{ ctx.src.text(self.declarations.items[union_id].name), ctx.src.text(case_name) });
        const id = self.declarations.items.len;
        try self.synthetic.put(ctx.allocator, id, {});
        try self.declarations.append(ctx.allocator, .{
            .builtin_name = display,
            .name = case_name,
            .parameters = parameters,
            .kind = .record,
            .fields = resolved,
        });
        return id;
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
                .record, .variants, .tuple => copyGuarantee(),
                .enumeration, .domain => .{ .bits = 19 },
                .buffer => copyGuarantee(),
                .resource, .result => .{},
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
            .callback => |callback| for (callback.arguments) |argument| try self.checkArguments(argument, parameters),
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
        .callback => |callback| dependent: {
            for (callback.arguments) |argument| if (depends(argument)) break :dependent true;
            break :dependent false;
        },
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
    for (program.types.records) |declaration| {
        if (declaration.managed) return sink.fail(
            "E_VALUE_CLASS",
            declaration.name,
            "class is shared mutable state under value semantics; use a record or recursive union for values, or a pool handle for identity",
        );
        try index.add(declaration.name, declaration.type_parameters, .record);
        index.declarations.items[index.declarations.items.len - 1].managed = declaration.managed;
    }
    for (program.types.variants) |declaration| try index.add(declaration.name, declaration.type_parameters, if (declaration.fallible) .result else if (declaration.is_union) .variants else .enumeration);
    inline for (.{ "domains", "resources" }, .{ Kind.domain, .resource }) |category, kind| {
        for (@field(program.types, category)) |declaration| {
            try index.add(declaration.name, declaration.type_parameters, kind);
            index.declarations.items[index.declarations.items.len - 1].managed = declaration.managed;
        }
    }
    for (program.types.expressions.aliases) |alias| {
        const key = if (module_names) |names| try names.declaration(alias.name) else src.text(alias.name);
        if (index.names.contains(key) or index.syntax.aliases.contains(key)) return sink.fail("E_DUPLICATE_TYPE", alias.name, "alias name conflicts with an existing type declaration");
        try index.syntax.aliases.put(allocator, key, .{ .declaration = alias });
    }
    try index.checkParameters(program);
    try index.addPrelude(program);
    index.syntax.suffixes = program.types.expressions.suffixes;
    for (program.types.expressions.callbacks) |syntax| try index.syntax.callbacks.put(allocator, syntax.span.start, syntax);
    for (program.types.expressions.arrays) |syntax| try index.syntax.arrays.put(allocator, syntax.span.start, syntax);
    for (program.types.expressions.tuples) |syntax| try index.syntax.tuples.put(allocator, syntax.span.start, syntax);
    for (program.types.expressions.applications) |syntax| try index.syntax.applications.put(allocator, syntax.span.start, syntax);
    for (program.types.records) |declaration| try index.fields(declaration.name, declaration.fields);
    for (program.types.variants) |declaration| try index.fields(declaration.name, declaration.cases);
    try index.inferGuarantees();
    index.inferStorable();
    for (index.declarations.items) |declaration| {
        if (declaration.parameters.len == 0 or declaration.kind != .buffer) continue;
        const element = declaration.fields[0];
        if (!index.guarantees(element.ty.?, declaration.parameters).contains(.copy)) return sink.fail(
            eRequirement,
            element.name,
            "managed collection elements must guarantee copy",
        );
    }
    for (index.declarations.items) |declaration| for (declaration.fields) |field| if (field.ty) |value| try index.checkArguments(value, declaration.parameters);
    return index;
}
