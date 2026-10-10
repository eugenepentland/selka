//! Best-effort lexical declarations when complete body parsing fails.
const std = @import("std");
const project = @import("project.zig");
const frontend = @import("frontend_runtime.zig");
const component = @import("parser_component.zig");
const diagnostic = @import("diagnostic.zig");
const receipt = @import("source_receipt.zig");
const navigation = @import("navigation.zig");

/// Lexical recovery preserves component host failures separately from source errors.
pub const Error = navigation.Error || component.Error;

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
pub fn candidates(allocator: std.mem.Allocator, loaded: *const project.Project) Error!Candidates {
    var arena = std.heap.ArenaAllocator.init(allocator);
    errdefer arena.deinit();
    const scratch = arena.allocator();
    _ = try frontend.verify(scratch, loaded.frontendRuntime());
    var symbols: std.ArrayList(navigation.Symbol) = .empty;
    var omitted: std.ArrayList([]const u8) = .empty;
    for (loaded.modules.items) |module| {
        var sink: diagnostic.Sink = .{ .allocator = scratch };
        const tokens = frontend.lex(scratch, module.src, &sink, loaded.frontendRuntime()) catch |err| switch (err) {
            error.SourceError => {
                try omitted.append(scratch, module.src.path);
                continue;
            },
            else => |failure| return failure,
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

/// What a lexical pass publishes as `reference_scope`: nothing was resolved.
pub const reference_scope = "lexical top-level candidates only; body syntax failed; no resolved references or visibility claims";

/// The loaded-source snapshot a lexical answer is pinned to, and its digest.
pub const Pinned = struct { snapshot: navigation.Snapshot, sha256: []const u8 };

/// Pin a lexical answer to the complete loaded-source receipts, which are
/// retained even though no semantic edge is invented.
pub fn pin(arena: std.mem.Allocator, loaded: *const project.Project, identity: receipt.Identity) navigation.Error!Pinned {
    var source_snapshot = loaded.*;
    source_snapshot.problem = null;
    const snapshot: navigation.Snapshot = .{
        .implementation = try receipt.implementation(arena, identity),
        .inputs = try receipt.inputs(arena, &source_snapshot),
    };
    return .{ .snapshot = snapshot, .sha256 = try receipt.digest(arena, snapshot) };
}

/// Complete loaded-source receipts are retained, but no semantic edges are invented.
pub fn render(allocator: std.mem.Allocator, loaded: *const project.Project, identity: receipt.Identity) Error![]u8 {
    var out: std.Io.Writer.Allocating = .init(allocator);
    errdefer out.deinit();
    write(&out.writer, allocator, loaded, identity) catch |err| switch (err) {
        error.WriteFailed => return error.OutOfMemory,
        else => |other| return other,
    };
    return out.toOwnedSlice();
}

/// Stream the complete lexical `navigation-v1` document `render` returns.
pub fn write(writer: *std.Io.Writer, allocator: std.mem.Allocator, loaded: *const project.Project, identity: receipt.Identity) (Error || error{WriteFailed})!void {
    var recovered = try candidates(allocator, loaded);
    defer recovered.deinit();
    const pinned = try pin(recovered.arena.allocator(), loaded, identity);
    try std.json.Stringify.value(.{
        .version = "navigation-v1",
        .checked = false,
        .reference_scope = reference_scope,
        .snapshot_sha256 = pinned.sha256,
        .snapshot = pinned.snapshot,
        .symbols = recovered.symbols,
        .references = @as([]const navigation.Reference, &.{}),
        .omitted_modules = recovered.omitted_modules,
    }, .{}, writer);
}
