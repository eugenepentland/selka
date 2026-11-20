//! The system libraries a built program loads, found the way the loader finds them (GH-3b,
//! docs/audits/native-closure-keys-design-note-2026-11-19.md). The rule: the keyed set is a superset of every file the
//! loader could load for a name, because a file left out is a result reused under bytes it was not built with, and a
//! file too many is only a cold build now and then. A built program's interpreter is the loader at `loader`; it needs
//! the names in `names`. For each name the closure holds every file the loader's cache maps it to (read from the cache's
//! table when this reader understands it, and in any case every NUL-terminated absolute path in the cache's bytes whose
//! last component is the name), and every candidate in the loader's default directories with their hwcaps and legacy
//! subdirectories, whatever the cache says, since the loader falls back to them when a listed file cannot be opened. The
//! files `/etc/ld.so.preload` names join the same way. A cache this reader cannot parse is keyed by its bytes too. Nothing
//! here fails: a file that cannot be read is one the loader cannot load either, and the caller keys it as unreadable.
const std = @import("std");

/// The interpreter path Zig writes into every dynamically linked x86-64 glibc program.
pub const loader = "/lib64/ld-linux-x86-64.so.2";
/// The libraries a built program needs (its `DT_NEEDED` names and the one glibc loads for unwinding).
pub const names = [_][]const u8{ "libc.so.6", "libm.so.6", "libgcc_s.so.1", "libpthread.so.0" };
/// The loader's cache of library names.
pub const cache_path = "/etc/ld.so.cache";
/// The file of libraries the loader loads into every program.
pub const preload_path = "/etc/ld.so.preload";
/// Where the x86-64 loader looks for a name its cache does not give it: the upstream directories, Debian's multiarch ones,
/// and `/lib` and `/usr/lib`, which this machine's `ld.so --help` also lists.
pub const default_directories = [_][]const u8{ "/lib64", "/usr/lib64", "/lib/x86_64-linux-gnu", "/usr/lib/x86_64-linux-gnu", "/lib", "/usr/lib" };
/// The legacy subdirectories glibc 2.26 to 2.36 searches below each default directory: every combination, most specific
/// first, of the optional parts `tls`, one platform (`haswell` or `xeon_phi`), the `avx512_1` hwcap and `x86_64`, the
/// empty one (the directory itself) last. 2 x 3 x 2 x 2 = 24.
pub const legacy_subdirectories = legacy: {
    var list: [24][]const u8 = undefined;
    var count = 0;
    for ([_]bool{ true, false }) |tls| for ([_][]const u8{ "haswell", "xeon_phi", "" }) |platform| for ([_]bool{ true, false }) |avx| for ([_]bool{ true, false }) |x86| {
        var path: []const u8 = "";
        if (tls) path = path ++ "/tls";
        if (platform.len != 0) path = path ++ "/" ++ platform;
        if (avx) path = path ++ "/avx512_1";
        if (x86) path = path ++ "/x86_64";
        list[count] = if (path.len == 0) "" else path[1..];
        count += 1;
    };
    const final = list;
    break :legacy final;
};
/// The subdirectories of each default directory the loader searches: the glibc-hwcaps levels (glibc 2.33 and later),
/// then the legacy ones, which end with the directory itself.
pub const default_subdirectories = [_][]const u8{ "glibc-hwcaps/x86-64-v4", "glibc-hwcaps/x86-64-v3", "glibc-hwcaps/x86-64-v2" } ++ legacy_subdirectories;
/// More candidate files than this in one list is a cache or preload file no real machine has (a hostile one could make
/// the list quadratic to build): reuse is off instead.
pub const candidate_cap = 4096;
/// What `$LIB` in a preload entry can expand to on x86-64.
pub const lib_expansions = [_][]const u8{ "lib", "lib64", "lib/x86_64-linux-gnu" };
/// What `$PLATFORM` can expand to.
pub const platform_expansions = [_][]const u8{ "x86_64", "haswell", "xeon_phi" };
/// Files larger than this are not read whole: a cache or a preload file that large turns reuse off.
pub const size_limit = 64 << 20;

const magic = "glibc-ld.so.cache1.1";
const old_magic = "ld.so-1.7.0";
const header_size = 48;
const entry_size = 24;
const old_header_size = 16;
const old_entry_size = 12;
/// `FLAG_ELF_LIBC6` in the type byte and `FLAG_X8664_LIB64` in the architecture byte.
const libc6_type: u32 = 0x03;
const x86_64_architecture: u32 = 0x0300;

