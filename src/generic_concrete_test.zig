//! Concrete schemas remain nominal while unrelated generic arguments stay symbolic.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const schema = "struct Sample{values:[2]i64,tag:u8}";
const program = schema ++
    "fn make<T:integer>(x:T)->Sample{return new Sample{values:new [2]i64[cast<i64>(x),cast<i64>(x)+1],tag:7u8};}" ++
    "fn total<T:copy>(x:T,s:Sample)->i64{_ = x;return s.values[0]+s.values[1]+cast<i64>(len(s.values));}" ++
    "fn choose<T:copy>(x:T,a:Sample,b:Sample)->Sample{_ = x;if a.tag==b.tag{return a;}return b;}" ++
    "fn main()->i64{let p=make::<u8>(7u8);return total::<bool>(true,choose::<i64>(0,p,p));}";
fn scenario(allocator: std.mem.Allocator) !void {
    var c = try language.Compilation.init(allocator, "concrete.my", program);
    defer c.deinit();
    try t.expectEqual(@as(i64, 17), (try c.execute(allocator)).value);
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
const updates = "struct Pair{values:[2]i64,flag:bool}" ++
    "fn change<T:integer>(p:Pair,index:T,value:i64)->Pair{let mut q=p;q.values=replace(p.values,index,value);return q;}" ++
    "fn main()->i64{let original=new Pair{values:new [2]i64[7,8],flag:true};let changed=change::<u8>(original,0u8,20);" ++
    "if changed.flag{return original.values[0]+changed.values[0]+changed.values[1];}return 0;}";
fn updateScenario(allocator: std.mem.Allocator) !void {
    var c = try language.Compilation.init(allocator, "updates.my", updates);
    defer c.deinit();
    try t.expectEqual(@as(i64, 35), (try c.execute(allocator)).value);
    var table = try language.Compilation.init(allocator, "table-update.my", "enum Key{first,second}" ++
        "fn put<T:integer>(p:[Key]i64,key:Key,value:T)->[Key]i64{return replace(p,key,cast<i64>(value));}" ++
        "fn main()->i64{let old=new [Key]i64{first:1,second:2};let changed=put::<u8>(old,new Key.first,8u8);return old[new Key.first]+changed[new Key.first];}");
    defer table.deinit();
    try t.expectEqual(@as(i64, 9), (try table.execute(allocator)).value);
}
// spec: GENERIC-UPDATE-1
test "generic record updates and array replacement preserve snapshots under allocation failures" {
    try updateScenario(t.allocator);
    var stable = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(stable.allocator(), updateScenario, .{});
}
const variants = "struct Payload{n:i64}enum Color{red,blue}union Choice{none,value:Payload}" ++
    "fn make<T:integer>(x:T)->Choice{return new Choice.value(new Payload{n:cast<i64>(x)});}" ++
    "fn score<T:copy>(context:T,x:Choice)->i64{_ = context;match x{Choice.none=>{return 0;},Choice.value(p)=>{return p.n;}}}" ++
    "fn color<T:copy>(context:T)->Color{_ = context;return new Color.blue;}" ++
    "fn mapping<T:integer>(x:T)->[Color]i64{return new [Color]i64{red:cast<i64>(x),blue:0};}" ++
    "fn main()->i64{match color::<bool>(true){Color.red=>{return 0;},Color.blue=>{return score::<i64>(0,make::<u8>(7u8))+mapping::<u8>(2u8)[new Color.red];}}}";
fn variantScenario(allocator: std.mem.Allocator) !void {
    var c = try language.Compilation.init(allocator, "variants.my", variants);
    defer c.deinit();
    try t.expectEqual(@as(i64, 9), (try c.execute(allocator)).value);
}
// spec: GENERIC-VARIANT-1
test "generic concrete variants construct and match with scoped payloads under allocation failures" {
    try variantScenario(t.allocator);
    var stable = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(stable.allocator(), variantScenario, .{});
}
