//! Reserved standard modules are identical for disk, embedded and inspection providers.
//!
//! Adding a module is this table plus its guide, nothing else is a list to keep in step:
//!   1. `src/stdlib/NAME.selka` and one row below (`paths` and `count` follow it, and the
//!      reference engine, its module limit and the tests read them);
//!   2. a heading for it in `docs/standard-library.md`, and the new count in words wherever
//!      the guides and `src/features.json` state one ("twenty-three modules");
//!      `STDLIB-COUNT-1` in `standard_library_test.zig` fails naming the file that is stale;
//!   3. tests (`src/stdlib_NAME_test.zig`, registered in `src/root_test.zig`, or
//!      `tests/lang/*.selka`) and a `SPEC.md` bullet for the behaviour.
//!
//! A module's header is the comment that opens its file. Put it above the `import` lines, or, in a module with none, end it
//! with an empty `#` line: `selka fmt` removes a blank line between comment lines, and `selka reference` would otherwise
//! print the header as the first declaration's description (`reference_test.zig` checks all modules).
const std = @import("std");
const product = @import("product.zig");
const Module = struct { path: []const u8, text: []const u8 };
const modules = [_]Module{
    .{ .path = "argparse.selka", .text = @embedFile("stdlib/argparse.selka") },
    .{ .path = "base64.selka", .text = @embedFile("stdlib/base64.selka") },
    .{ .path = "binary.selka", .text = @embedFile("stdlib/binary.selka") },
    .{ .path = "byte_builder.selka", .text = @embedFile("stdlib/byte_builder.selka") },
    .{ .path = "byte_format.selka", .text = @embedFile("stdlib/byte_format.selka") },
    .{ .path = "buffers.selka", .text = @embedFile("stdlib/buffers.selka") },
    .{ .path = "bytes.selka", .text = @embedFile("stdlib/bytes.selka") },
    .{ .path = "buildkit.selka", .text = @embedFile("stdlib/buildkit.selka") },
    .{ .path = "cache_record.selka", .text = @embedFile("stdlib/cache_record.selka") },
    .{ .path = "cpu.selka", .text = @embedFile("stdlib/cpu.selka") },
    .{ .path = "csv.selka", .text = @embedFile("stdlib/csv.selka") },
    .{ .path = "dicts.selka", .text = @embedFile("stdlib/dicts.selka") },
    .{ .path = "durable.selka", .text = @embedFile("stdlib/durable.selka") },
    .{ .path = "environment.selka", .text = @embedFile("stdlib/environment.selka") },
    .{ .path = "filesystem.selka", .text = @embedFile("stdlib/filesystem.selka") },
    .{ .path = "flate.selka", .text = @embedFile("stdlib/flate.selka") },
    .{ .path = "hashes.selka", .text = @embedFile("stdlib/hashes.selka") },
    .{ .path = "http.selka", .text = @embedFile("stdlib/http.selka") },
    .{ .path = "hex.selka", .text = @embedFile("stdlib/hex.selka") },
    .{ .path = "json.selka", .text = @embedFile("stdlib/json.selka") },
    .{ .path = "lists.selka", .text = @embedFile("stdlib/lists.selka") },
    .{ .path = "logging.selka", .text = @embedFile("stdlib/logging.selka") },
    .{ .path = "math.selka", .text = @embedFile("stdlib/math.selka") },
    .{ .path = "memo.selka", .text = @embedFile("stdlib/memo.selka") },
    .{ .path = "network.selka", .text = @embedFile("stdlib/network.selka") },
    .{ .path = "options.selka", .text = @embedFile("stdlib/options.selka") },
    .{ .path = "parallel.selka", .text = @embedFile("stdlib/parallel.selka") },
    .{ .path = "path.selka", .text = @embedFile("stdlib/path.selka") },
    .{ .path = "persistent_memo.selka", .text = @embedFile("stdlib/persistent_memo.selka") },
    .{ .path = "pool.selka", .text = @embedFile("stdlib/pool.selka") },
    .{ .path = "process.selka", .text = @embedFile("stdlib/process.selka") },
    .{ .path = "random.selka", .text = @embedFile("stdlib/random.selka") },
    .{ .path = "registers.selka", .text = @embedFile("stdlib/registers.selka") },
    .{ .path = "sets.selka", .text = @embedFile("stdlib/sets.selka") },
    .{ .path = "simd.selka", .text = @embedFile("stdlib/simd.selka") },
    .{ .path = "sort.selka", .text = @embedFile("stdlib/sort.selka") },
    .{ .path = "spans.selka", .text = @embedFile("stdlib/spans.selka") },
    .{ .path = "streams.selka", .text = @embedFile("stdlib/streams.selka") },
    .{ .path = "strings.selka", .text = @embedFile("stdlib/strings.selka") },
    .{ .path = "symbols.selka", .text = @embedFile("stdlib/symbols.selka") },
    .{ .path = "testing.selka", .text = @embedFile("stdlib/testing.selka") },
    .{ .path = "time.selka", .text = @embedFile("stdlib/time.selka") },
};
/// Every reserved standard module's file name (`csv.selka`), in table order: the one list
/// the reference engine, the tests and the prose counts are checked against.
pub const paths = paths: {
    var out: [modules.len][]const u8 = undefined;
    for (modules, 0..) |module, index| out[index] = module.path;
    break :paths out;
};

