//! Compile-time file embedding (`EMBED-1`): `embed_bytes("path")` and
//! `embed_str("path")` read one project file while the program is loaded, so the
//! data is baked into the binary and no runtime capability is involved.
//!
//! The loader finds every call whose only argument is a string literal, reads
//! the named file beneath the project root, and records the outcome as a
//! `source.Embed` on the source that spells the call. The checker only looks the
//! outcome up, so a missing or forbidden file is an ordinary located diagnostic
//! and the file's content digest can join every cache key that covers the module.
const std = @import("std");
const ast = @import("ast.zig");
const source = @import("source.zig");
const lexer = @import("lexer.zig");
const byte_literal = @import("byte_literal.zig");
const format_strings = @import("format_strings.zig");
const diagnostic = @import("diagnostic.zig");
const component = @import("lexer_component.zig");
const Blake3 = std.crypto.hash.Blake3;

/// Builtin spelling that embeds a file as `bytes`.
pub const bytes_name = "embed_bytes";
/// Builtin spelling that embeds a UTF-8 file as `str`.
pub const str_name = "embed_str";
/// Largest file one embed may read, in bytes (16 MiB).
pub const size_cap: usize = 16 * 1024 * 1024;

/// Which value an embed call produces.
pub const Kind = enum { bytes, str };

/// The embed kind a bare call name spells, or null for any other name.
pub fn kindOf(name: []const u8) ?Kind {
    if (std.mem.eql(u8, name, bytes_name)) return .bytes;
    if (std.mem.eql(u8, name, str_name)) return .str;
    return null;
}

/// Diagnostic code: the argument is not exactly one string literal.
pub const code_argument = "E_EMBED_ARGUMENT";
/// Diagnostic code: the source was not loaded from a directory, so there is nothing to resolve against.
pub const code_unavailable = "E_EMBED_UNAVAILABLE";
/// Diagnostic code: the path is empty or spelled with a NUL byte or backslash.
pub const code_path = "E_EMBED_PATH";
/// Diagnostic code: the path is absolute.
pub const code_absolute = "E_EMBED_ABSOLUTE";
/// Diagnostic code: the path leaves the project root through `..` or a symbolic link.
pub const code_escape = "E_EMBED_ESCAPE";
/// Diagnostic code: no such file.
pub const code_missing = "E_EMBED_MISSING";
/// Diagnostic code: the path names a directory or another non-regular file.
pub const code_directory = "E_EMBED_DIRECTORY";
/// Diagnostic code: the file is larger than `size_cap`.
pub const code_too_large = "E_EMBED_TOO_LARGE";
/// Diagnostic code: the file exists but cannot be read.
pub const code_unreadable = "E_EMBED_UNREADABLE";
/// Diagnostic code: `embed_str` was given a file that is not valid UTF-8.
pub const code_utf8 = "E_EMBED_UTF8";

/// Stable diagnostic code for one embed outcome; null for `ok`.
pub fn codeOf(status: source.EmbedStatus) ?[]const u8 {
    return switch (status) {
        .ok => null,
        .unresolved => code_unavailable,
        .invalid_path => code_path,
        .absolute => code_absolute,
        .escapes => code_escape,
        .missing => code_missing,
        .directory => code_directory,
        .too_large => code_too_large,
        .unreadable => code_unreadable,
    };
}

/// The located message for a failed embed, quoting the path as written.
pub fn messageOf(allocator: std.mem.Allocator, status: source.EmbedStatus, path: []const u8) std.mem.Allocator.Error![]const u8 {
    return switch (status) {
        .ok => "the file was read",
        .unresolved => std.fmt.allocPrint(
            allocator,
            "cannot embed \"{s}\": the file was not read when this source was loaded; embed calls need a source loaded from a file on disk and the call written as embed_bytes(\"path\") with one plain string literal",
            .{path},
        ),
        .invalid_path => std.fmt.allocPrint(allocator, "embed path \"{s}\" is not a usable path; write a non-empty relative path such as \"data/table.txt\", without NUL bytes or backslashes", .{path}),
        .absolute => std.fmt.allocPrint(allocator, "embed path \"{s}\" is absolute; embedded files are named relative to the directory of the source file that embeds them", .{path}),
        .escapes => std.fmt.allocPrint(allocator, "embedded file \"{s}\" is outside the project root (through `..` or a symbolic link); keep embedded data inside the project", .{path}),
        .missing => std.fmt.allocPrint(allocator, "cannot embed \"{s}\": no such file; the path is relative to the directory of the source file that embeds it", .{path}),
        .directory => std.fmt.allocPrint(allocator, "cannot embed \"{s}\": it is a directory or not a regular file; name one file", .{path}),
        .too_large => std.fmt.allocPrint(allocator, "cannot embed \"{s}\": the file is larger than the {d} MiB embed limit", .{ path, size_cap / (1024 * 1024) }),
        .unreadable => std.fmt.allocPrint(allocator, "cannot embed \"{s}\": the file cannot be read", .{path}),
    };
}

