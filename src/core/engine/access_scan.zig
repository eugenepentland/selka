//! The no-raw-access rule (spec §4, the K5 rule of the provable-cache plan): the files that implement a kind read the
//! world only through the context. This scans a source file's tokens for the names that reach the filesystem, the
//! environment, the clock, the random source, other processes or C: `std.fs`, `std.Io.Dir`, `std.Io.File`, `std.process`,
//! `std.posix`, `std.os`, `std.c`, `std.time`, `std.Io.Timestamp`, `std.Io.Clock`, `std.Io.random`, `std.Random`,
//! `std.crypto.random` and `@cImport`, spelled directly or through `@import("std")`. An alias (`const fs = std.fs;`)
//! is caught where it is made.
//!
//! It is a lint, not a proof: it cannot see a raw access that a kind's data smuggles in (a function pointer, a global
//! another file owns). Verify mode (spec §10) is the check that sees those. What the scan covers is every file of a
//! kind's closure outside the engine runtime, which is the one place raw access belongs.
const std = @import("std");

/// The dotted names a kind's files may not use.
pub const banned = [_][]const u8{
    "std.fs",
    "std.Io.Dir",
    "std.Io.File",
    "std.Io.net",
    "std.process",
    "std.posix",
    "std.os",
    "std.c",
    "std.time",
    "std.Io.Timestamp",
    "std.Io.Clock",
    "std.Io.random",
    "std.Random",
    "std.crypto.random",
};

/// One use of a banned name.
pub const Finding = struct {
    /// The line, from 1.
    line: usize,
    /// The banned name, e.g. `std.fs`.
    name: []const u8,
};

/// The use of banned names in `source`, in order. The findings borrow from `banned`. Everything the scan allocates is
/// in `a`, which should be an arena that the caller drops.
pub fn scan(a: std.mem.Allocator, source: []const u8) std.mem.Allocator.Error![]const Finding {
    const terminated = try a.allocSentinel(u8, source.len, 0);
    @memcpy(terminated, source);
    var tokens: std.ArrayList(std.zig.Token) = .empty;
    var tokenizer = std.zig.Tokenizer.init(terminated);
    while (true) {
        const token = tokenizer.next();
        if (token.tag == .eof) break;
        try tokens.append(a, token);
    }
    var found: std.ArrayList(Finding) = .empty;
    var at: usize = 0;
    while (at < tokens.items.len) : (at += 1) {
        const token = tokens.items[at];
        if (std.mem.eql(u8, terminated[token.loc.start..token.loc.end], "@cImport")) {
            try found.append(a, .{ .line = lineOf(terminated, token.loc.start), .name = "@cImport" });
            continue;
        }
        const chain = try chainAt(a, terminated, tokens.items, at);
        if (chain.len == 0) continue;
        for (banned) |name| {
            if (startsWithName(chain, name)) {
                try found.append(a, .{ .line = lineOf(terminated, token.loc.start), .name = name });
                break;
            }
        }
    }
    return found.items;
}

/// The identifiers of the dotted chain that starts at token `at` when it begins `std` or `@import("std")`, else empty.
fn chainAt(a: std.mem.Allocator, source: [:0]const u8, tokens: []const std.zig.Token, at: usize) std.mem.Allocator.Error![]const []const u8 {
    var chain: std.ArrayList([]const u8) = .empty;
    var next = at;
    const after_period = at > 0 and tokens[at - 1].tag == .period;
    const imports_std = isText(source, tokens[at], "@import") and at + 3 < tokens.len and tokens[at + 1].tag == .l_paren and isStdImport(source, tokens[at + 2], tokens[at + 3]);
    if (isText(source, tokens[at], "std") and !after_period) {
        try chain.append(a, "std");
        next = at + 1;
    } else if (imports_std) {
        try chain.append(a, "std");
        next = at + 4;
    } else return chain.items;
    while (next + 1 < tokens.len and tokens[next].tag == .period and tokens[next + 1].tag == .identifier) : (next += 2) {
        const token = tokens[next + 1];
        try chain.append(a, source[token.loc.start..token.loc.end]);
    }
    return chain.items;
}

fn isStdImport(source: [:0]const u8, name: std.zig.Token, close: std.zig.Token) bool {
    return isText(source, name, "\"std\"") and close.tag == .r_paren;
}

fn isText(source: [:0]const u8, token: std.zig.Token, text: []const u8) bool {
    return std.mem.eql(u8, source[token.loc.start..token.loc.end], text);
}

fn startsWithName(chain: []const []const u8, name: []const u8) bool {
    var parts = std.mem.splitScalar(u8, name, '.');
    var position: usize = 0;
    while (parts.next()) |part| : (position += 1) {
        if (position >= chain.len or !std.mem.eql(u8, chain[position], part)) return false;
    }
    return true;
}

fn lineOf(source: []const u8, offset: usize) usize {
    return 1 + std.mem.count(u8, source[0..offset], "\n");
}

/// Whether the closure file `path` (relative to `src`) is part of the engine runtime, where raw access belongs: a file
/// in `core/engine/` outside `core/engine/kinds/`. The scan covers every other file of a kind's closure.
pub fn isEngineRuntime(path: []const u8) bool {
    return std.mem.startsWith(u8, path, "core/engine/") and !std.mem.startsWith(u8, path, "core/engine/kinds/");
}

test "a source that reaches the filesystem, the environment or the clock is found where it does" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const found = try scan(a,
        \\const std = @import("std");
        \\const Dir = std.Io.Dir;
        \\fn clock(io: std.Io) i96 {
        \\    return std.Io.Timestamp.now(io, .real).nanoseconds;
        \\}
        \\fn viaImport() void {
        \\    _ = @import("std").process.getEnvVarOwned;
        \\    _ = std.fs.cwd();
        \\}
        \\const c = @cImport({});
    );
    try std.testing.expectEqual(@as(usize, 5), found.len);
    try std.testing.expectEqualStrings("std.Io.Dir", found[0].name);
    try std.testing.expectEqual(@as(usize, 2), found[0].line);
    try std.testing.expectEqualStrings("std.Io.Timestamp", found[1].name);
    try std.testing.expectEqualStrings("std.process", found[2].name);
    try std.testing.expectEqualStrings("std.fs", found[3].name);
    try std.testing.expectEqualStrings("@cImport", found[4].name);
}

test "names in comments and strings, and the standard library's pure parts, are not accesses" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const found = try scan(arena.allocator(),
        \\//! Reads nothing: no std.fs here, no std.process either.
        \\const std = @import("std");
        \\/// std.Io.Dir is not used.
        \\fn pure(a: std.mem.Allocator, text: []const u8) ![]u8 {
        \\    const note = "std.fs.cwd()";
        \\    _ = note;
        \\    var list: std.ArrayList(u8) = .empty;
        \\    try list.appendSlice(a, text);
        \\    return std.fmt.allocPrint(a, "{s}", .{list.items});
        \\}
    );
    try std.testing.expectEqual(@as(usize, 0), found.len);
}

test "the engine runtime is the files directly in core/engine, and kinds are the files below it" {
    try std.testing.expect(isEngineRuntime("core/engine/context.zig"));
    try std.testing.expect(!isEngineRuntime("core/engine/kinds/probe.zig"));
    try std.testing.expect(!isEngineRuntime("core/fast_blake3.zig"));
    try std.testing.expect(!isEngineRuntime("sema.zig"));
}
