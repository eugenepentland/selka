//! The machine state a Debug `selka` prints when it takes a SIGSEGV (F22), ahead of Zig's own report.
//!
//! A compiler child died now and then with "General protection exception (no address available)" at a `@memset`
//! (the self-hosted backend's `mov` plus overlapping `rep movsb`), on a buffer the allocator had just filled. Zig's
//! report names the line and nothing else: not the registers, not whether the processor or the kernel raised the
//! signal, not how much memory the machine had. This handler adds those facts and then hands the signal to the
//! handler Zig installed, which prints its trace and ends the process as before, so the exit status and the text after
//! these lines do not change. It exists only in Debug builds on x86-64 Linux, the compilers the gate and the lanes run.
//!
//! F55 added what tells a memory fault from a processor fault: the faulting address, whether it and the far end of the
//! string operation are readable once the signal arrived, and the mappings on either side of the address. A page fault on
//! memory the allocator filled a moment before (F55) is either a mapping that went away (the neighbours show a hole), a copy
//! that ran past the end of its buffer (the end of the operation is unreadable, the start is not), or the processor or kernel
//! raising a fault that its own page tables do not justify (everything around the address is mapped and readable now).
//!
//! FR15 then found nothing in the compiler behind the deaths and left two facts for the next one (FR14 landed them): the
//! processor the thread ran on, and the 64 bytes around the source and the destination of the copy (from 16 below `rsi`
//! and `rdi`), so a memset that left the allocator's fill in place can be told from a copy that read other bytes.
const std = @import("std");
const builtin = @import("builtin");
const linux = std.os.linux;

/// Whether this build installs the handler: a Debug build on x86-64 Linux, where the layout of the signal context
/// below is the kernel's. Release compilers install nothing.
pub const enabled = builtin.mode == .debug and builtin.os.tag == .linux and builtin.cpu.arch == .x86_64;

/// The general registers the report names.
pub const Registers = struct {
    rip: u64,
    rsi: u64,
    rdi: u64,
    rcx: u64,
    rsp: u64,
};

/// How the signal arose: `signal_code` is `si_code` (0x80, SI_KERNEL, for a general protection fault), `number` the
/// processor's exception vector (13 general protection, 14 page fault, 12 stack segment), `error_code` its error code
/// and `flags` the saved RFLAGS (bit 10 is the direction flag).
pub const Trap = struct {
    signal_code: i32,
    number: u64,
    error_code: u64,
    flags: u64,
};

/// Memory figures in KiB; null when the file or the line could not be read.
pub const Memory = struct {
    resident: ?u64,
    available: ?u64,
    swap_free: ?u64,
};

/// What the report learned about the faulting address after the signal arrived (F55). `address` is the kernel's `si_addr`
/// (null for a general protection fault, which names none); each `readable` flag is whether a one byte read of that address
/// succeeds now, null when the address is not canonical and was not tried.
pub const Probe = struct {
    address: ?u64,
    address_readable: ?bool,
    destination_end_readable: ?bool,
    source_end_readable: ?bool,
};

/// The mappings of `/proc/self/maps` on either side of an address, one line each, cut at `line_capacity` bytes; `inside`
/// is true when the address lies within a mapping (then `before` is that mapping).
pub const Neighbours = struct {
    before: [line_capacity]u8 = undefined,
    before_len: usize = 0,
    after: [line_capacity]u8 = undefined,
    after_len: usize = 0,
    inside: bool = false,

    /// The mapping at or below the address.
    pub fn lower(self: *const Neighbours) []const u8 {
        return self.before[0..self.before_len];
    }

    /// The first mapping above the address.
    pub fn upper(self: *const Neighbours) []const u8 {
        return self.after[0..self.after_len];
    }
};

/// Bytes kept of one mapping line: the range, permissions, offset and the start of the path.
pub const line_capacity: usize = 160;

