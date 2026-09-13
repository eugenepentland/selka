//! Partial field availability is checked before generic instantiation.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const schema = "result R{ok:i64,err:i64}struct Pair{left:R,right:R,code:i64}";
fn reject(body: []const u8, code: []const u8) !void {
    const bytes = try std.mem.concat(t.allocator, u8, &.{ schema, body, "fn main()->i64{return 0;}" });
    defer t.allocator.free(bytes);
    var c = try language.Compilation.init(t.allocator, "generic-fields-invalid.my", bytes);
    defer c.deinit();
    try t.expectError(error.SourceError, c.check());
    try t.expectEqualStrings(code, c.diagnostics.items[0].code);
}
// spec: GENERIC-FIELD-1
test "generic field access rejects copied results repeated moves and incomplete whole values" {
    try reject("fn f<T:copy>(p:Pair)->R{return read_field(p,left);}", "E_FIELD_COPY");
    try reject("fn f<T:copy>(p:Pair)->R{acknowledge take_field(p,left);return take_field(p,left);}", "E_FIELD_MOVED");
    try reject("fn f<T:copy>(p:Pair)->i64{discard take_field(p,code);return read_field(p,code);}", "E_FIELD_MOVED");
    try reject("fn f<T:copy>(p:Pair)->Pair{acknowledge take_field(p,left);return p;}", "E_PARTIAL_MOVE");
    try reject("fn f<T:copy>(p:Pair)->i64{acknowledge take_field(p,left);acknowledge p;return 0;}", "E_PARTIAL_MOVE");
    try reject("fn f<T:copy>(p:Pair)->i64{acknowledge p;return read_field(p,code);}", "E_OWNED_CONSUMED");
    try reject("fn f<T:copy>(p:Pair)->i64{acknowledge take_field(p,left);return read_field(p,code);}", "E_RESULT_UNHANDLED");
    try reject("fn f<T:copy>(p:Pair)->i64{discard take_field(p,left);return 0;}", "E_RESULT_DISCARD");
}
test "generic partial moves enforce concrete record shapes and value binding access" {
    try reject("struct Data{n:i64}fn f<T:copy>(p:Data)->i64{return take_field(p,n);}", "E_FIELD_TAKE");
    var c = try language.Compilation.init(t.allocator, "reference-field.my", "struct Data{n:i64}fn f<T:copy>(p:&Data)->i64{return read_field(p,n);}" ++
        "fn main()->i64{let data=new Data{n:7};borrow data as view{return f::<i64>(view);}}");
    defer c.deinit();
    try t.expectEqual(@as(i64, 7), (try c.execute(t.allocator)).value);
    try reject("fn f<T:copy>(p:T)->i64{return read_field(p,n);}", "E_GENERIC_BODY_UNSUPPORTED");
    try reject("fn f<T:copy>(p:[1]R)->R{return take_field(p,left);}", "E_TYPE");
    try reject("fn f<T:copy>(p:Pair)->R{return take_field(p,missing);}", "E_UNKNOWN_FIELD");
}
test "generic field snapshots distinguish which field moved on continuing paths" {
    try reject("fn f<T:copy>(flag:bool,p:Pair)->i64{if flag{acknowledge take_field(p,left);}else{acknowledge take_field(p,right);}return 0;}", "E_RESULT_PATH");
    try reject("fn f<T:copy>(p:Pair)->i64{while false{acknowledge take_field(p,left);}return 0;}", "E_RESULT_LOOP");
    try reject("fn consume(r:R)->bool{acknowledge r;return true;}fn f<T:copy>(p:Pair)->i64{discard false&&consume(take_field(p,left));return 0;}", "E_RESULT_PATH");
    try reject("enum E{a,b}fn f<T:copy>(e:E,p:Pair)->i64{match e{E.a=>{acknowledge take_field(p,left);},E.b=>{acknowledge take_field(p,right);}}return 0;}", "E_RESULT_PATH");
}
test "generic partial replacement and propagation retain remaining obligations" {
    try reject("fn f<T:copy>(original:Pair)->i64{let mut p=original;acknowledge take_field(p,left);p=new Pair{left:new R.ok(1),right:new R.ok(2),code:0};return 0;}", "E_RESULT_OVERWRITE");
    try reject("fn f<T:copy>(p:Pair)->R{return new R.ok(try take_field(p,left));}", "E_RESULT_UNHANDLED");
    try reject("fn consume(r:R,n:i64)->i64{acknowledge r;return n;}fn f<T:copy>(p:Pair)->R{return new R.ok(consume(take_field(p,left),try take_field(p,right)));}", "E_RESULT_PROPAGATION");
}
const program = schema ++
    "fn drain<T:copy>(flag:bool,p:Pair)->i64{if flag{acknowledge take_field(p,left);acknowledge take_field(p,right);}else{acknowledge take_field(p,right);acknowledge take_field(p,left);}return read_field(p,code);}" ++
    "fn step<T:copy>(p:Pair)->R{acknowledge take_field(p,left);let n=try take_field(p,right);return new R.ok(n+read_field(p,code));}" ++
    "fn number(r:R)->i64{match r{R.ok(n)=>{return n;},R.err(n)=>{return 0-n;}}}" ++
    "fn refill<T:copy>()->i64{let mut n=0;let mut p=new Pair{left:new R.ok(1),right:new R.err(2),code:3};" ++
    "while n<2{acknowledge take_field(p,left);acknowledge take_field(p,right);p=new Pair{left:new R.ok(n),right:new R.ok(n)," ++
    "code:n};n+=1;}acknowledge take_field(p,left);acknowledge take_field(p,right);return read_field(p,code);}" ++
    "fn main()->i64{return drain::<bool>(true,new Pair{left:new R.ok(1),right:new R.ok(2),code:3})+drain::<bool>(false," ++
    "new Pair{left:new R.ok(1),right:new R.ok(2),code:4})+number(step::<bool>(new Pair{left:new R.ok(1),right:new R.ok(5)," ++
    "code:6}))+number(step::<bool>(new Pair{left:new R.ok(1),right:new R.err(2),code:6}))+refill::<bool>();}";
fn scenario(allocator: std.mem.Allocator) !void {
    var c = try language.Compilation.init(allocator, "generic-fields.my", program);
    defer c.deinit();
    try t.expectEqual(@as(i64, 17), (try c.execute(allocator)).value);
}
test "generic fieldValue snapshots scopes replenishment and propagation survive allocation failures" {
    try scenario(t.allocator);
    var stable = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(stable.allocator(), scenario, .{});
}
test "generic partial nested records and returning match arms preserve remaining fields" {
    const bytes = schema ++ "struct Outer{p:Pair,code:i64}enum E{a,b}" ++
        "fn f<T:copy>(e:E,outer:Outer)->i64{let p=take_field(outer,p);match e{E.a=>{acknowledge take_field(p,left);" ++
        "acknowledge take_field(p,right);return read_field(outer,code);},E.b=>{}}acknowledge take_field(p,right);" ++
        "acknowledge take_field(p,left);return read_field(p,code);}" ++
        "fn main()->i64{return f::<bool>(new E.a,new Outer{p:new Pair{left:new R.ok(1),right:new R.ok(2),code:3},code:4})+f::<bool>(new E.b,new Outer{p:new Pair{left:new R.ok(1),right:new R.ok(2),code:3},code:4});}";
    var c = try language.Compilation.init(t.allocator, "nested-fields.my", bytes);
    defer c.deinit();
    try t.expectEqual(@as(i64, 7), (try c.execute(t.allocator)).value);
}
