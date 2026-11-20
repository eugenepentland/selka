//! Syntax-only declaration and direct-test facts for the overview.
const std = @import("std");
const ast = @import("ast.zig");
const interfaces = @import("interfaces.zig");
const files = @import("interface_files.zig");
const loader = @import("release_project_load.zig");
const types = @import("overview_types.zig");
const source = @import("source.zig");

/// Allocation or declaration-resolution failures, never body-check failures.
pub const Error = interfaces.ContractError;
/// Direct test callers keyed by the defining module::function identity.
pub const Direct = struct { callers: std.StringHashMapUnmanaged(std.ArrayList([]const u8)) = .empty, count: usize = 0 };
/// Cached canonical interface blocks and direct syntax edges for one rendering.
pub const Context = struct {
    a: std.mem.Allocator,
    model: *loader.Model,
    blocks: [][]const files.Declaration,
    direct: Direct,
    included: []const bool,

    /// Build shared declaration blocks and inspect only test bodies for call edges.
    pub fn compose(a: std.mem.Allocator, model: *loader.Model) Error!Context {
        const blocks = try a.alloc([]const files.Declaration, model.index.units.len);
        @memset(blocks, &.{});
        const included = try includedModules(a, model);
        return .{ .a = a, .model = model, .blocks = blocks, .direct = try directTests(a, model, included), .included = included };
    }

    /// Resolve a facade to its defining declaration without losing its public name.
    pub fn origin(self: *Context, id: interfaces.Identity) interfaces.Identity {
        var found = id;
        while (self.model.index.units[found.module].symbols.items[found.symbol].re_export) |next| found = next;
        return found;
    }

    /// Return the exact .api declaration block, including canonical contracts.
    pub fn signature(self: *Context, id: interfaces.Identity) Error![]const u8 {
        const resolved = self.origin(id);
        if (self.blocks[resolved.module].len == 0) self.blocks[resolved.module] = try files.declarations(self.a, try files.render(self.a, self.model.index, resolved.module));
        const symbol = self.model.index.units[resolved.module].symbols.items[resolved.symbol];
        for (self.blocks[resolved.module]) |block| if (std.mem.eql(u8, block.name, symbol.name)) return block.text;
        return error.InternalError;
    }

    /// Collect kind-specific facts using the declaration's original syntax.
    pub fn details(self: *Context, id: interfaces.Identity) Error!types.Details {
        const resolved = self.origin(id);
        const symbol = self.model.index.units[resolved.module].symbols.items[resolved.symbol];
        const syntax = self.model.index.units[resolved.module].syntax;
        const src = self.model.project.modules.items[resolved.module].src;
        var result: types.Details = .{};
        var clauses: std.ArrayList([]const u8) = .empty;
        for (ast.attributesOf(syntax, symbol.span)) |attribute| {
            if (attribute.kind.contract()) try clauses.append(self.a, try folded(self.a, src.text(attribute.span)));
        }
        result.contracts = clauses.items;
        if (self.model.index.findFunction(self.model.index.units[resolved.module], symbol.span)) |function| {
            if (!function.policy.constant) result.function = try self.functionFacts(resolved.module, function);
        }
        for (syntax.types.records) |record| {
            if (record.name.start == symbol.span.start) result.fields = try self.fields(resolved.module, record.fields);
        }
        for (syntax.types.variants) |variant| {
            if (variant.name.start != symbol.span.start) continue;
            const cases = try self.a.alloc(types.Case, variant.cases.len);
            for (variant.cases, cases) |item, *out| {
                out.* = .{ .name = src.text(item.name), .fields = try self.fields(resolved.module, item.fields) };
                if (item.payload) |payload| {
                    const field = try self.a.alloc(types.Field, 1);
                    field[0] = .{ .name = "value", .type = try folded(self.a, src.text(payload)), .default = null };
                    out.fields = field;
                }
            }
            result.cases = cases;
        }
        return result;
    }

    fn fields(self: *Context, module: usize, parameters: []const ast.Parameter) Error![]const types.Field {
        const src = self.model.project.modules.items[module].src;
        const syntax = self.model.index.units[module].syntax;
        const result = try self.a.alloc(types.Field, parameters.len);
        for (parameters, result) |parameter, *out| out.* = .{
            .name = src.text(parameter.name),
            .type = try folded(self.a, src.text(parameter.ty)),
            .default = if (parameter.default_value) |value| try folded(self.a, src.text(syntax.nodes.items[@backingInt(value)].span)) else null,
        };
        return result;
    }

    fn functionFacts(self: *Context, module: usize, function: ast.Function) Error!types.Function {
        const src = self.model.project.modules.items[module].src;
        const syntax = self.model.index.units[module].syntax;
        var writes: std.ArrayList([]const u8) = .empty;
        var authority: std.ArrayList(types.Parameter) = .empty;
        for (function.signature.parameters) |parameter| {
            if (parameter.mut) try writes.append(self.a, src.text(parameter.name));
            const ty = try self.model.index.contractTypeText(module, parameter.ty, function.signature.type_parameters);
            if (capability(ty)) |name| try authority.append(self.a, .{ .name = src.text(parameter.name), .type = name });
        }
        const name = try qualified(self.a, self.model, module, src.text(function.name));
        const tests = if (self.direct.callers.get(name)) |list| list.items else &.{};
        const doc = ast.docstringOf(syntax, function.name);
        return .{
            .writes = writes.items,
            .authority = authority.items,
            .tests = tests,
            .fails = if (function.signature.failure_type) |span| try folded(self.a, src.text(span)) else null,
            .hole = hole(syntax, src, function),
            .examples = if (doc) |value| @import("docstring_examples.zig").count(value.text) else 0,
            .waiver = try @import("lint.zig").waiverReason(self.a, src, syntax, function.name, "missing-example"),
        };
    }
};