/// Byte offset of the first byte that keeps `bytes` from being valid UTF-8, or
/// null when it is valid. `embed_str` reports the offset in its diagnostic.
pub fn firstInvalidUtf8(bytes: []const u8) ?usize {
    var index: usize = 0;
    while (index < bytes.len) {
        const lead = bytes[index];
        if (lead < 0x80) {
            index += 1;
            continue;
        }
        const width = std.unicode.utf8ByteSequenceLength(lead) catch return index;
        if (index + width > bytes.len) return index;
        _ = std.unicode.utf8Decode(bytes[index .. index + width]) catch return index;
        index += width;
    }
    return null;
}

/// The parsed shape of a builtin call node.
const Call = @FieldType(@FieldType(ast.Node, "data"), "call");

/// What one embed call is checked against: the source that spells it, its syntax
/// nodes, and where diagnostics go.
pub const Context = struct { scratch: std.mem.Allocator, src: source.Source, nodes: []const ast.Node, sink: *diagnostic.Sink };

/// Validate one embed call against what the loader read and answer the file it
/// read. The call must have exactly one string-literal argument; a failed read,
/// or for `embed_str` a file that is not valid UTF-8, is reported at that literal.
pub fn check(context: Context, call: Call, kind: Kind, site: source.Span) diagnostic.Error!*const source.Embed {
    const allocator = context.scratch;
    const builtin = if (kind == .bytes) bytes_name else str_name;
    if (call.arguments.len != 1 or call.argument_names.len != 0) {
        const message = try std.fmt.allocPrint(allocator, "{s} takes exactly one argument: a string literal path such as {s}(\"data/table.txt\")", .{ builtin, builtin });
        return context.sink.fail(code_argument, site, message);
    }
    const argument = context.nodes[@backingInt(call.arguments[0])];
    if (argument.data != .text) {
        const message = try std.fmt.allocPrint(allocator, "{s} requires a plain string literal path: the file is read at compile time, so the path cannot be computed", .{builtin});
        return context.sink.fail(code_argument, argument.span, message);
    }
    const found = context.src.embedAt(argument.span) orelse
        return context.sink.fail(code_unavailable, argument.span, try messageOf(allocator, .unresolved, argument.data.text));
    if (codeOf(found.status)) |code| return context.sink.fail(code, argument.span, try messageOf(allocator, found.status, found.path));
    if (kind == .str) if (firstInvalidUtf8(found.contents)) |offset| {
        const message = try std.fmt.allocPrint(allocator, "embed_str file \"{s}\" is not valid UTF-8 (invalid byte at offset {d}); use embed_bytes for binary data", .{ found.path, offset });
        return context.sink.fail(code_utf8, argument.span, message);
    };
    return found;
}

/// Whether `bytes` could hold an embed call at all. Modules that never spell
/// one skip the scan entirely.
pub fn mayEmbed(bytes: []const u8) bool {
    return std.mem.indexOf(u8, bytes, "embed_") != null;
}

/// Find every `embed_bytes("literal")` and `embed_str("literal")` call in one
/// tokenized source, in source order, as unresolved embeds, including the ones
/// inside `f"..."` interpolations. A call whose argument is anything else is
/// left for the checker to reject.
pub fn sites(allocator: std.mem.Allocator, src: source.Source, tokens: []const lexer.Token) std.mem.Allocator.Error![]source.Embed {
    var found: std.ArrayList(source.Embed) = .empty;
    errdefer found.deinit(allocator);
    try collect(allocator, src, tokens, &found);
    return found.toOwnedSlice(allocator);
}