/// What `snapshot` reads out of a signal context.
pub const Snapshot = struct {
    registers: Registers,
    trap: Trap,
};

/// The kernel's x86-64 `ucontext_t` as far as the report reads it: the first three words and the stack description
/// (40 bytes), then `mcontext.gregs` in the order of the kernel's `struct sigcontext`.
pub const SignalContext = extern struct {
    flags: u64,
    link: ?*anyopaque,
    stack: [3]u64,
    gregs: [23]u64,
};

/// Indices into `SignalContext.gregs` (the kernel's `struct sigcontext` order).
const reg = struct {
    const rdi = 8;
    const rsi = 9;
    const rcx = 14;
    const rsp = 15;
    const rip = 16;
    const flags = 17;
    const err = 19;
    const trapno = 20;
};

/// Whether `address` is a canonical 48-bit virtual address (bits 63..47 all equal). A non-canonical operand is what
/// makes the processor raise a general protection fault instead of a page fault.
pub fn isCanonical(address: u64) bool {
    const high = @as(i64, @bitCast(address)) >> 47;
    return high == 0 or high == -1;
}

/// The value of the `key:` line of a `/proc` file in `text` (`VmRSS:   1234 kB` gives 1234); null when the key is
/// absent or has no number.
pub fn kilobytes(text: []const u8, key: []const u8) ?u64 {
    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |line| {
        if (!std.mem.startsWith(u8, line, key) or line.len <= key.len or line[key.len] != ':') continue;
        const rest = std.mem.trim(u8, line[key.len + 1 ..], " \t");
        const digits = rest[0 .. std.mem.indexOfAny(u8, rest, " \t") orelse rest.len];
        return std.fmt.parseInt(u64, digits, 10) catch null;
    }
    return null;
}

/// The registers and trap fields of a signal context.
pub fn snapshot(context: *const SignalContext, signal_code: i32) Snapshot {
    return .{
        .registers = .{
            .rip = context.gregs[reg.rip],
            .rsi = context.gregs[reg.rsi],
            .rdi = context.gregs[reg.rdi],
            .rcx = context.gregs[reg.rcx],
            .rsp = context.gregs[reg.rsp],
        },
        .trap = .{
            .signal_code = signal_code,
            .number = context.gregs[reg.trapno],
            .error_code = context.gregs[reg.err],
            .flags = context.gregs[reg.flags],
        },
    };
}

/// The report: four lines of registers, canonical checks (including the far ends of a forward string operation,
/// `rsi + rcx` and `rdi + rcx`), the bytes at `rip` (`code`, up to 16; `??` when unreadable) and the memory figures.
/// Writes into `out` and returns the used part; the text is cut when `out` is too small.
pub fn describe(out: []u8, state: Snapshot, code: []const u8, memory: Memory) []const u8 {
    var writer = std.Io.Writer.fixed(out);
    write(&writer, state, code, memory) catch |err| switch (err) {
        error.WriteFailed => return writer.buffered(), // `out` is full: the text is cut there
    };
    return writer.buffered();
}

/// The F55 lines: the address and the readability probes, then the mappings beside the address. Writes into `out` and
/// returns the used part, cut when `out` is too small.
pub fn describeFault(out: []u8, probe: Probe, neighbours: *const Neighbours) []const u8 {
    var writer = std.Io.Writer.fixed(out);
    writeFault(&writer, probe, neighbours) catch |err| switch (err) {
        error.WriteFailed => return writer.buffered(), // `out` is full: the text is cut there
    };
    return writer.buffered();
}

/// Bytes a window holds: 16 before the register and 48 from it.
pub const window_len: usize = 64;
/// The window is read and reported in chunks of this many bytes, each readable or not on its own.
pub const chunk_len: usize = 16;

