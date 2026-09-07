//! Checked symbolic public templates, deliberately separate from concrete call schemas.
const std = @import("std");
const ast = @import("ast.zig");
const source = @import("source.zig");
const interfaces = @import("interfaces.zig");
const effects = @import("effect_set.zig");
const Parameter = struct { name: []const u8, requirements: []const []const u8, field_requirements: []const Value, operation_requirements: []const Operation };
const Operation = struct { name: []const u8, parameters: []const Value, result: []const u8, declared_effects: []const []const u8 };
const Value = struct { name: []const u8, type: []const u8, reference: ?bool, slice: bool };
const Case = struct { name: []const u8, payload: ?[]const u8 };
const Provenance = struct { parameter: []const u8, mutable: bool, slice: bool };
const Location = struct { path: []const u8, start: usize, end: usize, line: usize, column: usize, sha256: []const u8 };
/// Symbolic constructor/function declaration; borrowed strings remain owned by the checked project.
pub const Template = struct {
    name: []const u8,
    module: []const u8,
    kind: enum { function, record, tagged_union, result, enumeration, buffer, pool, handle },
    contract: Contract,
    shape: Shape = .{},
    imports: []const @import("source_receipt.zig").Import,
    source: Location,
};
const Contract = struct {
    callable: bool = false,
    requires_explicit_instantiation: bool = true,
    type_resolution: []const u8 = "declaration-module-scope",
    type_parameters: []const Parameter,
    signature: Signature = .{},
};
const Signature = struct {
    parameters: ?[]const Value = null,
    result: ?[]const u8 = null,
    return_reference: ?Provenance = null,
    declared_effects: ?[]const []const u8 = null,
};
const Shape = struct { fields: ?[]const Value = null, cases: ?[]const Case = null, element: ?[]const u8 = null, handle: ?[]const u8 = null };

