//! Structural contracts are checked independently of specialization.
const std = @import("std");
const t = std.testing;
const print = std.debug.print;
const language = @import("compiler.zig");
fn run(bytes: []const u8, expected: i64) !void {
    var c = try language.Compilation.init(t.allocator, "structural.my", bytes);
    defer c.deinit();
    const result = c.execute(t.allocator) catch |err| {
        for (c.diagnostics.items) |diag| print("{s}: {s} ({s})\n", .{ diag.code, diag.message, c.src.text(diag.span) });
        return err;
    };
    try t.expectEqual(expected, result.value);
}
fn reject(bytes: []const u8, code: []const u8) !void {
    var c = try language.Compilation.init(t.allocator, "structural-invalid.my", bytes);
    defer c.deinit();
    try t.expectError(error.SourceError, c.check());
    try t.expectEqualStrings(code, c.diagnostics.items[0].code);
}
// spec: STRUCTURAL-FIELD-1
test "structural fields execute multiple nominal record shapes and forwarding" {
    try run("struct A{value:i64}struct B{tag:bool,value:i64}fn get<T:copy+field(value:i64)>(v:T)->i64{return v.value;}fn forward<U:copy+field(v" ++
        "alue:i64)>(v:U)->i64{return get::<U>(v);}fn main()->i64{return get::<A>(new A{value:2})+forward::<B>(new B{tag:true,value:3});}", 5);
}
// spec: STRUCTURAL-OP-1
test "structural public domain operations execute with explicit type owned dispatch" {
    try run("domain D:i64{fn make(n:i64)->D{return wrap<D>(n);}fn score(v:D)->i64 effects(){return unwrap(v);}}fn apply<T:copy+op(score(v:T)->i64 effects())>(v:T)->i64{return T.score(v);}fn main()->i64{return apply::<D>(D.make(7));}", 7);
}
// spec: STRUCTURAL-LIMIT-1
test "structural declarations reject uncalled invalid access and incomplete construction" {
    try reject("fn f<T:copy+field(value:i64)>(v:T)->bool{return v.value;}fn main()->i64{return 0;}", "E_GENERIC_TYPE");
    try reject("fn f<T:copy+field(value:i64)>()->T{return new T{value:1};}fn main()->i64{return 0;}", "E_GENERIC_BODY_UNSUPPORTED");
    try reject("fn f<T:copy>(v:T)->i64{return T.score(v);}fn main()->i64{return 0;}", "E_GENERIC_REQUIREMENT");
}

