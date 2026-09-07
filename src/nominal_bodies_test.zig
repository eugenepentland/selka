//! Generic nominal bodies are checked before calls and specialize through the VM catalog.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const definitions = "struct Box<T:copy>{value:T}union Slot<T:copy>{none,some:T}result R<T:copy>{ok:T,err:i64}";
fn run(allocator: std.mem.Allocator, text: []const u8, expected: i64) !void {
    var compilation = try language.Compilation.init(allocator, "nominal-body.my", text);
    defer compilation.deinit();
    const result = compilation.execute(allocator) catch |err| {
        if (err != error.OutOfMemory) @import("diagnostics_test.zig").report(compilation.diagnostics.items);
        return err;
    };
    try t.expectEqual(expected, result.value);
}
fn reject(text: []const u8, code: []const u8) !void {
    var compilation = try language.Compilation.init(t.allocator, "bad-nominal-body.my", text);
    defer compilation.deinit();
    try t.expectError(error.SourceError, compilation.check());
    try t.expectEqualStrings(code, compilation.diagnostics.items[0].code);
}
const basic = definitions ++
    "fn pack<T:copy>(x:T)->Box<T>{return new Box<T>{value:x};}fn extract<T:copy>(box:Box<T>)->T{return box.value;}" ++
    "fn alter<T:copy>(box:Box<T>,x:T)->Box<T>{return update(box){value:x};}" ++
    "fn slot<T:copy>(x:T)->Slot<T>{return new Slot<T>.some(x);}fn choose<T:copy>(x:Slot<T>,fallback:T)->T{" ++
    "match x{Slot<T>.none=>{return fallback;},Slot<T>.some(value)=>{return value;}}}" ++
    "fn main()->i64{return extract::<i64>(alter::<i64>(pack::<i64>(3),choose::<i64>(slot::<i64>(7),0)));}";
// spec: NOMINAL-BODY-1
test "nominal bodies construct project update match and forward symbolic arguments" {
    try run(t.allocator, basic, 7);
}
test "nominal bodies reject invalid uncalled field payload and identity operations" {
    try reject(definitions ++ "fn wrong<T:copy>(x:T)->Box<T>{return new Box<T>{value:1};}fn main()->i64{return 0;}", "E_GENERIC_TYPE");
    try reject(definitions ++ "fn wrong<T:copy>(x:Box<T>)->T{return x.missing;}fn main()->i64{return 0;}", "E_UNKNOWN_FIELD");
    try reject(definitions ++ "fn wrong<T:copy>(x:Slot<T>)->i64{match x{Slot<T>.none=>{return 1;}}}fn main()->i64{return 0;}", "E_INCOMPLETE_MATCH");
    try reject(definitions ++ "fn wrong<T:copy,U:copy>(x:Box<T>)->Box<U>{return x;}fn main()->i64{return 0;}", "E_GENERIC_TYPE");
}
const results = definitions ++ "result Output<T:copy>{err:i64,ok:Box<T>}" ++
    "fn plus<T:integer>(x:R<T>)->Output<T>{let n=try x;return new Output<T>.ok(new Box<T>{value:n+n});}" ++
    "fn main()->i64{match plus::<i64>(new R<i64>.ok(6)){Output<i64>.ok(box)=>{return box.value;},Output<i64>.err(e)=>{return e;}}}";
test "nominal bodies propagate results with named error remapping and obligations" {
    try run(t.allocator, results, 12);
    try reject(definitions ++ "fn drop<T:copy>(r:R<T>)->i64{return 0;}fn main()->i64{return 0;}", "E_RESULT_UNHANDLED");
    try reject(definitions ++ "fn drop<T:copy>(r:R<T>)->i64{discard r;return 0;}fn main()->i64{return 0;}", "E_RESULT_DISCARD");
}
const arrays = definitions ++
    "fn pairs<T:copy>(x:T)->[2]T{return new [2]T[x,x];}fn boxed<T:copy>(x:T)->Box<[2]T>{return new Box<[2]T>{value:pairs::<T>(x)};}" ++
    "fn main()->i64{let a=pairs::<i64>(1);let b=boxed::<i64>(8);return a[0]+b.value[1];}";
