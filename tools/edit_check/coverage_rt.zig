//! Coverage runtime for the edit check's instrumented build (EC1).
//!
//! The pinned Zig's `-ffuzz` makes LLVM emit one inline 8-bit counter per control-flow
//! edge (`__sancov_cntrs`) and a table with the address of each (`__sancov_pcs1`), and
//! links Zig's own fuzzer runtime. This object records, when the process exits, which
//! counters ran. It is linked only into the coverage variant (`build_coverage.zig`)
//! and is compiled without instrumentation. A program that nothing else ties to the
//! fuzzer runtime also links `coverage_hooks.zig`, which defines the hooks that
//! runtime exports so the linker never pulls it out of its archive.
//!
//! The counters are 8 bits and wrap, so an edge that ran exactly a multiple of 256 times
//! reads zero. While `SELKA_COVERAGE_DIR` is set, a sampling thread therefore ORs the
//! counters into a shadow bitmap every `SELKA_COVERAGE_SAMPLE_MS` milliseconds (default
//! 5, `0` turns it off), and the exit hook ORs them once more: only an edge that ran a
//! multiple of 256 times inside a single interval, and never before, can read zero.
//!
//! Output: `$SELKA_COVERAGE_DIR/$SELKA_COVERAGE_TEST/<pid>.cov`: a header (the executable's
//! path and its GNU build id, which a copy of the same binary shares), then the
//! ascending indices of the counters that ran, delta-coded as LEB128, then the
//! ascending indices among them that read zero at exit and were seen only by the
//! sampler (the wrapped counters). The index is the PC table's index, so a reader that
//! has the same binary maps it to source. A process with no `SELKA_COVERAGE_DIR` and
//! no ancestor that has one writes nothing.
//!
//! A test often starts its compiler with a cleared or explicit environment (the CLI
//! tests run user commands under an empty `PATH`), so the variables never reach it. Such a
//! process adopts the directory and test of its nearest ancestor that has them, read from
//! `/proc/<pid>/environ` at start, so the hit set it writes still belongs to the test that
//! started it. The walk runs only in this coverage runtime, never in the normal build.
const std = @import("std");
const linux = std.os.linux;
const builtin = @import("builtin");
const build_id = @import("build_id.zig");

/// Written at the start of every `.cov` file. The version is bumped with each change of the layout.
pub const magic = "MYLCOV03";

const counters_start = @extern([*]const u8, .{ .name = "__start___sancov_cntrs", .linkage = .weak });
const counters_stop = @extern([*]const u8, .{ .name = "__stop___sancov_cntrs", .linkage = .weak });
const pcs_start = @extern([*]const usize, .{ .name = "__start___sancov_pcs1", .linkage = .weak });

extern "c" fn atexit(callback: *const fn () callconv(.c) void) c_int;
extern "c" fn pthread_create(thread: *usize, attr: ?*const anyopaque, start: *const fn (?*anyopaque) callconv(.c) ?*anyopaque, arg: ?*anyopaque) c_int;
extern "c" fn pthread_sigmask(how: c_int, set: ?*const std.c.sigset_t, old: ?*std.c.sigset_t) c_int;

/// Default sampling interval in milliseconds.
const default_sample_ms: u32 = 5;
/// Bytes OR-ed by the sampling thread and the exit hook: a counter ever seen nonzero.
var shadow: ?[*]u8 = null;

/// Runs before `main` (glibc and Zig's own start code both run `.init_array`).
export const selka_coverage_init: *const fn () callconv(.c) void linksection(".init_array") = &init;

/// Where this process writes its hit set: the directory, and the test's token (sanitized to one path component).
/// `record_dir_len` is 0 when the process records nothing.
var record_dir: [4096]u8 = undefined;
var record_dir_len: usize = 0;
var record_test: [256]u8 = undefined;
var record_test_len: usize = 0;

/// Most ancestors the walk reads before it gives up.
const max_ancestors = 32;

