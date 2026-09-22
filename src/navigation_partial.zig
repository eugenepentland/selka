//! Best-effort lexical declarations when complete body parsing fails.
const std = @import("std");
const project = @import("project.zig");
const lexer = @import("lexer.zig");
const diagnostic = @import("diagnostic.zig");
const receipt = @import("source_receipt.zig");
const navigation = @import("navigation.zig");

/// The top-level names a lexer pass recovered after body parsing failed. The
/// bytes belong to the arena until `deinit`, and nothing here claims a resolved
/// relationship, a visibility or a signature.
pub const Candidates = struct {
    arena: std.heap.ArenaAllocator,
    symbols: []const navigation.Symbol,
    /// Modules whose bytes could not even be lexed, so they contributed nothing.
    omitted_modules: []const []const u8,

    /// Release the arena every slice above points into.
    pub fn deinit(self: *Candidates) void {
        self.arena.deinit();
    }
};

/// Recover top-level declaration candidates by lexing each loaded module. Only
/// indentation-zero `def`/`class`/`union`/`enum`/`domain` names and the managed
/// resource families are published; every candidate keeps the default
/// `lexical-only` analysis status, because no body was resolved.
pub fn candidates(allocator: std.mem.Allocator, loaded: *const project.Project) navigation.Error!Candidates {
    var arena = std.heap.ArenaAllocator.init(allocator);
    errdefer arena.deinit();
    const scratch = arena.allocator();
    var symbols: std.ArrayList(navigation.Symbol) = .empty;
    var omitted: std.ArrayList([]const u8) = .empty;
    for (loaded.modules.items) |module| {
        var sink: diagnostic.Sink = .{ .allocator = scratch };
        const tokens = lexer.lex(scratch, module.src.bytes, &sink) catch |err| {
            if (err == error.OutOfMemory) return error.OutOfMemory;
            try omitted.append(scratch, module.src.path);
            continue;
        };
        var depth: usize = 0;
        for (tokens, 0..) |token, i| {
            if (token.tag == .indent) depth += 1;
            if (token.tag == .dedent and depth > 0) depth -= 1;
            if (depth != 0 or i + 1 >= tokens.len or tokens[i + 1].tag != .ident) continue;
            const kind: []const u8 = switch (token.tag) {
                .kw_def => "function",
                .kw_class, .kw_union, .kw_enum, .kw_domain => "type",
                .ident => if (std.mem.eql(u8, module.src.text(token.span), "result") or std.mem.eql(u8, module.src.text(token.span), "buffer") or std.mem.eql(u8, module.src.text(token.span), "pool")) "type" else continue,
                else => continue,
            };
            if (symbols.items.len >= 50000) return error.NavigationLimit;
            const span = tokens[i + 1].span;
            const at = module.src.locate(span.start);
            const name = module.src.text(span);
            try symbols.append(scratch, .{
                .id = try std.fmt.allocPrint(scratch, "{s}::{s}", .{ module.name, name }),
                .name = name,
                .kind = kind,
                .location = .{ .path = at.path, .start = span.start, .end = span.end, .line = at.line, .column = at.column },
            });
        }
    }
    return .{ .arena = arena, .symbols = symbols.items, .omitted_modules = omitted.items };
}

/// Complete loaded-source receipts are retained, but no semantic edges are invented.
pub fn render(allocator: std.mem.Allocator, loaded: *const project.Project, identity: receipt.Identity) navigation.Error![]u8 {
    var recovered = try candidates(allocator, loaded);
    defer recovered.deinit();
    var source_snapshot = loaded.*;
    source_snapshot.problem = null;
    const scratch = recovered.arena.allocator();
    const snapshot: navigation.Snapshot = .{
        .implementation = try receipt.implementation(scratch, identity),
        .inputs = try receipt.inputs(scratch, &source_snapshot),
    };
    return std.json.Stringify.valueAlloc(allocator, .{
        .version = "navigation-v1",
        .checked = false,
        .reference_scope = "lexical top-level candidates only; body syntax failed; no resolved references or visibility claims",
        .snapshot_sha256 = try receipt.digest(scratch, snapshot),
        .snapshot = snapshot,
        .symbols = recovered.symbols,
        .references = @as([]const navigation.Reference, &.{}),
        .omitted_modules = recovered.omitted_modules,
    }, .{});
}
