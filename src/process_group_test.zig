//! A group of started programs (`process.group`, `group_start`, `group_wait_any`, `group_signal`, `group_stop`,
//! `group_close`) on real children under `--restrict --allow-process`. Each guest runs in a fresh directory, which holds
//! the files its children write, and returns 42 when every check holds. Every child is bounded in time by itself
//! (`sleep 60` at most) and is ended by the guest. The scripted Process's side of the group (keys, order, what a close
//! answers) is `tests/lang/process_group.selka`.
const std = @import("std");
const t = std.testing;
const fixture = @import("stdlib_fixture.zig");
const files = @import("io_files_test.zig");

const granted: [2][]const u8 = .{ "--restrict", "--allow-process" };

/// The helpers every guest below shares: start a shell script into the group, ask for the next program that ended, close the
/// group, run a shell command and read what it printed, and the two checks a test makes of the system (is a process gone, how
/// many zombie children does this program have).
const prelude =
    \\import process
    \\import strings
    \\
    \\func begin(proc: Process, mut jobs: process.Group, script: str) -> int:
    \\    match process.group_start(proc, mut jobs, process.command(["/bin/sh", "-c", copy(script)]), None, None):
    \\        case Ok(key):
    \\            return key
    \\        case Err(_):
    \\            return -1
    \\
    \\
    \\func next(proc: Process, mut jobs: process.Group, millis: int) -> str:
    \\    match process.group_wait_any_within(proc, mut jobs, millis):
    \\        case Ok(found):
    \\            match found:
    \\                case Some(done):
    \\                    return f"{done.key}:{done.output.exited}:{done.output.code}"
    \\                case None:
    \\                    return "none"
    \\        case Err(error):
    \\            return process.message(error)
    \\
    \\
    \\func first(proc: Process, mut jobs: process.Group) -> str:
    \\    match process.group_wait_any(proc, mut jobs):
    \\        case Ok(done):
    \\            return f"{done.key}:{done.output.exited}:{done.output.code}"
    \\        case Err(error):
    \\            return process.message(error)
    \\
    \\
    \\func end(proc: Process, own jobs: process.Group) -> str:
    \\    match process.group_close(proc, own jobs, 500):
    \\        case Ok(rest):
    \\            mut line = ""
    \\            for item in rest:
    \\                line = line + f"{item.key}:{item.output.exited}:{item.output.code} "
    \\            return line
    \\        case Err(error):
    \\            return process.message(error)
    \\
    \\
    \\func said(proc: Process, script: str) -> str:
    \\    match process.run(proc, process.command(["/bin/sh", "-c", copy(script)])):
    \\        case Ok(result):
    \\            match strings.decode(result.stdout):
    \\                case Ok(text):
    \\                    return copy(strings.strip(text))
    \\                case Err(_):
    \\                    return "?"
    \\        case Err(_):
    \\            return "?"
    \\
    \\
    \\func number_in(proc: Process, name: str) -> int:
    \\    const text = said(proc, "i=0; while [ ! -s " + name + " ] && [ $i -lt 200 ]; do sleep 0.05; i=$((i+1)); done; cat " + name)
    \\    match parse_int(text):
    \\        case Some(found):
    \\            return found
    \\        case None:
    \\            return -1
    \\
    \\
    \\func gone(proc: Process, number: int) -> bool:
    \\    const script = "i=0; while [ $i -lt 60 ]; do s=$(awk '{print $3}' /proc/" + str(number) + "/stat 2>/dev/null); if [ -z \"$s\" ] || [ \"$s\" = Z ]; then echo gone; exit 0; fi; sleep 0.1; i=$((i+1)); done; echo alive"
    \\    return said(proc, script) == "gone"
    \\
    \\
    \\func zombies(proc: Process) -> str:
    \\    return said(proc, "cat /proc/[0-9]*/stat 2>/dev/null | sed 's/^[0-9]* (.*) //' | awk -v me=$PPID '$1==\"Z\" && $2==me {n++} END {print n+0}'")
    \\
    \\
;

/// Run `text` in a fresh directory with the Process grant and require 42.
fn expectPasses(text: []const u8) !void {
    var sandbox: files.Sandbox = undefined;
    try sandbox.init(true);
    defer sandbox.deinit();
    try fixture.expect(t.allocator, text, .{ .directory = sandbox.path, .arguments = &granted }, 42);
}