test "nominal bodies reuse concrete array identities created by earlier function specialization" {
    try run(t.allocator, arrays, 9);
}
fn allocations(allocator: std.mem.Allocator) !void {
    try run(allocator, basic, 7);
    try run(allocator, results, 12);
    try run(allocator, arrays, 9);
}
test "nominal bodies release shape catalogs and VM storage after every allocation failure" {
    var stable = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(stable.allocator(), allocations, .{});
}

const owners = definitions ++ "buffer B:u8;result Open<T:copy>{ok:B,err:i64}struct Owner<T:copy>{buffer:B,tag:T}" ++
    "fn consume<T:copy>(owner:Owner<T>)->T{discard take_field(owner,buffer);return read_field(owner,tag);}" ++
    "fn work<T:integer>(heap:allocator,tag:T)->R<T>{let owner=new Owner<T>{buffer:try acquire_buffer<Open<T>>(heap,1),tag:tag};return new R<T>.ok(consume::<T>(owner));}" ++
    "fn main(heap:allocator)->i64{match work::<i64>(heap,21){R<i64>.ok(n)=>{return n;},R<i64>.err(e)=>{return e;}}}";
fn ownedScenario(allocator: std.mem.Allocator) !void {
    var compilation = try language.Compilation.init(allocator, "nominal-owner.my", owners);
    defer compilation.deinit();
    var statistics: @import("memory.zig").Statistics = .{};
    const result = compilation.executeWithOptions(allocator, .{ .memory = .{ .statistics = &statistics } }) catch |err| {
        if (err != error.OutOfMemory) @import("diagnostics_test.zig").report(compilation.diagnostics.items);
        return err;
    };
    try t.expectEqual(@as(i64, 21), result.value);
    try t.expectEqual(@as(u64, 1), statistics.created);
    try t.expectEqual(statistics.created, statistics.released);
    try t.expectEqual(@as(usize, 0), statistics.live_allocations);
}
test "nominal bodies preserve owned partial moves and typed acquisition under allocation failures" {
    try ownedScenario(t.allocator);
    var stable = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(stable.allocator(), ownedScenario, .{});
}
test "nominal bodies reject duplicate partial moves cleanup effects and arena escapes before calls" {
    const owned_types = "buffer B:u8;result Open{ok:B,err:i64}struct Owner<T:copy>{buffer:B,tag:T}result Made<T:copy>{ok:Owner<T>,err:i64}";
    try reject(owned_types ++ "fn wrong<T:copy>(x:Owner<T>)->T{discard take_field(x,buffer);discard take_field(x,buffer);return read_field(x,tag);}fn main()->i64{return 0;}", "E_FIELD_MOVED");
    try reject(owned_types ++ "fn wrong<T:copy>(heap:allocator,tag:T)->Made<T>{arena heap as scratch{return new Made<T>.ok(new Owner<T>{buffer:try acquire_buffer<Open>(scratch,1),tag:tag});}}fn main()->i64{return 0;}", "E_ARENA_ESCAPE");
    try reject("resource F:network;struct Owner<T:copy>{file:F,tag:T}fn wrong<T:copy>(owner:Owner<T>)->i64 effects(){discard owner;return 0;}fn main()->i64{return 0;}", "E_EFFECT_BOUND");
}
const loans = definitions ++ "fn view<T:copy>(x:&Box<T>)->&Box<T> from x{return x;}" ++
    "fn change<T:copy>(x:&mut Box<T>,value:T)->i64{write_ref(x,new Box<T>{value:value});return 0;}" ++
    "fn main()->i64{let mut box=new Box<i64>{value:3};let original=box;borrow mut box as r{discard change::<i64>(r,9);}" ++
    "borrow box as r{borrow view::<i64>(r) as v{return read_ref(v).value+original.value;}}}";
