//! Test-only source guard for ownership refusal construction and emission.
//! Zig's typed Refusal API requires a rule at ordinary ownership call sites.
//! This guard also checks generic diagnostic APIs and D1's predicate layers.
const std = @import("std");
const rules = @import("ownership_rules.zig");
const Ast = std.zig.Ast;
const Node = Ast.Node.Index;

/// An audited ordinary typing/rendering expression sharing an ownership code.
/// Tokens and occurrence counts are pinned so a new site cannot reuse a waiver.
pub const Exception = struct { path: []const u8, expression: []const u8, count: usize = 1 };

const Alias = struct { name: []const u8, value: Node, scope: Node, start: u32 };
const Range = struct { node: Node, start: u32, end: u32 };
const Index = struct { aliases: []const Alias, functions: []const Range };
const Codes = std.ArrayList([]const u8);
const Allowances = struct { entries: []const Exception, seen: []usize };
const Imports = struct { allocator: std.mem.Allocator, values: std.StringHashMapUnmanaged([]const []const u8) = .empty };
const Layer = enum { frontend, core };
const Decision = struct { condition: []const u8, arm: []const u8, kind: enum { branch, case } };
const Choice = struct { value: union(enum) { code: []const u8, rule: ?rules.Rule }, decisions: []const Decision };
const Selection = struct { mode: enum { code, rule }, decisions: []const Decision = &.{}, depth: usize = 0 };

