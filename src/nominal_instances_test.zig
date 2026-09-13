//! Concrete nominal instances execute through ordinary typed IR and the checked bytecode VM.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const typed = @import("typed.zig");
const definitions = "struct Box<T:copy>{value:T}union Slot<T:copy>{none,some:T}result Answer<T:copy>{ok:T,err:i64}";
fn run(allocator: std.mem.Allocator, text: []const u8, expected: i64) !void {
    var compilation = try language.Compilation.init(allocator, "instances.my", text);
    defer compilation.deinit();
    const output = try compilation.execute(allocator);
    try t.expectEqual(expected, output.value);
}
fn reject(text: []const u8, code: []const u8) !void {
    var compilation = try language.Compilation.init(t.allocator, "bad-instances.my", text);
    defer compilation.deinit();
    try t.expectError(error.SourceError, compilation.check());
    try t.expectEqualStrings(code, compilation.diagnostics.items[0].code);
}
const basic = definitions ++ "fn main()->i64{let a=new Box<i64>{value:7};let mut b=a;b.value=9;" ++
    "let slot=new Slot<Box<i64>>.some(b);match slot{Slot<Box<i64>>.none=>{return 0;},Slot<Box<i64>>.some(value)=>{return a.value+value.value;}}}";
test "nominal instances preserve argument order and nominal declaration identity" {
    try reject(definitions ++ "fn takes(x:Box<i64>)->i64{return x.value;}fn main()->i64{return takes(new Box<bool>{value:true});}", "E_TYPE");
    try reject("struct Pair<A:copy,B:copy>{a:A,b:B}fn takes(x:Pair<i64,bool>)->i64{return x.a;}fn main()->i64{return takes(new Pair<bool,i64>{a:true,b:1});}", "E_TYPE");
    try reject("struct A<T:copy>{value:T}struct B<T:copy>{value:T}fn takes(x:A<i64>)->i64{return x.value;}fn main()->i64{return takes(new B<i64>{value:1});}", "E_TYPE");
    try reject(definitions ++ "fn main()->i64{let x:Box=1;return x;}", "E_GENERIC_ARITY");
    try reject(definitions ++ "fn Box()->i64{return 1;}fn main()->i64{return 0;}", "E_DUPLICATE_NAME");
}
test "nominal instances compose with existing generic functions and fixed arrays" {
    try run(t.allocator, definitions ++ "fn id<T:copy>(x:T)->T{return x;}fn pair<T:copy>(x:T)->[2]T{return new [2]T[x,x];}" ++
        "fn main()->i64{let boxes=pair::<Box<i64>>(id::<Box<i64>>(new Box<i64>{value:6}));return boxes[0].value+boxes[1].value;}", 12);
    try run(t.allocator, definitions ++ "fn main()->i64{let a=new [2]Box<i64>[new Box<i64>{value:3},new Box<i64>{value:8}];return a[1].value;}", 8);
}
fn allocations(allocator: std.mem.Allocator) !void {
    try run(allocator, basic, 16);
}
test "nominal catalog collect and VM execution clean up every allocation failure" {
    try allocations(t.allocator);
    var stable = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(stable.allocator(), allocations, .{});
}
test "nominal instances retain concrete checks within generic bodies" {
    try run(t.allocator, definitions ++ "fn identity<T:copy>(x:Box<T>)->Box<T>{return x;}fn main()->i64{return identity::<i64>(new Box<i64>{value:5}).value;}", 5);
    try reject(definitions ++ "fn bad<T:copy>()->i64{let box=new Box<i64>{value:true};return 0;}fn main()->i64{return 0;}", "E_GENERIC_TYPE");
    try run(t.allocator, definitions ++ "fn concrete<T:copy>()->i64{let box=new Box<i64>{value:4};return box.value;}fn main()->i64{return concrete::<bool>();}", 4);
}
const Modules = struct {
    fn read(_: ?*anyopaque, allocator: std.mem.Allocator, path: []const u8, _: usize) language.project.ReadError![]u8 {
        if (std.mem.eql(u8, path, "main.my")) return allocator.dupe(u8, "module main;import model as m;fn main()->i64{let x=new m::Box<i64>{value:4};return m::twice(x).value;}");
        if (std.mem.eql(u8, path, "model.my")) return allocator.dupe(u8, "module model;export Box;export Empty;export twice;struct Box<T:copy>{value:T}struct Empty<T:copy>{}struct Hidden{value:i64}" ++
            "fn twice(x:Box<i64>)->Box<i64>{let mut y=x;y.value=x.value*2;return y;}" ++
            "fn hidden_values(x:Box<Hidden>,y:Empty<Hidden>)->i64{_ = x;_ = y;return 0;}");
        return error.NotFound;
    }
};
fn moduleScenario(allocator: std.mem.Allocator) !void {
    var project = language.project.Project.init(allocator);
    defer project.deinit();
    try project.load(.{ .context = null, .read = Modules.read }, "main", .{});
    var index = try language.interfaces.build(&project);
    var compilation = try language.project_compile.Compilation.init(&index);
    try compilation.emit();
    const public_type = try compilation.publicValueType("model::Box<i64>");
    try t.expectEqual(typed.Type.i64, compilation.program.?.records[public_type.recordIndex()].fields[0].ty);
    try t.expectError(error.UnknownPublicValueType, compilation.publicValueType("model::Box<model::Hidden>"));
    try t.expectError(error.UnknownPublicValueType, compilation.publicValueType("model::Empty<model::Hidden>"));
    try t.expectEqual(@as(i64, 8), (try language.vm.run(allocator, compilation.code.?)).value);
}
test "nominal instances share declaration identity through imported signatures and constructors" {
    try moduleScenario(t.allocator);
    var stable = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(stable.allocator(), moduleScenario, .{});
}
fn largeNames(allocator: std.mem.Allocator) ![]u8 {
    var text: std.Io.Writer.Allocating = .init(allocator);
    defer text.deinit();
    try text.writer.writeAll("struct Pair<A:copy,B:copy>{a:A,b:B}");
    for (0..18) |i| try text.writer.print("struct Chain{d}<T:copy>{{next:Chain{d}<Pair<T,T>>}}", .{ i, i + 1 });
    try text.writer.writeAll("struct Chain18<T:copy>{}fn takes(x:Chain0<i64>)->i64{_ = x;return 0;}fn main()->i64{return 0;}");
    return text.toOwnedSlice();
}
test "nominal concrete type names stop expansion before excessive diagnostic allocation" {
    const text = try largeNames(t.allocator);
    defer t.allocator.free(text);
    try reject(text, "E_GENERIC_LIMIT");
}
fn hostEcho(call: *language.host_functions.Call) language.host_functions.CallbackError!typed.Value {
    return typed.Value.createVariant(call.allocator(), call.result_type, 0, call.arguments[0]);
}
fn hostScenario(allocator: std.mem.Allocator) !void {
    var compilation = try language.Compilation.init(allocator, "host-instance.my", definitions ++
        "host fn echo(x:Box<i64>)->Answer<Box<i64>> effects(host);fn main()->i64{match echo(new Box<i64>{value:7}){Answer<Box<i64>>.ok(box)=>{return box.value;},Answer<Box<i64>>.err(e)=>{return e;}}}");
    defer compilation.deinit();
    try compilation.emit();
    var registry = try language.vm_host.Registry.init(allocator, compilation.code.?);
    defer registry.deinit();
    const signature = try registry.contract("echo");
    try registry.register("echo", .{ .signature = signature, .invoke = hostEcho }, signature.effects);
    const result = try language.vm.runWithHost(allocator, compilation.code.?, .{}, &registry, .{});
    try t.expectEqual(@as(i64, 7), result.value);
}
test "nominal instances cross typed host calls without erasing result or payload identity" {
    try hostScenario(t.allocator);
    var stable = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(stable.allocator(), hostScenario, .{});
}
test "nominal exported type constructors are symbolic schema templates rather than concrete callable roots" {
    var project = language.project.Project.init(t.allocator);
    defer project.deinit();
    try project.load(.{ .context = null, .read = Modules.read }, "main", .{});
    var index = try language.interfaces.build(&project);
    var compilation = try language.project_compile.Compilation.init(&index);
    const bytes = try language.schema.render(t.allocator, &compilation);
    defer t.allocator.free(bytes);
    const parsed = try std.json.parseFromSlice(std.json.Value, t.allocator, bytes, .{});
    defer parsed.deinit();
    const templates = parsed.value.object.get("generic_templates").?.array.items;
    try t.expect(templates.len >= 1);
    try t.expect(!templates[0].object.get("contract").?.object.get("callable").?.bool);
    try t.expect(templates[0].object.get("contract").?.object.get("requires_explicit_instantiation").?.bool);
}
test "nominal instances carry domain payloads beside resource declarations" {
    const program = definitions ++
        "domain Id:i64{fn make(n:i64)->Id{return wrap<Id>(n);}fn number(n:Id)->i64{return unwrap(n);}}" ++
        "resource File:filesystem;" ++
        "fn main()->i64{let box=new Box<Id>{value:Id.make(13)};return Id.number(box.value);}";
    var compilation = try language.Compilation.init(t.allocator, "nominal-domain.my", program);
    defer compilation.deinit();
    try t.expectEqual(@as(i64, 13), (try compilation.execute(t.allocator)).value);
    var resources: usize = 0;
    for (compilation.program.?.records) |record| if (record.shape.resource) |kind| {
        try t.expectEqual(@import("external_resources.zig").Kind.filesystem, kind);
        try t.expect(record.contract.move_only);
        resources += 1;
    };
    try t.expectEqual(@as(usize, 1), resources);
}
test "nominal instances keep growing phantom arguments outside runtime storage" {
    try run(t.allocator, "struct Empty<T:copy>{}struct Grow<T:copy>{marker:Empty<Grow<[1]T>>}" ++
        "fn main()->i64{_ = new Grow<i64>{marker:new Empty<Grow<[1]i64>>{}};return 1;}", 1);
}
