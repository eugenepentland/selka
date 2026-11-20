//! A stop passed on to the program a command waits for (FR16, RUN-SIGNALS-1).
//!
//! `selka run`, `run-project` and `build --run` start the guest and wait for it. A supervisor that signals one process
//! (`kill PID`, a timeout command, a service manager's `ExecStop`) used to end the compiler and leave the guest running
//! with no parent. For the wait the compiler now hears SIGTERM, SIGINT and SIGHUP, passes each on to the guest, keeps
//! waiting, and, when the guest died of a signal the compiler was sent too, ends by that signal itself once its own
//! cleanup is done (`endLikeGuest`), so the caller sees the status and the "killed by" record it saw before. A program
//! that does not die of the signal keeps its own exit status.
//!
//! No thread: the handlers only record the signal and pass it on, and the wait is the compiler's own `waitid`. The copy is
//! marked with the sender this process heard (`passOn`), so a program that hears stops counts a signal sent to the
//! whole process group, which reaches it directly and as the copy, once (FR5b). A signal
//! the terminal sent (`SI_KERNEL`: Ctrl-C, a hang-up) already reached the guest through the shared process group, so it
//! is recorded and not sent twice. A signal that arrives before the guest has a process number is kept and sent as soon
//! as it has one. A signal that was ignored when the command started stays ignored (a `nohup selka run` keeps its
//! SIGHUP ignored, and the guest inherits that). A compiler killed outright (SIGKILL, a crash) cannot pass anything on:
//! the guest itself asks the kernel for a SIGKILL when its parent ends (`process_spawn.Options.die_with_parent`).
const std = @import("std");
const linux = std.os.linux;

/// The signals passed on.
const passed = [_]linux.SIG{ .TERM, .INT, .HUP };

/// `si_code` of a signal the kernel itself raised, as the terminal does for Ctrl-C.
const from_kernel: i32 = 0x80;

/// The guest's process number from its start until the compiler has seen it end; 0 outside that.
var guest: std.atomic.Value(linux.pid_t) = .init(0);
/// A bit per signal number heard since `Waiting.begin`.
var heard: std.atomic.Value(u32) = .init(0);
/// A bit per signal number to pass on that the guest has not been sent yet.
var owed: std.atomic.Value(u32) = .init(0);
/// The signal that ended the guest, or 0 when it exited.
var ended_by: std.atomic.Value(u32) = .init(0);
/// Per signal number, the process that sent it last (0 for the kernel), carried by the copy passed on.
var senders: [32]std.atomic.Value(linux.pid_t) = @splat(.init(0));

/// The high half of the value a passed-on signal carries; its low half is the sender this process heard. The runtime's stop
/// handler (`src/core/runtime/core_stop.c`, `CORE_STOP_MARK`) reads it to know a delivery is a copy of a signal the sender
/// may also have sent the program directly (a group kill), so one SIGTERM is one stop (FR5b, D-FR16-3).
const copy_mark: u64 = 0x4d594c53;
/// `si_code` of a signal a process queues with a value (`SI_QUEUE`).
const queued: i32 = -1;

/// Send `signal` to `pid` as a marked copy from `sender`: `rt_sigqueueinfo` with `SI_QUEUE`, this process as the
/// sender of record and the mark and `sender` as the value. A program that does not hear stops dies of it exactly as it
/// died of `kill`: the default action does not read the code. Async-signal-safe (system calls only).
fn passOn(pid: linux.pid_t, signal: linux.SIG, sender: linux.pid_t) void {
    var info: linux.siginfo_t = undefined;
    @memset(std.mem.asBytes(&info), 0);
    info.signo = signal;
    info.code = queued;
    info.fields.common.first.piduid = .{ .pid = linux.getpid(), .uid = linux.getuid() };
    info.fields.common.second.value = .{ .ptr = @ptrFromInt((copy_mark << 32) | @as(u32, @bitCast(sender))) };
    _ = linux.syscall3(.rt_sigqueueinfo, @as(usize, @bitCast(@as(isize, pid))), @backingInt(signal), @intFromPtr(&info));
}

fn bit(signal: linux.SIG) u32 {
    return @as(u32, 1) << @intCast(@backingInt(signal));
}

/// The handler: record the signal, and send it on when the guest exists and the terminal did not already.
fn hear(signal: linux.SIG, info: *const linux.siginfo_t, context: ?*anyopaque) callconv(.c) void {
    _ = context;
    _ = heard.fetchOr(bit(signal), .seq_cst);
    if (info.code == from_kernel) return;
    const sender = info.fields.common.first.piduid.pid;
    senders[@intCast(@backingInt(signal))].store(sender, .seq_cst);
    _ = owed.fetchOr(bit(signal), .seq_cst);
    const pid = guest.load(.seq_cst);
    if (pid == 0) return;
    passOn(pid, signal, sender);
    _ = owed.fetchAnd(~bit(signal), .seq_cst);
}

