//! Environment capability contracts, bounded host values and generic execution tests.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const native = @import("native_execute.zig");
const module = "environment.selka";
const declarations =
    \\record Entry:
    \\    present: bool
    \\    bytes: FixedArray[u8, 4]
    \\    length: u64
    \\
    \\
    \\result Lookup:
    \\    err: i64,
    \\    ok: Entry
    \\
    \\
    \\
;
fn reject(source: []const u8, code: []const u8) !void {
    var c = try language.Compilation.initTrusted(t.allocator, module, source);
    defer c.deinit();
    try t.expectError(error.SourceError, c.check());
    try t.expectEqualStrings(code, c.diagnostics.items[0].code);
}
/// Run one program against a guest environment holding `K` only when given.
fn lookup(source: []const u8, value: ?[]const u8, arguments: []const []const u8, expected: i64) !void {
    var c = try language.Compilation.initTrusted(t.allocator, module, source);
    defer c.deinit();
    var guest: std.process.Environ.Map = .init(t.allocator);
    defer guest.deinit();
    if (value) |bytes| try guest.put("K", bytes);
    const outcome = native.runWithOptions(&c, .{ .environment = &guest, .arguments = arguments }) catch |err| {
        @import("diagnostics_test.zig").report(c.diagnostics.items);
        return err;
    };
    try t.expectEqualStrings("", outcome.trap.code);
    try t.expectEqual(expected, outcome.value);
}
const forwarded = declarations ++
    \\record Authority:
    \\    env: Environment
    \\
    \\
    \\func lookup(auth: Authority) -> Lookup:
    \\    return environment_get[Lookup](auth.env, FixedArray[u8, 1]([75u8]))
    \\
    \\
    \\func main(environment: Environment) -> i64:
    \\    const authority = Authority(env=environment)
    \\    match lookup(authority):
    \\        case ok(entry):
    \\            if entry.present:
    \\                return 10 + i64(entry.length) + i64(entry.bytes[3])
    \\            else:
    \\                return i64(entry.length) + i64(entry.bytes[0])
    \\        case err(code):
    \\            return -code
;
fn scenario(allocator: std.mem.Allocator) !void {
    var c = try language.Compilation.initTrusted(allocator, module, forwarded);
    defer c.deinit();
    try c.check();
    var duplicates = try language.duplicates.discover(allocator, c.program.?, .{ .min_nodes = 1 });
    defer duplicates.deinit();
}
test "environment grants are rejected outside a capability parameter" {
    try reject(declarations ++
        \\func main() -> i64:
        \\    match environment_get[Lookup](7, FixedArray[u8, 1]([75u8])):
        \\        case ok(entry):
        \\            return i64(entry.length)
        \\        case err(code):
        \\            return -code
    , "E_TYPE");
}
test "environment execution reporting and byte conversions release all failed allocations" {
    var no_resize = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(no_resize.allocator(), scenario, .{});
}
const generic_environment = declarations ++
    \\func lookup[G](cap: Environment) -> Lookup:
    \\    mut name: FixedArray[u8, 1] = FixedArray[u8, 1]([75u8])
    \\    return environment_get[Lookup](cap, name)
    \\
    \\
    \\func main(cap: Environment) -> i64:
    \\    match lookup[bool](cap):
    \\        case ok(e):
    \\            return i64(e.length) + i64(e.bytes[0]) + i64(e.bytes[1])
    \\        case err(e):
    \\            return e
;
fn genericEnvironmentScenario(allocator: std.mem.Allocator) !void {
    var c = try language.Compilation.initTrusted(allocator, "generic-environment.selka", generic_environment);
    defer c.deinit();
    try c.check();
}
// spec-case: FRONTEND-TYPES-1
test "generic environment sources use explicit fixed-array constructors" {
    try genericEnvironmentScenario(t.allocator);
}

const python_get =
    \\func main(env: Environment) -> i64:
    \\    match env.get("K"):
    \\        case Some(value):
    \\            return strings.char_count(value)
    \\        case None:
    \\            return 0
