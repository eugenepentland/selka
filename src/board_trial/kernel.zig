//! Bounded rectangle kernel shared by the native wrapper and standalone Zig baseline.
const m = @import("model.zig");
/// Exact intersection or a declared service failure.
pub const Result = union(enum) { ok: bool, err: m.GeometryFailure };
/// Per-observation callback count and deterministic unavailability injection.
pub const Kernel = struct {
    calls: u64 = 0,
    unavailable: bool = false,
    /// Count every requested operation, returning typed failure before unsafe arithmetic.
    pub fn intersect(self: *Kernel, a: m.Rect, b: m.Rect) Result {
        self.calls += 1;
        if (!m.valid(a) or !m.valid(b)) return .{ .err = .invalid_bounds };
        if (self.unavailable) return .{ .err = .unavailable };
        return .{ .ok = overlap(a.x, a.width, b.x, b.width) and overlap(a.y, a.height, b.y, b.height) };
    }
};
fn overlap(a: m.Micrometres, aw: m.Micrometres, b: m.Micrometres, bw: m.Micrometres) bool {
    return @backingInt(a) < @backingInt(b) + @backingInt(bw) and @backingInt(b) < @backingInt(a) + @backingInt(aw);
}
