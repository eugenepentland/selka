//! Builtin modules obey project loading rules and execute generic, non-EDA queries.
const source_names = @import("source_names.zig");
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const native = @import("native_execute.zig");
const fixture = @import("stdlib_fixture.zig");
const source =
    "import sort\n" ++
    "func main() -> int:\n" ++
    "    mut ordered = sort.sort_ints([9, 1, 4])\n" ++
    "    return ordered[0] + ordered[2]\n";
fn read(_: ?*anyopaque, allocator: std.mem.Allocator, path: []const u8, limit: usize) language.project.ReadError![]u8 {
    if (!std.mem.eql(u8, path, source_names.entry)) return error.NotFound;
    if (source.len > limit) return error.TooLarge;
    return allocator.dupe(u8, source);
}
// spec: STANDARD-MODULES-1
test "standard modules load through embedded providers and execute reserved sources" {
    var program: language.embedded_project.Program = undefined;
    try program.init(t.allocator, .{ .context = null, .read = read });
    defer program.deinit();
    const outcome = try native.run(&program.compilation);
    try t.expectEqual(@as(i64, 10), outcome.value);
    try t.expectEqual(@as(usize, 2), program.loaded.modules.items.len);
}
// spec: STANDARD-MODULES-2
test "standard modules remain inside the total project byte budget" {
    var project = language.project.Project.init(t.allocator);
    defer project.deinit();
    try t.expectError(error.SourceError, project.load(.{ .context = null, .read = read }, "main", .{ .max_total_bytes = source.len + 1 }));
    try t.expectEqualStrings("E_PROJECT_BYTES", project.problem.?.code);
}

// spec: STANDARD-MODULES-7
test "standard generic results cannot be silently ignored" {
    try fixture.reject(t.allocator, "import strings\nfunc main() -> int:\n    strings.repeat(\"a\", 2)\n    return 0\n");
    try fixture.reject(t.allocator, "import time\nfunc main() -> int:\n    time.seconds(1)\n    return 0\n");
}

// spec-case: STANDARD-MODULES-1
test "standard fixture helpers report every assertion failure through declared errors" {
    const ordering = "import sort\nfunc main() -> int:\n    return sort.sort_ints([1, 2])[0]\n";
    try t.expectError(error.TestExpectedEqual, fixture.run(t.allocator, ordering, 41));
    const bounds = "import sort\nfunc main() -> int:\n    return sort.sort_ints([1])[5]\n";
    try t.expectError(error.TestUnexpectedResult, fixture.run(t.allocator, bounds, 0));
    try t.expectError(error.TestExpectedError, fixture.reject(t.allocator, ordering));
    try fixture.reject(t.allocator, "import sort\nfunc main() -> int:\n    return sort.sort_ints([1])\n");
}

// spec-case: STANDARD-MODULES-1
test "standard modules compose with one another inside a single project" {
    try fixture.run(t.allocator, "import json\n" ++
        "import base64\n" ++
        "import path\n" ++
        "func main() -> int:\n" ++
        "    mut encoded = base64.b64encode(path.basename(\"/tmp/answer.txt\").encode())\n" ++
        "    match encoded.decode():\n" ++
        "        case Ok(text):\n" ++
        "            mut fields: dict[str, json.Json] = {}\n" ++
        "            return rendered(text, mut fields)\n" ++
        "        case Err(_):\n" ++
        "            return 1\n" ++
        "func rendered(text: str, mut fields: dict[str, json.Json]) -> int:\n" ++
        "    fields[\"name\"] = json.text(text)\n" ++
        "    mut document = json.dumps(json.object(fields))\n" ++
        "    if document != \"{\\\"name\\\":\\\"YW5zd2VyLnR4dA==\\\"}\":\n" ++
        "        return 2\n" ++
        "    return len(document) + 15\n", 42);
}

// spec: NETWORK-SURFACE-1
test "the network module wraps acquisition and one linear I/O operation" {
    const program_text =
        \\import network
        \\func main(net: Network) -> int:
        \\    mut scoped = net.host("127.0.0.1:8000")
        \\    match network.connect(scoped):
        \\        case network.Connected.ok(connection):
        \\            mut payload: FixedArray[u8, 4] = b"ping"
        \\            match network.write(connection, payload):
        \\                case network.Written.ok(_):
        \\                    return 0
        \\                case network.Written.err(code):
        \\                    return code
        \\        case network.Connected.err(code):
        \\            return code
    ;
    var entry: fixture.Entry = .{ .text = program_text };
    var program: language.embedded_project.Program = undefined;
    try program.init(t.allocator, .{ .context = &entry, .read = fixture.Entry.read });
    defer program.deinit();
    try t.expectEqual(@as(usize, 2), program.loaded.modules.items.len);
}