/// Changed by hand when `resolve`, `gather` or `locate` come to list other candidates without a constant here changing
/// (a new source of candidates, another way to read the cache): it is one of the rules `policy` hashes.
pub const rules_version = "1";

/// The names of every constant this file makes the closure's candidate list from, in a fixed order. `policy` hashes them
/// all into the key of an inventory hint, because a hint lists the candidates the compiler that wrote it looked at: on
/// 19 November 2026 a hint made when each default directory had 11 subdirectories (565 inputs) was still read by a
/// compiler that has 27 (949 inputs), and the toolchain identity moved at the next change of `/etc/ld.so.cache`, which
/// made the inventory afresh. A constant added to this file that the list below does not name fails the test "every
/// constant of the closure rules is in the policy".
pub const rule_names = [_][]const u8{
    "rules_version",   "loader",              "names",                 "cache_path",
    "preload_path",    "default_directories", "legacy_subdirectories", "default_subdirectories",
    "candidate_cap",   "lib_expansions",      "platform_expansions",   "size_limit",
    "magic",           "old_magic",           "header_size",           "entry_size",
    "old_header_size", "old_entry_size",      "libc6_type",            "x86_64_architecture",
    "tokens",
};

/// Hash every rule of the closure (`rule_names`) into `hash`, anything with an `update(bytes)`: a change of any rule is a
/// change of the key a hint is stored under.
pub fn policy(hash: anytype) void {
    frame(hash, "native-closure-rules-v1");
    inline for (rule_names) |name| {
        frame(hash, name);
        frameValue(hash, @field(@This(), name));
    }
}

fn frame(hash: anytype, bytes: []const u8) void {
    frameCount(hash, bytes.len);
    hash.update(bytes);
}

fn frameCount(hash: anytype, count: usize) void {
    var length: [8]u8 = undefined;
    std.mem.writeInt(u64, &length, count, .little);
    hash.update(&length);
}

/// A constant of the rules, whatever it is made of: a number, text, a list of them, or a record of them.
fn frameValue(hash: anytype, value: anytype) void {
    switch (@typeInfo(@TypeOf(value))) {
        .comptime_int, .int => frameCount(hash, value),
        .pointer => frameItems(hash, value),
        .array => frameItems(hash, &value),
        .@"struct" => inline for (comptime std.meta.fieldNames(@TypeOf(value))) |name| frameValue(hash, @field(value, name)),
        else => @compileError("a rule of the closure is text, a number, or a list or record of them"),
    }
}

/// Text as it is, any other list with its length and then each item.
fn frameItems(hash: anytype, items: anytype) void {
    if (@TypeOf(items[0]) == u8) return frame(hash, items);
    frameCount(hash, items.len);
    for (items) |item| frameValue(hash, item);
}

/// The closure of one machine (or of a test's system root).
pub const Closure = struct {
    /// The loader and every candidate of every name, below the root, without repeats.
    files: []const []const u8,
    /// The files `/etc/ld.so.preload` names, resolved like `names`, below the root.
    preloaded: []const []const u8,
    /// The cache could not be parsed: its bytes are keyed as well.
    cache_keyed: bool,
    /// Why the closure cannot be keyed soundly (a preload entry with a relative path or an unknown `$` token, or a
    /// preload file too large to read), or null. Reuse is off while it is set.
    unsound: ?[]const u8,
};