test "nominal bodies preserve borrowed mutation snapshots and returned input lifetimes" {
    try run(t.allocator, loans, 12);
    try reject(definitions ++ "fn wrong<T:copy>(value:T)->&Box<T> from value{let box=new Box<T>{value:value};borrow box as r{return r;}}fn main()->i64{return 0;}", "E_RETURN_LIFETIME");
    try reject(definitions ++ "fn wrong<T:copy>(value:T)->i64{let mut box=new Box<T>{value:value};borrow box as r{box=new Box<T>{value:value};}return 0;}fn main()->i64{return 0;}", "E_BORROW_CONFLICT");
}

const module_source = "module model;export Box;export pack;export extract;struct Box<T:copy>{value:T}" ++
    "fn pack<T:copy>(x:T)->Box<T>{return new Box<T>{value:x};}fn extract<T:copy>(box:Box<T>)->T{return box.value;}";
const Modules = struct {
    fn read(_: ?*anyopaque, allocator: std.mem.Allocator, path: []const u8, _: usize) language.project.ReadError![]u8 {
        if (std.mem.eql(u8, path, "main.my")) return allocator.dupe(u8, "module main;import model as m;fn main()->i64{return m::extract::<i64>(m::pack::<i64>(23));}");
        if (std.mem.eql(u8, path, "model.my")) return allocator.dupe(u8, module_source);
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
    const ty = try compilation.publicValueType("model::Box<i64>");
    try t.expectEqual(@import("typed.zig").Type.i64, compilation.program.?.records[ty.recordIndex()].fields[0].ty);
    try t.expectEqual(@as(i64, 23), (try language.vm.run(allocator, compilation.code.?)).value);
}
test "nominal bodies preserve imported declaration identity through specialization and public lookup" {
    try moduleScenario(t.allocator);
    var stable = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(stable.allocator(), moduleScenario, .{});
}
test "nominal bodies preserve phantom enum identity and field order across partial results" {
    try run(t.allocator, "enum Tag<T:copy>{a,b}fn same<T:copy>(a:Tag<T>,b:Tag<T>)->bool{return a==b;}" ++
        "fn make<T:copy>()->Tag<T>{return new Tag<T>.a;}fn main()->i64{if same::<i64>(make::<i64>(),new Tag<i64>.a){return 3;}return 0;}", 3);
    try run(t.allocator, definitions ++ "struct Pair<T:copy>{left:R<T>,right:R<T>}fn first<T:copy>(p:Pair<T>)->R<T>{" ++
        "acknowledge take_field(p,right);return take_field(p,left);}fn main()->i64{match first::<i64>(new Pair<i64>{left:new R<i64>.ok(13),right:new R<i64>.err(9)}){R<i64>.ok(n)=>{return n;},R<i64>.err(e)=>{return e;}}}", 13);
    const failing = try std.mem.replaceOwned(u8, t.allocator, results, "new R<i64>.ok(6)", "new R<i64>.err(17)");
    defer t.allocator.free(failing);
    try run(t.allocator, failing, 17);
    try reject(definitions ++ "fn bad<T:copy>(r:R<T>)->i64{while false{acknowledge r;}return 0;}fn main()->i64{return 0;}", "E_RESULT_LOOP");
}
test "nominal bodies bound growing function specialization before executable output" {
    const source_text = definitions ++ "fn grow<T:copy>(x:T)->i64{return grow::<Box<T>>(new Box<T>{value:x});}fn main()->i64{return grow::<i64>(0);}";
    var compilation = try language.Compilation.init(t.allocator, "growing-nominal.my", source_text);
    defer compilation.deinit();
    try t.expectError(error.SourceError, compilation.emit());
    try t.expectEqualStrings("E_GENERIC_LIMIT", compilation.diagnostics.items[0].code);
    try t.expect(compilation.program == null and compilation.code == null);
}