/// The memory around one operand of the faulting string copy (FR15, FR14): `window_len` bytes from `start` (the register
/// minus 16), and for each chunk of `chunk_len` bytes whether it could be read once the signal arrived.
pub const Window = struct {
    start: u64,
    data: [window_len]u8 = @splat(0),
    readable: [window_len / chunk_len]bool = @splat(false),
};

/// The lines that say which processor took the fault and what the copy's source and destination held (FR15's evidence
/// for F22: a memset that left the allocator's 0xaa fill in place reads differently from a copy that read the wrong bytes):
/// `cpu` (null when `getcpu` failed), then each window in hexadecimal, a chunk that could not be read as `??`. Writes into
/// `out` and returns the used part, cut when `out` is too small.
pub fn describeCopy(out: []u8, cpu: ?u32, source: Window, destination: Window) []const u8 {
    var writer = std.Io.Writer.fixed(out);
    writeCopy(&writer, cpu, source, destination) catch |err| switch (err) {
        error.WriteFailed => return writer.buffered(), // `out` is full: the text is cut there
    };
    return writer.buffered();
}

fn writeCopy(writer: *std.Io.Writer, cpu: ?u32, source: Window, destination: Window) std.Io.Writer.Error!void {
    try writer.writeAll("crash-state: cpu=");
    if (cpu) |number| try writer.print("{d}", .{number}) else try writer.writeAll("?");
    try writer.print(" src_window=0x{x} dst_window=0x{x}\n", .{ source.start, destination.start });
    try writeWindow(writer, "src_bytes", source);
    try writeWindow(writer, "dst_bytes", destination);
}

fn writeWindow(writer: *std.Io.Writer, label: []const u8, window: Window) std.Io.Writer.Error!void {
    try writer.print("crash-state: {s}=", .{label});
    for (window.readable, 0..) |readable, chunk| {
        if (chunk != 0) try writer.writeAll(" ");
        if (!readable) {
            try writer.writeAll("??");
            continue;
        }
        for (window.data[chunk * chunk_len ..][0..chunk_len]) |byte| try writer.print("{x:0>2}", .{byte});
    }
    try writer.writeAll("\n");
}

fn writeFault(writer: *std.Io.Writer, probe: Probe, neighbours: *const Neighbours) std.Io.Writer.Error!void {
    try writer.writeAll("crash-state: fault_addr=");
    if (probe.address) |address| try writer.print("0x{x}", .{address}) else try writer.writeAll("?");
    try writer.writeAll(" readable_now=");
    try flag(writer, probe.address_readable);
    try writer.writeAll(" dest_end_readable=");
    try flag(writer, probe.destination_end_readable);
    try writer.writeAll(" src_end_readable=");
    try flag(writer, probe.source_end_readable);
    try writer.print(" inside_mapping={d}\n", .{@intFromBool(neighbours.inside)});
    try writer.print("crash-state: map_at_or_below={s}\n", .{neighbours.lower()});
    try writer.print("crash-state: map_above={s}\n", .{neighbours.upper()});
}

fn flag(writer: *std.Io.Writer, value: ?bool) std.Io.Writer.Error!void {
    try writer.writeAll(if (value) |known| (if (known) "1" else "0") else "?");
}

/// Fold one line of `/proc/self/maps` into `found` for `address`: keep the last mapping that starts at or below it and the
/// first that starts above it. The file is in ascending order, so a caller passes its lines in order and stops after the
/// first line above the address (`true` is returned once `found` has its upper neighbour).
pub fn considerMapping(found: *Neighbours, line: []const u8, address: u64) bool {
    const dash = std.mem.indexOfScalar(u8, line, '-') orelse return false;
    const space = std.mem.indexOfScalar(u8, line, ' ') orelse return false;
    if (dash > space) return false;
    const start = std.fmt.parseInt(u64, line[0..dash], 16) catch return false;
    const end = std.fmt.parseInt(u64, line[dash + 1 .. space], 16) catch return false;
    const kept = line[0..@min(line.len, line_capacity)];
    if (start > address) {
        @memcpy(found.after[0..kept.len], kept);
        found.after_len = kept.len;
        return true;
    }
    @memcpy(found.before[0..kept.len], kept);
    found.before_len = kept.len;
    found.inside = address < end;
    return false;
}

