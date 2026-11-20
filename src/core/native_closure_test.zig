//! Tests of the system closure (`native_closure.zig`): the loader cache reader in both layouts, the scan that holds
//! whatever the layout, the name comparison, the default directories, and the preload file. The captures that key these
//! files are tested in `tool_identity.zig` (GH-3b). The rule they hold: the keyed set is a superset of every file the
//! loader could load for a name.
const std = @import("std");
const closure = @import("native_closure.zig");
const t = std.testing;

fn contains(paths: []const []const u8, path: []const u8) bool {
    for (paths) |known| if (std.mem.eql(u8, known, path)) return true;
    return false;
}

const sample = [_]closure.Entry{
    .{ .name = "libc.so.6", .path = "/usr/lib/x86_64-linux-gnu/glibc-hwcaps/x86-64-v3/libc.so.6" },
    .{ .name = "libc.so.6", .path = "/usr/lib/x86_64-linux-gnu/libc.so.6" },
    // The 32-bit library of the same name is not one an x86-64 program loads.
    .{ .name = "libc.so.6", .path = "/usr/lib32/libc.so.6", .flags = 0x0003 },
    .{ .name = "libm.so.6", .path = "/usr/lib/x86_64-linux-gnu/libm.so.6" },
};

test "the loader cache parser lists every candidate of a name and refuses a truncated or foreign cache" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const bytes = try closure.render(a, &sample, false);
    const found = (try closure.candidates(a, bytes, "libc.so.6")).?;
    try t.expectEqual(@as(usize, 2), found.len);
    try t.expectEqualStrings("/usr/lib/x86_64-linux-gnu/glibc-hwcaps/x86-64-v3/libc.so.6", found[0]);
    try t.expectEqualStrings("/usr/lib/x86_64-linux-gnu/libc.so.6", found[1]);
    try t.expectEqual(@as(usize, 0), (try closure.candidates(a, bytes, "libgcc_s.so.1")).?.len);
    // A string that runs off the end, a table longer than the file, a header alone, an old table alone, big-endian.
    try t.expect((try closure.candidates(a, bytes[0 .. bytes.len - 1], "libc.so.6")) == null);
    try t.expect((try closure.candidates(a, bytes[0..60], "libc.so.6")) == null);
    try t.expect((try closure.candidates(a, bytes[0..20], "libc.so.6")) == null);
    try t.expect((try closure.candidates(a, "ld.so-1.7.0" ++ @as([45]u8, @splat(0)), "libc.so.6")) == null);
    const huge = try a.dupe(u8, bytes);
    std.mem.writeInt(u32, huge[20..24], std.math.maxInt(u32), .little);
    try t.expect((try closure.candidates(a, huge, "libc.so.6")) == null);
    const big = try a.dupe(u8, bytes);
    big[28] = 1;
    try t.expect((try closure.candidates(a, big, "libc.so.6")) == null);
}

// GH-3b review, R3: glibc before 2.32 writes the old table first and the new one after it.
test "a compat cache is read through the new-format block after the old table" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const bytes = try closure.render(a, &sample, true);
    try t.expect(std.mem.startsWith(u8, bytes, "ld.so-1.7.0"));
    const found = (try closure.candidates(a, bytes, "libc.so.6")).?;
    try t.expectEqual(@as(usize, 2), found.len);
    try t.expectEqualStrings("/usr/lib/x86_64-linux-gnu/libm.so.6", (try closure.candidates(a, bytes, "libm.so.6")).?[0]);
}

// GH-3b review, R3: whatever the layout, every absolute path in the cache whose last component is the name is keyed.
test "the scan of a cache it cannot parse finds every path that ends in the name" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const bytes = "unknown-cache-format\x00libc.so.6\x00/opt/odd/libc.so.6\x00\x01\x02/usr/lib32/libc.so.6\x00/opt/libc.so.60\x00";
    try t.expect((try closure.candidates(a, bytes, "libc.so.6")) == null);
    const found = try closure.scan(a, bytes, "libc.so.6");
    try t.expectEqual(@as(usize, 2), found.len);
    try t.expectEqualStrings("/opt/odd/libc.so.6", found[0]);
    try t.expectEqualStrings("/usr/lib32/libc.so.6", found[1]);
}