/// Append the embed calls of `tokens` to `found`, descending into format strings.
fn collect(allocator: std.mem.Allocator, src: source.Source, tokens: []const lexer.Token, found: *std.ArrayList(source.Embed)) std.mem.Allocator.Error!void {
    for (tokens, 0..) |token, index| {
        if (token.tag == .format) {
            try collectHoles(allocator, src, token.span, found);
            continue;
        }
        if (token.tag != .ident or index + 3 >= tokens.len) continue;
        const kind = kindOf(src.text(token.span)) orelse continue;
        if (tokens[index + 1].tag != .lparen or tokens[index + 2].tag != .bytes) continue;
        const closing = tokens[index + 3].tag == .rparen or (tokens[index + 3].tag == .comma and index + 4 < tokens.len and tokens[index + 4].tag == .rparen);
        if (!closing) continue;
        const literal = tokens[index + 2].span;
        const spelling = src.text(literal);
        if (spelling.len < 2 or (spelling[0] != '"' and spelling[0] != '\'') or byte_literal.quoteDelimiters(spelling) != 1) continue;
        var scratch: diagnostic.Sink = .{ .allocator = allocator };
        defer scratch.deinit();
        const path = byte_literal.decode(allocator, src, literal, &scratch) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => continue,
        };
        try found.append(allocator, .{ .literal = literal, .path = path, .text = kind == .str });
    }
}

/// Append the embed calls inside the interpolations of one `f"..."` literal.
fn collectHoles(allocator: std.mem.Allocator, src: source.Source, span: source.Span, found: *std.ArrayList(source.Embed)) std.mem.Allocator.Error!void {
    if (!mayEmbed(src.text(span))) return;
    var scratch: diagnostic.Sink = .{ .allocator = allocator };
    defer scratch.deinit();
    const pieces = format_strings.split(allocator, src, span, &scratch) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return,
    };
    defer allocator.free(pieces);
    for (pieces) |piece| {
        const hole = switch (piece) {
            .hole => |inner| inner,
            else => continue,
        };
        const tokens = lexer.lexRange(allocator, src.bytes, hole, &scratch) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => continue,
        };
        defer allocator.free(tokens);
        try collect(allocator, src, tokens, found);
    }
}

/// Lex `src` and find its embed calls, or none without lexing when the source
/// never spells `embed_`. A lexing failure yields no sites: the parser reports it.
pub fn scan(allocator: std.mem.Allocator, src: source.Source) std.mem.Allocator.Error![]source.Embed {
    return scanWithRuntime(allocator, src, null) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return &.{},
    };
}

/// Find embed sites using the selected full-source lexer. Source failures are
/// left to parsing; component failures propagate even when no site is present.
pub fn scanWithRuntime(allocator: std.mem.Allocator, src: source.Source, runtime: ?component.Runtime) (diagnostic.Error || component.Error)![]source.Embed {
    if (runtime) |capabilities| _ = try component.identity(allocator, capabilities);
    if (!mayEmbed(src.bytes)) return &.{};
    var scratch: diagnostic.Sink = .{ .allocator = allocator };
    defer scratch.deinit();
    const tokens = (if (runtime) |capabilities| component.lex(allocator, src, &scratch, capabilities) else lexer.lex(allocator, src.bytes, &scratch)) catch |err| switch (err) {
        error.SourceError => return &.{},
        else => return err,
    };
    defer allocator.free(tokens);
    return sites(allocator, src, tokens);
}

/// Where embedded paths resolve. `import_root` holds the module files (a
/// module's `path` is relative to it) and `root` is the project root that no
/// embedded file may leave: the directory of the nearest `mylang.json`, or the
/// entry's own directory when there is none.
pub const Roots = struct { io: std.Io, import_root: []const u8, root: []const u8 };

/// One read: the file's status and, when `ok`, its bytes owned by the allocator.
pub const Read = struct { status: source.EmbedStatus, contents: []const u8 = &.{} };

/// Read the file one embed names, relative to the directory of `module_path`
/// (itself relative to `roots.import_root`). Every failure is a status; only an
/// allocation failure is an error.
pub fn read(allocator: std.mem.Allocator, roots: Roots, module_path: []const u8, path: []const u8) std.mem.Allocator.Error!Read {
    return readLimited(allocator, roots, module_path, path, size_cap);
}

