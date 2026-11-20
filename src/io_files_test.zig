//! The Python file surface natively: `with open(...)` scopes, handle methods,
//! whole-path helpers, cleanup on every exit, and the effect and grant bounds.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const native = @import("native_execute.zig");
const transition = @import("ownership_transition_test_support.zig");

const module = "io-files.selka";

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

/// Grant a read-only directory holding `notes.txt` and compare everything printed (`@ROOT@` naming the directory).
fn expectPrinted(text: []const u8, expected: []const u8) !void {
    var sandbox: Sandbox = undefined;
    try sandbox.init(false);
    defer sandbox.deinit();
    try sandbox.temporary.dir.writeFile(t.io, .{ .sub_path = "notes.txt", .data = "alpha\nbeta\n" });
    const outcome = try sandbox.run(module, text);
    try t.expectEqualStrings("", outcome.trap.code);
    // `@ROOT@` in `expected` stands for the granted directory's real path, which a refusal names.
    const rooted = try std.mem.replaceOwned(u8, t.allocator, expected, "@ROOT@", sandbox.path);
    defer t.allocator.free(rooted);
    try t.expectEqualStrings(rooted, outcome.stdout);
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

/// Core owns the file-scope lifetime rule; its source still passes frontend typing.
fn rejectOwned(text: []const u8, code: []const u8) !void {
    var compilation = try language.Compilation.init(t.allocator, module, text);
    defer compilation.deinit();
    try compilation.check();
    try t.expect(compilation.program != null);
    try transition.refuses(t.allocator, text, code);
}

// spec: IO-7
test "IO-7 with open binds a handle whose reads follow the declared mode" {
    try expectPrinted(
        \\func main(fs: Filesystem, out: Stream) -> int:
        \\    with fs.open("notes.txt", "rb") as f:
        \\        print(out, f.read())
        \\    return 0
    , "b'alpha\\nbeta\\n'\n");
    try expectPrinted(
        \\func main(fs: Filesystem, out: Stream) -> int:
        \\    with fs.open("notes.txt", "r") as f:
        \\        print(out, f.read(5))
        \\        print(out, f.readline())
        \\    return 0
    , "alpha\n\n\n");
    try expectPrinted(
        \\func main(fs: Filesystem, out: Stream) -> int:
        \\    with fs.open("notes.txt", "r") as f:
        \\        for line in f.readlines():
        \\            print(out, strings.char_count(line))
        \\    return 0
    , "6\n5\n");
}

// A line is read a chunk at a time and the octets past its newline go back to the file, so a
// later read of any kind starts right after the line: across a chunk boundary, a line longer
// than a chunk, and a line that ends at end of file.
test "IO-7 a line read leaves every later read right after its newline" {
    var sandbox: Sandbox = undefined;
    try sandbox.init(false);
    defer sandbox.deinit();
    var text: std.ArrayList(u8) = .empty;
    defer text.deinit(t.allocator);
    try text.appendNTimes(t.allocator, 'x', 20000);
    try text.appendSlice(t.allocator, "\nsecond\n");
    try text.appendNTimes(t.allocator, 'y', 16383);
    try text.appendSlice(t.allocator, "\nthird\nrest");
    try sandbox.temporary.dir.writeFile(t.io, .{ .sub_path = "lines.txt", .data = text.items });
    const outcome = try sandbox.run(module,
        \\func main(fs: Filesystem, out: Stream) -> int:
        \\    with fs.open("lines.txt", "r") as f:
        \\        print(out, len(f.readline()))
        \\        print(out, f.read(3))
        \\        print(out, f.readline())
        \\        print(out, len(f.readline()))
        \\        for line in f.readlines():
        \\            print(out, line)
        \\        print(out, len(f.readline()), len(f.read()))
        \\    return 0
    );
    try t.expectEqualStrings("", outcome.trap.code);
    try t.expectEqualStrings("20001\nsec\nond\n\n16384\nthird\n\nrest\n0 0\n", outcome.stdout);
}

// spec: IO-8
test "IO-8 writing modes create truncate and append through a write grant" {
    var sandbox: Sandbox = undefined;
    try sandbox.init(true);
    defer sandbox.deinit();
    const program =
        \\func main(fs: Filesystem, out: Stream) -> int:
        \\    with fs.open("out.txt", "w") as f:
        \\        print(out, f.write("first\n"))
        \\        f.flush()
        \\    with fs.open("out.txt", "a") as f:
        \\        _ = f.write("second\n")
        \\    with fs.open("out.txt", "w") as f:
        \\        _ = f.write("third\n")
        \\    return 0
    ;
    const outcome = try sandbox.run(module, program);
    try t.expectEqualStrings("6\n", outcome.stdout);
    const written = try sandbox.temporary.dir.readFileAlloc(t.io, "out.txt", t.allocator, .limited(64));
    defer t.allocator.free(written);
    try t.expectEqualStrings("third\n", written);
}

// `f.sync()` answers `Result[Unit, str]`: the appended record is on the file when it answers, a second handle reads it back
// while the first is still open, and a handle opened only to read answers Ok at once (as `flush` does nothing there).
test "FSYNC a synced write is read back by a second handle and a read-only handle answers Ok" {
    var sandbox: Sandbox = undefined;
    try sandbox.init(true);
    defer sandbox.deinit();
    const outcome = try sandbox.run(module,
        \\func main(fs: Filesystem, out: Stream) -> int:
        \\    with fs.open("wal.log", "a") as f:
        \\        print(out, f.sync())
        \\        _ = f.write("one\n")
        \\        print(out, f.sync())
        \\        with fs.open("wal.log", "r") as g:
        \\            print(out, g.read())
        \\            print(out, g.sync())
        \\        _ = f.write("two\n")
        \\        print(out, f.sync())
        \\    print(out, fs.sync_directory(""))
        \\    return 0
    );
    try t.expectEqualStrings("", outcome.trap.code);
    try t.expectEqualStrings("Ok(None)\nOk(None)\none\n\nOk(None)\nOk(None)\nOk(None)\n", outcome.stdout);
    const written = try sandbox.temporary.dir.readFileAlloc(t.io, "wal.log", t.allocator, .limited(64));
    defer t.allocator.free(written);
    try t.expectEqualStrings("one\ntwo\n", written);
}

// A failure of the synchronization is an `Err` a program can show: the system's reason and the path the file was opened under.
// `/dev/full` takes the open (the default grant names it by its absolute path) and has nothing to synchronize.
test "FSYNC a file that cannot be synchronized answers Err with the path and the reason" {
    var sandbox: Sandbox = undefined;
    try sandbox.init(false);
    defer sandbox.deinit();
    const program =
        \\func main(fs: Filesystem, out: Stream) -> int:
        \\    with fs.open("/dev/full", "a") as f:
        \\        match f.sync():
        \\            case Ok(_):
        \\                print(out, "synced")
        \\            case Err(message):
        \\                print(out, message)
        \\    return 0
    ;
    var compilation = try language.Compilation.init(t.allocator, module, program);
    defer compilation.deinit();
    const outcome = try native.runWithOptions(&compilation, .{ .directory = sandbox.path });
    try t.expectEqualStrings("", outcome.trap.code);
    try t.expectEqualStrings("sync '/dev/full': this kind of file cannot be synchronized\n", outcome.stdout);
}

test "FSYNC the method takes no argument and the unknown-method message lists it" {
    try reject(
        \\func main(fs: Filesystem, out: Stream) -> int:
        \\    with fs.open("wal.log", "a") as f:
        \\        _ = f.sync(1)
        \\    return 0
    , "E_ARITY");
    var compilation = try language.Compilation.init(t.allocator, module,
        \\func main(fs: Filesystem, out: Stream) -> int:
        \\    with fs.open("wal.log", "a") as f:
        \\        f.fsync()
        \\    return 0
    );
    defer compilation.deinit();
    try t.expectError(error.SourceError, compilation.check());
    try t.expectEqualStrings("E_FILE_ARGUMENT", compilation.diagnostics.items[0].code);
    try t.expectEqualStrings("unknown file method; open handles support read, readline, readlines, write, flush, sync and close", compilation.diagnostics.items[0].message);
}

// spec: IO-9
test "IO-9 whole-path helpers report provider failures as readable Result errors" {
    var sandbox: Sandbox = undefined;
    try sandbox.init(true);
    defer sandbox.deinit();
    try sandbox.temporary.dir.writeFile(t.io, .{ .sub_path = "notes.txt", .data = "alpha\n" });
    const program =
        \\func main(fs: Filesystem, out: Stream) -> int:
        \\    print(out, fs.read_text("notes.txt"))
        \\    print(out, fs.read_file("notes.txt"))
        \\    print(out, fs.exists("notes.txt"), fs.exists("absent.txt"))
        \\    print(out, fs.write_text("copy.txt", "beta\n"))
        \\    print(out, fs.read_text("copy.txt"))
        \\    print(out, fs.mkdir("sub"))
        \\    print(out, fs.listdir("sub"))
        \\    print(out, fs.remove("copy.txt"))
        \\    print(out, fs.exists("copy.txt"))
        \\    print(out, fs.read_text("absent.txt"))
        \\    print(out, fs.read_text("../escape"))
        \\    return 0
    ;
    const outcome = try sandbox.run(module, program);
    // The escape resolves beside the sandbox, outside its one grant (docs/io.md, "How a path is read").
    const escape = try std.fmt.allocPrint(t.allocator, "Err(\"read '../escape': denied: '{s}/escape' is outside the granted directories\")\n", .{std.fs.path.dirname(sandbox.path).?});
    defer t.allocator.free(escape);
    const expected = try std.mem.concat(t.allocator, u8, &.{ "Ok('alpha\\n')\n" ++
        "Ok(b'alpha\\n')\n" ++
        "True False\n" ++
        "Ok(None)\n" ++
        "Ok('beta\\n')\n" ++
        "Ok(None)\n" ++
        "Ok([])\n" ++
        "Ok(None)\n" ++
        "False\n" ++
        "Err(\"read 'absent.txt': the path does not exist\")\n", escape });
    defer t.allocator.free(expected);
    try t.expectEqualStrings(expected, outcome.stdout);
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
    const program = try std.fmt.allocPrint(t.allocator, "func main(fs: Filesystem, out: Stream) -> int:\n    print(out, fs.read_file(\"{s}\"))\n    return 0\n", .{fifo});
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
        \\func main(fs: Filesystem, out: Stream) -> int:
        \\    print(out, fs.read_file("pipe"))
        \\    return 0
    );
    try t.expectEqualStrings("Err(\"read 'pipe': is not a regular file\")\n", outcome.stdout);
}

