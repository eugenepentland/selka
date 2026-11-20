//! Strict release command arguments, with no implicit date or partial cut.
const std = @import("std");
const decisions = @import("release_decisions.zig");
/// Ordered gate steps; a subset always retains this order.
pub const Step = enum { format, check, lint, tests, docs, decisions, overview };
/// Requested release operation.
pub const Action = enum { check, init, draft, cut };
/// Whether `release init` leaves comments alone, lists adoptions or writes them.
pub const Adoption = enum { none, preview, write };
/// Caller-supplied command values and gate selection.
pub const Options = struct {
    action: Action,
    project: []const u8,
    name: ?[]const u8 = null,
    date: ?[]const u8 = null,
    steps: std.EnumSet(Step) = .full,
    json: bool = false,
    adoption: Adoption = .none,
};
/// Usage shared by help and rejected argument lists.
pub const usage =
    "usage: selka release check PROJECT [--step NAME,…] [--json]\n" ++
    "       selka release init PROJECT [--adopt-comments [--dry-run]]\n" ++
    "       selka release draft PROJECT --name SLUG [--date YYYY-MM-DD]\n" ++
    "       selka release cut PROJECT --name NAME\n";
/// Parse exactly one operation, rejecting irrelevant, duplicate and empty flags.
pub fn parse(args: []const []const u8) error{Usage}!Options {
    if (args.len < 2) return error.Usage;
    var result: Options = .{ .action = std.meta.stringToEnum(Action, args[0]) orelse return error.Usage, .project = args[1] };
    if (result.project.len == 0 or result.project[0] == '-') return error.Usage;
    var subset = false;
    var adopt = false;
    var dry_run = false;
    var i: usize = 2;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--json")) {
            if (result.action != .check or result.json) return error.Usage;
            result.json = true;
        } else if (std.mem.eql(u8, arg, "--adopt-comments")) {
            if (result.action != .init or adopt) return error.Usage;
            adopt = true;
        } else if (std.mem.eql(u8, arg, "--dry-run")) {
            if (result.action != .init or dry_run) return error.Usage;
            dry_run = true;
        } else if (value(args, &i, "--name")) |name| {
            if (result.action != .draft and result.action != .cut) return error.Usage;
            if (result.name != null or !validName(name)) return error.Usage;
            result.name = name;
        } else if (value(args, &i, "--date")) |date| {
            if (result.date != null or result.action != .draft or !decisions.validDate(date)) return error.Usage;
            result.date = date;
        } else if (value(args, &i, "--step")) |steps| {
            if (subset or result.action != .check) return error.Usage;
            subset = true;
            result.steps = .empty;
            var names = std.mem.splitScalar(u8, steps, ',');
            while (names.next()) |name| {
                const step = std.meta.stringToEnum(Step, name) orelse return error.Usage;
                if (result.steps.contains(step)) return error.Usage;
                result.steps.insert(step);
            }
        } else return error.Usage;
    }
    if ((result.action == .draft or result.action == .cut) and result.name == null) return error.Usage;
    if (dry_run and !adopt) return error.Usage;
    result.adoption = if (dry_run) .preview else if (adopt) .write else .none;
    return result;
}
fn value(args: []const []const u8, index: *usize, flag: []const u8) ?[]const u8 {
    const arg = args[index.*];
    if (std.mem.eql(u8, arg, flag)) {
        if (index.* + 1 >= args.len) return null;
        index.* += 1;
        return args[index.*];
    }
    if (arg.len > flag.len and std.mem.startsWith(u8, arg, flag) and arg[flag.len] == '=') return arg[flag.len + 1 ..];
    return null;
}
/// A release/draft name is one non-hidden portable path component.
pub fn validName(name: []const u8) bool {
    if (name.len == 0 or name[0] == '.') return false;
    for (name) |c| {
        if (std.ascii.isAlphanumeric(c)) continue;
        if (c != '_' and c != '-' and c != '.') return false;
    }
    return true;
}
