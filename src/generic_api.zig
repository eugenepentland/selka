//! Checked symbolic public templates, deliberately separate from concrete call schemas.
//!
//! The generic-template JSON shape is versioned by `generic-templates-v2`. Each
//! exported function/constructor template carries a `contract.type_parameters`
//! list; a type parameter additionally carries `named_requirements` when its
//! bound names an exported (or same-module) constraint. Each entry retains the
//! bound spelling as written (`name`, including any module alias), the resolved
//! declaring `module`, and that bound's own expanded `requirements`,
//! `field_requirements`, and `operation_requirements`. The parameter's top-level
//! requirement arrays are the fully expanded union of inline and named promises,
//! so a provider can read either the complete contract or the per-bound detail.
//!
//! Exported constraint declarations are published as a distinct, non-callable
//! template kind (`"constraint"`) with a `constraint.subject` name and the same
//! expanded promise shape. They are never callable endpoints and have no concrete
//! signature.
const std = @import("std");
const ast = @import("ast.zig");
const source = @import("source.zig");
const interfaces = @import("interfaces.zig");
const effects = @import("effect_set.zig");
const diagnostic = @import("diagnostic.zig");
const generic_requirements = @import("generic_requirements.zig");
const constraint_lookup = @import("constraint_lookup.zig");
const module_names = @import("module_names.zig");
const project_syntax = @import("project_syntax.zig");

/// Errors surfaced while expanding checked named bounds into the public mirror.
pub const Error = diagnostic.Error;

/// Expanded builtin/field/operation promises of one inline list or named bound.
const Expanded = struct {
    requirements: []const []const u8,
    field_requirements: []const Value,
    operation_requirements: []const Operation,
};
/// One named bound used by a type parameter, with its declaring module and promises.
const NamedRequirement = struct {
    /// Bound spelling exactly as used at the parameter, e.g. `contracts.Prices`.
    name: []const u8,
    /// Resolved declaring module's public name, e.g. `contracts`.
    module: []const u8,
    expanded: Expanded,
};
/// Exported constraint declaration's subject binder and expanded promises.
const ConstraintInfo = struct {
    subject: []const u8,
    expanded: Expanded,
};
const Parameter = struct {
    constant_length: bool,
    name: []const u8,
    requirements: []const []const u8,
    field_requirements: []const Value,
    operation_requirements: []const Operation,
    /// Per-bound detail; the arrays above already hold the expanded union.
    named_requirements: []const NamedRequirement = &.{},
};
const Operation = struct { name: []const u8, parameters: []const Value, result: []const u8, declared_effects: []const []const u8 };
const Value = struct { name: []const u8, type: []const u8 };
const Case = struct { name: []const u8, payload: ?[]const u8 };
const Location = struct { path: []const u8, start: usize, end: usize, line: usize, column: usize, sha256: []const u8 };
/// Symbolic constructor/function declaration; borrowed strings remain owned by the checked project.
pub const Template = struct {
    name: []const u8,
    module: []const u8,
    kind: enum { function, record, tagged_union, result, enumeration, constraint },
    contract: Contract,
    shape: Shape = .{},
    imports: []const @import("source_receipt.zig").Import,
    source: Location,
};
const Contract = struct {
    callable: bool = false,
    requires_explicit_instantiation: bool = true,
    type_resolution: []const u8 = "declaration-module-scope",
    type_parameters: []const Parameter = &.{},
    signature: Signature = .{},
    /// Present only for `kind == .constraint`; absent for callable constructors.
    constraint: ?ConstraintInfo = null,
};
const Signature = struct {
    parameters: ?[]const Value = null,
    result: ?[]const u8 = null,
    declared_effects: ?[]const []const u8 = null,
    declared_mutates: ?[]const u16 = null,
    return_origin: ?[]const u8 = null,
};
const Shape = struct { fields: ?[]const Value = null, cases: ?[]const Case = null };
const Subject = struct { aliases: []const generic_requirements.SubjectAlias, name: []const u8 };

