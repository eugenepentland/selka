//! What `mylang index-project` prints. The complete `navigation-v1` document
//! grows with every local and every edge — 36 MB for a 50k-line project — so
//! the default is a `navigation-summary-v1` overview whose size grows with the
//! module count only, and a `navigation-selection-v1` document publishes the
//! `navigation-v1` records one filter selects. `--full` still streams the
//! complete document byte for byte as the command always published it.
const std = @import("std");
const navigation = @import("navigation.zig");
const navigation_partial = @import("navigation_partial.zig");
const pc = @import("project_compile.zig");
const project = @import("project.zig");
const receipt = @import("source_receipt.zig");

/// JSON keys several documents share, so a rename touches one place.
const key_version = "version";
const key_checked = "checked";
const key_snapshot_sha256 = "snapshot_sha256";
const key_snapshot = "snapshot";
const key_symbols = "symbols";
const key_references = "references";
const key_omitted_modules = "omitted_modules";
const key_modules = "modules";

/// Which document one `index-project` run publishes.
pub const View = union(enum) {
    /// `navigation-summary-v1`: per-module declaration counts and the queries
    /// that drill down. The default.
    summary,
    /// `navigation-v1`: every symbol and reference (`--full`).
    full,
    /// `navigation-selection-v1`: the records one filter selects.
    selection: Selection,
};

/// Which records a selection keeps; every filter present must match.
pub const Selection = struct {
    /// `--module=NAME`: declarations of one module.
    module: ?[]const u8 = null,
    /// `--symbol=NAME`: one declaration and the members it owns, spelled
    /// `module::name`, `module.name` or a bare name that only one declaration carries.
    symbol: ?[]const u8 = null,
    /// `--kind=KIND`: one of `navigation.kinds`.
    kind: ?[]const u8 = null,
};

/// One `index-project` request: the view, and the entry path the summary's
/// drill-down queries repeat.
pub const Request = struct { view: View = .summary, entry: []const u8 = "" };

/// Whether a selection named anything. `ok` answers; `missing` and
/// `ambiguous` still publish a document that says why, and the command exits 2.
pub const Status = enum { ok, missing, ambiguous };

/// Navigation failures, plus a stdout that refused the document.
pub const Error = navigation.VisitError;

/// The tables one pass published, whichever path produced them.
const Published = struct {
    checked: bool,
    reference_scope: []const u8,
    snapshot: navigation.Snapshot,
    snapshot_sha256: []const u8,
    symbols: []const navigation.Symbol,
    references: []const navigation.Reference,
    /// Modules a lexical pass could not even lex; null on a merged compilation.
    omitted_modules: ?[]const []const u8 = null,
};

/// Publish the requested view of a merged compilation, checked or not. No view
/// holds every relationship row: the summary skips the walk, `--full` writes
/// each row as the walk produces it, and a selection keeps only the rows into or
/// out of what it selected, so memory stays near the check's own.
pub fn writeChecked(writer: *std.Io.Writer, allocator: std.mem.Allocator, compilation: *pc.Compilation, identity: receipt.Identity, request: Request) Error!Status {
    switch (request.view) {
        .full => {
            var full: FullDocument = .{ .json = .{ .writer = writer } };
            var facts = try navigation.collect(allocator, compilation, identity, .{ .edges = .{ .visit = full.visitor() } });
            defer facts.deinit();
            try full.json.endArray();
            try full.json.endObject();
            return .ok;
        },
        .summary => {
            var facts = try navigation.collect(allocator, compilation, identity, .{ .edges = .none });
            defer facts.deinit();
            try summary(writer, facts.arena.allocator(), tablesOf(&facts), request.entry);
            return .ok;
        },
        .selection => |selected| {
            var scratch = std.heap.ArenaAllocator.init(allocator);
            defer scratch.deinit();
            var keeping: Keeping = .{ .arena = scratch.allocator(), .selected = selected };
            var facts = try navigation.collect(allocator, compilation, identity, .{ .edges = .{ .visit = keeping.visitor() } });
            defer facts.deinit();
            return selection(writer, scratch.allocator(), tablesOf(&facts), selected, keeping.resolution);
        },
    }
}

/// The tables a merged compilation's pass published.
fn tablesOf(facts: *const navigation.Facts) Published {
    return .{
        .checked = facts.checked,
        .reference_scope = navigation.checked_reference_scope,
        .snapshot = facts.snapshot,
        .snapshot_sha256 = facts.snapshot_sha256,
        .symbols = facts.symbols,
        .references = facts.references,
    };
}

