//! Combine already-parsed module tables while preserving declaration ownership.
//! This is not name resolution: consumers must retain the module context below.
/// Failures returned by build; callers must handle these boundary errors.
pub const BuildError = error{
    EmptySourceMap,
    IncompleteProject,
    InvalidNodeId,
    InvalidSourceIndex,
    InvalidSourceSpan,
    InvalidStatementId,
    NestedSourceMap,
    OutOfMemory,
    Overflow,
};

const std = @import("std");
const ast = @import("ast.zig");
const source = @import("source.zig");
const interfaces = @import("interfaces.zig");
const literals_fact = @import("ast_literals.zig");
const lazy_module = @import("lazy_module.zig");
const lazy_loader = @import("lazy_loader.zig");
const compile_mode = @import("builtin").mode;
/// Half-open expression and statement ranges originating in one merged module.
pub const Range = struct { node_start: usize, node_end: usize, statement_start: usize, statement_end: usize };
/// Merged project syntax, mapped source, and entry identity backed by the project arena.
pub const Merged = struct {
    src: source.Source,
    syntax: ast.Program,
    modules: []const Range,
    function_modules: []const usize,
    /// The loader of the bodies still to be filled, when some module was read lazily; the program's `facts.loader` points into it.
    loader: ?*lazy_loader.Loader = null,
};
const Remap = @import("ast_copy.zig").Mapper;

/// What the merge notes about the trees as it writes them, so that no later pass looks for it: the literals the type catalog registers, in
/// node order, and the retired constructs the rejections look for.
const Notes = struct { literals: std.ArrayList(ast.Literal) = .empty, retired: ast.Retired = .{} };

fn anyLazy(index: *const interfaces.Index) bool {
    for (index.units) |unit| if (unit.lazy != null) return true;
    return false;
}

/// Write one module's nodes and statements into the merged tables at the bases `map` names, relocated. A module read lazily has only the
/// trees outside its lazy bodies written, and its facts come with the entry; any other module is copied whole and its facts are noted
/// as its trees go by.
fn writeTrees(allocator: std.mem.Allocator, unit: interfaces.Unit, map: Remap, merged: *ast.Program, notes: *Notes) BuildError!void {
    if (unit.lazy) |lazy| {
        for (lazy.declarations.node_runs) |run| {
            for (run.items, 0..) |node, k| merged.nodes.items[map.nodes + run.start + k] = try map.value(allocator, ast.Node, node);
        }
        for (lazy.declarations.statement_runs) |run| {
            for (run.items, 0..) |statement, k| merged.statements.items[map.statements + run.start + k] = try map.value(allocator, ast.Statement, statement);
        }
        for (lazy.declarations.facts.literals) |literal| try notes.literals.append(allocator, try map.value(allocator, ast.Literal, literal));
        notes.retired = notes.retired.merge(lazy.declarations.facts.retired);
        return;
    }
    const src = map.src.?;
    for (unit.syntax.nodes.items, 0..) |node, k| {
        const mapped = try map.value(allocator, ast.Node, node);
        merged.nodes.items[map.nodes + k] = mapped;
        if (literals_fact.of(src, mapped)) |literal| try notes.literals.append(allocator, literal);
        notes.retired = notes.retired.merge(.ofNode(mapped));
    }
    for (unit.syntax.statements.items, 0..) |statement, k| {
        const mapped = try map.value(allocator, ast.Statement, statement);
        merged.statements.items[map.statements + k] = mapped;
        notes.retired = notes.retired.merge(.ofStatement(mapped));
    }
}

