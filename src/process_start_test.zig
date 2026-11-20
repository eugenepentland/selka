//! Started programs (FR6): `process.start`, `signal`, `wait_within`, `wait` and `stop` on real children under
//! `--restrict --allow-process`, and the address space every child gets back (F-32). Each guest runs in a fresh
//! directory, which holds the files its children write, and returns 42 when every check holds. Every child is bounded in
//! time by itself (`sleep 30` at most) and is ended by the guest, or by the system when the guest ends first (a started
//! program is killed with its parent, which the trap test checks by process number).
const std = @import("std");
const t = std.testing;
const fixture = @import("stdlib_fixture.zig");
const files = @import("io_files_test.zig");

const granted: [2][]const u8 = .{ "--restrict", "--allow-process" };

/// Run `text` in a fresh directory with the Process grant and require 42.
fn expectPasses(text: []const u8, memory: ?u64) !void {
    var sandbox: files.Sandbox = undefined;
    try sandbox.init(true);
    defer sandbox.deinit();
    try fixture.expect(t.allocator, text, .{ .directory = sandbox.path, .arguments = &granted, .max_memory = memory }, 42);
}

test "process.start returns while the program runs, and signal and wait_within end it and report the signal" {
    try expectPasses(
        \\import process
        \\func main(proc: Process) -> int:
        \\    mut child = process.start(proc, process.command(["/bin/sleep", "30"]), None, None) else Err(_):
        \\        return 1
        \\    const number = process.pid(mut child)
        \\    if number <= 0 or number != child.pid:
        \\        _ = process.stop(proc, own child, 0)
        \\        return 2
        \\    match process.wait_within(proc, mut child, 0):
        \\        case Ok(found):
        \\            if found is not None:
        \\                _ = process.stop(proc, own child, 0)
        \\                return 3
        \\        case Err(_):
        \\            _ = process.stop(proc, own child, 0)
        \\            return 4
        \\    match process.wait_within(proc, mut child, 200):
        \\        case Ok(found):
        \\            if found is not None:
        \\                _ = process.stop(proc, own child, 0)
        \\                return 5
        \\        case Err(_):
        \\            _ = process.stop(proc, own child, 0)
        \\            return 6
        \\    match process.signal(proc, mut child, process.SIGTERM):
        \\        case Ok(_):
        \\            pass
        \\        case Err(_):
        \\            _ = process.stop(proc, own child, 0)
        \\            return 7
        \\    match process.wait_within(proc, mut child, 30000):
        \\        case Ok(found):
        \\            match found:
        \\                case Some(output):
        \\                    if output.exited or output.code != 15:
        \\                        _ = process.stop(proc, own child, 0)
        \\                        return 8
        \\                case None:
        \\                    _ = process.stop(proc, own child, 0)
        \\                    return 9
        \\        case Err(_):
        \\            _ = process.stop(proc, own child, 0)
        \\            return 10
        \\    # Once a wait has seen the end, a signal sends nothing and a wait answers the same at once.
        \\    match process.signal(proc, mut child, process.SIGKILL):
        \\        case Ok(_):
        \\            pass
        \\        case Err(_):
        \\            _ = process.stop(proc, own child, 0)
        \\            return 11
        \\    match process.wait(proc, own child):
        \\        case Ok(output):
        \\            if output.exited or output.code != 15 or output.stdout != b"" or output.truncated:
        \\                return 12
        \\        case Err(_):
        \\            return 13
        \\    # The program is gone: no process has its number any more.
        \\    match process.run(proc, process.command(["/bin/sh", "-c", "kill -0 " + str(number) + " 2>/dev/null"])):
        \\        case Ok(result):
        \\            if result.exited and result.code == 0:
        \\                return 14
        \\        case Err(_):
        \\            return 15
        \\    return 42
    , null);
}

