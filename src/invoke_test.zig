//! `mylang invoke` acceptance: target selection and eligibility, request
//! validation, the `native-invocation-v1` envelope, and the result/trap/timeout
//! distinction.
//!
//! Every test here is straight-line: schema fixtures are parsed once by a
//! helper and the loops that walk them live in helpers, not in test bodies.
const std = @import("std");
const testing = std.testing;
const fs = @import("qbe_build_io.zig");
const options = @import("native_test_options.zig");
const sessions = @import("native_test_session.zig");
const wire = @import("native_test_wire.zig");
const invoke = @import("invoke.zig");
const command = @import("invoke_command.zig");
const schema_json = @import("invoke_wire_schema.zig");
const Value = std.json.Value;

/// A checked-schema fixture shaped exactly like `language-schema-v1`: two
/// scalar arguments, a nested record result, a record argument, an unsupported
/// nested buffer, a capability argument and a domain-codec result.
const fixture =
    \\{"functions":[
    \\{"name":"tool::scale","parameters":[{"name":"value","type":"i64","mode":"value"},{"name":"factor","type":"i64","mode":"value"}],"result":"i64","effects":[],"mutates":[],"return_origin":"unknown"},
    \\{"name":"tool::sample_label","parameters":[{"name":"sample","type":"tool::Sample","mode":"value"}],"result":"i64","effects":[],"mutates":[],"return_origin":"unknown"},
    \\{"name":"tool::note_weight","parameters":[{"name":"note","type":"tool::Note","mode":"value"}],"result":"i64","effects":[],"mutates":[],"return_origin":"unknown"},
    \\{"name":"tool::probe_filesystem","parameters":[{"name":"fs","type":"filesystem_cap","mode":"value"}],"result":"i64","effects":["filesystem"],"mutates":[],"return_origin":"unknown"},
    \\{"name":"tool::announce","parameters":[{"name":"out","type":"stream_cap","mode":"value"},{"name":"value","type":"i64","mode":"value"}],"result":"i64","effects":["output"],"mutates":[],"return_origin":"unknown"},
    \\{"name":"tool::grow","parameters":[{"name":"seed","type":"i64","mode":"value"}],"result":"tool::Sample","effects":["managed_allocation"],"mutates":[],"return_origin":"unknown"}],
    \\"types":[
    \\{"name":"i64","kind":"integer","move_only":false,"opaque":false,"bits":64,"signed":true,"minimum":"-9223372036854775808","maximum":"9223372036854775807"},
    \\{"name":"bool","kind":"boolean","move_only":false,"opaque":false},
    \\{"name":"stream_cap","kind":"capability","move_only":false,"opaque":true},
    \\{"name":"filesystem_cap","kind":"capability","move_only":false,"opaque":true},
    \\{"name":"tool::Span","kind":"record","move_only":false,"opaque":false,"fields":[{"name":"low","type":"i64"},{"name":"high","type":"i64"}]},
    \\{"name":"tool::Sample","kind":"record","move_only":false,"opaque":false,"fields":[{"name":"label","type":"i64"},{"name":"span","type":"tool::Span"},{"name":"weights","type":"[3]i64"}]},
    \\{"name":"[3]i64","kind":"array","move_only":false,"opaque":false,"element":"i64","length":3},
    \\{"name":"tool::Note","kind":"record","move_only":false,"opaque":false,"fields":[{"name":"title","type":"str"},{"name":"weight","type":"i64"}]},
    \\{"name":"str","kind":"buffer","move_only":false,"opaque":true,"element":"u8"},
    \\{"name":"tool::Ratio","kind":"result","move_only":false,"requires_handling":true,"opaque":false,"cases":[{"name":"ok","payload":"i64"},{"name":"err","payload":"i64"}]},
    \\{"name":"tool::MetresWire","kind":"record","move_only":false,"opaque":false,"fields":[{"name":"count","type":"i64"}]},
    \\{"name":"tool::Metres","kind":"domain","move_only":false,"opaque":true,"codec":{"wire":"tool::MetresWire","decode":"tool::Metres::from_wire","encode":"tool::Metres::to_wire","error_type":"i64"}}]}