// GH-3b review, R6: the loader's cache compares runs of digits as numbers (`_dl_cache_libcmp`).
test "library names compare as the loader's cache compares them" {
    try t.expect(closure.sameLibrary("libgcc_s.so.01", "libgcc_s.so.1"));
    try t.expect(closure.sameLibrary("libc.so.6", "libc.so.6"));
    try t.expect(!closure.sameLibrary("libc.so.6", "libc.so.60"));
    try t.expect(!closure.sameLibrary("libc.so.6", "libc.so.6x"));
    try t.expect(!closure.sameLibrary("libm.so.6", "libc.so.6"));
}

// GH-3b review, R1 and R2: the default candidates are keyed whatever the cache says, hwcaps and legacy ones included.
test "every name keeps its default candidates whatever the cache says, and an unparsed cache is keyed" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = t.tmpDir(.{});
    defer temporary.cleanup();
    const root = try temporary.dir.realPathFileAlloc(t.io, ".", a);
    const none = try closure.resolve(a, t.io, root);
    try t.expect(none.cache_keyed);
    try temporary.dir.createDirPath(t.io, "etc");
    var entries: [closure.names.len]closure.Entry = undefined;
    for (closure.names, &entries) |name, *entry| entry.* = .{ .name = name, .path = try std.fs.path.join(a, &.{ "/opt/listed", name }) };
    try temporary.dir.writeFile(t.io, .{ .sub_path = "etc/ld.so.cache", .data = try closure.render(a, &entries, false) });
    const listed = try closure.resolve(a, t.io, root);
    try t.expect(!listed.cache_keyed);
    try t.expect(listed.unsound == null);
    try t.expect(contains(listed.files, try closure.below(a, root, "/lib64/ld-linux-x86-64.so.2")));
    try t.expect(contains(listed.files, try closure.below(a, root, "/opt/listed/libm.so.6")));
    for ([_][]const u8{
        "/usr/lib64/libc.so.6",
        "/lib/x86_64-linux-gnu/libgcc_s.so.1",
        "/usr/lib/libpthread.so.0",
        "/lib/libm.so.6",
        "/usr/lib/x86_64-linux-gnu/glibc-hwcaps/x86-64-v3/libc.so.6",
        "/lib64/tls/haswell/x86_64/libm.so.6",
        "/usr/lib/x86_64/libc.so.6",
    }) |path| try t.expect(contains(listed.files, try closure.below(a, root, path)));
    try t.expectEqual(1 + closure.names.len * (1 + closure.default_directories.len * closure.default_subdirectories.len), listed.files.len);
    try temporary.dir.writeFile(t.io, .{ .sub_path = "etc/ld.so.cache", .data = "glibc-ld.so.cache1.1 damaged" });
    try t.expect((try closure.resolve(a, t.io, root)).cache_keyed);
}