test "a started program's exit status, and its output in two files, in one file, or in /dev/null" {
    try expectPasses(
        \\import process
        \\func contents(proc: Process, path: str) -> bytes:
        \\    match process.run(proc, process.command(["/bin/cat", copy(path)])):
        \\        case Ok(result):
        \\            return copy(result.stdout)
        \\        case Err(_):
        \\            return b"unreadable"
        \\func main(proc: Process) -> int:
        \\    const script = process.command(["/bin/sh", "-c", "echo out; echo err >&2; echo out2; exit 3"])
        \\    mut apart = process.start(proc, copy(script), Some("out.log"), Some("err.log")) else Err(_):
        \\        return 1
        \\    match process.wait(proc, own apart):
        \\        case Ok(output):
        \\            if not output.exited or output.code != 3:
        \\                return 2
        \\        case Err(_):
        \\            return 3
        \\    if contents(proc, "out.log") != b"out\nout2\n" or contents(proc, "err.log") != b"err\n":
        \\        return 4
        \\    mut together = process.start(proc, copy(script), Some("both.log"), Some("both.log")) else Err(_):
        \\        return 5
        \\    match process.wait(proc, own together):
        \\        case Ok(output):
        \\            if not output.exited or output.code != 3:
        \\                return 6
        \\        case Err(_):
        \\            return 7
        \\    if contents(proc, "both.log") != b"out\nerr\nout2\n":
        \\        return 8
        \\    # A file is emptied when the program starts.
        \\    mut again = process.start(proc, process.command(["/bin/sh", "-c", "echo fresh"]), Some("out.log"), None) else Err(_):
        \\        return 9
        \\    match process.wait(proc, own again):
        \\        case Ok(_):
        \\            pass
        \\        case Err(_):
        \\            return 10
        \\    if contents(proc, "out.log") != b"fresh\n":
        \\        return 11
        \\    # No path: /dev/null, so nothing reaches this program's own output.
        \\    mut quiet = process.start(proc, process.command(["/bin/sh", "-c", "echo leaked; echo leaked >&2"]), None, None) else Err(_):
        \\        return 12
        \\    match process.wait(proc, own quiet):
        \\        case Ok(output):
        \\            if not output.exited or output.code != 0:
        \\                return 13
        \\        case Err(_):
        \\            return 14
        \\    # The request's directory and environment reach the started program as they reach run's.
        \\    mut placed = process.command(["/bin/sh", "-c", "pwd; echo $ONLY"])
        \\    placed.directory = "/usr"
        \\    placed.environment = Some(["ONLY=this"])
        \\    mut where = process.start(proc, placed, Some("where.log"), None) else Err(_):
        \\        return 15
        \\    match process.wait(proc, own where):
        \\        case Ok(_):
        \\            pass
        \\        case Err(_):
        \\            return 16
        \\    if contents(proc, "where.log") != b"/usr\nthis\n":
        \\        return 17
        \\    return 42
    , null);
}

test "the guest's output stays its own when a started program has no output path" {
    var sandbox: files.Sandbox = undefined;
    try sandbox.init(true);
    defer sandbox.deinit();
    const outcome = try fixture.runOutcome(t.allocator,
        \\import process
        \\func main(proc: Process) -> int:
        \\    mut quiet = process.start(proc, process.command(["/bin/sh", "-c", "echo leaked; echo leaked >&2"]), None, None) else Err(_):
        \\        return 1
        \\    _ = process.wait(proc, own quiet)
        \\    return 42
    , .{ .directory = sandbox.path, .arguments = &granted });
    try t.expectEqual(@as(i64, 42), outcome.value);
    try t.expect(std.mem.indexOf(u8, outcome.stdout, "leaked") == null);
    try t.expect(std.mem.indexOf(u8, outcome.stderr, "leaked") == null);
}

test "start_to lets a started program write to the guest's own standard output and standard error, after what the guest printed" {
    var sandbox: files.Sandbox = undefined;
    try sandbox.init(true);
    defer sandbox.deinit();
    const outcome = try fixture.runOutcome(t.allocator,
        \\import process
        \\func main(proc: Process, out: Stream, err: Stream) -> int:
        \\    print(out, "before")
        \\    print(err, "before on error")
        \\    mut child = process.start_to(proc, process.command(["/bin/sh", "-c", "echo child-out; echo child-err >&2; sleep 0.2; echo child-more"]), process.Destination.Caller, process.Destination.Caller) else Err(_):
        \\        return 1
        \\    match process.wait(proc, own child):
        \\        case Ok(output):
        \\            if not output.exited or output.code != 0 or len(output.stdout) != 0 or len(output.stderr) != 0:
        \\                return 2
        \\        case Err(_):
        \\            return 3
        \\    print(out, "after")
        \\    return 42
    , .{ .directory = sandbox.path, .arguments = &granted });
    try t.expectEqual(@as(i64, 42), outcome.value);
    try t.expectEqualStrings("before\nchild-out\nchild-more\nafter\n", outcome.stdout);
    try t.expectEqualStrings("before on error\nchild-err\n", outcome.stderr);
}