/// All output storage belongs to index.project.arena; the original AST is unchanged.
pub fn build(index: *interfaces.Index) BuildError!Merged {
    const project = index.project;
    if (!project.progress.complete or project.problem != null) return error.IncompleteProject;
    const allocator = project.arena.allocator();
    const inputs = try allocator.alloc(source.Source, project.modules.items.len);
    for (inputs, project.modules.items) |*input, module| input.* = module.src;
    const src = try source.Source.initMapped(allocator, inputs);
    const ranges = try allocator.alloc(Range, inputs.len);
    var merged: ast.Program = .{ .nodes = .empty, .statements = .empty, .functions = &.{} };
    var function_modules: std.ArrayList(usize) = .empty;
    // Size the merged tables once: appending module by module into an arena
    // would otherwise regrow and recopy the whole program's nodes repeatedly.
    var node_total: usize = 0;
    var statement_total: usize = 0;
    var function_total: usize = 0;
    for (index.units) |unit| {
        node_total += unit.syntax.nodes.items.len;
        statement_total += unit.syntax.statements.items.len;
        function_total += unit.syntax.functions.len;
    }
    var notes: Notes = .{};
    const extents = try allocator.alloc(ast.Extent, inputs.len);
    try merged.nodes.ensureTotalCapacityPrecise(allocator, node_total);
    try merged.statements.ensureTotalCapacityPrecise(allocator, statement_total);
    try function_modules.ensureTotalCapacityPrecise(allocator, function_total);
    // The tables are written by id: a module read lazily leaves its bodies unwritten until `ensureBody`, and holds the sentinel meanwhile in
    // a build that looks for the reads that missed it.
    const lazy_any = anyLazy(index);
    merged.nodes.items.len = node_total;
    merged.statements.items.len = statement_total;
    if (lazy_any and (index.mode == .lazy_sentinel or compile_mode == .debug)) {
        @memset(std.mem.sliceAsBytes(merged.nodes.items), lazy_module.sentinel);
        @memset(std.mem.sliceAsBytes(merged.statements.items), lazy_module.sentinel);
    }
    var node_cursor: usize = 0;
    var statement_cursor: usize = 0;
    for (index.units, 0..) |unit, module| {
        const map: Remap = .{
            .src = src,
            .module = module,
            .nodes = node_cursor,
            .statements = statement_cursor,
            .node_count = unit.syntax.nodes.items.len,
            .statement_count = unit.syntax.statements.items.len,
        };
        try writeTrees(allocator, unit, map, &merged, &notes);
        node_cursor += unit.syntax.nodes.items.len;
        statement_cursor += unit.syntax.statements.items.len;
        ranges[module] = .{ .node_start = map.nodes, .node_end = node_cursor, .statement_start = map.statements, .statement_end = statement_cursor };
        const origin = src.origins[module];
        extents[module] = .{
            .node_start = ranges[module].node_start,
            .node_end = ranges[module].node_end,
            .statement_start = ranges[module].statement_start,
            .statement_end = ranges[module].statement_end,
            .source_start = origin.start,
            .source_end = origin.start + origin.original.bytes.len,
        };
        for (unit.syntax.functions) |_| try function_modules.append(allocator, module);
    }
    // Append each declaration category once, avoiding quadratic slice copying.
    inline for (.{ "functions", "records", "domains", "variants", "constraints", "suffixes", "arrays", "tuples", "applications", "callbacks", "aliases", "resources" }) |field| {
        const is_function = comptime std.mem.eql(u8, field, "functions");
        // `tuples` is a structural type expression too: a module program that
        // names one keeps it, exactly as it keeps a fixed-array spelling.
        const is_expression = comptime std.mem.eql(u8, field, "suffixes") or
            std.mem.eql(u8, field, "arrays") or std.mem.eql(u8, field, "tuples") or
            std.mem.eql(u8, field, "applications") or std.mem.eql(u8, field, "aliases") or
            std.mem.eql(u8, field, "callbacks");
        const Collection = if (is_function) ast.Program else if (is_expression) ast.TypeExpressions else ast.TypeDeclarations;
        const Slice = @FieldType(Collection, field);
        const Item = @typeInfo(Slice).pointer.child;
        var declarations: std.ArrayList(Item) = .empty;
        for (index.units, ranges, 0..) |unit, range, module| {
            const map: Remap = .{
                .src = src,
                .module = module,
                .nodes = range.node_start,
                .statements = range.statement_start,
                .node_count = unit.syntax.nodes.items.len,
                .statement_count = unit.syntax.statements.items.len,
            };
            for (@field(if (is_function) unit.syntax else if (is_expression) unit.syntax.types.expressions else unit.syntax.types, field)) |item| try declarations.append(allocator, try map.value(allocator, Item, item));
        }
        if (is_function) {
            merged.functions = try declarations.toOwnedSlice(allocator);
        } else {
            @field(if (is_expression) merged.types.expressions else merged.types, field) = try declarations.toOwnedSlice(allocator);
        }
    }
    // A `public` modifier publishes a declaration, so each module's name spans
    // must survive the merge under the same relocation as the declarations they
    // publish: a consumer resolves publication from a function's name span.
    var public_names: std.ArrayList(source.Span) = .empty;
    for (index.units, 0..) |unit, module| {
        const map: Remap = .{ .src = src, .module = module };
        for (unit.syntax.types.public_declarations) |span| try public_names.append(allocator, try map.value(allocator, source.Span, span));
    }
    merged.types.public_declarations = try public_names.toOwnedSlice(allocator);
    // Lambdas are syntax-only callable bodies: they are not module exports, but
    // their spans and body node identities must be relocated with the same map
    // as the rest of the merged syntax or a module program loses them.
    var lambdas: std.ArrayList(ast.Lambda) = .empty;
    for (index.units, ranges, 0..) |unit, range, module| {
        const map: Remap = .{
            .src = src,
            .module = module,
            .nodes = range.node_start,
            .statements = range.statement_start,
            .node_count = unit.syntax.nodes.items.len,
            .statement_count = unit.syntax.statements.items.len,
        };
        for (unit.syntax.lambdas) |lambda| try lambdas.append(allocator, try map.value(allocator, ast.Lambda, lambda));
    }
    merged.lambdas = try lambdas.toOwnedSlice(allocator);
    // Declaration attributes are keyed by each module's own name span, so they
    // must be relocated with the same map as the functions they describe. A
    // contract clause's condition is an expression of its module, so node
    // identities move with that module's node range too.
    var attributes: std.ArrayList(ast.DeclarationAttributes) = .empty;
    for (index.units, ranges, 0..) |unit, range, module| {
        const map: Remap = .{
            .src = src,
            .module = module,
            .nodes = range.node_start,
            .statements = range.statement_start,
            .node_count = unit.syntax.nodes.items.len,
            .statement_count = unit.syntax.statements.items.len,
        };
        for (unit.syntax.attributes) |entry| try attributes.append(allocator, try map.value(allocator, ast.DeclarationAttributes, entry));
    }
    merged.attributes = try attributes.toOwnedSlice(allocator);
    // Leading docstrings carry no expression or statement identity; they only
    // need the same span relocation as the declarations that own them.
    var docstrings: std.ArrayList(ast.DeclarationDoc) = .empty;
    for (index.units, 0..) |unit, module| {
        const map: Remap = .{ .src = src, .module = module };
        for (unit.syntax.docstrings) |entry| try docstrings.append(allocator, try map.value(allocator, ast.DeclarationDoc, entry));
    }
    merged.docstrings = try docstrings.toOwnedSlice(allocator);
    merged.facts = .{ .extents = extents, .literals = try notes.literals.toOwnedSlice(allocator), .retired = notes.retired };
    const loader = if (lazy_any) try attachLoader(allocator, index, src, &merged, ranges) else null;
    // The rejections of retired syntax look around the whole program for the repair they publish: a program that holds a retired
    // construct, or a lambda, is complete before anything reads it.
    if (loader != null and (notes.retired.any() or merged.lambdas.len != 0)) try ast.ensureAll(merged);
    return .{ .src = src, .syntax = merged, .modules = ranges, .function_modules = try function_modules.toOwnedSlice(allocator), .loader = loader };
}