// spec: IO-10
test "IO-10 a read-only grant denies every writing mode" {
    var sandbox: Sandbox = undefined;
    try sandbox.init(false);
    defer sandbox.deinit();
    const program =
        \\func main(fs: Filesystem, out: Stream) -> int:
        \\    print(out, fs.write_text("out.txt", "x"))
        \\    print(out, fs.mkdir("sub"))
        \\    print(out, fs.remove("out.txt"))
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
        \\func early(fs: Filesystem) -> int:
        \\    with fs.open("notes.txt", "r") as f:
        \\        return strings.char_count(f.read())
        \\
        \\func looped(fs: Filesystem) -> int:
        \\    mut total = 0
        \\    for index in range(300):
        \\        with fs.open("notes.txt", "r") as f:
        \\            total = total + strings.char_count(f.read())
        \\            if index == 298:
        \\                break
        \\    return total
        \\
        \\func propagated(fs: Filesystem) -> int fails str:
        \\    with try fs.open("notes.txt", "r") as f:
        \\        _ = f.read()
        \\        _ = try fs.read_text("absent.txt")
        \\        return 0
        \\
        \\func main(fs: Filesystem) -> int:
        \\    mut total = early(fs) + looped(fs)
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
        \\func main(fs: Filesystem, out: Stream) -> int:
        \\    with fs.open("notes.txt", "r") as f:
        \\        print(out, strings.char_count(f.read()))
        \\        f.close()
        \\    return 0
    , "11\n");
    try expectTrap(
        \\func main(fs: Filesystem) -> int:
        \\    with fs.open("written.txt", "w") as f:
        \\        f.close()
        \\        _ = f.write("late")
        \\    return 0
    , "R_FILE");
}