test "start_to mixes the guest's own streams, a file and /dev/null, and the old start still keeps the guest's output its own" {
    var sandbox: files.Sandbox = undefined;
    try sandbox.init(true);
    defer sandbox.deinit();
    const outcome = try fixture.runOutcome(t.allocator,
        \\import process
        \\func contents(proc: Process, path: str) -> bytes:
        \\    match process.run(proc, process.command(["/bin/cat", copy(path)])):
        \\        case Ok(result):
        \\            return copy(result.stdout)
        \\        case Err(_):
        \\            return b"unreadable"
        \\func main(proc: Process) -> int:
        \\    const script = process.command(["/bin/sh", "-c", "echo out; echo err >&2"])
        \\    mut filed = process.start_to(proc, copy(script), process.Destination.File(path="out.log"), process.Destination.Caller) else Err(_):
        \\        return 1
        \\    _ = process.wait(proc, own filed)
        \\    mut shown = process.start_to(proc, copy(script), process.Destination.Caller, process.Destination.Discard) else Err(_):
        \\        return 2
        \\    _ = process.wait(proc, own shown)
        \\    mut quiet = process.start_to(proc, copy(script), process.Destination.Discard, process.Destination.Discard) else Err(_):
        \\        return 3
        \\    _ = process.wait(proc, own quiet)
        \\    mut plain = process.start(proc, copy(script), None, None) else Err(_):
        \\        return 4
        \\    _ = process.wait(proc, own plain)
        \\    if contents(proc, "out.log") != b"out\n":
        \\        return 5
        \\    return 42
    , .{ .directory = sandbox.path, .arguments = &granted });
    try t.expectEqual(@as(i64, 42), outcome.value);
    // Only the second start let its standard output through; the first sent standard error through, the third and fourth nothing.
    try t.expectEqualStrings("out\n", outcome.stdout);
    try t.expectEqualStrings("err\n", outcome.stderr);
}

test "a started program that writes to the guest's streams ends with the guest's end, and a child of start_to is stopped like any other" {
    var sandbox: files.Sandbox = undefined;
    try sandbox.init(true);
    defer sandbox.deinit();
    const outcome = try fixture.runOutcome(t.allocator,
        \\import process
        \\func main(proc: Process, out: Stream) -> int:
        \\    print(out, "serving")
        \\    mut server = process.start_to(proc, process.command(["/bin/sh", "-c", "echo up; exec sleep 30"]), process.Destination.Caller, process.Destination.Caller) else Err(_):
        \\        return 1
        \\    match process.wait_within(proc, mut server, 300):
        \\        case Ok(found):
        \\            if found is not None:
        \\                _ = process.stop(proc, own server, 0)
        \\                return 2
        \\        case Err(_):
        \\            _ = process.stop(proc, own server, 0)
        \\            return 3
        \\    match process.stop(proc, own server, 5000):
        \\        case Ok(found):
        \\            if found.exited or found.code != 15:
        \\                return 4
        \\        case Err(_):
        \\            return 5
        \\    print(out, "stopped")
        \\    return 42
    , .{ .directory = sandbox.path, .arguments = &granted });
    try t.expectEqual(@as(i64, 42), outcome.value);
    try t.expectEqualStrings("serving\nup\nstopped\n", outcome.stdout);
}