fn init() callconv(.c) void {
    _ = atexit(&flush);
    if (!adoptOwn()) adoptAncestor();
    if (record_dir_len == 0) return;
    const interval = sampleInterval();
    const start = counters_start orelse return;
    const stop = counters_stop orelse return;
    if (interval == 0 or stop == start) return;
    const memory = std.c.mmap(null, stop - start, .{ .READ = true, .WRITE = true }, .{ .TYPE = .PRIVATE, .ANONYMOUS = true }, -1, 0);
    if (@intFromPtr(memory) == std.math.maxInt(usize)) return;
    shadow = @ptrCast(memory);
    // The sampler must not take the process's signals: block them all while it is created.
    var everything: std.c.sigset_t = undefined;
    @memset(std.mem.asBytes(&everything), 0xff);
    var previous: std.c.sigset_t = undefined;
    _ = pthread_sigmask(0, &everything, &previous);
    var thread: usize = 0;
    _ = pthread_create(&thread, null, &sampler, @ptrFromInt(interval));
    _ = pthread_sigmask(2, &previous, null);
}

fn sampleInterval() u32 {
    const text = std.c.getenv("SELKA_COVERAGE_SAMPLE_MS") orelse return default_sample_ms;
    return std.fmt.parseInt(u32, std.mem.span(@as([*:0]const u8, text)), 10) catch default_sample_ms;
}

/// Holds the environment block of an ancestor while the walk reads it.
var environ_block: [64 * 1024]u8 = undefined;

/// Records the directory and test of this process from its own environment; true when it has a directory.
fn adoptOwn() bool {
    const dir = std.c.getenv("SELKA_COVERAGE_DIR") orelse return false;
    const test_name = if (std.c.getenv("SELKA_COVERAGE_TEST")) |text| std.mem.span(text) else "_";
    _ = record(std.mem.span(dir), test_name);
    return true;
}

/// Records the directory and test of the nearest ancestor whose environment names a directory.
fn adoptAncestor() void {
    var pid: i32 = linux.getpid();
    var stat: [1024]u8 = undefined;
    for (0..max_ancestors) |_| {
        pid = parentOf(pid, &stat) orelse return;
        if (pid <= 1) return;
        var path: [64]u8 = undefined;
        const name = std.mem.printSentinel(&path, "/proc/{d}/environ", .{pid}, 0) catch return;
        const block = readProc(name, &environ_block) orelse continue;
        const dir = environValue(block, "SELKA_COVERAGE_DIR") orelse continue;
        _ = record(dir, environValue(block, "SELKA_COVERAGE_TEST") orelse "_");
        return;
    }
}

/// Stores a directory and a test token as this process's record; false when either does not fit.
fn record(dir: []const u8, test_name: []const u8) bool {
    const name = if (test_name.len == 0) "_" else test_name;
    if (dir.len == 0 or dir.len > record_dir.len or name.len > record_test.len) return false;
    @memcpy(record_dir[0..dir.len], dir);
    record_dir_len = dir.len;
    // The token is data from the environment: keep it one path component.
    for (name, 0..) |byte, index| record_test[index] = if (byte == '/') '_' else byte;
    record_test_len = name.len;
    return true;
}

/// The parent of process `pid`, from `/proc/<pid>/stat`; null when it cannot be read.
fn parentOf(pid: i32, buffer: []u8) ?i32 {
    var path: [64]u8 = undefined;
    const name = std.mem.printSentinel(&path, "/proc/{d}/stat", .{pid}, 0) catch return null;
    const text = readProc(name, buffer) orelse return null;
    // The command name sits in parentheses and may hold spaces: the fields after its last `)` follow it.
    const close = std.mem.lastIndexOfScalar(u8, text, ')') orelse return null;
    var fields = std.mem.tokenizeScalar(u8, text[close + 1 ..], ' ');
    _ = fields.next() orelse return null;
    const parent = fields.next() orelse return null;
    return std.fmt.parseInt(i32, parent, 10) catch null;
}