// A with-bound file is lent whole to a `mut` argument (tests/lang/with_file_lend.selka); every other use stays refused,
// so the handle cannot leave its scope and be closed twice.
test "a with-bound file is lent as mut but refused as owned, assigned, stored and returned" {
    try rejectOwned(
        \\func my_take(own lease: File) -> bool:
        \\    return True
        \\func main(fs: Filesystem) -> int:
        \\    with fs.open("a.bin", "wb") as lease:
        \\        _ = my_take(own lease)
        \\    return 0
    , "E_WITH_RESOURCE");
    try reject(
        \\func main(fs: Filesystem) -> int:
        \\    with fs.open("a.bin", "wb") as lease:
        \\        with fs.open("b.bin", "wb") as other:
        \\            lease = other
        \\    return 0
    , "E_IMMUTABLE");
    // The record that would hold the lease is refused where it is declared, before any local has its type.
    try reject(
        \\record Holder:
        \\    lease: File
        \\func main(fs: Filesystem) -> int:
        \\    with fs.open("a.bin", "wb") as lease:
        \\        _ = Holder(lease=lease)
        \\    return 0
    , "E_WITH_RESOURCE");
    try rejectOwned(
        \\func keep(fs: Filesystem) -> File:
        \\    with fs.open("a.bin", "wb") as lease:
        \\        return lease
        \\func main() -> int:
        \\    return 0
    , "E_WITH_RESOURCE");
}

