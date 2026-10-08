//! Declarative cases and provider overlays retain original module paths. Provider
//! paths must be existing dependencies, and cases never silently discard tests.
const std = @import("std");
const language = @import("mylang");
const frontend = @import("frontend.zig");
const discover = @import("test_runner_discover.zig");
const v = @import("property_value.zig");
const equivalent = @import("property_validate.zig").equivalent;
const providers_key = "providers";
pub const Error = error{ OutOfMemory, InvalidTestCases, UnknownTestCase, InvalidTestProviders, ProviderSignatureChanged, ReadFailed };
/// Owned parsed document under the command arena.
pub const File = struct { path: ?[]const u8 = null, document: std.json.Value = .null, bytes: []const u8 = "" };
/// Cases sharing one provider graph can be checked and built together.
pub const Group = struct { providers: []const frontend.Provider, cases: []const discover.Case };

/// Explicit file or the old runner's sibling FILE.cases.json convention.
pub fn load(a: std.mem.Allocator, io: std.Io, entry: []const u8, explicit: ?[]const u8) Error!File {
    const inferred = try defaultPath(a, entry);
    const path = explicit orelse inferred;
    const bytes = std.Io.Dir.cwd().readFileAlloc(io, path, a, .limited(16 << 20)) catch |err| {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        if (explicit == null and err == error.FileNotFound) return .{};
        return error.ReadFailed;
    };
    const value = std.json.parseFromSliceLeaky(std.json.Value, a, bytes, .{}) catch |err| {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        return error.InvalidTestCases;
    };
    if (value != .object) return error.InvalidTestCases;
    return .{ .path = std.Io.Dir.cwd().realPathFileAlloc(io, path, a) catch path, .document = value, .bytes = bytes };
}

/// The inferred cases path must be recorded even when the optional file is absent.
pub fn defaultPath(a: std.mem.Allocator, entry: []const u8) Error![]const u8 {
    return std.fmt.allocPrint(a, "{s}.cases.json", .{if (std.mem.endsWith(u8, entry, ".my")) entry[0 .. entry.len - 3] else entry});
}

/// Distinct provider maps matching the child filter, for dependency discovery.
/// Child validation still owns case names, filters, signatures and execution.
pub fn providerSets(a: std.mem.Allocator, file: File, filter: []const u8) Error![]const []const frontend.Provider {
    if (file.document == .null) return &.{};
    if (file.document != .object) return error.InvalidTestCases;
    var result: std.ArrayList([]const frontend.Provider) = .empty;
    var fields = file.document.object.iterator();
    while (fields.next()) |item| {
        if (item.value_ptr.* != .object) return error.InvalidTestCases;
        if (!discover.matches(filter, item.key_ptr.*)) continue;
        const providers = try overlays(a, v.get(item.value_ptr.*, providers_key));
        if (providers.len == 0) continue;
        var duplicate = false;
        for (result.items) |previous| duplicate = duplicate or same(previous, providers);
        if (!duplicate) try result.append(a, providers);
    }
    return result.items;
}

/// Validate every name and field, including cases outside the current filter.
pub fn validate(file: File, cases: []const discover.Case) Error!void {
    if (file.document == .null) return;
    var entries = file.document.object.iterator();
    while (entries.next()) |item| {
        var found = false;
        for (cases) |case| found = found or std.mem.eql(u8, case.name, item.key_ptr.*);
        if (!found) return error.UnknownTestCase;
        if (item.value_ptr.* != .object) return error.InvalidTestCases;
        var fields = item.value_ptr.object.iterator();
        while (fields.next()) |setting| {
            const name = setting.key_ptr.*;
            if (!allowedField(name)) return error.InvalidTestCases;
        }
        const arguments = v.get(item.value_ptr.*, "arguments");
        const skip = v.get(item.value_ptr.*, "skip");
        const providers = v.get(item.value_ptr.*, providers_key);
        if (arguments != .null and arguments != .object) return error.InvalidTestCases;
        if (skip != .null and skip != .string) return error.InvalidTestCases;
        if (providers != .null and providers != .object) return error.InvalidTestCases;
    }
}