;
// spec: ENVIRONMENT-GET-1
test "python env.get returns Some for present names and None for absent ones" {
    try lookup(python_get, "ab", &.{}, 2);
    try lookup(python_get, null, &.{}, 0);
    try lookup(python_get, "", &.{}, 0);
}
const python_computed =
    \\func lookup(env: Environment, name: str) -> i64:
    \\    match env.get(name):
    \\        case Some(value):
    \\            return strings.char_count(value)
    \\        case None:
    \\            return 0
    \\func main(env: Environment) -> i64:
    \\    mut name = "K"
    \\    const prefix = "FIRST_"
    \\    return lookup(env, name) + 10 * lookup(env, prefix + "ABSENT") + 100 * lookup(env, name + "")
;
// spec-case: ENVIRONMENT-GET-1
test "python env.get accepts a computed name and answers Some or None like a literal one" {
    try lookup(python_computed, "ab", &.{}, 202);
    try lookup(python_computed, null, &.{}, 0);
}
const python_odd_names =
    \\func probe(env: Environment, name: str) -> i64:
    \\    match env.get(name):
    \\        case Some(_):
    \\            return 1
    \\        case None:
    \\            return 0
    \\func main(env: Environment) -> i64:
    \\    mut long = "K"
    \\    for _ in range(300):
    \\        long = long + "K"
    \\    return probe(env, "") + 10 * probe(env, "K=1") + 100 * probe(env, "K\x00") + 1000 * probe(env, long) + 10000 * probe(env, "K")
;
// spec-case: ENVIRONMENT-GET-1
test "python env.get answers None for an empty name, one with NUL or equals, and one over 255 octets" {
    try lookup(python_odd_names, "ab", &.{}, 10000);
    try lookup(python_odd_names, "ab", &.{ "--restrict", "--allow-env=K" }, 10000);
}
// spec-case: ENVIRONMENT-GET-1
test "python env.get answers None for an odd name even when the allow-list holds no name, but traps a real one" {
    try lookup(
        \\func probe(env: Environment, name: str) -> i64:
        \\    match env.get(name):
        \\        case Some(_):
        \\            return 1
        \\        case None:
        \\            return 0
        \\func main(env: Environment) -> i64:
        \\    return probe(env, "") + probe(env, "K=1") + probe(env, "A\x00B")
    , "ab", &.{ "--restrict", "--allow-env=OTHER" }, 0);
    var c = try language.Compilation.initTrusted(t.allocator, module,
        \\func probe(env: Environment, name: str) -> i64:
        \\    match env.get(name):
        \\        case Some(_):
        \\            return 1
        \\        case None:
        \\            return 0
        \\func main(env: Environment) -> i64:
        \\    const prefix = "K"
        \\    return probe(env, prefix)
    );
    defer c.deinit();
    var guest: std.process.Environ.Map = .init(t.allocator);
    defer guest.deinit();
    try guest.put("K", "ab");
    const denied = try native.runWithOptions(&c, .{ .environment = &guest, .arguments = &.{ "--restrict", "--allow-env=OTHER" } });
    try t.expectEqualStrings("R_CAPABILITY", denied.trap.code);
}
// spec-case: ENVIRONMENT-NAMES-1
test "python env.names lists every visible name, not only the first 64" {
    var c = try language.Compilation.initTrusted(t.allocator, module,
        \\func main(env: Environment) -> i64:
        \\    mut count = 0
        \\    for name in env.names():
        \\        if len(name) == 9 and name[0:6] == "NAMES_":
        \\            count += 1
        \\    return count
    );
    defer c.deinit();
    var guest: std.process.Environ.Map = .init(t.allocator);
    defer guest.deinit();
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    for (0..120) |index| try guest.put(try std.fmt.allocPrint(arena.allocator(), "NAMES_{d:0>3}", .{index}), "x");
    const outcome = try native.runWithOptions(&c, .{ .environment = &guest, .arguments = &.{} });
    try t.expectEqualStrings("", outcome.trap.code);
    try t.expectEqual(@as(i64, 120), outcome.value);
}
// spec-case: ENVIRONMENT-GET-1
test "a generic function body may call env.get with a computed name" {
    try lookup(
        \\func read[T](env: Environment, marker: T, name: str) -> i64:
        \\    match env.get(name):
        \\        case Some(value):
        \\            return strings.char_count(value)
        \\        case None:
        \\            return 0
        \\func main(env: Environment) -> i64:
        \\    return read(env, 1, "K") + 10 * read(env, "x", "NOT_SET")
    , "abc", &.{}, 3);
}
// spec-case: ENVIRONMENT-GET-1
test "the raw environment_get spelling is reserved for standard-library sources" {
    var c = try language.Compilation.init(t.allocator, "environment.selka",
        \\result Lookup:
        \\    ok: i64,
        \\    err: i64
        \\
        \\
        \\func main(env: Environment) -> i64:
        \\    _ = environment_get[Lookup](env, FixedArray[u8, 1]([75u8]))
        \\    return 0
    );
    defer c.deinit();
    try t.expectError(error.SourceError, c.check());
    try t.expectEqualStrings("E_INTERNAL_NAME", c.diagnostics.items[0].code);
}
// spec-case: ENVIRONMENT-GET-1
test "python env.get traps when the grant allowlist denies the name" {
    var c = try language.Compilation.initTrusted(t.allocator, module, python_get);
    defer c.deinit();
    var guest: std.process.Environ.Map = .init(t.allocator);
    defer guest.deinit();
    try guest.put("K", "ab");
    const denied = try native.runWithOptions(&c, .{ .environment = &guest, .arguments = &.{ "--restrict", "--allow-env=OTHER" } });
    try t.expectEqualStrings("R_CAPABILITY", denied.trap.code);
}
const python_only =
    \\func main(env: Environment) -> i64:
    \\    with env.only("K") as narrowed:
    \\        match narrowed.get("K"):
    \\            case Some(value):
    \\                return strings.char_count(value)
    \\            case None:
    \\                return 0