/// How many standard modules ship inside the compiler.
pub const count = modules.len;

/// Return a library-owned source view, or null for an ordinary project module.
pub fn source(path: []const u8) ?[]const u8 {
    for (modules) |module| if (std.mem.eql(u8, path, module.path)) return module.text;
    return null;
}

/// Whether a checked source is one of the compiler's own standard-library
/// sources: the embedded text itself, served under its `@stdlib/` path. Those
/// sources may name the internal spellings (`__float_sqrt`, `__stand_in`) and
/// the method lowerings their own module functions are written with.
pub fn trusted(path: []const u8, bytes: []const u8, trusted_intrinsics: bool) bool {
    if (trusted_intrinsics) return true;
    const prefix = "@stdlib/";
    if (!std.mem.startsWith(u8, path, prefix)) return false;
    const embedded = source(path[prefix.len..]) orelse return false;
    return std.mem.eql(u8, embedded, bytes);
}

/// The standard modules other than `except` (a module name such as `strings`) whose source declares a public function
/// `name`, in table order and at most `found.len` of them: a line that begins `public func NAME(`, `public func NAME[` or
/// `public builtin func NAME(`. A diagnostic names them for a name another module lacks (F-51). Returns how many it wrote.
/// When `except` is a module of one kind of value (`strings`, `bytes`, `lists`, `dicts`, `sets`: `valueTaken`) a module is
/// named only when its function takes that kind of value first, since the author wrote `strings.NAME(text)` with a text in hand
/// and `bytes.index(data)` or `spans.is_empty(span)` cannot take it (MSG-F).
pub fn exporting(name: []const u8, except: []const u8, found: [][]const u8) usize {
    var written: usize = 0;
    for (modules) |module| {
        if (written == found.len) break;
        const stem = product.chopSource(module.path);
        if (std.mem.eql(u8, stem, except)) continue;
        if (!declaresPublicFunction(module.text, name)) continue;
        if (valueTaken(except)) |takes| {
            const first = firstParameterType(module.text, name, true) orelse continue;
            if (!takes(first)) continue;
        }
        found[written] = stem;
        written += 1;
    }
    return written;
}

/// The test of whether a type as the library spells it (`str`, `T[]`, `dict[K, V]`) is the kind of value the module `module` is
/// for, or null when `module` is not a module of one kind of value: text for `strings`, bytes for `bytes`, a list (`T[]`) for
/// `lists`, a dictionary for `dicts` and a set for `sets`.
fn valueTaken(module: []const u8) ?*const fn ([]const u8) bool {
    const kinds = [_]struct { name: []const u8, takes: *const fn ([]const u8) bool }{
        .{ .name = "strings", .takes = takesText },
        .{ .name = "bytes", .takes = takesBytes },
        .{ .name = "lists", .takes = takesList },
        .{ .name = "dicts", .takes = takesDictionary },
        .{ .name = "sets", .takes = takesSet },
    };
    for (kinds) |kind| if (std.mem.eql(u8, kind.name, module)) return kind.takes;
    return null;
}

fn takesText(ty: []const u8) bool {
    return std.mem.eql(u8, ty, "str");
}

fn takesBytes(ty: []const u8) bool {
    return std.mem.eql(u8, ty, "bytes");
}

fn takesList(ty: []const u8) bool {
    return std.mem.endsWith(u8, ty, "[]");
}

fn takesDictionary(ty: []const u8) bool {
    return std.mem.startsWith(u8, ty, "dict[");
}

fn takesSet(ty: []const u8) bool {
    return std.mem.startsWith(u8, ty, "set[");
}

/// The one standard module whose public function `name` takes a first parameter of the type `receiver`, spelled as the library
/// writes it (`Clock`): `time` for `now` and `Clock`. Null when no module does, when two do (`decode` of `bytes`), or when the
/// first parameter is not a plain `name: Type` (a `mut`, `own` or `named` one is written differently at a call). FR34: a method
/// call on a value that has no methods is told which module's function it meant.
pub fn declaringFirstParameter(name: []const u8, receiver: []const u8) ?[]const u8 {
    var match: ?[]const u8 = null;
    for (modules) |module| {
        const first = firstParameterType(module.text, name, false) orelse continue;
        if (!std.mem.eql(u8, first, receiver)) continue;
        if (match != null) return null;
        match = product.chopSource(module.path);
    }
    return match;
}