test "structural fields reject incomplete forwarding unknown fields and hidden obligations" {
    try reject("fn get<T:copy+field(value:i64)>(v:T)->i64{return v.value;}fn forward<U:copy>(v:U)->i64{return get::<U>(v);}fn main()->i64{return 0;}", "E_GENERIC_BODY_UNSUPPORTED");
    try reject("fn get<T:copy+field(value:i64)>(v:T)->i64{return v.hidden;}fn main()->i64{return 0;}", "E_UNKNOWN_FIELD");
    try reject("result R{ok:i64,err:i64}fn get<T:copy+field(value:R)>(v:T)->i64{return 0;}fn main()->i64{return 0;}", "E_GENERIC_REQUIREMENT");
    try reject("struct Box<T:copy+field(value:i64)>{item:T}fn main()->i64{return 0;}", "E_GENERIC_REQUIREMENT");
    try reject("fn f<T:copy+field(value:i64)+field(value:i64)>(v:T)->i64{return 0;}fn main()->i64{return 0;}", "E_GENERIC_REQUIREMENT");
    try reject("fn f<T:copy+op(score(v:T)->i64)>(v:T)->i64{return 0;}fn main()->i64{return 0;}", "E_GENERIC_REQUIREMENT");
}
const domain = "domain D:i64{fn make(n:i64)->D{return wrap<D>(n);}fn score(v:D)->i64 effects(){return unwrap(v);}}";
const operation = "fn apply<T:copy+op(score(v:T)->i64 effects())>(v:T)->i64{return T.score(v);}";
test "structural operation forwarding retains type identity and public contracts" {
    try run(domain ++ operation ++ "fn forward<U:copy+op(score(v:U)->i64 effects())>(v:U)->i64{return apply::<U>(v);}fn main()->i64{return forward::<D>(D.make(11));}", 11);
    try reject(operation ++ "fn forward<U:copy>(v:U)->i64{return apply::<U>(v);}fn main()->i64{return 0;}", "E_GENERIC_ARGUMENT");
    try reject("fn f<T:copy+op(score(v:T)->bool effects())>(v:T)->i64{return T.score(v);}fn main()->i64{return 0;}", "E_GENERIC_TYPE");
    try reject("fn f<T:copy+op(score(v:T)->i64 effects())>(v:T)->i64{return T.score(true);}fn main()->i64{return 0;}", "E_GENERIC_TYPE");
}
test "structural concrete operations reject private absent wrong typed and excessive effect methods" {
    try reject("domain D:i64{fn make()->D{return wrap<D>(1);}private fn score(v:D)->i64 effects(){return unwrap(v);}}" ++ operation ++ "fn main()->i64{return apply::<D>(D.make());}", "E_GENERIC_ARGUMENT");
    try reject("domain D:i64{fn make()->D{return wrap<D>(1);}}" ++ operation ++ "fn main()->i64{return apply::<D>(D.make());}", "E_GENERIC_ARGUMENT");
    try reject("domain D:i64{fn make()->D{return wrap<D>(1);}fn score(v:D)->bool effects(){return true;}}" ++ operation ++ "fn main()->i64{return apply::<D>(D.make());}", "E_GENERIC_ARGUMENT");
    try reject("domain D:i64{fn make()->D{return wrap<D>(1);}fn score(v:D)->i64 effects(host){return unwrap(v);}}" ++ operation ++ "fn main()->i64{return apply::<D>(D.make());}", "E_GENERIC_ARGUMENT");
    try reject("fn f<T:copy+op(score(v:T)->i64 effects(host))>(v:T)->i64 effects(){return T.score(v);}fn main()->i64{return 0;}", "E_EFFECT_BOUND");
}
const example = domain ++ operation ++ "struct A{value:i64}fn get<T:copy+field(value:i64)>(v:T)->i64{return v.value;}fn main()->i64{return get::<A>(new A{value:5})+apply::<D>(D.make(7));}";
fn lifecycle(allocator: std.mem.Allocator) !void {
    var c = try language.Compilation.init(allocator, "structural.my", example);
    defer c.deinit();
    const formatted = try c.format(allocator);
    defer allocator.free(formatted);
    var copy = try language.Compilation.init(allocator, "formatted.my", formatted);
    defer copy.deinit();
    const again = try copy.format(allocator);
    defer allocator.free(again);
    try t.expectEqualStrings(formatted, again);
    try t.expectEqual(@as(i64, 12), (try copy.execute(allocator)).value);
}
test "structural formatter lifecycle round trips and releases storage under allocation failure" {
    try lifecycle(t.allocator);
    var stable = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(stable.allocator(), lifecycle, .{});
}
const module_files = [_]language.embedded_project.File{
    .{ .path = "main.my", .bytes = "module main;import api;fn main()->i64{return api::apply::<api::D>(api::D.make(13));}" },
    .{ .path = "api.my", .bytes = "module api;export D;export apply;domain D:i64{fn make(n:i64)->D{return wrap<D>(n);}fn score(v:D)->i64 effects(){return unwrap(v);}" ++
        "}fn apply<T:copy+op(score(v:T)->i64 effects())>(v:T)->i64{return T.score(v);}" },
};
fn moduleRead(_: ?*anyopaque, allocator: std.mem.Allocator, path: []const u8, limit: usize) language.project.ReadError![]u8 {
    return language.embedded_project.read(allocator, &module_files, path, limit);
}
test "structural imported operation dispatch survives AST source relocation" {
    var program: language.embedded_project.Program = undefined;
    try program.init(t.allocator, .{ .context = null, .read = moduleRead });
    defer program.deinit();
    try t.expectEqual(@as(i64, 13), (try language.vm.run(t.allocator, program.compilation.code.?)).value);
}

// spec: STRUCTURAL-COMPOSITE-1
test "structural composite fields substitute arrays and nominal applications" {
    try run("struct Box<U:copy>{value:U}struct A{items:[2]i64,box:Box<i64>}" ++
        "fn get<T:copy+field(items:[2]U)+field(box:Box<U>),U:copy>(v:T)->U{return v.box.value;}" ++
        "fn main()->i64{return get::<A,i64>(new A{items:new [2]i64 [1,2],box:new Box<i64>{value:7}});}", 7);
    try reject("fn f<T:copy+field(items:[2]U),U:copy>(v:T)->U{return v.items[true];}", "E_GENERIC_OPERATION");
}

const composite = "struct Box<U:copy>{value:U}struct A{items:[2]i64,box:Box<i64>}struct B{items:[2]bool,box:Box<bool>}" ++
    "fn get<T:copy+field(items:[2]U)+field(box:Box<U>),U:copy>(v:T)->U{return v.box.value;}" ++
    "fn forward<V:copy+field(items:[2]W)+field(box:Box<W>),W:copy>(v:V)->W{return get::<V,W>(v);}" ++
    "fn main()->i64{let flag=forward::<B,bool>(new B{items:new [2]bool [true,false],box:new Box<bool>{value:true}});" ++
    "if flag{return forward::<A,i64>(new A{items:new [2]i64 [1,2],box:new Box<i64>{value:7}});}return 0;}";
fn compositeLifecycle(allocator: std.mem.Allocator) !void {
    var c = try language.Compilation.init(allocator, "composite.my", composite);
    defer c.deinit();
    const formatted = try c.format(allocator);
    defer allocator.free(formatted);
    var copy = try language.Compilation.init(allocator, "formatted.my", formatted);
    defer copy.deinit();
    try t.expectEqual(@as(i64, 7), (try copy.execute(allocator)).value);
}
