//! Result obligations in uninstantiated templates and their executable specializations.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const schema = "result R{ok:i64,err:i64}";
fn reject(body: []const u8, code: []const u8) !void {
    const bytes = try std.mem.concat(t.allocator, u8, &.{ schema, body, "fn main()->i64{return 0;}" });
    defer t.allocator.free(bytes);
    var c = try language.Compilation.init(t.allocator, "generic-result-invalid.my", bytes);
    defer c.deinit();
    try t.expectError(error.SourceError, c.check());
    try t.expectEqualStrings(code, c.diagnostics.items[0].code);
}
fn run(bytes: []const u8, expected: i64) !void {
    var c = try language.Compilation.init(t.allocator, "generic-result.my", bytes);
    defer c.deinit();
    try t.expectEqual(expected, (try c.execute(t.allocator)).value);
}
// spec: GENERIC-RESULT-1
test "uncalled generic templates cannot drop duplicate discard or overwrite results" {
    try reject("fn f<T:copy>(r:R)->i64{return 0;}", "E_RESULT_UNHANDLED");
    try reject("fn f<T:copy>()->i64{{let r=new R.ok(1);}return 0;}", "E_RESULT_UNHANDLED");
    try reject("fn f<T:copy>(r:R)->i64{let moved=r;acknowledge r;acknowledge moved;return 0;}", "E_RESULT_CONSUMED");
    try reject("fn f<T:copy>(r:R)->i64{discard r;return 0;}", "E_RESULT_DISCARD");
    try reject("fn f<T:copy>(r:&R)->&R from r{return r;}", "E_RESULT_BORROW");
    try reject("fn f<T:copy>(r:R)->i64{borrow r as view{}acknowledge r;return 0;}", "E_RESULT_BORROW");
    try reject("fn f<T:copy>()->i64{acknowledge 1;return 0;}", "E_ACKNOWLEDGE_TYPE");
    try reject("fn f<T:copy>()->i64{let mut r=new R.ok(1);r=new R.err(2);acknowledge r;return 0;}", "E_RESULT_OVERWRITE");
}
test "generic branches restore result state and merge only continuing paths" {
    try reject("fn f<T:copy>(flag:bool,r:R)->i64{if flag{acknowledge r;}return 0;}", "E_RESULT_PATH");
    try reject("fn f<T:copy>(flag:bool,r:R)->i64{if flag{return 0;}acknowledge r;return 1;}", "E_RESULT_UNHANDLED");
    try run(schema ++ "fn f<T:copy>(flag:bool,r:R)->i64{if flag{acknowledge r;return 1;}acknowledge r;return 2;}fn main()->i64{return f::<bool>(true,new R.err(3))+f::<bool>(false,new R.ok(4));}", 3);
    try run(schema ++ "fn f<T:copy>(flag:bool,r:R)->i64{if flag{acknowledge r;}else{acknowledge r;}return 7;}fn main()->i64{return f::<bool>(true,new R.err(3))+f::<bool>(false,new R.ok(4));}", 14);
}
test "generic loops and skipped boolean operands preserve obligations" {
    try reject("fn f<T:copy>(r:R)->i64{while false{acknowledge r;}return 0;}", "E_RESULT_LOOP");
    try reject("fn consume(r:R)->bool{acknowledge r;return false;}fn f<T:copy>(r:R)->i64{while consume(r){}return 0;}", "E_RESULT_LOOP");
    try reject("fn consume(r:R)->bool{acknowledge r;return true;}fn f<T:copy>(r:R)->i64{discard false&&consume(r);return 0;}", "E_RESULT_PATH");
    try reject("fn consume(r:R)->bool{acknowledge r;return true;}fn f<T:copy>(r:R)->i64{discard true||consume(r);return 0;}", "E_RESULT_PATH");
    try run(schema ++ "fn f<T:copy>()->i64{let mut n=0;let mut r=new R.ok(0);while n<3{acknowledge r;r=new R.err(n);n+=1;}r=r;acknowledge r;return n;}fn main()->i64{return f::<bool>();}", 3);
}
test "generic matches transfer nested payloads and merge outer obligations" {
    try reject("enum E{a,b}fn f<T:copy>(e:E,r:R)->i64{match e{E.a=>{acknowledge r;},E.b=>{}}return 0;}", "E_RESULT_PATH");
    try reject("union U{a:R,b}fn f<T:copy>(u:U)->i64{match u{U.a(discard)=>{},U.b=>{}}return 0;}", "E_RESULT_DISCARD");
    try reject("union U{a:R,b}fn f<T:copy>(u:U)->i64{match u{U.a(r)=>{},U.b=>{}}return 0;}", "E_RESULT_UNHANDLED");
    try run(schema ++ "enum E{a,b}fn f<T:copy>(e:E,r:R)->i64{match e{E.a=>{acknowledge r;return 1;},E.b=>{}}acknowledge r;return 2;}fn main()->i64{return f::<bool>(new E.a,new R.err(3))+f::<bool>(new E.b,new R.ok(4));}", 3);
}
test "generic aggregate operations preserve nested result obligations" {
    try reject("struct Box{r:R,n:i64}fn f<T:copy>(b:Box)->i64{return b.n;}", "E_RESULT_OPERATION");
    try reject("fn f<T:copy>(a:[2]R)->R{return a[0];}", "E_RESULT_OPERATION");
    try reject("fn f<T:copy>(a:[1]R)->u64{return len(a);}", "E_RESULT_OPERATION");
    try reject("fn f<T:copy>(a:[1]R)->[1]R{return replace(a,0,new R.ok(1));}", "E_RESULT_OPERATION");
    try reject("struct Box{r:R}fn f<T:copy>(b:Box)->Box{return update(b){r:new R.ok(1)};}", "E_RESULT_OPERATION");
    try run(schema ++ "struct Box{r:R,n:i64}fn f<T:copy>(r:R)->R{let b=new Box{r:r,n:1};let changed=update(b){n:2};return changed.r;}fn main()->i64{match f::<bool>(new R.ok(9)){R.ok(n)=>{return n;},R.err(discard)=>{return 0;}}}", 9);
}
const scenario_source = schema ++
    "fn step<T:copy>(r:R)->R{return new R.ok((try r)+1);}" ++
    "fn consume(r:R)->bool{acknowledge r;return true;}" ++
    "fn flow<T:copy>(flag:bool,r:R)->i64{if flag{acknowledge r;return 1;}acknowledge r;let mut n=0;" ++
    "let mut item=new R.ok(0);while n<3{acknowledge item;item=new R.err(n);n+=1;}acknowledge item;" ++
    "discard false&&consume(new R.err(1));return n;}" ++
    "fn main()->i64{let n=flow::<bool>(true,new R.ok(1))+flow::<bool>(false,new R.err(2));match step::<bool>(new R.ok(4)){R.ok(value)=>{return value+n;},R.err(discard)=>{return 0;}}}";
