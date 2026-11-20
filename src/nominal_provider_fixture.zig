//! Deterministic resource provider for symbolic nominal contract acceptance.
const std = @import("std");
const resources = @import("external_resources.zig");
const external = @import("external_capabilities.zig");
/// Named fields are deliberately reordered to test semantic contract matching.
pub const declarations =
    \\resource File: filesystem
    \\
    \\
    \\result Open[T]:
    \\    err: i64,
    \\    ok: File
    \\
    \\
    \\record Failure[T]:
    \\    code: i64
    \\    resource: File
    \\
    \\
    \\result Finish[T]:
    \\    err: Failure[T],
    \\    ok: bool
    \\
    \\
    \\record Chunk[T]:
    \\    eof: bool
    \\    bytes: FixedArray[u8, 4]
    \\    length: u64
    \\
    \\
    \\result Read[T]:
    \\    err: i64,
    \\    ok: Chunk[T]
    \\
    \\
    \\result Written[T]:
    \\    err: i64,
    \\    ok: u64
    \\
    \\
    \\result Status[T]:
    \\    ok: i64,
    \\    err: i64
    \\
    \\
    \\func singleton[T](x: T) -> FixedArray[T, 1]:
    \\    return FixedArray[T, 1]([x])
    \\
    \\
    \\
;
/// Observable ownership and callback accounting, including failed completion retries.
pub const Counts = struct { acquired: usize = 0, live: usize = 0, completed: usize = 0, released: usize = 0, completions: usize = 0, reads: usize = 0, writes: usize = 0 };
/// Host functions check exact requests and record every byte supplied by the guest.
pub const Fake = struct {
    counts: Counts = .{},
    fail_completion: bool = true,
    failure: ?external.CallError = null,
    written: [8]u8 = @splat(0),
    written_length: usize = 0,
    fn acquire(context: *anyopaque, request: []const u8, _: resources.Permissions) external.CallError!u64 {
        const self: *Fake = @ptrCast(@alignCast(context));
        if (!std.mem.eql(u8, request, &.{42})) return error.Denied;
        self.counts.acquired += 1;
        self.counts.live += 1;
        return self.counts.acquired;
    }
    fn read(context: *anyopaque, _: u64, output: []u8) external.CallError!resources.Read {
        const self: *Fake = @ptrCast(@alignCast(context));
        self.counts.reads += 1;
        @memset(output, 99);
        if (self.failure) |err| return err;
        const length = @min(2, output.len);
        for (output[0..length], 0..) |*byte, index| byte.* = @intCast(7 + index);
        return .{ .length = length, .eof = true };
    }
    fn write(context: *anyopaque, _: u64, input: []const u8) external.CallError!usize {
        const self: *Fake = @ptrCast(@alignCast(context));
        self.counts.writes += 1;
        if (self.failure) |err| return err;
        if (input.len > self.written.len - self.written_length) return error.Failed;
        @memcpy(self.written[self.written_length..][0..input.len], input);
        self.written_length += input.len;
        return input.len;
    }
    fn complete(context: *anyopaque, _: u64) external.CallError!void {
        const self: *Fake = @ptrCast(@alignCast(context));
        self.counts.completions += 1;
        if (self.fail_completion) {
            self.fail_completion = false;
            return error.Failed;
        }
        self.counts.completed += 1;
        self.counts.live -= 1;
    }
    fn release(context: *anyopaque, _: u64) void {
        const self: *Fake = @ptrCast(@alignCast(context));
        self.counts.released += 1;
        self.counts.live -= 1;
    }
    /// Bind this fixture's state to the ordinary typed resource interface.
    pub fn provider(self: *Fake) resources.Provider {
        return .{ .context = self, .acquire = acquire, .read = read, .write = write, .complete = complete, .release = release };
    }
};
