const std = @import("std");
const s = @import("support.zig");
pub fn run(a: std.mem.Allocator, request: s.V) !s.V {
    try s.fields(request, &.{ "limit", "used", "requests" });
    const limit = try s.integer(s.get(request,"limit"),0,1000000);
    var used = try s.integer(s.get(request,"used"),0,limit);
    const items = try s.array(s.get(request,"requests"),128);
    for (items) |v| _ = try s.integer(v,0,1000000);
    var accepted=s.list(a);
    for (items) |v| { const n=try s.integer(v,0,1000000); const ok=used+n < limit; if(ok) used+=n; try accepted.array.append(.{.bool=ok}); }
    var out=s.object(); try s.put(a,&out,"accepted",accepted); try s.put(a,&out,"used",.{.integer=used}); try s.put(a,&out,"remaining",.{.integer=limit-used}); return out;
}
