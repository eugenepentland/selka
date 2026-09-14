//! The Python file surface natively: `with open(...)` scopes, handle methods,
//! whole-path helpers, cleanup on every exit, and the effect and grant bounds.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const native = @import("native_execute.zig");
const file_resources = @import("file_resources.zig");

const module = "io-files.my";

/// Opening the granted directory, compiling a guest program and running it.
pub const SandboxError = native.Error || std.Io.Dir.RealPathFileAllocError || std.mem.Allocator.Error;

/// One real temporary directory and the capability grant a run receives over it.
/// Every capability suite that needs a filesystem builds its fixtures here.
pub const Sandbox = struct {
    temporary: std.testing.TmpDir,
    path: [:0]u8,
    grant: [2][]const u8,

    /// Open a fresh directory and decide whether its grant carries write authority.
    pub fn init(self: *Sandbox, writable: bool) SandboxError!void {
        self.temporary = t.tmpDir(.{});
        self.path = try self.temporary.dir.realPathFileAlloc(t.io, ".", t.allocator);
        self.grant = .{ "--restrict", if (writable) "--allow-write=." else "--allow-read=." };
    }
    /// Release the resolved path and remove the directory and everything in it.
    pub fn deinit(self: *Sandbox) void {
        t.allocator.free(self.path);
        self.temporary.cleanup();
    }
    /// Run the guest inside the granted directory, so its relative paths resolve there.
    pub fn options(self: *Sandbox) native.Options {
        return .{ .directory = self.path, .arguments = &self.grant };
    }
    /// Compile and run one program against this grant, returning the whole outcome.
    pub fn run(self: *Sandbox, name: []const u8, text: []const u8) SandboxError!native.Run {
        var compilation = try language.Compilation.init(t.allocator, name, text);
        defer compilation.deinit();
        return native.runWithOptions(&compilation, self.options()) catch |err| {
            @import("diagnostics_test.zig").report(compilation.diagnostics.items);
            return err;
        };
    }
};

/// Grant a read-only directory holding `notes.txt` and compare everything printed.
fn expectPrinted(text: []const u8, expected: []const u8) !void {
    var sandbox: Sandbox = undefined;
    try sandbox.init(false);
    defer sandbox.deinit();
    try sandbox.temporary.dir.writeFile(t.io, .{ .sub_path = "notes.txt", .data = "alpha\nbeta\n" });
    const outcome = try sandbox.run(module, text);
    try t.expectEqualStrings("", outcome.trap.code);
    try t.expectEqualStrings(expected, outcome.stdout);
}

fn expectTrap(text: []const u8, code: []const u8) !void {
    var sandbox: Sandbox = undefined;
    try sandbox.init(true);
    defer sandbox.deinit();
    const outcome = try sandbox.run(module, text);
    try t.expectEqualStrings(code, outcome.trap.code);
}

fn reject(text: []const u8, code: []const u8) !void {
    var compilation = try language.Compilation.init(t.allocator, module, text);
    defer compilation.deinit();
    try t.expectError(error.SourceError, compilation.check());
    try t.expectEqualStrings(code, compilation.diagnostics.items[0].code);
}

// spec: IO-7
test "IO-7 with open binds a handle whose reads follow the declared mode" {
    try expectPrinted(
        \\def main(fs: Filesystem) -> int:
        \\    with open(fs, "notes.txt", "rb") as f:
        \\        print(f.read())
        \\    return 0
    , "b'alpha\\nbeta\\n'\n");
    try expectPrinted(
        \\def main(fs: Filesystem) -> int:
        \\    with open(fs, "notes.txt", "r") as f:
        \\        print(f.read(5))
        \\        print(f.readline())
        \\    return 0
    , "alpha\n\n\n");
    try expectPrinted(
        \\def main(fs: Filesystem) -> int:
        \\    with open(fs, "notes.txt", "r") as f:
        \\        for line in f.readlines():
        \\            print(len(line))
        \\    return 0
    , "6\n5\n");
}

// spec: IO-8
test "IO-8 writing modes create truncate and append through a write grant" {
    var sandbox: Sandbox = undefined;
    try sandbox.init(true);
    defer sandbox.deinit();
    const program =
        \\def main(fs: Filesystem) -> int:
        \\    with open(fs, "out.txt", "w") as f:
        \\        print(f.write("first\n"))
        \\        f.flush()
        \\    with open(fs, "out.txt", "a") as f:
        \\        _ = f.write("second\n")
        \\    with open(fs, "out.txt", "w") as f:
        \\        _ = f.write("third\n")
        \\    return 0
    ;
    const outcome = try sandbox.run(module, program);
    try t.expectEqualStrings("6\n", outcome.stdout);
    const written = try sandbox.temporary.dir.readFileAlloc(t.io, "out.txt", t.allocator, .limited(64));
    defer t.allocator.free(written);
    try t.expectEqualStrings("third\n", written);
}