test "a group of no program, of one and of sixty-four, each answered once, leaves no zombie" {
    try expectPasses(prelude ++
        \\func main(proc: Process) -> int:
        \\    mut empty = process.group()
        \\    if process.group_size(mut empty) != 0:
        \\        _ = end(proc, own empty)
        \\        return 1
        \\    if first(proc, mut empty) != "the group has no program to wait for":
        \\        _ = end(proc, own empty)
        \\        return 2
        \\    if end(proc, own empty) != "":
        \\        return 3
        \\    mut one = process.group()
        \\    if begin(proc, mut one, "exit 5") != 0:
        \\        _ = end(proc, own one)
        \\        return 4
        \\    if first(proc, mut one) != "0:True:5" or process.group_size(mut one) != 0:
        \\        _ = end(proc, own one)
        \\        return 5
        \\    _ = end(proc, own one)
        \\    mut many = process.group()
        \\    for index in range(64):
        \\        if begin(proc, mut many, "exit " + str(index)) != index:
        \\            _ = end(proc, own many)
        \\            return 6
        \\    if process.group_size(mut many) != 64:
        \\        _ = end(proc, own many)
        \\        return 7
        \\    mut seen: bool[] = []
        \\    for _ in range(64):
        \\        append(mut seen, False)
        \\    for _ in range(64):
        \\        match process.group_wait_any(proc, mut many):
        \\            case Ok(done):
        \\                if done.key < 0 or done.key >= 64 or seen[done.key] or not done.output.exited or done.output.code != done.key:
        \\                    _ = end(proc, own many)
        \\                    return 8
        \\                seen[done.key] = True
        \\            case Err(_):
        \\                _ = end(proc, own many)
        \\                return 9
        \\    const left = process.group_size(mut many)
        \\    if end(proc, own many) != "" or left != 0:
        \\        return 10
        \\    if zombies(proc) != "0":
        \\        return 11
        \\    return 42
    );
}

test "the first of several programs to end answers first, whatever the order they started in" {
    try expectPasses(prelude ++
        \\func main(proc: Process) -> int:
        \\    mut jobs = process.group()
        \\    const slow = begin(proc, mut jobs, "sleep 2.5; exit 1")
        \\    const quick = begin(proc, mut jobs, "sleep 0.2; exit 2")
        \\    const middle = begin(proc, mut jobs, "sleep 1.2; exit 3")
        \\    if slow != 0 or quick != 1 or middle != 2:
        \\        _ = end(proc, own jobs)
        \\        return 1
        \\    if next(proc, mut jobs, 0) != "none":
        \\        _ = end(proc, own jobs)
        \\        return 2
        \\    if first(proc, mut jobs) != "1:True:2":
        \\        _ = end(proc, own jobs)
        \\        return 3
        \\    if process.group_size(mut jobs) != 2:
        \\        _ = end(proc, own jobs)
        \\        return 4
        \\    if first(proc, mut jobs) != "2:True:3":
        \\        _ = end(proc, own jobs)
        \\        return 5
        \\    if next(proc, mut jobs, 30000) != "0:True:1":
        \\        _ = end(proc, own jobs)
        \\        return 6
        \\    if end(proc, own jobs) != "" or zombies(proc) != "0":
        \\        return 7
        \\    return 42
    );
}

test "a time limit that expires answers None, and the program is still there to be signalled and waited for" {
    try expectPasses(prelude ++
        \\func main(proc: Process) -> int:
        \\    mut jobs = process.group()
        \\    const key = begin(proc, mut jobs, "sleep 60")
        \\    if key != 0 or next(proc, mut jobs, 150) != "none" or process.group_size(mut jobs) != 1:
        \\        _ = end(proc, own jobs)
        \\        return 1
        \\    match process.group_wait_any_within(proc, mut jobs, -1):
        \\        case Ok(_):
        \\            _ = end(proc, own jobs)
        \\            return 2
        \\        case Err(_):
        \\            pass
        \\    match process.group_signal(proc, mut jobs, key, process.SIGTERM):
        \\        case Ok(_):
        \\            pass
        \\        case Err(_):
        \\            _ = end(proc, own jobs)
        \\            return 3
        \\    if next(proc, mut jobs, 30000) != "0:False:15":
        \\        _ = end(proc, own jobs)
        \\        return 4
        \\    mut killed = process.group()
        \\    const other = begin(proc, mut killed, "sleep 60")
        \\    match process.group_signal(proc, mut killed, other, process.SIGKILL):
        \\        case Ok(_):
        \\            pass
        \\        case Err(_):
        \\            _ = end(proc, own killed)
        \\            _ = end(proc, own jobs)
        \\            return 5
        \\    const answer = first(proc, mut killed)
        \\    _ = end(proc, own killed)
        \\    const closed = end(proc, own jobs)
        \\    if answer != "0:False:9" or closed != "" or zombies(proc) != "0":
        \\        return 6
        \\    return 42
    );
}

