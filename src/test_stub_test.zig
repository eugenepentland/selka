//! The stub `main` the test runner appends to a test file that declares none (FR19): it is recognised by its place and its
//! comment, so that a test file whose module imports `main` is not refused for the stub's `main` meeting the import's alias,
//! while a `main` the author wrote still is.
const std = @import("std");
const t = std.testing;
const check_directory = @import("check_directory.zig");

// spec: TEST-STUB-1
test "the runner's stub main is recognised at the end of a text and nowhere else" {
    const file = "import main\n\npublic func test_it() -> bool:\n    return True\n" ++ check_directory.test_stub;
    const at = std.mem.lastIndexOf(u8, file, "main").?;
    try t.expect(check_directory.isTestStubMain(file, .{ .start = at, .end = at + 4 }));
    // Another `main` of the same text is not the stub's: the `import main` at the start.
    try t.expect(!check_directory.isTestStubMain(file, .{ .start = 7, .end = 11 }));
    // A `main` the author wrote, even a last one, has no stub's comment above it.
    const own = "import main\n\nfunc main() -> int:\n    return 0\n";
    try t.expect(!check_directory.isTestStubMain(own, .{ .start = own.len - "main() -> int:\n    return 0\n".len, .end = own.len - "() -> int:\n    return 0\n".len }));
    try t.expect(!check_directory.isTestStubMain("", .{ .start = 0, .end = 0 }));
}