// spec: IO-9
test "IO-9 whole-path helpers report provider failures as readable Result errors" {
    var sandbox: Sandbox = undefined;
    try sandbox.init(true);
    defer sandbox.deinit();
    try sandbox.temporary.dir.writeFile(t.io, .{ .sub_path = "notes.txt", .data = "alpha\n" });
    const program =
        \\def main(fs: Filesystem) -> int:
        \\    print(read_text(fs, "notes.txt"))
        \\    print(read_file(fs, "notes.txt"))
        \\    print(exists(fs, "notes.txt"), exists(fs, "absent.txt"))
        \\    print(write_text(fs, "copy.txt", "beta\n"))
        \\    print(read_text(fs, "copy.txt"))
        \\    print(mkdir(fs, "sub"))
        \\    print(listdir(fs, "sub"))
        \\    print(remove(fs, "copy.txt"))
        \\    print(exists(fs, "copy.txt"))
        \\    print(read_text(fs, "absent.txt"))
        \\    print(read_text(fs, "../escape"))
        \\    return 0
    ;
    const outcome = try sandbox.run(module, program);
    try t.expectEqualStrings(
        "Ok('alpha\\n')\n" ++
            "Ok(b'alpha\\n')\n" ++
            "True False\n" ++
            "Ok(None)\n" ++
            "Ok('beta\\n')\n" ++
            "Ok(None)\n" ++
            "Ok([])\n" ++
            "Ok(None)\n" ++
            "False\n" ++
            "Err('read \\'absent.txt\\': failed: the path does not exist or could not be used')\n" ++
            "Err('read \\'../escape\\': denied: outside the granted directories, or the mode needs a write grant')\n",
        outcome.stdout,
    );
}

// spec: IO-10
test "IO-10 a read-only grant denies every writing mode" {
    var sandbox: Sandbox = undefined;
    try sandbox.init(false);
    defer sandbox.deinit();
    const program =
        \\def main(fs: Filesystem) -> int:
        \\    print(write_text(fs, "out.txt", "x"))
        \\    print(mkdir(fs, "sub"))
        \\    print(remove(fs, "out.txt"))
        \\    return 0
    ;
    const outcome = try sandbox.run(module, program);
    try t.expect(std.mem.indexOf(u8, outcome.stdout, "needs a write grant") != null);
    try t.expectEqual(@as(usize, 3), std.mem.count(u8, outcome.stdout, "Err("));
}

// spec: IO-11
test "IO-11 a with scope closes its file on every exit including traps and propagation" {
    var sandbox: Sandbox = undefined;
    try sandbox.init(true);
    defer sandbox.deinit();
    try sandbox.temporary.dir.writeFile(t.io, .{ .sub_path = "notes.txt", .data = "alpha\n" });
    // The provider holds 256 handles at once, so three hundred scopes that each
    // return, break or propagate can only finish if every one released its own.
    const program =
        \\def early(fs: Filesystem) -> int:
        \\    with open(fs, "notes.txt", "r") as f:
        \\        return len(f.read())
        \\
        \\def looped(fs: Filesystem) -> int:
        \\    total = 0
        \\    for index in range(300):
        \\        with open(fs, "notes.txt", "r") as f:
        \\            total = total + len(f.read())
        \\            if index == 298:
        \\                break
        \\    return total
        \\
        \\def propagated(fs: Filesystem) -> Result[int, str]:
        \\    with open(fs, "notes.txt", "r")? as f:
        \\        _ = f.read()
        \\        _ = read_text(fs, "absent.txt")?
        \\        return Ok(0)
        \\
        \\def main(fs: Filesystem) -> int:
        \\    total = early(fs) + looped(fs)
        \\    match propagated(fs):
        \\        case Ok(value):
        \\            return value
        \\        case Err(message):
        \\            return total
    ;
    const outcome = try sandbox.run(module, program);
    try t.expectEqualStrings("", outcome.trap.code);
    try t.expectEqual(@as(i64, 6 + 299 * 6), outcome.value);
    // Explicit close releases the handle before the scope ends.
    try expectPrinted(
        \\def main(fs: Filesystem) -> int:
        \\    with open(fs, "notes.txt", "r") as f:
        \\        print(len(f.read()))
        \\        f.close()
        \\    return 0
    , "11\n");
    try expectTrap(
        \\def main(fs: Filesystem) -> int:
        \\    with open(fs, "written.txt", "w") as f:
        \\        f.close()
        \\        _ = f.write("late")
        \\    return 0
    , "R_FILE");
}

