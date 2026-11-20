//! A stop that reaches the compiler alone (RUN-SIGNALS-1). `selka run` used to end by SIGTERM and leave its program
//! running with no parent; now SIGTERM, SIGINT and SIGHUP are passed on while the compiler waits, and a compiler killed
//! outright takes the program (and, for `selka test`, the test processes) with it. Every test starts the compiler as a
//! child, signals that one process, and then looks for the program in `/proc`. The programs bound themselves (20 s of
//! sleeping, `--timeout`, the step ceiling), so a test that fails leaves nothing running for long.
const std = @import("std");
const testing = std.testing;
const paths_module = @import("test_paths");

const waiter_source = @embedFile("fixtures/run_signals_waiter.selka");
const hearer_source = @embedFile("fixtures/run_signals_hearer.selka");
const hearer_c = @embedFile("fixtures/run_signals_hearer.c");
const burner_source = @embedFile("fixtures/run_signals_burner.selka");
/// A server that declares a `Stop`, the same server without one, and a program whose goodbye takes 2 s (FR5b, STOP-1).
const stop_server_source = @embedFile("fixtures/stop_server.selka");
const stop_server_default_source = @embedFile("fixtures/stop_server_default.selka");
const stop_linger_source = @embedFile("fixtures/stop_linger.selka");
/// The same with a 0.3 s goodbye, run many times by one test.
const stop_quick_source = @embedFile("fixtures/stop_quick.selka");
/// A program that returns at once when it hears a stop.
const stop_instant_source = @embedFile("fixtures/stop_instant.selka");
/// A program that burns for about twenty seconds, as the example of a documentation page (FR19).
const doctest_example = @embedFile("fixtures/run_signals_doctest_example.selka");
/// The locked library and the application of the packages test: the application is the waiter, importing the library.
const library_source = "\n\npublic func answer() -> int:\n    return 42\n";

/// A compiler process started by a test: its standard error is a pipe, its standard output and input are closed off.
const Compiler = struct {
    child: std.process.Child,
    environment: std.process.Environ.Map,
    directory: [:0]const u8,

    fn deinit(self: *Compiler) void {
        if (self.child.id != null) self.child.kill(testing.io);
        self.environment.deinit();
        testing.allocator.free(self.directory);
    }

    /// The process number the guest printed as `guest /proc/NUMBER` on standard error, read once the build is done.
    fn guestPid(self: *Compiler) !std.posix.pid_t {
        var buffer: [4096]u8 = undefined;
        var reader = self.child.stderr.?.readerStreaming(testing.io, &buffer);
        while (true) {
            const line = try reader.interface.takeDelimiterInclusive('\n');
            const marker = "guest /proc/";
            if (std.mem.startsWith(u8, line, marker)) return try std.fmt.parseInt(std.posix.pid_t, std.mem.trimEnd(u8, line[marker.len..], "\n"), 10);
        }
    }

    /// Everything the compiler still writes to standard error, up to its end.
    fn restOfStderr(self: *Compiler) ![]u8 {
        var buffer: [4096]u8 = undefined;
        var reader = self.child.stderr.?.readerStreaming(testing.io, &buffer);
        return reader.interface.allocRemaining(testing.allocator, .limited(1 << 20));
    }

    /// The next line the program writes to standard output, waited for: it is read as soon as the program's output reaches
    /// the pipe, which is the point of the tests below.
    fn stdoutLine(self: *Compiler, buffer: []u8) ![]const u8 {
        var reader = self.child.stdout.?.readerStreaming(testing.io, buffer);
        return reader.interface.takeDelimiterInclusive('\n');
    }

    /// Send the program `text` on its standard input and close it.
    fn feed(self: *Compiler, text: []const u8) !void {
        try self.child.stdin.?.writeStreamingAll(testing.io, text);
        self.child.stdin.?.close(testing.io);
        self.child.stdin = null;
    }

    fn signal(self: *Compiler, which: std.posix.SIG) !void {
        try std.posix.kill(self.child.id.?, which);
    }

    /// How the compiler ended.
    fn wait(self: *Compiler) !std.process.Child.Term {
        return self.child.wait(testing.io);
    }
};

/// The options every command here passes beside its own: a private cache and the toolchain `zig build` names.
const shared = [_][]const u8{ "--cache-dir", "cache", "--zig=" ++ @import("test_options").zig_path };

/// Start `selka ARGS` in `directory`, which already holds the fixtures. Its temporary files go under `directory`.
fn start(directory: std.Io.Dir, args: []const []const u8) !Compiler {
    return startWith(directory, args, .ignore, .ignore);
}

/// `start` with standard input and output as pipes the test reads and writes, for a program that talks while it runs.
fn startPiped(directory: std.Io.Dir, args: []const []const u8) !Compiler {
    return startWith(directory, args, .pipe, .pipe);
}

fn startWith(directory: std.Io.Dir, args: []const []const u8, stdin: std.process.SpawnOptions.StdIo, stdout: std.process.SpawnOptions.StdIo) !Compiler {
    return startIn(directory, args, .{ .stdin = stdin, .stdout = stdout });
}

/// How `startIn` starts a compiler: its standard input and output, and whether every store it reuses is empty, so that the
/// C runtime is compiled by `zig cc` (a build that finds its objects in a store starts no `zig`).
/// `group` starts it as the leader of a process group of its own, so a test can signal the whole group.
const Launch = struct { stdin: std.process.SpawnOptions.StdIo = .ignore, stdout: std.process.SpawnOptions.StdIo = .ignore, cold: bool = false, group: bool = false };