/// Retain one checked graph per distinct map of provider sources.
pub fn groups(a: std.mem.Allocator, file: File, cases: []const discover.Case) Error![]const Group {
    var result: std.ArrayList(Group) = .empty;
    var lists: std.ArrayList(std.ArrayList(discover.Case)) = .empty;
    for (cases) |case| {
        const providers = try overlays(a, v.get(v.get(file.document, case.name), providers_key));
        var index: ?usize = null;
        for (result.items, 0..) |group, position| if (same(group.providers, providers)) {
            index = position;
        };
        if (index == null) {
            index = result.items.len;
            try result.append(a, .{ .providers = providers, .cases = &.{} });
            try lists.append(a, .empty);
        }
        try lists.items[index.?].append(a, case);
    }
    for (result.items, lists.items) |*group, list| group.cases = list.items;
    return result.items;
}

/// A provider may replace an existing dependency, never the entry or a new path.
pub fn available(providers: []const frontend.Provider, session: *const frontend.Session, entry: []const u8) Error!void {
    for (providers) |provider| {
        var found = false;
        for (session.project.modules.items) |module| if (std.mem.eql(u8, module.src.path, provider.path)) {
            if (std.mem.eql(u8, module.name, entry)) return error.InvalidTestProviders;
            found = true;
        };
        if (!found) return error.InvalidTestProviders;
    }
}

/// Provider bodies may change; their interfaces may not. Each replaced module's
/// own exported types and functions keep their checked structure, and so does
/// each selected test's signature: its parameter and result types and every type
/// they reach, including callbacks, aliases and union payloads. Other modules'
/// exports (say, of a module the provider no longer imports) are not compared.
pub fn compatible(a: std.mem.Allocator, original: *frontend.Session, replacement: *frontend.Session, original_checked: frontend.Checked, replacement_checked: frontend.Checked, group: Group) Error!void {
    const left = try publicSchema(a, original, original_checked);
    const right = try publicSchema(a, replacement, replacement_checked);
    for (group.providers) |provider| {
        const prefix = try modulePrefix(a, provider.path);
        if (!sameModuleItems(left, right, "types", prefix)) return error.ProviderSignatureChanged;
        if (!sameModuleItems(left, right, "functions", prefix)) return error.ProviderSignatureChanged;
    }
    for (group.cases) |case| {
        const old = schemaFunction(left, case.name) orelse return error.ProviderSignatureChanged;
        const new = schemaFunction(right, case.name) orelse return error.ProviderSignatureChanged;
        for (signature_fields) |field| if (!equivalent(v.get(old, field), v.get(new, field))) return error.ProviderSignatureChanged;
        if (!try sameReachedTypes(a, left, right, old)) return error.ProviderSignatureChanged;
    }
}

/// The schema fields of a function that make up a selected test's signature.
const signature_fields = [_][]const u8{ "parameters", "result" };

/// `dir/name.my` declares `dir.name::` items.
fn modulePrefix(a: std.mem.Allocator, path: []const u8) Error![]const u8 {
    const module = try a.dupe(u8, path[0 .. path.len - ".my".len]);
    std.mem.replaceScalar(u8, module, '/', '.');
    return std.fmt.allocPrint(a, "{s}::", .{module});
}

/// The items of one module under `key` match one to one, by name and structure.
fn sameModuleItems(left: std.json.Value, right: std.json.Value, key: []const u8, prefix: []const u8) bool {
    var count: usize = 0;
    for (v.array(v.get(left, key))) |item| {
        const name = v.text(v.get(item, "name"));
        if (!std.mem.startsWith(u8, name, prefix)) continue;
        count += 1;
        const other = (if (std.mem.eql(u8, key, "types")) schemaType(right, name) else schemaFunction(right, name)) orelse return false;
        if (!equivalent(item, other)) return false;
    }
    for (v.array(v.get(right, key))) |item| {
        if (std.mem.startsWith(u8, v.text(v.get(item, "name")), prefix)) count -%= 1;
    }
    return count == 0;
}