/// Read an embedded file without allocating beyond the supplied project budget.
/// The standalone 16 MiB embed limit still applies when the budget is larger.
pub fn readLimited(allocator: std.mem.Allocator, roots: Roots, module_path: []const u8, path: []const u8, requested_limit: usize) std.mem.Allocator.Error!Read {
    const limit = @min(requested_limit, size_cap);
    if (spelledStatus(path)) |status| return .{ .status = status };
    const cwd = std.Io.Dir.cwd();
    const root = cwd.realPathFileAlloc(roots.io, roots.root, allocator) catch |err| return failed(err);
    defer allocator.free(root);
    const module_file = try std.fs.path.join(allocator, &.{ roots.import_root, module_path });
    defer allocator.free(module_file);
    const directory = cwd.realPathFileAlloc(roots.io, std.fs.path.dirname(module_file) orelse ".", allocator) catch |err| return failed(err);
    defer allocator.free(directory);
    // Resolve `.` and `..` lexically first so a path that names something outside
    // the root is refused without ever probing whether it exists.
    const target = (try lexicalJoin(allocator, directory, path)) orelse return .{ .status = .escapes };
    defer allocator.free(target);
    if (!within(root, target)) return .{ .status = .escapes };
    const real = cwd.realPathFileAlloc(roots.io, target, allocator) catch |err| return failed(err);
    defer allocator.free(real);
    // The canonical path has followed every symbolic link, so a link that leads
    // out of the root is caught here.
    if (!within(root, real)) return .{ .status = .escapes };
    const stat = cwd.statFile(roots.io, real, .{}) catch |err| return failed(err);
    if (stat.kind == .directory) return .{ .status = .directory };
    if (stat.kind != .file) return .{ .status = .directory };
    if (stat.size > limit) return .{ .status = .too_large };
    const contents = cwd.readFileAlloc(roots.io, real, allocator, .limited(limit + 1)) catch |err| return switch (err) {
        error.OutOfMemory => error.OutOfMemory,
        error.StreamTooLong => .{ .status = .too_large },
        else => failed(err),
    };
    if (contents.len > limit) {
        allocator.free(contents);
        return .{ .status = .too_large };
    }
    return .{ .status = .ok, .contents = contents };
}

/// Map a filesystem error onto the embed status it should report.
fn failed(err: anyerror) Read {
    return switch (err) {
        error.FileNotFound, error.NotDir => .{ .status = .missing },
        error.IsDir => .{ .status = .directory },
        else => .{ .status = .unreadable },
    };
}

/// `base` followed by the relative `path`, with `.` and empty parts dropped and
/// `..` popping a component; null when a `..` climbs above the filesystem root.
fn lexicalJoin(allocator: std.mem.Allocator, base: []const u8, path: []const u8) std.mem.Allocator.Error!?[]u8 {
    var parts: std.ArrayList([]const u8) = .empty;
    defer parts.deinit(allocator);
    var base_parts = std.mem.tokenizeScalar(u8, base, '/');
    while (base_parts.next()) |part| try parts.append(allocator, part);
    var path_parts = std.mem.splitScalar(u8, path, '/');
    while (path_parts.next()) |part| {
        if (part.len == 0 or std.mem.eql(u8, part, ".")) continue;
        if (std.mem.eql(u8, part, "..")) {
            if (parts.items.len == 0) return null;
            _ = parts.pop();
            continue;
        }
        try parts.append(allocator, part);
    }
    var joined: std.ArrayList(u8) = .empty;
    errdefer joined.deinit(allocator);
    for (parts.items) |part| {
        try joined.append(allocator, '/');
        try joined.appendSlice(allocator, part);
    }
    if (joined.items.len == 0) try joined.append(allocator, '/');
    const owned = try joined.toOwnedSlice(allocator);
    return owned;
}

/// Where `path`, written in a module whose directory is `module_directory`
/// (relative to the import root, `""` for the root itself), names a file
/// relative to that root: `.` and empty parts dropped and `..` removing a
/// component, or kept as a leading `..` when it climbs above the root. It is
/// the lexical spelling a copy of the project must give the file to keep the
/// module's relative reference working.
pub fn relativeTarget(allocator: std.mem.Allocator, module_directory: []const u8, path: []const u8) std.mem.Allocator.Error![]u8 {
    var parts: std.ArrayList([]const u8) = .empty;
    defer parts.deinit(allocator);
    for ([_][]const u8{ module_directory, path }) |text| {
        var pieces = std.mem.splitScalar(u8, text, '/');
        while (pieces.next()) |part| {
            if (part.len == 0 or std.mem.eql(u8, part, ".")) continue;
            const climbing = parts.items.len != 0 and !std.mem.eql(u8, parts.items[parts.items.len - 1], "..");
            if (std.mem.eql(u8, part, "..") and climbing) _ = parts.pop() else try parts.append(allocator, part);
        }
    }
    return std.mem.join(allocator, "/", parts.items);
}

