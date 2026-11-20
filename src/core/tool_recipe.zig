//! The command lines `zig cc` runs for a unit and for a link, learned once from Zig and replayed without it.
//!
//! `zig cc -c unit.ll` is three processes: Zig's driver, which resolves the CPU and prepares a compilation; a child `zig clang`
//! that compiles; and a child `zig ld.lld -r` that relinks the child's single object. A `zig cc` link is Zig's driver, which hashes
//! every input into a cache manifest (every build gives it a fresh local cache, so the manifest is never reused), and then one
//! `zig ld.lld` that also starts a worker thread per CPU. The children's argument lists are what Zig derives from the driver's
//! arguments, the CPU and the libc stubs in its global cache, so for one toolchain and one set of arguments they are the same text
//! every time, and `ZIG_VERBOSE_CC` / `ZIG_VERBOSE_LINK` make Zig print them.
//!
//! A *recipe* is that text with the build's own files taken out: the unit, its object and the output of a compile, the objects and
//! the output of a link. It is stored once in the per-user runtime directory, keyed by the toolchain, the CPU and the driver's
//! arguments, and every later build starts the child directly: `zig clang <unit> <recipe> -c -o <object>` and
//! `zig ld.lld <recipe with the objects>`. The programs are the ones the driver would link (the linked bytes are equal, and the
//! tests state it); only the processes Zig put in between, and the linker's thread count, are gone.
//!
//! A recipe is a hint, never a verdict: the build that cannot use one (not stored, damaged, a file it names gone, a child that
//! fails) runs `zig cc` as it always did, and that run's output is what the build reports.
const std = @import("std");
const fast_blake3 = @import("fast_blake3.zig");
const process_spawn = @import("process_spawn.zig");

/// Digest of a recipe's inputs.
pub const Digest = [32]u8;

/// The directory of a runtime store that holds the recipes.
pub const directory_name = "tool-recipes-v1";

/// What a link recipe has in place of the output path.
pub const output_mark = "@output@";

/// What a link recipe has in place of the objects the build links.
pub const objects_mark = "@objects@";

/// The linker's worker threads. `ld.lld` starts one per CPU by default; on a link of a few hundred small objects the pool costs
/// more CPU than the second thread saves wall time (measured: 99k program 46 -> 29 ms CPU, +2 ms wall; 400k 145 -> 85 ms CPU,
/// +7 ms wall). The output does not depend on the count.
pub const link_threads = "--threads=2";

const magic = "selka-tool-recipe-v1\n";

/// The one token of a stored record that says Zig ran and its command line cannot be a recipe, so no build asks again.
const unusable = "@unusable@";
const kind_compile = "compile";
const kind_link = "link";

/// Which child a recipe starts.
pub const Kind = enum {
    compile,
    link,

    fn name(self: Kind) []const u8 {
        return switch (self) {
            .compile => kind_compile,
            .link => kind_link,
        };
    }
};

/// The digest a recipe is stored under: `kind`, the toolchain and CPU `identity`, and `shape`, the driver's arguments without the
/// files of the build. Fields are length-delimited.
pub fn key(kind: Kind, identity: Digest, shape: []const []const u8) Digest {
    var hash = fast_blake3.Blake3.init(.{});
    field(&hash, "core-tool-recipe-key-v1");
    field(&hash, kind.name());
    field(&hash, &identity);
    for (shape) |argument| field(&hash, argument);
    var digest: Digest = undefined;
    hash.final(&digest);
    return digest;
}

fn field(hash: *fast_blake3.Blake3, bytes: []const u8) void {
    var length: [8]u8 = undefined;
    std.mem.writeInt(u64, &length, bytes.len, .little);
    hash.update(&length);
    hash.update(bytes);
}

/// The stored form of a recipe: a magic line, its kind, one token per line, and the BLAKE3 digest of everything before it. No tokens
/// is the record that there is no recipe. A token that holds a newline cannot be stored, and the caller gets null.
pub fn encode(a: std.mem.Allocator, kind: Kind, tokens: []const []const u8) std.mem.Allocator.Error!?[]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(a);
    try out.appendSlice(a, magic);
    try out.appendSlice(a, kind.name());
    try out.append(a, '\n');
    if (tokens.len == 0) {
        try out.appendSlice(a, unusable ++ "\n");
    } else for (tokens) |token| {
        if (token.len == 0 or std.mem.indexOfScalar(u8, token, '\n') != null) return null;
        try out.appendSlice(a, token);
        try out.append(a, '\n');
    }
    var digest: Digest = undefined;
    fast_blake3.hash(out.items, &digest);
    try out.appendSlice(a, &digest);
    const bytes = try out.toOwnedSlice(a);
    return bytes;
}

