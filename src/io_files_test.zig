//! The Python file surface on the VM: `with open(...)` scopes, handle methods,
//! whole-path helpers, cleanup on every exit, and the effect and native bounds.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const scoped = @import("scoped_providers.zig");
const file_resources = @import("file_resources.zig");

const module = "io-files.my";

/// One granted temporary directory and the provider callbacks over it.
const Sandbox = struct {
    temporary: std.testing.TmpDir,
    context: scoped.Context,
    roots: [1]scoped.Root,
    output: std.Io.Writer.Allocating,

    fn init(self: *Sandbox, writable: bool) void {
        self.temporary = t.tmpDir(.{});
        self.roots = .{.{ .dir = self.temporary.dir, .writable = writable }};
        self.context = .{ .allocator = t.allocator, .io = t.io, .roots = self.roots[0..1] };
        self.output = .init(t.allocator);
    }
    fn deinit(self: *Sandbox) void {
        self.context.deinit();
        self.output.deinit();
        self.temporary.cleanup();
    }
    fn options(self: *Sandbox, writable: bool) language.vm.Options {
        return .{
            .output = &self.output.writer,
            .resources = .{ .filesystem = self.context.filesystem(), .filesystem_permissions = if (writable) 7 else 5 },
        };
    }
    /// Compile and run one program against this grant, returning its scalar result.
    fn run(self: *Sandbox, text: []const u8, writable: bool) !i64 {
        var compilation = try language.Compilation.init(t.allocator, module, text);
        defer compilation.deinit();
        const outcome = compilation.executeWithOptions(t.allocator, self.options(writable)) catch |err| {
            if (err != error.OutOfMemory) @import("diagnostics_test.zig").report(compilation.diagnostics.items);
            return err;
        };
        return value(outcome);
    }
};

/// Report a trap as a readable failure so no test body needs a branch.
fn value(outcome: language.vm.Result) !i64 {
    if (outcome == .trap) {
        try t.expectEqualStrings("", outcome.trap.code);
        return error.Unreachable;
    }
    return outcome.value;
}

/// Report a successful run as a failure so no test body needs a branch.
fn trapCode(outcome: language.vm.Result) ![]const u8 {
    if (outcome == .value) {
        try t.expectEqual(@as(i64, -1), outcome.value);
        return error.Unreachable;
    }
    return outcome.trap.code;
}

fn expectPrinted(text: []const u8, expected: []const u8, writable: bool) !void {
    var sandbox: Sandbox = undefined;
    sandbox.init(writable);
    defer sandbox.deinit();
    try sandbox.temporary.dir.writeFile(t.io, .{ .sub_path = "notes.txt", .data = "alpha\nbeta\n" });
    _ = try sandbox.run(text, writable);
    try t.expectEqualStrings(expected, sandbox.output.written());
}

fn expectTrap(text: []const u8, code: []const u8) !void {
    var sandbox: Sandbox = undefined;
    sandbox.init(true);
    defer sandbox.deinit();
    var compilation = try language.Compilation.init(t.allocator, module, text);
    defer compilation.deinit();
    const outcome = try compilation.executeWithOptions(t.allocator, sandbox.options(true));
    try t.expectEqualStrings(code, try trapCode(outcome));
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
        \\    with open(fs, "notes.txt", "rb")? as f:
        \\        print(f.read())
        \\    return 0
    , "b'alpha\\nbeta\\n'\n", false);
    try expectPrinted(
        \\def main(fs: Filesystem) -> int:
        \\    with open(fs, "notes.txt", "r")? as f:
        \\        print(f.read(5))
        \\        print(f.readline())
        \\    return 0
    , "alpha\n\nbeta\n\n", false);
    try expectPrinted(
        \\def main(fs: Filesystem) -> int:
        \\    with open(fs, "notes.txt", "r")? as f:
        \\        for line in f.readlines():
        \\            print(len(line))
        \\    return 0
    , "6\n5\n", false);
}

// spec: IO-8
test "IO-8 writing modes create truncate and append through a write grant" {
    var sandbox: Sandbox = undefined;
    sandbox.init(true);
    defer sandbox.deinit();
    const program =
        \\def main(fs: Filesystem) -> int:
        \\    with open(fs, "out.txt", "w")? as f:
        \\        print(f.write("first\n"))
        \\        f.flush()
        \\    with open(fs, "out.txt", "a")? as f:
        \\        _ = f.write("second\n")
        \\    with open(fs, "out.txt", "w")? as f:
        \\        _ = f.write("third\n")
        \\    return 0
    ;
    _ = try sandbox.run(program, true);
    try t.expectEqualStrings("6\n", sandbox.output.written());
    const written = try sandbox.temporary.dir.readFileAlloc(t.io, "out.txt", t.allocator, .limited(64));
    defer t.allocator.free(written);
    try t.expectEqualStrings("third\n", written);
}

