//! The graph the `project-graph` kind returns (spec §17.2): what a loaded project says about which modules a program is made
//! of, in which orders, and the two program-wide flags the checker reads. The kind (`engine/kinds/project_graph.zig`) hands
//! back what this file builds while the front end computes the graph itself (shadow, G2a-G2f).
//!
//! Modules are named by their project-relative path (`src/lexer.selka`, or `@stdlib/...` for an embedded one), never by an index
//! or an absolute root (G-D11).
const std = @import("std");
const language = @import("selka");
const record = @import("engine/record.zig");
const graph_kind = @import("engine/kinds/project_graph.zig");

/// The first line of the payload.
pub const payload_magic = "selka-project-graph-v1";
/// The domain string of the parts' digests.
const domain = "selka-project-graph-part-v1";

/// The settings that decide how a graph loads and whether it loads at all: the budgets and the header flags. Written into
/// the query's argument, so a changed budget is another query.
pub fn settingsText(a: std.mem.Allocator, options: language.project.Options) std.mem.Allocator.Error![]const u8 {
    return std.fmt.allocPrint(a, "modules={d};imports={d};file={d};total={d};standard={d};legacy={d}", .{
        options.max_modules,
        options.max_imports,
        options.max_file_bytes,
        options.max_total_bytes,
        @intFromBool(options.standard.from_provider),
        @intFromBool(options.legacy_headers),
    });
}

/// The query argument for the graph of `entry` under `options`: the entry's module name, a zero byte, the settings.
pub fn argumentOf(a: std.mem.Allocator, entry: []const u8, options: language.project.Options) std.mem.Allocator.Error![]const u8 {
    return std.fmt.allocPrint(a, "{s}\x00{s}", .{ entry, try settingsText(a, options) });
}

fn digestOf(tag: []const u8, text: []const u8) [32]u8 {
    var state = std.crypto.hash.Blake3.init(.{});
    state.update(domain);
    state.update(tag);
    state.update("\x00");
    state.update(text);
    var out: [32]u8 = undefined;
    state.final(&out);
    return out;
}

fn byName(_: void, left: record.Part, right: record.Part) bool {
    return std.mem.lessThan(u8, left.name, right.name);
}

fn lessThan(_: void, left: []const u8, right: []const u8) bool {
    return std.mem.lessThan(u8, left, right);
}

/// The graph of `project`, loaded from `entry`, with everything allocated in `a`.
pub fn build(a: std.mem.Allocator, project: *const language.project.Project, entry: []const u8) std.mem.Allocator.Error!graph_kind.Answer {
    var paths: std.ArrayList([]const u8) = .empty;
    var modules: std.ArrayList(u8) = .empty;
    for (project.modules.items) |module| {
        try paths.append(a, module.src.path);
        try modules.print(a, "{s}\n", .{module.src.path});
    }
    var order: std.ArrayList(u8) = .empty;
    for (project.order.items) |id| try order.print(a, "{s}\n", .{project.modules.items[id].src.path});
    var std_result = false;
    for (project.modules.items) |module| std_result = std_result or std.mem.eql(u8, module.name, "std_result");
    const many = project.modules.items.len > 1 or (project.modules.items.len == 1 and project.modules.items[0].imports.len != 0);
    const flags = try std.fmt.allocPrint(a, "std_result={d};module_graph={d}\n", .{ @intFromBool(std_result), @intFromBool(many) });
    const sorted = try a.dupe([]const u8, paths.items);
    std.mem.sort([]const u8, sorted, {}, lessThan);
    const set = try std.mem.join(a, "\n", sorted);
    const payload = try std.fmt.allocPrint(a, "{s}\nentry {s}\nmodules\n{s}order\n{s}flags\n{s}", .{ payload_magic, entry, modules.items, order.items, flags });
    const parts = try a.dupe(record.Part, &.{
        .{ .name = "flags", .digest = digestOf("flags", flags) },
        .{ .name = "modules", .digest = digestOf("modules", modules.items) },
        .{ .name = "order", .digest = digestOf("order", order.items) },
        .{ .name = "set", .digest = digestOf("set", set) },
    });
    std.mem.sort(record.Part, parts, {}, byName);
    return .{ .payload = payload, .modules = paths.items, .parts = parts };
}
