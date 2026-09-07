//! Concrete nominal instances execute through ordinary typed IR and the checked bytecode VM.
const std = @import("std");
const memory = @import("memory.zig");
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
const basic = definitions ++ "fn main()->i64{let a=new Box<i64>{value:7};let b=update(a){value:9};" ++
    "let slot=new Slot<Box<i64>>.some(b);match slot{Slot<Box<i64>>.none=>{return 0;},Slot<Box<i64>>.some(value)=>{return a.value+value.value;}}}";
// spec: NOMINAL-INSTANCE-1
test "nominal instances construct update nest and exhaustively match on the VM" {
    try run(t.allocator, basic, 16);
    try run(t.allocator, definitions ++
        "fn plus(input:Answer<i64>)->Answer<i64>{return new Answer<i64>.ok((try input)+1);}fn main()->i64{match plus(new Answer<i64>.ok(4)){Answer<i64>.ok(n)=>{return n;},Answer<i64>.err(discard)=>{return 0;}}}", 5);
}
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
test "nominal instances keep growing phantom arguments outside runtime storage" {
    try run(t.allocator, "struct Empty<T:copy>{}struct Grow<T:copy>{marker:Empty<Grow<[1]T>>}" ++
        "fn main()->i64{discard new Grow<i64>{marker:new Empty<Grow<[1]i64>>{}};return 1;}", 1);
}
fn allocations(allocator: std.mem.Allocator) !void {
    try run(allocator, basic, 16);
}
test "nominal catalog collect and VM execution clean up every allocation failure" {
    try allocations(t.allocator);
    var stable = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(stable.allocator(), allocations, .{});
}

const owned = "buffer B:u8;result Open{ok:B,err:i64}struct Owner<T:copy>{buffer:B,tag:T}" ++ definitions ++
    "fn work(heap:allocator)->Answer<i64>{let owner=new Owner<i64>{buffer:try acquire_buffer<Open>(heap,2),tag:9};" ++
    "let tag=read_field(owner,tag);discard take_field(owner,buffer);return new Answer<i64>.ok(tag);}" ++
    "fn main(heap:allocator)->i64{match work(heap){Answer<i64>.ok(n)=>{return n;},Answer<i64>.err(e)=>{return e;}}}";
fn ownedScenario(allocator: std.mem.Allocator) !void {
    var compilation = try language.Compilation.init(allocator, "owned-instance.my", owned);
    defer compilation.deinit();
    var stats: memory.Statistics = .{};
    const result = try compilation.executeWithOptions(allocator, .{ .memory = .{ .statistics = &stats } });
    try t.expectEqual(@as(i64, 9), result.value);
    try t.expectEqual(@as(u64, 1), stats.created);
    try t.expectEqual(stats.created, stats.released);
    try t.expectEqual(@as(usize, 0), stats.live_allocations);
}
test "nominal instances retain owned fields partial moves result obligations and cleanup" {
    try ownedScenario(t.allocator);
    try reject("buffer B:u8;result Open{ok:B,err:i64}struct Owner<T:copy>{buffer:B,tag:T}result Created<T:copy>{ok:Owner<T>,err:i64}" ++
        "fn make(heap:allocator)->Created<i64>{arena heap as scratch{return new Created<i64>.ok(new Owner<i64>{buffer:try acquire_buffer<Open>(scratch,1),tag:1});}}fn main()->i64{return 0;}", "E_ARENA_ESCAPE");
    try run(t.allocator, definitions ++ "fn main(heap:allocator)->i64{let mut outside=new Box<i64>{value:0};" ++
        "arena heap as scratch{outside=new Box<i64>{value:11};}return outside.value;}", 11);
    try reject(definitions ++ "buffer B:u8;struct Owner<T:copy>{buffer:B,tag:T}fn bad(value:Owner<i64>)->i64{discard take_field(value,buffer);discard take_field(value,buffer);return 0;}fn main()->i64{return 0;}", "E_FIELD_MOVED");
    try reject(definitions ++ "struct Pending<T:copy>{result:Answer<T>}fn bad(value:Pending<i64>)->i64{return 0;}fn main()->i64{return 0;}", "E_RESULT_UNHANDLED");
    try reject(definitions ++ "fn main()->i64{let x=new Answer<i64>.ok(1);discard x;return 0;}", "E_RESULT_DISCARD");
    try reject(definitions ++ "fn main()->i64{discard new Box<Answer<i64>>{value:new Answer<i64>.ok(1)};return 0;}", "E_GENERIC_REQUIREMENT");
    try run(t.allocator, definitions ++ "fn main()->i64{discard new Box<[0]Answer<i64>>{value:new [0]Answer<i64>[]};return 2;}", 2);
}
test "nominal owned instance execution frees partial construction under allocation failures" {
    var stable = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(stable.allocator(), ownedScenario, .{});
}
test "nominal instances preserve borrowing snapshots arrays and enum key identities" {
    try run(t.allocator, definitions ++ "enum Key<T:copy>{left,right}fn main()->i64{" ++
        "let mut box=new Box<i64>{value:3};let snapshot=box;borrow mut box as r{write_ref(r,new Box<i64>{value:8});}" ++
        "let table=new [Key<bool>]Box<i64>{left:box,right:snapshot};return table[new Key<bool>.left].value+table[new Key<bool>.right].value;}", 11);
    try reject(definitions ++ "fn main()->i64{let mut box=new Box<i64>{value:3};borrow box as r{box=new Box<i64>{value:4};}return 0;}", "E_BORROW_CONFLICT");
    try reject(definitions ++ "enum Key<T:copy>{left,right}fn main()->i64{let table=new [Key<bool>]i64{left:1,right:2};return table[new Key<i64>.left];}", "E_TYPE");
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
            "fn twice(x:Box<i64>)->Box<i64>{return update(x){value:x.value*2};}" ++
            "fn hidden_values(x:Box<Hidden>,y:Empty<Hidden>)->i64{discard x;discard y;return 0;}");
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
    try text.writer.writeAll("struct Chain18<T:copy>{}fn takes(x:Chain0<i64>)->i64{discard x;return 0;}fn main()->i64{return 0;}");
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