/// The tokens of a stored recipe of `kind` (none: the record that there is no recipe), or null when `bytes` is not a record (a
/// different magic or kind, a cut or altered file).
pub fn decode(a: std.mem.Allocator, kind: Kind, bytes: []const u8) std.mem.Allocator.Error!?[]const []const u8 {
    if (bytes.len < magic.len + 32) return null;
    const body = bytes[0 .. bytes.len - 32];
    var digest: Digest = undefined;
    fast_blake3.hash(body, &digest);
    if (!std.mem.eql(u8, &digest, bytes[bytes.len - 32 ..])) return null;
    if (!std.mem.startsWith(u8, body, magic)) return null;
    var lines = std.mem.splitScalar(u8, body[magic.len..], '\n');
    if (!std.mem.eql(u8, lines.next() orelse return null, kind.name())) return null;
    var tokens: std.ArrayList([]const u8) = .empty;
    errdefer tokens.deinit(a);
    while (lines.next()) |line| {
        if (line.len == 0) {
            // Only the end of the last line leaves an empty remainder.
            if (lines.peek() != null) return null;
            break;
        }
        try tokens.append(a, try a.dupe(u8, line));
    }
    if (tokens.items.len == 0) return null;
    if (tokens.items.len == 1 and std.mem.eql(u8, tokens.items[0], unusable)) {
        tokens.deinit(a);
        return &.{};
    }
    const owned = try tokens.toOwnedSlice(a);
    return owned;
}

/// The stored recipe of `kind` under `digest` in `directory`: null when there is none or it is damaged, no tokens when a build found
/// that Zig's command line cannot be one.
pub fn load(a: std.mem.Allocator, io: std.Io, directory: []const u8, kind: Kind, digest: Digest) std.mem.Allocator.Error!?[]const []const u8 {
    const path = std.fs.path.join(a, &.{ directory, &std.fmt.bytesToHex(digest, .lower) }) catch return error.OutOfMemory;
    defer a.free(path);
    const bytes = std.Io.Dir.cwd().readFileAlloc(io, path, a, .limited(1 << 20)) catch |err| {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        return null;
    };
    defer a.free(bytes);
    return decode(a, kind, bytes);
}

/// Store `tokens` under `digest` in `directory`: written beside its place and renamed in, so a reader sees all of it or none. A
/// failed write loses only the saving.
pub fn store(a: std.mem.Allocator, io: std.Io, directory: []const u8, kind: Kind, digest: Digest, tokens: []const []const u8) std.mem.Allocator.Error!void {
    const bytes = (try encode(a, kind, tokens)) orelse return;
    defer a.free(bytes);
    const cwd = std.Io.Dir.cwd();
    cwd.createDirPath(io, directory) catch return;
    const path = try std.fs.path.join(a, &.{ directory, &std.fmt.bytesToHex(digest, .lower) });
    defer a.free(path);
    var nonce: [8]u8 = undefined;
    std.Io.random(io, &nonce);
    const staging = try std.fmt.allocPrint(a, "{s}.{s}.partial", .{ path, std.fmt.bytesToHex(nonce, .lower) });
    defer a.free(staging);
    cwd.writeFile(io, .{ .sub_path = staging, .data = bytes }) catch return;
    cwd.rename(staging, cwd, path, io) catch {
        removeStaged(io, staging);
        return;
    };
}

/// Best effort: a record written beside its place that could not be renamed in goes away.
fn removeStaged(io: std.Io, path: []const u8) void {
    std.Io.Dir.cwd().deleteFile(io, path) catch return;
}

/// The line of `text` that starts with `prefix`, the last such line when `last` is set and the first otherwise.
fn lineStarting(text: []const u8, prefix: []const u8, last: bool) ?[]const u8 {
    var found: ?[]const u8 = null;
    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |line| {
        if (!std.mem.startsWith(u8, line, prefix)) continue;
        found = line;
        if (!last) break;
    }
    return found;
}

