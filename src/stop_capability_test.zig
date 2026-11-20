//! The `Stop` capability's checking (FR5b): `main` may declare one, it is a handle that records, lists, options and
//! returns hold, the `process` operations take it and nothing else, `main` declares at most one, and an ordinary program
//! cannot build a stand-in except through `process.simulated_stop`.
const std = @import("std");
const t = std.testing;
const fixture = @import("stdlib_fixture.zig");

/// Check `source` as a project (so it may import `process`) and require that it checks clean, or that its first
/// diagnostic carries `code` and a message containing `needle`.
fn expectFirst(source: []const u8, code: []const u8, needle: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const checked = try fixture.check(arena.allocator(), source);
    if (code.len == 0) return checked.expectAccepted();
    try t.expect(!checked.passed);
    const first = checked.firstError().?;
    try t.expectEqualStrings(code, first.code);
    try t.expect(std.mem.indexOf(u8, first.message, needle) != null);
}

test "main declares a Stop and the process operations read and request it" {
    try expectFirst(
        \\import process
        \\
        \\func main(out: Stream, stop: Stop) -> int:
        \\    const spare = process.simulated_stop()
        \\    process.request_stop(spare)
        \\    print(out, process.stop_requested(stop), process.stop_requested(spare))
        \\    return 0
    , "", "");
}

test "a Stop is a handle that a record, a list and an option hold and a function returns" {
    try expectFirst(
        \\import process
        \\
        \\record Services:
        \\    stop: Stop
        \\    name: str
        \\
        \\func keep(stop: Stop) -> Stop:
        \\    return stop
        \\
        \\func main(out: Stream, stop: Stop) -> int:
        \\    const services = Services(stop=keep(stop), name="site")
        \\    const all = [stop, services.stop]
        \\    const maybe: Stop? = Some(stop)
        \\    print(out, process.stop_requested(all[1]), maybe is None)
        \\    return 0
    , "", "");
}

test "main declares at most one Stop" {
    try expectFirst(
        \\func main(first: Stop, second: Stop) -> int:
        \\    return 0
    , "E_MAIN", "at most one");
}

test "the process operations take a Stop and refuse anything else" {
    try expectFirst(
        \\import process
        \\
        \\func main(out: Stream) -> int:
        \\    print(out, process.stop_requested(3))
        \\    return 0
    , "E_TYPE", "");
    try expectFirst(
        \\func main(out: Stream, stop: Stop) -> int:
        \\    print(out, stop_control(stop, "read"))
        \\    return 0
    , "E_TYPE", "");
}

test "a Stop reached through a field has no methods, and the message names process.stop_requested" {
    try expectFirst(
        \\record Holder:
        \\    stop: Stop
        \\
        \\func main(out: Stream, stop: Stop) -> int:
        \\    const holder = Holder(stop=stop)
        \\    print(out, holder.stop.requested())
        \\    return 0
    , "E_COLLECTION_METHOD", "process.stop_requested(holder.stop)");
}

test "a method called on a Stop local names process.stop_requested, not a function form that does not exist" {
    try expectFirst(
        \\func main(out: Stream, stop: Stop) -> int:
        \\    print(out, stop.requested())
        \\    return 0
    , "E_UNKNOWN_TYPE", "read it with process.stop_requested(stop)");
}

test "an ordinary program cannot build a Stop stand-in directly" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const checked = try fixture.check(arena.allocator(),
        \\func main(out: Stream) -> int:
        \\    const stop = __stand_in[Stop](0)
        \\    print(out, 1)
        \\    return 0
    );
    try t.expect(!checked.passed);
}

test "selka run keeps its hooks after its program ends, so a late signal is recorded and does not end it (FR5b)" {
    const linux = std.os.linux;
    const run_signals = @import("compiler.zig").run_signals;
    const waiting = run_signals.Waiting.begin();
    waiting.finish(0);
    var term: linux.Sigaction = undefined;
    var hang: linux.Sigaction = undefined;
    _ = linux.sigaction(.TERM, null, &term);
    _ = linux.sigaction(.HUP, null, &hang);
    const term_hooked = term.handler.handler != linux.SIG.DFL and term.handler.handler != linux.SIG.IGN;
    const hang_hooked = hang.handler.handler != linux.SIG.DFL and hang.handler.handler != linux.SIG.IGN;
    // With no guest the hook only records the signal: this process lives, and as its program exited it repeats nothing.
    try std.posix.raise(.TERM);
    run_signals.endLikeGuest();
    _ = linux.sigaction(.TERM, &waiting.before[0], null);
    _ = linux.sigaction(.INT, &waiting.before[1], null);
    _ = linux.sigaction(.HUP, &waiting.before[2], null);
    try t.expect(term_hooked);
    try t.expect(hang_hooked);
}

test "selka run counts a signal still pending for it as sent, before its hook has run, and waits for nothing else (FR5c)" {
    const linux = std.os.linux;
    const run_signals = @import("compiler.zig").run_signals;
    const waiting = run_signals.Waiting.begin();
    // SIGTERM blocked in this thread and raised: pending, its hook not yet run, as when another thread has not taken it.
    var term_only = linux.sigemptyset();
    linux.sigaddset(&term_only, .TERM);
    _ = linux.sigprocmask(linux.SIG.BLOCK, &term_only, null);
    try std.posix.raise(.TERM);
    const pending_counts = run_signals.sentToo(.TERM);
    // A signal this process passes on that it was never sent is waited for briefly, then not counted.
    const never_sent = run_signals.sentToo(.INT);
    // A crash signal is not waited for at all.
    const crash = run_signals.sentToo(.SEGV);
    // Unblocked, the pending SIGTERM reaches the hook, which only records it with no guest.
    _ = linux.sigprocmask(linux.SIG.UNBLOCK, &term_only, null);
    waiting.finish(0);
    _ = linux.sigaction(.TERM, &waiting.before[0], null);
    _ = linux.sigaction(.INT, &waiting.before[1], null);
    _ = linux.sigaction(.HUP, &waiting.before[2], null);
    try t.expect(pending_counts);
    try t.expect(!never_sent);
    try t.expect(!crash);
}