// P4 where the type is written: a record that stores an open file is refused at its declaration, with the words that the refusal of a
// local of that type uses (`single_owner_test.zig` pins them), whether or not anything uses the record.
test "a record, list, option, variant, dictionary, generic type or callback that stores an open file is refused where it is declared" {
    const words = "an open file cannot be held inside a list, record, variant or callback type: it belongs to its `with` block; " ++
        "call its methods there, or lend it to a helper declared `mut f: File` and called as `put(mut f, data)`";
    const main = "\nfunc main() -> int:\n    return 0\n";
    const declarations = [_][]const u8{
        "record Holder:\n    f: File\n",
        "record Log:\n    t: TextFile\n",
        "record Bag:\n    files: File[]\n",
        "record Maybe:\n    f: File?\n",
        "enum Slot:\n    Open(f: File)\n    Closed\n",
        "record Reg:\n    m: dict[int, File]\n",
        "record Box[V]:\n    value: V\n\nrecord Uses:\n    b: Box[File]\n",
        "record Outer:\n    h: Holder\n\nrecord Holder:\n    f: File\n",
        "record Callbacks:\n    visit: func(File) -> int\n",
    };
    for (declarations) |declaration| {
        const text = try std.fmt.allocPrint(t.allocator, "{s}{s}", .{ declaration, main });
        defer t.allocator.free(text);
        try rejectNaming(text, "E_WITH_RESOURCE", words);
    }
}

// A generic instance is refused at the spelling that names it, not at the template's field; the template itself is not refused.
test "a generic type instantiated with an open file is refused where it is written, and the template is not" {
    const Case = struct { text: []const u8, spelling: []const u8 };
    const main = "\nfunc main() -> int:\n    return 0\n";
    const cases = [_]Case{
        .{ .text = "record Box[V]:\n    value: V\n\nrecord Uses:\n    b: Box[File]\n" ++ main, .spelling = "Box[File]" },
        .{ .text = "record Box[V]:\n    value: V\n\nfunc use(b: Box[File]) -> int:\n    return 0\n" ++ main, .spelling = "Box[File]" },
        .{ .text = "record Maybe:\n    f: File?\n" ++ main, .spelling = "File?" },
        .{ .text = "func use(f: File?) -> int:\n    return 0\n" ++ main, .spelling = "File?" },
    };
    for (cases) |case| {
        var compilation = try language.Compilation.init(t.allocator, module, case.text);
        defer compilation.deinit();
        try t.expectError(error.SourceError, compilation.check());
        try t.expectEqualStrings("E_WITH_RESOURCE", compilation.diagnostics.items[0].code);
        try t.expectEqualStrings(case.spelling, compilation.src.text(compilation.diagnostics.items[0].span));
    }
    var template = try language.Compilation.init(t.allocator, module,
        \\record Box[V]:
        \\    value: V
        \\
        \\record Uses:
        \\    b: Box[int]
        \\
        \\func main() -> int:
        \\    return 0
    );
    defer template.deinit();
    try template.check();
}