/// `start` with a cold start of the stores, for a build that must run `zig cc`.
fn startCold(directory: std.Io.Dir, args: []const []const u8) !Compiler {
    return startIn(directory, args, .{ .cold = true });
}

fn startIn(directory: std.Io.Dir, args: []const []const u8, launch: Launch) !Compiler {
    var environment = try paths_module.privateEnvironment(testing.allocator);
    errdefer environment.deinit();
    // `selka test` plans its cache through a component, which an uninstalled compiler finds by this variable.
    if (testing.environ.getPosix("SELKA_COMPONENT_DIR")) |component| try environment.put("SELKA_COMPONENT_DIR", component);
    const root = try directory.realPathFileAlloc(testing.io, ".", testing.allocator);
    errdefer testing.allocator.free(root);
    // A packages build stages its snapshot under TMPDIR and a killed one cannot remove it: keep it inside the test's directory.
    try environment.put("TMPDIR", root);
    try environment.put("SELKA_ZIG", @import("test_options").zig_path);
    if (launch.cold) {
        const stores = [_][2][]const u8{ .{ "XDG_CACHE_HOME", "xdg" }, .{ "SELKA_CORE_RUNTIME_CACHE", "runtime" }, .{ "SELKA_STAGE_SHARED_CACHE", "stages" } };
        for (stores) |store| {
            const path = try std.fs.path.join(testing.allocator, &.{ root, store[1] });
            defer testing.allocator.free(path);
            try environment.put(store[0], path);
        }
    }
    const compiler = try std.Io.Dir.cwd().realPathFileAlloc(testing.io, paths_module.corePath(), testing.allocator);
    defer testing.allocator.free(compiler);
    var argv: std.ArrayList([]const u8) = .empty;
    defer argv.deinit(testing.allocator);
    try argv.append(testing.allocator, compiler);
    try argv.appendSlice(testing.allocator, args);
    const child = try std.process.spawn(testing.io, .{ .argv = argv.items, .cwd = .{ .dir = directory }, .environ_map = &environment, .stdin = launch.stdin, .stdout = launch.stdout, .stderr = .pipe, .pgid = if (launch.group) 0 else null });
    return .{ .child = child, .environment = environment, .directory = root };
}

/// Whether process `pid` is running: a zombie waiting to be collected has ended.
fn running(pid: std.posix.pid_t) bool {
    var path_buffer: [64]u8 = undefined;
    const path = std.fmt.bufPrint(&path_buffer, "/proc/{d}/stat", .{pid}) catch return false;
    var text: [512]u8 = undefined;
    const length = (std.Io.Dir.cwd().readFile(testing.io, path, &text) catch return false).len;
    const close = std.mem.lastIndexOfScalar(u8, text[0..length], ')') orelse return false;
    return close + 2 < length and text[close + 2] != 'Z' and text[close + 2] != 'X';
}

/// Whether every process of `pids` has ended, looked for for at most ten seconds.
fn allGone(pids: []const std.posix.pid_t) bool {
    for (0..100) |_| {
        var any = false;
        for (pids) |pid| any = any or running(pid);
        if (!any) return true;
        testing.io.sleep(.fromMilliseconds(100), .awake) catch return false;
    }
    return false;
}

/// The processes started under `root` and under those, from the `children` files in `/proc`, whose program lies under `prefix`.
fn programsUnder(root: std.posix.pid_t, prefix: []const u8, found: *std.ArrayList(std.posix.pid_t)) !void {
    var pending: std.ArrayList(std.posix.pid_t) = .empty;
    defer pending.deinit(testing.allocator);
    try pending.append(testing.allocator, root);
    while (pending.pop()) |pid| {
        var tasks_buffer: [64]u8 = undefined;
        const tasks_path = try std.fmt.bufPrint(&tasks_buffer, "/proc/{d}/task", .{pid});
        var tasks = std.Io.Dir.cwd().openDir(testing.io, tasks_path, .{ .iterate = true }) catch continue;
        defer tasks.close(testing.io);
        var walk = tasks.iterate();
        while (try walk.next(testing.io)) |task| {
            var path_buffer: [96]u8 = undefined;
            const path = try std.fmt.bufPrint(&path_buffer, "/proc/{d}/task/{s}/children", .{ pid, task.name });
            var text: [1024]u8 = undefined;
            const list = std.Io.Dir.cwd().readFile(testing.io, path, &text) catch continue;
            var numbers = std.mem.tokenizeScalar(u8, list, ' ');
            while (numbers.next()) |number| {
                const child = std.fmt.parseInt(std.posix.pid_t, number, 10) catch continue;
                try pending.append(testing.allocator, child);
                if (lies(child, prefix)) try found.append(testing.allocator, child);
            }
        }
    }
}

/// Look for at least `wanted` programs under `prefix` below `root`, for at most a minute; `found` holds the last sight.
fn waitForPrograms(root: std.posix.pid_t, prefix: []const u8, wanted: usize, found: *std.ArrayList(std.posix.pid_t)) !void {
    for (0..600) |_| {
        found.clearRetainingCapacity();
        try programsUnder(root, prefix, found);
        if (found.items.len >= wanted) return;
        try testing.io.sleep(.fromMilliseconds(100), .awake);
    }
}