test "a program that ends while nobody waits is not lost, and the ones that did are answered in the order they started" {
    try expectPasses(prelude ++
        \\func main(proc: Process) -> int:
        \\    mut jobs = process.group()
        \\    const a = begin(proc, mut jobs, "exit 7")
        \\    const b = begin(proc, mut jobs, "exit 8")
        \\    const c = begin(proc, mut jobs, "kill -9 $$")
        \\    if a != 0 or b != 1 or c != 2:
        \\        _ = end(proc, own jobs)
        \\        return 1
        \\    _ = said(proc, "sleep 0.5")
        \\    if zombies(proc) != "3":
        \\        _ = end(proc, own jobs)
        \\        return 2
        \\    if next(proc, mut jobs, 0) != "0:True:7" or next(proc, mut jobs, 0) != "1:True:8" or next(proc, mut jobs, 0) != "2:False:9":
        \\        _ = end(proc, own jobs)
        \\        return 3
        \\    if next(proc, mut jobs, 0) != "the group has no program to wait for":
        \\        _ = end(proc, own jobs)
        \\        return 4
        \\    if end(proc, own jobs) != "" or zombies(proc) != "0":
        \\        return 5
        \\    return 42
    );
}

test "a signal reaches the program and what it started, and nothing is left running" {
    try expectPasses(prelude ++
        \\func main(proc: Process) -> int:
        \\    mut jobs = process.group()
        \\    const key = begin(proc, mut jobs, "sleep 60 & echo $! > child.pid; wait")
        \\    const child = number_in(proc, "child.pid")
        \\    if key != 0 or child <= 1:
        \\        _ = end(proc, own jobs)
        \\        return 1
        \\    match process.group_pid(mut jobs, key):
        \\        case Some(leader):
        \\            if leader <= 1 or leader == child:
        \\                _ = end(proc, own jobs)
        \\                return 2
        \\        case None:
        \\            _ = end(proc, own jobs)
        \\            return 3
        \\    match process.group_signal(proc, mut jobs, key, process.SIGTERM):
        \\        case Ok(_):
        \\            pass
        \\        case Err(_):
        \\            _ = end(proc, own jobs)
        \\            return 4
        \\    if next(proc, mut jobs, 30000) != "0:False:15":
        \\        _ = end(proc, own jobs)
        \\        return 5
        \\    if not gone(proc, child):
        \\        _ = end(proc, own jobs)
        \\        return 6
        \\    match process.group_signal(proc, mut jobs, key, process.SIGKILL):
        \\        case Ok(_):
        \\            pass
        \\        case Err(_):
        \\            _ = end(proc, own jobs)
        \\            return 7
        \\    match process.group_signal(proc, mut jobs, 9, process.SIGTERM):
        \\        case Ok(_):
        \\            _ = end(proc, own jobs)
        \\            return 8
        \\        case Err(_):
        \\            pass
        \\    if end(proc, own jobs) != "" or zombies(proc) != "0":
        \\        return 9
        \\    return 42
    );
}

test "stop sends SIGTERM, waits the grace and sends SIGKILL, to every program and what it started, and keeps the group open" {
    try expectPasses(prelude ++
        \\func main(proc: Process) -> int:
        \\    mut jobs = process.group()
        \\    const polite = begin(proc, mut jobs, "sleep 60")
        \\    const deaf = begin(proc, mut jobs, "trap '' TERM; sleep 60 & echo $! > deaf.pid; wait")
        \\    const done = begin(proc, mut jobs, "exit 4")
        \\    if polite != 0 or deaf != 1 or done != 2:
        \\        _ = end(proc, own jobs)
        \\        return 1
        \\    const sleeper = number_in(proc, "deaf.pid")
        \\    _ = said(proc, "sleep 0.3")
        \\    mut line = ""
        \\    match process.group_stop(proc, mut jobs, 400):
        \\        case Ok(stopped):
        \\            for item in stopped:
        \\                line = line + f"{item.key}:{item.output.exited}:{item.output.code} "
        \\        case Err(_):
        \\            _ = end(proc, own jobs)
        \\            return 2
        \\    if line != "0:False:15 1:False:9 2:True:4 ":
        \\        _ = end(proc, own jobs)
        \\        return 3
        \\    if process.group_size(mut jobs) != 0 or sleeper <= 1 or not gone(proc, sleeper) or zombies(proc) != "0":
        \\        _ = end(proc, own jobs)
        \\        return 4
        \\    if begin(proc, mut jobs, "exit 0") != 3 or first(proc, mut jobs) != "3:True:0":
        \\        _ = end(proc, own jobs)
        \\        return 5
        \\    if end(proc, own jobs) != "":
        \\        return 6
        \\    return 42
    );
}

