//! Validates bounded board documents, resolves pin references, and emits deterministic reports.
//! Geometry uses integer micrometers throughout validation and SVG serialization.
const std = @import("std");
const A = std.mem.Allocator;
const V = std.json.Value;
const Ref = struct { component: []const u8, pin: []const u8 };
const Component = struct { id: []const u8, x: i64, y: i64, width: i64, height: i64, pins: []const []const u8 };
const Net = struct { id: []const u8, members: []Ref };
const Finding = struct { code: []const u8, subjects: []const []const u8 };
const NetReport = struct { id: []const u8, members: []const Ref, span: i64 };
const Result = struct { unit: []const u8 = "um", findings: []const Finding, nets: []const NetReport, svg: []const u8 };
const Dimensions = struct { width: i64, height: i64 };
const E = error{InvalidBoard};
const invalidRequest = "invalid-request";
const clearanceCode = "clearance";
fn eq(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}
fn less(_: void, a: []const u8, b: []const u8) bool {
    return std.mem.lessThan(u8, a, b);
}
fn refLess(_: void, a: Ref, b: Ref) bool {
    return if (eq(a.component, b.component)) less({}, a.pin, b.pin) else less({}, a.component, b.component);
}
fn refEq(a: Ref, b: Ref) bool {
    return eq(a.component, b.component) and eq(a.pin, b.pin);
}
fn fields(v: V, names: []const []const u8) E!void {
    if (v != .object or v.object.count() != names.len) return error.InvalidBoard;
    for (names) |name| if (!v.object.contains(name)) return error.InvalidBoard;
}
fn get(v: V, key: []const u8) V {
    return v.object.get(key).?;
}
fn list(v: V, max: usize) E![]V {
    if (v != .array or v.array.items.len > max) return error.InvalidBoard;
    return v.array.items;
}
fn int(v: V, min: i64, max: i64) E!i64 {
    if (v != .number_string) return error.InvalidBoard;
    const n = std.fmt.parseInt(i64, v.number_string, 10) catch return error.InvalidBoard;
    if (n < min or n > max) return error.InvalidBoard;
    return n;
}
fn id(v: V) E![]const u8 {
    if (v != .string) return error.InvalidBoard;
    const s = v.string;
    if (s.len == 0 or s.len > 32 or s[0] < 'a' or s[0] > 'z') return error.InvalidBoard;
    for (s[1..]) |c| {
        if (c >= 'a' and c <= 'z') continue;
        if (c >= '0' and c <= '9') continue;
        if (c != '_' and c != '-') return error.InvalidBoard;
    }
    return s;
}
fn componentLess(_: void, a: Component, b: Component) bool {
    return less({}, a.id, b.id);
}
fn netLess(_: void, a: Net, b: Net) bool {
    return less({}, a.id, b.id);
}
fn findingLess(_: void, a: Finding, b: Finding) bool {
    if (!eq(a.code, b.code)) return less({}, a.code, b.code);
    for (a.subjects[0..@min(a.subjects.len, b.subjects.len)], b.subjects[0..@min(a.subjects.len, b.subjects.len)]) |x, y| {
        if (!eq(x, y)) return less({}, x, y);
    }
    return a.subjects.len < b.subjects.len;
}
fn encode(a: A, value: anytype) ![]const u8 {
    return std.json.Stringify.valueAlloc(a, value, .{});
}
fn err(a: A, name: []const u8) ![]const u8 {
    return encode(a, .{ .@"error" = name });
}
fn findComponent(cs: []const Component, name: []const u8) ?Component {
    for (cs) |c| {
        if (eq(c.id, name)) return c;
    }
    return null;
}
fn hasPin(c: Component, pin: []const u8) bool {
    for (c.pins) |p| {
        if (eq(p, pin)) return true;
    }
    return false;
}
fn uniqueRefs(refs: []Ref) []Ref {
    std.mem.sort(Ref, refs, {}, refLess);
    var n: usize = 0;
    for (refs) |r| {
        if (n == 0 or !refEq(refs[n - 1], r)) {
            refs[n] = r;
            n += 1;
        }
    }
    return refs[0..n];
}
fn addFinding(a: A, fs: *std.ArrayList(Finding), code: []const u8, subjects: []const []const u8) !void {
    try fs.append(a, .{ .code = code, .subjects = try a.dupe([]const u8, subjects) });
}
fn components(a: A, value: V, scale: i64) ![]Component {
    const cv = try list(value, 128);
    const cs = try a.alloc(Component, cv.len);
    for (cv, cs) |c, *out| {
        try fields(c, &.{ "id", "x", "y", "width", "height", "pins" });
        const pv = try list(get(c, "pins"), 32);
        const pins = try a.alloc([]const u8, pv.len);
        for (pv, pins) |p, *dest| dest.* = try id(p);
        std.mem.sort([]const u8, pins, {}, less);
        for (pins, 0..) |p, i| if (i > 0 and eq(p, pins[i - 1])) return error.InvalidBoard;
        out.* = .{
            .id = try id(get(c, "id")),
            .x = (try int(get(c, "x"), -1000000, 1000000)) * scale,
            .y = (try int(get(c, "y"), -1000000, 1000000)) * scale,
            .width = (try int(get(c, "width"), 1, 1000000)) * scale,
            .height = (try int(get(c, "height"), 1, 1000000)) * scale,
            .pins = pins,
        };
    }
    return cs;
}
fn nets(a: A, value: V) ![]Net {
    const nv = try list(value, 128);
    const ns = try a.alloc(Net, nv.len);
    for (nv, ns) |n, *out| {
        try fields(n, &.{ "id", "members" });
        const mv = try list(get(n, "members"), 128);
        const members = try a.alloc(Ref, mv.len);
        for (mv, members) |m, *dest| {
            try fields(m, &.{ "component", "pin" });
            dest.* = .{ .component = try id(get(m, "component")), .pin = try id(get(m, "pin")) };
        }
        std.mem.sort(Ref, members, {}, refLess);
        out.* = .{ .id = try id(get(n, "id")), .members = members };
    }
    return ns;
}
fn duplicateIds(a: A, values: anytype) !std.ArrayList([]const u8) {
    var duplicates: std.ArrayList([]const u8) = .empty;
    for (values, 0..) |value, i| {
        if (i == 0 or !eq(value.id, values[i - 1].id)) continue;
        if (duplicates.items.len > 0 and eq(duplicates.items[duplicates.items.len - 1], value.id)) continue;
        try duplicates.append(a, value.id);
    }
    return duplicates;
}
fn board(a: A, v: V) ![]const u8 {
    try fields(v, &.{ "version", "unit", "width", "height", clearanceCode, "components", "nets" });
    _ = try int(get(v, "version"), 1, 1);
    const unit = get(v, "unit");
    if (unit != .string) return error.InvalidBoard;
    if (!eq(unit.string, "um") and !eq(unit.string, "mm")) return error.InvalidBoard;
    const scale: i64 = if (eq(unit.string, "mm")) 1000 else 1;
    const w = (try int(get(v, "width"), 1, 1000000)) * scale;
    const h = (try int(get(v, "height"), 1, 1000000)) * scale;
    const clearance = (try int(get(v, clearanceCode), 0, 1000000)) * scale;
    const cs = try components(a, get(v, "components"), scale);
    const ns = try nets(a, get(v, "nets"));
    std.mem.sort(Component, cs, {}, componentLess);
    std.mem.sort(Net, ns, {}, netLess);
    const dc = try duplicateIds(a, cs);
    const dn = try duplicateIds(a, ns);
    if (dc.items.len + dn.items.len > 0) return encode(a, .{ .@"error" = "duplicate-id", .components = dc.items, .nets = dn.items });
    var unknown: std.ArrayList(Ref) = .empty;
    var all: std.ArrayList(Ref) = .empty;
    for (ns) |n| for (n.members) |r| {
        try all.append(a, r);
        const c = findComponent(cs, r.component);
        if (c == null or !hasPin(c.?, r.pin)) try unknown.append(a, r);
    };
    if (unknown.items.len > 0) return encode(a, .{ .@"error" = "unknown-pin", .refs = uniqueRefs(unknown.items) });
    std.mem.sort(Ref, all.items, {}, refLess);
    var reused: std.ArrayList(Ref) = .empty;
    for (all.items, 0..) |r, i| if (i > 0 and refEq(r, all.items[i - 1])) {
        try reused.append(a, r);
    };
    if (reused.items.len > 0) return encode(a, .{ .@"error" = "reused-pin", .refs = uniqueRefs(reused.items) });
    return report(a, cs, ns, all.items, .{ .width = w, .height = h }, clearance);
}
fn report(a: A, cs: []const Component, ns: []const Net, refs: []const Ref, size: Dimensions, clearance: i64) ![]const u8 {
    var fs: std.ArrayList(Finding) = .empty;
    for (cs, 0..) |c, i| {
        if (c.x < 0 or c.y < 0 or c.x + c.width > size.width or c.y + c.height > size.height) try addFinding(a, &fs, "outside-board", &.{c.id});
        for (cs[i + 1 ..]) |d| {
            const gx: i128 = @max(0, @max(c.x - (d.x + d.width), d.x - (c.x + c.width)));
            const gy: i128 = @max(0, @max(c.y - (d.y + d.height), d.y - (c.y + c.height)));
            const overlap = c.x < d.x + d.width and d.x < c.x + c.width and c.y < d.y + d.height and d.y < c.y + c.height;
            if (overlap or gx * gx + gy * gy < @as(i128, clearance) * clearance) try addFinding(a, &fs, clearanceCode, &.{ c.id, d.id });
        }
        for (c.pins) |p| {
            var connected = false;
            for (refs) |r| if (eq(r.component, c.id) and eq(r.pin, p)) {
                connected = true;
                break;
            };
            if (!connected) try addFinding(a, &fs, "unconnected-pin", &.{ c.id, p });
        }
    }
    const reports = try a.alloc(NetReport, ns.len);
    for (ns, reports) |n, *r| {
        if (n.members.len < 2) try addFinding(a, &fs, "underconnected-net", &.{n.id});
        var minx: i64 = std.math.maxInt(i64);
        var miny = minx;
        var maxx: i64 = std.math.minInt(i64);
        var maxy = maxx;
        for (n.members) |m| {
            const c = findComponent(cs, m.component).?;
            const x = 2 * c.x + c.width;
            const y = 2 * c.y + c.height;
            minx = @min(minx, x);
            miny = @min(miny, y);
            maxx = @max(maxx, x);
            maxy = @max(maxy, y);
        }
        r.* = .{ .id = n.id, .members = n.members, .span = if (n.members.len == 0) 0 else @divTrunc(maxx - minx + maxy - miny + 1, 2) };
    }
    std.mem.sort(Finding, fs.items, {}, findingLess);
    var svg: std.Io.Writer.Allocating = .init(a);
    try svg.writer.print("<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 {d} {d}\"><rect x=\"0\" y=\"0\" width=\"{d}\" height=\"{d}\" fill=\"white\" stroke=\"black\"/>", .{ size.width, size.height, size.width, size.height });
    for (cs) |c| try svg.writer.print("<rect id=\"{s}\" x=\"{d}\" y=\"{d}\" width=\"{d}\" height=\"{d}\" fill=\"none\" stroke=\"black\"/>", .{ c.id, c.x, c.y, c.width, c.height });
    try svg.writer.writeAll("</svg>");
    return encode(a, Result{ .findings = fs.items, .nets = reports, .svg = svg.written() });
}
// Preflight container depth without counting braces inside escaped JSON strings.
fn depthValid(s: []const u8) bool {
    var depth: usize = 0;
    var quoted = false;
    var escaped = false;
    for (s) |c| {
        if (quoted) {
            if (escaped) {
                escaped = false;
            } else if (c == '\\') {
                escaped = true;
            } else if (c == '"') {
                quoted = false;
            }
        } else if (c == '"') {
            quoted = true;
        } else if (c == '{' or c == '[') {
            depth += 1;
            if (depth > 64) return false;
        } else if (c == '}' or c == ']') {
            if (depth == 0) return false;
            depth -= 1;
        }
    }
    return depth == 0;
}
fn numbersValid(v: V) bool {
    switch (v) {
        .number_string => |s| {
            if (std.mem.indexOfAny(u8, s, ".eE") == null) {
                _ = std.fmt.parseInt(i64, s, 10) catch return false;
            } else {
                const f = std.fmt.parseFloat(f64, s) catch return false;
                if (!std.math.isFinite(f)) return false;
            }
        },
        .array => |xs| for (xs.items) |x| {
            if (!numbersValid(x)) return false;
        },
        .object => |o| for (o.values()) |x| {
            if (!numbersValid(x)) return false;
        },
        else => {},
    }
    return true;
}
fn run(a: A, input: []const u8) ![]const u8 {
    if (input.len > 1024 * 1024) return err(a, invalidRequest);
    if (!std.unicode.utf8ValidateSlice(input) or !depthValid(input)) return err(a, invalidRequest);
    const parsed = std.json.parseFromSlice(V, a, input, .{ .parse_numbers = false, .duplicate_field_behavior = .@"error" }) catch return err(a, invalidRequest);
    defer parsed.deinit();
    const root = parsed.value;
    if (!numbersValid(root) or root != .object) return err(a, invalidRequest);
    if (root.object.count() != 1 or !root.object.contains("cases")) return err(a, invalidRequest);
    const cases = list(get(root, "cases"), 64) catch return err(a, invalidRequest);
    var out: std.Io.Writer.Allocating = .init(a);
    try out.writer.writeAll("{\"results\":[");
    for (cases, 0..) |v, i| {
        if (i > 0) try out.writer.writeAll(",");
        const result = board(a, v) catch |e| switch (e) {
            error.InvalidBoard => try err(a, "invalid-board"),
            else => return e,
        };
        try out.writer.writeAll(result);
    }
    try out.writer.writeAll("]}");
    return out.written();
}
/// Reads one bounded JSON request and writes its deterministic response.
pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var threaded = std.Io.Threaded.init(a, .{});
    defer threaded.deinit();
    const io = threaded.io();
    var buf: [8192]u8 = undefined;
    var reader = std.Io.File.stdin().readerStreaming(io, &buf);
    var input: std.ArrayList(u8) = .empty;
    reader.interface.appendRemaining(a, &input, .limited(1024 * 1024 + 1)) catch |e| switch (e) {
        error.StreamTooLong => {
            try std.Io.File.stdout().writeStreamingAll(io, "{\"error\":\"invalid-request\"}\n");
            return;
        },
        else => return e,
    };
    const output = try run(a, input.items);
    try std.Io.File.stdout().writeStreamingAll(io, output);
    try std.Io.File.stdout().writeStreamingAll(io, "\n");
}