// GH-3b review, R4: glibc blanks from `#` to the end of a line and expands `$LIB` and `$PLATFORM`.
test "the preload file is read as glibc reads it: comments, separators, a bare name and expanded tokens" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const entries = try closure.preloadEntries(a, "/usr/lib/libjemalloc.so.2#ops\n# libcomment.so\n/a.so:/b.so\tlibhook.so\n/opt/${LIB}/$PLATFORM/x.so\n");
    try t.expectEqualStrings("/usr/lib/libjemalloc.so.2", entries[0]);
    try t.expectEqualStrings("/a.so", entries[1]);
    try t.expectEqualStrings("/b.so", entries[2]);
    try t.expectEqualStrings("libhook.so", entries[3]);
    try t.expectEqual(@as(usize, 4 + closure.lib_expansions.len * closure.platform_expansions.len), entries.len);
    try t.expect(contains(entries, "/opt/lib/x86_64-linux-gnu/haswell/x.so"));
    try t.expect(contains(entries, "/opt/lib64/xeon_phi/x.so"));
    var temporary = t.tmpDir(.{});
    defer temporary.cleanup();
    const root = try temporary.dir.realPathFileAlloc(t.io, ".", a);
    try temporary.dir.createDirPath(t.io, "etc");
    var listed: [1]closure.Entry = .{.{ .name = "libhook.so", .path = "/opt/libhook.so" }};
    try temporary.dir.writeFile(t.io, .{ .sub_path = "etc/ld.so.cache", .data = try closure.render(a, &listed, false) });
    try temporary.dir.writeFile(t.io, .{ .sub_path = "etc/ld.so.preload", .data = "/usr/local/lib/first.so:libhook.so # note\n" });
    const found = try closure.resolve(a, t.io, root);
    try t.expect(found.unsound == null);
    try t.expectEqualStrings(try closure.below(a, root, "/usr/local/lib/first.so"), found.preloaded[0]);
    try t.expectEqualStrings(try closure.below(a, root, "/opt/libhook.so"), found.preloaded[1]);
    // A bare name keeps its default candidates too.
    try t.expect(contains(found.preloaded, try closure.below(a, root, "/usr/lib64/libhook.so")));
    try temporary.dir.writeFile(t.io, .{ .sub_path = "etc/ld.so.preload", .data = "relative/x.so\n" });
    try t.expect((try closure.resolve(a, t.io, root)).unsound != null);
    try temporary.dir.writeFile(t.io, .{ .sub_path = "etc/ld.so.preload", .data = "$ORIGIN/x.so\n" });
    try t.expect((try closure.resolve(a, t.io, root)).unsound != null);
    try temporary.dir.writeFile(t.io, .{ .sub_path = "etc/ld.so.preload", .data = "/opt/$LIBRARY/x.so\n" });
    try t.expect((try closure.resolve(a, t.io, root)).unsound != null);
    try t.expectEqualStrings("/etc/ld.so.cache", try closure.below(a, "", "/etc/ld.so.cache"));
}

// GH-3b review, follow-up A: glibc 2.26 to 2.36 searches every combination of `tls`, a platform, `avx512_1` and `x86_64`.
test "the legacy subdirectories are every combination glibc searches, 24 per default directory" {
    try t.expectEqual(@as(usize, 24), closure.legacy_subdirectories.len);
    try t.expectEqual(@as(usize, 27), closure.default_subdirectories.len);
    try t.expectEqualStrings("tls/haswell/avx512_1/x86_64", closure.legacy_subdirectories[0]);
    try t.expectEqualStrings("", closure.legacy_subdirectories[23]);
    for ([_][]const u8{ "tls/xeon_phi/avx512_1/x86_64", "xeon_phi", "avx512_1", "tls/avx512_1", "haswell/x86_64", "tls" }) |wanted| {
        try t.expect(contains(&closure.legacy_subdirectories, wanted));
    }
}

/// The candidates the parser finds for `name` in a cache file of `test/fixtures/native-closure/`.
fn fixtureCandidates(a: std.mem.Allocator, file: []const u8, name: []const u8) !?[]const []const u8 {
    const path = try std.fs.path.join(a, &.{ "test/fixtures/native-closure", file });
    const bytes = try std.Io.Dir.cwd().readFileAlloc(t.io, path, a, .limited(1 << 20));
    return closure.candidates(a, bytes, name);
}

// GH-3b review, follow-up C: caches written by a real `ldconfig` (glibc 2.43, `-r ROOT -c compat` and `-c new`), for a
// root with libm and libgcc_s in a default directory and libpthread in `/opt/extra`, named by its `ld.so.conf`.
test "caches written by ldconfig in both layouts give the paths ldconfig -p prints" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    for ([_][]const u8{ "compat.ld.so.cache", "new.ld.so.cache" }) |file| {
        try t.expectEqualStrings("/usr/lib/x86_64-linux-gnu/libm.so.6", (try fixtureCandidates(a, file, "libm.so.6")).?[0]);
        try t.expectEqualStrings("/usr/lib/x86_64-linux-gnu/libgcc_s.so.1", (try fixtureCandidates(a, file, "libgcc_s.so.1")).?[0]);
        try t.expectEqualStrings("/opt/extra/libpthread.so.0", (try fixtureCandidates(a, file, "libpthread.so.0")).?[0]);
        try t.expectEqual(@as(usize, 0), (try fixtureCandidates(a, file, "libc.so.6")).?.len);
    }
}