test "a type that hands an open file on, or a helper that lends one, is not a stored file" {
    var compilation = try language.Compilation.init(t.allocator, module,
        \\result Opened:
        \\    ok: File,
        \\    err: int
        \\
        \\record Counter:
        \\    count: int
        \\
        \\func put(mut f: File, line: bytes) -> int:
        \\    return f.write(line)
        \\
        \\func main() -> int:
        \\    return 0
    );
    defer compilation.deinit();
    try compilation.check();
    try t.expectEqual(@as(usize, 0), compilation.diagnostics.items.len);
}

// spec: IO-12
test "IO-12 the file surface is rejected under noio by generic bodies and by the native backend" {
    try reject(
        \\func main(fs: Filesystem) -> int noio:
        \\    _ = fs.exists("notes.txt")
        \\    return 0
    , "E_EFFECTS_REMOVED");
    try reject(
        \\func main(fs: Filesystem) -> int:
        \\    with fs.read_text("notes.txt") as text:
        \\        return 0
    , "E_TYPE");
    try reject(
        \\func main() -> int:
        \\    with 7 as value:
        \\        return 0
    , "E_TYPE");
    try reject(
        \\func main(fs: Filesystem) -> int:
        \\    mut mode = "rb"
        \\    with fs.open("notes.txt", mode) as f:
        \\        return 0
    , "E_FILE_ARGUMENT");
    try reject(
        \\func main(fs: Filesystem) -> int:
        \\    with fs.open("notes.txt", "rb") as f:
        \\        _ = f.seek(0)
        \\    return 0
    , "E_FILE_ARGUMENT");
}