;

/// One parsed fixture schema owned by the caller's arena.
fn fixtureSchema(allocator: std.mem.Allocator) !Value {
    const parsed = try std.json.parseFromSlice(Value, allocator, fixture, .{ .allocate = .alloc_always });
    return parsed.value;
}

/// One named function out of the fixture schema.
fn fixtureFunction(schema: Value, name: []const u8) Value {
    return invoke.select(schema, name).?;
}

/// The wire pattern one integer property carries in a generated schema.
fn propertyPattern(schema: Value, name: []const u8) []const u8 {
    const properties = schema.object.get("properties").?;
    return properties.object.get(name).?.object.get("pattern").?.string;
}

// spec: INVOKE-4
test "the envelope version and the three documented exit statuses do not change" {
    try testing.expectEqualStrings("native-invocation-v1", invoke.envelope_version);
    try testing.expect(std.mem.indexOf(u8, command.usage, "usage: mylang invoke") != null);
    try testing.expectEqual(@as(u8, 0), invoke.exit_completed);
    try testing.expectEqual(@as(u8, 1), invoke.exit_source_or_runtime);
    try testing.expectEqual(@as(u8, 2), invoke.exit_request_or_setup);
}

// spec-case: INVOKE-4
test "every response status keeps its documented exit status and spelling" {
    try testing.expectEqualStrings("described", invoke.statusText(.described));
    try testing.expectEqualStrings("completed", invoke.statusText(.completed));
    try testing.expectEqualStrings("trap", invoke.statusText(.trap));
    try testing.expectEqualStrings("timeout", invoke.statusText(.timeout));
    try testing.expectEqualStrings("source-error", invoke.statusText(.@"source-error"));
    try testing.expectEqualStrings("invalid-request", invoke.statusText(.@"invalid-request"));
    try testing.expectEqualStrings("unsupported", invoke.statusText(.unsupported));
    try testing.expectEqualStrings("setup-failure", invoke.statusText(.@"setup-failure"));
    try testing.expectEqual(@as(u8, 0), invoke.exitStatusText("described"));
    try testing.expectEqual(@as(u8, 0), invoke.exitStatusText("completed"));
    try testing.expectEqual(@as(u8, 1), invoke.exitStatusText("trap"));
    try testing.expectEqual(@as(u8, 1), invoke.exitStatusText("timeout"));
    try testing.expectEqual(@as(u8, 1), invoke.exitStatusText("source-error"));
    try testing.expectEqual(@as(u8, 2), invoke.exitStatusText("invalid-request"));
    try testing.expectEqual(@as(u8, 2), invoke.exitStatusText("unsupported"));
    try testing.expectEqual(@as(u8, 2), invoke.exitStatusText("setup-failure"));
    try testing.expectEqual(@as(u8, 2), invoke.exitStatusText("not-a-status"));
    try testing.expect(invoke.completed(.described));
    try testing.expect(invoke.completed(.completed));
    try testing.expect(!invoke.completed(.trap));
}

// spec: INVOKE-5
test "a returned language error is a typed completed result, not a trap" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const failure = (try std.json.parseFromSlice(Value, a,
        \\{"case":"err","value":"-1"}
    , .{ .allocate = .alloc_always })).value;
    const success = (try std.json.parseFromSlice(Value, a,
        \\{"case":"ok","value":"7"}
    , .{ .allocate = .alloc_always })).value;
    try testing.expect(invoke.returnedError(failure));
    try testing.expect(!invoke.returnedError(success));
    try testing.expect(!invoke.returnedError(.{ .string = "7" }));
}