const Scan = struct {
    allocator: std.mem.Allocator,
    tree: Ast,
    path: []const u8,
    index: Index,
    allowances: Allowances,
    report: *std.ArrayList(u8),
    imports: *Imports,

    fn scope(self: *const Scan, node: Node) Node {
        const start = self.tree.tokenStart(self.tree.firstToken(node));
        for (self.index.functions) |function| {
            if (function.start <= start and start <= function.end) return function.node;
        }
        return .root;
    }

    fn alias(self: *const Scan, node: Node) ?Node {
        const name = self.tree.tokenSlice(self.tree.nodeMainToken(node));
        const at = self.tree.tokenStart(self.tree.firstToken(node));
        const current = self.scope(node);
        var found: ?Alias = null;
        for (self.index.aliases) |item| {
            if (item.start >= at or (item.scope != .root and item.scope != current)) continue;
            if (!std.mem.eql(u8, name, item.name)) continue;
            if (found == null) {
                found = item;
                continue;
            }
            const local_priority = found.?.scope == .root and item.scope == current;
            const newer = found.?.scope == item.scope and found.?.start < item.start;
            if (local_priority or newer) found = item;
        }
        return if (found) |item| item.value else null;
    }

    fn diagnosticModule(self: *const Scan, node: Node, depth: usize) bool {
        if (depth > 16) return false;
        const text = self.tree.getNodeSource(node);
        if (std.mem.eql(u8, text, "diagnostic")) return true;
        if (self.tree.nodeTag(node) == .identifier) {
            const value = self.alias(node) orelse return false;
            return self.diagnosticModule(value, depth + 1);
        }
        if (self.tree.nodeTag(node) == .field_access) {
            return std.mem.eql(u8, self.tree.tokenSlice(self.tree.nodeData(node).node_and_token[1]), "diagnostic");
        }
        return std.mem.startsWith(u8, text, "@import(") and std.mem.endsWith(u8, text, "diagnostic.zig\")");
    }

    fn addCode(self: *const Scan, out: *Codes, code: []const u8) !void {
        if (rules.rulesFor(code).len == 0) return;
        for (out.items) |previous| if (std.mem.eql(u8, previous, code)) return;
        for (rules.entries) |entry| {
            if (std.mem.eql(u8, entry.code, code)) return out.append(self.allocator, entry.code);
        }
    }

    fn codes(self: *const Scan, out: *Codes, node: Node, depth: usize) std.mem.Allocator.Error!void {
        if (depth > 16) return;
        switch (self.tree.nodeTag(node)) {
            .string_literal => {
                const text = self.tree.getNodeSource(node);
                if (text.len > 2) try self.addCode(out, text[1 .. text.len - 1]);
                return;
            },
            .identifier => {
                if (self.alias(node)) |value| try self.codes(out, value, depth + 1);
                return;
            },
            .field_access => {
                const data = self.tree.nodeData(node).node_and_token;
                const name = self.tree.tokenSlice(data[1]);
                if (self.diagnosticModule(data[0], 0)) {
                    try self.moduleCodes(out, "diagnostic.zig", name, depth + 1);
                } else if (std.mem.eql(u8, name, "code")) {
                    const value = self.resolved(data[0], 0);
                    if (self.field(value, "code")) |code| try self.codes(out, code, depth + 1);
                } else try self.importedCodes(out, data[0], name, depth + 1);
                return;
            },
            else => {},
        }
        // Only value-producing code selections and descriptors can carry codes.
        // A message builder, span expression or block is not code dataflow.
        if (self.field(node, "code")) |value| return self.codes(out, value, depth + 1);
        if (self.tree.fullIf(node)) |branch| {
            try self.codes(out, branch.ast.then_expr, depth + 1);
            if (branch.ast.else_expr.unwrap()) |other| try self.codes(out, other, depth + 1);
        }
        if (self.tree.fullSwitch(node)) |selection| {
            for (selection.ast.cases) |case| {
                const branch = self.tree.fullSwitchCase(case).?;
                try self.codes(out, branch.ast.target_expr, depth + 1);
            }
        }
    }

    fn importedCodes(self: *const Scan, out: *Codes, module: Node, name: []const u8, depth: usize) std.mem.Allocator.Error!void {
        if (depth > 16) return;
        const value = self.resolved(module, 0);
        if (!std.mem.eql(u8, self.tree.tokenSlice(self.tree.nodeMainToken(value)), "@import")) return;
        var buffer: [2]Node = undefined;
        const params = self.tree.builtinCallParams(&buffer, value) orelse return;
        if (params.len != 1 or self.tree.nodeTag(params[0]) != .string_literal) return;
        const spelling = self.tree.getNodeSource(params[0]);
        const imported = spelling[1 .. spelling.len - 1];
        if (!std.mem.endsWith(u8, imported, ".zig")) return;
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();
        const a = arena.allocator();
        const relative = try std.fs.path.join(a, &.{ std.fs.path.dirname(self.path) orelse "", imported });
        try self.moduleCodes(out, relative, name, depth + 1);
    }

    fn moduleCodes(self: *const Scan, out: *Codes, relative: []const u8, name: []const u8, depth: usize) std.mem.Allocator.Error!void {
        if (depth > 16) return;
        const cache = self.imports;
        const key = try std.fmt.allocPrint(cache.allocator, "{s}:{s}", .{ relative, name });
        if (cache.values.get(key)) |cached| {
            for (cached) |code| try self.addCode(out, code);
            return;
        }
        // An in-progress lookup is empty, closing an import-alias cycle.
        try cache.values.put(cache.allocator, key, &.{});
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();
        const a = arena.allocator();
        const path = try std.fs.path.join(a, &.{ "src", relative });
        const bytes = std.Io.Dir.cwd().readFileAlloc(std.testing.io, path, a, .limited(4 * 1024 * 1024)) catch return;
        const terminated = try a.dupeSentinel(u8, bytes, 0);
        var tree = try Ast.parse(a, terminated, .{ .mode = .zig });
        defer tree.deinit(a);
        const foreign: Scan = .{
            .allocator = self.allocator,
            .tree = tree,
            .path = relative,
            .index = try makeIndex(a, tree),
            .allowances = self.allowances,
            .report = self.report,
            .imports = cache,
        };
        for (foreign.index.aliases) |item| {
            if (item.scope == .root and std.mem.eql(u8, item.name, name)) {
                var found: Codes = .empty;
                defer found.deinit(self.allocator);
                try foreign.codes(&found, item.value, depth + 1);
                try cache.values.put(cache.allocator, key, try cache.allocator.dupe([]const u8, found.items));
                for (found.items) |code| try self.addCode(out, code);
                return;
            }
        }
    }

    fn resolved(self: *const Scan, node: Node, depth: usize) Node {
        if (depth > 16 or self.tree.nodeTag(node) != .identifier) return node;
        return if (self.alias(node)) |value| self.resolved(value, depth + 1) else node;
    }

    fn field(self: *const Scan, node: Node, name: []const u8) ?Node {
        var buffer: [2]Node = undefined;
        const init = self.tree.fullStructInit(&buffer, node) orelse return null;
        for (init.ast.fields) |value| {
            const first = self.tree.firstToken(value);
            if (first < 2) continue;
            if (std.mem.eql(u8, self.tree.tokenSlice(first - 2), name)) return value;
        }
        return null;
    }

    fn rule(self: *const Scan, node: Node) ?Node {
        if (self.field(node, "rule")) |value| return value;
        const provenance = self.field(node, "provenance") orelse return null;
        return self.field(self.resolved(provenance, 0), "rule");
    }

    fn labelled(self: *const Scan, node: Node) bool {
        const value = self.resolved(node, 0);
        if (self.tree.fullIf(value)) |branch| {
            const other = branch.ast.else_expr.unwrap() orelse return false;
            return self.labelled(branch.ast.then_expr) and self.labelled(other);
        }
        if (self.tree.fullSwitch(value)) |selection| {
            if (selection.ast.cases.len == 0) return false;
            for (selection.ast.cases) |case| {
                if (!self.labelled(self.tree.fullSwitchCase(case).?.ast.target_expr)) return false;
            }
            return true;
        }
        const selected = self.resolved(self.rule(value) orelse return false, 0);
        const first = self.tree.firstToken(selected);
        const last = self.tree.lastToken(selected);
        for (first..last + 1) |raw| {
            if (std.mem.eql(u8, self.tree.tokenSlice(@intCast(raw)), "null")) return false;
        }
        return true;
    }

    // Code and rule expressions can select matching branches independently.
    // Keep their conditions, so an `if`/`switch` pair is not a cross product of
    // values that cannot occur together. Messages are never traversed here.
    fn choices(self: *const Scan, a: std.mem.Allocator, out: *std.ArrayList(Choice), node: Node, selection: Selection) std.mem.Allocator.Error!void {
        if (selection.depth > 16) return;
        const value = self.resolved(node, 0);
        var next = selection;
        next.depth += 1;
        if (self.tree.fullIf(value)) |branch| {
            next.decisions = try self.decisions(a, selection.decisions, branch.ast.cond_expr, "then", .branch);
            try self.choices(a, out, branch.ast.then_expr, next);
            if (branch.ast.else_expr.unwrap()) |other| {
                next.decisions = try self.decisions(a, selection.decisions, branch.ast.cond_expr, "else", .branch);
                try self.choices(a, out, other, next);
            }
            return;
        }
        if (self.tree.fullSwitch(value)) |switched| {
            for (switched.ast.cases) |case| {
                const branch = self.tree.fullSwitchCase(case).?;
                const arm = if (branch.ast.values.len == 0) "else" else try self.caseValues(a, branch.ast.values);
                next.decisions = try self.decisions(a, selection.decisions, switched.ast.condition, arm, .case);
                try self.choices(a, out, branch.ast.target_expr, next);
            }
            return;
        }
        if (selection.mode == .rule) {
            const literal = if (self.tree.nodeTag(value) == .enum_literal)
                std.meta.stringToEnum(rules.Rule, self.tree.tokenSlice(self.tree.lastToken(value)))
            else
                null;
            return out.append(a, .{ .value = .{ .rule = literal }, .decisions = selection.decisions });
        }
        var found: Codes = .empty;
        defer found.deinit(self.allocator);
        try self.codes(&found, value, 0);
        for (found.items) |code| try out.append(a, .{ .value = .{ .code = code }, .decisions = selection.decisions });
    }

    fn decisions(self: *const Scan, a: std.mem.Allocator, previous: []const Decision, condition: Node, arm: []const u8, kind: @FieldType(Decision, "kind")) std.mem.Allocator.Error![]const Decision {
        const result = try a.alloc(Decision, previous.len + 1);
        @memcpy(result[0..previous.len], previous);
        result[previous.len] = .{ .condition = try normalize(a, self.tree.getNodeSource(self.resolved(condition, 0))), .arm = arm, .kind = kind };
        return result;
    }

    fn caseValues(self: *const Scan, a: std.mem.Allocator, values: []const Node) std.mem.Allocator.Error![]const u8 {
        var result: std.ArrayList(u8) = .empty;
        for (values) |value| {
            try result.appendSlice(a, try normalize(a, self.tree.getNodeSource(value)));
            try result.append(a, ',');
        }
        return result.toOwnedSlice(a);
    }

    // The only frontend W2 predicates compare written modes. Ownership of
    // the operand and whether its position transfers storage remain in Core.
    fn spellingMarkerSite(self: *const Scan, node: Node, code: []const u8, selected_rule: rules.Rule) bool {
        if (selected_rule != .W2 or !std.mem.eql(u8, code, "E_OWN_MARKER")) return false;
        var buffer: [1]Node = undefined;
        const function = self.tree.fullFnProto(&buffer, self.scope(node)) orelse return false;
        const name = self.tree.tokenSlice(function.name_token orelse return false);
        if (std.mem.eql(u8, self.path, "sema_calls.zig"))
            return std.mem.eql(u8, name, "checkMutationMarkers") or std.mem.eql(u8, name, "checkTakingModeMarkers");
        if (std.mem.eql(u8, self.path, "sema_receiver_marker.zig")) return std.mem.eql(u8, name, "require");
        return std.mem.eql(u8, self.path, "sema_collections.zig") and std.mem.eql(u8, name, "checkWriterFunction");
    }

    // These frontend K1 sites admit argument shapes and lexical lenders.
    // Actual conflicts with an active group loan are decided only in Core.
    fn taskArgumentSite(self: *const Scan, node: Node, code: []const u8, selected_rule: rules.Rule) bool {
        if (selected_rule != .K1 or !std.mem.eql(u8, code, "E_TASK_LOAN")) return false;
        if (!std.mem.eql(u8, self.path, "sema_tasks.zig")) return false;
        var buffer: [1]Node = undefined;
        const function = self.tree.fullFnProto(&buffer, self.scope(node)) orelse return false;
        const name = self.tree.tokenSlice(function.name_token orelse return false);
        return std.mem.eql(u8, name, "checkMapArguments") or std.mem.eql(u8, name, "submit") or
            std.mem.eql(u8, name, "checkLentOwners") or std.mem.eql(u8, name, "refuseBorrowedArguments");
    }

    // P4 is refused twice: Core refuses a local or a return that stores an open file, and the front end refuses the record, list,
    // variant or callback type that stores one where it is declared (`record_layouts.zig`), whether or not anything uses it.
    fn declaredFileSite(self: *const Scan, node: Node, code: []const u8, selected_rule: rules.Rule) bool {
        if (selected_rule != .P4 or !std.mem.eql(u8, code, "E_WITH_RESOURCE")) return false;
        if (!std.mem.eql(u8, self.path, "record_layouts.zig")) return false;
        var buffer: [1]Node = undefined;
        const function = self.tree.fullFnProto(&buffer, self.scope(node)) orelse return false;
        return std.mem.eql(u8, self.tree.tokenSlice(function.name_token orelse return false), "refuseFile");
    }

    fn checkPair(self: *Scan, node: Node, code: []const u8, selected_rule: rules.Rule) !void {
        if (!rules.valid(.{ .code = code, .rule = selected_rule })) return self.issue(node, code, "rule is not registered for this code");
        const actual = sourceLayer(self.path);
        const expected = predicateLayer(code, selected_rule);
        if (actual == expected or self.spellingMarkerSite(node, code, selected_rule) or self.taskArgumentSite(node, code, selected_rule) or
            self.declaredFileSite(node, code, selected_rule)) return;
        const reason = try std.fmt.allocPrint(self.allocator, "ownership rule {s} belongs to {s}; {s} check cannot enforce it", .{
            @tagName(selected_rule), @tagName(expected), @tagName(actual),
        });
        defer self.allocator.free(reason);
        try self.issue(node, code, reason);
    }

    fn checkChoices(self: *Scan, node: Node, code: Node, selected_rule: Node) !void {
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();
        const a = arena.allocator();
        var codes_selected: std.ArrayList(Choice) = .empty;
        var rules_selected: std.ArrayList(Choice) = .empty;
        try self.choices(a, &codes_selected, code, .{ .mode = .code });
        try self.choices(a, &rules_selected, selected_rule, .{ .mode = .rule });
        for (codes_selected.items) |left| {
            for (rules_selected.items) |right| {
                if (!compatible(left.decisions, right.decisions)) continue;
                if (right.value.rule) |selected| {
                    try self.checkPair(node, left.value.code, selected);
                } else {
                    // A code with one predicate layer can forward a dynamic rule
                    // within that domain. A shared code must instead forward the
                    // complete Refusal selected at its actual decision site.
                    if (mixedLayers(left.value.code)) {
                        try self.issue(node, left.value.code, "mixed-layer code requires an explicit rule descriptor at its decision site; forward the complete Refusal through helpers");
                        continue;
                    }
                    for (rules.rulesFor(left.value.code)) |selected| try self.checkPair(node, left.value.code, selected);
                }
            }
        }
    }

    fn functionName(self: *const Scan, node: Node, depth: usize) []const u8 {
        if (depth > 16) return "";
        switch (self.tree.nodeTag(node)) {
            .field_access => return self.tree.tokenSlice(self.tree.nodeData(node).node_and_token[1]),
            .identifier => {
                if (self.alias(node)) |value| return self.functionName(value, depth + 1);
                return self.tree.tokenSlice(self.tree.nodeMainToken(node));
            },
            else => return "",
        }
    }

    fn waived(self: *Scan, node: Node) !bool {
        const normalized = try normalize(self.allocator, self.tree.getNodeSource(node));
        defer self.allocator.free(normalized);
        for (self.allowances.entries, 0..) |item, i| {
            if (!std.mem.eql(u8, item.path, self.path)) continue;
            const expected = try normalize(self.allocator, item.expression);
            defer self.allocator.free(expected);
            if (!std.mem.eql(u8, expected, normalized)) continue;
            self.allowances.seen[i] += 1;
            return self.allowances.seen[i] <= item.count;
        }
        return false;
    }

    fn issue(self: *Scan, node: Node, code: []const u8, reason: []const u8) !void {
        const location = self.tree.tokenLocation(0, self.tree.firstToken(node));
        try self.report.print(self.allocator, "{s}:{d}: {s}: {s}\n", .{ self.path, location.line + 1, code, reason });
    }

    fn checkInit(self: *Scan, node: Node) !void {
        const code = self.field(node, "code") orelse return;
        // Index rows and unrelated code tables are not diagnostic construction.
        if (self.field(node, "rules") != null) return;
        var values: Codes = .empty;
        defer values.deinit(self.allocator);
        try self.codes(&values, code, 0);
        if (values.items.len == 0) return;
        if (!self.labelled(node)) {
            if (try self.waived(node)) return;
            try self.issue(node, values.items[0], "ownership construction has no explicit rule");
            return;
        }
        try self.checkChoices(node, code, self.rule(node).?);
    }

    fn checkCall(self: *Scan, node: Node) !void {
        var buffer: [1]Node = undefined;
        const call = self.tree.fullCall(&buffer, node) orelse return;
        const name = self.functionName(call.ast.fn_expr, 0);
        if (!emitter(name)) return;
        var values: Codes = .empty;
        defer values.deinit(self.allocator);
        var labelled_argument = false;
        for (call.ast.params) |param| {
            try self.codes(&values, param, 0);
            labelled_argument = labelled_argument or self.labelled(param);
        }
        if (rendering(name)) try self.renderedCodes(&values, call.ast.params);
        if (values.items.len == 0 or labelled_argument) return;
        if (try self.waived(node)) return;
        try self.issue(node, values.items[0], "ownership emission uses a code without a rule descriptor");
    }

    fn renderedCodes(self: *Scan, out: *Codes, params: []const Node) !void {
        for (params) |param| {
            if (self.tree.nodeTag(param) != .string_literal) continue;
            const text = self.tree.getNodeSource(param);
            for (rules.entries) |entry| {
                if (std.mem.indexOf(u8, text, entry.code) != null) try self.addCode(out, entry.code);
            }
        }
    }
};