test "a program with no granted filesystem refuses to start rather than reading anything" {
    var compilation = try language.Compilation.init(t.allocator, module,
        \\func main(fs: Filesystem) -> int:
        \\    _ = fs.exists("notes.txt")
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
        \\func main(fs: Filesystem, out: Stream) -> int:
        \\    print(out, fs.read_text("notes.txt"))
        \\    print(out, fs.read_file("notes.txt"))
        \\    print(out, fs.exists("notes.txt"), fs.exists("absent.txt"))
        \\    print(out, fs.write_text("copy.txt", "beta\n"))
        \\    print(out, fs.read_text("copy.txt"))
        \\    print(out, fs.mkdir("sub"))
        \\    print(out, fs.listdir("sub"))
        \\    print(out, fs.write_file("bin.txt", b"raw"))
        \\    print(out, fs.read_file("bin.txt"))
        \\    print(out, fs.remove("copy.txt"))
        \\    print(out, fs.exists("copy.txt"))
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
test "FILE-METHOD-1 write_file names write_text when given text" {
    try rejectNaming(
        \\func main(fs: Filesystem) -> int:
        \\    _ = fs.write_file("notes.txt", "text")
        \\    return 0
    , "E_TYPE", "write_text");
}

// spec-case: FILE-METHOD-1
test "FILE-METHOD-1 the method spelling shares the free form's result types modes and arity" {
    var compilation = try language.Compilation.init(t.allocator, module,
        \\func main(fs: Filesystem) -> int:
        \\    mut text: Result[str, str] = fs.read_text("notes.txt")
        \\    mut raw: Result[bytes, str] = fs.read_file("notes.txt")
        \\    mut listing: Result[str[], str] = fs.listdir(".")
        \\    mut present: bool = fs.exists("notes.txt")
        \\    mut wrote_text: Result[Unit, str] = fs.write_text("copy.txt", "x")
        \\    mut wrote_raw: Result[Unit, str] = fs.write_file("copy.bin", b"x")
        \\    mut made: Result[Unit, str] = fs.mkdir("sub")
        \\    mut dropped: Result[Unit, str] = fs.remove("sub")
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
        \\func main(fs: Filesystem) -> int:
        \\    _ = fs.read_text()
        \\    return 0
    , "E_ARITY");
    try reject(
        \\func main(fs: Filesystem) -> int:
        \\    _ = fs.read_text("a", "b")
        \\    return 0
    , "E_ARITY");
    try reject(
        \\func main(fs: Filesystem) -> int:
        \\    _ = fs.write_text("a")
        \\    return 0
    , "E_ARITY");
    try reject(
        \\func main(fs: Filesystem) -> int:
        \\    _ = fs.exists()
        \\    return 0
    , "E_ARITY");
    try reject(
        \\func main(fs: Filesystem) -> int:
        \\    with fs.open("a") as f:
        \\        _ = f
        \\        return 0
    , "E_ARITY");
    try reject(
        \\func main(fs: Filesystem) -> int:
        \\    mut mode = "r"
        \\    with fs.open("a", mode) as f:
        \\        _ = f
        \\        return 0
    , "E_FILE_ARGUMENT");
    try reject(
        \\func main(fs: Filesystem) -> int:
        \\    mut value: int = fs.read_text("notes.txt")
        \\    return value
    , "E_TYPE");
}

// spec-case: FILE-METHOD-1
test "FILE-METHOD-1 generic bodies reject the method spelling like the free form" {
    try reject(
        \\func look[T](fs: Filesystem, value: T) -> int:
        \\    _ = fs.read_text("x")
        \\    return 0
        \\
        \\func main(fs: Filesystem) -> int:
        \\    return look(fs, 7)
    , "E_GENERIC_BODY_UNSUPPORTED");
}

// spec-case: FILE-METHOD-1
test "FILE-METHOD-1 a same-named function or local keeps the free form while the method stays the receiver's" {
    try expectPrinted(
        \\func read_text(path: str) -> str:
        \\    _ = path
        \\    return "shadowed"
        \\
        \\func main(fs: Filesystem, out: Stream) -> int:
        \\    print(out, read_text("notes.txt"))
        \\    print(out, fs.read_text("notes.txt"))
        \\    return 0
    , "shadowed\nOk('alpha\\nbeta\\n')\n");
    try expectPrinted(
        \\func main(fs: Filesystem, out: Stream) -> int:
        \\    mut exists = 7
        \\    print(out, exists)
        \\    print(out, fs.exists("notes.txt"))
        \\    return 0
    , "7\nTrue\n");
}

// spec-case: FILE-METHOD-1
test "FILE-METHOD-1 with fs.open binds a direct handle and propagates through the method mark" {
    try expectPrinted(
        \\func main(fs: Filesystem, out: Stream) -> int:
        \\    with fs.open("notes.txt", "rb") as f:
        \\        print(out, f.read())
        \\    return 0
    , "b'alpha\\nbeta\\n'\n");
    try expectPrinted(
        \\func count(fs: Filesystem) -> int fails str:
        \\    mut total = 0
        \\    with try fs.open("notes.txt", "r") as f:
        \\        for line in f.readlines():
        \\            total = total + 1
        \\    return total
        \\
        \\func main(fs: Filesystem, out: Stream) -> int:
        \\    match count(fs):
        \\        case Ok(value):
        \\            print(out, value)
        \\        case Err(message):
        \\            print(out, message)
        \\    return 0
    , "2\n");
    try expectTrap(
        \\func main(fs: Filesystem) -> int:
        \\    with fs.open("absent.txt", "r") as f:
        \\        return strings.char_count(f.read())
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
        \\func probe(ctx: Ctx) -> bool noio:
        \\    return ctx.fs.exists("notes.txt")
        \\
        \\func main(fs: Filesystem, clock: Clock) -> int:
        \\    return 0
    , "E_EFFECTS_REMOVED");
    // An unknown method names what the receiver does have; a Clock has none.
    try rejectNaming(holder ++
        \\func main(fs: Filesystem, clock: Clock) -> int:
        \\    mut ctx = Ctx(fs=fs, clock=clock)
        \\    _ = ctx.fs.rename("a", "b")
        \\    return 0
    , "E_COLLECTION_METHOD", "a Filesystem has the methods open, read_file");
    try rejectNaming(holder ++
        \\func main(fs: Filesystem, clock: Clock) -> int:
        \\    mut ctx = Ctx(fs=fs, clock=clock)
        \\    _ = ctx.clock.now()
        \\    return 0
    , "E_COLLECTION_METHOD", "a Clock has no methods");
    // Arity and argument rules are the local spelling's.
    try reject(holder ++
        \\func main(fs: Filesystem, clock: Clock) -> int:
        \\    mut ctx = Ctx(fs=fs, clock=clock)
        \\    _ = ctx.fs.read_text()
        \\    return 0
    , "E_ARITY");
    try reject(holder ++
        \\func main(fs: Filesystem, clock: Clock) -> int:
        \\    mut ctx = Ctx(fs=fs, clock=clock)
        \\    mut mode = "rb"
        \\    with ctx.fs.open("notes.txt", mode) as f:
        \\        return 0
    , "E_FILE_ARGUMENT");
    try reject(holder ++
        \\func main(fs: Filesystem, clock: Clock) -> int:
        \\    mut ctx = Ctx(fs=fs, clock=clock)
        \\    mut name = "data"
        \\    _ = ctx.fs.dir(name)
        \\    return 0
    , "E_FILESYSTEM_DIR");
    // A read-only grant still denies writes and a direct open still traps.
    try expectPrinted(fs_holder ++
        \\func main(fs: Filesystem, out: Stream) -> int:
        \\    mut ctx = Ctx(fs=fs)
        \\    match ctx.fs.write_text("out.txt", "x"):
        \\        case Ok(_):
        \\            print(out, "wrote")
        \\        case Err(message):
        \\            print(out, message)
        \\    match ctx.fs.read_text("notes.txt"):
        \\        case Ok(text):
        \\            print(out, strings.char_count(text))
        \\        case Err(message):
        \\            print(out, message)
        \\    return 0
    , "write 'out.txt': denied: writing needs a write grant (--allow-write); '@ROOT@/out.txt' is granted for reading only\n11\n");
    try expectTrap(fs_holder ++
        \\func main(fs: Filesystem) -> int:
        \\    mut ctx = Ctx(fs=fs)
        \\    with ctx.fs.open("absent.txt", "r") as f:
        \\        return strings.char_count(f.read())
    , "R_FILE");
}

test "O2 frontend with scope errors distinguish type and missing binding" {
    try reject(
        \\func main() -> int:
        \\    with 7 as value:
        \\        return 0
    , "E_TYPE");
    try reject(
        \\func main(fs: Filesystem) -> int:
        \\    with fs.open("notes.txt", "rb"):
        \\        return 0
    , "E_BINDING_DECLARATION");
}

test "O2 file storage in a concrete generic type is refused where the type is written" {
    try reject(
        \\record Envelope[T]:
        \\    value: T
        \\func inspect(own value: Envelope[File]) -> int:
        \\    return 0
        \\func main() -> int:
        \\    return 0
    , "E_WITH_RESOURCE");
}

test "FR28 a bare open(fs, ...) with a mode that is no literal is refused as the removed spelling first, then for its mode" {
    var compilation = try language.Compilation.init(t.allocator, module,
        \\func main(fs: Filesystem) -> int:
        \\    mut mode = "rb"
        \\    with open(fs, "notes.txt", mode) as f:
        \\        return 0
    );
    defer compilation.deinit();
    try t.expectError(error.SourceError, compilation.check());
    try t.expectEqualStrings("E_REMOVED_SPELLING", compilation.diagnostics.items[0].code);
    try t.expectEqualStrings("E_FILE_ARGUMENT", compilation.diagnostics.items[1].code);
}

test "FR28 a bare library channel keeps its wrong operand's type error first: its refusal has no rewrite to put before it" {
    var compilation = try language.Compilation.init(t.allocator, module,
        \\func main(out: Stream, stop: Stop) -> int:
        \\    print(out, stop_control(stop, "read"))
        \\    return 0
    );
    defer compilation.deinit();
    try t.expectError(error.SourceError, compilation.check());
    try t.expectEqualStrings("E_TYPE", compilation.diagnostics.items[0].code);
}

/// Run `text` as a plain run (no `--restrict`) that starts in a fresh directory, so the device paths of the machine are reachable.
fn runPlain(text: []const u8) !native.Run {
    var sandbox: Sandbox = undefined;
    try sandbox.init(true);
    defer sandbox.deinit();
    var compilation = try language.Compilation.init(t.allocator, module, text);
    defer compilation.deinit();
    return native.runWithOptions(&compilation, .{ .directory = sandbox.path }) catch |err| {
        @import("diagnostics_test.zig").report(compilation.diagnostics.items);
        return err;
    };
}

// SP2-F-11, SP3-F-9: a refused write names what the system said, in one sentence for every call that touches the file.
test "a failed write says why: a full device, a missing folder, a directory and a missing file" {
    const outcome = try runPlain(
        \\func note(out: Stream, result: Result[Unit, str]):
        \\    match result:
        \\        case Ok(_):
        \\            print(out, "ok")
        \\        case Err(message):
        \\            print(out, message)
        \\func main(fs: Filesystem, out: Stream) -> int:
        \\    note(out, fs.write_file("/dev/full", b"x"))
        \\    note(out, fs.write_text("/dev/full", "x"))
        \\    note(out, fs.write_text("no/such/folder/x.txt", "x"))
        \\    note(out, fs.atomic_write_file("no/such/folder/x.txt", b"x"))
        \\    note(out, fs.write_text(".", "x"))
        \\    match fs.read_text("absent.txt"):
        \\        case Ok(_):
        \\            print(out, "ok")
        \\        case Err(message):
        \\            print(out, message)
        \\    return 0
    );
    try t.expectEqualStrings("", outcome.trap.code);
    try t.expectEqualStrings(
        "write '/dev/full': no space left on the device\n" ++
            "write '/dev/full': no space left on the device\n" ++
            "write 'no/such/folder/x.txt': a folder on the way does not exist\n" ++
            "atomic write 'no/such/folder/x.txt': a folder on the way does not exist\n" ++
            "write '.': is a directory\n" ++
            "read 'absent.txt': the path does not exist\n",
        outcome.stdout,
    );
}

test "a failed f.write traps R_FILE and names the path and the reason (SP3-F-9)" {
    const outcome = try runPlain(
        \\func main(fs: Filesystem) -> int fails str:
        \\    with try fs.open("/dev/full", "wb") as f:
        \\        _ = f.write(b"hello")
        \\    return 0
    );
    try t.expectEqualStrings("R_FILE", outcome.trap.code);
    try t.expect(std.mem.indexOf(u8, outcome.stderr, "error[R_FILE]: write '/dev/full': no space left on the device\n") != null);
}

test "a read or a close of a closed file traps R_FILE with the path and the reason" {
    const outcome = try runPlain(
        \\func main(fs: Filesystem) -> int fails str:
        \\    with try fs.open("seen.txt", "w") as f:
        \\        f.close()
        \\        _ = f.write("late")
        \\    return 0
    );
    try t.expectEqualStrings("R_FILE", outcome.trap.code);
    try t.expect(std.mem.indexOf(u8, outcome.stderr, "error[R_FILE]: write 'seen.txt': the file is already closed\n") != null);
    const unopened = try runPlain(
        \\func main(fs: Filesystem) -> int:
        \\    with fs.open("absent.txt", "r") as f:
        \\        return len(f.read())
    );
    try t.expectEqualStrings("R_FILE", unopened.trap.code);
    try t.expect(std.mem.indexOf(u8, unopened.stderr, "error[R_FILE]: open 'absent.txt': the path does not exist\n") != null);
}