/// Reads the file at `path` into `buffer` (up to its length); null when it cannot be opened or read.
fn readProc(path: [:0]const u8, buffer: []u8) ?[]u8 {
    const opened = linux.open(path.ptr, .{ .ACCMODE = .RDONLY, .CLOEXEC = true }, 0);
    if (linux.errno(opened) != .SUCCESS) return null;
    const fd: i32 = @intCast(opened);
    defer _ = linux.close(fd);
    var total: usize = 0;
    while (total < buffer.len) {
        const count = linux.read(fd, buffer[total..].ptr, buffer.len - total);
        if (linux.errno(count) != .SUCCESS) return null;
        if (count == 0) break;
        total += count;
    }
    return buffer[0..total];
}

/// The value of `key` in a NUL-separated `KEY=VALUE` block, as `/proc/<pid>/environ` holds it.
fn environValue(block: []const u8, key: []const u8) ?[]const u8 {
    var rest = block;
    while (rest.len > 0) {
        const end = std.mem.indexOfScalar(u8, rest, 0) orelse rest.len;
        const entry = rest[0..end];
        if (entry.len > key.len and std.mem.startsWith(u8, entry, key) and entry[key.len] == '=') return entry[key.len + 1 ..];
        rest = rest[@min(end + 1, rest.len)..];
    }
    return null;
}

/// Keep ORing the counters into `shadow` until the process ends.
fn sampler(argument: ?*anyopaque) callconv(.c) ?*anyopaque {
    const interval: u32 = @intCast(@intFromPtr(argument));
    const delay: linux.timespec = .{ .sec = interval / 1000, .nsec = (interval % 1000) * 1_000_000 };
    while (true) {
        _ = linux.nanosleep(&delay, null);
        accumulate();
    }
}

/// OR every counter into the shadow bitmap, eight bytes at a time.
fn accumulate() void {
    const target = shadow orelse return;
    const start = counters_start orelse return;
    const stop = counters_stop orelse return;
    const count = stop - start;
    const words = count / 8;
    const source: [*]align(1) const u64 = @ptrCast(start);
    const sink: [*]align(1) u64 = @ptrCast(target);
    for (0..words) |index| sink[index] |= source[index];
    for (words * 8..count) |index| target[index] |= start[index];
}

/// Whether counter `index` ran, according to the shadow bitmap or the counter itself.
fn ran(start: [*]const u8, index: usize) bool {
    if (start[index] != 0) return true;
    const target = shadow orelse return false;
    return target[index] != 0;
}

/// Appends little-endian integers and LEB128 deltas to a buffer that is written
/// to `fd` whenever it fills.
const Sink = struct {
    fd: i32,
    len: usize = 0,
    failed: bool = false,
    buffer: [64 * 1024]u8 = undefined,

    fn put(sink: *Sink, bytes: []const u8) void {
        for (bytes) |byte| sink.putByte(byte);
    }
    fn putByte(sink: *Sink, byte: u8) void {
        if (sink.len == sink.buffer.len) sink.drain();
        sink.buffer[sink.len] = byte;
        sink.len += 1;
    }
    fn putInt(sink: *Sink, comptime T: type, value: T) void {
        var bytes: [@sizeOf(T)]u8 = undefined;
        std.mem.writeInt(T, &bytes, value, .little);
        sink.put(&bytes);
    }
    fn putLeb(sink: *Sink, value: u64) void {
        var rest = value;
        while (rest >= 0x80) : (rest >>= 7) sink.putByte(@as(u8, @truncate(rest)) | 0x80);
        sink.putByte(@truncate(rest));
    }
    fn drain(sink: *Sink) void {
        var done: usize = 0;
        while (done < sink.len) {
            const written = linux.write(sink.fd, sink.buffer[done..].ptr, sink.len - done);
            if (linux.errno(written) != .SUCCESS) {
                sink.failed = true;
                break;
            }
            done += written;
        }
        sink.len = 0;
    }
};

fn loadBias() u64 {
    const Search = struct {
        fn first(info: *std.c.dl_phdr_info, size: usize, data: ?*anyopaque) callconv(.c) c_int {
            _ = size;
            const out: *u64 = @ptrCast(@alignCast(data.?));
            out.* = info.addr;
            return 1;
        }
    };
    var bias: u64 = 0;
    _ = std.c.dl_iterate_phdr(&Search.first, &bias);
    return bias;
}