/// Build a stable module::name spelling with no filesystem identity.
pub fn qualified(a: std.mem.Allocator, model: *const loader.Model, module: usize, name: []const u8) std.mem.Allocator.Error![]const u8 {
    return std.fmt.allocPrint(a, "{s}::{s}", .{ model.project.modules.items[module].name, name });
}

/// Fold insignificant declaration whitespace as the interface renderer does.
pub fn folded(a: std.mem.Allocator, text: []const u8) std.mem.Allocator.Error![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    try interfaces.appendFolded(&out, a, std.mem.trim(u8, text, " \t\r\n"));
    return out.items;
}

fn capability(ty: []const u8) ?[]const u8 {
    const names = [_][2][]const u8{
        .{ "filesystem_cap", "Filesystem" }, .{ "network_cap", "Network" },         .{ "clock_cap", "Clock" },
        .{ "random_cap", "Entropy" },        .{ "environment_cap", "Environment" }, .{ "stream_cap", "Stream" },
        .{ "host_cap", "Host" },             .{ "process_cap", "Process" },         .{ "input_cap", "Input" },
        .{ "stop_cap", "Stop" },             .{ "registers_cap", "Registers" },
    };
    for (names) |pair| if (std.mem.eql(u8, ty, pair[0]) or std.mem.eql(u8, ty, pair[1])) return pair[1];
    return null;
}

/// Whether the entire implementation is the syntactic todo[T]() hole.
pub fn hole(syntax: ast.Program, src: source.Source, function: ast.Function) bool {
    const body = syntax.statements.items[@backingInt(function.body)].data;
    if (body != .block or body.block.len != 1) return false;
    const statement = syntax.statements.items[@backingInt(body.block[0])].data;
    const value = switch (statement) {
        .ret => |id| id,
        .discard => |id| id,
        else => return false,
    };
    const expression = syntax.nodes.items[@backingInt(value)].data;
    if (expression != .call) return false;
    return expression.call.owner == null and std.mem.eql(u8, src.text(expression.call.name), "todo");
}

