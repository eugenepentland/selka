//! Raw namespace projection and import-use transfer for scalar body checking.
const std = @import("std");
const ast = @import("ast.zig");
const source = @import("source.zig");
const Names = @import("module_names.zig").Names;
const value = @import("body_check_value.zig");
const declaration = @import("declaration_value.zig");
const records = @import("records.zig");
const materialize = @import("body_check_materialize.zig");
/// Allocation or malformed raw namespace projection.
pub const Error = error{ OutOfMemory, ComponentProtocol };

/// Project raw syntax and existing namespace facts without checking a body.
pub fn input(a: std.mem.Allocator, src: source.Source, program: ast.Program, names: ?*Names, entry_required: bool, catalog: records.Catalog) Error!value.Input {
    return .{
        .context = .{ .path = src.path, .source = src.bytes, .trusted_intrinsics = src.trusted_intrinsics, .entry_required = entry_required },
        .program = program,
        .modules = if (names) |project_names| try modules(a, src, project_names) else &.{},
        .catalog = try materialize.project(a, catalog),
    };
}

fn modules(a: std.mem.Allocator, src: source.Source, names: *Names) Error![]const value.Module {
    const project = names.index.project;
    const units = names.index.units;
    if (project.modules.items.len > 4096 or src.origins.len != units.len or project.modules.items.len != units.len) return error.ComponentProtocol;
    const imported = try a.alloc(bool, units.len);
    defer a.free(imported);
    @memset(imported, false);
    var import_count: usize = 0;
    for (project.modules.items) |module| {
        if (module.imports.len > 65536 - import_count) return error.ComponentProtocol;
        import_count += module.imports.len;
        for (module.imports) |edge| {
            if (edge.target >= imported.len) return error.ComponentProtocol;
            imported[edge.target] = true;
        }
    }
    const output = try a.alloc(value.Module, units.len);
    for (project.modules.items, units, output, 0..) |module, unit, *out, id| {
        const imports = try a.alloc(declaration.Import, module.imports.len);
        for (module.imports, imports) |item, *edge| edge.* = .{ .name = item.name, .alias = item.alias, .span = item.span, .target = item.target };
        out.* = .{
            .context = .{ .module = id, .name = module.name, .path = module.src.path, .trusted_intrinsics = module.src.trusted_intrinsics, .is_imported = imported[id], .source = module.src.bytes },
            .offset = src.origins[id].start,
            .imports = imports,
            .symbols = unit.symbols.items,
            .import_used = try a.dupe(bool, unit.import_used),
        };
    }
    return output;
}

/// Observe the native oracle's final flags without changing the input snapshot.
pub fn importUsage(a: std.mem.Allocator, names: ?*Names) Error![]const []const bool {
    const project_names = names orelse return &.{};
    const units = project_names.index.units;
    const output = try a.alloc([]const bool, units.len);
    for (units, output) |unit, *out| out.* = unit.import_used;
    return output;
}

/// Transfer validated flags to the existing module index after authentication.
pub fn adoptUsage(names: ?*Names, used: []const []const bool) Error!void {
    const project_names = names orelse {
        if (used.len != 0) return error.ComponentProtocol;
        return;
    };
    if (used.len != project_names.index.units.len) return error.ComponentProtocol;
    for (project_names.index.units, used) |unit, flags| {
        if (flags.len != unit.import_used.len) return error.ComponentProtocol;
        @memcpy(unit.import_used, flags);
    }
}

/// Merge retained common-phase usage before any native body oracle runs.
/// Returned rows belong to the allocator; producer body observations stay exact.
pub fn mergeUsage(a: std.mem.Allocator, producer: []const []const bool, common: []const []const bool) Error![]const []const bool {
    if (producer.len != common.len) return error.ComponentProtocol;
    const output = try a.alloc([]const bool, producer.len);
    errdefer a.free(output);
    var initialized: usize = 0;
    errdefer for (output[0..initialized]) |row| a.free(row);
    for (producer, common, output) |observed, initial, *row| {
        if (observed.len != initial.len) return error.ComponentProtocol;
        const merged = try a.alloc(bool, observed.len);
        row.* = merged;
        initialized += 1;
        for (observed, initial, merged) |body_used, common_used, *used| used.* = body_used or common_used;
    }
    return output;
}
