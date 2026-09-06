//! Concrete schemas remain nominal while unrelated generic arguments stay symbolic.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const schema = "struct Sample{values:[2]i64,tag:u8}";
const program = schema ++
    "fn make<T:integer>(x:T)->Sample{return new Sample{values:new [2]i64[cast<i64>(x),cast<i64>(x)+1],tag:7u8};}" ++
    "fn total<T:copy>(x:T,s:Sample)->i64{discard x;return s.values[0]+s.values[1]+cast<i64>(len(s.values));}" ++
    "fn choose<T:copy>(x:T,a:Sample,b:Sample)->Sample{discard x;if a.tag==b.tag{return a;}return b;}" ++
    "fn main()->i64{let p=make::<u8>(7u8);return total::<bool>(true,choose::<i64>(0,p,p));}";
fn scenario(allocator: std.mem.Allocator) !void {
    var c = try language.Compilation.init(allocator, "concrete.my", program);
    defer c.deinit();
    try t.expectEqual(@as(i64, 17), (try c.execute(allocator)).value);
    const native = try c.emitC(allocator);
    defer allocator.free(native);
}
// spec: GENERIC-CONCRETE-1
test "generic concrete records and arrays retain checked shapes under allocation failures" {
    try scenario(t.allocator);
    var stable = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(stable.allocator(), scenario, .{});
}
fn reject(bytes: []const u8, expected: []const u8) !void {
    var c = try language.Compilation.init(t.allocator, "invalid.my", bytes);
    defer c.deinit();
    try t.expectError(error.SourceError, c.check());
    try t.expectEqualStrings(expected, c.diagnostics.items[0].code);
}
test "generic concrete shapes reject mismatched nominal values and malformed constructors before instantiation" {
    try reject("struct A{n:i64}struct B{n:i64}fn f<T:copy>(x:A)->B{return x;}fn main()->i64{return 0;}", "E_GENERIC_TYPE");
    try reject("struct A{n:i64}fn f<T:copy>(x:T)->A{discard x;return new A{};}fn main()->i64{return 0;}", "E_MISSING_FIELD");
    try reject("struct A{n:i64}fn f<T:copy>(x:T)->A{discard x;return new A{n:1,n:2};}fn main()->i64{return 0;}", "E_DUPLICATE_FIELD");
    try reject("struct A{n:i64}fn f<T:copy>(x:A)->i64{return x.other;}fn main()->i64{return 0;}", "E_UNKNOWN_FIELD");
    try reject("fn f<T:copy>(x:T)->[2]i64{discard x;return new [2]i64[1];}fn main()->i64{return 0;}", "E_ARRAY_LENGTH");
    try reject("fn f<T:copy>(x:[2]i64)->i64{return x[true];}fn main()->i64{return 0;}", "E_GENERIC_OPERATION");
    try reject("fn f<T:copy>(x:T)->i64{return x.n;}fn main()->i64{return 0;}", "E_GENERIC_BODY_UNSUPPORTED");
}
test "generic concreteType signatures preserve result and runtime ownership exclusions" {
    var c = try language.Compilation.init(t.allocator, "domain.my", "domain D:i64{fn make(x:i64)->D{return wrap<D>(x);}fn number(x:D)->i64{return unwrap(x);}}" ++
        "fn preserve<T:copy>(context:T,value:D)->D{discard context;return value;}fn main()->i64{return D.number(preserve::<bool>(true,D.make(7)));}");
    defer c.deinit();
    try t.expectEqual(@as(i64, 7), (try c.execute(t.allocator)).value);
    try reject("result R{ok:i64,err:i64}fn f<T:copy>(x:R)->i64{return 0;}fn main()->i64{return 0;}", "E_GENERIC_BODY_UNSUPPORTED");
    try reject("buffer B:u8;struct Outer{inner:B}fn g<T:copy>(x:Outer)->i64{return 0;}fn main()->i64{return 0;}", "E_GENERIC_BODY_UNSUPPORTED");
    try reject("buffer B:u8;fn f<T:copy>(x:B)->i64{return 0;}fn main()->i64{return 0;}", "E_GENERIC_BODY_UNSUPPORTED");
    try reject("domain D:i64{}fn f<T:copy>(x:D)->i64{return x+1;}fn main()->i64{return 0;}", "E_GENERIC_TYPE");
}