fn catalogCategories(allocator: std.mem.Allocator) !void {
    try run(allocator, definitions ++
        "domain Id:i64{fn make(n:i64)->Id{return wrap<Id>(n);}fn number(n:Id)->i64{return unwrap(n);}}" ++
        "fn main()->i64{let box=new Box<Id>{value:Id.make(13)};return Id.number(box.value);}", 13);
    const program = definitions ++ "pool P(Handle):Box<i64>;result Open{ok:P,err:i64}result Insert{ok:Handle,err:i64}" ++
        "result Read{ok:Box<i64>,err:i64}resource File:filesystem;" ++
        "fn work(heap:allocator)->Answer<i64>{let mut pool=try acquire_pool<Open>(heap,1);" ++
        "let id=try insert_pool<Insert>(pool,new Box<i64>{value:17});let value=try read_pool<Read>(pool,id);return new Answer<i64>.ok(value.value);}" ++
        "fn main(heap:allocator)->i64{match work(heap){Answer<i64>.ok(n)=>{return n;},Answer<i64>.err(e)=>{return e;}}}";
    var compilation = try language.Compilation.init(allocator, "nominal-pool.my", program);
    defer compilation.deinit();
    try t.expectEqual(@as(i64, 17), (try compilation.execute(allocator)).value);
    var resources: usize = 0;
    for (compilation.program.?.records) |record| if (record.shape.resource) |kind| {
        try t.expectEqual(@import("external_resources.zig").Kind.filesystem, kind);
        try t.expect(record.contract.move_only);
        resources += 1;
    };
    try t.expectEqual(@as(usize, 1), resources);
}

test "nominal catalog preserves domain factories pool handles and ordinary resource contracts" {
    try catalogCategories(t.allocator);
    var stable = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(stable.allocator(), catalogCategories, .{});
}

// spec: GENERIC-CONTAINER-1
test "generic buffers share one checked implementation across nominal elements" {
    try run(t.allocator, "buffer Vec<T:copy>:T;result Status{ok:bool,err:i64}result Open<T:copy>{ok:Vec<T>,err:i64}result Answer<T:copy>{ok:T,err:i64}" ++
        "struct A{value:i64}struct B{other:bool}" ++
        "fn first<T:copy>(heap:allocator,value:T)->Answer<T>{let mut v=try acquire_buffer<Open<T>>(heap,2);discard try append_buffer<Status>(v,value);return new Answer<T>.ok(read_buffer(v,0));}" ++
        "fn main(heap:allocator)->i64{match first::<A>(heap,new A{value:7}){Answer<A>.ok(a)=>{match first::<B>(heap,new B{other:true}){Answer<B>.ok(b" ++
        ")=>{if b.other{return a.value;}else{return 0;}},Answer<B>.err(e)=>{return e;}}},Answer<A>.err(e)=>{return e;}}}", 7);
}