fn compatible(left: []const Decision, right: []const Decision) bool {
    for (left) |a| for (right) |b| {
        if (a.kind == b.kind and std.mem.eql(u8, a.condition, b.condition) and !std.mem.eql(u8, a.arm, b.arm)) return false;
    };
    return true;
}

// Frontend adapters remain frontend checks even though the native driver owns
// their source files. New typed-program spelling helpers live outside core/.
fn sourceLayer(path: []const u8) Layer {
    if (std.mem.eql(u8, path, "core/frontend.zig") or std.mem.eql(u8, path, "core/frontend_reuse.zig")) return .frontend;
    return if (std.mem.startsWith(u8, path, "core/")) .core else .frontend;
}

// D1 assigns predicates, not just diagnostic families. R7 and M4 have distinct
// codes for their frontend spelling/binding side; X2 separates place shape from
// the Core loan and writable-owner checks in the same way.
fn predicateLayer(code: []const u8, rule: rules.Rule) Layer {
    return switch (rule) {
        .T1, .T2, .T3, .T4, .B1, .M2, .M3, .W3, .V6, .K2, .K3, .L1, .C2 => .frontend,
        .K1 => if (std.mem.eql(u8, code, "E_TASK_LOAN")) .core else .frontend,
        .M4 => if (std.mem.eql(u8, code, "E_VALUE_TEMPORARY_WRITE")) .frontend else .core,
        .R7 => if (std.mem.eql(u8, code, "E_VALUE_BINDING_WRITE")) .frontend else .core,
        .X2 => if (std.mem.eql(u8, code, "E_MATCH_MUT")) .frontend else .core,
        else => .core,
    };
}