/// Streams `navigation-v1` field by field: the envelope and every symbol once
/// the declarations are known, then each row as the walk produces it, keeping
/// none. The bytes are exactly `std.json.Stringify.value(facts.document())`'s.
const FullDocument = struct {
    json: std.json.Stringify,

    fn visitor(self: *FullDocument) navigation.Visitor {
        return .{ .context = self, .declarations = declarations, .wants = every, .row = row };
    }

    fn every(_: *anyopaque, _: []const u8, _: []const u8) bool {
        return true;
    }

    fn declarations(context: *anyopaque, table: navigation.Table) navigation.VisitError!void {
        const self: *FullDocument = @ptrCast(@alignCast(context));
        try self.json.beginObject();
        try self.json.objectField(key_version);
        try self.json.write("navigation-v1");
        try self.json.objectField(key_checked);
        try self.json.write(table.checked);
        try self.json.objectField("reference_scope");
        try self.json.write(navigation.checked_reference_scope);
        try self.json.objectField(key_snapshot_sha256);
        try self.json.write(table.snapshot_sha256);
        try self.json.objectField(key_snapshot);
        try self.json.write(table.snapshot);
        try self.json.objectField(key_symbols);
        try self.json.write(table.symbols);
        try self.json.objectField(key_references);
        try self.json.beginArray();
    }

    fn row(context: *anyopaque, reference: navigation.Reference) navigation.VisitError!bool {
        const self: *FullDocument = @ptrCast(@alignCast(context));
        try self.json.write(reference);
        return false;
    }
};

/// Resolves a selection once the declarations are known, then keeps only the
/// rows into or out of a selected declaration.
const Keeping = struct {
    arena: std.mem.Allocator,
    selected: Selection,
    resolution: Resolution = .{},
    ids: std.StringHashMapUnmanaged(void) = .empty,

    fn visitor(self: *Keeping) navigation.Visitor {
        return .{ .context = self, .declarations = declarations, .wants = wants, .row = row };
    }

    fn declarations(context: *anyopaque, table: navigation.Table) navigation.VisitError!void {
        const self: *Keeping = @ptrCast(@alignCast(context));
        self.resolution = try resolveSelection(self.arena, table.symbols, table.snapshot.inputs, self.selected);
        if (self.resolution.status != .ok) return;
        for (table.symbols) |symbol| {
            if (selects(symbol, self.selected, self.resolution.symbol)) try self.ids.put(self.arena, symbol.id, {});
        }
    }

    fn wants(context: *anyopaque, from: []const u8, to: []const u8) bool {
        const self: *Keeping = @ptrCast(@alignCast(context));
        return self.ids.contains(from) or self.ids.contains(to);
    }

    fn row(_: *anyopaque, _: navigation.Reference) navigation.VisitError!bool {
        return true;
    }
};

/// Publish the requested view of the lexical candidates a project whose body
/// syntax failed still yields.
pub fn writeLexical(writer: *std.Io.Writer, allocator: std.mem.Allocator, loaded: *const project.Project, identity: receipt.Identity, request: Request) Error!Status {
    if (request.view == .full) {
        try navigation_partial.write(writer, allocator, loaded, identity);
        return .ok;
    }
    var recovered = try navigation_partial.candidates(allocator, loaded);
    defer recovered.deinit();
    const scratch = recovered.arena.allocator();
    const pinned = try navigation_partial.pin(scratch, loaded, identity);
    const lexical: Published = .{
        .checked = false,
        .reference_scope = navigation_partial.reference_scope,
        .snapshot = pinned.snapshot,
        .snapshot_sha256 = pinned.sha256,
        .symbols = recovered.symbols,
        .references = &.{},
        .omitted_modules = recovered.omitted_modules,
    };
    switch (request.view) {
        .selection => |selected| {
            const resolution = try resolveSelection(scratch, lexical.symbols, lexical.snapshot.inputs, selected);
            return selection(writer, scratch, lexical, selected, resolution);
        },
        // `--full` returned above.
        .summary, .full => {
            try summary(writer, scratch, lexical, request.entry);
            return .ok;
        },
    }
}

/// Per-kind declaration counts, in `navigation.kinds` order.
const Counts = [navigation.kinds.len]usize;

/// One summary row: a module's declaration counts.
const Row = struct { kinds: Counts = @splat(0), exported: usize = 0 };