/// The dispositions found at `begin` (a command keeps its hooks until it exits; a test puts these back); a signal that
/// was ignored is not hooked.
pub const Waiting = struct {
    before: [passed.len]linux.Sigaction = undefined,
    hooked: [passed.len]bool = @splat(false),

    /// Hook the three signals before the guest starts, so none arrives unheard between its start and its process number.
    pub fn begin() Waiting {
        var waiting: Waiting = .{};
        heard.store(0, .seq_cst);
        owed.store(0, .seq_cst);
        ended_by.store(0, .seq_cst);
        for (passed, 0..) |signal, index| {
            if (linux.errno(linux.sigaction(signal, null, &waiting.before[index])) != .SUCCESS) continue;
            if (waiting.before[index].handler.handler == linux.SIG.IGN) continue;
            const action: linux.Sigaction = .{ .handler = .{ .sigaction = hear }, .mask = linux.sigemptyset(), .flags = linux.SA.SIGINFO | linux.SA.RESTART };
            waiting.hooked[index] = linux.errno(linux.sigaction(signal, &action, null)) == .SUCCESS;
        }
        return waiting;
    }

    /// The guest has process number `pid`: pass on what arrived before it, and everything after.
    pub fn started(self: *const Waiting, pid: linux.pid_t) void {
        _ = self;
        guest.store(pid, .seq_cst);
        const pending = owed.swap(0, .seq_cst);
        for (passed) |signal| if (pending & bit(signal) != 0) {
            passOn(pid, signal, senders[@intCast(@backingInt(signal))].load(.seq_cst));
        };
    }

    /// Block until the guest has ended, without collecting it: its process number stays its own until `ended`, so a
    /// signal the handler passes on in the meantime cannot reach a new process that took the number.
    pub fn awaitEnd(self: *const Waiting, pid: linux.pid_t) void {
        _ = self;
        var info: linux.siginfo_t = undefined;
        while (true) switch (linux.errno(linux.waitid(.PID, pid, &info, linux.W.EXITED | linux.W.NOWAIT, null))) {
            .INTR => continue,
            else => break,
        };
        guest.store(0, .seq_cst);
    }

    /// The guest is collected, and `signal` (0 for an exit) ended it: remember `signal`. The hooks stay until the process
    /// ends, and with no guest they only record a signal, so a signal that reaches this process after its program ended
    /// cannot end it by the default action and throw away the program's status (FR5b). Two such signals were seen: the
    /// second half of a sender that signals a process and then its group (`timeout`), arriving after a program that heard
    /// the stop had exited; and the first half itself, taken by another thread of this process too late to be recorded
    /// before the program, stopped by the second half, had ended. This process exits within milliseconds of its program,
    /// so nothing else waits on it. The same holds for SIGHUP. `endLikeGuest` repeats the program's fatal signal by the
    /// default action when this process was sent it too.
    pub fn finish(self: *const Waiting, signal: u32) void {
        _ = self;
        if (signal != 0 and signal < 32) ended_by.store(signal, .seq_cst);
    }
};

/// How long `sentToo` waits, in 1 ms turns, for a hook another thread has taken a signal for but not yet run.
const late_hook_turns = 100;

/// Whether this process was sent `signal` too, which its guest died of: the hook recorded it, or it is still pending for
/// the process. A process-directed signal wakes one thread of this process, and when that is not the thread that waits
/// for the guest, the waiting thread can see the guest dead (killed by the same group signal) before that thread has
/// run the hook, on a loaded machine (FR5c: 97 of 420 rounds with each run pinned beside a busy loop). A pending signal
/// is in the process's shared queue until a thread takes it, and `rt_sigpending` reports it to a thread that blocks it,
/// so this thread blocks `signal` while it looks (and unblocks it again when the answer is no); a signal a thread has
/// taken and not yet recorded is waited for, at most `late_hook_turns` ms, and only for a guest that died of a signal
/// this process passes on (SIGTERM, SIGINT, SIGHUP) that it has not seen. A guest that died of such a signal sent to it
/// alone pays that wait once, and the command then exits with 128 plus the signal, as before.
pub fn sentToo(signal: linux.SIG) bool {
    if (std.mem.indexOfScalar(linux.SIG, &passed, signal) == null) return heard.load(.seq_cst) & bit(signal) != 0;
    var only = linux.sigemptyset();
    linux.sigaddset(&only, signal);
    var before = linux.sigemptyset();
    _ = linux.sigprocmask(linux.SIG.BLOCK, &only, &before);
    var turn: u32 = 0;
    while (turn <= late_hook_turns) : (turn += 1) {
        if (heard.load(.seq_cst) & bit(signal) != 0) return true;
        var pending = linux.sigemptyset();
        _ = linux.syscall2(.rt_sigpending, @intFromPtr(&pending), linux.NSIG / 8);
        if (linux.sigismember(&pending, signal)) return true;
        const pause: linux.timespec = .{ .sec = 0, .nsec = std.time.ns_per_ms };
        _ = linux.nanosleep(&pause, null);
    }
    _ = linux.sigprocmask(linux.SIG.SETMASK, &before, null);
    return false;
}

/// The last thing a command does before it exits: when the guest died of a signal this process was sent too, end by
/// that signal, so the caller sees the same "killed by" record, then 128 plus the signal in a shell, as it saw when the
/// signal ended the compiler directly. Returns when there is nothing to repeat.
pub fn endLikeGuest() void {
    const number = ended_by.load(.seq_cst);
    if (number == 0 or number >= 32) return;
    const signal: linux.SIG = @fromBackingInt(@intCast(number));
    if (!sentToo(signal)) return;
    const default: linux.Sigaction = .{ .handler = .{ .handler = linux.SIG.DFL }, .mask = linux.sigemptyset(), .flags = 0 };
    _ = linux.sigaction(signal, &default, null);
    var unblock = linux.sigemptyset();
    linux.sigaddset(&unblock, signal);
    _ = linux.sigprocmask(linux.SIG.UNBLOCK, &unblock, null);
    _ = linux.kill(linux.getpid(), signal);
}