fn schemaFunction(schema: std.json.Value, name: []const u8) ?std.json.Value {
    for (v.array(v.get(schema, "functions"))) |item| if (std.mem.eql(u8, v.text(v.get(item, "name")), name)) return item;
    return null;
}

fn schemaType(schema: std.json.Value, name: []const u8) ?std.json.Value {
    for (v.array(v.get(schema, "types"))) |item| if (std.mem.eql(u8, v.text(v.get(item, "name")), name)) return item;
    return null;
}

/// Every type name the signature reaches has an equivalent definition in both.
fn sameReachedTypes(a: std.mem.Allocator, left: std.json.Value, right: std.json.Value, signature: std.json.Value) Error!bool {
    var pending: std.ArrayList([]const u8) = .empty;
    var seen: std.StringHashMapUnmanaged(void) = .empty;
    for (signature_fields) |field| try names(a, &pending, v.get(signature, field));
    while (pending.pop()) |name| {
        if ((try seen.getOrPut(a, name)).found_existing) continue;
        const old = schemaType(left, name);
        const new = schemaType(right, name);
        if (old == null and new == null) continue;
        if (old == null or new == null or !equivalent(old.?, new.?)) return false;
        try names(a, &pending, old.?);
    }
    return true;
}

/// Collect every string in `value`; those that name a schema type are followed.
fn names(a: std.mem.Allocator, out: *std.ArrayList([]const u8), value: std.json.Value) Error!void {
    switch (value) {
        .string => |text| try out.append(a, text),
        .array => |items| for (items.items) |item| try names(a, out, item),
        .object => |fields| {
            var entries = fields.iterator();
            while (entries.next()) |entry| try names(a, out, entry.value_ptr.*);
        },
        else => {},
    }
}

fn publicSchema(a: std.mem.Allocator, session: *frontend.Session, checked: frontend.Checked) Error!std.json.Value {
    // Schema rendering reads the already checked program and declaration index.
    // Its check() returns immediately when program is present; merged syntax
    // and lowering state are not required by testRoots or graph rendering.
    var view: language.project_compile.Compilation = .{
        .index = session.interfaceIndex(),
        .src = checked.src,
        .syntax = .{ .nodes = .empty, .statements = .empty, .functions = &.{} },
        .diagnostics = .{ .allocator = a },
        .program = checked.program,
    };
    // The shared checked-facts API exposes the schema rooted at every test,
    // including private @test parameters; it does not lower or invoke a driver.
    const bytes = view.emitNativeTestFactsScoped(a, .all) catch |err| {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        return error.ProviderSignatureChanged;
    };
    const facts = std.json.parseFromSliceLeaky(std.json.Value, a, bytes, .{}) catch |err| {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        return error.ProviderSignatureChanged;
    };
    return std.json.parseFromSliceLeaky(std.json.Value, a, v.text(v.get(facts, "schema")), .{}) catch |err| {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        return error.ProviderSignatureChanged;
    };
}