/// The loader of the lazy bodies of `index`'s modules, and the program's pointer to it: one slot per lazy body, in the order of the merged
/// ids of their root statements.
fn attachLoader(allocator: std.mem.Allocator, index: *interfaces.Index, src: source.Source, merged: *ast.Program, ranges: []const Range) BuildError!*lazy_loader.Loader {
    var total: usize = 0;
    for (index.units) |unit| total += if (unit.lazy) |lazy| lazy.declarations.bodies.len else 0;
    const slots = try allocator.alloc(lazy_loader.Slot, total);
    const bases = try allocator.alloc(lazy_loader.Base, ranges.len);
    var next: u32 = 0;
    for (index.units, ranges, bases, 0..) |unit, range, *base, module| {
        base.* = .{
            .node = range.node_start,
            .statement = range.statement_start,
            .node_count = range.node_end - range.node_start,
            .statement_count = range.statement_end - range.statement_start,
            .first_slot = next,
            .end_slot = next,
        };
        const lazy = unit.lazy orelse continue;
        for (lazy.declarations.bodies, 0..) |body, position| {
            const root = @backingInt(unit.syntax.functions[body.function].body) + range.statement_start;
            slots[next] = .{ .root = @intCast(root), .module = @intCast(module), .body = @intCast(position) };
            next += 1;
        }
        base.end_slot = next;
        std.mem.sort(lazy_loader.Slot, slots[base.first_slot..base.end_slot], {}, struct {
            fn lessThan(_: void, left: lazy_loader.Slot, right: lazy_loader.Slot) bool {
                return left.root < right.root;
            }
        }.lessThan);
    }
    const loader = try allocator.create(lazy_loader.Loader);
    loader.* = .{ .arena = allocator, .index = index, .src = src, .tables = .{ .nodes = merged.nodes.items, .statements = merged.statements.items }, .bases = bases, .slots = slots };
    merged.facts.loader = loader.attach();
    return loader;
}