// spec-case: INVOKE-5
test "a trap response keeps its code, operation and source-mapped frames" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const detail = try invoke.trapDetail(a, "R_DIVISION_BY_ZERO (floor_div: left 7, right 0)\n  in tool::integer_divide at tool.my:39:22\n");
    try testing.expectEqualStrings("R_DIVISION_BY_ZERO", detail.code);
    try testing.expectEqualStrings("floor_div", detail.operation);
    try testing.expectEqual(@as(usize, 1), detail.frames.len);
    try testing.expectEqualStrings("tool::integer_divide", detail.frames[0].function);
    try testing.expectEqualStrings("tool.my", detail.frames[0].path);
    try testing.expectEqual(@as(u64, 39), detail.frames[0].line);
    try testing.expectEqual(@as(u64, 22), detail.frames[0].column);
    const unrelated = try invoke.trapDetail(a, "NativeTestProcessFailed: .{ .signal = .SEGV }\n");
    try testing.expectEqualStrings("", unrelated.code);
    try testing.expectEqual(@as(usize, 0), unrelated.frames.len);
}

// spec: INVOKE-3
test "a repeated argument key is found in the raw request text at any depth" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try testing.expectEqualStrings("value", (try invoke.duplicateKey(a,
        \\{"value": "1", "factor": "2", "value": "3"}
    )).?);
    try testing.expectEqualStrings("outer", (try invoke.duplicateKey(a,
        \\{"outer": {"value": "1"}, "outer": {"value": "2"}}
    )).?);
    try testing.expect((try invoke.duplicateKey(a,
        \\{"outer": {"value": "1"}, "value": "2"}
    )) == null);
    try testing.expect((try invoke.duplicateKey(a,
        \\{"message": "a, \"value\": b", "value": "2"}
    )) == null);
    try testing.expect((try invoke.duplicateKey(a, "[]")) == null);
}

// spec: INVOKE-1
test "a target is selected by its exact qualified name only" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const schema = try fixtureSchema(arena.allocator());
    try testing.expect(invoke.select(schema, "tool::scale") != null);
    try testing.expect(invoke.select(schema, "tool::hidden") == null);
    try testing.expect(invoke.select(schema, "scale") == null);
    try testing.expectEqualStrings("tool::scale", invoke.select(schema, "tool::scale").?.object.get("name").?.string);
}

// spec: INVOKE-2
test "an eligible scalar export reports its contract and needs no authority" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const schema = try fixtureSchema(a);
    const verdict = try invoke.eligibility(a, schema, fixtureFunction(schema, "tool::scale"));
    try testing.expect(verdict.eligible);
    try testing.expect(verdict.wire_supported);
    try testing.expect(verdict.refusal == null);
    try testing.expectEqual(@as(usize, 0), verdict.capabilities.len);
    try testing.expectEqual(@as(usize, 0), verdict.effects.len);
    try testing.expectEqualStrings("integer", invoke.wireKind(invoke.types(schema), "i64"));
    try testing.expectEqualStrings("record", invoke.wireKind(invoke.types(schema), "tool::Sample"));
    try testing.expectEqualStrings("injected-stream", invoke.wireKind(invoke.types(schema), "stream_cap"));
}

// spec-case: INVOKE-9
test "a record argument is executable and an unsupported nested field still names its path" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const schema = try fixtureSchema(a);
    // A record argument now executes: the copied-value adapter reads the
    // emitter's own crossing from the manifest and passes the argument buffer,
    // so the wire subset and the executable subset agree on it.
    const aggregate = try invoke.eligibility(a, schema, fixtureFunction(schema, "tool::sample_label"));
    try testing.expect(aggregate.eligible);
    try testing.expect(aggregate.wire_supported);
    try testing.expect(aggregate.refusal == null);
    const nested = try invoke.eligibility(a, schema, fixtureFunction(schema, "tool::note_weight"));
    try testing.expect(!nested.eligible);
    try testing.expect(!nested.wire_supported);
    try testing.expectEqualStrings("unsupported-type", nested.refusal.?.kind);
    try testing.expectEqualStrings("argument 'note' -> field 'title'", nested.refusal.?.path);
    const capability = try invoke.eligibility(a, schema, fixtureFunction(schema, "tool::probe_filesystem"));
    try testing.expect(!capability.eligible);
    try testing.expectEqualStrings("authority", capability.refusal.?.kind);
    try testing.expectEqual(@as(usize, 1), capability.capabilities.len);
    try testing.expectEqualStrings("filesystem_cap", capability.capabilities[0]);
    try testing.expectEqual(@as(usize, 1), capability.effects.len);
}