/// Whether process `pid` runs a program under `prefix`.
fn lies(pid: std.posix.pid_t, prefix: []const u8) bool {
    var path_buffer: [64]u8 = undefined;
    const path = std.fmt.bufPrint(&path_buffer, "/proc/{d}/exe", .{pid}) catch return false;
    var target: [std.fs.max_path_bytes]u8 = undefined;
    const length = std.Io.Dir.cwd().readLink(testing.io, path, &target) catch return false;
    return std.mem.startsWith(u8, target[0..length], prefix);
}

/// Run `waiter` with `selka run`, send `which` to the compiler process alone, and require that the compiler ended by that
/// signal (the status a shell reports as 128 plus it) and that the program it started is gone.
fn expectGuestEndsWithCompiler(which: std.posix.SIG) !void {
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "waiter.selka", .data = waiter_source });
    var compiler = try start(temporary.dir, &([_][]const u8{ "run", "waiter.selka", "--timeout", "30" } ++ shared));
    defer compiler.deinit();
    const guest = try compiler.guestPid();
    try testing.expect(running(guest));
    try compiler.signal(which);
    const term = try compiler.wait();
    try testing.expectEqual(std.process.Child.Term{ .signal = which }, term);
    try testing.expect(allGone(&.{guest}));
}

test "SIGTERM sent to selka run alone ends the program it started, and the compiler ends by SIGTERM" {
    try expectGuestEndsWithCompiler(.TERM);
}

test "SIGINT sent to selka run alone ends the program it started, and the compiler ends by SIGINT" {
    try expectGuestEndsWithCompiler(.INT);
}

test "SIGHUP sent to selka run alone ends the program it started, and the compiler ends by SIGHUP" {
    try expectGuestEndsWithCompiler(.HUP);
}

test "a selka run killed outright with SIGKILL takes its program with it" {
    try expectGuestEndsWithCompiler(.KILL);
}

test "a program that hears the stop hears it once, and selka run ends with the program's own status" {
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "hearer.selka", .data = hearer_source });
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "hearer.c", .data = hearer_c });
    var compiler = try start(temporary.dir, &([_][]const u8{ "run", "hearer.selka", "--link", "hearer.c", "--timeout", "30" } ++ shared));
    defer compiler.deinit();
    const guest = try compiler.guestPid();
    try compiler.signal(.TERM);
    const rest = try compiler.restOfStderr();
    defer testing.allocator.free(rest);
    try testing.expectEqual(std.process.Child.Term{ .exited = 7 }, try compiler.wait());
    try testing.expectEqualStrings("heard 1\n", rest);
    try testing.expect(allGone(&.{guest}));
}

test "a selka test killed outright with SIGKILL takes its test processes with it" {
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "burn.selka", .data = burner_source });
    var compiler = try start(temporary.dir, &([_][]const u8{ "test", "burn.selka", "--max-steps", "4000000000", "--timeout-ms", "30000" } ++ shared));
    defer compiler.deinit();
    const prefix = try std.fmt.allocPrint(testing.allocator, "{s}/cache/tests/", .{compiler.directory});
    defer testing.allocator.free(prefix);
    var processes: std.ArrayList(std.posix.pid_t) = .empty;
    defer processes.deinit(testing.allocator);
    // The test program and the forked trial that runs the test: both appear once the build is done.
    try waitForPrograms(compiler.child.id.?, prefix, 2, &processes);
    try testing.expect(processes.items.len >= 2);
    try compiler.signal(.KILL);
    try testing.expectEqual(std.process.Child.Term{ .signal = .KILL }, try compiler.wait());
    try testing.expect(allGone(processes.items));
}

/// The processes that are direct children of `parent` and run a program under `prefix`.
fn childrenUnder(parent: std.posix.pid_t, prefix: []const u8, found: *std.ArrayList(std.posix.pid_t)) !void {
    var tasks_buffer: [64]u8 = undefined;
    const tasks_path = try std.fmt.bufPrint(&tasks_buffer, "/proc/{d}/task", .{parent});
    var tasks = std.Io.Dir.cwd().openDir(testing.io, tasks_path, .{ .iterate = true }) catch return;
    defer tasks.close(testing.io);
    var walk = tasks.iterate();
    while (try walk.next(testing.io)) |task| {
        var path_buffer: [96]u8 = undefined;
        const path = try std.fmt.bufPrint(&path_buffer, "/proc/{d}/task/{s}/children", .{ parent, task.name });
        var text: [1024]u8 = undefined;
        const list = std.Io.Dir.cwd().readFile(testing.io, path, &text) catch continue;
        var numbers = std.mem.tokenizeScalar(u8, list, ' ');
        while (numbers.next()) |number| {
            const child = std.fmt.parseInt(std.posix.pid_t, number, 10) catch continue;
            if (lies(child, prefix)) try found.append(testing.allocator, child);
        }
    }
}

/// Whether every process of `pids` has ended within `milliseconds`.
fn goneWithin(pids: []const std.posix.pid_t, milliseconds: u32) bool {
    var waited: u32 = 0;
    while (true) : (waited += 50) {
        var any = false;
        for (pids) |pid| any = any or running(pid);
        if (!any) return true;
        if (waited >= milliseconds) return false;
        testing.io.sleep(.fromMilliseconds(50), .awake) catch return false;
    }
}