fn directTests(a: std.mem.Allocator, model: *loader.Model, included: []const bool) Error!Direct {
    var result: Direct = .{};
    for (model.project.modules.items, 0..) |module, module_id| {
        if (!included[module_id]) continue;
        const syntax = model.index.units[module_id].syntax;
        for (syntax.functions) |function| {
            if (!try isTest(model, module_id, function)) continue;
            result.count += 1;
            const caller = try qualified(a, model, module_id, module.src.text(function.name));
            const body = syntax.statements.items[@backingInt(function.body)].span;
            for (syntax.nodes.items) |node| {
                if (node.span.start < body.start or node.span.end > body.end) continue;
                if (node.data != .call) continue;
                const call = node.data.call;
                const spelled = module.src.text(if (call.owner) |owner| .{ .start = owner.start, .end = call.name.end } else call.name);
                const target = resolve(model, module_id, try callName(a, spelled)) orelse continue;
                const symbol = model.index.units[target.module].symbols.items[target.symbol];
                const callee = try qualified(a, model, target.module, symbol.name);
                const slot = try result.callers.getOrPut(a, callee);
                if (!slot.found_existing) slot.value_ptr.* = .empty;
                if (!contains(slot.value_ptr.items, caller)) try slot.value_ptr.append(a, caller);
            }
        }
    }
    var lists = result.callers.valueIterator();
    while (lists.next()) |list| std.mem.sort([]const u8, list.items, {}, less);
    return result;
}

/// Match the runner's source-level test discovery rule.
pub fn isTest(model: *loader.Model, module: usize, function: ast.Function) Error!bool {
    if (function.signature.type_parameters.len != 0 or function.policy.owner != null) return false;
    if (function.policy.c_abi or function.policy.host != null) return false;
    const syntax = model.index.units[module].syntax;
    const src = model.project.modules.items[module].src;
    if (ast.hasAttribute(syntax, function.name, .@"test")) return true;
    if (!std.mem.startsWith(u8, src.text(function.name), "test_")) return false;
    if (ast.isPublicDeclaration(syntax, function.name)) return true;
    if (function.signature.parameters.len != 0 or function.signature.failure_type != null) return false;
    const result = try model.index.contractTypeText(module, function.signature.return_type, &.{});
    return std.mem.eql(u8, result, "bool");
}

fn resolve(model: *loader.Model, from: usize, spelled: []const u8) ?interfaces.Identity {
    if (declared(model, from, spelled)) |found| return found;
    var cursor = spelled.len;
    while (std.mem.lastIndexOfScalar(u8, spelled[0..cursor], '.')) |dot| {
        cursor = dot;
        for (model.project.modules.items[from].imports) |item| {
            if (item.matches(spelled[0..dot])) return declared(model, item.target, spelled[dot + 1 ..]);
        }
    }
    return null;
}

fn declared(model: *loader.Model, module: usize, name: []const u8) ?interfaces.Identity {
    var id: interfaces.Identity = .{ .module = module, .symbol = model.index.units[module].names.get(name) orelse return null };
    while (model.index.units[id.module].symbols.items[id.symbol].re_export) |next| id = next;
    return if (model.index.units[id.module].symbols.items[id.symbol].kind == .function) id else null;
}

/// Whether a borrowed string list already contains a value.
pub fn contains(list: []const []const u8, name: []const u8) bool {
    for (list) |item| if (std.mem.eql(u8, item, name)) return true;
    return false;
}

/// Lexical ordering shared by imports and direct caller lists.
pub fn less(_: void, left: []const u8, right: []const u8) bool {
    return std.mem.lessThan(u8, left, right);
}

fn callName(a: std.mem.Allocator, spelled: []const u8) ![]const u8 {
    const end = std.mem.indexOfScalar(u8, spelled, '[') orelse spelled.len;
    var result: std.ArrayList(u8) = .empty;
    for (spelled[0..end]) |byte| if (!std.ascii.isWhitespace(byte)) {
        try result.append(a, byte);
    };
    return result.items;
}

fn includedModules(a: std.mem.Allocator, model: *loader.Model) ![]const bool {
    const included = try a.alloc(bool, model.project.modules.items.len);
    @memset(included, false);
    var work: std.ArrayList(usize) = .empty;
    for (model.selection.roots) |path| {
        for (model.project.modules.items, 0..) |module, id| if (std.mem.eql(u8, module.src.path, path)) try work.append(a, id);
    }
    while (work.pop()) |id| {
        if (included[id]) continue;
        const module = model.project.modules.items[id];
        if (std.mem.startsWith(u8, module.src.path, "@stdlib/")) continue;
        if (@import("release_project.zig").excluded(module.src.path, model.options.exclude)) continue;
        included[id] = true;
        for (module.imports) |item| try work.append(a, item.target);
    }
    return included;
}
