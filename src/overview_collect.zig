//! Assemble the stable overview-v1 document from the shared release model.
const std = @import("std");
const ast = @import("ast.zig");
const interfaces = @import("interfaces.zig");
const loader = @import("release_project_load.zig");
const store = @import("overview_store.zig");
const types = @import("overview_types.zig");
const facts = @import("overview_facts.zig");
const baseline = @import("api_diff_baseline.zig");

/// Collect all visible facts; allocations belong to the caller's arena.
pub fn collect(a: std.mem.Allocator, model: *loader.Model, metadata: store.Store) (facts.Error || baseline.Error)!types.Document {
    var context = try facts.Context.compose(a, model);
    var walk: Walk = .{ .a = a, .model = model };
    for (model.selection.entries) |path| {
        for (model.modules) |id| if (std.mem.eql(u8, model.project.modules.items[id].src.path, path)) try walk.visit(id, 0);
    }
    for (model.modules) |id| if (!walk.seen.contains(id)) try walk.visit(id, 0);
    var modules: std.ArrayList(types.Module) = .empty;
    for (walk.order.items) |id| try modules.append(a, try moduleFacts(&context, metadata, id));
    const changes = try changeFacts(a, model, metadata);
    const history = try a.dupe(store.Release, metadata.history);
    std.mem.reverse(store.Release, history);
    return .{
        .title = std.fs.path.basename(model.root),
        .summary = summary(model),
        .counts = projectCounts(model, context.included, counts(modules.items, context.direct.count, changes, metadata)),
        .map = walk.map.items,
        .modules = modules.items,
        .releases = .{
            .since = if (history.len == 0) "init" else history[0].name,
            .changes = changes,
            .decisions = metadata.decisions,
            .history = history,
            .authority = try authorities(a, modules.items),
            .overview_path = model.options.overview,
        },
    };
}

const Walk = struct {
    a: std.mem.Allocator,
    model: *loader.Model,
    seen: std.AutoHashMapUnmanaged(usize, void) = .empty,
    order: std.ArrayList(usize) = .empty,
    map: std.ArrayList(types.MapEntry) = .empty,

    fn visit(self: *Walk, module: usize, depth: usize) std.mem.Allocator.Error!void {
        if (!selected(self.model, module)) return;
        const found = try self.seen.getOrPut(self.a, module);
        try self.map.append(self.a, .{
            .name = self.model.project.modules.items[module].name,
            .summary = firstSentence(moduleDoc(self.model, module)),
            .depth = depth,
            .repeated = found.found_existing,
        });
        if (found.found_existing) return;
        try self.order.append(self.a, module);
        for (self.model.project.modules.items[module].imports) |item| try self.visit(item.target, depth + 1);
    }
};

fn selected(model: *const loader.Model, id: usize) bool {
    for (model.modules) |module| if (module == id) return true;
    return false;
}

fn summary(model: *const loader.Model) []const u8 {
    for (model.modules) |module| {
        if (std.mem.eql(u8, model.project.modules.items[module].src.path, model.selection.entries[0])) return moduleDoc(model, module);
    }
    return "";
}

fn moduleDoc(model: *const loader.Model, id: usize) []const u8 {
    const doc = ast.docstringOf(model.index.units[id].syntax, ast.module_docstring_span) orelse return "";
    return doc.text;
}

/// A paragraph's first sentence, without introducing a date or other generated fact.
pub fn firstSentence(text: []const u8) []const u8 {
    const trimmed = std.mem.trim(u8, text, " \t\r\n");
    for (trimmed, 0..) |byte, i| {
        const punctuation = byte == '.' or byte == '!' or byte == '?';
        if (punctuation and (i + 1 == trimmed.len or std.ascii.isWhitespace(trimmed[i + 1]))) return trimmed[0 .. i + 1];
        if (byte == '\n' and i + 1 < trimmed.len and trimmed[i + 1] == '\n') return trimmed[0..i];
    }
    return trimmed;
}

fn moduleFacts(context: *facts.Context, metadata: store.Store, id: usize) !types.Module {
    const a = context.a;
    const model = context.model;
    const module = model.project.modules.items[id];
    const unit = model.index.units[id];
    var imports: std.ArrayList([]const u8) = .empty;
    for (module.imports) |item| try imports.append(a, model.project.modules.items[item.target].name);
    var importers: std.ArrayList([]const u8) = .empty;
    for (model.modules) |other| {
        for (model.project.modules.items[other].imports) |item| {
            if (item.target == id and !facts.contains(importers.items, model.project.modules.items[other].name)) try importers.append(a, model.project.modules.items[other].name);
        }
    }
    std.mem.sort([]const u8, importers.items, {}, facts.less);
    var order: std.ArrayList(usize) = .empty;
    var private: usize = 0;
    for (unit.symbols.items, 0..) |symbol, slot| {
        if (symbol.exported and symbol.owner == null) try order.append(a, slot);
        if (symbol.exported) continue;
        if (model.index.findFunction(unit, symbol.span)) |function| private += @intFromBool(!function.policy.constant);
    }
    std.mem.sort(usize, order.items, unit.symbols.items, sourceLess);
    var declarations: std.ArrayList(types.Declaration) = .empty;
    for (order.items) |slot| {
        const symbol = unit.symbols.items[slot];
        const identity: interfaces.Identity = .{ .module = id, .symbol = slot };
        const origin = context.origin(identity);
        const original = model.index.units[origin.module].symbols.items[origin.symbol];
        const doc = ast.docstringOf(model.index.units[origin.module].syntax, original.span);
        const details = try context.details(identity);
        const name = try facts.qualified(a, model, id, symbol.name);
        try declarations.append(a, .{
            .name = name,
            .kind = if (symbol.kind == .function and details.function == null) "constant" else @tagName(symbol.kind),
            .signature = try context.signature(identity),
            .doc = if (doc) |value| value.text else "",
            .details = details,
            .decisions = try decisionRefs(a, metadata, name, false),
        });
    }
    return .{ .name = module.name, .path = module.src.path, .doc = moduleDoc(model, id), .imports = imports.items, .importers = importers.items, .private_functions = private, .declarations = declarations.items };
}