/// Every path the cache in `bytes` maps `name` to for x86-64 libc6, in the cache's order; null when `bytes` holds no
/// table this reader understands. The new format is read at the start of the file, or after the old format's table
/// (glibc before 2.32 writes both). Every read is bounds-checked.
pub fn candidates(arena: std.mem.Allocator, bytes: []const u8, name: []const u8) error{OutOfMemory}!?[]const []const u8 {
    const base = newFormatOffset(bytes) orelse return null;
    const block = bytes[base..];
    if (block.len < header_size or !std.mem.startsWith(u8, block, magic)) return null;
    const count = std.mem.readInt(u32, block[20..24], .little);
    // Byte 28 says how the file was written: 0 (unset) or 2 (little-endian) are the only ones this host reads.
    if (block[28] != 0 and block[28] != 2) return null;
    const table = std.math.mul(usize, count, entry_size) catch return null;
    const end = std.math.add(usize, header_size, table) catch return null;
    if (end > block.len) return null;
    var found: std.ArrayList([]const u8) = .empty;
    for (0..count) |index| {
        const entry = block[header_size + index * entry_size ..][0..entry_size];
        const flags = std.mem.readInt(u32, entry[0..4], .little);
        // In the new format, string offsets count from the start of its own block.
        const key = text(block, std.mem.readInt(u32, entry[4..8], .little)) orelse return null;
        const value = text(block, std.mem.readInt(u32, entry[8..12], .little)) orelse return null;
        if (flags & 0xff != libc6_type or flags & 0xff00 != x86_64_architecture) continue;
        if (!sameLibrary(key, name) or !std.fs.path.isAbsolute(value)) continue;
        try found.append(arena, value);
    }
    return found.items;
}

/// Where the new-format block starts: 0, or after the old format's table, aligned to 8 as glibc's `ALIGN_CACHE`.
fn newFormatOffset(bytes: []const u8) ?usize {
    if (!std.mem.startsWith(u8, bytes, old_magic)) return 0;
    if (bytes.len < old_header_size) return null;
    const count = std.mem.readInt(u32, bytes[12..16], .little);
    const table = std.math.mul(usize, count, old_entry_size) catch return null;
    const end = std.math.add(usize, old_header_size, table) catch return null;
    const aligned = std.mem.alignForward(usize, end, 8);
    return if (aligned <= bytes.len) aligned else null;
}

/// Every NUL-terminated absolute path in `bytes` whose last component is `name`: the floor that holds whatever the
/// cache's format is.
pub fn scan(arena: std.mem.Allocator, bytes: []const u8, name: []const u8) error{OutOfMemory}![]const []const u8 {
    var found: std.ArrayList([]const u8) = .empty;
    var pieces = std.mem.splitScalar(u8, bytes, 0);
    while (pieces.next()) |piece| {
        const start = std.mem.indexOfScalar(u8, piece, '/') orelse continue;
        const path = piece[start..];
        if (!sameLibrary(std.fs.path.basename(path), name)) continue;
        try found.append(arena, path);
        // One more than the cap is enough for the caller to refuse the list.
        if (found.items.len > candidate_cap) break;
    }
    return found.items;
}

/// Whether two library names are the same name to the loader's cache (`_dl_cache_libcmp`): runs of digits compare as
/// numbers, so `libgcc_s.so.01` is `libgcc_s.so.1`.
pub fn sameLibrary(left: []const u8, right: []const u8) bool {
    var i: usize = 0;
    var j: usize = 0;
    while (i < left.len and j < right.len) {
        if (!std.ascii.isDigit(left[i]) or !std.ascii.isDigit(right[j])) {
            if (left[i] != right[j]) return false;
            i += 1;
            j += 1;
            continue;
        }
        var a: u64 = 0;
        while (i < left.len and std.ascii.isDigit(left[i])) : (i += 1) a = a *| 10 +| (left[i] - '0');
        var b: u64 = 0;
        while (j < right.len and std.ascii.isDigit(right[j])) : (j += 1) b = b *| 10 +| (right[j] - '0');
        if (a != b) return false;
    }
    return i == left.len and j == right.len;
}

/// The NUL-terminated string at `offset` of `bytes`, or null when it does not end inside them.
fn text(bytes: []const u8, offset: u32) ?[]const u8 {
    if (offset >= bytes.len) return null;
    const length = std.mem.indexOfScalar(u8, bytes[offset..], 0) orelse return null;
    return bytes[offset..][0..length];
}