test "a selka doctest killed outright takes its child compiler and the example's program with it (FR19)" {
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.createDirPath(testing.io, "repo/docs");
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "repo/docs/burn.md", .data = "# A page whose example burns\n\n```selka\n" ++ doctest_example ++ "```\n" });
    var compiler = try start(temporary.dir, &.{ "doctest", "repo" });
    defer compiler.deinit();
    // The example's program lies under the temporary tree, where TMPDIR sends the doctest's workspace; the child compiler
    // that runs it is the doctest's own program and lies elsewhere.
    var program: std.ArrayList(std.posix.pid_t) = .empty;
    defer program.deinit(testing.allocator);
    try waitForPrograms(compiler.child.id.?, compiler.directory, 1, &program);
    try testing.expect(program.items.len >= 1);
    var everything: std.ArrayList(std.posix.pid_t) = .empty;
    defer everything.deinit(testing.allocator);
    try programsUnder(compiler.child.id.?, "", &everything);
    try testing.expect(everything.items.len >= 2);
    try compiler.signal(.KILL);
    try testing.expectEqual(std.process.Child.Term{ .signal = .KILL }, try compiler.wait());
    try testing.expect(allGone(everything.items));
}

test "a build killed outright takes the zig process it started with it, at once (FR19)" {
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "prog.selka", .data = "func main() -> int:\n    return 7\n" });
    // The cold build compiles the C runtime with `zig cc`, which takes seconds: long enough to be seen and killed.
    var compiler = try startCold(temporary.dir, &([_][]const u8{ "build", "prog.selka", "-o", "prog" } ++ shared));
    defer compiler.deinit();
    const toolchain = std.fs.path.dirname(@import("test_options").zig_path) orelse "/";
    var started: std.ArrayList(std.posix.pid_t) = .empty;
    defer started.deinit(testing.allocator);
    for (0..600) |_| {
        started.clearRetainingCapacity();
        try childrenUnder(compiler.child.id.?, toolchain, &started);
        if (started.items.len >= 1) break;
        try testing.io.sleep(.fromMilliseconds(50), .awake);
    }
    try testing.expect(started.items.len >= 1);
    try compiler.signal(.KILL);
    try testing.expectEqual(std.process.Child.Term{ .signal = .KILL }, try compiler.wait());
    // The `zig cc` the compiler started ends with it. (Its own child, `zig clang`, finishes the one file it is compiling; a
    // process the compiler did not start is not the compiler's to end.)
    try testing.expect(goneWithin(started.items, 1500));
}

/// Lock `library/numbers.selka`, then start `selka packages build app/main.selka --command run-project` over the waiter, so
/// that the guest is a grandchild of the compiler process the test signals. Returns it, the guest's number read.
fn startPackaged(directory: std.Io.Dir) !Compiler {
    try directory.createDirPath(testing.io, "library");
    try directory.createDirPath(testing.io, "app");
    try directory.writeFile(testing.io, .{ .sub_path = "library/numbers.selka", .data = library_source });
    try directory.writeFile(testing.io, .{ .sub_path = "packages.json", .data = "{\"packages\":[{\"name\":\"numbers\",\"root\":\"library\"}]}" });
    try directory.writeFile(testing.io, .{ .sub_path = "app/main.selka", .data = "import numbers\n" ++ waiter_source });
    var locking = try start(directory, &.{ "packages", "lock", "packages.json", "--output", "lock.json" });
    defer locking.deinit();
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, try locking.wait());
    return start(directory, &([_][]const u8{ "packages", "build", "app/main.selka", "--lock", "lock.json", "--command", "run-project", "--" } ++ [_][]const u8{ "--timeout", "30" } ++ shared));
}

/// Run the waiter through `selka packages build --command run-project`, send `which` to the `packages` process alone, and
/// require that it ended by that signal and that the guest, started by the `run-project` it started, is gone.
fn expectPackagedGuestEndsWithPackages(which: std.posix.SIG) !void {
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    var compiler = try startPackaged(temporary.dir);
    defer compiler.deinit();
    const guest = try compiler.guestPid();
    try testing.expect(running(guest));
    try compiler.signal(which);
    try testing.expectEqual(std.process.Child.Term{ .signal = which }, try compiler.wait());
    try testing.expect(allGone(&.{guest}));
}

test "SIGTERM sent to selka packages build alone ends the program its run-project started" {
    try expectPackagedGuestEndsWithPackages(.TERM);
}

test "a selka packages build killed outright with SIGKILL takes its run-project and the program with it" {
    try expectPackagedGuestEndsWithPackages(.KILL);
}

/// What every program below starts with: its process number on standard error, for `guestPid`.
const announce =
    \\    match filesystem.realpath(fs, "/proc/self"):
    \\        case Ok(path):
    \\            print(err, "guest " + path)
    \\        case Err(_):
    \\            return 1
    \\
;

/// A program that prints `ready`, then waits in the poller for up to 10 s.
const poller_source =
    "import filesystem\nimport network\n\n\n" ++
    "func main(net: Network, fs: Filesystem, out: Stream, err: Stream) -> int:\n" ++ announce ++
    \\    with net.host("127.0.0.1:0") as scoped:
    \\        match network.open_poller(scoped):
    \\            case ok(poller):
    \\                mut polled = own poller
    \\                mut ready = network.new_ready()
    \\                print(out, "ready")
    \\                mut turns = 0
    \\                while turns < 200:
    \\                    polled = network.wait(own polled, 50, mut ready)
    \\                    turns = turns + 1
    \\                _ = own polled
    \\                return 0
    \\            case err(_):
    \\                return 2
    \\
    ;