fn tokenize(a: std.mem.Allocator, line: []const u8) std.mem.Allocator.Error!?[]const []const u8 {
    var tokens: std.ArrayList([]const u8) = .empty;
    errdefer tokens.deinit(a);
    var parts = std.mem.splitScalar(u8, line, ' ');
    while (parts.next()) |part| {
        // Zig joins the arguments with one space, so an empty token is an argument it could not have printed unambiguously.
        if (part.len == 0) return null;
        try tokens.append(a, part);
    }
    const owned = try tokens.toOwnedSlice(a);
    return owned;
}

/// A compile recipe from the `ZIG_VERBOSE_CC` output of `zig cc -c ... -o OUTPUT INPUT`: the child's arguments between its input
/// and its `-c -o <object>`. Null unless the line has exactly that shape and names no file of its own (an absolute path would be
/// one a later build cannot be sure exists).
pub fn compileTokens(a: std.mem.Allocator, verbose: []const u8, zig: []const u8, input: []const u8) std.mem.Allocator.Error!?[]const []const u8 {
    const prefix = try std.fmt.allocPrint(a, "{s} clang {s} ", .{ zig, input });
    defer a.free(prefix);
    const line = lineStarting(verbose, prefix, false) orelse return null;
    const tokens = (try tokenize(a, line)) orelse return null;
    if (tokens.len < 6) return null;
    if (!std.mem.eql(u8, tokens[tokens.len - 3], "-c") or !std.mem.eql(u8, tokens[tokens.len - 2], "-o")) return null;
    const middle = tokens[3 .. tokens.len - 3];
    for (middle) |token| if (token.len == 0 or token[0] == '/') return null;
    return middle;
}

/// The child `zig clang` command line of a compile recipe: the unit, the recipe, and `-c -o object`.
pub fn compileArguments(a: std.mem.Allocator, zig: []const u8, tokens: []const []const u8, input: []const u8, object: []const u8) std.mem.Allocator.Error![]const []const u8 {
    var argv: std.ArrayList([]const u8) = .empty;
    errdefer argv.deinit(a);
    try argv.appendSlice(a, &.{ zig, "clang", input });
    try argv.appendSlice(a, tokens);
    try argv.appendSlice(a, &.{ "-c", "-o", object });
    const owned = try argv.toOwnedSlice(a);
    return owned;
}

/// A link recipe from the `ZIG_VERBOSE_LINK` output of `zig cc ... -o OUTPUT OBJECTS...`: the last `ld.lld` line (the earlier ones
/// build Zig's own stubs), with the output path and the run of the build's objects replaced by `output_mark` and `objects_mark`.
/// Null unless the line holds the output after a `-o` and the objects as one run, in order.
pub fn linkTokens(a: std.mem.Allocator, verbose: []const u8, objects: []const []const u8, output: []const u8) std.mem.Allocator.Error!?[]const []const u8 {
    if (objects.len == 0) return null;
    const line = lineStarting(verbose, "ld.lld ", true) orelse return null;
    const tokens = (try tokenize(a, line)) orelse return null;
    var result: std.ArrayList([]const u8) = .empty;
    errdefer result.deinit(a);
    var at: usize = 1;
    var placed_output = false;
    var placed_objects = false;
    while (at < tokens.len) {
        const token = tokens[at];
        if (std.mem.eql(u8, token, "-o") and at + 1 < tokens.len and std.mem.eql(u8, tokens[at + 1], output)) {
            if (placed_output) return null;
            try result.appendSlice(a, &.{ token, output_mark });
            placed_output = true;
            at += 2;
            continue;
        }
        if (std.mem.eql(u8, token, objects[0])) {
            if (placed_objects or at + objects.len > tokens.len) return null;
            for (objects, tokens[at..][0..objects.len]) |expected, seen| if (!std.mem.eql(u8, expected, seen)) return null;
            try result.append(a, objects_mark);
            placed_objects = true;
            at += objects.len;
            continue;
        }
        if (std.mem.eql(u8, token, output_mark) or std.mem.eql(u8, token, objects_mark)) return null;
        try result.append(a, token);
        at += 1;
    }
    if (!placed_output or !placed_objects) return null;
    const owned = try result.toOwnedSlice(a);
    return owned;
}

