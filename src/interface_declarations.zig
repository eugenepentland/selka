//! Project/AST projection and ownership transfer for declaration component values.
const std = @import("std");
const value = @import("declaration_value.zig");
const wire = @import("declaration_component_protocol.zig");
/// Project parsed facts without constructing names, resolving exports or selecting diagnostics.
pub fn input(a: std.mem.Allocator, index: anytype, module_id: usize, is_imported: bool) wire.Error!value.Input {
    const module = index.project.modules.items[module_id];
    if (module.src.bytes.len > 1048576 or module.imports.len > 4096) return error.ComponentProtocol;
    const syntax = index.units[module_id].syntax;
    var declarations: std.ArrayList(value.Declaration) = .empty;
    inline for (.{ "records", "domains", "variants", "resources" }, 0..) |field, category| {
        for (@field(syntax.types, field)) |item| try declarations.append(a, .{ .category = @fromBackingInt(@intCast(category)), .span = item.name });
    }
    for (syntax.types.expressions.aliases) |item| try declarations.append(a, .{ .category = .alias, .span = item.name });
    for (syntax.types.constraints) |item| try declarations.append(a, .{ .category = .constraint, .span = item.name });
    for (syntax.functions) |item| try declarations.append(a, .{ .category = .function, .span = item.name, .owner = item.policy.owner, .restricted = item.policy.restricted });
    const imports = try a.alloc(value.Import, module.imports.len);
    for (module.imports, imports) |item, *out| out.* = .{ .name = item.name, .alias = item.alias, .span = item.span, .target = item.target };
    const exports = try a.alloc(value.Export, module.exports.len);
    for (module.exports, exports) |item, *out| out.* = .{ .name = item.name, .alias = item.alias, .span = item.span };
    var dependencies: std.ArrayList(value.Dependency) = .empty;
    var seen: std.AutoHashMapUnmanaged(usize, void) = .empty;
    for (module.imports) |item| {
        const entry = try seen.getOrPut(a, item.target);
        if (entry.found_existing) continue;
        const target = index.project.modules.items[item.target];
        try dependencies.append(a, .{ .module = item.target, .name = target.name, .source_len = target.src.bytes.len, .symbols = index.units[item.target].symbols.items });
    }
    return .{
        .context = .{ .module = module_id, .name = module.name, .path = module.src.path, .trusted_intrinsics = module.src.trusted_intrinsics, .is_imported = is_imported, .source = module.src.bytes },
        .declarations = declarations.items,
        .imports = imports,
        .exports = exports,
        .public = syntax.types.public_declarations,
        .dependencies = dependencies.items,
    };
}
/// Copy a validated successful table into project storage for later native checking.
pub fn adopt(index: anytype, module_id: usize, output: value.Output, ready: []const bool) wire.Error!void {
    const a = index.project.arena.allocator();
    const unit = &index.units[module_id];
    if (unit.symbols.items.len != 0 or unit.import_used.len != output.import_used.len) return error.ComponentProtocol;
    if (ready.len != index.units.len) return error.ComponentProtocol;
    const symbols = try a.alloc(value.Symbol, output.symbols.len);
    for (symbols, output.symbols, 0..) |*out, item, symbol_id| {
        if (item.re_export) |origin| {
            if (origin.module >= index.units.len or origin.module == module_id) return error.ComponentProtocol;
            // Only an already indexed transitive dependency may be a canonical origin.
            if (!ready[origin.module]) return error.ComponentProtocol;
            const targets = index.units[origin.module].symbols.items;
            if (origin.symbol >= targets.len or targets[origin.symbol].kind != item.kind or targets[origin.symbol].re_export != null) return error.ComponentProtocol;
        }
        out.* = item;
        out.name = try a.dupe(u8, item.name);
        if (item.owner) |owner| out.owner = try a.dupe(u8, owner);
        try unit.names.putNoClobber(a, out.name, symbol_id);
    }
    unit.symbols = .fromOwnedSlice(symbols);
    @memcpy(unit.import_used, output.import_used);
}