const nested_source = schema ++ "union U{a:R,b}fn make<T:integer>(n:T)->R{return new R.ok(cast<i64>(n));" ++
    "}fn take<T:copy>(u:U)->i64{match u{U.a(r)=>{match r{R.ok(n)=>{return n;},R.err(n)=>{return 0-n;" ++
    "}}},U.b=>{return 0;}}}fn main()->i64{return take::<bool>(new U.a(make::<u8>(7u8)))+take::<bool>(new U.a(new R." ++
    "err(2)))+take::<bool>(new U.b);}";
fn allocationScenario(allocator: std.mem.Allocator) !void {
    var c = try language.Compilation.init(allocator, "generic-results.my", scenario_source);
    defer c.deinit();
    try t.expectEqual(@as(i64, 9), (try c.execute(allocator)).value);
}
test "generic result construction nested matching and native emission survive allocation failures" {
    try run(nested_source, 5);
    try allocationScenario(t.allocator);
    var stable = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(stable.allocator(), allocationScenario, .{});
}
test "generic acknowledgement retains operand traps" {
    var c = try language.Compilation.init(t.allocator, "generic-result-trap.my", schema ++ "fn f<T:integer>(n:T)->i64{acknowledge new R.err(7/cast<i64>(n));return 0;}fn main()->i64{return f::<u8>(0u8);}");
    defer c.deinit();
    try t.expectEqualStrings("R_DIVISION_BY_ZERO", (try c.execute(t.allocator)).trap.code);
}

test "generic propagation rejects live bindings and earlier evaluated result temporaries" {
    try reject("fn f<T:copy>(r:R,pending:R)->R{return new R.ok(try r);}", "E_RESULT_UNHANDLED");
    try reject("fn consume(r:R,n:i64)->i64{acknowledge r;return n;}fn f<T:copy>(r:R)->R{return new R.ok(consume(new R.ok(1),try r));}", "E_RESULT_PROPAGATION");
    try reject("struct Pair{first:R,second:i64}fn f<T:copy>(r:R)->R{acknowledge new Pair{first:new R.ok(1),second:try r};return new R.ok(0);}", "E_RESULT_PROPAGATION");
    try reject("fn f<T:copy>(r:R)->R{acknowledge new [2]R[new R.ok(1),new R.ok(try r)];return new R.ok(0);}", "E_RESULT_PROPAGATION");
    try reject("fn f<T:copy>(r:R)->i64{return try r;}", "E_TRY_RETURN");
    try reject("fn f<T:copy>()->R{return new R.ok(try 1);}", "E_TRY_TYPE");
    try reject("result S{ok:i64,err:bool}fn f<T:copy>(r:S)->R{return new R.ok(try r);}", "E_GENERIC_TYPE");
}
test "generic propagation executes success error and nested result paths" {
    try run(schema ++ "fn f<T:copy>(r:R)->R{return new R.ok((try r)+1);}fn number<T:copy>(r:R)->i64{match r{R.ok(n)=>{return n;" ++
        "},R.err(n)=>{return 0-n;}}}fn main()->i64{return number::<bool>(f::<bool>(new R.ok(7)))+number::<bool>(f::<boo" ++
        "l>(new R.err(3)));}", 5);
    try run(schema ++ "result Nested{ok:R,err:i64}fn f<T:copy>(r:Nested)->R{let inner=try r;return inner;}fn main()->i64{match f::<bool>(new Nested.ok(new R.ok(9))){R.ok(n)=>{return n;},R.err(discard)=>{return 0;}}}", 9);
    try run(schema ++ "fn consume(r:R,n:i64)->i64{acknowledge r;return n;}fn f<T:copy>(r:R)->R{let n=consume(new R.ok(1),2);" ++
        "return new R.ok(n+(try r));}fn main()->i64{match f::<bool>(new R.ok(7)){R.ok(n)=>{return n;" ++
        "},R.err(discard)=>{return 0;}}}", 9);
}