fn write(writer: *std.Io.Writer, state: Snapshot, code: []const u8, memory: Memory) std.Io.Writer.Error!void {
    const r = state.registers;
    const t = state.trap;
    try writer.print("crash-state: si_code=0x{x} trap={d} error=0x{x} rflags=0x{x} df={d}\n", .{ @as(u32, @bitCast(t.signal_code)), t.number, t.error_code, t.flags, (t.flags >> 10) & 1 });
    try writer.print("crash-state: rip=0x{x} rsi=0x{x} rdi=0x{x} rcx=0x{x} rsp=0x{x}\n", .{ r.rip, r.rsi, r.rdi, r.rcx, r.rsp });
    try writer.print("crash-state: canonical rip={d} rsi={d} rdi={d} rsp={d} rsi+rcx={d} rdi+rcx={d}\n", .{
        @intFromBool(isCanonical(r.rip)),
        @intFromBool(isCanonical(r.rsi)),
        @intFromBool(isCanonical(r.rdi)),
        @intFromBool(isCanonical(r.rsp)),
        @intFromBool(isCanonical(r.rsi +% r.rcx)),
        @intFromBool(isCanonical(r.rdi +% r.rcx)),
    });
    try writer.writeAll("crash-state: code=");
    for (0..16) |at| {
        if (at < code.len) try writer.print("{x:0>2} ", .{code[at]}) else try writer.writeAll("?? ");
    }
    try writer.writeAll("\n");
    try writer.writeAll("crash-state: vmrss_kb=");
    try figure(writer, memory.resident);
    try writer.writeAll(" mem_available_kb=");
    try figure(writer, memory.available);
    try writer.writeAll(" swap_free_kb=");
    try figure(writer, memory.swap_free);
    try writer.writeAll("\n");
}

fn figure(writer: *std.Io.Writer, value: ?u64) std.Io.Writer.Error!void {
    if (value) |number| try writer.print("{d}", .{number}) else try writer.writeAll("?");
}

/// The text of `path` (at most `buffer.len` bytes), read with raw system calls so it is safe inside a signal handler.
fn slurp(path: [*:0]const u8, buffer: []u8) []const u8 {
    const opened = linux.open(path, .{ .ACCMODE = .RDONLY, .CLOEXEC = true }, 0);
    if (linux.errno(opened) != .SUCCESS) return buffer[0..0];
    const fd: i32 = @intCast(opened);
    defer _ = linux.close(fd);
    const got = linux.read(fd, buffer.ptr, buffer.len);
    return if (linux.errno(got) == .SUCCESS) buffer[0..got] else buffer[0..0];
}

fn readMemory() Memory {
    var buffer: [4096]u8 = undefined;
    const resident = kilobytes(slurp("/proc/self/status", &buffer), "VmRSS");
    const meminfo = slurp("/proc/meminfo", &buffer);
    return .{ .resident = resident, .available = kilobytes(meminfo, "MemAvailable"), .swap_free = kilobytes(meminfo, "SwapFree") };
}

/// Up to 16 bytes at `address` in this process, or none when the range is not readable; `process_vm_readv` on
/// ourselves reports an unmapped range as an error where a plain read would fault again inside the handler.
fn readCode(buffer: *[16]u8, address: u64) []const u8 {
    if (!isCanonical(address)) return buffer[0..0];
    var local = [_]std.posix.iovec{.{ .base = buffer, .len = buffer.len }};
    var remote = [_]std.posix.iovec_const{.{ .base = @ptrFromInt(address), .len = buffer.len }};
    const got = linux.process_vm_readv(linux.getpid(), &local, &remote, 0);
    return if (linux.errno(got) == .SUCCESS) buffer[0..got] else buffer[0..0];
}