fn mixedLayers(code: []const u8) bool {
    // W2 spelling sites are a narrower frontend predicate sharing the Core
    // marker code. Opaque rules must still forward a complete decision.
    if (std.mem.eql(u8, code, "E_OWN_MARKER") or std.mem.eql(u8, code, "E_TASK_LOAN") or std.mem.eql(u8, code, "E_WITH_RESOURCE")) return true;
    var first: ?Layer = null;
    for (rules.rulesFor(code)) |selected| {
        const layer = predicateLayer(code, selected);
        if (first) |previous| {
            if (previous != layer) return true;
        } else first = layer;
    }
    return false;
}

fn rendering(name: []const u8) bool {
    return std.mem.eql(u8, name, "print") or std.mem.eql(u8, name, "allocPrint") or std.mem.eql(u8, name, "writeAll");
}

fn emitter(name: []const u8) bool {
    return std.mem.startsWith(u8, name, "fail") or std.mem.startsWith(u8, name, "reject") or
        std.mem.startsWith(u8, name, "refuse") or std.mem.startsWith(u8, name, "checkOwnership") or
        std.mem.eql(u8, name, "ownership") or rendering(name);
}

fn makeIndex(allocator: std.mem.Allocator, tree: Ast) !Index {
    var functions: std.ArrayList(Range) = .empty;
    var aliases: std.ArrayList(Alias) = .empty;
    for (0..tree.nodes.len) |raw| {
        const node: Node = @fromBackingInt(@intCast(raw));
        if (tree.nodeTag(node) != .fn_decl) continue;
        try functions.append(allocator, .{ .node = node, .start = tree.tokenStart(tree.firstToken(node)), .end = tree.tokenStart(tree.lastToken(node)) });
    }
    for (0..tree.nodes.len) |raw| {
        const node: Node = @fromBackingInt(@intCast(raw));
        var name: []const u8 = undefined;
        var value: Node = undefined;
        if (tree.fullVarDecl(node)) |declaration| {
            value = declaration.ast.init_node.unwrap() orelse continue;
            name = tree.tokenSlice(declaration.ast.mut_token + 1);
        } else if (tree.nodeTag(node) == .assign) {
            const data = tree.nodeData(node).node_and_node;
            if (tree.nodeTag(data[0]) != .identifier) continue;
            name = tree.tokenSlice(tree.nodeMainToken(data[0]));
            value = data[1];
        } else continue;
        const start = tree.tokenStart(tree.firstToken(node));
        var scope: Node = .root;
        for (functions.items) |function| {
            if (function.start <= start and start <= function.end) {
                scope = function.node;
                break;
            }
        }
        try aliases.append(allocator, .{ .name = name, .value = value, .scope = scope, .start = start });
    }
    return .{ .aliases = try aliases.toOwnedSlice(allocator), .functions = try functions.toOwnedSlice(allocator) };
}