/// The module part of a `module::name` identity.
fn moduleOf(id: []const u8) []const u8 {
    const at = std.mem.indexOf(u8, id, "::") orelse return id;
    return id[0..at];
}

fn kindIndex(kind: []const u8) ?usize {
    for (navigation.kinds, 0..) |known, index| {
        if (std.mem.eql(u8, known, kind)) return index;
    }
    return null;
}

/// `navigation-summary-v1`: the identity, the totals, one row per loaded module
/// with its declaration counts by kind, and the queries that publish the records
/// behind a row. Its size grows with the module count, never with locals or edges.
fn summary(writer: *std.Io.Writer, arena: std.mem.Allocator, published: Published, entry: []const u8) Error!void {
    const inputs = published.snapshot.inputs;
    const rows = try arena.alloc(Row, inputs.len);
    @memset(rows, .{});
    var by_module: std.StringHashMapUnmanaged(usize) = .empty;
    for (inputs, 0..) |input, index| try by_module.put(arena, input.module, index);
    var totals: Row = .{};
    for (published.symbols) |symbol| {
        const kind = kindIndex(symbol.kind) orelse continue;
        totals.kinds[kind] += 1;
        if (symbol.exported) totals.exported += 1;
        const row = by_module.get(moduleOf(symbol.id)) orelse continue;
        rows[row].kinds[kind] += 1;
        if (symbol.exported) rows[row].exported += 1;
    }
    var json: std.json.Stringify = .{ .writer = writer };
    try json.beginObject();
    try json.objectField(key_version);
    try json.write("navigation-summary-v1");
    try json.objectField(key_checked);
    try json.write(published.checked);
    try json.objectField(key_snapshot_sha256);
    try json.write(published.snapshot_sha256);
    try json.objectField("compiler");
    try json.write(published.snapshot.implementation);
    if (published.omitted_modules) |omitted| {
        try json.objectField(key_omitted_modules);
        try json.write(omitted);
    }
    try json.objectField("totals");
    try json.beginObject();
    try json.objectField(key_modules);
    try json.write(inputs.len);
    try json.objectField(key_symbols);
    try json.write(published.symbols.len);
    try writeRow(&json, totals);
    try json.endObject();
    try json.objectField(key_modules);
    try json.beginArray();
    for (inputs, rows) |input, row| {
        try json.beginObject();
        try json.objectField("module");
        try json.write(input.module);
        try json.objectField("path");
        try json.write(input.path);
        try writeRow(&json, row);
        try json.endObject();
    }
    try json.endArray();
    try json.objectField("queries");
    try json.beginObject();
    inline for (.{
        .{ "module", "mylang index-project {s} --module=MODULE" },
        .{ "symbol", "mylang index-project {s} --symbol=MODULE.NAME" },
        .{ "kind", "mylang index-project {s} --module=MODULE --kind=KIND" },
        .{ "context", "mylang context {s} --symbol=MODULE.NAME" },
        .{ "tests", "mylang tests-for {s} MODULE.NAME" },
        .{ "full", "mylang index-project {s} --full" },
    }) |query| {
        try json.objectField(query[0]);
        try json.write(try std.fmt.allocPrint(arena, query[1], .{entry}));
    }
    try json.endObject();
    try json.endObject();
}

/// The `exported` count and the non-zero per-kind counts of one row.
fn writeRow(json: *std.json.Stringify, row: Row) Error!void {
    try json.objectField("exported");
    try json.write(row.exported);
    try json.objectField("kinds");
    try json.beginObject();
    for (navigation.kinds, row.kinds) |kind, count| {
        if (count == 0) continue;
        try json.objectField(kind);
        try json.write(count);
    }
    try json.endObject();
}

/// What a selection's filters resolved to.
const Resolution = struct {
    status: Status = .ok,
    reason: ?[]const u8 = null,
    /// The identity `--symbol` resolved to.
    symbol: ?[]const u8 = null,
    candidates: []const []const u8 = &.{},
};