// spec-case: INVOKE-2
test "an injected stream is eligible and a nested aggregate result is carried" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const schema = try fixtureSchema(a);
    const streamed = try invoke.eligibility(a, schema, fixtureFunction(schema, "tool::announce"));
    try testing.expect(streamed.eligible);
    try testing.expect(streamed.wire_supported);
    try testing.expectEqual(@as(usize, 0), streamed.capabilities.len);
    try testing.expectEqual(@as(usize, 1), streamed.effects.len);
    try testing.expectEqualStrings("output", streamed.effects[0]);
    const nested = try invoke.eligibility(a, schema, fixtureFunction(schema, "tool::grow"));
    try testing.expect(nested.eligible);
    try testing.expect(nested.wire_supported);
    const described: invoke.Description = .{
        .eligible = false,
        .wire_supported = true,
        .contract = .{ .arguments = &.{}, .result = .{ .type = "i64", .wire = "integer" }, .effects = &.{}, .mutates = &.{}, .return_origin = "unknown" },
        .authority = .{ .capabilities = &.{}, .effects = &.{} },
    };
    try testing.expect(!described.eligible);
    try testing.expect(described.wire_supported);
    try testing.expect(described.unsupported == null);
}

// spec-case: INVOKE-3
test "named arguments are refused as missing, extra or malformed" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const schema = try fixtureSchema(a);
    const function = fixtureFunction(schema, "tool::scale");
    const missing = (try std.json.parseFromSlice(Value, a,
        \\{"value":"1"}
    , .{ .allocate = .alloc_always })).value;
    try testing.expectEqualStrings("argument 'factor' is missing", (try invoke.nameRefusal(a, function, missing)).?.reason);
    const extra = (try std.json.parseFromSlice(Value, a,
        \\{"value":"1","factor":"2","extra":"3"}
    , .{ .allocate = .alloc_always })).value;
    try testing.expectEqualStrings("argument 'extra' is not a parameter of the selected function", (try invoke.nameRefusal(a, function, extra)).?.reason);
    const malformed = (try std.json.parseFromSlice(Value, a,
        \\{"value":1,"factor":"2"}
    , .{ .allocate = .alloc_always })).value;
    try testing.expect((try invoke.nameRefusal(a, function, malformed)) == null);
    var codec: wire.Codec = .{ .allocator = a, .types = invoke.types(schema) };
    defer codec.deinit();
    const refusal = (try invoke.arguments(&codec, a, function, malformed)).?;
    try testing.expectEqualStrings("invalid-request", refusal.kind);
    try testing.expectEqualStrings("argument 'value'", refusal.path);
    var accepted: wire.Codec = .{ .allocator = a, .types = invoke.types(schema) };
    defer accepted.deinit();
    const valid = (try std.json.parseFromSlice(Value, a,
        \\{"value":"21","factor":"2"}
    , .{ .allocate = .alloc_always })).value;
    try testing.expect((try invoke.arguments(&accepted, a, function, valid)) == null);
    try testing.expectEqual(@as(usize, 2), accepted.nodes.items.len);
    try testing.expectEqual(@as(u64, 21), accepted.nodes.items[0].bits);
}