test "transport rejects globally invalid numbers and duplicate decoded keys" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const inputs = [_][]const u8{
        "{\"cases\":[],\"ca\\u0073es\":[]}",
        "{\"cases\":[{\"x\":9223372036854775808}]}",
        "{\"cases\":[{\"x\":-9223372036854775809}]}",
        "{\"cases\":[{\"x\":1e999}]}",
        "{\"cases\":[]} true",
        "{\"cases\":[\"\xff\"]}",
    };
    for (inputs) |input| try std.testing.expectEqualStrings("{\"error\":\"invalid-request\"}", try run(a, input));
    try std.testing.expectEqualStrings("{\"results\":[{\"error\":\"invalid-board\"}]}", try run(a, "{\"cases\":[-9223372036854775808]}"));
}
test "nesting includes root but ignores escaped delimiters" {
    var s: [130]u8 = undefined;
    @memset(s[0..64], '[');
    @memset(s[64..128], ']');
    try std.testing.expect(depthValid(s[0..128]));
    @memset(s[0..65], '[');
    @memset(s[65..130], ']');
    try std.testing.expect(!depthValid(&s));
    try std.testing.expect(depthValid("[\"\\\"[{}]\\\"\"]"));
}
test "schema rejects floating integers and repeated pins" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const prefix = "{\"cases\":[{\"version\":1,\"unit\":\"um\",\"width\":10,\"height\":10,\"clearance\":0,\"nets\":[],\"components\":";
    const suffix = "}]}";
    try std.testing.expectEqualStrings("{\"results\":[{\"error\":\"invalid-board\"}]}", try run(a, prefix ++ "[{\"id\":\"a\",\"x\":0.0,\"y\":0,\"width\":1,\"height\":1,\"pins\":[]}]" ++ suffix));
    try std.testing.expectEqualStrings("{\"results\":[{\"error\":\"invalid-board\"}]}", try run(a, prefix ++ "[{\"id\":\"a\",\"x\":0,\"y\":0,\"width\":1,\"height\":1,\"pins\":[\"p\",\"p\"]}]" ++ suffix));
}