/// Remove layout and comments while retaining token boundaries and spelling.
pub fn normalize(allocator: std.mem.Allocator, bytes: []const u8) std.mem.Allocator.Error![]u8 {
    const terminated = try allocator.dupeSentinel(u8, bytes, 0);
    defer allocator.free(terminated);
    var tokens = std.zig.Tokenizer.init(terminated);
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);
    while (true) {
        const token = tokens.next();
        if (token.tag == .eof) break;
        try out.appendSlice(allocator, terminated[token.loc.start..token.loc.end]);
        try out.append(allocator, 0);
    }
    return out.toOwnedSlice(allocator);
}

/// Append findings for one Zig source; `seen` tracks exact audited exceptions.
pub fn inspect(allocator: std.mem.Allocator, path: []const u8, bytes: []const u8, exceptions: []const Exception, seen: []usize, report: *std.ArrayList(u8)) std.mem.Allocator.Error!void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const terminated = try a.dupeSentinel(u8, bytes, 0);
    var tree = try Ast.parse(a, terminated, .{ .mode = .zig });
    defer tree.deinit(a);
    if (tree.errors.len != 0) {
        try report.print(allocator, "{s}: source guard could not parse Zig source\n", .{path});
        return;
    }
    var imports: Imports = .{ .allocator = a };
    var scan: Scan = .{
        .allocator = allocator,
        .tree = tree,
        .path = path,
        .index = try makeIndex(a, tree),
        .allowances = .{ .entries = exceptions, .seen = seen },
        .report = report,
        .imports = &imports,
    };
    for (0..tree.nodes.len) |raw| {
        const node: Node = @fromBackingInt(@intCast(raw));
        try scan.checkInit(node);
        try scan.checkCall(node);
    }
}