/// A program that prints a prompt and reads one line of standard input.
const prompt_source =
    "import filesystem\n\n\n" ++
    "func main(fs: Filesystem, stdin: Input, out: Stream, err: Stream) -> int:\n" ++ announce ++
    \\    print(out, "name?")
    \\    match stdin.read_line():
    \\        case Some(_):
    \\            print(out, "got a line")
    \\        case None:
    \\            print(out, "no line")
    \\    return 0
    \\
    ;

/// A program that prints `ready` and sleeps for 20 s on the real clock.
const sleeper_source =
    "import filesystem\nimport time\n\n\n" ++
    "func main(fs: Filesystem, clock: Clock, out: Stream, err: Stream) -> int:\n" ++ announce ++
    \\    print(out, "ready")
    \\    time.sleep(clock, 20000000000)
    \\    return 0
    \\
    ;

/// A program that prints `ready` and runs `sleep 20` as a started program, which the run waits for.
const runner_source =
    "import filesystem\nimport process\n\n\n" ++
    "func main(proc: Process, fs: Filesystem, out: Stream, err: Stream) -> int:\n" ++ announce ++
    \\    print(out, "ready")
    \\    match process.run(proc, process.command(["/bin/sleep", "20"])):
    \\        case Ok(_):
    \\            return 0
    \\        case Err(_):
    \\            return 2
    \\
    ;

/// Run `source` as `main.selka` with `selka run`, standard output a pipe, and require that its first line, `ready` or `first`,
/// reaches the pipe while the program is still waiting, then end it with SIGTERM to the compiler alone.
fn expectLineWhileWaiting(source: []const u8, first: []const u8) !void {
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "main.selka", .data = source });
    var compiler = try startPiped(temporary.dir, &([_][]const u8{ "run", "main.selka", "--timeout", "40" } ++ shared));
    defer compiler.deinit();
    const guest = try compiler.guestPid();
    var buffer: [256]u8 = undefined;
    try testing.expectEqualStrings(first, try compiler.stdoutLine(&buffer));
    try testing.expect(running(guest));
    try compiler.signal(.TERM);
    try testing.expectEqual(std.process.Child.Term{ .signal = .TERM }, try compiler.wait());
    try testing.expect(allGone(&.{guest}));
}

test "a line printed to standard output reaches the pipe while the program waits in the poller" {
    try expectLineWhileWaiting(poller_source, "ready\n");
}

test "a line printed to standard output reaches the pipe while the program sleeps on the real clock" {
    try expectLineWhileWaiting(sleeper_source, "ready\n");
}

test "a line printed to standard output reaches the pipe while the program waits for a program it started" {
    try expectLineWhileWaiting(runner_source, "ready\n");
}

test "a prompt printed to standard output reaches the pipe before the program reads standard input" {
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "main.selka", .data = prompt_source });
    var compiler = try startPiped(temporary.dir, &([_][]const u8{ "run", "main.selka", "--timeout", "40" } ++ shared));
    defer compiler.deinit();
    const guest = try compiler.guestPid();
    var buffer: [256]u8 = undefined;
    try testing.expectEqualStrings("name?\n", try compiler.stdoutLine(&buffer));
    try testing.expect(running(guest));
    try compiler.feed("Ada\n");
    try testing.expectEqualStrings("got a line\n", try compiler.stdoutLine(&buffer));
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, try compiler.wait());
}

/// A program that listens on `port`, prints `listening`, accepts one connection, prints `accepted` and reads from it.
fn acceptSource(port: u16) ![]u8 {
    return std.fmt.allocPrint(testing.allocator,
        \\import filesystem
        \\import network
        \\
        \\
        \\func main(net: Network, fs: Filesystem, out: Stream, err: Stream) -> int:
        \\    match filesystem.realpath(fs, "/proc/self"):
        \\        case Ok(path):
        \\            print(err, "guest " + path)
        \\        case Err(_):
        \\            return 1
        \\    with net.host("127.0.0.1:{d}") as scoped:
        \\        match network.listen(scoped):
        \\            case ok(owned):
        \\                mut listener = own owned
        \\                print(out, "listening")
        \\                match accept_resource[network.Accepted](listener):
        \\                    case Ok(connection):
        \\                        mut live = own connection
        \\                        print(out, "accepted")
        \\                        match read_resource[network.Read[16]](live):
        \\                            case Ok(chunk):
        \\                                print(out, "read " + str(int(chunk.length)))
        \\                                _ = network.close(own live)
        \\                                return 0
        \\                            case Err(_):
        \\                                return 4
        \\                    case Err(_):
        \\                        return 3
        \\            case err(_):
        \\                return 2
        \\
    , .{port});
}

/// A loopback port nothing listens on now, found by binding port 0 and letting go of it.
fn freePort() !u16 {
    var server = try (std.Io.net.IpAddress{ .ip4 = .loopback(0) }).listen(testing.io, .{});
    defer server.deinit(testing.io);
    return server.socket.address.getPort();
}

test "a line printed to standard output reaches the pipe while the program waits in accept and in a read" {
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    const port = try freePort();
    const source = try acceptSource(port);
    defer testing.allocator.free(source);
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "main.selka", .data = source });
    var compiler = try startPiped(temporary.dir, &([_][]const u8{ "run", "main.selka", "--timeout", "40" } ++ shared));
    defer compiler.deinit();
    const guest = try compiler.guestPid();
    var buffer: [256]u8 = undefined;
    try testing.expectEqualStrings("listening\n", try compiler.stdoutLine(&buffer));
    try testing.expect(running(guest));
    var peer = try (std.Io.net.IpAddress{ .ip4 = .loopback(port) }).connect(testing.io, .{ .mode = .stream });
    defer peer.close(testing.io);
    try testing.expectEqualStrings("accepted\n", try compiler.stdoutLine(&buffer));
    try testing.expect(running(guest));
    var writer = peer.writer(testing.io, &buffer);
    try writer.interface.writeAll("hi");
    try writer.interface.flush();
    try testing.expectEqualStrings("read 2\n", try compiler.stdoutLine(&buffer));
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, try compiler.wait());
}