test "schema helpers preserve InvalidBoard for malformed domain values" {
    try std.testing.expectError(error.InvalidBoard, fields(.null, &.{}));
    try std.testing.expectError(error.InvalidBoard, list(.null, 128));
    try std.testing.expectError(error.InvalidBoard, int(.{ .number_string = "1.0" }, 0, 10));
    try std.testing.expectError(error.InvalidBoard, int(.{ .number_string = "11" }, 0, 10));
    try std.testing.expectError(error.InvalidBoard, id(.{ .string = "a!" }));
    try std.testing.expectError(error.InvalidBoard, id(.{ .string = "" }));
    try std.testing.expectEqualStrings("a-z_9", try id(.{ .string = "a-z_9" }));
}
fn fixtureComponent(name: []const u8, x: i64, y: i64) Component {
    return .{ .id = name, .x = x, .y = y, .width = 1, .height = 1, .pins = &.{} };
}
fn expectFindings(allocator: A, cs: []const Component, ns: []const Net, refs: []const Ref, clearance: i64, expected: []const Finding) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const output = try report(a, cs, ns, refs, .{ .width = 10, .height = 10 }, clearance);
    const parsed = try std.json.parseFromSlice(V, a, output, .{});
    const actual = try encode(a, get(parsed.value, "findings"));
    try std.testing.expectEqualStrings(try encode(a, expected), actual);
}
// spec: EDA-OUTSIDE-1
test "outside board includes negative placement and permits exact board edges" {
    const cs = [_]Component{ fixtureComponent("a", -1, 0), fixtureComponent("b", 9, 9) };
    try expectFindings(std.testing.allocator, &cs, &.{}, &.{}, 0, &.{.{ .code = "outside-board", .subjects = &.{"a"} }});
}
// spec: EDA-CLEARANCE-1
test "clearance exact equality passes while overlap fails at zero" {
    const separated = [_]Component{ fixtureComponent("a", 0, 0), fixtureComponent("b", 4, 5) };
    try expectFindings(std.testing.allocator, &separated, &.{}, &.{}, 5, &.{});
    const collision = [_]Finding{.{ .code = clearanceCode, .subjects = &.{ "a", "b" } }};
    try expectFindings(std.testing.allocator, &separated, &.{}, &.{}, 6, &collision);
    const touching = [_]Component{ fixtureComponent("a", 0, 0), fixtureComponent("b", 1, 0) };
    try expectFindings(std.testing.allocator, &touching, &.{}, &.{}, 0, &.{});
    const overlapping = [_]Component{ fixtureComponent("a", 0, 0), fixtureComponent("b", 0, 0) };
    try expectFindings(std.testing.allocator, &overlapping, &.{}, &.{}, 0, &collision);
}
// spec: EDA-UNDERCONNECTED-1
test "nets with fewer than two members produce underconnected findings" {
    const cs = [_]Component{ fixtureComponent("a", 0, 0), fixtureComponent("b", 5, 5) };
    var refs = [_]Ref{ .{ .component = "a", .pin = "p" }, .{ .component = "b", .pin = "p" } };
    const ns = [_]Net{
        .{ .id = "empty", .members = &.{} },
        .{ .id = "full", .members = &refs },
        .{ .id = "single", .members = refs[0..1] },
    };
    try expectFindings(std.testing.allocator, &cs, &ns, &refs, 0, &.{
        .{ .code = "underconnected-net", .subjects = &.{"empty"} },
        .{ .code = "underconnected-net", .subjects = &.{"single"} },
    });
}
// spec: EDA-UNCONNECTED-1
test "only pins absent from every net produce unconnected findings" {
    var c = fixtureComponent("a", 0, 0);
    c.pins = &.{ "p", "q" };
    const refs = [_]Ref{.{ .component = "a", .pin = "p" }};
    try expectFindings(std.testing.allocator, &.{c}, &.{}, &refs, 0, &.{.{ .code = "unconnected-pin", .subjects = &.{ "a", "q" } }});
}