/// Whether one byte at `address` can be read now, by `process_vm_readv` on this process (an error, not a second fault,
/// for an unmapped address); null for an address that is not canonical.
fn readableNow(address: u64) ?bool {
    if (!isCanonical(address) or address == 0) return null;
    var byte: [1]u8 = undefined;
    var local = [_]std.posix.iovec{.{ .base = &byte, .len = 1 }};
    var remote = [_]std.posix.iovec_const{.{ .base = @ptrFromInt(address), .len = 1 }};
    return linux.errno(linux.process_vm_readv(linux.getpid(), &local, &remote, 0)) == .SUCCESS;
}

/// The mappings beside `address`, read from `/proc/self/maps` with raw system calls (safe inside a signal handler).
fn readNeighbours(address: u64) Neighbours {
    var found: Neighbours = .{};
    const opened = linux.open("/proc/self/maps", .{ .ACCMODE = .RDONLY, .CLOEXEC = true }, 0);
    if (linux.errno(opened) != .SUCCESS) return found;
    const fd: i32 = @intCast(opened);
    defer _ = linux.close(fd);
    var chunk: [4096]u8 = undefined;
    var line: [512]u8 = undefined;
    var line_len: usize = 0;
    while (true) {
        const got = linux.read(fd, &chunk, chunk.len);
        if (linux.errno(got) != .SUCCESS or got == 0) break;
        for (chunk[0..got]) |byte| {
            if (byte != '\n') {
                if (line_len < line.len) {
                    line[line_len] = byte;
                    line_len += 1;
                }
                continue;
            }
            const done = considerMapping(&found, line[0..line_len], address);
            line_len = 0;
            if (done) return found;
        }
    }
    return found;
}

/// The window around `register`: the 64 bytes from 16 below it, read chunk by chunk with `process_vm_readv`, so an unmapped
/// chunk is marked unreadable instead of faulting inside the handler.
fn readWindow(register: u64) Window {
    var window: Window = .{ .start = register -% 16 };
    for (&window.readable, 0..) |*readable, chunk| {
        var buffer: [16]u8 = undefined;
        const got = readCode(&buffer, window.start +% chunk * chunk_len);
        readable.* = got.len == chunk_len;
        if (readable.*) @memcpy(window.data[chunk * chunk_len ..][0..chunk_len], got);
    }
    return window;
}

/// The processor this thread runs on, by the raw `getcpu` system call (safe inside a signal handler); null when it fails.
fn currentCpu() ?u32 {
    var cpu: u32 = 0;
    const status = linux.syscall3(.getcpu, @intFromPtr(&cpu), 0, 0);
    return if (linux.errno(status) == .SUCCESS) cpu else null;
}

/// What a read tells about the faulting address and the far ends of the string operation `registers` describes.
fn probeFault(info: *const linux.siginfo_t, registers: Registers) Probe {
    // Only a fault (`SEGV_MAPERR` 1, `SEGV_ACCERR` 2, ...) carries an address: a general protection fault (SI_KERNEL, 0x80) and a
    // signal sent by `kill` (SI_USER, 0) fill the field with something else.
    const faulted = info.code > 0 and info.code != 0x80;
    const address: ?u64 = if (faulted) @intFromPtr(info.fields.sigfault.addr) else null;
    return .{
        .address = address,
        .address_readable = if (address) |at| readableNow(at) else null,
        .destination_end_readable = readableNow(registers.rdi +% registers.rcx -% 1),
        .source_end_readable = readableNow(registers.rsi +% registers.rcx -% 1),
    };
}

var previous: linux.Sigaction = undefined;