// ---- Hearing a stop (FR5b, STOP-1) ---------------------------------------------------------------------------------------

/// Build `source` (written as `name.selka`) into the binary `name` in `directory`, with the private cache.
fn buildProgram(directory: std.Io.Dir, name: []const u8, source: []const u8) !void {
    var file_buffer: [64]u8 = undefined;
    const file = try std.fmt.bufPrint(&file_buffer, "{s}.selka", .{name});
    try directory.writeFile(testing.io, .{ .sub_path = file, .data = source });
    var builder = try start(directory, &([_][]const u8{ "build", file, "-o", name } ++ shared));
    defer builder.deinit();
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, try builder.wait());
}

/// Start the built program `name` of `directory` directly (no compiler), with standard output a pipe, in a group of its own.
fn startBuilt(directory: std.Io.Dir, name: []const u8) !Compiler {
    var environment = try paths_module.privateEnvironment(testing.allocator);
    errdefer environment.deinit();
    const root = try directory.realPathFileAlloc(testing.io, ".", testing.allocator);
    errdefer testing.allocator.free(root);
    const program = try std.fs.path.join(testing.allocator, &.{ root, name });
    defer testing.allocator.free(program);
    const child = try std.process.spawn(testing.io, .{ .argv = &.{program}, .cwd = .{ .dir = directory }, .environ_map = &environment, .stdin = .ignore, .stdout = .pipe, .stderr = .pipe, .pgid = 0 });
    return .{ .child = child, .environment = environment, .directory = root };
}

/// Where a test starts the server and how it ends: `built` runs the binary itself, otherwise `selka run` runs the source.
const Served = struct { built: bool, which: std.posix.SIG };

/// Start the server of `source` as `how` says, connect, read its greeting, send `how.which` to the process the test
/// started, and answer how it ended and everything the client read after the greeting.
fn serveAndSignal(source: []const u8, how: Served, after: *std.ArrayList(u8)) !std.process.Child.Term {
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    if (how.built) try buildProgram(temporary.dir, "server", source);
    if (!how.built) try temporary.dir.writeFile(testing.io, .{ .sub_path = "server.selka", .data = source });
    var process = if (how.built) try startBuilt(temporary.dir, "server") else try startIn(temporary.dir, &([_][]const u8{ "run", "server.selka", "--timeout", "90" } ++ shared), .{ .stdout = .pipe, .group = true });
    defer process.deinit();
    _ = try process.guestPid();
    var buffer: [256]u8 = undefined;
    const line = try process.stdoutLine(&buffer);
    const port = try std.fmt.parseInt(u16, std.mem.trimEnd(u8, line["port ".len..], "\n"), 10);
    var peer = try (std.Io.net.IpAddress{ .ip4 = .loopback(port) }).connect(testing.io, .{ .mode = .stream });
    defer peer.close(testing.io);
    var reading: [256]u8 = undefined;
    var reader = peer.reader(testing.io, &reading);
    try testing.expectEqualStrings("hello\n", try reader.interface.takeDelimiterInclusive('\n'));
    try process.signal(how.which);
    const rest = try reader.interface.allocRemaining(testing.allocator, .limited(4096));
    defer testing.allocator.free(rest);
    try after.appendSlice(testing.allocator, rest);
    return process.wait();
}

/// Require that the server of `source`, served and signalled as `how` says, ended as `ended` and its client then read `last`.
fn expectServed(source: []const u8, how: Served, ended: std.process.Child.Term, last: []const u8) !void {
    var after: std.ArrayList(u8) = .empty;
    defer after.deinit(testing.allocator);
    try testing.expectEqual(ended, try serveAndSignal(source, how, &after));
    try testing.expectEqualStrings(last, after.items);
}

test "a server that declares a Stop sends its last line and exits 0 on SIGTERM and SIGINT, built and under selka run" {
    try expectServed(stop_server_source, .{ .built = true, .which = .TERM }, .{ .exited = 0 }, "bye\n");
    try expectServed(stop_server_source, .{ .built = true, .which = .INT }, .{ .exited = 0 }, "bye\n");
    try expectServed(stop_server_source, .{ .built = false, .which = .TERM }, .{ .exited = 0 }, "bye\n");
    try expectServed(stop_server_source, .{ .built = false, .which = .INT }, .{ .exited = 0 }, "bye\n");
}

test "a built server without a Stop still dies of SIGTERM and SIGINT, and its client reads no last line" {
    try expectServed(stop_server_default_source, .{ .built = true, .which = .TERM }, .{ .signal = .TERM }, "");
    try expectServed(stop_server_default_source, .{ .built = true, .which = .INT }, .{ .signal = .INT }, "");
}

/// How the lingering program is signalled: to the process the test started, to its whole process group, twice to the
/// process a second apart, SIGTERM from the test and 0.1 s later from another process (`/bin/kill`), or SIGTERM then
/// SIGINT 0.1 s apart.
const Delivery = enum { process, group, twice, other_sender, term_then_int };