const Context = struct {
    allocator: std.mem.Allocator,
    index: *interfaces.Index,
    /// Merged source for the whole project; named-bound lookups use these coordinates.
    src: source.Source,
    /// Merged syntax retained so named constraints resolve through the checked index.
    program: ast.Program,
    names: *module_names.Names,
    module: usize,

    fn provider(self: Context) constraint_lookup.Provider {
        return .{ .program = self.program, .src = self.src, .names = self.names };
    }
    fn moduleAt(self: Context, span: source.Span) ?usize {
        const original = self.src.originalSpan(span) catch return null;
        return original.input;
    }
    /// A template is public only when its relocated declaration names an exported
    /// top-level symbol. Domain members keep their qualified namespace key and are
    /// not published as free templates, matching the pre-body inventory.
    fn visible(self: Context, span: source.Span) bool {
        const original = self.src.originalSpan(span) catch return false;
        const unit = self.index.units[self.module];
        for (unit.symbols.items) |symbol| {
            if (symbol.owner != null) continue;
            if (symbol.span.start != original.span.start or symbol.span.end != original.span.end) continue;
            return symbol.exported and !symbol.restricted;
        }
        return false;
    }
    fn parameters(self: Context, parameters_: []const ast.TypeParameter) Error![]const Parameter {
        if (parameters_.len == 0) return &.{};
        var lookup_provider = self.provider();
        var sink: diagnostic.Sink = .{ .allocator = self.allocator };
        const lookup = lookup_provider.lookup();
        const resolved = try generic_requirements.resolveBounds(self.allocator, self.src, parameters_, &sink, lookup);
        const out = try self.allocator.alloc(Parameter, parameters_.len);
        for (out, parameters_, resolved) |*item, parameter, requirement| {
            const parameter_name = self.src.text(parameter.name);
            const aliases = generic_requirements.subjectAliases(requirement);
            var explicit: std.ArrayList([]const u8) = .empty;
            if (parameter.default_copy) try appendUnique(self.allocator, &explicit, "copy");
            for (parameter.requirements) |span| try appendUnique(self.allocator, &explicit, self.src.text(span));
            var named: std.ArrayList(NamedRequirement) = .empty;
            for (parameter.named_requirements) |reference| {
                const definition = try lookup.find(lookup.ctx, reference, &sink);
                const declared = definition.body;
                if (declared.default_copy) try appendUnique(self.allocator, &explicit, "copy");
                for (declared.requirements) |span| try appendUnique(self.allocator, &explicit, self.src.text(span));
                // Resolve just this bound so its expanded promises and subject
                // alias stay attributable to the spelling used on the parameter.
                const synthetic: ast.TypeParameter = .{ .name = parameter.name, .requirements = &.{}, .named_requirements = &.{reference} };
                const one = [_]ast.TypeParameter{synthetic};
                const expanded = try generic_requirements.resolveBounds(self.allocator, self.src, &one, &sink, lookup);
                const expanded_aliases = generic_requirements.subjectAliases(expanded[0]);
                const module_index = definition.module orelse return error.InternalError;
                try named.append(self.allocator, .{
                    .name = try self.boundName(reference),
                    .module = self.index.project.modules.items[module_index].name,
                    .expanded = .{
                        .requirements = try explicitBuiltins(self, declared),
                        .field_requirements = try self.values(expanded[0].field_requirements, expanded_aliases, parameter_name),
                        .operation_requirements = try self.operations(expanded[0].operation_requirements, expanded_aliases, parameter_name),
                    },
                });
            }
            item.* = .{
                .name = parameter_name,
                .constant_length = parameter.constant_length,
                .requirements = try explicit.toOwnedSlice(self.allocator),
                .field_requirements = try self.values(requirement.field_requirements, aliases, parameter_name),
                .operation_requirements = try self.operations(requirement.operation_requirements, aliases, parameter_name),
                .named_requirements = try named.toOwnedSlice(self.allocator),
            };
        }
        return out;
    }
    /// Render parsed type expressions with only subject leaves substituted;
    /// qualified concrete names, array lengths and effect syntax stay intact.
    fn typeText(self: Context, span: source.Span, aliases: []const generic_requirements.SubjectAlias, parameter_name: []const u8) Error![]const u8 {
        if (aliases.len == 0) return self.src.text(span);
        var output: std.Io.Writer.Allocating = .init(self.allocator);
        errdefer output.deinit();
        try self.writeType(&output.writer, span, .{ .aliases = aliases, .name = parameter_name }, 0);
        return output.toOwnedSlice();
    }
    fn writeType(self: Context, writer: *std.Io.Writer, span: source.Span, subject: Subject, depth: usize) Error!void {
        if (depth == 256) return error.InternalError; // Checked type syntax is depth-bounded.
        if (generic_requirements.matchScope(subject.aliases, self.src, span) == .subject) {
            writer.writeAll(subject.name) catch return error.OutOfMemory;
            return;
        }
        var at = span.start;
        for (try self.typeChildren(span)) |child| {
            writer.writeAll(self.src.text(.{ .start = at, .end = child.start })) catch return error.OutOfMemory;
            try self.writeType(writer, child, subject, depth + 1);
            at = child.end;
        }
        writer.writeAll(self.src.text(.{ .start = at, .end = span.end })) catch return error.OutOfMemory;
    }
    fn typeChildren(self: Context, span: source.Span) Error![]const source.Span {
        const expressions = self.program.types.expressions;
        for (expressions.applications) |application| {
            if (std.meta.eql(application.span, span)) return application.arguments;
        }
        for (expressions.callbacks) |callback| {
            if (!std.meta.eql(callback.span, span)) continue;
            const children = try self.allocator.alloc(source.Span, callback.parameters.len + 1);
            @memcpy(children[0..callback.parameters.len], callback.parameters);
            children[callback.parameters.len] = callback.return_type;
            return children;
        }
        for (expressions.arrays) |array| {
            if (!std.meta.eql(array.span, span)) continue;
            return self.allocator.dupe(source.Span, if (array.index == .enum_type) &.{ array.index.enum_type, array.element } else &.{array.element});
        }
        return &.{};
    }
    fn values(self: Context, parameters_: []const ast.Parameter, aliases: []const generic_requirements.SubjectAlias, parameter_name: []const u8) Error![]const Value {
        const out = try self.allocator.alloc(Value, parameters_.len);
        for (out, parameters_) |*item, parameter| item.* = .{
            .name = self.src.text(parameter.name),
            .type = try self.typeText(parameter.ty, aliases, parameter_name),
        };
        return out;
    }
    fn operations(self: Context, operations_: []const ast.Operation, aliases: []const generic_requirements.SubjectAlias, parameter_name: []const u8) Error![]const Operation {
        const out = try self.allocator.alloc(Operation, operations_.len);
        for (out, operations_) |*item, original| item.* = .{
            .name = self.src.text(original.name),
            .parameters = try self.values(original.parameters, aliases, parameter_name),
            .result = try self.typeText(original.return_type, aliases, parameter_name),
            .declared_effects = try self.effectNames(original.effect_bound.allowed),
        };
        return out;
    }
    fn boundName(self: Context, reference: ast.BoundReference) Error![]const u8 {
        if (reference.alias) |alias| return std.fmt.allocPrint(self.allocator, "{s}.{s}", .{ self.src.text(alias), self.src.text(reference.name) });
        return self.src.text(reference.name);
    }
    fn base(self: Context, name: source.Span, parameters_: []const ast.TypeParameter) Error!Template {
        const module = self.index.project.modules.items[self.module];
        const original = self.src.originalSpan(name) catch return error.InternalError;
        const location = module.src.locate(original.span.start);
        const imports = try self.allocator.alloc(@import("source_receipt.zig").Import, module.imports.len);
        for (imports, module.imports) |*item, imported| item.* = .{
            .module = self.index.project.modules.items[imported.target].name,
            .alias = imported.alias,
        };
        return .{
            .name = try std.fmt.allocPrint(self.allocator, "{s}::{s}", .{ module.name, self.src.text(name) }),
            .module = module.name,
            .kind = .function,
            .contract = .{ .type_parameters = try self.parameters(parameters_) },
            .imports = imports,
            .source = .{
                .path = module.src.path,
                .start = original.span.start,
                .end = original.span.end,
                .line = location.line,
                .column = location.column,
                .sha256 = try std.fmt.allocPrint(self.allocator, "{s}", .{std.fmt.bytesToHex(module.digest, .lower)}),
            },
        };
    }
    fn function(self: Context, declaration: ast.Function) Error!Template {
        var out = try self.base(declaration.name, declaration.signature.type_parameters);
        out.contract.signature.parameters = try self.values(declaration.signature.parameters, &.{}, "");
        out.contract.signature.result = self.src.text(declaration.signature.return_type);
        if (declaration.policy.effect_bound) |bound| {
            out.contract.signature.declared_effects = try self.effectNames(bound.allowed);
            out.contract.signature.declared_mutates = declaration.signature.mutates;
            out.contract.signature.return_origin = "unknown";
        }
        return out;
    }
    fn constraintTemplate(self: Context, declaration: ast.Constraint) Error!Template {
        const subject = self.src.text(declaration.subject.name);
        var out = try self.base(declaration.name, &.{});
        out.kind = .constraint;
        out.contract = .{};
        out.contract.constraint = .{
            .subject = subject,
            .expanded = .{
                .requirements = try explicitBuiltins(self, &declaration.subject),
                .field_requirements = try self.values(declaration.subject.field_requirements, &.{}, subject),
                .operation_requirements = try self.operations(declaration.subject.operation_requirements, &.{}, subject),
            },
        };
        return out;
    }
    fn effectNames(self: Context, mask: effects.Mask) Error![]const []const u8 {
        var names: std.ArrayList([]const u8) = .empty;
        inline for (std.meta.tags(effects.Effect)) |effect| {
            if (mask & effects.bit(effect) != 0) try names.append(self.allocator, @tagName(effect));
        }
        return names.items;
    }
};