/// The build id found so far: its bytes, and its length (0 when there is none).
const IdSearch = struct {
    out: [build_id.max_length]u8 = undefined,
    len: usize = 0,
};

/// The `dl_iterate_phdr` callback of `buildIdOf`: the first object reported is the program itself.
fn findBuildId(info: *std.c.dl_phdr_info, size: usize, data: ?*anyopaque) callconv(.c) c_int {
    _ = size;
    const search: *IdSearch = @ptrCast(@alignCast(data.?));
    for (info.phdr[0..info.phnum]) |phdr| {
        if (@intFromEnum(phdr.type) != build_id.pt_note) continue;
        const notes = @as([*]const u8, @ptrFromInt(info.addr + phdr.vaddr))[0..phdr.memsz];
        search.len = build_id.noteBuildId(notes, &search.out);
        if (search.len != 0) break;
    }
    return 1;
}

/// The build id of this program; `len` is 0 when the program carries none.
fn buildIdOf() IdSearch {
    var search: IdSearch = .{};
    _ = std.c.dl_iterate_phdr(&findBuildId, &search);
    return search;
}

/// The exit hook: write this process's hit set, if a directory is configured.
fn flush() callconv(.c) void {
    if (record_dir_len == 0) return;
    const start = counters_start orelse return;
    const stop = counters_stop orelse return;
    const pcs = pcs_start orelse return;
    var path: [4096]u8 = undefined;
    const leaf = std.mem.printSentinel(&path, "{s}/{s}", .{ record_dir[0..record_dir_len], record_test[0..record_test_len] }, 0) catch return;
    makePath(leaf);
    const file = std.mem.printSentinel(path[leaf.len + 1 ..], "{s}/{d}.cov", .{ leaf, linux.getpid() }, 0) catch return;
    const opened = linux.open(file.ptr, .{ .ACCMODE = .WRONLY, .CREAT = true, .TRUNC = true, .CLOEXEC = true }, 0o644);
    if (linux.errno(opened) != .SUCCESS) return;
    var sink: Sink = .{ .fd = @intCast(opened) };
    const count = stop - start;
    var exe: [512]u8 = undefined;
    const exe_len = linux.readlink("/proc/self/exe", &exe, exe.len);
    const exe_text = if (linux.errno(exe_len) == .SUCCESS) exe[0..exe_len] else exe[0..0];
    const id = buildIdOf();
    accumulate();
    var hits: u32 = 0;
    var wrapped: u32 = 0;
    for (0..count) |index| {
        hits += @intFromBool(ran(start, index));
        wrapped += @intFromBool(start[index] == 0 and ran(start, index));
    }
    sink.put(magic);
    sink.putInt(u32, @intCast(count));
    sink.putInt(u32, hits);
    sink.putInt(u32, wrapped);
    sink.putInt(u64, loadBias());
    sink.putInt(u64, pcs[0]);
    sink.putInt(u16, @intCast(exe_text.len));
    sink.put(exe_text);
    sink.putInt(u8, @intCast(id.len));
    sink.put(id.out[0..id.len]);
    var previous: usize = 0;
    for (0..count) |index| {
        if (!ran(start, index)) continue;
        sink.putLeb(index - previous);
        previous = index;
    }
    previous = 0;
    for (0..count) |index| {
        if (start[index] != 0 or !ran(start, index)) continue;
        sink.putLeb(index - previous);
        previous = index;
    }
    sink.drain();
    _ = linux.close(@intCast(opened));
}

/// Create `path` and every missing directory above it.
fn makePath(path: [:0]u8) void {
    for (1..path.len) |index| {
        if (path[index] != '/') continue;
        path[index] = 0;
        _ = linux.mkdir(@as([*:0]const u8, @ptrCast(path.ptr)), 0o755);
        path[index] = '/';
    }
    _ = linux.mkdir(path.ptr, 0o755);
}