;
// spec: ENVIRONMENT-ONLY-1
test "python env.only narrows a read to its literal names" {
    try lookup(python_only, "ab", &.{}, 2);
    try lookup(python_only, null, &.{}, 0);
}
// spec-case: ENVIRONMENT-ONLY-1
test "python env.only refuses a name outside its scope and a dynamic name" {
    var c = try language.Compilation.initTrusted(t.allocator, module,
        \\func main(env: Environment) -> i64:
        \\    with env.only("OTHER") as narrowed:
        \\        match narrowed.get("K"):
        \\            case Some(value):
        \\                return strings.char_count(value)
        \\            case None:
        \\                return 0
    );
    defer c.deinit();
    var guest: std.process.Environ.Map = .init(t.allocator);
    defer guest.deinit();
    try guest.put("K", "ab");
    const denied = try native.runWithOptions(&c, .{ .environment = &guest, .arguments = &.{} });
    try t.expectEqualStrings("R_CAPABILITY", denied.trap.code);
    try reject(
        \\func main(env: Environment) -> i64:
        \\    mut name = "K"
        \\    _ = env.only(name)
        \\    return 0
    , "E_ENVIRONMENT_NAME");
}
const python_names =
    \\func main(env: Environment) -> i64:
    \\    mut names = env.names()
    \\    if names[0] == "HOME":
    \\        return len(names)
    \\    return -1
;
// spec: ENVIRONMENT-NAMES-1
test "python env.names reports the sorted allowlist as a list[str]" {
    try lookup(python_names, "ab", &.{ "--restrict", "--allow-env=ZZ,HOME" }, 2);
}
// spec-case: ENVIRONMENT-NAMES-1
test "python env.names lists the process environment when no allowlist is set" {
    try lookup(
        \\func main(env: Environment) -> i64:
        \\    mut names = env.names()
        \\    for name in names:
        \\        if name == "K":
        \\            return 1
        \\    return 0
    , "ab", &.{}, 1);
}
// spec-case: ENVIRONMENT-NAMES-1
test "python env.names on a narrowed environment lists its scope" {
    try lookup(
        \\func main(env: Environment) -> i64:
        \\    with env.only("K") as narrowed:
        \\        mut names = narrowed.names()
        \\        if names[0] == "K":
        \\            return len(names)
        \\        return -1
    , "ab", &.{}, 1);
}