/// The `zig ld.lld` command line of a link recipe: the thread count, the recipe, the output and the objects in their places.
pub fn linkArguments(a: std.mem.Allocator, zig: []const u8, tokens: []const []const u8, objects: []const []const u8, output: []const u8) std.mem.Allocator.Error![]const []const u8 {
    var argv: std.ArrayList([]const u8) = .empty;
    errdefer argv.deinit(a);
    try argv.appendSlice(a, &.{ zig, "ld.lld", link_threads });
    for (tokens) |token| {
        if (std.mem.eql(u8, token, output_mark)) {
            try argv.append(a, output);
        } else if (std.mem.eql(u8, token, objects_mark)) {
            try argv.appendSlice(a, objects);
        } else try argv.append(a, token);
    }
    const owned = try argv.toOwnedSlice(a);
    return owned;
}

/// Whether every file a link recipe names under `global_cache` (Zig's libc stubs and compiler-rt) still exists: a recipe outlives
/// the directory it was learned in only as long as Zig's builds are still there.
pub fn filesExist(io: std.Io, tokens: []const []const u8, global_cache: []const u8) bool {
    for (tokens) |token| {
        if (!std.mem.startsWith(u8, token, global_cache)) continue;
        std.Io.Dir.cwd().access(io, token, .{}) catch return false;
    }
    return true;
}

/// `text` without the lines Zig printed for `ZIG_VERBOSE_CC` and `ZIG_VERBOSE_LINK` (the `zig clang` and `ld.lld` command lines),
/// so a run made to learn a recipe reports what the same run without it would have.
pub fn withoutVerbose(a: std.mem.Allocator, text: []const u8, zig: []const u8) std.mem.Allocator.Error![]const u8 {
    const clang_prefix = try std.fmt.allocPrint(a, "{s} clang ", .{zig});
    defer a.free(clang_prefix);
    var kept: std.ArrayList(u8) = .empty;
    errdefer kept.deinit(a);
    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |line| {
        if (std.mem.startsWith(u8, line, "ld.lld ") or std.mem.startsWith(u8, line, clang_prefix)) continue;
        if (line.len == 0 and lines.peek() == null) continue;
        try kept.appendSlice(a, line);
        try kept.append(a, '\n');
    }
    const owned = try kept.toOwnedSlice(a);
    return owned;
}

/// What deriving a compile recipe needs.
pub const Probe = struct {
    arena: std.mem.Allocator,
    io: std.Io,
    /// The build's environment: Zig's cache directories are set in it.
    environment: *const std.process.Environ.Map,
    zig: []const u8,
    /// A private directory this build may write in.
    staging: []const u8,
};

/// The probe module: one function, so the compile and the backend both run.
const probe_module = "define i32 @probe() {\n  ret i32 0\n}\n";

/// What deriving a compile recipe found: whether Zig ran the probe to the end, and the recipe its command line gave.
pub const Derived = struct { ran: bool, tokens: ?[]const []const u8 = null };

/// Learn the compile recipe of `cc_arguments` (the driver's arguments between `zig cc` and `-o`): compile a one-function module
/// with them under `ZIG_VERBOSE_CC` and read the child's command line. `ran` is false when Zig failed (a failure may pass, so the
/// caller records nothing); `tokens` is null when it ran and printed no line of the shape `compileTokens` accepts.
pub fn deriveCompile(p: Probe, cc_arguments: []const []const u8) std.mem.Allocator.Error!Derived {
    const input = try std.fs.path.join(p.arena, &.{ p.staging, "recipe-probe.ll" });
    const object = try std.fs.path.join(p.arena, &.{ p.staging, "recipe-probe.o" });
    std.Io.Dir.cwd().writeFile(p.io, .{ .sub_path = input, .data = probe_module }) catch return .{ .ran = false };
    var environment = try p.environment.clone(p.arena);
    defer environment.deinit();
    try environment.put("ZIG_VERBOSE_CC", "1");
    var argv: std.ArrayList([]const u8) = .empty;
    try argv.appendSlice(p.arena, &.{ p.zig, "cc" });
    try argv.appendSlice(p.arena, cc_arguments);
    try argv.appendSlice(p.arena, &.{ "-o", object, input });
    const result = process_spawn.run(p.arena, p.io, .{ .argv = argv.items, .environment = .{ .map = &environment }, .die_with_parent = true }) catch |err| {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        return .{ .ran = false };
    };
    const succeeded = switch (result.term) {
        .exited => |code| code == 0,
        else => false,
    };
    if (!succeeded) return .{ .ran = false };
    return .{ .ran = true, .tokens = try compileTokens(p.arena, result.stderr, p.zig, input) };
}