/// Start the lingering program (built, or under `selka run`), let it settle in its sleep, signal it as `delivery` says,
/// and answer how the process the test started ended; `said` gets what it wrote to standard error after its number.
fn lingerAndSignal(built: bool, delivery: Delivery, said: *std.ArrayList(u8)) !std.process.Child.Term {
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    if (built) try buildProgram(temporary.dir, "linger", stop_linger_source);
    if (!built) try temporary.dir.writeFile(testing.io, .{ .sub_path = "linger.selka", .data = stop_linger_source });
    var process = if (built) try startBuilt(temporary.dir, "linger") else try startIn(temporary.dir, &([_][]const u8{ "run", "linger.selka", "--timeout", "90" } ++ shared), .{ .group = true });
    defer process.deinit();
    _ = try process.guestPid();
    try testing.io.sleep(.fromMilliseconds(300), .awake);
    switch (delivery) {
        .process => try process.signal(.TERM),
        .group => try std.posix.kill(-process.child.id.?, .TERM),
        .twice => {
            try process.signal(.TERM);
            try testing.io.sleep(.fromMilliseconds(1000), .awake);
            try process.signal(.TERM);
        },
        .other_sender => {
            try process.signal(.TERM);
            try testing.io.sleep(.fromMilliseconds(100), .awake);
            try killFromAnotherProcess(process.child.id.?);
        },
        .term_then_int => {
            try process.signal(.TERM);
            try testing.io.sleep(.fromMilliseconds(100), .awake);
            try process.signal(.INT);
        },
    }
    const rest = try process.restOfStderr();
    defer testing.allocator.free(rest);
    try said.appendSlice(testing.allocator, rest);
    return process.wait();
}

/// Require that one `delivery` of SIGTERM was one stop: the goodbye ran and the process the test started exited 0.
fn expectOneStop(built: bool, delivery: Delivery) !void {
    var said: std.ArrayList(u8) = .empty;
    defer said.deinit(testing.allocator);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, try lingerAndSignal(built, delivery, &said));
    try testing.expectEqualStrings("heard after 1 sleeps\ngoodbye\n", said.items);
}

test "one SIGTERM is one stop: to a built program, to selka run alone, and to the whole group of either" {
    try expectOneStop(true, .process);
    try expectOneStop(true, .group);
    try expectOneStop(false, .process);
    try expectOneStop(false, .group);
}

/// Send SIGTERM to `pid` from a process of its own (`/bin/kill`), so the signal has a different sender from the test's.
fn killFromAnotherProcess(pid: std.posix.pid_t) !void {
    var number: [16]u8 = undefined;
    const text = try std.fmt.bufPrint(&number, "{d}", .{pid});
    var killer = try std.process.spawn(testing.io, .{ .argv = &.{ "/bin/kill", "-TERM", text }, .stdin = .ignore, .stdout = .ignore, .stderr = .ignore });
    _ = try killer.wait(testing.io);
}

/// Require that two signals delivered as `delivery` says ended the program by `which` during its goodbye.
fn expectSecondStopEnds(built: bool, delivery: Delivery, which: std.posix.SIG) !void {
    var said: std.ArrayList(u8) = .empty;
    defer said.deinit(testing.allocator);
    try testing.expectEqual(std.process.Child.Term{ .signal = which }, try lingerAndSignal(built, delivery, &said));
    try testing.expectEqualStrings("heard after 1 sleeps\n", said.items);
}

test "a second SIGTERM a second after the first ends the program during its goodbye, built and under selka run" {
    try expectSecondStopEnds(true, .twice, .TERM);
    try expectSecondStopEnds(false, .twice, .TERM);
}

test "the same signal from a different sender 0.1 s after the first ends the program, built and under selka run" {
    try expectSecondStopEnds(true, .other_sender, .TERM);
    try expectSecondStopEnds(false, .other_sender, .TERM);
}

test "SIGINT 0.1 s after SIGTERM ends the program during its goodbye" {
    try expectSecondStopEnds(true, .term_then_int, .INT);
}

/// Run the quick-goodbye program `rounds` times (built, or under `selka run`), each time sending SIGTERM to the process
/// the test started and at once to its whole group, in alternating order, as `timeout` without `--foreground` does; count
/// the rounds that exited 0 after saying goodbye.
fn processAndGroupRounds(built: bool, rounds: usize) !usize {
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    if (built) try buildProgram(temporary.dir, "quick", stop_quick_source);
    if (!built) try temporary.dir.writeFile(testing.io, .{ .sub_path = "quick.selka", .data = stop_quick_source });
    var clean: usize = 0;
    for (0..rounds) |round| {
        var process = if (built) try startBuilt(temporary.dir, "quick") else try startIn(temporary.dir, &([_][]const u8{ "run", "quick.selka", "--timeout", "60" } ++ shared), .{ .group = true });
        defer process.deinit();
        _ = try process.guestPid();
        try testing.io.sleep(.fromMilliseconds(50), .awake);
        const pid = process.child.id.?;
        if (round % 2 == 0) {
            try std.posix.kill(pid, .TERM);
            try std.posix.kill(-pid, .TERM);
        } else {
            try std.posix.kill(-pid, .TERM);
            try std.posix.kill(pid, .TERM);
        }
        const rest = try process.restOfStderr();
        defer testing.allocator.free(rest);
        const term = try process.wait();
        if (std.meta.eql(term, std.process.Child.Term{ .exited = 0 }) and std.mem.eql(u8, rest, "goodbye\n")) clean += 1;
    }
    return clean;
}