fn onSegv(signal: linux.SIG, info: *const linux.siginfo_t, context: ?*anyopaque) callconv(.c) void {
    if (context) |raw| {
        const state = snapshot(@ptrCast(@alignCast(raw)), info.code);
        var code_buffer: [16]u8 = undefined;
        const code = readCode(&code_buffer, state.registers.rip);
        var out: [1024]u8 = undefined;
        const text = describe(&out, state, code, readMemory());
        _ = linux.write(2, text.ptr, text.len);
        const probe = probeFault(info, state.registers);
        const neighbours = if (probe.address) |at| readNeighbours(at) else Neighbours{};
        var fault_out: [1024]u8 = undefined;
        const fault_text = describeFault(&fault_out, probe, &neighbours);
        _ = linux.write(2, fault_text.ptr, fault_text.len);
        var copy_out: [512]u8 = undefined;
        const copy_text = describeCopy(&copy_out, currentCpu(), readWindow(state.registers.rsi), readWindow(state.registers.rdi));
        _ = linux.write(2, copy_text.ptr, copy_text.len);
    }
    // Zig's handler prints its trace and aborts; it does not return. Were it not installed the default action
    // runs when this returns, because RESETHAND already restored it.
    if (previous.handler.sigaction) |next| next(signal, info, context);
}

/// Put the report in front of the SIGSEGV handler Zig installed at start. Does nothing in a build that is not
/// `enabled`, or when no `SA_SIGINFO` handler is installed to hand the signal to.
pub fn install() void {
    if (!enabled) return;
    var current: linux.Sigaction = undefined;
    if (linux.errno(linux.sigaction(.SEGV, null, &current)) != .SUCCESS) return;
    if (current.flags & linux.SA.SIGINFO == 0 or current.handler.sigaction == null) return;
    previous = current;
    const act: linux.Sigaction = .{
        .handler = .{ .sigaction = onSegv },
        .mask = linux.sigemptyset(),
        .flags = linux.SA.SIGINFO | linux.SA.RESTART | linux.SA.RESETHAND | linux.SA.ONSTACK,
    };
    _ = linux.sigaction(.SEGV, &act, null);
}

// spec: F22-CRASH-STATE-1
test "the crash report states the registers, the canonical checks, the code bytes and the memory figures" {
    const state: Snapshot = .{
        .registers = .{ .rip = 0x1c13ec2, .rsi = 0x7f00_1000_0000, .rdi = 0x7f00_1000_0004, .rcx = 0x1c, .rsp = 0x7ffd_0000_1000 },
        .trap = .{ .signal_code = 0x80, .number = 13, .error_code = 0, .flags = 0x10246 },
    };
    var out: [1024]u8 = undefined;
    const text = describe(&out, state, &.{ 0xf3, 0xa4, 0x48, 0xc7 }, .{ .resident = 123_456, .available = 654_321, .swap_free = null });
    try std.testing.expectEqualStrings(
        "crash-state: si_code=0x80 trap=13 error=0x0 rflags=0x10246 df=0\n" ++
            "crash-state: rip=0x1c13ec2 rsi=0x7f0010000000 rdi=0x7f0010000004 rcx=0x1c rsp=0x7ffd00001000\n" ++
            "crash-state: canonical rip=1 rsi=1 rdi=1 rsp=1 rsi+rcx=1 rdi+rcx=1\n" ++
            "crash-state: code=f3 a4 48 c7 ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? \n" ++
            "crash-state: vmrss_kb=123456 mem_available_kb=654321 swap_free_kb=?\n",
        text,
    );
}

// spec-case: F22-CRASH-STATE-1
test "the crash report marks a non-canonical operand and a set direction flag" {
    const state: Snapshot = .{
        .registers = .{ .rip = 0x1000, .rsi = 0xaaaa_aaaa_aaaa_aaaa, .rdi = 0x7fff_ffff_f000, .rcx = 0x1000, .rsp = 0x7ffd_0000_1000 },
        .trap = .{ .signal_code = 0x80, .number = 13, .error_code = 0, .flags = 0x10646 },
    };
    var out: [1024]u8 = undefined;
    const text = describe(&out, state, &.{}, .{ .resident = null, .available = null, .swap_free = null });
    try std.testing.expect(std.mem.indexOf(u8, text, "df=1\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "canonical rip=1 rsi=0 rdi=1 rsp=1 rsi+rcx=0 rdi+rcx=0\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "vmrss_kb=? mem_available_kb=? swap_free_kb=?\n") != null);
}

