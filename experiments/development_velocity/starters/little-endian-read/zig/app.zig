const std=@import("std"); const s=@import("support.zig");
pub fn run(a:std.mem.Allocator, request:s.V)!s.V{
 try s.fields(request,&.{"hex","offsets"}); const h=s.get(request,"hex"); if(h!=.string or h.string.len>1024 or h.string.len%2!=0)return error.InvalidRequest;
 var bytes=try a.alloc(u8,h.string.len/2); for(bytes,0..) |*b,i| b=std.fmt.parseInt(u8,h.string[i*2..i*2+2],16) catch return error.InvalidRequest;
 const offsets=try s.array(s.get(request,"offsets"),128); for(offsets)|v|{const n=try s.integer(v,0,512);if(n+2>bytes.len){var e=s.object();try s.put(a,&e,"error",.{.string="out-of-bounds"});return e;}}
 var values=s.list(a); for(offsets)|v|{const n:@TypeOf(bytes.len)=@intCast(try s.integer(v,0,512));const x=std.mem.readInt(u16,bytes[n..][0..2],.big);try values.array.append(.{.integer=x});}
 var out=s.object();try s.put(a,&out,"values",values);return out;
}
