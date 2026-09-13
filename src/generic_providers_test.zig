//! Provider contracts must hold even for uncalled generic templates.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const schema = "result R{ok:i64,err:i64}result Random{ok:u64,err:i64}resource File:filesystem;result Open{ok:File,err:i64}" ++
    "struct Failure{resource:File,code:i64}result Finish{ok:bool,err:Failure}struct Chunk{bytes:[4]u8,length:u64,eof:bool}" ++
    "result Read{ok:Chunk,err:i64}struct Progress{length:u64,eof:bool}result Slice{ok:Progress,err:i64}" ++
    "struct Entry{bytes:[4]u8,length:u64,present:bool}result Env{ok:Entry,err:i64}";
fn reject(body: []const u8, code: []const u8) !void {
    const bytes = try std.mem.concat(t.allocator, u8, &.{ schema, body, "fn main()->i64{return 0;}" });
    defer t.allocator.free(bytes);
    var c = try language.Compilation.init(t.allocator, "generic-provider-invalid.my", bytes);
    defer c.deinit();
    try t.expectError(error.SourceError, c.check());
    try t.expectEqualStrings(code, c.diagnostics.items[0].code);
}