fn explicitBuiltins(self: Context, subject: *const ast.TypeParameter) Error![]const []const u8 {
    var names: std.ArrayList([]const u8) = .empty;
    if (subject.default_copy) try appendUnique(self.allocator, &names, "copy");
    for (subject.requirements) |span| try appendUnique(self.allocator, &names, self.src.text(span));
    return names.toOwnedSlice(self.allocator);
}
fn appendUnique(allocator: std.mem.Allocator, list: *std.ArrayList([]const u8), name: []const u8) !void {
    for (list.items) |existing| if (std.mem.eql(u8, existing, name)) return;
    try list.append(allocator, name);
}
/// Render a parenthesized case's named fields as its API payload text, so an
/// exported generic union publishes each field and whether it has a default.
/// A case without named fields has no such text.
fn caseFieldsText(allocator: std.mem.Allocator, src: source.Source, fields: []const ast.Parameter) Error!?[]const u8 {
    if (fields.len == 0) return null;
    var out: std.ArrayList(u8) = .empty;
    try out.appendSlice(allocator, "(");
    for (fields, 0..) |field, index| {
        if (index != 0) try out.appendSlice(allocator, ",");
        try out.appendSlice(allocator, src.text(field.name));
        try out.appendSlice(allocator, ":");
        try out.appendSlice(allocator, src.text(field.ty));
        if (field.default_value != null) try out.appendSlice(allocator, "=default");
    }
    try out.appendSlice(allocator, ")");
    const text = try out.toOwnedSlice(allocator);
    return text;
}
fn less(_: void, a: Template, b: Template) bool {
    return std.mem.lessThan(u8, a.name, b.name);
}
/// Collect exported templates only after the caller has checked the complete project.
/// All allocations belong to the supplied arena; source views borrow the project.
pub fn collect(arena: std.mem.Allocator, index: *interfaces.Index) Error![]const Template {
    // The checked schema reports merged-language named contracts, so look them up
    // through the same relocated syntax the semantic checker uses.
    const merged = project_syntax.build(index) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return error.InternalError,
    };
    var names: module_names.Names = .{ .index = index, .src = merged.src };
    var context: Context = .{ .allocator = arena, .index = index, .src = merged.src, .program = merged.syntax, .names = &names, .module = 0 };
    var out: std.ArrayList(Template) = .empty;
    for (merged.syntax.functions) |function| {
        if (function.signature.type_parameters.len == 0) continue;
        const module = context.moduleAt(function.name) orelse continue;
        context.module = module;
        if (!context.visible(function.name)) continue;
        try out.append(arena, try context.function(function));
    }
    for (merged.syntax.types.records) |record| {
        if (record.type_parameters.len == 0) continue;
        const module = context.moduleAt(record.name) orelse continue;
        context.module = module;
        if (!context.visible(record.name)) continue;
        var item = try context.base(record.name, record.type_parameters);
        item.kind = .record;
        item.shape.fields = try context.values(record.fields, &.{}, "");
        try out.append(arena, item);
    }
    for (merged.syntax.types.variants) |variant| {
        if (variant.type_parameters.len == 0) continue;
        const module = context.moduleAt(variant.name) orelse continue;
        context.module = module;
        if (!context.visible(variant.name)) continue;
        var item = try context.base(variant.name, variant.type_parameters);
        item.kind = if (variant.fallible) .result else if (variant.is_union) .tagged_union else .enumeration;
        const cases = try arena.alloc(Case, variant.cases.len);
        for (cases, variant.cases) |*case, original| case.* = .{
            .name = context.src.text(original.name),
            .payload = if (original.payload) |payload| context.src.text(payload) else try caseFieldsText(arena, context.src, original.fields),
        };
        item.shape.cases = cases;
        try out.append(arena, item);
    }
    for (merged.syntax.types.constraints) |constraint| {
        const module = context.moduleAt(constraint.name) orelse continue;
        context.module = module;
        if (!context.visible(constraint.name)) continue;
        try out.append(arena, try context.constraintTemplate(constraint));
    }
    std.mem.sort(Template, out.items, {}, less);
    return out.items;
}
/// Whether an exported source symbol denotes a constructor rather than a concrete type.
pub fn isConstructor(unit: interfaces.Unit, span: source.Span) bool {
    inline for (.{ "records", "variants" }) |category| for (@field(unit.syntax.types, category)) |declaration| {
        if (declaration.name.start == span.start and declaration.type_parameters.len != 0) return true;
    };
    return false;
}