test "a recipe survives its stored form and refuses a cut, altered or foreign one" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const tokens = [_][]const u8{ "--no-default-config", "-target", "x86_64-unknown-linux5.10.0-gnu2.31.0", "-O0" };
    const bytes = (try encode(a, .compile, &tokens)).?;
    const decoded = (try decode(a, .compile, bytes)).?;
    try std.testing.expectEqual(@as(usize, 4), decoded.len);
    try std.testing.expectEqualStrings("-target", decoded[1]);
    try std.testing.expect((try decode(a, .link, bytes)) == null);
    try std.testing.expect((try decode(a, .compile, bytes[0 .. bytes.len - 1])) == null);
    var altered = try a.dupe(u8, bytes);
    altered[magic.len + 10] ^= 1;
    try std.testing.expect((try decode(a, .compile, altered)) == null);
    try std.testing.expect((try decode(a, .compile, "")) == null);
    try std.testing.expect((try encode(a, .compile, &.{"two\nlines"})) == null);
    try std.testing.expect((try encode(a, .compile, &.{""})) == null);
    // No tokens is the record that Zig's command line cannot be a recipe.
    const none = (try encode(a, .link, &.{})).?;
    const nothing = (try decode(a, .link, none)).?;
    try std.testing.expectEqual(@as(usize, 0), nothing.len);
}

test "a compile recipe is what the child ran between its input and its output" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const verbose = "/opt/zig/zig clang /tmp/p/recipe-probe.ll --no-default-config -target x86_64-unknown-linux5.10.0-gnu2.31.0 -O0 -Xclang -target-cpu -Xclang alderlake -Wno-override-module -c -o /tmp/p/local/tmp/x.o\n";
    const tokens = (try compileTokens(a, verbose, "/opt/zig/zig", "/tmp/p/recipe-probe.ll")).?;
    try std.testing.expectEqualStrings("--no-default-config", tokens[0]);
    try std.testing.expectEqualStrings("-Wno-override-module", tokens[tokens.len - 1]);
    const argv = try compileArguments(a, "/opt/zig/zig", tokens, "unit.ll", "unit.o");
    try std.testing.expectEqualStrings("clang", argv[1]);
    try std.testing.expectEqualStrings("unit.ll", argv[2]);
    try std.testing.expectEqualStrings("-c", argv[argv.len - 3]);
    try std.testing.expectEqualStrings("unit.o", argv[argv.len - 1]);
    // Another line, an input that is not the probe's, an ending that is not `-c -o`, or a path of its own is no recipe.
    try std.testing.expect((try compileTokens(a, "something else\n", "/opt/zig/zig", "/tmp/p/recipe-probe.ll")) == null);
    try std.testing.expect((try compileTokens(a, verbose, "/opt/zig/zig", "/tmp/q.ll")) == null);
    try std.testing.expect((try compileTokens(a, "/opt/zig/zig clang /tmp/p/recipe-probe.ll -O0 -x ir -S -o /tmp/y.o\n", "/opt/zig/zig", "/tmp/p/recipe-probe.ll")) == null);
    try std.testing.expect((try compileTokens(a, "/opt/zig/zig clang /tmp/p/recipe-probe.ll -O0 -isystem /usr/include -Wno-override-module -c -o /tmp/y.o\n", "/opt/zig/zig", "/tmp/p/recipe-probe.ll")) == null);
}