test "closing a group with programs running ends them and what they started, reaps every one and says how each ended" {
    try expectPasses(prelude ++
        \\func main(proc: Process) -> int:
        \\    mut jobs = process.group()
        \\    const a = begin(proc, mut jobs, "sleep 60 & echo $! > a.pid; wait")
        \\    const b = begin(proc, mut jobs, "sleep 60")
        \\    const c = begin(proc, mut jobs, "exit 0")
        \\    const d = begin(proc, mut jobs, "exit 6")
        \\    if a != 0 or b != 1 or c != 2 or d != 3:
        \\        _ = end(proc, own jobs)
        \\        return 1
        \\    const grandchild = number_in(proc, "a.pid")
        \\    _ = said(proc, "sleep 0.5")
        \\    if first(proc, mut jobs) != "2:True:0" or process.group_size(mut jobs) != 3:
        \\        _ = end(proc, own jobs)
        \\        return 2
        \\    const closed = end(proc, own jobs)
        \\    if closed != "0:False:15 1:False:15 3:True:6 ":
        \\        return 3
        \\    if grandchild <= 1 or not gone(proc, grandchild) or zombies(proc) != "0":
        \\        return 4
        \\    return 42
    );
}

test "a program's output goes where group_start was told, and the waits carry none" {
    try expectPasses(prelude ++
        \\func main(proc: Process) -> int:
        \\    mut jobs = process.group()
        \\    mut ok = True
        \\    match process.group_start(proc, mut jobs, process.command(["/bin/sh", "-c", "echo one; echo oops >&2"]), Some("a.out"), Some("a.err")):
        \\        case Ok(_):
        \\            pass
        \\        case Err(_):
        \\            ok = False
        \\    match process.group_start_to(proc, mut jobs, process.command(["/bin/sh", "-c", "echo two; echo hidden >&2"]), process.Destination.File(path="b.out"), process.Destination.Discard):
        \\        case Ok(_):
        \\            pass
        \\        case Err(_):
        \\            ok = False
        \\    for _ in range(2):
        \\        match process.group_wait_any(proc, mut jobs):
        \\            case Ok(done):
        \\                ok = ok and done.output.exited and done.output.code == 0 and done.output.stdout == b"" and done.output.stderr == b""
        \\            case Err(_):
        \\                ok = False
        \\    const text = said(proc, "cat a.out b.out a.err; ls b.err 2>/dev/null")
        \\    const closed = end(proc, own jobs)
        \\    if not ok or closed != "" or text != "one\ntwo\noops":
        \\        return 1
        \\    return 42
    );
}

test "a program that is not there fails NotFound and leaves the group as it was" {
    try expectPasses(prelude ++
        \\func main(proc: Process) -> int:
        \\    mut jobs = process.group()
        \\    if begin(proc, mut jobs, "exit 1") != 0:
        \\        _ = end(proc, own jobs)
        \\        return 1
        \\    mut missing = False
        \\    match process.group_start(proc, mut jobs, process.command(["/no/such/program-xyz"]), None, None):
        \\        case Ok(_):
        \\            _ = end(proc, own jobs)
        \\            return 2
        \\        case Err(error):
        \\            match error:
        \\                case NotFound(program=_):
        \\                    missing = True
        \\                case Failed(message=_):
        \\                    missing = False
        \\    if not missing or process.group_size(mut jobs) != 1 or begin(proc, mut jobs, "exit 2") != 1:
        \\        _ = end(proc, own jobs)
        \\        return 3
        \\    if first(proc, mut jobs) != "0:True:1" or first(proc, mut jobs) != "1:True:2":
        \\        _ = end(proc, own jobs)
        \\        return 4
        \\    if end(proc, own jobs) != "" or zombies(proc) != "0":
        \\        return 5
        \\    return 42
    );
}

test "under --restrict without --allow-process a program that asks for a Process does not start, group or not" {
    var sandbox: files.Sandbox = undefined;
    try sandbox.init(true);
    defer sandbox.deinit();
    const refused: [1][]const u8 = .{"--restrict"};
    const outcome = fixture.runOutcome(t.allocator, prelude ++
        \\func main(proc: Process) -> int:
        \\    mut jobs = process.group()
        \\    const key = begin(proc, mut jobs, "exit 0")
        \\    _ = end(proc, own jobs)
        \\    return 42 + key
    , .{ .directory = sandbox.path, .arguments = &refused });
    const run = try outcome;
    try t.expectEqual(@as(u8, 2), run.status);
    try t.expect(std.mem.indexOf(u8, run.stderr, "pass --allow-process") != null);
}