fn resolveSelection(arena: std.mem.Allocator, symbols: []const navigation.Symbol, inputs: []const receipt.Input, selected: Selection) error{OutOfMemory}!Resolution {
    if (selected.module) |name| {
        var known = false;
        for (inputs) |input| known = known or std.mem.eql(u8, input.module, name);
        if (!known) return .{ .status = .missing, .reason = "no loaded module has that name" };
    }
    const spelling = selected.symbol orelse return .{};
    const ids = try arena.alloc([]const u8, symbols.len);
    for (ids, symbols) |*id, symbol| id.* = symbol.id;
    switch (try navigation.resolveSpelling(arena, spelling, ids)) {
        .found => |id| return .{ .symbol = id },
        .ambiguous => |candidates| return .{ .status = .ambiguous, .reason = "several declarations match that dotted spelling; use a module-qualified name", .candidates = candidates },
        .missing => {},
    }
    // A bare name is accepted only when exactly one declaration carries it,
    // the rule `context --symbol` applies.
    var named: std.ArrayList([]const u8) = .empty;
    for (symbols) |symbol| {
        if (std.mem.eql(u8, symbol.name, spelling)) try named.append(arena, symbol.id);
    }
    if (named.items.len == 1) return .{ .symbol = named.items[0] };
    if (named.items.len > 1) return .{ .status = .ambiguous, .reason = "several declarations carry that unqualified name; use a module-qualified name", .candidates = named.items };
    return .{ .status = .missing, .reason = "no declaration in this project has that name" };
}

/// Whether one declaration passes every filter. `--symbol` keeps the
/// declaration and the members it owns: a type's fields and cases, a domain's
/// functions, a function's parameters and locals.
fn selects(symbol: navigation.Symbol, selected: Selection, resolved: ?[]const u8) bool {
    if (selected.module) |name| {
        if (!std.mem.startsWith(u8, symbol.id, name) or !std.mem.startsWith(u8, symbol.id[name.len..], "::")) return false;
    }
    if (selected.kind) |kind| {
        if (!std.mem.eql(u8, symbol.kind, kind)) return false;
    }
    if (resolved) |id| {
        if (!std.mem.startsWith(u8, symbol.id, id)) return false;
        if (symbol.id.len != id.len and symbol.id[id.len] != '.' and symbol.id[id.len] != '/') return false;
    }
    return true;
}

/// `navigation-selection-v1`: the `navigation-v1` symbols the filters select,
/// every reference into or out of one of them, and the snapshot rows of the
/// modules those records locate. `snapshot_sha256` still pins the whole project.
fn selection(writer: *std.Io.Writer, arena: std.mem.Allocator, published: Published, selected: Selection, resolution: Resolution) Error!Status {
    var symbols: std.ArrayList(navigation.Symbol) = .empty;
    var references: std.ArrayList(navigation.Reference) = .empty;
    var ids: std.StringHashMapUnmanaged(void) = .empty;
    var paths: std.StringHashMapUnmanaged(void) = .empty;
    if (resolution.status == .ok) {
        for (published.symbols) |symbol| {
            if (!selects(symbol, selected, resolution.symbol)) continue;
            try symbols.append(arena, symbol);
            try ids.put(arena, symbol.id, {});
            try paths.put(arena, symbol.location.path, {});
        }
        for (published.references) |reference| {
            if (!ids.contains(reference.from) and !ids.contains(reference.to)) continue;
            try references.append(arena, reference);
            try paths.put(arena, reference.location.path, {});
        }
    }
    var inputs: std.ArrayList(receipt.Input) = .empty;
    for (published.snapshot.inputs) |input| {
        if (paths.contains(input.path)) try inputs.append(arena, input);
    }
    var json: std.json.Stringify = .{ .writer = writer };
    try json.beginObject();
    try json.objectField(key_version);
    try json.write("navigation-selection-v1");
    try json.objectField("status");
    try json.write(@tagName(resolution.status));
    if (resolution.reason) |reason| {
        try json.objectField("reason");
        try json.write(reason);
    }
    try json.objectField(key_checked);
    try json.write(published.checked);
    try json.objectField("reference_scope");
    try json.write(published.reference_scope);
    try json.objectField("selection");
    try json.write(.{ .module = selected.module, .symbol = selected.symbol, .kind = selected.kind, .resolved = resolution.symbol });
    if (resolution.candidates.len != 0) {
        try json.objectField("candidates");
        try json.write(resolution.candidates);
    }
    try json.objectField(key_snapshot_sha256);
    try json.write(published.snapshot_sha256);
    try json.objectField(key_snapshot);
    try json.write(navigation.Snapshot{ .implementation = published.snapshot.implementation, .inputs = inputs.items });
    try json.objectField(key_symbols);
    try json.write(symbols.items);
    try json.objectField(key_references);
    try json.write(references.items);
    if (published.omitted_modules) |omitted| {
        try json.objectField(key_omitted_modules);
        try json.write(omitted);
    }
    try json.endObject();
    return resolution.status;
}
