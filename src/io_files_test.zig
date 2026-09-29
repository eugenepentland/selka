//! The Python file surface natively: `with open(...)` scopes, handle methods,
//! whole-path helpers, cleanup on every exit, and the effect and grant bounds.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const native = @import("native_execute.zig");

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
        \\def main(fs: Filesystem, out: Stream) -> int:
        \\    with open(fs, "notes.txt", "rb") as f:
        \\        out.print(f.read())
        \\    return 0
    , "b'alpha\\nbeta\\n'\n");
    try expectPrinted(
        \\def main(fs: Filesystem, out: Stream) -> int:
        \\    with open(fs, "notes.txt", "r") as f:
        \\        out.print(f.read(5))
        \\        out.print(f.readline())
        \\    return 0
    , "alpha\n\n\n");
    try expectPrinted(
        \\def main(fs: Filesystem, out: Stream) -> int:
        \\    with open(fs, "notes.txt", "r") as f:
        \\        for line in f.readlines():
        \\            out.print(len(line))
        \\    return 0
    , "6\n5\n");
}

// spec: IO-8
test "IO-8 writing modes create truncate and append through a write grant" {
    var sandbox: Sandbox = undefined;
    try sandbox.init(true);
    defer sandbox.deinit();
    const program =
        \\def main(fs: Filesystem, out: Stream) -> int:
        \\    with open(fs, "out.txt", "w") as f:
        \\        out.print(f.write("first\n"))
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
        \\def main(fs: Filesystem, out: Stream) -> int:
        \\    out.print(read_text(fs, "notes.txt"))
        \\    out.print(read_file(fs, "notes.txt"))
        \\    out.print(exists(fs, "notes.txt"), exists(fs, "absent.txt"))
        \\    out.print(write_text(fs, "copy.txt", "beta\n"))
        \\    out.print(read_text(fs, "copy.txt"))
        \\    out.print(mkdir(fs, "sub"))
        \\    out.print(listdir(fs, "sub"))
        \\    out.print(remove(fs, "copy.txt"))
        \\    out.print(exists(fs, "copy.txt"))
        \\    out.print(read_text(fs, "absent.txt"))
        \\    out.print(read_text(fs, "../escape"))
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

/// Make a FIFO at `path` in the sandbox.
fn makeFifo(path: [:0]const u8) !void {
    const linux = std.os.linux;
    try t.expectEqual(linux.E.SUCCESS, linux.errno(linux.mknod(path, linux.S.IFIFO | 0o600, 0)));
}

/// Open the FIFO for writing, which waits until the guest opens it to read,
/// then write `bytes` and close, so the guest reads them and then end of file.
fn feedFifo(path: [:0]const u8, bytes: []const u8) void {
    const linux = std.os.linux;
    const fd = linux.open(path, .{ .ACCMODE = .WRONLY, .CLOEXEC = true }, 0);
    if (linux.errno(fd) != .SUCCESS) return;
    _ = linux.write(@intCast(fd), bytes.ptr, bytes.len);
    _ = linux.close(@intCast(fd));
}

/// Let a writer that is still waiting for a reader finish: open the FIFO
/// without blocking, wait for the writer, and only then close the read end, so
/// the writer never writes into a pipe with no reader.
fn finishFifo(path: [:0]const u8, writer: std.Thread) void {
    const linux = std.os.linux;
    const fd = linux.open(path, .{ .ACCMODE = .RDONLY, .NONBLOCK = true, .CLOEXEC = true }, 0);
    writer.join();
    if (linux.errno(fd) == .SUCCESS) _ = linux.close(@intCast(fd));
}

// A shell's process substitution `<(...)` hands a program `/dev/fd/N`, a pipe;
// the default grant opens it the way `fopen` does and reads to end of file.
// spec: CAPABILITY-6
test "the default grant reads a FIFO named by its absolute path the way fopen does" {
    var sandbox: Sandbox = undefined;
    try sandbox.init(false);
    defer sandbox.deinit();
    const fifo = try std.fs.path.joinZ(t.allocator, &.{ sandbox.path, "pipe" });
    defer t.allocator.free(fifo);
    try makeFifo(fifo);
    const program = try std.fmt.allocPrint(t.allocator, "def main(fs: Filesystem, out: Stream) -> int:\n    out.print(read_file(fs, \"{s}\"))\n    return 0\n", .{fifo});
    defer t.allocator.free(program);
    var compilation = try language.Compilation.init(t.allocator, module, program);
    defer compilation.deinit();
    const writer = try std.Thread.spawn(.{}, feedFifo, .{ fifo, "print 1;\n" });
    const outcome = native.runWithOptions(&compilation, .{ .directory = sandbox.path });
    finishFifo(fifo, writer);
    try t.expectEqualStrings("Ok(b'print 1;\\n')\n", (try outcome).stdout);
}

// Under `--restrict` a granted directory still serves regular files only, and
// a FIFO in it is refused at once rather than waiting for a writer.
// spec-case: CAPABILITY-6
test "a restricted grant refuses a FIFO inside the granted directory without blocking" {
    var sandbox: Sandbox = undefined;
    try sandbox.init(false);
    defer sandbox.deinit();
    const fifo = try std.fs.path.joinZ(t.allocator, &.{ sandbox.path, "pipe" });
    defer t.allocator.free(fifo);
    try makeFifo(fifo);
    const outcome = try sandbox.run(module,
        \\def main(fs: Filesystem, out: Stream) -> int:
        \\    out.print(read_file(fs, "pipe"))
        \\    return 0
    );
    try t.expectEqualStrings("Err('read \\'pipe\\': denied: outside the granted directories, or the mode needs a write grant')\n", outcome.stdout);
}

// spec: IO-10
test "IO-10 a read-only grant denies every writing mode" {
    var sandbox: Sandbox = undefined;
    try sandbox.init(false);
    defer sandbox.deinit();
    const program =
        \\def main(fs: Filesystem, out: Stream) -> int:
        \\    out.print(write_text(fs, "out.txt", "x"))
        \\    out.print(mkdir(fs, "sub"))
        \\    out.print(remove(fs, "out.txt"))
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
        \\def main(fs: Filesystem, out: Stream) -> int:
        \\    with open(fs, "notes.txt", "r") as f:
        \\        out.print(len(f.read()))
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

// spec: FILE-METHOD-1
test "FILE-METHOD-1 the whole-path helpers accept the qualified method spelling" {
    var sandbox: Sandbox = undefined;
    try sandbox.init(true);
    defer sandbox.deinit();
    try sandbox.temporary.dir.writeFile(t.io, .{ .sub_path = "notes.txt", .data = "alpha\n" });
    const program =
        \\def main(fs: Filesystem, out: Stream) -> int:
        \\    out.print(fs.read_text("notes.txt"))
        \\    out.print(fs.read_file("notes.txt"))
        \\    out.print(fs.exists("notes.txt"), fs.exists("absent.txt"))
        \\    out.print(fs.write_text("copy.txt", "beta\n"))
        \\    out.print(fs.read_text("copy.txt"))
        \\    out.print(fs.mkdir("sub"))
        \\    out.print(fs.listdir("sub"))
        \\    out.print(fs.write_file("bin.txt", b"raw"))
        \\    out.print(fs.read_file("bin.txt"))
        \\    out.print(fs.remove("copy.txt"))
        \\    out.print(fs.exists("copy.txt"))
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
            "Ok(b'raw')\n" ++
            "Ok(None)\n" ++
            "False\n",
        outcome.stdout,
    );
}

// spec-case: FILE-METHOD-1
test "FILE-METHOD-1 the method spelling shares the free form's result types modes and arity" {
    var compilation = try language.Compilation.init(t.allocator, module,
        \\def main(fs: Filesystem) -> int:
        \\    text: Result[str, str] = fs.read_text("notes.txt")
        \\    raw: Result[bytes, str] = fs.read_file("notes.txt")
        \\    listing: Result[list[str], str] = fs.listdir(".")
        \\    present: bool = fs.exists("notes.txt")
        \\    wrote_text: Result[None, str] = fs.write_text("copy.txt", "x")
        \\    wrote_raw: Result[None, str] = fs.write_file("copy.bin", b"x")
        \\    made: Result[None, str] = fs.mkdir("sub")
        \\    dropped: Result[None, str] = fs.remove("sub")
        \\    _ = text
        \\    _ = raw
        \\    _ = listing
        \\    _ = present
        \\    _ = wrote_text
        \\    _ = wrote_raw
        \\    _ = made
        \\    _ = dropped
        \\    return 0
    );
    defer compilation.deinit();
    try compilation.check();
    try reject(
        \\def main(fs: Filesystem) -> int:
        \\    _ = fs.read_text()
        \\    return 0
    , "E_ARITY");
    try reject(
        \\def main(fs: Filesystem) -> int:
        \\    _ = fs.read_text("a", "b")
        \\    return 0
    , "E_ARITY");
    try reject(
        \\def main(fs: Filesystem) -> int:
        \\    _ = fs.write_text("a")
        \\    return 0
    , "E_ARITY");
    try reject(
        \\def main(fs: Filesystem) -> int:
        \\    _ = fs.exists()
        \\    return 0
    , "E_ARITY");
    try reject(
        \\def main(fs: Filesystem) -> int:
        \\    with fs.open("a") as f:
        \\        _ = f
        \\        return 0
    , "E_ARITY");
    try reject(
        \\def main(fs: Filesystem) -> int:
        \\    mode = "r"
        \\    with fs.open("a", mode) as f:
        \\        _ = f
        \\        return 0
    , "E_FILE_ARGUMENT");
    try reject(
        \\def main(fs: Filesystem) -> int:
        \\    value: int = fs.read_text("notes.txt")
        \\    return value
    , "E_TYPE");
}

// spec-case: FILE-METHOD-1
test "FILE-METHOD-1 generic bodies reject the method spelling like the free form" {
    try reject(
        \\def look[T](fs: Filesystem, value: T) -> int:
        \\    _ = fs.read_text("x")
        \\    return 0
        \\
        \\def main(fs: Filesystem) -> int:
        \\    return look(fs, 7)
    , "E_GENERIC_BODY_UNSUPPORTED");
}

// spec-case: FILE-METHOD-1
test "FILE-METHOD-1 a same-named function or local keeps the free form while the method stays the receiver's" {
    try expectPrinted(
        \\def read_text(path: str) -> str:
        \\    _ = path
        \\    return "shadowed"
        \\
        \\def main(fs: Filesystem, out: Stream) -> int:
        \\    out.print(read_text("notes.txt"))
        \\    out.print(fs.read_text("notes.txt"))
        \\    return 0
    , "shadowed\nOk('alpha\\nbeta\\n')\n");
    try expectPrinted(
        \\def main(fs: Filesystem, out: Stream) -> int:
        \\    exists = 7
        \\    out.print(exists)
        \\    out.print(fs.exists("notes.txt"))
        \\    return 0
    , "7\nTrue\n");
}

// spec-case: FILE-METHOD-1
test "FILE-METHOD-1 with fs.open binds a direct handle and propagates through the method mark" {
    try expectPrinted(
        \\def main(fs: Filesystem, out: Stream) -> int:
        \\    with fs.open("notes.txt", "rb") as f:
        \\        out.print(f.read())
        \\    return 0
    , "b'alpha\\nbeta\\n'\n");
    try expectPrinted(
        \\def count(fs: Filesystem) -> Result[int, str]:
        \\    total = 0
        \\    with fs.open("notes.txt", "r")? as f:
        \\        for line in f.readlines():
        \\            total = total + 1
        \\    return Ok(total)
        \\
        \\def main(fs: Filesystem, out: Stream) -> int:
        \\    match count(fs):
        \\        case Ok(value):
        \\            out.print(value)
        \\        case Err(message):
        \\            out.print(message)
        \\    return 0
    , "2\n");
    try expectTrap(
        \\def main(fs: Filesystem) -> int:
        \\    with fs.open("absent.txt", "r") as f:
        \\        return len(f.read())
    , "R_FILE");
}

/// Reject `text` with `code` and require the first message to contain `fragment`.
fn rejectNaming(text: []const u8, code: []const u8, fragment: []const u8) !void {
    var compilation = try language.Compilation.init(t.allocator, module, text);
    defer compilation.deinit();
    try t.expectError(error.SourceError, compilation.check());
    try t.expectEqualStrings(code, compilation.diagnostics.items[0].code);
    try t.expect(std.mem.indexOf(u8, compilation.diagnostics.items[0].message, fragment) != null);
}

const holder =
    \\record Ctx:
    \\    fs: Filesystem
    \\    clock: Clock
    \\
    \\
;

const fs_holder =
    \\record Ctx:
    \\    fs: Filesystem
    \\
    \\
;

// spec-case: CAPABILITY-FIELD-METHOD-1
test "CAPABILITY-FIELD-METHOD-1 a capability field keeps the effect, grant and trap rules of a local" {
    // `noio` withholds the filesystem effect from the field spelling as from a local.
    try reject(holder ++
        \\def probe(ctx: Ctx) -> bool noio:
        \\    return ctx.fs.exists("notes.txt")
        \\
        \\def main(fs: Filesystem, clock: Clock) -> int:
        \\    return 0
    , "E_EFFECT_BOUND");
    // An unknown method names what the receiver does have; a Clock has none.
    try rejectNaming(holder ++
        \\def main(fs: Filesystem, clock: Clock) -> int:
        \\    ctx = Ctx(fs=fs, clock=clock)
        \\    _ = ctx.fs.rename("a", "b")
        \\    return 0
    , "E_COLLECTION_METHOD", "a Filesystem has the methods open, read_file");
    try rejectNaming(holder ++
        \\def main(fs: Filesystem, clock: Clock) -> int:
        \\    ctx = Ctx(fs=fs, clock=clock)
        \\    _ = ctx.clock.now()
        \\    return 0
    , "E_COLLECTION_METHOD", "a Clock has no methods");
    // Arity and argument rules are the local spelling's.
    try reject(holder ++
        \\def main(fs: Filesystem, clock: Clock) -> int:
        \\    ctx = Ctx(fs=fs, clock=clock)
        \\    _ = ctx.fs.read_text()
        \\    return 0
    , "E_ARITY");
    try reject(holder ++
        \\def main(fs: Filesystem, clock: Clock) -> int:
        \\    ctx = Ctx(fs=fs, clock=clock)
        \\    mode = "rb"
        \\    with ctx.fs.open("notes.txt", mode) as f:
        \\        return 0
    , "E_FILE_ARGUMENT");
    try reject(holder ++
        \\def main(fs: Filesystem, clock: Clock) -> int:
        \\    ctx = Ctx(fs=fs, clock=clock)
        \\    name = "data"
        \\    _ = ctx.fs.dir(name)
        \\    return 0
    , "E_FILESYSTEM_DIR");
    // A read-only grant still denies writes and a direct open still traps.
    try expectPrinted(fs_holder ++
        \\def main(fs: Filesystem, out: Stream) -> int:
        \\    ctx = Ctx(fs=fs)
        \\    match ctx.fs.write_text("out.txt", "x"):
        \\        case Ok(_):
        \\            out.print("wrote")
        \\        case Err(message):
        \\            out.print(message)
        \\    match ctx.fs.read_text("notes.txt"):
        \\        case Ok(text):
        \\            out.print(len(text))
        \\        case Err(message):
        \\            out.print(message)
        \\    return 0
    , "write 'out.txt': denied: outside the granted directories, or the mode needs a write grant\n11\n");
    try expectTrap(fs_holder ++
        \\def main(fs: Filesystem) -> int:
        \\    ctx = Ctx(fs=fs)
        \\    with ctx.fs.open("absent.txt", "r") as f:
        \\        return len(f.read())
    , "R_FILE");
}
