//! Builtin modules obey project loading rules and execute generic, non-EDA queries.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const fixture = @import("stdlib_fixture.zig");
const source =
    "module main\nimport sort\n" ++
    "def main() -> int:\n" ++
    "    ordered = sort.sort_ints([9, 1, 4])\n" ++
    "    return ordered[0] + ordered[2]\n";
fn read(_: ?*anyopaque, allocator: std.mem.Allocator, path: []const u8, limit: usize) language.project.ReadError![]u8 {
    if (!std.mem.eql(u8, path, "main.my")) return error.NotFound;
    if (source.len > limit) return error.TooLarge;
    return allocator.dupe(u8, source);
}
// spec: STANDARD-MODULES-1
test "standard modules load through embedded providers and execute reserved sources" {
    var program: language.embedded_project.Program = undefined;
    try program.init(t.allocator, .{ .context = null, .read = read });
    defer program.deinit();
    const outcome = try language.vm.run(t.allocator, program.compilation.code.?);
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
    try fixture.reject(t.allocator, "module main\nimport strings\ndef main() -> int:\n    strings.repeat(\"a\", 2)\n    return 0\n");
    try fixture.reject(t.allocator, "module main\nimport time\ndef main() -> int:\n    time.seconds(1)\n    return 0\n");
}

// spec-case: STANDARD-MODULES-1
test "standard fixture helpers report every assertion failure through declared errors" {
    const ordering = "module main\nimport sort\ndef main() -> int:\n    return sort.sort_ints([1, 2])[0]\n";
    try t.expectError(error.TestExpectedEqual, fixture.run(t.allocator, ordering, 41));
    const bounds = "module main\nimport sort\ndef main() -> int:\n    return sort.sort_ints([1])[5]\n";
    try t.expectError(error.TestUnexpectedResult, fixture.run(t.allocator, bounds, 0));
    try t.expectError(error.TestExpectedError, fixture.reject(t.allocator, ordering));
    try fixture.reject(t.allocator, "module main\nimport sort\ndef main() -> int:\n    return sort.sort_ints([1])\n");
}

// spec-case: STANDARD-MODULES-1
test "standard modules compose with one another inside a single project" {
    try fixture.run(t.allocator, "module main\nimport json\nimport base64\nimport path\n" ++
        "def main() -> int:\n" ++
        "    encoded = base64.b64encode(path.basename(\"/tmp/answer.txt\").encode())\n" ++
        "    match encoded.decode():\n" ++
        "        case Ok(text):\n" ++
        "            return rendered(text)\n" ++
        "        case Err(_):\n" ++
        "            return 1\n" ++
        "def rendered(text: str) -> int:\n" ++
        "    fields: dict[str, json.Json] = {}\n" ++
        "    fields[\"name\"] = json.text(text)\n" ++
        "    document = json.dumps(json.object(fields))\n" ++
        "    if document != \"{\\\"name\\\":\\\"YW5zd2VyLnR4dA==\\\"}\":\n" ++
        "        return 2\n" ++
        "    return len(document) - 4\n", 42);
}