// spec: INVOKE-6
test "the generated request schema describes decimal-string integers" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const schema = try fixtureSchema(a);
    const request = try schema_json.request(a, invoke.types(schema), fixtureFunction(schema, "tool::scale"));
    try testing.expectEqualStrings("object", request.object.get("type").?.string);
    try testing.expectEqual(false, request.object.get("additionalProperties").?.bool);
    try testing.expectEqualStrings(schema_json.signed_pattern, propertyPattern(request, "value"));
    try testing.expectEqualStrings(schema_json.signed_pattern, propertyPattern(request, "factor"));
    try testing.expectEqualStrings("i64", request.object.get("properties").?.object.get("value").?.object.get("x-mylang-type").?.string);
    try testing.expect(!request.object.contains("effects"));
    try testing.expect(!request.object.contains("mutates"));
    try testing.expect(std.mem.indexOf(u8, request.object.get("$comment").?.string, "not the language-contract graph") != null);
}

// spec-case: INVOKE-6
test "the generated schema follows the nominal shape of a nested result" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const schema = try fixtureSchema(a);
    const sample = try schema_json.typeSchema(a, invoke.types(schema), "tool::Sample", 0);
    const span = sample.object.get("properties").?.object.get("span").?;
    try testing.expectEqualStrings("object", span.object.get("type").?.string);
    try testing.expectEqualStrings("tool::Span", span.object.get("x-mylang-type").?.string);
    const weights = sample.object.get("properties").?.object.get("weights").?;
    try testing.expectEqualStrings("array", weights.object.get("type").?.string);
    try testing.expectEqual(@as(i64, 3), weights.object.get("minItems").?.integer);
    const ratio = try schema_json.typeSchema(a, invoke.types(schema), "tool::Ratio", 0);
    try testing.expectEqual(@as(usize, 2), ratio.object.get("oneOf").?.array.items.len);
    const metres = try schema_json.typeSchema(a, invoke.types(schema), "tool::Metres", 0);
    try testing.expectEqualStrings("tool::Metres", metres.object.get("x-mylang-domain").?.string);
    try testing.expectError(error.InvalidSchema, schema_json.typeSchema(a, invoke.types(schema), "str", 0));
    var codec: wire.Codec = .{ .allocator = a, .types = invoke.types(schema) };
    defer codec.deinit();
    const request = try schema_json.request(a, invoke.types(schema), fixtureFunction(schema, "tool::announce"));
    try testing.expectEqual(@as(usize, 1), request.object.get("required").?.array.items.len);
    try testing.expectEqualStrings("value", request.object.get("required").?.array.items[0].string);
}

// spec: INVOKE-7
test "describe resolves no native toolchain while an executing session does" {
    var environment: std.process.Environ.Map = .init(testing.allocator);
    defer environment.deinit();
    var context = try fs.Context.init(testing.allocator, testing.io, &environment);
    defer context.deinit();
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    const root = try temporary.dir.realPathFileAlloc(context.io, ".", context.allocator);
    const entry = try std.fs.path.join(context.allocator, &.{ root, "main.my" });
    try context.write(entry, "module main\n\n\ndef main() -> int:\n    return 0\n");
    const opts: options.Options = .{
        .source = entry,
        .cache = try std.fs.path.join(context.allocator, &.{ root, "cache" }),
        .zig = "no-such-zig-tool",
        .qbe = "no-such-qbe-tool",
    };
    const frontend = try sessions.Session.initFrontend(context, opts);
    defer context.remove(frontend.temporary);
    try testing.expectEqualStrings("", frontend.tools.zig);
    try testing.expectEqualStrings("", frontend.tools.qbe);
    try testing.expectEqual(@as(usize, 64), frontend.hashes[0].len);
    try testing.expectEqualStrings(entry, frontend.source.entry_path);
    try testing.expectError(error.ToolNotFound, sessions.Session.init(context, opts));
}