test "generic pools specialize nominal handles and preserve remove errors" {
    try run(t.allocator, "pool Store<T:copy>(Id):T;result Open<T:copy>{ok:Store<T>,err:i64}result Insert<T:copy>{ok:Id<T>,err:i64}result Read<T:copy>{ok:T,err:i64}result Status{ok:bool,err:i64}result Answer{ok:i64,err:i64}" ++
        "fn work<T:copy>(heap:allocator,value:T)->Answer{let mut p=try acquire_pool<Open<T>>(heap,2);let id=try insert_pool<Insert<T>>(p,value);disca" ++
        "rd try read_pool<Read<T>>(p,id);discard try remove_pool<Status>(p,id);match read_pool<Read<T>>(p,id){Read<T>.ok(discard)=>{return new Answer" ++
        ".ok(0);},Read<T>.err(discard)=>{return new Answer.ok(1);}}}" ++
        "fn main(heap:allocator)->i64{match work::<i64>(heap,7){Answer.ok(n)=>{return n;},Answer.err(e)=>{return e;}}}", 1);
}

test "generic container declarations check unused element contracts" {
    try reject("buffer Vec<T:codec>:T;fn main()->i64{return 0;}", "E_GENERIC_REQUIREMENT");
    try reject("pool Store<T:codec>(Id):T;fn main()->i64{return 0;}", "E_GENERIC_REQUIREMENT");
    try reject("buffer Vec<T:copy>:T;buffer B:u8;fn f(value:Vec<B>)->i64{discard value;return 0;}fn main()->i64{return 0;}", "E_GENERIC_REQUIREMENT");
    try reject("buffer Vec<T:copy>:T;result Status{ok:bool,err:i64}result Open<T:copy>{ok:Vec<T>,err:i64}fn bad<T:copy>(heap:allocator)->Open<T>{let mut v=try acquire_buffer<Open<T>>(hea" ++
        "p,1);discard try append_buffer<Status>(v,true);return new Open<T>.ok(v);}fn main()->i64{return 0;}", "E_GENERIC_TYPE");
}

const collection_client =
    "module main;import std_collections as c;" ++
    "fn main(heap:allocator)->i64{match c::filled::<i64>(heap,4u64,9){" ++
    "c::Created<i64>.err(e)=>{return e;},c::Created<i64>.ok(input)=>{let mut values=input;" ++
    "borrow mut values[0..4] as view{write_slice(view,0,5);write_slice(view,1,1);write_slice(view,2,3);" ++
    "discard c::sort::<i64>(view);if read_slice(view,0)!=1{return -1;}" ++
    "discard c::reverse::<i64>(view);if read_slice(view,0)!=9{return -2;}" ++
    "discard c::sort::<i64>(view);if !c::contains::<i64>(view,3){return -3;}" ++
    "return cast<i64>(c::lower_bound::<i64>(view,4))+c::find::<i64>(view,9);}}}}";
fn readCollections(_: ?*anyopaque, allocator: std.mem.Allocator, path: []const u8, limit: usize) language.project.ReadError![]u8 {
    if (!std.mem.eql(u8, path, "main.my")) return error.NotFound;
    if (collection_client.len > limit) return error.TooLarge;
    return allocator.dupe(u8, collection_client);
}
// spec: STANDARD-COLLECTIONS-1
test "standard generic collections allocate sort search and mutate one borrowed vector" {
    var program: language.embedded_project.Program = undefined;
    try program.init(t.allocator, .{ .context = null, .read = readCollections });
    defer program.deinit();
    const outcome = try language.vm.run(t.allocator, program.compilation.code.?);
    try t.expectEqual(@as(i64, 5), outcome.value);
}

fn readBounded(_: ?*anyopaque, allocator: std.mem.Allocator, path: []const u8, limit: usize) language.project.ReadError![]u8 {
    const client = @embedFile("stdlib/tests/bounded.my");
    if (!std.mem.eql(u8, path, "main.my")) return error.NotFound;
    if (client.len > limit) return error.TooLarge;
    return allocator.dupe(u8, client);
}
// spec: BOUNDED-COLLECTIONS-1
test "bounded maps sets and queues preserve owners through full duplicate and deletion paths" {
    var program: language.embedded_project.Program = undefined;
    try program.init(t.allocator, .{ .context = null, .read = readBounded });
    defer program.deinit();
    var stats: memory.Statistics = .{};
    const outcome = try language.vm.runWithOptions(t.allocator, program.compilation.code.?, .{ .memory = .{ .statistics = &stats } });
    try t.expectEqual(@as(i64, 21), outcome.value);
    try t.expectEqual(stats.created, stats.released);
    try t.expectEqual(@as(usize, 0), stats.live_allocations);
}