/// The status a path earns from its spelling alone, before any file is touched.
pub fn spelledStatus(path: []const u8) ?source.EmbedStatus {
    if (path.len == 0 or std.mem.indexOfAny(u8, path, "\\\x00") != null) return .invalid_path;
    if (path[0] == '/') return .absolute;
    return null;
}

/// Whether the absolute `path` is `root` itself or lies beneath it, by whole components.
fn within(root: []const u8, path: []const u8) bool {
    if (!std.mem.startsWith(u8, path, root)) return false;
    if (path.len == root.len) return true;
    return root.len == 1 or path[root.len] == '/';
}

/// Fill every unresolved embed of `embeds` by reading its file. Sorted order is kept.
pub fn resolve(allocator: std.mem.Allocator, roots: Roots, module_path: []const u8, embeds: []source.Embed) std.mem.Allocator.Error!void {
    for (embeds) |*embed| {
        const outcome = try read(allocator, roots, module_path, embed.path);
        embed.status = outcome.status;
        embed.contents = outcome.contents;
        if (outcome.status == .ok) digest(outcome.contents, &embed.digest);
    }
}

/// The content digest an embed carries: BLAKE3, which stays cheap on the
/// megabytes a file may hold even in an unoptimized compiler.
pub fn digest(contents: []const u8, out: *[32]u8) void {
    Blake3.hash(contents, out, .{});
}

/// Mix what every embed of `embeds` contributes to a cache key: where its call
/// sits, the path spelled, the outcome and the content digest. Editing the file,
/// deleting it or making it unreadable each change the mix.
pub fn hashInto(hasher: anytype, embeds: []const source.Embed) void {
    var length: [8]u8 = undefined;
    std.mem.writeInt(u64, &length, embeds.len, .little);
    hasher.update(&length);
    for (embeds) |embed| {
        std.mem.writeInt(u64, &length, embed.path.len, .little);
        hasher.update(&length);
        hasher.update(embed.path);
        hasher.update(&.{@backingInt(embed.status)});
        hasher.update(&embed.digest);
    }
}

test "utf-8 validation reports the first offending byte" {
    try std.testing.expectEqual(@as(?usize, null), firstInvalidUtf8("héllo 🙂"));
    try std.testing.expectEqual(@as(?usize, 2), firstInvalidUtf8("ab\xffcd"));
    try std.testing.expectEqual(@as(?usize, 3), firstInvalidUtf8("abc\xe2\x82"));
    try std.testing.expectEqual(@as(?usize, 0), firstInvalidUtf8("\xc0\xaf"));
}

test "a relative target keeps a climb above the root as a leading parent" {
    const inside = try relativeTarget(std.testing.allocator, "lib/deep", "../assets/./x.txt");
    defer std.testing.allocator.free(inside);
    try std.testing.expectEqualStrings("lib/assets/x.txt", inside);
    const above = try relativeTarget(std.testing.allocator, "lib", "../../shared/y.bin");
    defer std.testing.allocator.free(above);
    try std.testing.expectEqualStrings("../shared/y.bin", above);
    try std.testing.expectEqual(source.EmbedStatus.absolute, spelledStatus("/etc/x").?);
    try std.testing.expectEqual(@as(?source.EmbedStatus, null), spelledStatus("a/b"));
}

test "a lexical join climbs with parent components and refuses to leave the filesystem" {
    const joined = (try lexicalJoin(std.testing.allocator, "/a/b", "./c/../d//e")).?;
    defer std.testing.allocator.free(joined);
    try std.testing.expectEqualStrings("/a/b/d/e", joined);
    try std.testing.expectEqual(@as(?[]u8, null), try lexicalJoin(std.testing.allocator, "/a", "../../x"));
    try std.testing.expect(within("/a/b", "/a/b/c"));
    try std.testing.expect(within("/a/b", "/a/b"));
    try std.testing.expect(!within("/a/b", "/a/bc"));
    try std.testing.expect(within("/", "/x"));
}