test "a link recipe puts the output and the objects back where the driver's line had them" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const objects = [_][]const u8{ "/s/core_rt.o", "/s/u1.o", "/s/u2.o" };
    const stub = "ld.lld -r --error-limit=0 -o /g/crt1.o /g/start.o\n";
    const verbose = stub ++ "ld.lld --error-limit=0 --entry _start -o /w/program /g/crt1.o --dynamic-linker /lib64/ld-linux-x86-64.so.2 /s/core_rt.o /s/u1.o /s/u2.o --as-needed /g/libc.so.6\n";
    const tokens = (try linkTokens(a, verbose, &objects, "/w/program")).?;
    try std.testing.expectEqualStrings("--error-limit=0", tokens[0]);
    const replay = [_][]const u8{ "/s/core_rt.o", "/s/v1.o" };
    const argv = try linkArguments(a, "/opt/zig/zig", tokens, &replay, "/w2/program");
    try std.testing.expectEqualStrings("ld.lld", argv[1]);
    try std.testing.expectEqualStrings(link_threads, argv[2]);
    const joined = try std.mem.join(a, " ", argv[3..]);
    try std.testing.expectEqualStrings("--error-limit=0 --entry _start -o /w2/program /g/crt1.o --dynamic-linker /lib64/ld-linux-x86-64.so.2 /s/core_rt.o /s/v1.o --as-needed /g/libc.so.6", joined);
    // Objects out of order, a missing output, or no linker line at all are no recipe.
    const swapped = [_][]const u8{ "/s/core_rt.o", "/s/u2.o", "/s/u1.o" };
    try std.testing.expect((try linkTokens(a, verbose, &swapped, "/w/program")) == null);
    try std.testing.expect((try linkTokens(a, verbose, &objects, "/w/other")) == null);
    try std.testing.expect((try linkTokens(a, "nothing\n", &objects, "/w/program")) == null);
    try std.testing.expect((try linkTokens(a, verbose, &.{}, "/w/program")) == null);
}

test "a run made to learn a recipe reports what it would have without" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const stderr = "warning: one\nld.lld -r -o a b\n/opt/zig/zig clang x.ll -c -o y.o\nwarning: two\n";
    try std.testing.expectEqualStrings("warning: one\nwarning: two\n", try withoutVerbose(a, stderr, "/opt/zig/zig"));
    try std.testing.expectEqualStrings("", try withoutVerbose(a, "", "/opt/zig/zig"));
}

test "recipes are keyed by kind, toolchain and arguments and stored atomically" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const identity: Digest = @splat(1);
    const shape = [_][]const u8{ "-c", "-O0" };
    const base = key(.compile, identity, &shape);
    try std.testing.expect(!std.mem.eql(u8, &base, &key(.link, identity, &shape)));
    try std.testing.expect(!std.mem.eql(u8, &base, &key(.compile, @splat(2), &shape)));
    try std.testing.expect(!std.mem.eql(u8, &base, &key(.compile, identity, &.{ "-c", "-O3" })));
    try std.testing.expect(!std.mem.eql(u8, &key(.compile, identity, &.{ "ab", "c" }), &key(.compile, identity, &.{ "a", "bc" })));
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    const root = try directory.dir.realPathFileAlloc(std.testing.io, ".", a);
    const place = try std.fs.path.join(a, &.{ root, directory_name });
    try std.testing.expect((try load(a, std.testing.io, place, .compile, base)) == null);
    try store(a, std.testing.io, place, .compile, base, &.{ "-O0", "-target", "x" });
    const loaded = (try load(a, std.testing.io, place, .compile, base)).?;
    try std.testing.expectEqual(@as(usize, 3), loaded.len);
    try std.testing.expect((try load(a, std.testing.io, place, .link, base)) == null);
    try std.testing.expect(filesExist(std.testing.io, &.{ "-O0", "/nowhere/else" }, root));
    try std.testing.expect(!filesExist(std.testing.io, &.{ "-O0", try std.fs.path.join(a, &.{ root, "gone" }) }, root));
}

test "tokenize and deriveCompile say an allocation failure and a Zig that cannot start" {
    try std.testing.expectError(error.OutOfMemory, tokenize(std.testing.failing_allocator, "a b c"));
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    const root = try directory.dir.realPathFileAlloc(std.testing.io, ".", a);
    var environment: std.process.Environ.Map = .init(a);
    // A Zig that is not there did not run: the caller records nothing, so a later build may try again.
    const missing = try deriveCompile(.{ .arena = a, .io = std.testing.io, .environment = &environment, .zig = "/no/such/zig", .staging = root }, &.{"-c"});
    try std.testing.expect(!missing.ran);
    try std.testing.expect(missing.tokens == null);
    // A program that runs and prints no command line gives a run with no recipe, which a build records as such.
    const silent = try deriveCompile(.{ .arena = a, .io = std.testing.io, .environment = &environment, .zig = "/bin/true", .staging = root }, &.{"-c"});
    try std.testing.expect(silent.ran);
    try std.testing.expect(silent.tokens == null);
}