fn boundedRuntime(allocator: std.mem.Allocator, code: language.bytecode.Program) !void {
    var stats: memory.Statistics = .{};
    const outcome = language.vm.runWithOptions(allocator, code, .{ .memory = .{ .statistics = &stats } });
    try t.expectEqual(stats.created, stats.released);
    try t.expectEqual(@as(usize, 0), stats.live_allocations);
    try t.expectEqual(@as(i64, 21), (try outcome).value);
}

test "bounded collection runtime frees ownership on every allocation failure" {
    var program: language.embedded_project.Program = undefined;
    try program.init(t.allocator, .{ .context = null, .read = readBounded });
    defer program.deinit();
    var no_resize = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(no_resize.allocator(), boundedRuntime, .{program.compilation.code.?});
}

const owner_borrows =
    "buffer Vec<T:copy>:T;result Open<T:copy>{ok:Vec<T>,err:i64}result Status{ok:bool,err:i64}" ++
    "struct Holder<T:copy>{buffer:Vec<T>,tag:i64}result Answer{ok:i64,err:i64}" ++
    "fn inspect<T:copy>(holder:&Holder<T>)->i64 noalloc{return read_field(holder,tag);}" ++
    "fn append<T:copy>(values:&mut Vec<T>,value:T)->Status noalloc{return append_buffer<Status>(values,value);}" ++
    "fn size<T:copy>(values:&Vec<T>)->u64 noalloc{return len_buffer(values);}" ++
    "fn work(heap:allocator)->Answer{let mut values=try acquire_buffer<Open<i64>>(heap,2);" ++
    "borrow mut values as view{discard try append::<i64>(view,7);if size::<i64>(view)!=1u64{return new Answer.ok(-1);}}" ++
    "borrow values[0..1] as view{if read_slice(view,0)!=7{return new Answer.ok(-2);}}" ++
    "let holder=new Holder<i64>{buffer:values,tag:9};borrow holder as view{return new Answer.ok(inspect::<i64>(view));}}" ++
    "fn main(heap:allocator)->i64{match work(heap){Answer.ok(n)=>{return n;},Answer.err(e)=>{return e;}}}";
// spec: OWNER-REFERENCE-1
test "whole owner references inspect records and mutate generic buffers without transfer" {
    try run(t.allocator, owner_borrows, 9);
}

test "owner references preserve exclusion obligations and forbid extracting ownership" {
    const defs = "buffer B:i64;result Open{ok:B,err:i64}result Status{ok:bool,err:i64}struct Holder{buffer:B,tag:i64}";
    try reject(defs ++ "fn f(b:&B)->Status{return append_buffer<Status>(b,1);}fn main()->i64{return 0;}", "E_REFERENCE_READ_ONLY");
    try reject(defs ++ "fn f(b:&B)->B{return read_ref(b);}fn main()->i64{return 0;}", "E_REFERENCE_VALUE");
    try reject(defs ++ "fn f(h:&Holder)->B{return take_field(h,buffer);}fn main()->i64{return 0;}", "E_REFERENCE_READ_ONLY");
    try reject(defs ++ "fn f(b:B)->i64{borrow b as view{discard b;}return 0;}fn main()->i64{return 0;}", "E_BORROW_CONFLICT");
    try reject(defs ++ "fn f(h:Holder)->i64{discard take_field(h,buffer);borrow h as view{return read_field(view,tag);}}fn main()->i64{return 0;}", "E_RESULT_BORROW");
    try reject(defs ++ "fn f(b:&mut B)->i64{borrow b[0..0] as view{return 0;}}fn main()->i64{return 0;}", "E_SLICE_TYPE");
    try reject(defs ++ "fn f<T:copy>(b:&B)->Status{return append_buffer<Status>(b,1);}fn main()->i64{return 0;}", "E_REFERENCE_READ_ONLY");
    try reject(defs ++ "fn f<T:copy>(b:&B)->B{return read_ref(b);}fn main()->i64{return 0;}", "E_REFERENCE_VALUE");
}

test "shared owner inspectors do not acquire the owner's resource cleanup effects" {
    var compilation = try language.Compilation.init(t.allocator, "inspect.my", "resource F:filesystem;struct Holder{file:F,tag:i64}" ++
        "fn inspect(h:&Holder)->i64 effects(){return read_field(h,tag);}" ++
        "fn generic<T:copy>(h:&Holder)->i64 effects(){return read_field(h,tag);}" ++
        "fn main()->i64{return 0;}");
    defer compilation.deinit();
    try compilation.check();
}

