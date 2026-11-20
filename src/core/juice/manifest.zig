//! Strict experiment contracts and source/input inventories.
const std = @import("std");
const key_stdout_sha256 = "stdout_sha256";
const key_stdout_regex = "stdout_regex";
const d = @import("data.zig");
const p = @import("platform.zig");
const toml = @import("toml.zig");
const C = d.Context;
const V = d.Value;
/// Parsed workload with separate mutable-source and fixed-input identities.
pub const Manifest = struct { data: V, root: []const u8, sources: V, inputs: V };
fn keys(c: *C, v: V, allowed: []const u8) !void {
    for (try d.keys(c, v)) |key| {
        var found = false;
        var words = std.mem.tokenizeScalar(u8, allowed, ' ');
        while (words.next()) |word| if (std.mem.eql(u8, key, word)) {
            found = true;
            break;
        };
        if (!found) return c.fail(try std.fmt.allocPrint(c.a, "unknown manifest field: {s}", .{key}));
    }
}
fn strings(v: V, nonempty: bool) !void {
    const rows = try d.items(v);
    if (nonempty and rows.len == 0) return error.InvalidExperiment;
    for (rows) |s| if ((try d.str(s)).len == 0) return error.InvalidExperiment;
}
/// Glob matcher with path-aware star, recursive double-star, question and simple ranges.
pub fn matches(pattern: []const u8, path: []const u8) bool {
    var a: usize = 0;
    var b: usize = 0;
    while (a < pattern.len) {
        if (pattern[a] == '*') {
            const recursive = a + 1 < pattern.len and pattern[a + 1] == '*';
            a += if (recursive) @as(usize, 2) else 1;
            if (recursive and a < pattern.len and pattern[a] == '/' and matches(pattern[a + 1 ..], path[b..])) return true;
            while (true) {
                if (matches(pattern[a..], path[b..])) return true;
                if (b == path.len or (!recursive and path[b] == '/')) return false;
                b += 1;
            }
        }
        if (b == path.len) return false;
        if (pattern[a] == '?') {
            if (path[b] == '/') return false;
        } else if (pattern[a] == '[') {
            const end = std.mem.indexOfScalarPos(u8, pattern, a + 1, ']') orelse return false;
            var i = a + 1;
            var matched = false;
            while (i < end) {
                if (i + 2 < end and pattern[i + 1] == '-') {
                    matched = matched or (path[b] >= pattern[i] and path[b] <= pattern[i + 2]);
                    i += 3;
                } else {
                    matched = matched or path[b] == pattern[i];
                    i += 1;
                }
            }
            if (!matched) return false;
            a = end;
        } else if (pattern[a] != path[b]) return false;
        a += 1;
        b += 1;
    }
    return b == path.len;
}
fn inventory(c: *C, root: []const u8, patterns: V) !V {
    var result = d.object();
    for (try d.items(patterns)) |pattern| {
        const glob = try d.str(pattern);
        try d.relative(glob);
        var count: usize = 0;
        if (std.mem.indexOfAny(u8, glob, "*?[") == null) {
            const file = try p.inside(c, root, glob);
            try d.put(c, &result, glob, try c.fileHash(file));
            continue;
        }
        var directory = try std.Io.Dir.cwd().openDir(c.io, root, .{ .iterate = true });
        defer directory.close(c.io);
        var walker = try directory.walk(c.a);
        defer walker.deinit();
        while (try walker.next(c.io)) |entry| {
            if (entry.kind != .file and entry.kind != .sym_link) continue;
            if (matches(glob, entry.path)) {
                const file = try p.inside(c, root, entry.path);
                try d.put(c, &result, try c.a.dupe(u8, entry.path), try c.fileHash(file));
                count += 1;
            }
        }
        if (count == 0) return c.fail("declared source or input matches no files");
    }
    return result;
}
fn checkBuild(c: *C, manifest: *Manifest) !void {
    var build = try d.req(manifest.data, "build");
    try keys(c, build, "command compiler entry flags prefix dependencies tools timeout_seconds counter_semantics");
    try d.default(c, &build, d.key_timeout_seconds, .{ .integer = 300 });
    _ = try d.positive(d.get(build, d.key_timeout_seconds));
    for ([_][]const u8{ "flags", "prefix", "dependencies", "tools" }) |key| {
        try d.default(c, &build, key, d.array(c));
        try strings(d.get(build, key), false);
    }
    if (d.is(d.get(manifest.data, "adapter"), "native")) {
        const argv = try d.req(build, "command");
        try strings(argv, true);
        var output = false;
        for (try d.items(argv)) |arg| if (std.mem.indexOf(u8, try d.str(arg), "{binary}") != null) {
            output = true;
        };
        if (!output) return c.fail("build.command must write {binary}");
        if (d.is(argv.array.items[0], "{compiler}")) _ = try d.str(try d.req(build, "compiler"));
    } else {
        if (d.get(build, "command") != .null) return c.fail("selka build commands are generated; use entry and flags");
        try d.default(c, &build, "compiler", d.string("selka"));
        const entry = try d.str(try d.req(build, "entry"));
        if (d.get(manifest.sources, entry) == .null) return c.fail("build.entry must be a declared source");
        if ((try d.str(try d.req(build, "counter_semantics"))).len == 0) return c.fail("selka needs an explicit counter_semantics contract");
        for (try d.items(d.get(build, "flags"))) |flag| {
            const f = try d.str(flag);
            const key = f[0 .. std.mem.indexOfScalar(u8, f, '=') orelse f.len];
            if (std.mem.startsWith(u8, f, "-o")) return error.InvalidExperiment;
            for ([_][]const u8{ "--counters", "--debug", "--output", "--run" }) |reserved| if (std.mem.eql(u8, key, reserved)) return c.fail("flags cannot override output, release mode or instrumentation");
        }
    }
    try d.put(c, &manifest.data, "build", build);
}
fn workload(c: *C, w: *V, names: *V) !void {
    try keys(c, w.*, "name family tier args units unit timeout_seconds expected_stdout stdout_sha256 stdout_regex expected_stderr exit_code check outputs region weight");
    const name = try d.str(try d.req(w.*, "name"));
    if (!d.identifier(name) or names.object.contains(name)) return c.fail("workload names must be unique simple identifiers");
    try d.put(c, names, name, .null);
    try d.default(c, w, "family", d.string(name));
    if ((try d.str(d.get(w.*, "family"))).len == 0) return error.InvalidExperiment;
    try d.default(c, w, "tier", d.string("quick"));
    if (!d.is(d.get(w.*, "tier"), "quick") and !d.is(d.get(w.*, "tier"), "validation")) return error.InvalidExperiment;
    if ((try d.str(try d.req(w.*, "unit"))).len == 0) return error.InvalidExperiment;
    _ = try d.positive(try d.req(w.*, "units"));
    try d.default(c, w, "weight", .{ .integer = 1 });
    try d.default(c, w, d.key_timeout_seconds, .{ .integer = 30 });
    _ = try d.positive(d.get(w.*, "weight"));
    _ = try d.positive(d.get(w.*, d.key_timeout_seconds));
    for ([_][]const u8{ "args", "check", "outputs" }) |key| {
        try d.default(c, w, key, d.array(c));
        try strings(d.get(w.*, key), false);
    }
    for (try d.items(d.get(w.*, "outputs"))) |path| try d.relative(try d.str(path));
    const has_oracle = d.get(w.*, "expected_stdout") != .null or d.get(w.*, key_stdout_sha256) != .null or (try d.items(d.get(w.*, "check"))).len > 0;
    if (!has_oracle) return c.fail("every workload requires a correctness oracle");
    try d.default(c, w, "expected_stderr", d.string(""));
    for ([_][]const u8{ "expected_stdout", "expected_stderr", key_stdout_sha256, key_stdout_regex, "region" }) |key| if (d.get(w.*, key) != .null) {
        _ = try d.str(d.get(w.*, key));
    };
    if (d.get(w.*, key_stdout_sha256) != .null) {
        const sha = try d.str(d.get(w.*, key_stdout_sha256));
        if (sha.len != 64) return error.InvalidExperiment;
        for (sha) |ch| if (!std.ascii.isDigit(ch) and (ch < 'a' or ch > 'f')) return error.InvalidExperiment;
    }
    try d.default(c, w, d.key_exit_code, .{ .integer = 0 });
    if (d.get(w.*, d.key_exit_code) != .integer or d.get(w.*, d.key_exit_code).integer != 0) return c.fail("workloads must complete successfully (exit_code = 0)");
    if (d.get(w.*, "region") != .null and (try d.str(d.get(w.*, "region"))).len == 0) return error.InvalidExperiment;
    if (d.get(w.*, key_stdout_regex) != .null) try @import("normalize.zig").validate(c, try d.str(d.get(w.*, key_stdout_regex)));
}
/// Read TOML or JSON manifests and fingerprint every explicitly declared input.
pub fn load(c: *C, path: []const u8) d.Error!Manifest {
    return loadImpl(c, path) catch |err| d.failure(c, err);
}
fn loadImpl(c: *C, path: []const u8) !Manifest {
    const absolute = try p.real(c, path);
    const text = try c.readBytes(absolute);
    const trimmed = std.mem.trimStart(u8, text, " \r\n\t");
    var data = if (std.mem.startsWith(u8, trimmed, "{")) try c.parse(text) else try toml.parse(c, text);
    try keys(c, data, "version name adapter sources inputs environment build workloads");
    if (d.get(data, "version") != .integer or d.get(data, "version").integer != 1) return c.fail("manifest version must be 1");
    if (!d.identifier(try d.str(try d.req(data, "name")))) return c.fail("invalid manifest name");
    try d.default(c, &data, "adapter", d.string("native"));
    if (!d.is(d.get(data, "adapter"), "native") and !d.is(d.get(data, "adapter"), "selka")) return c.fail("adapter must be native or selka");
    try strings(try d.req(data, "sources"), true);
    try d.default(c, &data, "inputs", d.array(c));
    try strings(d.get(data, "inputs"), false);
    const root = std.fs.path.dirname(absolute) orelse return error.InvalidExperiment;
    var m: Manifest = .{ .data = data, .root = root, .sources = try inventory(c, root, d.get(data, "sources")), .inputs = try inventory(c, root, d.get(data, "inputs")) };
    for (try d.keys(c, m.inputs)) |name| {
        if (m.sources.object.contains(name)) return c.fail("sources and fixed inputs must be disjoint");
        const top = name[0 .. std.mem.indexOfScalar(u8, name, '/') orelse name.len];
        if (std.mem.eql(u8, top, "program") or std.mem.eql(u8, top, "counters.json") or std.mem.startsWith(u8, top, "collector")) return c.fail("fixed input collides with a runner control path");
    }
    try d.default(c, &m.data, "environment", d.object());
    const env = d.get(m.data, "environment");
    for (try d.keys(c, env)) |key| {
        _ = try d.str(d.get(env, key));
        if (key.len == 0 or std.mem.indexOfScalar(u8, key, '=') != null) return error.InvalidExperiment;
        for ([_][]const u8{ "HOME", "TMPDIR", "PWD", "SELKA_COUNTERS", "VALGRIND_LIB" }) |reserved| if (std.mem.eql(u8, key, reserved)) return c.fail("environment overrides a runner control variable");
    }
    try checkBuild(c, &m);
    const workloads = try d.req(m.data, "workloads");
    if ((try d.items(workloads)).len == 0) return c.fail("at least one workload required");
    var names = d.object();
    for (workloads.array.items) |*w| try workload(c, w, &names);
    return m;
}
/// Select precisely the requested tier and names, refusing empty/mistyped requests.
pub fn select(c: *C, m: Manifest, tier: []const u8, names: V) d.Error!V {
    return selectImpl(c, m, tier, names) catch |err| d.failure(c, err);
}
fn selectImpl(c: *C, m: Manifest, tier: []const u8, names: V) !V {
    const known_tier = std.mem.eql(u8, tier, "all") or std.mem.eql(u8, tier, "quick") or std.mem.eql(u8, tier, "validation");
    if (!known_tier) return error.InvalidExperiment;
    var result = d.array(c);
    var found = d.object();
    for (try d.items(d.get(m.data, "workloads"))) |w| {
        if (!std.mem.eql(u8, tier, "all") and !d.is(d.get(w, "tier"), tier)) continue;
        var wanted = names == .null;
        if (names != .null) for (try d.items(names)) |name| {
            if (d.equal(name, d.get(w, "name"))) wanted = true;
        };
        if (wanted) {
            try d.add(c, &result, w);
            try d.put(c, &found, try d.str(d.get(w, "name")), .null);
        }
    }
    if (result.array.items.len == 0) return c.fail("workload selection is empty");
    if (names != .null) for (try d.items(names)) |name| {
        if (!found.object.contains(try d.str(name))) return c.fail("workload missing or outside selected tier");
    };
    return result;
}