// spec-case: F22-CRASH-STATE-1
test "canonical addresses are the 48-bit ones and kilobyte lines are read by key" {
    try std.testing.expect(isCanonical(0));
    try std.testing.expect(isCanonical(0x7fff_ffff_ffff));
    try std.testing.expect(isCanonical(0xffff_8000_0000_0000));
    try std.testing.expect(!isCanonical(0x8000_0000_0000));
    try std.testing.expect(!isCanonical(0xaaaa_aaaa_aaaa_aaaa));
    const meminfo = "MemTotal:       29409660 kB\nMemAvailable:   14684160 kB\nSwapTotal:       8388604 kB\nSwapFree:         312960 kB\n";
    try std.testing.expectEqual(@as(?u64, 14684160), kilobytes(meminfo, "MemAvailable"));
    try std.testing.expectEqual(@as(?u64, 312960), kilobytes(meminfo, "SwapFree"));
    try std.testing.expectEqual(@as(?u64, null), kilobytes(meminfo, "VmRSS"));
    try std.testing.expectEqual(@as(?u64, null), kilobytes("MemAvailableX: 1 kB\n", "MemAvailable"));
}

// spec-case: F22-CRASH-STATE-1
test "a signal context yields the registers and the trap the kernel saved" {
    var context: SignalContext = std.mem.zeroes(SignalContext);
    context.gregs[reg.rip] = 0x1c13ec2;
    context.gregs[reg.rsi] = 0x1111;
    context.gregs[reg.rdi] = 0x2222;
    context.gregs[reg.rcx] = 0x33;
    context.gregs[reg.rsp] = 0x4444;
    context.gregs[reg.trapno] = 13;
    context.gregs[reg.err] = 0x10;
    context.gregs[reg.flags] = 0x246;
    const state = snapshot(&context, 0x80);
    try std.testing.expectEqual(Registers{ .rip = 0x1c13ec2, .rsi = 0x1111, .rdi = 0x2222, .rcx = 0x33, .rsp = 0x4444 }, state.registers);
    try std.testing.expectEqual(Trap{ .signal_code = 0x80, .number = 13, .error_code = 0x10, .flags = 0x246 }, state.trap);
    try std.testing.expectEqual(@as(usize, 40 + 23 * 8), @sizeOf(SignalContext));
}

// spec-case: F22-CRASH-STATE-1
test "the fault report states the address, the readability probes and the mappings beside it" {
    var neighbours: Neighbours = .{};
    const done_below = considerMapping(&neighbours, "7f0010000000-7f0010021000 rw-p 00000000 00:00 0", 0x7f0010021000);
    const done_above = considerMapping(&neighbours, "7f0010040000-7f0010060000 rw-p 00000000 00:00 0                          [heap]", 0x7f0010021000);
    try std.testing.expect(!done_below);
    try std.testing.expect(done_above);
    var out: [1024]u8 = undefined;
    const text = describeFault(&out, .{ .address = 0x7f0010021000, .address_readable = false, .destination_end_readable = true, .source_end_readable = null }, &neighbours);
    try std.testing.expectEqualStrings(
        "crash-state: fault_addr=0x7f0010021000 readable_now=0 dest_end_readable=1 src_end_readable=? inside_mapping=0\n" ++
            "crash-state: map_at_or_below=7f0010000000-7f0010021000 rw-p 00000000 00:00 0\n" ++
            "crash-state: map_above=7f0010040000-7f0010060000 rw-p 00000000 00:00 0                          [heap]\n",
        text,
    );
}