fn ownerReferenceRuntime(allocator: std.mem.Allocator, code: language.bytecode.Program) !void {
    var stats: memory.Statistics = .{};
    const outcome = language.vm.runWithOptions(allocator, code, .{ .memory = .{ .statistics = &stats } });
    try t.expectEqual(stats.created, stats.released);
    try t.expectEqual(@as(usize, 0), stats.live_allocations);
    try t.expectEqual(@as(i64, 9), (try outcome).value);
}
test "owner reference restoreLocalOwner unwinds nested owned cells under allocation failures" {
    var compilation = try language.Compilation.init(t.allocator, "owner-reference.my", owner_borrows);
    defer compilation.deinit();
    try compilation.emit();
    var no_resize = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(no_resize.allocator(), ownerReferenceRuntime, .{compilation.code.?});
    const generated = try compilation.emitC(t.allocator);
    defer t.allocator.free(generated);
    try t.expect(std.mem.indexOf(u8, generated, "reference_owner(") != null);
}

test "whole owner reborrows return references and grow buffers before fresh element views" {
    try run(t.allocator, "buffer B:i64;result Open{ok:B,err:i64}result Status{ok:bool,err:i64}result Answer{ok:i64,err:i64}" ++
        "fn identity<T:copy>(value:&mut B)->&mut B from value{return value;}" ++
        "fn work(heap:allocator)->Answer{let mut b=try acquire_buffer<Open>(heap,0);" ++
        "borrow mut b as view{borrow mut identity::<bool>(view) as child{" ++
        "discard try reserve_buffer<Status>(child,heap,2);discard try append_buffer<Status>(child,11);}}" ++
        "borrow b[0..1] as view{return new Answer.ok(read_slice(view,0));}}" ++
        "fn main(heap:allocator)->i64{match work(heap){Answer.ok(n)=>{return n;},Answer.err(e)=>{return e;}}}", 11);
}

test "whole pool references mutate inspect and remove through generic helpers" {
    try run(t.allocator, "pool Store<T:copy>(Id):T;result Open<T:copy>{ok:Store<T>,err:i64}result Insert<T:copy>{ok:Id<T>,err:i64}" ++
        "result Read<T:copy>{ok:T,err:i64}result Status{ok:bool,err:i64}result Answer{ok:i64,err:i64}" ++
        "fn insert<T:copy>(pool:&mut Store<T>,value:T)->Insert<T> noalloc{return insert_pool<Insert<T>>(pool,value);}" ++
        "fn get<T:copy>(pool:&Store<T>,id:Id<T>)->Read<T> noalloc{return read_pool<Read<T>>(pool,id);}" ++
        "fn work(heap:allocator)->Answer{let mut pool=try acquire_pool<Open<i64>>(heap,1);borrow mut pool as view{" ++
        "let id=try insert::<i64>(view,17);let value=try get::<i64>(view,id);discard try remove_pool<Status>(view,id);return new Answer.ok(value);}}" ++
        "fn main(heap:allocator)->i64{match work(heap){Answer.ok(n)=>{return n;},Answer.err(e)=>{return e;}}}", 17);
}

test "whole buffer replacement preserves lexical arena escape checks in ordinary and generic helpers" {
    const defs = "buffer B:i64;result Open{ok:B,err:i64}result Status{ok:bool,err:i64}";
    try reject(defs ++ "fn replace_owner(b:&mut B,heap:allocator)->Status{arena heap as scratch{write_ref(b,try acquire_buffer<Open>(scratch,1));}return new Status.ok(true);}fn main()->i64{return 0;}", "E_ARENA_ESCAPE");
    try reject(defs ++ "fn replace_owner<T:copy>(b:&mut B,heap:allocator)->Status{arena heap as scratch{write_ref(b,try acquire_buffer<Open>(scratch,1));}return new Status.ok(true);}fn main()->i64{return 0;}", "E_ARENA_ESCAPE");
    try run(t.allocator, defs ++
        "fn replace_owner(b:&mut B,value:B)->i64 noalloc{write_ref(b,value);return cast<i64>(capacity_buffer(b));}" ++
        "fn work(heap:allocator)->Status{let mut b=try acquire_buffer<Open>(heap,1);let value=try acquire_buffer<Open>(heap,3);" ++
        "borrow mut b as view{if replace_owner(view,value)!=3{return new Status.ok(false);}}return new Status.ok(capacity_buffer(b)==3u64);}" ++
        "fn main(heap:allocator)->i64{match work(heap){Status.ok(good)=>{if good{return 1;}return 0;},Status.err(e)=>{return e;}}}", 1);
}