// GH-3b review, follow-up D: an input this reader will not take whole turns reuse off instead of going unkeyed.
test "a cache over the size limit or a list past the candidate cap turns reuse off" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = t.tmpDir(.{});
    defer temporary.cleanup();
    const root = try temporary.dir.realPathFileAlloc(t.io, ".", a);
    try temporary.dir.createDirPath(t.io, "etc");
    // A sparse file: its size is asked, its bytes are never read.
    const huge = try temporary.dir.createFile(t.io, "etc/ld.so.cache", .{});
    try huge.setLength(t.io, closure.size_limit + 1);
    huge.close(t.io);
    const large = try closure.resolve(a, t.io, root);
    try t.expect(std.mem.indexOf(u8, large.unsound.?, "larger than 64 MiB") != null);
    var entries: std.ArrayList(closure.Entry) = .empty;
    for (0..closure.candidate_cap + 1) |index| try entries.append(a, .{ .name = "libc.so.6", .path = try std.fmt.allocPrint(a, "/opt/{d}/libc.so.6", .{index}) });
    try temporary.dir.writeFile(t.io, .{ .sub_path = "etc/ld.so.cache", .data = try closure.render(a, entries.items, false) });
    const crowded = try closure.resolve(a, t.io, root);
    try t.expect(std.mem.indexOf(u8, crowded.unsound.?, "candidate files") != null);
}

/// A hash that keeps what it is given, to see what the policy covers.
const Recorder = struct {
    bytes: std.ArrayList(u8) = .empty,

    pub fn update(self: *Recorder, more: []const u8) void {
        self.bytes.appendSlice(t.allocator, more) catch @panic("out of memory");
    }
};

// GH-3f: the hint of an inventory was keyed by the default directories but not by their subdirectories, so a hint that
// listed 565 inputs outlived the change to 949 and the identity moved at the next change of the loader cache.
test "the policy holds every default directory, every subdirectory and every name" {
    var recorder: Recorder = .{};
    defer recorder.bytes.deinit(t.allocator);
    closure.policy(&recorder);
    for (closure.default_directories ++ closure.default_subdirectories ++ closure.names ++ closure.lib_expansions ++ closure.platform_expansions) |text| {
        try t.expect(std.mem.indexOf(u8, recorder.bytes.items, text) != null);
    }
    for ([_][]const u8{ closure.loader, closure.cache_path, closure.preload_path, closure.rules_version }) |text| {
        try t.expect(std.mem.indexOf(u8, recorder.bytes.items, text) != null);
    }
    var again: Recorder = .{};
    defer again.bytes.deinit(t.allocator);
    closure.policy(&again);
    try t.expectEqualSlices(u8, recorder.bytes.items, again.bytes.items);
}

/// The name of the first constant of `native_closure.zig` that is neither a type, a function nor in `rule_names`, or null.
fn unlistedRule() ?[]const u8 {
    inline for (comptime std.meta.declarations(closure)) |name| {
        const kind = @typeInfo(@TypeOf(@field(closure, name)));
        if (kind != .type and kind != .@"fn" and comptime !std.mem.eql(u8, name, "rule_names")) {
            for (closure.rule_names) |rule| {
                if (std.mem.eql(u8, rule, name)) break;
            } else return name;
        }
    }
    return null;
}

// A constant added to `native_closure.zig` is a rule of the closure until a test says it is not: name it in `rule_names`.
test "every constant of the closure rules is in the policy" {
    try t.expectEqual(@as(?[]const u8, null), unlistedRule());
    for (closure.rule_names, 0..) |rule, index| for (closure.rule_names[index + 1 ..]) |other| try t.expect(!std.mem.eql(u8, rule, other));
}