// spec-case: F22-CRASH-STATE-1
test "a general protection fault names no address and an address inside a mapping is reported as such" {
    var neighbours: Neighbours = .{};
    _ = considerMapping(&neighbours, "00400000-00452000 r-xp 00000000 08:02 173521 /usr/bin/dbus-daemon", 0x410000);
    _ = considerMapping(&neighbours, "garbage", 0x410000);
    try std.testing.expect(neighbours.inside);
    var out: [1024]u8 = undefined;
    const text = describeFault(&out, .{ .address = null, .address_readable = null, .destination_end_readable = null, .source_end_readable = null }, &neighbours);
    try std.testing.expect(std.mem.indexOf(u8, text, "fault_addr=? readable_now=? dest_end_readable=? src_end_readable=? inside_mapping=1\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "map_above=\n") != null);
}

// spec-case: F22-CRASH-STATE-1
test "this process's own mappings place an address inside one and a stack address between neighbours" {
    var local: u8 = 0;
    const here = @intFromPtr(&local);
    const found = readNeighbours(here);
    try std.testing.expect(found.inside);
    try std.testing.expect(found.lower().len != 0);
    try std.testing.expectEqual(@as(?bool, true), readableNow(here));
    try std.testing.expectEqual(@as(?bool, null), readableNow(0xaaaa_aaaa_aaaa_aaaa));
    try std.testing.expectEqual(@as(?bool, false), readableNow(0x1000));
}

// spec-case: F22-CRASH-STATE-1
test "the copy report names the processor and the bytes around the source and the destination, an unreadable chunk as ??" {
    var source: Window = .{ .start = 0x7f0010000000 - 16 };
    @memset(&source.data, 0xaa);
    source.readable = .{ true, true, true, false };
    source.data[16] = 0x41;
    var destination: Window = .{ .start = 0x7f0010000004 - 16 };
    for (&destination.data, 0..) |*byte, at| byte.* = @intCast(at);
    destination.readable = @splat(true);
    var out: [512]u8 = undefined;
    const text = describeCopy(&out, 7, source, destination);
    const fill = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
    try std.testing.expectEqualStrings(
        "crash-state: cpu=7 src_window=0x7f000ffffff0 dst_window=0x7f000ffffff4\n" ++
            "crash-state: src_bytes=" ++ fill ++ " 41aaaaaaaaaaaaaaaaaaaaaaaaaaaaaa " ++ fill ++ " ??\n" ++
            "crash-state: dst_bytes=000102030405060708090a0b0c0d0e0f 101112131415161718191a1b1c1d1e1f " ++
            "202122232425262728292a2b2c2d2e2f 303132333435363738393a3b3c3d3e3f\n",
        text,
    );
    const unknown = describeCopy(&out, null, .{ .start = 0 }, .{ .start = 0 });
    try std.testing.expect(std.mem.startsWith(u8, unknown, "crash-state: cpu=? src_window=0x0 dst_window=0x0\ncrash-state: src_bytes=?? ?? ?? ??\n"));
}

// spec-case: F22-CRASH-STATE-1
test "a window reads this process's memory around a register and marks an unmapped or non-canonical one unreadable" {
    var buffer: [96]u8 = undefined;
    for (&buffer, 0..) |*byte, at| byte.* = @intCast(at);
    const window = readWindow(@intFromPtr(&buffer) + 16);
    try std.testing.expectEqual(@intFromPtr(&buffer), window.start);
    try std.testing.expectEqualSlices(bool, &.{ true, true, true, true }, &window.readable);
    try std.testing.expectEqualSlices(u8, buffer[0..window_len], &window.data);
    const wild = readWindow(0xaaaa_aaaa_aaaa_aaaa);
    try std.testing.expectEqualSlices(bool, &.{ false, false, false, false }, &wild.readable);
    try std.testing.expect(currentCpu() != null);
}