test "stop ends a program that exits on SIGTERM, and kills one that ignores it" {
    try expectPasses(
        \\import process
        \\func up(proc: Process, path: str) -> bool:
        \\    match process.run(proc, process.command(["/usr/bin/timeout", "30", "/bin/sh", "-c", "until [ -s " + path + " ]; do sleep 0.02; done"])):
        \\        case Ok(result):
        \\            return result.exited and result.code == 0
        \\        case Err(_):
        \\            return False
        \\func main(proc: Process) -> int:
        \\    const polite = process.command(["/bin/sh", "-c", "trap 'exit 7' TERM; echo up; while :; do sleep 0.05; done"])
        \\    mut server = process.start(proc, polite, Some("polite.log"), None) else Err(_):
        \\        return 1
        \\    if not up(proc, "polite.log"):
        \\        _ = process.stop(proc, own server, 0)
        \\        return 2
        \\    match process.stop(proc, own server, 30000):
        \\        case Ok(output):
        \\            if not output.exited or output.code != 7:
        \\                return 3
        \\        case Err(_):
        \\            return 4
        \\    const deaf = process.command(["/bin/sh", "-c", "trap '' TERM; echo up; exec /bin/sleep 30"])
        \\    mut stubborn = process.start(proc, deaf, Some("deaf.log"), None) else Err(_):
        \\        return 5
        \\    if not up(proc, "deaf.log"):
        \\        _ = process.stop(proc, own stubborn, 0)
        \\        return 6
        \\    match process.wait_within(proc, mut stubborn, 0):
        \\        case Ok(found):
        \\            if found is not None:
        \\                _ = process.stop(proc, own stubborn, 0)
        \\                return 7
        \\        case Err(_):
        \\            _ = process.stop(proc, own stubborn, 0)
        \\            return 8
        \\    match process.stop(proc, own stubborn, 300):
        \\        case Ok(output):
        \\            if output.exited or output.code != 9:
        \\                return 9
        \\        case Err(_):
        \\            return 10
        \\    return 42
    , null);
}

test "start, signal and wait_within refuse what they cannot do, with the reason" {
    try expectPasses(
        \\import process
        \\func failure(proc: Process, request: process.Request, out: str?) -> str:
        \\    match process.start(proc, request, out, None):
        \\        case Ok(child):
        \\            _ = process.stop(proc, own child, 0)
        \\            return "started"
        \\        case Err(error):
        \\            return process.message(error)
        \\func main(proc: Process) -> int:
        \\    if failure(proc, process.command(["no-such-program-xyz"]), None) != "no program 'no-such-program-xyz' was found":
        \\        return 1
        \\    if failure(proc, process.command(["/etc/passwd"]), None) != "cannot run '/etc/passwd': permission denied":
        \\        return 2
        \\    if failure(proc, process.command([]), None) != "a process request needs a program to run":
        \\        return 3
        \\    mut fed = process.command(["/bin/cat"])
        \\    fed.input = b"x"
        \\    if failure(proc, fed, None) != "process.start gives the program no standard input: leave request.input empty":
        \\        return 4
        \\    if failure(proc, process.command(["/bin/true"]), Some("missing/out.log")) != "cannot open 'missing/out.log' for the program's output (errno 2)":
        \\        return 5
        \\    mut child = process.start(proc, process.command(["/bin/sleep", "30"]), None, None) else Err(_):
        \\        return 6
        \\    match process.signal(proc, mut child, 0):
        \\        case Ok(_):
        \\            _ = process.stop(proc, own child, 0)
        \\            return 7
        \\        case Err(error):
        \\            if process.message(error) != "a signal number is 1 to 64, not 0":
        \\                _ = process.stop(proc, own child, 0)
        \\                return 8
        \\    match process.signal(proc, mut child, 65):
        \\        case Ok(_):
        \\            _ = process.stop(proc, own child, 0)
        \\            return 9
        \\        case Err(_):
        \\            pass
        \\    match process.wait_within(proc, mut child, -1):
        \\        case Ok(_):
        \\            _ = process.stop(proc, own child, 0)
        \\            return 10
        \\        case Err(error):
        \\            if process.message(error) != "process.wait_within needs a limit of zero or more milliseconds; process.wait has none":
        \\                _ = process.stop(proc, own child, 0)
        \\                return 11
        \\    match process.stop(proc, own child, 0):
        \\        case Ok(output):
        \\            if output.exited:
        \\                return 12
        \\        case Err(_):
        \\            return 13
        \\    return 42
    , null);
}