// spec: IO-9
test "IO-9 whole-path helpers report provider failures as readable Result errors" {
    var sandbox: Sandbox = undefined;
    sandbox.init(true);
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
    _ = try sandbox.run(program, true);
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
        sandbox.output.written(),
    );
}

// spec: IO-10
test "IO-10 a read-only grant denies every writing mode" {
    var sandbox: Sandbox = undefined;
    sandbox.init(false);
    defer sandbox.deinit();
    const program =
        \\def main(fs: Filesystem) -> int:
        \\    print(write_text(fs, "out.txt", "x"))
        \\    print(mkdir(fs, "sub"))
        \\    print(remove(fs, "out.txt"))
        \\    return 0
    ;
    _ = try sandbox.run(program, false);
    try t.expect(std.mem.indexOf(u8, sandbox.output.written(), "needs a write grant") != null);
    try t.expectEqual(@as(usize, 3), std.mem.count(u8, sandbox.output.written(), "Err("));
}

// spec: IO-11
test "IO-11 a with scope closes its file on every exit including traps and propagation" {
    var sandbox: Sandbox = undefined;
    sandbox.init(true);
    defer sandbox.deinit();
    try sandbox.temporary.dir.writeFile(t.io, .{ .sub_path = "notes.txt", .data = "alpha\n" });
    // One live resource at a time proves each scope released its handle.
    var statistics: [2]@import("external_resources.zig").Statistics = undefined;
    var options = sandbox.options(true);
    options.resources.max_live_per_kind = 1;
    options.resources.statistics = &statistics;
    const program =
        \\def early(fs: Filesystem) -> int:
        \\    with open(fs, "notes.txt", "r")? as f:
        \\        return len(f.read())
        \\
        \\def looped(fs: Filesystem) -> int:
        \\    total = 0
        \\    for index in range(3):
        \\        with open(fs, "notes.txt", "r")? as f:
        \\            total = total + len(f.read())
        \\            if index == 1:
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
    var compilation = try language.Compilation.init(t.allocator, module, program);
    defer compilation.deinit();
    const outcome = try compilation.executeWithOptions(t.allocator, options);
    try t.expectEqual(@as(i64, 18), try value(outcome));
    try t.expectEqual(@as(usize, 0), statistics[0].live);
    // Explicit close releases the handle before the scope ends.
    try expectPrinted(
        \\def main(fs: Filesystem) -> int:
        \\    with open(fs, "notes.txt", "r")? as f:
        \\        print(len(f.read()))
        \\        f.close()
        \\    return 0
    , "11\n", false);
    try expectTrap(
        \\def main(fs: Filesystem) -> int:
        \\    with open(fs, "written.txt", "w")? as f:
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
        \\    with open(fs, "notes.txt", "rb") as f:
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
        \\    with open(fs, "notes.txt", mode)? as f:
        \\        return 0
    , "E_FILE_ARGUMENT");
    try reject(
        \\def main(fs: Filesystem) -> int:
        \\    with open(fs, "notes.txt", "rb")? as f:
        \\        _ = f.seek(0)
        \\    return 0
    , "E_FILE_ARGUMENT");
    var compilation = try language.Compilation.init(t.allocator, module,
        \\def main(fs: Filesystem) -> int:
        \\    _ = exists(fs, "notes.txt")
        \\    return 0
    );
    defer compilation.deinit();
    try t.expectError(error.SourceError, compilation.emitQbe(t.allocator));
    try t.expectEqualStrings("E_QBE_UNSUPPORTED", compilation.diagnostics.items[0].code);
}

test "file operations report a readable reason for every provider failure" {
    try t.expectEqualStrings("no filesystem authority is available", file_resources.reason(error.Unavailable));
    try t.expectEqualStrings("too many files are open", file_resources.reason(error.ResourceLimit));
    try t.expectEqualStrings("the file is already closed", file_resources.reason(error.InvalidOwner));
    try t.expectEqualStrings("the bytes read are not valid UTF-8 text", file_resources.reason(error.InvalidUtf8));
    try t.expect(std.mem.startsWith(u8, file_resources.reason(error.Denied), "denied"));
    try t.expect(std.mem.startsWith(u8, file_resources.reason(error.Failed), "failed"));
}

test "a program with no granted filesystem provider traps rather than reading anything" {
    var compilation = try language.Compilation.init(t.allocator, module,
        \\def main(fs: Filesystem) -> int:
        \\    _ = exists(fs, "notes.txt")
        \\    return 0
    );
    defer compilation.deinit();
    try t.expectError(error.CapabilityUnavailable, compilation.executeWithOptions(t.allocator, .{}));
}

test "the run helpers name an unexpected trap or an unexpected value as a failure" {
    const empty: language.vm.Result = .{ .trap = .{ .code = "", .message = "", .span = .{ .start = 0, .end = 0 } } };
    try t.expectError(error.Unreachable, value(empty));
    try t.expectError(error.Unreachable, trapCode(.{ .value = -1 }));
}