// spec: IO-12
test "IO-12 the file surface is rejected under noio by generic bodies and by the native backend" {
    try reject(
        \\def main(fs: Filesystem) -> int noio:
        \\    _ = exists(fs, "notes.txt")
        \\    return 0
    , "E_EFFECT_BOUND");
    try reject(
        \\def main(fs: Filesystem) -> int:
        \\    with read_text(fs, "notes.txt") as text:
        \\        return 0
    , "E_WITH_RESOURCE");
    try reject(
        \\def main() -> int:
        \\    with 7 as value:
        \\        return 0
    , "E_WITH_RESOURCE");
    try reject(
        \\def main(fs: Filesystem) -> int:
        \\    mode = "rb"
        \\    with open(fs, "notes.txt", mode) as f:
        \\        return 0
    , "E_FILE_ARGUMENT");
    try reject(
        \\def main(fs: Filesystem) -> int:
        \\    with open(fs, "notes.txt", "rb") as f:
        \\        _ = f.seek(0)
        \\    return 0
    , "E_FILE_ARGUMENT");
}

// spec-case: IO-12
test "IO-12 the native backend lowers the whole file surface" {
    var compilation = try language.Compilation.init(t.allocator, module,
        \\def count(fs: Filesystem) -> Result[int, str]:
        \\    total = 0
        \\    with open(fs, "lines.txt", "r")? as f:
        \\        for line in f.readlines():
        \\            total = total + len(line)
        \\    return Ok(total)
        \\
        \\def main(fs: Filesystem) -> int:
        \\    _ = read_text(fs, "notes.txt")
        \\    _ = read_file(fs, "notes.txt")
        \\    _ = write_text(fs, "notes.txt", "x")
        \\    _ = write_file(fs, "notes.txt", b"x")
        \\    _ = exists(fs, "notes.txt")
        \\    _ = listdir(fs, ".")
        \\    _ = mkdir(fs, "made")
        \\    _ = remove(fs, "made")
        \\    with open(fs, "notes.txt", "wb") as f:
        \\        _ = f.write(b"x")
        \\        f.flush()
        \\        f.close()
        \\    match count(fs):
        \\        case Ok(value):
        \\            return value
        \\        case Err(message):
        \\            return 0 - len(message)
    );
    defer compilation.deinit();
    const manifest = try compilation.emitQbe(t.allocator);
    defer t.allocator.free(manifest);
    try t.expect(std.mem.indexOf(u8, manifest, "myl_qbe_file_access") != null);
    try t.expect(std.mem.indexOf(u8, manifest, "myl_qbe_file_method") != null);
    // An open handle is one owned resource word, dropped at every scope exit.
    try t.expect(std.mem.indexOf(u8, manifest, "myl_native_owned_drop") != null);
}

test "file operations report a readable reason for every provider failure" {
    try t.expectEqualStrings("no filesystem authority is available", file_resources.reason(error.Unavailable));
    try t.expectEqualStrings("too many files are open", file_resources.reason(error.ResourceLimit));
    try t.expectEqualStrings("the file is already closed", file_resources.reason(error.InvalidOwner));
    try t.expectEqualStrings("the bytes read are not valid UTF-8 text", file_resources.reason(error.InvalidUtf8));
    try t.expect(std.mem.startsWith(u8, file_resources.reason(error.Denied), "denied"));
    try t.expect(std.mem.startsWith(u8, file_resources.reason(error.Failed), "failed"));
}

test "a program with no granted filesystem refuses to start rather than reading anything" {
    var compilation = try language.Compilation.init(t.allocator, module,
        \\def main(fs: Filesystem) -> int:
        \\    _ = exists(fs, "notes.txt")
        \\    return 0
    );
    defer compilation.deinit();
    const outcome = try native.runWithOptions(&compilation, .{ .arguments = &.{"--restrict"} });
    try t.expectEqualStrings("CapabilityUnavailable", outcome.trap.code);
    try t.expectEqual(@as(u8, 2), outcome.status);
    try t.expectEqualStrings("", outcome.stdout);
}
