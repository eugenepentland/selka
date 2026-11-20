//! The `Process` capability from the host side: real children under `--restrict --allow-process`. The shell is
//! `/bin/sh`; a request without one is the program path itself. Exits and values are checked by the guest, which
//! returns 42 when every check holds.
const std = @import("std");
const t = std.testing;
const fixture = @import("stdlib_fixture.zig");

const granted: []const []const u8 = &.{ "--restrict", "--allow-process" };

fn expectPasses(text: []const u8) !void {
    try fixture.expect(t.allocator, text, .{ .arguments = granted }, 42);
}

test "process.run captures output and the exit status, and reports a signal as not exited" {
    try expectPasses(
        \\import process
        \\func main(proc: Process) -> int:
        \\    match process.run(proc, process.command(["/bin/sh", "-c", "printf out; printf err >&2; exit 3"])):
        \\        case Ok(result):
        \\            if not result.exited or result.code != 3 or result.stdout != b"out" or result.stderr != b"err" or result.truncated:
        \\                return 1
        \\        case Err(_):
        \\            return 2
        \\    match process.run(proc, process.command(["/bin/sh", "-c", "kill -9 $$"])):
        \\        case Ok(result):
        \\            if result.exited or result.code != 9:
        \\                return 3
        \\        case Err(_):
        \\            return 4
        \\    return 42
    );
}

test "a missing program is NotFound, a program the system will not run is Failed, and an empty argv is refused" {
    try expectPasses(
        \\import process
        \\func main(proc: Process) -> int:
        \\    match process.run(proc, process.command(["no-such-program-xyz"])):
        \\        case Ok(_):
        \\            return 1
        \\        case Err(error):
        \\            match error:
        \\                case NotFound(program=name):
        \\                    if name != "no-such-program-xyz":
        \\                        return 2
        \\                case Failed(message=_):
        \\                    return 3
        \\    match process.run(proc, process.command(["/etc/passwd"])):
        \\        case Ok(_):
        \\            return 4
        \\        case Err(error):
        \\            match error:
        \\                case NotFound(program=_):
        \\                    return 5
        \\                case Failed(message=text):
        \\                    if text != "cannot run '/etc/passwd': permission denied":
        \\                        return 6
        \\    match process.run(proc, process.command([])):
        \\        case Ok(_):
        \\            return 7
        \\        case Err(error):
        \\            match error:
        \\                case NotFound(program=_):
        \\                    return 8
        \\                case Failed(message=text):
        \\                    if text != "a process request needs a program to run":
        \\                        return 9
        \\    return 42
    );
}

test "standard input, an explicit environment and a working directory reach the child" {
    try expectPasses(
        \\import process
        \\func main(proc: Process) -> int:
        \\    mut cat = process.command(["/bin/cat"])
        \\    cat.input = b"piped\n"
        \\    match process.run(proc, cat):
        \\        case Ok(result):
        \\            if result.stdout != b"piped\n":
        \\                return 1
        \\        case Err(_):
        \\            return 2
        \\    mut env = process.command(["/usr/bin/env"])
        \\    env.environment = Some(["ONLY=this"])
        \\    match process.run(proc, env):
        \\        case Ok(result):
        \\            if result.stdout != b"ONLY=this\n":
        \\                return 3
        \\        case Err(_):
        \\            return 4
        \\    mut where = process.command(["/bin/pwd"])
        \\    where.directory = "/usr"
        \\    match process.run(proc, where):
        \\        case Ok(result):
        \\            if result.stdout != b"/usr\n":
        \\                return 5
        \\        case Err(_):
        \\            return 6
        \\    return 42
    );
}

test "the child sees only its three standard descriptors, even when the caller holds a socket" {
    try expectPasses(
        \\import process
        \\func main(proc: Process) -> int:
        \\    match process.run(proc, process.command(["/bin/sh", "-c", "ls /proc/self/fd"])):
        \\        case Ok(result):
        \\            if result.stdout != b"0\n1\n2\n3\n":
        \\                return 1
        \\        case Err(_):
        \\            return 2
        \\    return 42
    );
}

test "output past the limit is dropped without blocking the child, and a child that never reads its input is harmless" {
    try expectPasses(
        \\import process
        \\func main(proc: Process) -> int:
        \\    mut big = process.command(["/bin/sh", "-c", "yes | head -c 3000000; echo done >&2"])
        \\    big.limit = 1000
        \\    match process.run(proc, big):
        \\        case Ok(result):
        \\            if len(result.stdout) != 1000 or result.stderr != b"done\n" or not result.truncated or not result.exited or result.code != 0:
        \\                return 1
        \\        case Err(_):
        \\            return 2
        \\    mut deaf = process.command(["/bin/sh", "-c", "exit 0"])
        \\    mut chunk: int[] = []
        \\    for index in range(300000):
        \\        append(mut chunk, 65)
        \\    deaf.input = bytes(chunk)
        \\    match process.run(proc, deaf):
        \\        case Ok(result):
        \\            if not result.exited or result.code != 0 or result.truncated:
        \\                return 3
        \\        case Err(_):
        \\            return 4
        \\    return 42
    );
}

test "executable_path answers the absolute path of the running program" {
    try expectPasses(
        \\import process
        \\func main(proc: Process) -> int:
        \\    match process.executable_path(proc):
        \\        case Ok(path):
        \\            if len(path) < 2 or path[0:1] != "/" or path == process.SCRIPTED_EXECUTABLE_PATH:
        \\                return 1
        \\        case Err(_):
        \\            return 2
        \\    return 42
    );
}

test "expect and calls need a scripted Process: on a real one they trap, and run starts the real program" {
    try fixture.trap(t.allocator,
        \\import process
        \\func main(proc: Process) -> int:
        \\    return len(process.calls(proc))
    , .{ .arguments = granted }, "R_ASSERT");
    try fixture.trap(t.allocator,
        \\import process
        \\func main(proc: Process) -> int:
        \\    process.expect(proc, process.Rule(program="x", reply=process.Reply.Missing))
        \\    return 0
    , .{ .arguments = granted }, "R_ASSERT");
    try expectPasses(
        \\import process
        \\func main(proc: Process) -> int:
        \\    match process.run(proc, process.command(["/bin/sh", "-c", "printf real"])):
        \\        case Ok(result):
        \\            if result.stdout != b"real":
        \\                return 1
        \\        case Err(_):
        \\            return 2
        \\    return 42
    );
}