/// The closure below `root` ("" for the machine itself; a test's directory otherwise).
pub fn resolve(arena: std.mem.Allocator, io: std.Io, root: []const u8) error{OutOfMemory}!Closure {
    const cache_file = try below(arena, root, cache_path);
    // The loader still reads a cache this reader will not: what it maps the names to would be unkeyed. The size is
    // asked first, so a huge cache is never read into memory.
    const size = if (std.Io.Dir.cwd().statFile(io, cache_file, .{})) |info| info.size else |_| 0;
    const too_large = size > size_limit;
    const cache: ?[]const u8 = if (too_large) null else std.Io.Dir.cwd().readFileAlloc(io, cache_file, arena, .limited(size_limit)) catch |err| cache: {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        break :cache null;
    };
    const parsed = if (cache) |bytes| (try candidates(arena, bytes, names[0])) != null else false;
    var files: std.ArrayList([]const u8) = .empty;
    var preloaded: std.ArrayList([]const u8) = .empty;
    const unsound = gather(arena, io, root, cache, &files, &preloaded) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.TooMany => try std.fmt.allocPrint(arena, "the loader cache or the preload file names more than {d} candidate files", .{candidate_cap}),
    };
    const why: ?[]const u8 = if (too_large) "/etc/ld.so.cache is larger than 64 MiB" else unsound;
    return .{ .files = files.items, .preloaded = preloaded.items, .cache_keyed = !parsed, .unsound = why };
}

/// The errors of building a candidate list: allocation, or a list past `candidate_cap`.
const GatherError = error{ OutOfMemory, TooMany };

fn gather(arena: std.mem.Allocator, io: std.Io, root: []const u8, cache: ?[]const u8, files: *std.ArrayList([]const u8), preloaded: *std.ArrayList([]const u8)) GatherError!?[]const u8 {
    try add(arena, files, try below(arena, root, loader));
    for (names) |name| try locate(arena, root, cache, name, files);
    return preload(arena, io, root, cache, preloaded);
}

/// Add every candidate of `name` to `files`: what the cache maps it to, what its bytes name, and the default ones.
fn locate(arena: std.mem.Allocator, root: []const u8, cache: ?[]const u8, name: []const u8, files: *std.ArrayList([]const u8)) GatherError!void {
    if (cache) |bytes| {
        for ((try candidates(arena, bytes, name)) orelse &.{}) |path| try add(arena, files, try below(arena, root, path));
        for (try scan(arena, bytes, name)) |path| try add(arena, files, try below(arena, root, path));
    }
    for (default_directories) |directory| for (default_subdirectories) |subdirectory| {
        try add(arena, files, try below(arena, root, try std.fs.path.join(arena, &.{ directory, subdirectory, name })));
    };
}

/// Add the files the preload file names to `files`; why they cannot be keyed soundly, or null.
fn preload(arena: std.mem.Allocator, io: std.Io, root: []const u8, cache: ?[]const u8, files: *std.ArrayList([]const u8)) GatherError!?[]const u8 {
    const path = try below(arena, root, preload_path);
    const bytes = std.Io.Dir.cwd().readFileAlloc(io, path, arena, .limited(size_limit)) catch |err| {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        if (err == error.StreamTooLong) return "/etc/ld.so.preload is larger than 64 MiB";
        // A preload file the loader cannot open preloads nothing.
        return null;
    };
    for (try preloadEntries(arena, bytes)) |entry| {
        if (std.mem.indexOfScalar(u8, entry, '$') != null) {
            const why = try std.fmt.allocPrint(arena, "/etc/ld.so.preload names `{s}`, whose `$` token cannot be expanded", .{entry});
            return why;
        }
        if (std.mem.indexOfScalar(u8, entry, '/') == null) {
            try locate(arena, root, cache, entry, files);
        } else if (std.fs.path.isAbsolute(entry)) {
            try add(arena, files, try below(arena, root, entry));
        } else {
            const why = try std.fmt.allocPrint(arena, "/etc/ld.so.preload names the relative path `{s}`", .{entry});
            return why;
        }
    }
    return null;
}

/// The entries of a preload file as glibc reads it: each line blanked from `#` to its end, then split at blanks, tabs,
/// newlines and colons, and `$LIB`, `$PLATFORM` (or `${LIB}`, `${PLATFORM}`) expanded to every value they can have here.
pub fn preloadEntries(arena: std.mem.Allocator, bytes: []const u8) error{OutOfMemory}![]const []const u8 {
    var entries: std.ArrayList([]const u8) = .empty;
    var lines = std.mem.splitScalar(u8, bytes, '\n');
    while (lines.next()) |line| {
        const kept = line[0 .. std.mem.indexOfScalar(u8, line, '#') orelse line.len];
        var words = std.mem.tokenizeAny(u8, kept, " \t\r:");
        while (words.next()) |word| try expand(arena, word, &entries);
    }
    return entries.items;
}