/// `declaringFirstParameter`, except that the module `home` answers first when it declares the function for `receiver`
/// itself: a capability's own module (`process` for `Process`) is the function its method meant, even when another module
/// declares a function of the name for the same type (`buildkit.run`). Otherwise the one module, or null, as there.
pub fn declaringFirstParameterHome(name: []const u8, receiver: []const u8, home: []const u8) ?[]const u8 {
    for (modules) |module| {
        const stem = product.chopSource(module.path);
        if (!std.mem.eql(u8, stem, home)) continue;
        const first = firstParameterType(module.text, name, false) orelse break;
        if (std.mem.eql(u8, first, receiver)) return stem;
        break;
    }
    return declaringFirstParameter(name, receiver);
}

/// The type of the first parameter of the public function `name` in `text`, as written, or null when `text` declares no such
/// function, its signature does not close on its line, or its first parameter carries a default, or a modifier unless
/// `modifier` is true (`mut values: T[]` is then `T[]`).
fn firstParameterType(text: []const u8, name: []const u8, modifier: bool) ?[]const u8 {
    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |line| {
        const rest = if (std.mem.startsWith(u8, line, "public func "))
            line["public func ".len..]
        else if (std.mem.startsWith(u8, line, "public builtin func "))
            line["public builtin func ".len..]
        else
            continue;
        if (!std.mem.startsWith(u8, rest, name) or rest.len == name.len) continue;
        var at = name.len;
        if (rest[at] == '[') {
            var depth: usize = 0;
            while (at < rest.len) : (at += 1) {
                if (rest[at] == '[') depth += 1;
                if (rest[at] == ']') depth -= 1;
                if (depth == 0) break;
            }
            at += 1;
        }
        if (at >= rest.len or rest[at] != '(') continue;
        const parameters = rest[at + 1 ..];
        if (!modifier) return plainFirstType(parameters);
        for ([_][]const u8{ "mut ", "own " }) |marker| if (std.mem.startsWith(u8, parameters, marker)) return plainFirstType(parameters[marker.len..]);
        return plainFirstType(parameters);
    }
    return null;
}

/// The type in `parameters` (the text after a signature's `(`) when its first parameter is `name: Type`, up to the `,` or `)` that
/// ends it; null for a modifier before the name, a default after the type, or a list that does not close.
fn plainFirstType(parameters: []const u8) ?[]const u8 {
    const colon = std.mem.indexOfScalar(u8, parameters, ':') orelse return null;
    const name = parameters[0..colon];
    if (name.len == 0) return null;
    for (name) |byte| if (!std.ascii.isAlphanumeric(byte) and byte != '_') return null;
    var depth: usize = 0;
    var at = colon + 1;
    while (at < parameters.len) : (at += 1) {
        switch (parameters[at]) {
            '(', '[' => depth += 1,
            ')', ']' => {
                if (depth == 0) return if (parameters[at] == ')') std.mem.trim(u8, parameters[colon + 1 .. at], " ") else null;
                depth -= 1;
            },
            ',' => if (depth == 0) return std.mem.trim(u8, parameters[colon + 1 .. at], " "),
            '=' => if (depth == 0) return null,
            else => {},
        }
    }
    return null;
}

/// Whether `text` has a line that declares the public function `name` (the forms `exporting` lists).
fn declaresPublicFunction(text: []const u8, name: []const u8) bool {
    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |line| {
        const rest = if (std.mem.startsWith(u8, line, "public func "))
            line["public func ".len..]
        else if (std.mem.startsWith(u8, line, "public builtin func "))
            line["public builtin func ".len..]
        else
            continue;
        if (!std.mem.startsWith(u8, rest, name) or rest.len == name.len) continue;
        if (rest[name.len] == '(' or rest[name.len] == '[') return true;
    }
    return false;
}

/// The reserved standard module names, comma-separated in table order, for
/// diagnostics that tell a user which imports need no project module.
pub fn names(allocator: std.mem.Allocator) error{OutOfMemory}![]u8 {
    var joined: std.ArrayList(u8) = .empty;
    errdefer joined.deinit(allocator);
    for (modules, 0..) |module, index| {
        if (index != 0) try joined.appendSlice(allocator, ", ");
        try joined.appendSlice(allocator, product.chopSource(module.path));
    }
    return joined.toOwnedSlice(allocator);
}
