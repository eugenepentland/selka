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

// spec: GENERIC-PROVIDER-1
test "generic externalValue and environmentValue enforce capability kinds and result shapes" {
    try reject("fn f<T:copy>(cap:random_cap)->R{return clock_now<R>(cap);}", "E_GENERIC_TYPE");
    try reject("fn f<T:copy>(cap:clock_cap)->Random{return clock_now<Random>(cap);}", "E_EXTERNAL_RESULT");
    try reject("fn f<T:copy>(cap:random_cap)->R{return random_u64<R>(cap);}", "E_EXTERNAL_RESULT");
    try reject("fn f<T:copy>(cap:environment_cap)->R{return environment_get<R>(cap,new [0]u8[]);}", "E_ENVIRONMENT_RESULT");
    try reject("fn f<T:copy>(cap:clock_cap)->Env{return environment_get<Env>(cap,new [0]u8[]);}", "E_GENERIC_TYPE");
    try reject("fn f<T:copy>(cap:environment_cap)->Env{return environment_get<Env>(cap,new [1]i64[1]);}", "E_ENVIRONMENT_NAME");
    try reject("fn f<T:copy>(cap:random_cap)->i64 effects(){_ = random_u64<Random>(cap);return 0;}", "E_EFFECT_BOUND");
    try reject("fn f<T:copy>(cap:environment_cap)->i64 effects(){_ = environment_get<Env>(cap,new [0]u8[]);return 0;}", "E_EFFECT_BOUND");
}

test "generic acquireResource and completeResource preserve kind byte request and ownership contracts" {
    try reject("fn f<T:copy>(cap:filesystem_cap)->R{return acquire_resource<R>(cap,new [0]u8[]);}", "E_RESOURCE_RESULT");
    try reject("fn f<T:copy>(cap:network_cap)->Open{return acquire_resource<Open>(cap,new [0]u8[]);}", "E_GENERIC_TYPE");
    try reject("fn f<T:copy>(cap:filesystem_cap)->Open{return acquire_resource<Open>(cap,0);}", "E_RESOURCE_REQUEST");
    try reject("fn f<T:copy>(file:File)->R{return complete_resource<R>(file);}", "E_COMPLETION_RESULT");
    try reject("fn f<T:copy>()->Finish{return complete_resource<Finish>(0);}", "E_GENERIC_TYPE");
    try reject("fn f<T:copy>(file:File)->Finish{_ = complete_resource<Finish>(file);return complete_resource<Finish>(file);}", "E_OWNED_CONSUMED");
    try reject("fn f<T:copy>(cap:filesystem_cap)->Open noio{return acquire_resource<Open>(cap,new [0]u8[]);}", "E_EFFECT_BOUND");
}

test "generic resourceIo checks mutation owner state byte values and fixed result payloads" {
    try reject("fn f<T:copy>(file:File)->Read{return read_resource<Read>(file);}", "E_IMMUTABLE");
    try reject("fn f<T:copy>(input:File)->Read{let mut file=input;_ = file;return read_resource<Read>(file);}", "E_OWNED_CONSUMED");
    try reject("fn f<T:copy>(input:File)->R{let mut file=input;return read_resource<R>(file);}", "E_RESOURCE_IO_RESULT");
    try reject("fn f<T:copy>(input:File)->Random{let mut file=input;return write_resource<Random>(file,1);}", "E_RESOURCE_BYTES");
    try reject("fn consume(file:File)->[0]u8{_ = file;return new [0]u8[];}fn f<T:copy>(input:File)->Random{let mut file=input;return write_resource<Random>(file,consume(file));}", "E_OWNED_CONSUMED");
}
