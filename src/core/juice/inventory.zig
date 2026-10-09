//! Static ELF diagnostics and dynamic-library identities, never scored as executions.
const std = @import("std");
const d = @import("data.zig");
const p = @import("platform.zig");
const C = d.Context;
const V = d.Value;
fn inspect(c: *C, argv: []const []const u8, env: *const std.process.Environ.Map) !std.process.RunResult {
    const command = try c.a.dupe([]const u8, argv);
    command[0] = try p.executable(c, command[0], c.env);
    return std.process.run(c.a, c.io, .{
        .argv = command,
        .environ_map = env,
        .timeout = .{
            .duration = .{
                .raw = .fromSeconds(30),
                .clock = .awake,
            },
        },
        .stdout_limit = .limited(64 << 20),
        .stderr_limit = .limited(4 << 20),
    });
}
fn succeeded(result: std.process.RunResult) bool {
    return result.term == .exited and result.term.exited == 0;
}
/// Static code bytes and potentially expensive instruction sites; missing tools stay unknown.
pub fn code(c: *C, binary: []const u8) d.Error!V {
    return codeImpl(c, binary) catch |err| d.failure(c, err);
}
fn codeImpl(c: *C, binary: []const u8) !V {
    var result = try c.value(.{ .sections = d.object(), .functions = d.object(), .available = false });
    const sizes = inspect(c, &.{ "size", "-A", binary }, c.env) catch return result;
    const symbols = inspect(c, &.{ "nm", "-S", "--defined-only", binary }, c.env) catch return result;
    const assembly = inspect(c, &.{ "objdump", "-d", "--no-show-raw-insn", binary }, c.env) catch return result;
    const all_succeeded = succeeded(sizes) and succeeded(symbols);
    if (!all_succeeded or !succeeded(assembly)) return result;
    var sections = d.object();
    var functions = d.object();
    var rows = std.mem.splitScalar(u8, sizes.stdout, '\n');
    while (rows.next()) |line| {
        var fields = std.mem.tokenizeAny(u8, line, " \t\r");
        const name = fields.next() orelse continue;
        if (name.len == 0 or name[0] != '.') continue;
        const size = std.fmt.parseInt(i64, fields.next() orelse continue, 10) catch continue;
        try d.put(c, &sections, name, .{ .integer = size });
    }
    rows = std.mem.splitScalar(u8, symbols.stdout, '\n');
    while (rows.next()) |line| {
        var fields = std.mem.tokenizeAny(u8, line, " \t\r");
        _ = fields.next() orelse continue;
        const size = std.fmt.parseInt(i64, fields.next() orelse continue, 16) catch continue;
        const kind = fields.next() orelse continue;
        if (!std.mem.eql(u8, kind, "t") and !std.mem.eql(u8, kind, "T")) continue;
        const name = fields.rest();
        if (name.len > 0) try d.put(c, &functions, name, try c.value(.{ .bytes = size }));
    }
    rows = std.mem.splitScalar(u8, assembly.stdout, '\n');
    var current: ?[]const u8 = null;
    while (rows.next()) |line| {
        if (std.mem.indexOf(u8, line, " <")) |at| {
            if (std.mem.endsWith(u8, line, ">:")) {
                current = line[at + 2 .. line.len - 2];
                if (d.get(functions, current.?) == .null) try d.put(c, &functions, current.?, try c.value(.{ .bytes = 0 }));
                continue;
            }
        }
        const name = current orelse continue;
        const colon = std.mem.indexOfScalar(u8, line, ':') orelse continue;
        _ = std.fmt.parseInt(u64, std.mem.trim(u8, line[0..colon], " \t"), 16) catch continue;
        var fields = std.mem.tokenizeAny(u8, line[colon + 1 ..], " \t");
        const op = fields.next() orelse continue;
        const exchange = std.mem.startsWith(u8, op, "xchg") and std.mem.indexOfScalar(u8, fields.rest(), '(') != null;
        const divide = std.mem.startsWith(u8, op, "div") or std.mem.startsWith(u8, op, "idiv") or std.mem.startsWith(u8, op, "vdiv");
        const key = if (std.mem.eql(u8, op, "lock") or exchange) "atomic_sites" else if (divide) "divide_sites" else if (std.mem.startsWith(u8, op, "v")) "vector_sites" else continue;
        var function = d.get(functions, name);
        const old = d.get(function, key);
        try d.put(c, &function, key, .{ .float = (if (old == .null) @as(f64, 0) else try d.num(old)) + 1 });
        try d.put(c, &functions, name, function);
    }
    try d.put(c, &result, "sections", sections);
    try d.put(c, &result, "functions", functions);
    try d.put(c, &result, "available", .{ .bool = true });
    return result;
}
/// Fingerprint actual libraries under the staged program's runtime environment.
pub fn libraries(c: *C, binary: []const u8, env: *const std.process.Environ.Map) d.Error!V {
    return librariesImpl(c, binary, env) catch |err| d.failure(c, err);
}
fn librariesImpl(c: *C, binary: []const u8, env: *const std.process.Environ.Map) !V {
    const result = try inspect(c, &.{ "ldd", binary }, env);
    if (std.mem.indexOf(u8, result.stdout, "=> not found") != null) return c.fail("executable has an unresolved shared library");
    const static = std.mem.indexOf(u8, result.stdout, "not a dynamic executable") != null or std.mem.indexOf(u8, result.stderr, "not a dynamic executable") != null;
    if (!succeeded(result) and !static) return c.fail("cannot determine executable shared-library identity");
    var identities = d.object();
    var fields = std.mem.tokenizeAny(u8, result.stdout, " \t\r\n");
    while (fields.next()) |field| if (std.fs.path.isAbsolute(field)) {
        try d.put(c, &identities, field, try c.fileHash(field));
    };
    return identities;
}
