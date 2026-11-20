//! rename: keep-file (this file names the old spellings on purpose, and the rename program leaves it alone).
//! One release of one-line hints for a command line or a shell that still spells things the way the language did before its
//! rename from `mylang` to `selka` (decision GH-D4: none of the old spellings is honoured, and nothing reads them as a fallback).
//!
//! The old names are text in this file and nowhere else in the compiler: the source suffix, the project file and the two
//! variable prefixes. Each hint is one line that names the new spelling and, for a project, the command that moves it across.
//! An entry file or a project folder spelled the old way ends the command with status 2 (it would have failed anyway, with a
//! message that did not say why); a set old variable is mentioned once and the command goes on.
const std = @import("std");
const product = @import("compiler_root").compiler_language.product;

/// The command that moves a project across: it renames the sources, the project file, the variables and the work directory.
pub const crossing_command = "python3 scripts/rename_to_selka.py --project DIR";
/// The source suffix before the rename.
const old_source_suffix = ".my";
/// The project file before the rename.
const old_project_file = "mylang.json";
/// The prefix of the compiler's variables before the rename (`MYLANG_JOBS` is `SELKA_JOBS` now).
const old_env_prefix = "MYLANG_";
/// The prefix of the core's and the runtime's variables before the rename (`MYL_CORE_LEAKCHECK` is `SELKA_CORE_LEAKCHECK` now).
const old_core_env_prefix = "MYL_CORE_";

/// The operand at or after `at.*` of a command line, and `at.*` moved past it: options, the value of `-o` and everything after a
/// bare `--` (the arguments of the program a command runs) are not operands.
fn nextOperand(args: []const [:0]const u8, at: *usize) ?[]const u8 {
    while (at.* < args.len) {
        const arg: []const u8 = args[at.*];
        at.* += 1;
        if (std.mem.eql(u8, arg, "--")) {
            at.* = args.len;
            return null;
        }
        if (std.mem.eql(u8, arg, "-o")) {
            at.* += 1;
            continue;
        }
        if (arg.len == 0 or arg[0] == '-') continue;
        return arg;
    }
    return null;
}

/// The hint for an operand that ends in the old source suffix, or null: `args` is the whole command line, its command word
/// included (a source file is never the command word, so the command word is not tested).
pub fn entryHint(allocator: std.mem.Allocator, args: []const [:0]const u8) std.mem.Allocator.Error!?[]u8 {
    var at: usize = 2;
    while (nextOperand(args, &at)) |operand| {
        if (!std.mem.endsWith(u8, operand, old_source_suffix)) continue;
        return try std.fmt.allocPrint(
            allocator,
            "selka: {s} ends in {s}: source files end in {s} now; move the project across with `{s}`\n",
            .{ operand, old_source_suffix, product.source_suffix, crossing_command },
        );
    }
    return null;
}

/// The hint for a folder operand that holds the old project file and not the new one, or null: `args` as for `entryHint`.
pub fn projectFileHint(allocator: std.mem.Allocator, io: std.Io, args: []const [:0]const u8) std.mem.Allocator.Error!?[]u8 {
    var at: usize = 2;
    while (nextOperand(args, &at)) |operand| {
        if (!isDirectory(io, operand)) continue;
        if (!holds(allocator, io, operand, old_project_file) or holds(allocator, io, operand, product.project_file)) continue;
        return try std.fmt.allocPrint(
            allocator,
            "selka: {s} holds {s} and no {s}: the project file is {s} now; move the project across with `{s}`\n",
            .{ operand, old_project_file, product.project_file, product.project_file, crossing_command },
        );
    }
    return null;
}

/// Whether `path` names a directory.
fn isDirectory(io: std.Io, path: []const u8) bool {
    const info = std.Io.Dir.cwd().statFile(io, path, .{}) catch return false;
    return info.kind == .directory;
}

/// Whether the folder `directory` holds a file called `name`.
fn holds(allocator: std.mem.Allocator, io: std.Io, directory: []const u8, name: []const u8) bool {
    const path = std.fs.path.join(allocator, &.{ directory, name }) catch return false;
    defer allocator.free(path);
    _ = std.Io.Dir.cwd().statFile(io, path, .{}) catch return false;
    return true;
}

/// The new spelling of the variable `name`, allocated, or null when `name` has neither old prefix.
fn newSpelling(allocator: std.mem.Allocator, name: []const u8) std.mem.Allocator.Error!?[]u8 {
    if (std.mem.startsWith(u8, name, old_env_prefix)) return try std.mem.concat(allocator, u8, &.{ product.env_prefix, name[old_env_prefix.len..] });
    if (std.mem.startsWith(u8, name, old_core_env_prefix)) return try std.mem.concat(allocator, u8, &.{ product.core_env_prefix, name[old_core_env_prefix.len..] });
    return null;
}

/// Whether the name `a` sorts before `b`, byte by byte.
fn nameLess(_: void, a: []const u8, b: []const u8) bool {
    return std.mem.lessThan(u8, a, b);
}

/// The hint for the variables of `environment` that carry an old prefix while their new spelling is not set, or null when there
/// are none: one line naming the first such variable in sorted order and its new spelling, and how many more there are. No list of
/// old names is kept, the prefix is the test.
pub fn variableHint(allocator: std.mem.Allocator, environment: *const std.process.Environ.Map) std.mem.Allocator.Error!?[]u8 {
    var unanswered: std.ArrayList([]const u8) = .empty;
    defer unanswered.deinit(allocator);
    var entries = environment.iterator();
    while (entries.next()) |entry| {
        const name = entry.key_ptr.*;
        const spelled = (try newSpelling(allocator, name)) orelse continue;
        defer allocator.free(spelled);
        if (environment.get(spelled) == null) try unanswered.append(allocator, name);
    }
    if (unanswered.items.len == 0) return null;
    std.mem.sort([]const u8, unanswered.items, {}, nameLess);
    const first = unanswered.items[0];
    const spelled = (try newSpelling(allocator, first)).?;
    defer allocator.free(spelled);
    const more = unanswered.items.len - 1;
    if (more == 0) {
        return try std.fmt.allocPrint(allocator, "selka: the variable {s} is set and {s} is not: variables begin with {s} now, and the old name is ignored\n", .{ first, spelled, product.env_prefix });
    }
    return try std.fmt.allocPrint(allocator, "selka: the variable {s} is set and {s} is not: variables begin with {s} now, and the old name is ignored; more old names set: {d}\n", .{ first, spelled, product.env_prefix, more });
}