// spec: INVOKE-8
test "the invoke command line rejects a malformed request before anything runs" {
    try testing.expectError(error.InvalidInvocationArguments, command.parse(&.{"main.my"}));
    try testing.expectError(error.InvalidInvocationArguments, command.parse(&.{ "main.my", "--function", "tool::scale" }));
    try testing.expectError(error.InvalidInvocationArguments, command.parse(&.{ "main.my", "--function=tool::scale", "--describe", "--input=r.json" }));
    try testing.expectError(error.InvalidInvocationArguments, command.parse(&.{ "main.my", "--function=tool::scale", "--describe", "--format=xml" }));
    try testing.expectError(error.InvalidInvocationArguments, command.parse(&.{ "main.my", "--function=tool::scale", "--input=r.json", "--timeout=0" }));
    try testing.expectError(error.InvalidInvocationArguments, command.parse(&.{ "main.my", "--function=tool::scale", "--input=r.json", "--max-memory=12x" }));
    try testing.expectError(error.InvalidInvocationArguments, command.parse(&.{ "main.my", "--function=tool::scale", "--input=r.json", "--nonsense" }));
    const accepted: command.Request = try command.parse(&.{ "main.my", "--function=tool::scale", "--input=r.json", "--timeout=30", "--max-steps=100" });
    try testing.expectEqualStrings("tool::scale", accepted.function);
    try testing.expectEqualStrings("r.json", accepted.input.?);
    try testing.expectEqual(@as(?u64, 30), accepted.bounds.timeout_seconds);
    try testing.expectEqual(@as(?u64, 100), accepted.bounds.max_steps);
    const rejection: command.ParseError = error.InvalidInvocationArguments;
    try testing.expectEqualStrings("InvalidInvocationArguments", @errorName(rejection));
}

/// The installed compiler the build names beside `MYLANG_QBE`, plus the project
/// root its three-level install path (`zig-out/bin|focus/qbe`) sits under.
const Tools = struct { compiler: []const u8, root: []const u8 };

fn tools(allocator: std.mem.Allocator) !Tools {
    const qbe = std.testing.environ.getPosix("MYLANG_QBE") orelse return error.ToolNotFound;
    const bin = std.fs.path.dirname(qbe) orelse return error.ToolNotFound;
    const out = std.fs.path.dirname(bin) orelse return error.ToolNotFound;
    const root = std.fs.path.dirname(out) orelse return error.ToolNotFound;
    return .{ .compiler = try std.fs.path.join(allocator, &.{ bin, "mylang" }), .root = try allocator.dupe(u8, root) };
}

/// Invoke one fixture function against a fresh cache and return the CLI's stdout.
fn invocation(allocator: std.mem.Allocator, resolved: Tools, name: []const u8, request: []const u8) ![]const u8 {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const entry = try std.fs.path.join(a, &.{ resolved.root, "tests", "invoke", "tool.my" });
    const input = try std.fs.path.join(a, &.{ resolved.root, "tests", "invoke", "requests", try std.fmt.allocPrint(a, "{s}.json", .{request}) });
    const flag = try std.fmt.allocPrint(a, "--input={s}", .{input});
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const cache = try temporary.dir.realPathFileAlloc(std.testing.io, ".", a);
    const result = try std.process.run(a, std.testing.io, .{
        .argv = &.{ resolved.compiler, "invoke", entry, "--function", name, flag, "--cache-dir", cache },
        .cwd = .inherit,
    });
    if (fs.exitCode(result.term) != 0) try std.Io.File.stderr().writeStreamingAll(std.testing.io, result.stderr);
    try testing.expectEqual(@as(u8, 0), fs.exitCode(result.term));
    return allocator.dupe(u8, result.stdout);
}

// spec: INVOKE-9
test "a nested record argument executes through the copied-value adapter" {
    const a = testing.allocator;
    const resolved = try tools(a);
    defer a.free(resolved.compiler);
    defer a.free(resolved.root);
    const stdout = try invocation(a, resolved, "tool::sample_label", "sample");
    defer a.free(stdout);
    try testing.expect(std.mem.indexOf(u8, stdout, "\"status\":\"completed\"") != null);
    try testing.expect(std.mem.indexOf(u8, stdout, "\"value\":\"7\"") != null);
    try testing.expect(std.mem.endsWith(u8, resolved.compiler, "mylang"));
}