test "a sender that signals the process and then its group, as timeout does, gives one stop and the goodbye every time" {
    try testing.expectEqual(@as(usize, 30), try processAndGroupRounds(true, 30));
    try testing.expectEqual(@as(usize, 10), try processAndGroupRounds(false, 10));
}

/// Run the built lingering program on a terminal of its own (`script`), press Ctrl-C `presses` times a second apart, and
/// answer how `script` ended (it ends as its command did) and what the terminal showed.
fn lingerAtTerminal(presses: usize, shown: *std.ArrayList(u8)) !std.process.Child.Term {
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    try buildProgram(temporary.dir, "linger", stop_linger_source);
    var environment = try paths_module.privateEnvironment(testing.allocator);
    defer environment.deinit();
    const root = try temporary.dir.realPathFileAlloc(testing.io, ".", testing.allocator);
    defer testing.allocator.free(root);
    // `exec`, so the shell `script` starts becomes the program: a shell that waited for it would die of the Ctrl-C itself
    // (it is in the terminal's foreground group too) and take the terminal, and the program, with it.
    const program = try std.fmt.allocPrint(testing.allocator, "exec {s}/linger", .{root});
    defer testing.allocator.free(program);
    var terminal = std.process.spawn(testing.io, .{ .argv = &.{ "/usr/bin/script", "-qec", program, "/dev/null" }, .cwd = .{ .dir = temporary.dir }, .environ_map = &environment, .stdin = .pipe, .stdout = .pipe, .stderr = .ignore }) catch return error.SkipZigTest;
    defer if (terminal.id != null) terminal.kill(testing.io);
    var buffer: [4096]u8 = undefined;
    var reader = terminal.stdout.?.readerStreaming(testing.io, &buffer);
    while (true) {
        const line = try reader.interface.takeDelimiterInclusive('\n');
        if (std.mem.indexOf(u8, line, "guest /proc/") != null) break;
    }
    try testing.io.sleep(.fromMilliseconds(300), .awake);
    for (0..presses) |press| {
        if (press > 0) try testing.io.sleep(.fromMilliseconds(1000), .awake);
        try terminal.stdin.?.writeStreamingAll(testing.io, "\x03");
    }
    const rest = try reader.interface.allocRemaining(testing.allocator, .limited(1 << 16));
    defer testing.allocator.free(rest);
    try shown.appendSlice(testing.allocator, rest);
    return terminal.wait(testing.io);
}

test "Ctrl-C at a terminal is one stop and the goodbye runs; a second Ctrl-C during it ends the program" {
    var once: std.ArrayList(u8) = .empty;
    defer once.deinit(testing.allocator);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, try lingerAtTerminal(1, &once));
    try testing.expect(std.mem.indexOf(u8, once.items, "goodbye") != null);
    var twice: std.ArrayList(u8) = .empty;
    defer twice.deinit(testing.allocator);
    // `script` ends as its command did: 128 plus the signal for one killed by SIGINT.
    try testing.expectEqual(std.process.Child.Term{ .exited = 130 }, try lingerAtTerminal(2, &twice));
    try testing.expect(std.mem.indexOf(u8, twice.items, "goodbye") == null);
}

/// Run `source` (as `main.selka`) under `selka run` `rounds` times; each round sends SIGTERM to the `selka run` process and
/// to its group, in alternating order, with a gap swept from 0 to 3 ms between them, so the second signal reaches the
/// compiler before, while and after its program ends. Count the rounds that ended as `ended` with `said` on standard error.
fn gapRounds(source: []const u8, rounds: usize, ended: std.process.Child.Term, said: []const u8) !usize {
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "main.selka", .data = source });
    var matching: usize = 0;
    for (0..rounds) |round| {
        var process = try startIn(temporary.dir, &([_][]const u8{ "run", "main.selka", "--timeout", "60" } ++ shared), .{ .group = true });
        defer process.deinit();
        _ = try process.guestPid();
        try testing.io.sleep(.fromMilliseconds(50), .awake);
        const pid = process.child.id.?;
        const gap: std.Io.Duration = .fromMicroseconds(@intCast((round / 2) % 7 * 500));
        try std.posix.kill(if (round % 2 == 0) pid else -pid, .TERM);
        try testing.io.sleep(gap, .awake);
        try std.posix.kill(if (round % 2 == 0) -pid else pid, .TERM);
        const rest = try process.restOfStderr();
        defer testing.allocator.free(rest);
        const term = try process.wait();
        if (std.meta.eql(term, ended) and std.mem.eql(u8, rest, said)) {
            matching += 1;
        } else std.debug.print("gapRounds: round {d} (gap {d} us, {s} first) ended {any} and said \"{s}\"\n", .{ round, (round / 2) % 7 * 500, if (round % 2 == 0) "selka run" else "the group", term, rest });
    }
    return matching;
}

test "selka run exits with its program's status when a repeat of the stop arrives as the program ends, gaps 0 to 3 ms" {
    try testing.expectEqual(@as(usize, 28), try gapRounds(stop_instant_source, 28, .{ .exited = 0 }, "goodbye\n"));
    // A program that does not hear the stop dies of it, and `selka run` still ends by that signal, however late its own
    // hook runs (FR5c).
    try testing.expectEqual(@as(usize, 28), try gapRounds(waiter_source, 28, .{ .signal = .TERM }, ""));
}