/// Wait up to 20 seconds for process `number` to be gone or dead and unreaped (state `Z`: under the gate's subreaper an
/// orphan that was killed waits there to be reaped), and answer whether it went.
fn gone(number: []const u8) !bool {
    const script = "for i in $(seq 1 200); do s=$(awk '{print $3}' /proc/$0/stat 2>/dev/null) || exit 0; " ++
        "[ -z \"$s\" ] || [ \"$s\" = Z ] && exit 0; sleep 0.1; done; exit 1";
    const result = try std.process.run(t.allocator, t.io, .{ .argv = &.{ "sh", "-c", script, number } });
    defer t.allocator.free(result.stdout);
    defer t.allocator.free(result.stderr);
    return result.term == .exited and result.term.exited == 0;
}

test "a started program is killed when the program that started it traps, and is gone or a zombie within 20 seconds" {
    var sandbox: files.Sandbox = undefined;
    try sandbox.init(true);
    defer sandbox.deinit();
    try fixture.trap(t.allocator,
        \\import process
        \\func main(proc: Process) -> int:
        \\    mut child = process.start(proc, process.command(["/bin/sleep", "30"]), None, None) else Err(_):
        \\        return 1
        \\    _ = process.run(proc, process.command(["/bin/sh", "-c", "echo " + str(child.pid) + " > pid.txt"]))
        \\    assert False, "the program ends here with its child still running"
        \\    _ = process.stop(proc, own child, 0)
        \\    return 42
    , .{ .directory = sandbox.path, .arguments = &granted }, "R_ASSERT");
    const written = try sandbox.temporary.dir.readFileAlloc(t.io, "pid.txt", t.allocator, .limited(64));
    defer t.allocator.free(written);
    const number = std.mem.trim(u8, written, " \n");
    try t.expect(number.len > 0);
    try t.expect(try gone(number));
}

/// The soft address-space limits of a child, of the guest that started it and of the `selka run` that started the
/// guest, compared by the child: `same` when the child's equals the runner's, then `guest-lower` when the guest's own is
/// below the runner's (the ceiling still bounds the guest).
const limits_script =
    \\lim() { awk '/^Max address space/ {print $4}' /proc/$1/limits; }
    \\runner=$(awk '/^PPid:/ {print $2}' /proc/$PPID/status)
    \\if [ "$(lim $$)" = "$(lim $runner)" ]; then echo same; else echo "child $(lim $$) runner $(lim $runner)"; fi
    \\if [ "$(lim $PPID)" != "$(lim $runner)" ]; then echo guest-lower; fi
;

fn limitsGuest(comptime wanted: []const u8) []const u8 {
    return
    \\import process
    \\const SCRIPT: str = "
    ++ comptime escaped(limits_script) ++
        \\"
        \\func main(proc: Process) -> int:
        \\    match process.run(proc, process.command(["/bin/sh", "-c", SCRIPT])):
        \\        case Ok(result):
        \\            if result.stdout != b"
    ++ wanted ++
        \\":
        \\                return 1
        \\        case Err(_):
        \\            return 2
        \\    mut child = process.start(proc, process.command(["/bin/sh", "-c", SCRIPT]), Some("limits.log"), None) else Err(_):
        \\        return 3
        \\    _ = process.wait(proc, own child)
        \\    match process.run(proc, process.command(["/bin/cat", "limits.log"])):
        \\        case Ok(result):
        \\            if result.stdout != b"
    ++ wanted ++
        \\":
        \\                return 4
        \\        case Err(_):
        \\            return 5
        \\    return 42
    ;
}

/// `text` as the body of a Selka string literal: quotes, backslashes and newlines escaped.
fn escaped(comptime text: []const u8) []const u8 {
    @setEvalBranchQuota(100000);
    comptime var out: []const u8 = "";
    inline for (text) |byte| {
        out = out ++ switch (byte) {
            '"' => "\\\"",
            '\\' => "\\\\",
            '\n' => "\\n",
            else => &[_]u8{byte},
        };
    }
    return out;
}

test "a program run or started under selka run gets the address space the guest started with, not its ceiling" {
    try expectPasses(limitsGuest("same\\nguest-lower\\n"), 64 << 20);
    try expectPasses(limitsGuest("same\\nguest-lower\\n"), null);
    try expectPasses(limitsGuest("same\\n"), 0);
}
