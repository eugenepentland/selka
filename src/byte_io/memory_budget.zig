//! Runtime byte budgets exclude source compilation and input transport storage.
const std = @import("std");
const Memory = @import("mylang").allocation_budget.Memory;
/// Independent VM/host quotas also charge the shared total budget.
pub const Config = struct {
    total: usize = std.math.maxInt(usize),
    vm: usize = std.math.maxInt(usize),
    host: usize = std.math.maxInt(usize),
    output: bool = false,
    seen: u8 = 0,
    /// Parse unique memory options. Zero permits no nonempty allocation.
    pub fn parse(self: *Config, argument: []const u8) error{InvalidArguments}!bool {
        if (std.mem.eql(u8, argument, "--memory-report")) {
            if (self.output) return error.InvalidArguments;
            self.output = true;
            return true;
        }
        const names = [_][]const u8{ "--max-runtime-bytes=", "--max-vm-bytes=", "--max-host-bytes=" };
        for (names, 0..) |name, index| {
            if (!std.mem.startsWith(u8, argument, name)) continue;
            const bit = @as(u8, 1) << @as(u3, @intCast(index));
            if (self.seen & bit != 0) return error.InvalidArguments;
            const digits = argument[name.len..];
            if (digits.len == 0) return error.InvalidArguments;
            for (digits) |digit| if (digit < '0' or digit > '9') return error.InvalidArguments;
            const value = std.fmt.parseInt(usize, digits, 10) catch return error.InvalidArguments;
            self.seen |= bit;
            switch (index) {
                0 => self.total = value,
                1 => self.vm = value,
                2 => self.host = value,
                else => unreachable,
            }
            return true;
        }
        return false;
    }
};
fn statistic(budget: Memory) struct { limit: usize, live: usize, peak: usize } {
    return .{ .limit = budget.limit, .live = budget.live, .peak = budget.peak };
}
/// Subcategories share the VM parent budget; logical capacity counts slots, not bytes.
pub const Observations = struct {
    backing: Memory,
    bookkeeping: Memory,
};
/// Emit best-effort accounting after resource cleanup without allocating memory.
pub fn report(io: std.Io, config: Config, total: Memory, vm: Memory, host: Memory, observations: Observations) void {
    if (!config.output) return;
    var buffer: [2048]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    std.json.Stringify.value(.{
        .version = "runtime-memory-v1",
        .scope = "requested-live-bytes-excluding-source-input-and-allocator-overhead",
        .total = statistic(total),
        .vm = statistic(vm),
        .host = statistic(host),
        .vm_categories = .{ .guest_backing = statistic(observations.backing), .bookkeeping_and_snapshots = statistic(observations.bookkeeping) },
    }, .{}, &writer) catch return;
    writer.writeByte('\n') catch return;
    std.Io.File.stderr().writeStreamingAll(io, writer.buffered()) catch return;
}