const Context = struct {
    allocator: std.mem.Allocator,
    index: *const interfaces.Index,
    module: usize,
    fn src(self: Context) source.Source {
        return self.index.project.modules.items[self.module].src;
    }
    fn visible(self: Context, name: source.Span) bool {
        const unit = self.index.units[self.module];
        const id = unit.names.get(self.src().text(name)) orelse return false;
        return unit.symbols.items[id].exported and !unit.symbols.items[id].restricted;
    }
    fn parameters(self: Context, parameters_: []const ast.TypeParameter) ![]const Parameter {
        const out = try self.allocator.alloc(Parameter, parameters_.len);
        for (out, parameters_) |*item, parameter| {
            const requirements = try self.allocator.alloc([]const u8, parameter.requirements.len);
            for (requirements, parameter.requirements) |*requirement, span| requirement.* = self.src().text(span);
            const operations = try self.allocator.alloc(Operation, parameter.operation_requirements.len);
            for (operations, parameter.operation_requirements) |*operation, original| operation.* = .{
                .name = self.src().text(original.name),
                .parameters = try self.values(original.parameters),
                .result = self.src().text(original.return_type),
                .declared_effects = try self.effectNames(original.effect_bound.allowed),
            };
            item.* = .{
                .name = self.src().text(parameter.name),
                .requirements = requirements,
                .field_requirements = try self.values(parameter.field_requirements),
                .operation_requirements = operations,
            };
        }
        return out;
    }
    fn values(self: Context, parameters_: []const ast.Parameter) ![]const Value {
        const out = try self.allocator.alloc(Value, parameters_.len);
        for (out, parameters_) |*item, parameter| item.* = .{
            .name = self.src().text(parameter.name),
            .type = self.src().text(parameter.ty),
            .reference = parameter.reference,
            .slice = parameter.slice,
        };
        return out;
    }
    fn base(self: Context, name: source.Span, parameters_: []const ast.TypeParameter) !Template {
        const module = self.index.project.modules.items[self.module];
        const location = self.src().locate(name.start);
        const imports = try self.allocator.alloc(@import("source_receipt.zig").Import, module.imports.len);
        for (imports, module.imports) |*item, imported| item.* = .{
            .module = self.index.project.modules.items[imported.target].name,
            .alias = imported.alias,
        };
        return .{
            .name = try std.fmt.allocPrint(self.allocator, "{s}::{s}", .{ module.name, self.src().text(name) }),
            .module = module.name,
            .kind = .function,
            .contract = .{ .type_parameters = try self.parameters(parameters_) },
            .imports = imports,
            .source = .{
                .path = module.src.path,
                .start = name.start,
                .end = name.end,
                .line = location.line,
                .column = location.column,
                .sha256 = try std.fmt.allocPrint(self.allocator, "{s}", .{std.fmt.bytesToHex(module.digest, .lower)}),
            },
        };
    }
    fn effectNames(self: Context, mask: effects.Mask) ![]const []const u8 {
        var names: std.ArrayList([]const u8) = .empty;
        inline for (std.meta.tags(effects.Effect)) |effect| {
            if (mask & effects.bit(effect) != 0) try names.append(self.allocator, @tagName(effect));
        }
        return names.items;
    }
    fn function(self: Context, declaration: ast.Function) !Template {
        var out = try self.base(declaration.name, declaration.signature.type_parameters);
        out.contract.signature.parameters = try self.values(declaration.signature.parameters);
        out.contract.signature.result = self.src().text(declaration.signature.return_type);
        if (declaration.signature.return_reference) |ref| out.contract.signature.return_reference = .{
            .parameter = self.src().text(ref.source),
            .mutable = ref.mutable,
            .slice = ref.slice,
        };
        if (declaration.policy.effect_bound) |bound| {
            out.contract.signature.declared_effects = try self.effectNames(bound.allowed);
        }
        return out;
    }
};
fn less(_: void, a: Template, b: Template) bool {
    return std.mem.lessThan(u8, a.name, b.name);
}
/// Collect exported templates only after the caller has checked the complete project.
/// All allocations belong to the supplied arena; source views borrow the project.
pub fn collect(arena: std.mem.Allocator, index: *const interfaces.Index) std.mem.Allocator.Error![]const Template {
    var out: std.ArrayList(Template) = .empty;
    for (index.units, 0..) |unit, module| {
        const context: Context = .{ .allocator = arena, .index = index, .module = module };
        for (unit.syntax.functions) |function| {
            if (function.signature.type_parameters.len == 0 or !context.visible(function.name)) continue;
            try out.append(arena, try context.function(function));
        }
        for (unit.syntax.types.records) |record| {
            if (record.type_parameters.len == 0 or !context.visible(record.name)) continue;
            var item = try context.base(record.name, record.type_parameters);
            item.kind = .record;
            item.shape.fields = try context.values(record.fields);
            try out.append(arena, item);
        }
        for (unit.syntax.types.buffers) |buffer| {
            if (buffer.type_parameters.len == 0 or !context.visible(buffer.name)) continue;
            var item = try context.base(buffer.name, buffer.type_parameters);
            item.kind = .buffer;
            item.shape.element = context.src().text(buffer.backing);
            try out.append(arena, item);
        }
        for (unit.syntax.types.pools) |pool| {
            if (pool.type_parameters.len == 0) continue;
            if (context.visible(pool.name)) {
                var item = try context.base(pool.name, pool.type_parameters);
                item.kind = .pool;
                item.shape.element = context.src().text(pool.element);
                item.shape.handle = context.src().text(pool.handle);
                try out.append(arena, item);
            }
            if (context.visible(pool.handle)) {
                var item = try context.base(pool.handle, pool.type_parameters);
                item.kind = .handle;
                try out.append(arena, item);
            }
        }
        for (unit.syntax.types.variants) |variant| {
            if (variant.type_parameters.len == 0 or !context.visible(variant.name)) continue;
            var item = try context.base(variant.name, variant.type_parameters);
            item.kind = if (variant.fallible) .result else if (variant.is_union) .tagged_union else .enumeration;
            const cases = try arena.alloc(Case, variant.cases.len);
            for (cases, variant.cases) |*case, original| case.* = .{
                .name = context.src().text(original.name),
                .payload = if (original.payload) |payload| context.src().text(payload) else null,
            };
            item.shape.cases = cases;
            try out.append(arena, item);
        }
    }
    std.mem.sort(Template, out.items, {}, less);
    return out.items;
}
/// Whether an exported source symbol denotes a constructor rather than a concrete type.
pub fn isConstructor(unit: interfaces.Unit, span: source.Span) bool {
    inline for (.{ "records", "variants", "buffers", "pools" }) |category| for (@field(unit.syntax.types, category)) |declaration| {
        if (declaration.name.start == span.start and declaration.type_parameters.len != 0) return true;
        if (@hasField(@TypeOf(declaration), "handle")) if (declaration.handle.start == span.start and declaration.type_parameters.len != 0) return true;
    };
    return false;
}