fn sourceLess(symbols: []const interfaces.Symbol, left: usize, right: usize) bool {
    return symbols[left].span.start < symbols[right].span.start;
}

fn decisionRefs(a: std.mem.Allocator, metadata: store.Store, name: []const u8, pending_only: bool) ![]const usize {
    var result: std.ArrayList(usize) = .empty;
    for (metadata.decisions, 0..) |decision, index| {
        if (pending_only and !decision.pending) continue;
        if (facts.contains(decision.changes, name)) try result.append(a, index);
    }
    return result.items;
}

fn changeFacts(a: std.mem.Allocator, model: *loader.Model, metadata: store.Store) ![]const types.Change {
    const bytes = try @import("api_diff.zig").snapshotPublic(a, model.index, model.modules);
    const current = try baseline.parseReleaseBaseline(a, bytes);
    const diff = try baseline.compareEntries(a, metadata.previous orelse &.{}, current);
    var changes: std.ArrayList(types.Change) = .empty;
    for (diff.additive) |change| try changes.append(a, .{ .name = change.display, .kind = "added", .decisions = try decisionRefs(a, metadata, change.display, true) });
    for (diff.breaking) |change| try changes.append(a, .{
        .name = change.display,
        .kind = if (std.mem.eql(u8, change.detail, "removed declaration")) "removed" else "interface changed",
        .decisions = try decisionRefs(a, metadata, change.display, true),
    });
    std.mem.sort(types.Change, changes.items, {}, changeLess);
    return changes.items;
}

fn changeLess(_: void, left: types.Change, right: types.Change) bool {
    return std.mem.lessThan(u8, left.name, right.name);
}

fn counts(modules: []const types.Module, tests: usize, changes: []const types.Change, metadata: store.Store) types.Counts {
    var result: types.Counts = .{ .modules = modules.len, .tests = tests };
    for (modules) |module| for (module.declarations) |declaration| {
        result.types += @intFromBool(std.mem.eql(u8, declaration.kind, "type"));
        if (declaration.details.function) |function| {
            result.functions.total += 1;
            result.functions.with_examples += @intFromBool(function.examples != 0);
            result.functions.waived += @intFromBool(function.waiver != null);
        }
    };
    for (changes) |change| {
        if (std.mem.eql(u8, change.kind, "added")) result.changes.added += 1;
        if (std.mem.eql(u8, change.kind, "removed")) result.changes.removed += 1;
        if (std.mem.eql(u8, change.kind, "interface changed")) result.changes.changed += 1;
    }
    for (metadata.decisions) |decision| result.changes.decisions += @intFromBool(decision.pending);
    return result;
}

fn authorities(a: std.mem.Allocator, modules: []const types.Module) ![]const types.Authority {
    var groups: std.StringHashMapUnmanaged(std.ArrayList([]const u8)) = .empty;
    for (modules) |module| for (module.declarations) |declaration| {
        const function = declaration.details.function orelse continue;
        for (function.authority) |parameter| {
            const slot = try groups.getOrPut(a, parameter.type);
            if (!slot.found_existing) slot.value_ptr.* = .empty;
            if (!facts.contains(slot.value_ptr.items, declaration.name)) try slot.value_ptr.append(a, declaration.name);
        }
    };
    var out: std.ArrayList(types.Authority) = .empty;
    var iterator = groups.iterator();
    while (iterator.next()) |entry| {
        std.mem.sort([]const u8, entry.value_ptr.items, {}, facts.less);
        try out.append(a, .{ .type = entry.key_ptr.*, .functions = entry.value_ptr.items });
    }
    std.mem.sort(types.Authority, out.items, {}, authorityLess);
    return out.items;
}

fn authorityLess(_: void, left: types.Authority, right: types.Authority) bool {
    return std.mem.lessThan(u8, left.type, right.type);
}

fn projectCounts(model: *loader.Model, included: []const bool, public: types.Counts) types.Counts {
    var result = public;
    for (model.project.modules.items, 0..) |module, id| {
        if (!included[id]) continue;
        const syntax = model.index.units[id].syntax;
        for (syntax.functions) |function| {
            if (function.policy.constant) continue;
            if (ast.docstringOf(syntax, function.name)) |doc| result.examples += @import("docstring_examples.zig").count(doc.text);
            result.holes += @intFromBool(facts.hole(syntax, module.src, function));
        }
    }
    return result;
}