fn overlays(a: std.mem.Allocator, value: std.json.Value) Error![]const frontend.Provider {
    if (value == .null) return &.{};
    if (value != .object) return error.InvalidTestProviders;
    var found: std.ArrayList(frontend.Provider) = .empty;
    var fields = value.object.iterator();
    while (fields.next()) |item| {
        const path = item.key_ptr.*;
        if (std.fs.path.isAbsolute(path) or !std.mem.endsWith(u8, path, ".my") or item.value_ptr.* != .string) return error.InvalidTestProviders;
        const module = try a.dupe(u8, path[0 .. path.len - 3]);
        std.mem.replaceScalar(u8, module, '/', '.');
        if (!language.project.validName(module)) return error.InvalidTestProviders;
        try found.append(a, .{ .path = path, .text = item.value_ptr.string });
    }
    std.mem.sort(frontend.Provider, found.items, {}, before);
    return found.items;
}
fn before(_: void, left: frontend.Provider, right: frontend.Provider) bool {
    return std.mem.lessThan(u8, left.path, right.path);
}
fn same(left: []const frontend.Provider, right: []const frontend.Provider) bool {
    if (left.len != right.len) return false;
    for (left, right) |a, b| if (!std.mem.eql(u8, a.path, b.path) or !std.mem.eql(u8, a.text, b.text)) return false;
    return true;
}

// spec-case: NEW-CORE-S4-TEST-4
test "provider paths refuse traversal and preserve distinct fixture bodies" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const invalid = try std.json.parseFromSliceLeaky(std.json.Value, a, "{\"../other.my\":\"module other\"}", .{});
    try std.testing.expectError(error.InvalidTestProviders, overlays(a, invalid));
    const one = try std.json.parseFromSliceLeaky(std.json.Value, a, "{\"dep.my\":\"module dep\\n\"}", .{});
    const two = try std.json.parseFromSliceLeaky(std.json.Value, a, "{\"dep.my\":\"module dep\\n# changed\\n\"}", .{});
    try std.testing.expect(!same(try overlays(a, one), try overlays(a, two)));
}

// spec-case: NEW-CORE-S4-TEST-4
test "providerSets preserves distinct closures and defaultPath records absent convention" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try std.testing.expectEqualStrings("dir/app.cases.json", try defaultPath(a, "dir/app.my"));
    const value = try std.json.parseFromSliceLeaky(std.json.Value, a, "{\"one\":{\"providers\":{\"dep.my\":\"module dep\\nimport left\\n\"}}," ++
        "\"same\":{\"providers\":{\"dep.my\":\"module dep\\nimport left\\n\"}}," ++
        "\"other\":{\"providers\":{\"dep.my\":\"module dep\\nimport right\\n\"}}}", .{});
    const sets = try providerSets(a, .{ .document = value }, "");
    try std.testing.expectEqual(@as(usize, 2), sets.len);
    try std.testing.expect(!same(sets[0], sets[1]));
    try std.testing.expectEqual(@as(usize, 1), (try providerSets(a, .{ .document = value }, "other")).len);
    const invalid = try std.json.parseFromSliceLeaky(std.json.Value, a, "{\"one\":{\"providers\":false}}", .{});
    try std.testing.expectError(error.InvalidTestProviders, providerSets(a, .{ .document = invalid }, ""));
}

fn allowedField(name: []const u8) bool {
    for ([_][]const u8{ providers_key, "arguments", "expected", "skip" }) |allowed| if (std.mem.eql(u8, name, allowed)) return true;
    return false;
}

// spec-case: NEW-CORE-S4-TEST-4
test "publicSchema refuses an invalid checked type catalog and propagates allocation failure" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", a);
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "app.my", .data = "module app\n\npublic record Cell:\n    value: int\n\ndef main() -> int:\n    return 0\n" });
    const path = try std.fs.path.join(a, &.{ root, "app.my" });
    var diagnostics: std.ArrayList(u8) = .empty;
    var session = frontend.Session.init(std.testing.allocator, std.testing.io, root);
    defer session.deinit();
    const checked = try session.checkFile(a, path, &diagnostics);
    var damaged = checked;
    damaged.program.records = &.{};
    try std.testing.expectError(error.ProviderSignatureChanged, publicSchema(a, &session, damaged));
    var failing = std.testing.FailingAllocator.init(a, .{ .fail_index = 0 });
    try std.testing.expectError(error.OutOfMemory, publicSchema(failing.allocator(), &session, checked));
}
