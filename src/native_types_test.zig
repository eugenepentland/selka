//! Frontend-driven stable native type catalog regressions.
const std = @import("std");
const Catalog = @import("native_types.zig").Catalog;
test "frontend generic names and layouts survive source declaration reorder" {
    const compiler = @import("compiler.zig");
    var first = try compiler.Compilation.init(std.testing.allocator, "types.my", "struct Box<T:copy>{value:T} struct Noise{x:u8} fn main()->i64{let b=new Box<i64>{value:7};return b.value;}");
    defer first.deinit();
    try first.check();
    var second = try compiler.Compilation.init(std.testing.allocator, "types.my", "struct Noise{x:u8} struct Box<T:copy>{value:T} fn main()->i64{let b=new Box<i64>{value:7};return b.value;}");
    defer second.deinit();
    try second.check();
    var a = try Catalog.initRecords(std.testing.allocator, first.program.?.records);
    defer a.deinit();
    var b = try Catalog.initRecords(std.testing.allocator, second.program.?.records);
    defer b.deinit();
    var found = false;
    for (a.records) |record| {
        if (!std.mem.startsWith(u8, record.name, "Box<")) continue;
        for (b.records) |other| {
            if (!std.mem.eql(u8, record.name, other.name)) continue;
            try std.testing.expectEqualSlices(u8, &(try a.layout(record.id)).hash, &(try b.layout(other.id)).hash);
            found = true;
        }
    }
    try std.testing.expect(found);
}