const Token = struct { name: []const u8, values: []const []const u8 };
const tokens = [_]Token{
    .{ .name = "${LIB}", .values = &lib_expansions },
    .{ .name = "$LIB", .values = &lib_expansions },
    .{ .name = "${PLATFORM}", .values = &platform_expansions },
    .{ .name = "$PLATFORM", .values = &platform_expansions },
};

/// Add `word` with its first `$LIB` or `$PLATFORM` token replaced by each value, recursively; a word with no such token
/// as it is (an unknown `$` token stays, and the caller refuses it).
fn expand(arena: std.mem.Allocator, word: []const u8, entries: *std.ArrayList([]const u8)) error{OutOfMemory}!void {
    for (tokens) |token| {
        const at = std.mem.indexOf(u8, word, token.name) orelse continue;
        // `$LIBRARY` is not `$LIB` followed by text: the unknown token stays, and the caller refuses it.
        const after = at + token.name.len;
        const braced = token.name[1] == '{';
        if (!braced and after < word.len and (std.ascii.isAlphanumeric(word[after]) or word[after] == '_')) continue;
        for (token.values) |value| try expand(arena, try std.mem.concat(arena, u8, &.{ word[0..at], value, word[at + token.name.len ..] }), entries);
        return;
    }
    try entries.append(arena, word);
}

fn add(arena: std.mem.Allocator, files: *std.ArrayList([]const u8), path: []const u8) GatherError!void {
    for (files.items) |known| if (std.mem.eql(u8, known, path)) return;
    if (files.items.len >= candidate_cap) return error.TooMany;
    try files.append(arena, path);
}

/// `path` below `root`; `path` itself when `root` is empty.
pub fn below(arena: std.mem.Allocator, root: []const u8, path: []const u8) error{OutOfMemory}![]const u8 {
    if (root.len == 0) return path;
    return std.mem.concat(arena, u8, &.{ std.mem.trimEnd(u8, root, "/"), if (std.fs.path.isAbsolute(path)) "" else "/", path });
}

/// One entry of a cache `render` writes.
pub const Entry = struct { name: []const u8, path: []const u8, flags: u32 = libc6_type | x86_64_architecture };

/// A loader cache in the format `candidates` reads, holding `entries`; with `compat`, preceded by an old-format table
/// as glibc before 2.32 writes it. For tests and fixtures, which must not depend on the machine's own cache.
pub fn render(arena: std.mem.Allocator, entries: []const Entry, compat: bool) error{OutOfMemory}![]const u8 {
    var bytes: std.ArrayList(u8) = .empty;
    if (compat) {
        try bytes.appendSlice(arena, old_magic);
        try bytes.appendNTimes(arena, 0, old_header_size - old_magic.len);
        std.mem.writeInt(u32, bytes.items[12..16], @intCast(entries.len), .little);
        // The old entries' string offsets are not read here; they stay zero.
        try bytes.appendNTimes(arena, 0, entries.len * old_entry_size);
        try bytes.appendNTimes(arena, 0, std.mem.alignForward(usize, bytes.items.len, 8) - bytes.items.len);
    }
    const base = bytes.items.len;
    var strings: std.ArrayList(u8) = .empty;
    const start = header_size + entries.len * entry_size;
    try bytes.appendSlice(arena, magic);
    try bytes.appendNTimes(arena, 0, header_size - magic.len);
    std.mem.writeInt(u32, bytes.items[base + 20 ..][0..4], @intCast(entries.len), .little);
    bytes.items[base + 28] = 2;
    for (entries) |entry| {
        var record: [entry_size]u8 = @splat(0);
        std.mem.writeInt(u32, record[0..4], entry.flags, .little);
        std.mem.writeInt(u32, record[4..8], @intCast(start + strings.items.len), .little);
        try strings.appendSlice(arena, entry.name);
        try strings.append(arena, 0);
        std.mem.writeInt(u32, record[8..12], @intCast(start + strings.items.len), .little);
        try strings.appendSlice(arena, entry.path);
        try strings.append(arena, 0);
        try bytes.appendSlice(arena, &record);
    }
    std.mem.writeInt(u32, bytes.items[base + 24 ..][0..4], @intCast(strings.items.len), .little);
    try bytes.appendSlice(arena, strings.items);
    return bytes.items;
}
