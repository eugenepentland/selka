//! Native Zig implementation of the mylang schematic-to-SVG pipeline.
//!
//! This is a faithful port of `experiments/full-svg-benchmark/ports/rust/main.rs`
//! (which is itself a direct transcription of `src/schematic/guest/*.my`,
//! module `main` and the modules it imports) with the host byte interface
//! replaced by whole-document reads. It performs the same parse, validation,
//! model construction, net normalization, placement, routing and SVG
//! serialization, in the same order, with the same integer arithmetic, so its
//! output is byte-identical to the mylang arm of
//! `experiments/full-svg-benchmark`.
//!
//! Usage: `zig-o3 <module.sexp> <pinout.sexp> <interface.sexp> <output.svg>`
//!
//! Success writes the SVG, prints nothing and exits 0. A validation failure
//! prints the first located issue code alone on stdout, exits with that code
//! and writes no SVG — the mylang guest's contract. Only a wrong argument
//! count (or an unreadable input) reports on stderr and exits 2.

const std = @import("std");

/// The allocator every growable list uses. It mirrors Rust's global allocator
/// so the port keeps the reference implementation's shape: no function threads
/// an allocator parameter that the Rust does not thread either.
var global_alloc: std.mem.Allocator = undefined;

/// Allocation failure terminates the process; the harness never exercises it.
fn oom() noreturn {
    std.process.exit(2);
}

/// The mylang issue code carried out of the `Err(code)` paths, mirroring the
/// Rust implementation's `Result<_, i64>`.
var issue_code: i64 = 0;

const Fail = error{Failed};

fn fail(code: i64) Fail {
    issue_code = code;
    return error.Failed;
}

// ── spans and documents ──────────────────────────────────────────────

const Span = struct {
    file: usize,
    start: usize,
    end: usize,

    inline fn len(self: Span) usize {
        return self.end - self.start;
    }

    inline fn isEmpty(self: Span) bool {
        return self.end == self.start;
    }
};

const EMPTY: Span = .{ .file = 0, .start = 0, .end = 0 };

const Ctx = struct {
    docs: [3][]const u8,

    inline fn byte(self: *const Ctx, file: usize, position: usize) u8 {
        return self.docs[file][position];
    }

    /// `text.equal`
    fn equal(self: *const Ctx, a: Span, b: Span) bool {
        if (a.len() != b.len()) return false;
        var i: usize = 0;
        while (i < a.len()) : (i += 1) {
            if (self.byte(a.file, a.start + i) != self.byte(b.file, b.start + i)) return false;
        }
        return true;
    }

    /// `text.matches`
    fn matches(self: *const Ctx, a: Span, b: []const u8) bool {
        if (a.len() != b.len) return false;
        var i: usize = 0;
        while (i < a.len()) : (i += 1) {
            if (self.byte(a.file, a.start + i) != b[i]) return false;
        }
        return true;
    }

    /// `text.number`
    fn number(self: *const Ctx, a: Span) i64 {
        var value: i64 = 0;
        var i = a.start;
        if (i == a.end) return -1;
        while (i < a.end) : (i += 1) {
            const c = self.byte(a.file, i);
            if (c < 48 or c > 57) return -1;
            if (value > 1000000) return -1;
            value = value * 10 + c - 48;
        }
        return value;
    }

    /// `text.identifier`
    fn identifier(self: *const Ctx, a: Span) bool {
        if (a.isEmpty() or a.len() > 64) return false;
        var i = a.start;
        while (i < a.end) : (i += 1) {
            const ch = self.byte(a.file, i);
            if (ch < 33 or ch == 92) return false;
        }
        return true;
    }

    /// `text.folded`
    fn folded(self: *const Ctx, a: Span, b: Span) bool {
        if (a.len() != b.len()) return false;
        var i: usize = 0;
        while (i < a.len()) : (i += 1) {
            if (lower(self.byte(a.file, a.start + i)) != lower(self.byte(b.file, b.start + i))) return false;
        }
        return true;
    }
};

inline fn lower(ch: u8) u8 {
    if (ch >= 65 and ch <= 90) return ch + 32;
    return ch;
}

// ── output buffer ────────────────────────────────────────────────────

const Out = struct {
    bytes: std.ArrayList(u8),

    fn init(capacity: usize) Out {
        var out: Out = .{ .bytes = .empty };
        out.bytes.ensureTotalCapacity(global_alloc, capacity) catch oom();
        return out;
    }

    inline fn put(self: *Out, value: u8) void {
        self.bytes.append(global_alloc, value) catch oom();
    }

    inline fn write(self: *Out, text: []const u8) void {
        self.bytes.appendSlice(global_alloc, text) catch oom();
    }

    /// `text.decimal`
    fn decimal(self: *Out, value: i64) void {
        var buffer: [24]u8 = undefined;
        const negative = value < 0;
        var magnitude: u64 = if (negative) @intCast(-value) else @intCast(value);
        var digits_at: usize = buffer.len;
        while (true) {
            digits_at -= 1;
            buffer[digits_at] = '0' + @as(u8, @intCast(magnitude % 10));
            magnitude /= 10;
            if (magnitude == 0) break;
        }
        if (negative) {
            digits_at -= 1;
            buffer[digits_at] = '-';
        }
        self.write(buffer[digits_at..]);
    }

    /// `text.escaped`
    fn escaped(self: *Out, ctx: *const Ctx, a: Span) void {
        var i = a.start;
        while (i < a.end) {
            var c = ctx.byte(a.file, i);
            i += 1;
            if (c == 92 and i < a.end) {
                c = ctx.byte(a.file, i);
                i += 1;
                if (c == 110) {
                    c = 10;
                } else if (c == 114) {
                    c = 13;
                } else if (c == 116) {
                    c = 9;
                }
            }
            switch (c) {
                9 => self.write("&#9;"),
                10 => self.write("&#10;"),
                13 => self.write("&#13;"),
                38 => self.write("&amp;"),
                60 => self.write("&lt;"),
                62 => self.write("&gt;"),
                34 => self.write("&quot;"),
                else => self.put(c),
            }
        }
    }
};

// ── sexpr ────────────────────────────────────────────────────────────

const Kind = enum { list, atom, str };

const Node = struct {
    kind: Kind,
    span: Span,
    next: usize,
};

/// `sexpr.at`: an out-of-range index is an empty atom whose `next` ends the list.
inline fn at(nodes: []const Node, index: i64) Node {
    if (index < 0 or index >= @as(i64, @intCast(nodes.len))) {
        return .{ .kind = .atom, .span = EMPTY, .next = nodes.len };
    }
    return nodes[@intCast(index)];
}

/// `sexpr.form`
fn form(ctx: *const Ctx, nodes: []const Node, index: i64, name: []const u8) bool {
    const item = at(nodes, index);
    if (item.kind != .list or @as(i64, @intCast(item.next)) == index + 1) return false;
    return ctx.matches(at(nodes, index + 1).span, name);
}

/// `sexpr.parse`
fn parse(ctx: *const Ctx, file: usize) Fail!std.ArrayList(Node) {
    const src = ctx.docs[file];
    const size = src.len;
    var nodes: std.ArrayList(Node) = .empty;
    nodes.ensureTotalCapacity(global_alloc, 1 + size / 8) catch oom();
    var stack: std.ArrayList(usize) = .empty;
    stack.ensureTotalCapacity(global_alloc, 16) catch oom();
    var nesting: usize = 0;
    var p: usize = 0;
    nodes.append(global_alloc, .{
        .kind = .list,
        .span = .{ .file = file, .start = 0, .end = size },
        .next = 0,
    }) catch oom();
    while (p < size) {
        const c = src[p];
        if (c == 32 or c == 9 or c == 10 or c == 13) {
            p += 1;
        } else if (c == 59) {
            while (p < size and src[p] != 10) p += 1;
        } else if (c == 41) {
            if (nesting == 0) return fail(1);
            nesting -= 1;
            const open = stack.items[nesting];
            nodes.items[open].next = nodes.items.len;
            p += 1;
        } else {
            const index = nodes.items.len;
            const start = p;
            if (index == 16384) return fail(5);
            var kind: Kind = .atom;
            if (c == 40) {
                if (nesting == 128) return fail(2);
                if (nesting == stack.items.len) {
                    stack.append(global_alloc, index) catch oom();
                } else {
                    stack.items[nesting] = index;
                }
                nesting += 1;
                kind = .list;
                p += 1;
            } else if (c == 34) {
                kind = .str;
                p += 1;
                var closed = false;
                while (p < size and !closed) {
                    const ch = src[p];
                    p += 1;
                    if (ch == 92) {
                        if (p == size) return fail(3);
                        const escape = src[p];
                        if (escape != 92 and escape != 34 and escape != 110 and escape != 114 and escape != 116) return fail(6);
                        p += 1;
                    } else if (ch == 34) {
                        closed = true;
                    }
                }
                if (!closed) return fail(3);
            } else {
                var scanning = true;
                while (p < size and scanning) {
                    const ch = src[p];
                    if (ch == 40 or ch == 41 or ch == 32 or ch == 9 or ch == 10 or ch == 13 or ch == 59) {
                        scanning = false;
                    } else {
                        p += 1;
                    }
                }
            }
            var span = Span{ .file = file, .start = start, .end = p };
            if (kind == .str) {
                span.start = start + 1;
                span.end = p - 1;
            }
            nodes.append(global_alloc, .{ .kind = kind, .span = span, .next = index + 1 }) catch oom();
        }
    }
    if (nesting != 0) return fail(4);
    nodes.items[0].next = nodes.items.len;
    return nodes;
}

// ── circuit model ────────────────────────────────────────────────────

const Part = struct {
    node: i64,
    reference: Span,
    family: Span,
    value: Span,
    kind: i64,
    pin1: i64,
    pin2: i64,
};

const Pin = struct {
    part: usize,
    number: i64,
    net: Span,
    nc: bool,
    display: Span,
    net_id: i64,
    display_id: i64,
    raw_rail: i64,
    rail: i64,
    decoupling: bool,
};

/// `circuit.body`
fn body(ctx: *const Ctx, nodes: []const Node) i64 {
    var i: i64 = 1;
    while (i < @as(i64, @intCast(nodes.len))) {
        if (form(ctx, nodes, i, "design-block")) return i;
        if (form(ctx, nodes, i, "defmodule")) {
            i += 1;
        } else {
            i = @intCast(at(nodes, i).next);
        }
    }
    return -1;
}

/// `circuit.title`
fn title(ctx: *const Ctx, nodes: []const Node) Span {
    const b = body(ctx, nodes);
    if (b < 0) return EMPTY;
    return at(nodes, b + 2).span;
}

/// `circuit.kind`
fn part_kind(ctx: *const Ctx, family: Span) i64 {
    if (ctx.matches(family, "cap-0402") or ctx.matches(family, "cap-0603")) return 1;
    if (ctx.matches(family, "res-0402")) return 2;
    if (ctx.matches(family, "ind-0402")) return 3;
    return 0;
}

/// `circuit.collectParts`
fn collect_parts(ctx: *const Ctx, nodes: []const Node) Fail!std.ArrayList(Part) {
    var out: std.ArrayList(Part) = .empty;
    const b = body(ctx, nodes);
    if (b < 0) return fail(10);
    var i = b + 3;
    while (i < @as(i64, @intCast(at(nodes, b).next))) {
        if (form(ctx, nodes, i, "instance")) {
            const reference = at(nodes, i + 2);
            const spec = at(nodes, i + 3);
            if (i + 3 >= @as(i64, @intCast(at(nodes, i).next))) return fail(11);
            if (!ctx.identifier(reference.span) or reference.kind != .str) return fail(11);
            var family = spec.span;
            var value = EMPTY;
            if (spec.kind == .list) {
                family = at(nodes, i + 4).span;
                value = at(nodes, i + 5).span;
            }
            if (out.items.len == 128) return fail(5);
            var j: usize = 0;
            while (j < out.items.len) : (j += 1) {
                if (ctx.equal(out.items[j].reference, reference.span)) return fail(12);
            }
            out.append(global_alloc, .{
                .node = i,
                .reference = reference.span,
                .family = family,
                .value = value,
                .kind = part_kind(ctx, family),
                .pin1 = -1,
                .pin2 = -1,
            }) catch oom();
        }
        i = @intCast(at(nodes, i).next);
    }
    return out;
}

/// `circuit.label`
fn pinout_label(ctx: *const Ctx, pinout: []const Node, number: i64) Span {
    var i: i64 = 1;
    while (i < @as(i64, @intCast(pinout.len))) {
        if (form(ctx, pinout, i, "pin") and ctx.number(at(pinout, i + 2).span) == number) {
            return at(pinout, i + 3).span;
        }
        i += 1;
    }
    return EMPTY;
}

/// `circuit.collectPins`
fn collect_pins(
    ctx: *const Ctx,
    nodes: []const Node,
    parts: []const Part,
    pinout: []const Node,
) Fail!std.ArrayList(Pin) {
    var out: std.ArrayList(Pin) = .empty;
    var part: usize = 0;
    while (part < parts.len) : (part += 1) {
        const item = parts[part];
        var f: i64 = @intCast(at(nodes, item.node + 3).next);
        while (f < @as(i64, @intCast(at(nodes, item.node).next))) {
            const nc = form(ctx, nodes, f, "nc-ok");
            if (form(ctx, nodes, f, "pin") or nc) {
                var netindex = f + 2;
                while (netindex < @as(i64, @intCast(at(nodes, f).next)) and at(nodes, netindex).kind != .str) {
                    netindex = @intCast(at(nodes, netindex).next);
                }
                if (netindex == @as(i64, @intCast(at(nodes, f).next)) or netindex == f + 2) return fail(13);
                const net = at(nodes, netindex).span;
                if ((!nc and !ctx.identifier(net)) or net.isEmpty()) return fail(13);
                var p = f + 2;
                while (p < netindex) {
                    const number = ctx.number(at(nodes, p).span);
                    var valid = number == 1 or number == 2;
                    if (item.kind == 0) {
                        const named = pinout_label(ctx, pinout, number);
                        valid = named.end > named.start;
                    }
                    if (!valid) return fail(14);
                    var j: usize = 0;
                    while (j < out.items.len) : (j += 1) {
                        const previous = out.items[j];
                        if (previous.part == part and previous.number == number) return fail(15);
                    }
                    if (out.items.len == 1024) return fail(5);
                    out.append(global_alloc, .{
                        .part = part,
                        .number = number,
                        .net = net,
                        .nc = nc,
                        .display = net,
                        .net_id = -1,
                        .display_id = -1,
                        .raw_rail = 0,
                        .rail = 0,
                        .decoupling = false,
                    }) catch oom();
                    p = @intCast(at(nodes, p).next);
                }
            }
            f = @intCast(at(nodes, f).next);
        }
    }
    return out;
}

/// `circuit.displayNet`
fn display_net(ctx: *const Ctx, net: Span, parts: []const Part, pins: []const Pin) Span {
    var last: i64 = -1;
    var previous: i64 = -1;
    var i = net.start;
    while (i < net.end) : (i += 1) {
        if (ctx.byte(net.file, i) == 46) {
            previous = last;
            last = @intCast(i);
        }
    }
    if (previous <= @as(i64, @intCast(net.start)) or last <= previous + 1 or last + 1 == @as(i64, @intCast(net.end))) {
        return net;
    }
    var base = net;
    base.end = @intCast(previous);
    var reference = net;
    reference.start = @intCast(previous + 1);
    reference.end = @intCast(last);
    var number_span = net;
    number_span.start = @intCast(last + 1);
    const number = ctx.number(number_span);
    var trunk = false;
    var named_host = false;
    var loop_b: usize = 0;
    while (loop_b < pins.len) : (loop_b += 1) {
        const pin = pins[loop_b];
        if (!pin.nc) {
            if (ctx.equal(pin.net, base)) trunk = true;
            if (pin.number == number and
                ctx.equal(pin.net, net) and
                ctx.equal(parts[pin.part].reference, reference)) named_host = true;
        }
    }
    if (trunk and named_host) return base;
    return net;
}

/// `circuit.railKind` / `layout_graph.rail`
fn rail_kind(ctx: *const Ctx, span: Span) i64 {
    if (ctx.matches(span, "GND")) return 1;
    if (span.len() >= 2 and ctx.byte(span.file, span.start) == 86 and ctx.byte(span.file, span.start + 1) == 95) {
        return 2;
    }
    return 0;
}

/// `circuit.normalize`
fn normalize(ctx: *const Ctx, parts: []Part, pins: []Pin) void {
    var i: usize = 0;
    while (i < pins.len) : (i += 1) {
        pins[i].display = display_net(ctx, pins[i].net, parts, pins);
        pins[i].raw_rail = rail_kind(ctx, pins[i].net);
        pins[i].rail = rail_kind(ctx, pins[i].display);
        if (pins[i].number == 1) parts[pins[i].part].pin1 = @intCast(i);
        if (pins[i].number == 2) parts[pins[i].part].pin2 = @intCast(i);
        var raw_id: i64 = -1;
        var j: usize = 0;
        while (j < i) : (j += 1) {
            if (raw_id < 0 and ctx.equal(pins[j].net, pins[i].net)) raw_id = pins[j].net_id;
        }
        if (raw_id < 0) raw_id = @intCast(i);
        pins[i].net_id = raw_id;
    }
    var loop_b: usize = 0;
    while (loop_b < pins.len) : (loop_b += 1) {
        var display_id: i64 = -1;
        var j: usize = 0;
        while (j < pins.len) : (j += 1) {
            if (display_id < 0 and ctx.equal(pins[j].net, pins[loop_b].display)) display_id = pins[j].net_id;
        }
        var j2: usize = 0;
        while (j2 < loop_b) : (j2 += 1) {
            if (display_id < 0 and ctx.equal(pins[j2].display, pins[loop_b].display)) display_id = pins[j2].display_id;
        }
        if (display_id < 0) display_id = @as(i64, @intCast(pins.len)) + @as(i64, @intCast(loop_b));
        pins[loop_b].display_id = display_id;
    }
    var loop_c: usize = 0;
    while (loop_c < pins.len) : (loop_c += 1) {
        const pin = pins[loop_c];
        if (pin.raw_rail == 1 and parts[pin.part].kind == 1) {
            var other_index = parts[pin.part].pin1;
            if (other_index == @as(i64, @intCast(loop_c))) other_index = parts[pin.part].pin2;
            if (other_index >= 0) {
                const other = pins[@intCast(other_index)];
                pins[loop_c].decoupling = other.rail == 2 and
                    other.raw_rail != 1 and
                    other.display_id != other.net_id;
            }
        }
    }
}

// ── validate ─────────────────────────────────────────────────────────

/// `validate.source`
fn validate_source(ctx: *const Ctx, nodes: []const Node) i64 {
    var i: i64 = 1;
    var modules: i64 = 0;
    var blocks: i64 = 0;
    while (i < @as(i64, @intCast(nodes.len))) {
        if (form(ctx, nodes, i, "defmodule")) {
            modules += 1;
            const params = at(nodes, i + 3);
            if (modules != 1 or params.kind != .list or @as(i64, @intCast(params.next)) != i + 4) return 16;
            var f = i + 4;
            while (f < @as(i64, @intCast(at(nodes, i).next))) {
                if (at(nodes, f).kind == .str or form(ctx, nodes, f, "implements")) {
                    // permitted
                } else if (form(ctx, nodes, f, "design-block")) {
                    blocks += 1;
                    if (blocks != 1 or at(nodes, f + 2).kind != .str) return 16;
                    var child = f + 3;
                    while (child < @as(i64, @intCast(at(nodes, f).next))) {
                        if (!form(ctx, nodes, child, "instance") and !metadata(ctx, nodes, child)) return 17;
                        child = @intCast(at(nodes, child).next);
                    }
                } else {
                    return 17;
                }
                f = @intCast(at(nodes, f).next);
            }
        } else if (!form(ctx, nodes, i, "import")) {
            return 17;
        }
        i = @intCast(at(nodes, i).next);
    }
    if (modules != 1 or blocks != 1) return 16;
    return 0;
}

/// `validate.metadata`
fn metadata(ctx: *const Ctx, nodes: []const Node, i: i64) bool {
    const names = [_][]const u8{
        "net-envelope",
        "port",
        "port-group",
        "net-class",
        "pcb-plan",
        "rough",
        "note",
    };
    for (names) |name| {
        if (form(ctx, nodes, i, name)) return true;
    }
    return false;
}

/// `validate.pinoutCheck`
fn pinout_check(ctx: *const Ctx, nodes: []const Node) i64 {
    if (!form(ctx, nodes, 1, "pinout") or
        at(nodes, 1).next != nodes.len or
        at(nodes, 3).kind != .str)
    {
        return 18;
    }
    var count: i64 = 0;
    var i: i64 = 4;
    while (i < @as(i64, @intCast(at(nodes, 1).next))) {
        const number = ctx.number(at(nodes, i + 2).span);
        if (!form(ctx, nodes, i, "pin") or
            @as(i64, @intCast(at(nodes, i).next)) != i + 4 or
            number < 1 or
            number > 41 or
            at(nodes, i + 3).kind != .str or
            !ctx.identifier(at(nodes, i + 3).span))
        {
            return 18;
        }
        var j: i64 = 4;
        while (j < i) {
            if (ctx.number(at(nodes, j + 2).span) == number) return 18;
            j = @intCast(at(nodes, j).next);
        }
        count += 1;
        i = @intCast(at(nodes, i).next);
    }
    if (count != 41) return 18;
    return 0;
}

/// `validate.fields`
fn fields(ctx: *const Ctx, nodes: []const Node, item: Part) i64 {
    const spec = at(nodes, item.node + 3);
    if (item.kind != 0 and
        (spec.kind != .list or
            @as(i64, @intCast(spec.next)) < item.node + 6 or
            at(nodes, item.node + 5).kind != .str))
    {
        return 19;
    }
    if (item.kind == 0 and spec.kind != .atom) return 19;
    var f: i64 = @intCast(spec.next);
    while (f < @as(i64, @intCast(at(nodes, item.node).next))) {
        if (!form(ctx, nodes, f, "pin") and
            !form(ctx, nodes, f, "nc-ok") and
            !form(ctx, nodes, f, "id") and
            !form(ctx, nodes, f, "decouples"))
        {
            return 17;
        }
        if (form(ctx, nodes, f, "nc-ok") and item.kind != 0) return 13;
        if (form(ctx, nodes, f, "pin") or form(ctx, nodes, f, "nc-ok")) {
            var j = f + 2;
            while (j < @as(i64, @intCast(at(nodes, f).next)) and at(nodes, j).kind == .atom) j += 1;
            if (j == f + 2 or at(nodes, j).kind != .str) return 13;
            if (form(ctx, nodes, f, "nc-ok") and
                (j != f + 3 or @as(i64, @intCast(at(nodes, f).next)) != j + 1))
            {
                return 13;
            }
            j += 1;
            while (j < @as(i64, @intCast(at(nodes, f).next))) {
                if (!form(ctx, nodes, j, "i-typ") and !form(ctx, nodes, j, "i-max")) return 17;
                j = @intCast(at(nodes, j).next);
            }
        }
        f = @intCast(at(nodes, f).next);
    }
    return 0;
}

/// `validate.model`
fn validate_model(
    ctx: *const Ctx,
    nodes: []const Node,
    parts: []const Part,
    pins: []const Pin,
    pinout: []const Node,
) i64 {
    const schema = pinout_check(ctx, pinout);
    if (schema != 0) return schema;
    var chips: i64 = 0;
    var p: usize = 0;
    while (p < parts.len) : (p += 1) {
        const item = parts[p];
        const field_error = fields(ctx, nodes, item);
        if (field_error != 0) return field_error;
        if (item.kind == 0) {
            chips += 1;
            if (!ctx.folded(item.family, at(pinout, 3).span)) return 19;
        }
        var count: i64 = 0;
        var j: usize = 0;
        while (j < pins.len) : (j += 1) {
            if (pins[j].part == p) count += 1;
        }
        if ((item.kind == 0 and count != 41) or (item.kind != 0 and count != 2)) return 20;
    }
    if (chips != 1) return 19;
    return 0;
}

// ── ports ────────────────────────────────────────────────────────────

const Port = struct {
    prefix: Span,
    name: Span,
    direction: Span,
};

/// `ports.collect`
fn ports_collect(ctx: *const Ctx, nodes: []const Node, lanes: []const Node) Fail!std.ArrayList(Port) {
    var out: std.ArrayList(Port) = .empty;
    if (!form(ctx, lanes, 1, "interface") or at(lanes, 1).next != lanes.len) return fail(21);
    const b = body(ctx, nodes);
    var i = b + 3;
    while (i < @as(i64, @intCast(at(nodes, b).next))) {
        if (form(ctx, nodes, i, "port")) {
            const name = at(nodes, i + 2);
            const direction = at(nodes, i + 3);
            if (i + 3 >= @as(i64, @intCast(at(nodes, i).next)) or
                name.kind != .str or
                !ctx.identifier(name.span) or
                !direction_ok(ctx, direction.span))
            {
                return fail(21);
            }
            if (out.items.len == 32) return fail(21);
            out.append(global_alloc, .{ .prefix = EMPTY, .name = name.span, .direction = direction.span }) catch oom();
        } else if (form(ctx, nodes, i, "port-group")) {
            const prefix = at(nodes, i + 2).span;
            if (!ctx.identifier(prefix) or !ctx.equal(at(nodes, i + 3).span, at(lanes, 3).span)) return fail(21);
            var rename = i + 4;
            while (rename < @as(i64, @intCast(at(nodes, i).next))) {
                if (!form(ctx, nodes, rename, "rename") or
                    @as(i64, @intCast(at(nodes, rename).next)) != rename + 4 or
                    at(nodes, rename + 3).kind != .str)
                {
                    return fail(21);
                }
                var found = false;
                var lane: i64 = 5;
                while (lane < @as(i64, @intCast(at(lanes, 1).next))) {
                    if (ctx.equal(at(nodes, rename + 2).span, at(lanes, lane + 2).span)) found = true;
                    lane = @intCast(at(lanes, lane).next);
                }
                if (!found) return fail(21);
                rename = @intCast(at(nodes, rename).next);
            }
            var lane: i64 = 5;
            while (lane < @as(i64, @intCast(at(lanes, 1).next))) {
                if (!form(ctx, lanes, lane, "signal") or
                    @as(i64, @intCast(at(lanes, lane).next)) < lane + 4 or
                    !direction_ok(ctx, at(lanes, lane + 3).span))
                {
                    return fail(21);
                }
                var label = at(lanes, lane + 2).span;
                const original = label;
                var pre = prefix;
                var renamed = false;
                var rename2 = i + 4;
                while (rename2 < @as(i64, @intCast(at(nodes, i).next))) {
                    if (ctx.equal(at(nodes, rename2 + 2).span, original)) {
                        if (renamed) return fail(21);
                        renamed = true;
                        label = at(nodes, rename2 + 3).span;
                        pre = EMPTY;
                    }
                    rename2 = @intCast(at(nodes, rename2).next);
                }
                if (!ctx.identifier(label) or out.items.len == 32) return fail(21);
                out.append(global_alloc, .{
                    .prefix = pre,
                    .name = label,
                    .direction = at(lanes, lane + 3).span,
                }) catch oom();
                lane = @intCast(at(lanes, lane).next);
            }
        }
        i = @intCast(at(nodes, i).next);
    }
    return out;
}

/// `ports.direction`
fn direction_ok(ctx: *const Ctx, span: Span) bool {
    return ctx.matches(span, "in") or ctx.matches(span, "out") or ctx.matches(span, "bidi");
}

/// `ports.size`
fn port_size(item: Port) i64 {
    var n: i64 = @intCast(item.name.end - item.name.start);
    if (item.prefix.start != item.prefix.end) {
        n += @as(i64, @intCast(item.prefix.end - item.prefix.start)) + 1;
    }
    return n;
}

/// `ports.byteAt`
fn port_byte(ctx: *const Ctx, item: Port, index: i64) u8 {
    const n: i64 = @intCast(item.prefix.end - item.prefix.start);
    if (n == 0) return ctx.byte(item.name.file, @intCast(@as(i64, @intCast(item.name.start)) + index));
    if (index < n) return ctx.byte(item.prefix.file, @intCast(@as(i64, @intCast(item.prefix.start)) + index));
    if (index == n) return 95;
    return ctx.byte(item.name.file, @intCast(@as(i64, @intCast(item.name.start)) + index - n - 1));
}

/// `ports.equal`
fn port_equal(ctx: *const Ctx, a: Port, b: Port) bool {
    if (port_size(a) != port_size(b)) return false;
    var i: i64 = 0;
    while (i < port_size(a)) : (i += 1) {
        if (port_byte(ctx, a, i) != port_byte(ctx, b, i)) return false;
    }
    return true;
}

/// `ports.validate`
fn ports_validate(ctx: *const Ctx, connections: []const Port, pins: []const Pin) i64 {
    var i: usize = 0;
    while (i < connections.len) : (i += 1) {
        const item = connections[i];
        var j: usize = 0;
        while (j < i) : (j += 1) {
            if (port_equal(ctx, item, connections[j])) return 22;
        }
        var found = false;
        var k: usize = 0;
        while (k < pins.len) : (k += 1) {
            const pin = pins[k];
            const candidate = Port{ .prefix = EMPTY, .name = pin.net, .direction = EMPTY };
            if (!pin.nc and port_equal(ctx, item, candidate)) found = true;
        }
        if (!found) return 23;
    }
    return 0;
}

// ── net graph ────────────────────────────────────────────────────────

const Net = struct {
    span: Span,
    identity: i64,
    group: i64,
    owner: i64,
    distance: i64,
};

const Edge = struct {
    a: usize,
    b: usize,
};

/// `layout_graph.findId`
fn find_id(nets: []const Net, identity: i64) i64 {
    var i: usize = 0;
    while (i < nets.len) : (i += 1) {
        if (nets[i].identity == identity) return @intCast(i);
    }
    return -1;
}

/// `layout_graph.build`
fn graph_build(parts: []const Part, pins: []const Pin) std.ArrayList(Net) {
    var nets: std.ArrayList(Net) = .empty;
    var edges: std.ArrayList(Edge) = .empty;
    var i: usize = 0;
    while (i < pins.len) : (i += 1) {
        const pin = pins[i];
        if (!pin.nc) {
            var present = false;
            var n: usize = 0;
            while (n < nets.items.len) : (n += 1) {
                if (nets.items[n].identity == pin.display_id) present = true;
            }
            if (!present) {
                nets.append(global_alloc, .{
                    .span = pin.display,
                    .identity = pin.display_id,
                    .group = @intCast(nets.items.len),
                    .owner = -1,
                    .distance = 4096,
                }) catch oom();
            }
        }
    }
    var part: usize = 0;
    while (part < parts.len) : (part += 1) {
        if (parts[part].kind != 0) {
            const ai = parts[part].pin1;
            const bi = parts[part].pin2;
            if (ai >= 0 and
                bi >= 0 and
                !pins[@intCast(ai)].nc and
                !pins[@intCast(bi)].nc and
                pins[@intCast(ai)].rail == 0 and
                pins[@intCast(bi)].rail == 0)
            {
                var na: i64 = -1;
                var nb: i64 = -1;
                var ga: i64 = -1;
                var gb: i64 = -1;
                var loop_b: usize = 0;
                while (loop_b < nets.items.len) : (loop_b += 1) {
                    const item = nets.items[loop_b];
                    if (item.identity == pins[@intCast(ai)].display_id) {
                        ga = item.group;
                        na = @intCast(loop_b);
                    }
                    if (item.identity == pins[@intCast(bi)].display_id) {
                        gb = item.group;
                        nb = @intCast(loop_b);
                    }
                }
                if (na >= 0 and nb >= 0) {
                    edges.append(global_alloc, .{ .a = @intCast(na), .b = @intCast(nb) }) catch oom();
                }
                if (ga >= 0 and gb >= 0 and ga != gb) {
                    var loop_c: usize = 0;
                    while (loop_c < nets.items.len) : (loop_c += 1) {
                        if (nets.items[loop_c].group == gb) nets.items[loop_c].group = ga;
                    }
                }
            }
        }
    }
    var loop_d: usize = 0;
    while (loop_d < pins.len) : (loop_d += 1) {
        const pin = pins[loop_d];
        if (!pin.nc and parts[pin.part].kind == 0) {
            var n: usize = 0;
            while (n < nets.items.len) : (n += 1) {
                if (nets.items[n].owner < 0 and nets.items[n].identity == pin.display_id) {
                    nets.items[n].owner = @intCast(loop_d);
                    nets.items[n].distance = 0;
                }
            }
        }
    }
    var changed = true;
    var passes: i64 = 0;
    while (changed and passes < 128) {
        changed = false;
        var loop_e: usize = 0;
        while (loop_e < edges.items.len) : (loop_e += 1) {
            const edge = edges.items[loop_e];
            // Records are values: these are snapshots taken before any update.
            const head = nets.items[edge.a];
            const tail = nets.items[edge.b];
            if (head.distance + 1 < tail.distance or
                (head.owner >= 0 and
                    tail.owner >= 0 and
                    head.distance + 1 == tail.distance and
                    pins[@intCast(head.owner)].number < pins[@intCast(tail.owner)].number))
            {
                nets.items[edge.b].owner = head.owner;
                nets.items[edge.b].distance = head.distance + 1;
                changed = true;
            }
            if (tail.distance + 1 < head.distance or
                (head.owner >= 0 and
                    tail.owner >= 0 and
                    tail.distance + 1 == head.distance and
                    pins[@intCast(tail.owner)].number < pins[@intCast(head.owner)].number))
            {
                nets.items[edge.a].owner = tail.owner;
                nets.items[edge.a].distance = tail.distance + 1;
                changed = true;
            }
        }
        passes += 1;
    }
    return nets;
}

// ── layout ───────────────────────────────────────────────────────────

const Point = struct {
    x: i64,
    y: i64,
};

const Row = struct {
    index: usize,
    group: i64,
    height: i64,
    rail: i64,
    side: i64,
    y: i64,
};

/// Floor division, matching mylang's `//` on integers.
inline fn floor_div(a: i64, b: i64) i64 {
    const q = @divTrunc(a, b);
    if (@rem(a, b) != 0 and ((a < 0) != (b < 0))) return q - 1;
    return q;
}

/// `layout.pinGroup`
fn pin_group(pin: Pin, nets: []const Net) i64 {
    const id = find_id(nets, pin.display_id);
    if (id < 0) return -1;
    return nets[@intCast(id)].group;
}

/// `layout.rowHeight`
fn row_height(pin: Pin, passive_counts: []const i64, bridge_nets: []const bool) i64 {
    if (pin.rail != 0) return 40;
    const count = passive_counts[@intCast(pin.net_id)];
    if (count > 1) {
        if (!bridge_nets[@intCast(pin.net_id)]) return count * 40;
        return 56 + (count - 1) * 40;
    }
    return 56;
}

/// `layout.collectRows`
fn collect_rows(parts: []const Part, pins: []const Pin, nets: []const Net) std.ArrayList(Row) {
    var out: std.ArrayList(Row) = .empty;
    var counts: [130]i64 = @splat(0);
    var offsets: [130]i64 = @splat(0);
    var cursor: [130]i64 = @splat(0);
    const ordered = global_alloc.alloc(i64, pins.len) catch oom();
    @memset(ordered, -1);
    const passive_counts = global_alloc.alloc(i64, pins.len) catch oom();
    @memset(passive_counts, 0);
    const bridge_nets = global_alloc.alloc(bool, pins.len) catch oom();
    @memset(bridge_nets, false);
    const hub_nets = global_alloc.alloc(bool, pins.len) catch oom();
    @memset(hub_nets, false);
    var hub_count: usize = 0;
    var i: usize = 0;
    while (i < pins.len) : (i += 1) {
        const pin = pins[i];
        if (parts[pin.part].kind == 0) {
            if (!pin.nc and pin.number >= 1 and pin.number <= 128) {
                counts[@intCast(pin.number)] += 1;
                hub_count += 1;
            }
            if (pin.net_id >= 0) hub_nets[@intCast(pin.net_id)] = true;
        } else if (!pin.nc and pin.net_id >= 0) {
            passive_counts[@intCast(pin.net_id)] += 1;
        }
    }
    var number: usize = 1;
    while (number <= 129) : (number += 1) {
        offsets[number] = offsets[number - 1] + counts[number - 1];
        cursor[number] = offsets[number];
    }
    var loop_b: usize = 0;
    while (loop_b < pins.len) : (loop_b += 1) {
        const pin = pins[loop_b];
        if (parts[pin.part].kind == 0 and !pin.nc and pin.number >= 1 and pin.number <= 128) {
            const slot = cursor[@intCast(pin.number)];
            ordered[@intCast(slot)] = @intCast(loop_b);
            cursor[@intCast(pin.number)] = slot + 1;
        }
    }
    var loop_c: usize = 0;
    while (loop_c < pins.len) : (loop_c += 1) {
        const pin = pins[loop_c];
        if (parts[pin.part].kind != 0 and !pin.nc) {
            var far = parts[pin.part].pin1;
            if (far == @as(i64, @intCast(loop_c))) far = parts[pin.part].pin2;
            if (far >= 0 and
                pins[@intCast(far)].raw_rail == 0 and
                pins[@intCast(far)].net_id >= 0 and
                hub_nets[@intCast(pins[@intCast(far)].net_id)])
            {
                bridge_nets[@intCast(pin.net_id)] = true;
            }
        }
    }
    var seen_groups: std.ArrayList(i64) = .empty;
    var position: usize = 0;
    while (position < hub_count) : (position += 1) {
        const index = ordered[position];
        const pin = pins[@intCast(index)];
        const group = pin_group(pin, nets);
        var present = false;
        var n: usize = 0;
        while (n < seen_groups.items.len) : (n += 1) {
            if (seen_groups.items[n] == group) present = true;
        }
        if (!present) {
            seen_groups.append(global_alloc, group) catch oom();
            var member: usize = 0;
            while (member < hub_count) : (member += 1) {
                const other_index = ordered[member];
                const other = pins[@intCast(other_index)];
                if (other.part == pin.part and pin_group(other, nets) == group) {
                    out.append(global_alloc, .{
                        .index = @intCast(other_index),
                        .group = group,
                        .height = row_height(other, passive_counts, bridge_nets),
                        .rail = other.rail,
                        .side = 0,
                        .y = 0,
                    }) catch oom();
                }
            }
        }
    }
    return out;
}

/// `layout.height`
fn layout_height(points: []const Point) i64 {
    var bottom: i64 = 160;
    var i: usize = 0;
    while (i < points.len) : (i += 1) {
        if (points[i].y + 40 > bottom) bottom = points[i].y + 40;
    }
    return bottom;
}

/// `layout.placeRows`
fn place_rows(rows: []Row) void {
    var total: i64 = 0;
    var i: usize = 0;
    while (i < rows.len) : (i += 1) {
        const row = rows[i];
        total += row.height;
        if (i == 0 or rows[i - 1].group != row.group) {
            if (row.rail == 1) total += 16;
            if (row.rail == 2) total += 56;
        }
    }
    var prefix: i64 = 0;
    var best: i64 = total * 100;
    var split: usize = rows.len;
    var loop_b: usize = 0;
    while (loop_b + 1 < rows.len) : (loop_b += 1) {
        const row = rows[loop_b];
        prefix += row.height;
        if (loop_b == 0 or rows[loop_b - 1].group != row.group) {
            if (row.rail == 1) prefix += 16;
            if (row.rail == 2) prefix += 56;
        }
        if (rows[loop_b].group != rows[loop_b + 1].group) {
            var delta = total * 48 - 100 * prefix;
            if (delta < 0) delta = -delta;
            if (delta < best) {
                best = delta;
                split = loop_b + 1;
            }
        }
    }
    var y: i64 = 80;
    var loop_c: usize = 0;
    while (loop_c < rows.len) : (loop_c += 1) {
        if (loop_c == split) y = 80;
        const row = rows[loop_c];
        if (loop_c > 0 and loop_c != split and rows[loop_c - 1].group != row.group) {
            if (rows[loop_c - 1].rail == 1) y += 16;
            if (rows[loop_c - 1].rail == 2) y += 36;
            if (rows[loop_c - 1].height == 80) y += 16;
        }
        if (row.rail == 2 and (loop_c == 0 or loop_c == split or rows[loop_c - 1].group != row.group)) y += 20;
        var offset: i64 = 0;
        if (row.height > 56) offset = floor_div(row.height - 56, 2);
        if (row.height == 80) offset = 20;
        const side: i64 = if (loop_c >= split) 1 else -1;
        rows[loop_c].side = side;
        rows[loop_c].y = y + offset;
        y += row.height;
    }
}

/// `layout.nearest`
fn nearest(pin: Pin, parts: []const Part, pins: []const Pin, rows: []const Row, nets: []const Net) i64 {
    const group = pin_group(pin, nets);
    const id = find_id(nets, pin.display_id);
    var owner: i64 = -1;
    if (id >= 0) owner = nets[@intCast(id)].owner;
    var fallback: i64 = -1;
    var i: usize = 0;
    while (i < rows.len) : (i += 1) {
        const row = rows[i];
        const hub = pins[row.index];
        if (pin.net_id == hub.net_id) return @intCast(i);
        if (@as(i64, @intCast(row.index)) == owner) fallback = @intCast(i);
        if (row.group == group and fallback < 0) fallback = @intCast(i);
    }
    _ = parts;
    return fallback;
}

/// `layout.partPin`
fn part_pin(part: usize, number: i64, parts: []const Part, pins: []const Pin) Pin {
    var index: i64 = -1;
    if (number == 1) {
        index = parts[part].pin1;
    } else if (number == 2) {
        index = parts[part].pin2;
    }
    if (index >= 0 and
        @as(usize, @intCast(index)) < pins.len and
        pins[@intCast(index)].part == part and
        pins[@intCast(index)].number == number)
    {
        return pins[@intCast(index)];
    }
    var i: usize = 0;
    while (i < pins.len) : (i += 1) {
        const pin = pins[i];
        if (pin.part == part and pin.number == number) return pin;
    }
    return .{
        .part = part,
        .number = number,
        .net = EMPTY,
        .nc = true,
        .display = EMPTY,
        .net_id = -1,
        .display_id = -1,
        .raw_rail = 0,
        .rail = 0,
        .decoupling = false,
    };
}

/// `layout.depth`
fn depth(pin: Pin, nets: []const Net) i64 {
    const id = find_id(nets, pin.display_id);
    if (id < 0) return 4096;
    return nets[@intCast(id)].distance;
}

/// `layout.innerPin`
fn inner_pin(part: usize, parts: []const Part, pins: []const Pin, nets: []const Net) Pin {
    const a = part_pin(part, 1, parts, pins);
    const b = part_pin(part, 2, parts, pins);
    if (a.raw_rail != 0 and b.raw_rail == 0) return b;
    if (b.raw_rail == 0 and depth(b, nets) < depth(a, nets)) return b;
    return a;
}

/// `layout.bridge`
fn bridge(part: usize, parts: []const Part, pins: []const Pin, rows: []const Row, nets: []const Net) bool {
    const a = part_pin(part, 1, parts, pins);
    const b = part_pin(part, 2, parts, pins);
    if (a.raw_rail != 0 or b.raw_rail != 0) return false;
    if (depth(a, nets) != depth(b, nets)) return false;
    const ai = nearest(a, parts, pins, rows, nets);
    const bi = nearest(b, parts, pins, rows, nets);
    return ai >= 0 and bi >= 0 and ai != bi;
}

/// `layout.groundBranch`
fn ground_branch(part: usize, parts: []const Part, pins: []const Pin, nets: []const Net) bool {
    const inner = inner_pin(part, parts, pins, nets);
    const outer = part_pin(part, 3 - inner.number, parts, pins);
    if (outer.raw_rail == 1) return true;
    if (outer.raw_rail == 2) return false;
    var found = false;
    var j: usize = 0;
    while (j < parts.len) : (j += 1) {
        if (parts[j].kind != 0 and j != part) {
            const a = part_pin(j, 1, parts, pins);
            const b = part_pin(j, 2, parts, pins);
            var other_rail: i64 = 0;
            if (a.net_id == outer.net_id) other_rail = b.raw_rail;
            if (b.net_id == outer.net_id) other_rail = a.raw_rail;
            if (other_rail == 2) return false;
            if (other_rail == 1) found = true;
        }
    }
    return found;
}

/// `layout.branch`
fn branch(
    part: usize,
    parts: []const Part,
    pins: []const Pin,
    rows: []const Row,
    nets: []const Net,
    remaining: i64,
) i64 {
    if (remaining == 0) return 0;
    const inner = inner_pin(part, parts, pins, nets);
    const level = depth(inner, nets);
    var offset: i64 = 0;
    if (level > 0) {
        const owner = nearest(inner, parts, pins, rows, nets);
        var j: usize = 0;
        while (j < parts.len) : (j += 1) {
            if (parts[j].kind != 0 and j != part) {
                const previous = inner_pin(j, parts, pins, nets);
                if (depth(previous, nets) < level and
                    nearest(previous, parts, pins, rows, nets) == owner)
                {
                    const outer = part_pin(j, 3 - previous.number, parts, pins);
                    if (outer.net_id == inner.net_id) {
                        offset = branch(j, parts, pins, rows, nets, remaining - 1);
                        break;
                    }
                }
            }
        }
    }
    var count: i64 = 0;
    var rank: i64 = 0;
    var has_bridge = false;
    const grounded = ground_branch(part, parts, pins, nets);
    var j2: usize = 0;
    while (j2 < parts.len) : (j2 += 1) {
        if (parts[j2].kind != 0) {
            const previous = inner_pin(j2, parts, pins, nets);
            const a = part_pin(j2, 1, parts, pins);
            const b = part_pin(j2, 2, parts, pins);
            if (bridge(j2, parts, pins, rows, nets)) {
                if (a.net_id == inner.net_id or b.net_id == inner.net_id) has_bridge = true;
            } else if (previous.net_id == inner.net_id) {
                count += 1;
                const other_ground = ground_branch(j2, parts, pins, nets);
                if (level > 0) {
                    if (@as(i64, @intCast(j2)) < @as(i64, @intCast(part))) rank += 1;
                } else if ((other_ground and !grounded) or
                    (other_ground == grounded and @as(i64, @intCast(j2)) < @as(i64, @intCast(part))))
                {
                    rank += 1;
                }
            }
        }
    }
    if (level == 0) {
        var spacing: i64 = 20;
        if (has_bridge) spacing = 40;
        offset -= (count - 1) * spacing;
    }
    return offset + rank * 40;
}

/// `layout.endpoint`
fn endpoint(pin: Pin, parts: []const Part, pins: []const Pin, rows: []const Row, nets: []const Net) Point {
    const inner = inner_pin(pin.part, parts, pins, nets);
    const chosen = nearest(inner, parts, pins, rows, nets);
    if (chosen < 0) {
        return .{ .x = 100 + pin.number * 60, .y = 80 + @as(i64, @intCast(pin.part)) * 60 };
    }
    const row = rows[@intCast(chosen)];
    var edge: i64 = 352;
    if (row.side == 1) edge = 532;
    const level = depth(inner, nets);
    if (bridge(pin.part, parts, pins, rows, nets)) {
        const target = nearest(pin, parts, pins, rows, nets);
        const other = rows[@intCast(target)];
        var reach: i64 = 50;
        if (level > 0) reach = 170;
        return .{ .x = edge + row.side * reach, .y = other.y };
    }
    const hub = pins[row.index];
    var count: i64 = 0;
    var j: usize = 0;
    while (j < parts.len) : (j += 1) {
        if (parts[j].kind != 0) {
            const attached = inner_pin(j, parts, pins, nets);
            if (attached.net_id == hub.net_id and !bridge(j, parts, pins, rows, nets)) count += 1;
        }
    }
    var reach: i64 = 40;
    if (count > 1) reach = 60;
    if (pin.number != inner.number) reach = 120;
    const local_rail = inner.raw_rail == 2 and inner.display_id != inner.net_id;
    var y = row.y + branch(pin.part, parts, pins, rows, nets, 128);
    if (local_rail) {
        reach = 70;
        if (pin.number != inner.number) reach = 110;
        y += 20;
    }
    const x = edge + row.side * (reach + level * 60);
    return .{ .x = x, .y = y };
}

/// `layout.build`
fn layout_build(parts: []const Part, pins: []const Pin) std.ArrayList(Point) {
    const nets = graph_build(parts, pins);
    var out: std.ArrayList(Point) = .empty;
    out.ensureTotalCapacity(global_alloc, pins.len) catch oom();
    const ordered = collect_rows(parts, pins, nets.items);
    place_rows(ordered.items);
    var i: usize = 0;
    while (i < pins.len) : (i += 1) {
        const pin = pins[i];
        var point = Point{ .x = -1, .y = -1 };
        if (parts[pin.part].kind == 0) {
            var j: usize = 0;
            while (j < ordered.items.len) : (j += 1) {
                const row = ordered.items[j];
                if (row.index == i) {
                    var x: i64 = 352;
                    if (row.side == 1) x = 532;
                    point = .{ .x = x, .y = row.y };
                }
            }
        } else {
            point = endpoint(pin, parts, pins, ordered.items, nets.items);
        }
        out.append(global_alloc, point) catch oom();
    }
    return out;
}

// ── routes ───────────────────────────────────────────────────────────

const Segment = struct {
    x1: i64,
    y1: i64,
    x2: i64,
    y2: i64,
    net: Span,
    junction: bool,
    terminal: bool,
};

fn segment(x1: i64, y1: i64, x2: i64, y2: i64, net: Span, junction: bool, terminal: bool) Segment {
    return .{
        .x1 = x1,
        .y1 = y1,
        .x2 = x2,
        .y2 = y2,
        .net = net,
        .junction = junction,
        .terminal = terminal,
    };
}

inline fn manhattan(a: Point, b: Point) i64 {
    var x = a.x - b.x;
    var y = a.y - b.y;
    if (x < 0) x = -x;
    if (y < 0) y = -y;
    return x + y;
}

/// `layout_routes.external`
fn external(ctx: *const Ctx, net: Span, connections: []const Port) bool {
    const target = Port{ .prefix = EMPTY, .name = net, .direction = EMPTY };
    var i: usize = 0;
    while (i < connections.len) : (i += 1) {
        if (port_equal(ctx, target, connections[i])) return true;
    }
    return false;
}

/// `layout_routes.blocked`
fn blocked(
    a: Point,
    b: Point,
    net_id: i64,
    pins: []const Pin,
    points: []const Point,
) bool {
    var i: usize = 0;
    while (i < pins.len) : (i += 1) {
        const pin = pins[i];
        const q = points[i];
        var intersects = false;
        if (a.x == b.x and q.x == a.x and
            ((q.y >= a.y and q.y <= b.y) or (q.y >= b.y and q.y <= a.y)))
        {
            intersects = true;
        }
        if (a.y == b.y and q.y == a.y and
            ((q.x >= a.x and q.x <= b.x) or (q.x >= b.x and q.x <= a.x)))
        {
            intersects = true;
        }
        if (intersects and !pin.nc and pin.display_id != net_id) {
            if (a.x == b.x) return true;
            if (a.y == b.y) return true;
        }
    }
    return false;
}

/// `layout_routes.build`
fn routes_build(
    ctx: *const Ctx,
    parts: []const Part,
    pins: []const Pin,
    points: []const Point,
    connections: []const Port,
) std.ArrayList(Segment) {
    var out: std.ArrayList(Segment) = .empty;
    var i: usize = 0;
    while (i < pins.len) : (i += 1) {
        const pin = pins[i];
        const point = points[i];
        if (!pin.nc) {
            const display = pin.display;
            const is_ground = pin.raw_rail == 1;
            const coupled_ground = pin.decoupling;
            const local_ground = is_ground and parts[pin.part].kind != 0 and !coupled_ground;
            const is_rail = pin.rail != 0 and !is_ground;
            const standalone_rail = is_rail and parts[pin.part].kind != 0 and pin.net_id == pin.display_id;
            var nearest_index: i64 = -1;
            var shortest: i64 = 1000000;
            var count: i64 = 0;
            var j: usize = 0;
            while (j < pins.len) : (j += 1) {
                const other = pins[j];
                const other_point = points[j];
                const other_standalone = is_rail and parts[other.part].kind != 0 and other.net_id == pin.display_id;
                const allowed = (!is_ground or
                    (coupled_ground and other.decoupling) or
                    (!coupled_ground and parts[other.part].kind == 0)) and
                    !other_standalone;
                if (!other.nc and allowed and pin.display_id == other.display_id) {
                    count += 1;
                    if (@as(i64, @intCast(j)) < @as(i64, @intCast(i)) and manhattan(point, other_point) < shortest) {
                        nearest_index = @intCast(j);
                        shortest = manhattan(point, other_point);
                    }
                }
            }
            if (nearest_index < 0 and
                count > 1 and
                (is_ground or is_rail) and
                !local_ground and
                !standalone_rail)
            {
                var low = point.y;
                var high = point.y;
                var k: usize = 0;
                while (k < pins.len) : (k += 1) {
                    const other = pins[k];
                    if (!other.nc and
                        ((coupled_ground and other.decoupling) or
                            (!coupled_ground and parts[other.part].kind == 0)) and
                        pin.display_id == other.display_id)
                    {
                        const q = points[k];
                        if (q.y < low) low = q.y;
                        if (q.y > high) high = q.y;
                    }
                }
                var side: i64 = -1;
                if (point.x > 442) side = 1;
                var y = floor_div(low + high, 2);
                if (is_rail) y = low - 20;
                if (coupled_ground) y = high;
                var bus = point.x + side * 40;
                if (coupled_ground) bus = point.x + side * 20;
                out.append(global_alloc, segment(bus, point.y, bus, y, display, false, false)) catch oom();
                var reach: i64 = 100;
                if (coupled_ground) reach = 10;
                out.append(global_alloc, segment(bus, y, bus + side * reach, y, display, false, true)) catch oom();
            }
            if (nearest_index < 0 and
                count > 1 and
                !is_ground and
                !is_rail and
                external(ctx, display, connections))
            {
                var dx: i64 = 24;
                if (point.x < 442) dx = -24;
                out.append(global_alloc, segment(point.x, point.y, point.x + dx, point.y, display, false, true)) catch oom();
            }
            if (local_ground or standalone_rail or count == 1) {
                var dx: i64 = 24;
                if (parts[pin.part].kind == 0) {
                    dx = 140;
                    if (!external(ctx, display, connections) and !is_rail and !is_ground) dx = 50;
                }
                if (point.x < 442) dx = -dx;
                out.append(global_alloc, segment(point.x, point.y, point.x + dx, point.y, display, false, true)) catch oom();
            } else if (nearest_index >= 0) {
                const previous = points[@intCast(nearest_index)];
                if (is_ground or (point.x == previous.x and (point.x == 352 or point.x == 532))) {
                    var bus = point.x - 40;
                    if (point.x > 442) bus = point.x + 40;
                    if (coupled_ground) {
                        bus = point.x - 20;
                        if (point.x > 442) bus = point.x + 20;
                    }
                    out.append(global_alloc, segment(point.x, point.y, bus, point.y, display, false, false)) catch oom();
                    out.append(global_alloc, segment(bus, point.y, bus, previous.y, display, true, false)) catch oom();
                    out.append(global_alloc, segment(bus, previous.y, previous.x, previous.y, display, false, false)) catch oom();
                } else if (is_rail and parts[pin.part].kind != 0) {
                    var bus: i64 = 302;
                    if (point.x > 442) bus = 582;
                    out.append(global_alloc, segment(point.x, point.y, bus, point.y, display, false, false)) catch oom();
                    out.append(global_alloc, segment(bus, point.y, bus, previous.y, display, false, false)) catch oom();
                    out.append(global_alloc, segment(bus, previous.y, previous.x, previous.y, display, false, false)) catch oom();
                } else if (parts[pins[@intCast(nearest_index)].part].kind == 0 and point.y != previous.y) {
                    var side: i64 = 1;
                    if (previous.x < 442) side = -1;
                    const bus = previous.x + side * 50;
                    out.append(global_alloc, segment(point.x, point.y, bus, point.y, display, false, false)) catch oom();
                    out.append(global_alloc, segment(bus, point.y, bus, previous.y, display, false, false)) catch oom();
                    out.append(global_alloc, segment(bus, previous.y, previous.x, previous.y, display, false, false)) catch oom();
                } else if (point.x == previous.x and blocked(point, previous, pin.display_id, pins, points)) {
                    var offset: i64 = 16;
                    var lane = point.x + offset;
                    var lane_start = Point{ .x = lane, .y = point.y };
                    var lane_end = Point{ .x = lane, .y = previous.y };
                    while (blocked(lane_start, lane_end, pin.display_id, pins, points) and offset < 160) {
                        offset += 16;
                        lane = point.x + offset;
                        lane_start.x = lane;
                        lane_end.x = lane;
                    }
                    out.append(global_alloc, segment(point.x, point.y, lane, point.y, display, false, false)) catch oom();
                    out.append(global_alloc, segment(lane, point.y, lane, previous.y, display, false, false)) catch oom();
                    out.append(global_alloc, segment(lane, previous.y, previous.x, previous.y, display, false, false)) catch oom();
                } else {
                    out.append(global_alloc, segment(point.x, point.y, previous.x, point.y, display, count > 2, false)) catch oom();
                    if (point.y != previous.y) {
                        out.append(global_alloc, segment(previous.x, point.y, previous.x, previous.y, display, count > 2, false)) catch oom();
                    }
                }
            }
        }
    }
    return out;
}

// ── SVG ──────────────────────────────────────────────────────────────

/// `draw.rect`
fn draw_rect(out: *Out, x: i64, y: i64, w: i64, h: i64) void {
    out.write("<rect class=\"chip\" x=\"");
    out.decimal(x);
    out.write("\" y=\"");
    out.decimal(y);
    out.write("\" width=\"");
    out.decimal(w);
    out.write("\" height=\"");
    out.decimal(h);
    out.write("\" rx=\"6\"/>");
}

/// `draw.line`
fn draw_line(out: *Out, x1: i64, y1: i64, x2: i64, y2: i64) void {
    out.write("<line x1=\"");
    out.decimal(x1);
    out.write("\" y1=\"");
    out.decimal(y1);
    out.write("\" x2=\"");
    out.decimal(x2);
    out.write("\" y2=\"");
    out.decimal(y2);
    out.write("\"/>");
}

/// `draw.labelStart`
fn draw_label_start(out: *Out, x: i64, y: i64, anchor: i64) void {
    out.write("<text x=\"");
    out.decimal(x);
    out.write("\" y=\"");
    out.decimal(y);
    out.write("\" text-anchor=\"");
    if (anchor == 0) {
        out.write("start");
    } else if (anchor == 1) {
        out.write("middle");
    } else {
        out.write("end");
    }
    out.write("\">");
}

/// `draw.labelEnd`
fn draw_label_end(out: *Out) void {
    out.write("</text>");
}

/// `draw.label`
fn draw_label(out: *Out, ctx: *const Ctx, x: i64, y: i64, anchor: i64, value: Span) void {
    draw_label_start(out, x, y, anchor);
    out.escaped(ctx, value);
    draw_label_end(out);
}

/// `draw.symbol`
fn draw_symbol(out: *Out, kind: i64) void {
    out.write("<g class=\"symbol\">");
    draw_line(out, -20, 0, -12, 0);
    draw_line(out, 12, 0, 20, 0);
    if (kind == 1) {
        draw_line(out, -3, -6, -3, 6);
        draw_line(out, 3, -6, 3, 6);
        draw_line(out, -12, 0, -3, 0);
        draw_line(out, 3, 0, 12, 0);
    } else if (kind == 2) {
        out.write("<rect x=\"-12\" y=\"-5\" width=\"24\" height=\"10\"/>");
    } else {
        out.write("<path d=\"M -12 0 c 0,-7 6,-7 6,0 c 0,-7 6,-7 6,0 c 0,-7 6,-7 6,0 c 0,-7 6,-7 6,0\"/>");
    }
    out.write("</g>");
}

/// `svg.instanceStart`
fn instance_start(out: *Out, ctx: *const Ctx, item: Part) void {
    out.write("<g class=\"component\" data-ref=\"");
    out.escaped(ctx, item.reference);
    out.write("\" data-family=\"");
    out.escaped(ctx, item.family);
    out.write("\" data-value=\"");
    out.escaped(ctx, item.value);
    out.write("\"><title>");
    out.escaped(ctx, item.reference);
    out.write(" — ");
    out.escaped(ctx, item.family);
    out.write(" ");
    out.escaped(ctx, item.value);
    out.write("</title>");
}

/// `svg.pinStart`
fn pin_start(out: *Out, ctx: *const Ctx, pin: Pin, display: Span, point: Point) void {
    out.write("<g data-pin=\"");
    out.decimal(pin.number);
    out.write("\" data-x=\"");
    out.decimal(point.x);
    out.write("\" data-y=\"");
    out.decimal(point.y);
    if (pin.nc) {
        out.write("\" data-nc=\"true\"><title>");
        out.escaped(ctx, pin.net);
        out.write("</title>");
    } else {
        out.write("\" data-net=\"");
        out.escaped(ctx, pin.net);
        out.write("\" data-electrical-net=\"");
        out.escaped(ctx, display);
        out.write("\">");
    }
}

/// `svg.finishGroup`
fn finish_group(out: *Out) void {
    out.write("</g>");
}

/// `svg.displayRef`
fn display_ref(out: *Out, parts: []const Part, index: usize) void {
    const item = parts[index];
    var n: i64 = 0;
    var i: usize = 0;
    while (i <= index) : (i += 1) {
        if (parts[i].kind == item.kind) n += 1;
    }
    if (item.kind == 0) {
        out.write("U");
    } else if (item.kind == 1) {
        out.write("C");
    } else if (item.kind == 2) {
        out.write("R");
    } else {
        out.write("L");
    }
    out.decimal(n);
}

/// `svg.passive`
fn passive(out: *Out, ctx: *const Ctx, index: usize, parts: []const Part, pins: []const Pin, points: []const Point) void {
    const item = parts[index];
    var a = Point{ .x = 0, .y = 0 };
    var b = a;
    var i: usize = 0;
    while (i < pins.len) : (i += 1) {
        const pin = pins[i];
        if (pin.part == index) {
            if (pin.number == 1) {
                a = points[i];
            } else {
                b = points[i];
            }
        }
    }
    const x = floor_div(a.x + b.x, 2);
    const y = floor_div(a.y + b.y, 2);
    instance_start(out, ctx, item);
    out.write("<g transform=\"translate(");
    out.decimal(x);
    out.write(" ");
    out.decimal(y);
    out.write(")");
    if (a.x == b.x) out.write(" rotate(90)");
    out.write("\"><rect class=\"symbol-clear\" x=\"-20\" y=\"-9\" width=\"40\" height=\"18\"/>");
    draw_symbol(out, item.kind);
    finish_group(out);
    if (a.x == b.x) {
        var top = a.y;
        var bottom = b.y;
        if (top > bottom) {
            top = b.y;
            bottom = a.y;
        }
        draw_line(out, x, top, x, y - 20);
        draw_line(out, x, y + 20, x, bottom);
        draw_label_start(out, x + 10, y + 3, 0);
    } else {
        var left = a.x;
        var right = b.x;
        if (left > right) {
            left = b.x;
            right = a.x;
        }
        draw_line(out, left, y, x - 20, y);
        draw_line(out, x + 20, y, right, y);
        draw_label_start(out, x, y - 14, 1);
    }
    display_ref(out, parts, index);
    out.write(" ");
    out.escaped(ctx, item.value);
    draw_label_end(out);
    var loop_b: usize = 0;
    while (loop_b < pins.len) : (loop_b += 1) {
        const pin = pins[loop_b];
        if (pin.part == index) {
            pin_start(out, ctx, pin, pin.display, points[loop_b]);
            finish_group(out);
        }
    }
    finish_group(out);
}

/// `svg.chip`
fn chip(
    out: *Out,
    ctx: *const Ctx,
    index: usize,
    parts: []const Part,
    pins: []const Pin,
    points: []const Point,
    pinout: []const Node,
) void {
    instance_start(out, ctx, parts[index]);
    draw_rect(out, 352, 20, 180, layout_height(points) - 40);
    draw_label_start(out, 442, 38, 1);
    display_ref(out, parts, index);
    out.write(" ");
    out.escaped(ctx, parts[index].family);
    draw_label_end(out);
    var i: usize = 0;
    while (i < pins.len) : (i += 1) {
        const pin = pins[i];
        if (pin.part == index) {
            const point = points[i];
            pin_start(out, ctx, pin, pin.display, points[i]);
            if (!pin.nc) {
                var side: i64 = -1;
                var anchor: i64 = 0;
                if (point.x > 442) {
                    side = 1;
                    anchor = 2;
                }
                draw_line(out, point.x, point.y, point.x + side * 40, point.y);
                draw_label(
                    out,
                    ctx,
                    point.x - side * 8,
                    point.y + 4,
                    anchor,
                    pinout_label(ctx, pinout, pin.number),
                );
                draw_label_start(out, point.x + side * 3, point.y - 3, 1);
                out.decimal(pin.number);
                draw_label_end(out);
            }
            finish_group(out);
        }
    }
    finish_group(out);
}

/// `svg.portName`
fn port_name(out: *Out, ctx: *const Ctx, item: Port) void {
    if (item.prefix.start != item.prefix.end) {
        out.escaped(ctx, item.prefix);
        out.write("_");
    }
    out.escaped(ctx, item.name);
}

/// `svg.ports`
fn svg_ports(out: *Out, ctx: *const Ctx, connections: []const Port) void {
    var i: usize = 0;
    while (i < connections.len) : (i += 1) {
        const item = connections[i];
        out.write("<g class=\"port\" data-port=\"");
        port_name(out, ctx, item);
        out.write("\" data-direction=\"");
        out.escaped(ctx, item.direction);
        out.write("\"><title>");
        port_name(out, ctx, item);
        out.write("</title></g>");
    }
}

/// `svg.ground`
fn svg_ground(ctx: *const Ctx, net: Span) bool {
    return ctx.matches(net, "GND");
}

/// `svg.routes`
fn svg_routes(out: *Out, ctx: *const Ctx, segments: []const Segment, connections: []const Port) void {
    var i: usize = 0;
    while (i < segments.len) : (i += 1) {
        const item = segments[i];
        out.write("<g class=\"wire\" data-net=\"");
        out.escaped(ctx, item.net);
        out.write("\">");
        draw_line(out, item.x1, item.y1, item.x2, item.y2);
        if (item.terminal) {
            if (svg_ground(ctx, item.net)) {
                out.write("<g class=\"ground\">");
                draw_line(out, item.x2, item.y2, item.x2, item.y2 + 6);
                draw_line(out, item.x2 - 7, item.y2 + 6, item.x2 + 7, item.y2 + 6);
                draw_line(out, item.x2 - 4, item.y2 + 9, item.x2 + 4, item.y2 + 9);
                draw_line(out, item.x2 - 1, item.y2 + 12, item.x2 + 1, item.y2 + 12);
                finish_group(out);
            } else if (!external(ctx, item.net, connections) and rail_kind(ctx, item.net) == 0) {
                out.write("<g class=\"dangling-marker\">");
                draw_line(out, item.x2 - 4, item.y2 - 4, item.x2 + 4, item.y2 + 4);
                draw_line(out, item.x2 - 4, item.y2 + 4, item.x2 + 4, item.y2 - 4);
                finish_group(out);
            } else {
                var side: i64 = 1;
                var anchor: i64 = 0;
                if (item.x2 < 442) {
                    side = -1;
                    anchor = 2;
                }
                out.write("<g class=\"net-label\">");
                draw_label(out, ctx, item.x2 + side * 12, item.y2 + 4, anchor, item.net);
                finish_group(out);
            }
        }
        finish_group(out);
    }
}

/// `svg.render`
fn render(ctx: *const Ctx, drawing: *const Drawing) std.ArrayList(u8) {
    const parts = drawing.parts.items;
    const pins = drawing.pins.items;
    const points = layout_build(parts, pins);
    const segments = routes_build(ctx, parts, pins, points.items, drawing.connections.items);
    var out = Out.init(64 * 1024);
    out.write("<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 884 ");
    out.decimal(layout_height(points.items));
    out.write("\" width=\"884\" height=\"");
    out.decimal(layout_height(points.items));
    out.write("\" role=\"img\"><title>");
    out.escaped(ctx, title(ctx, drawing.nodes.items));
    out.write("</title><style>");
    out.write("svg{background:#0d1117}text{font-family:Arial,sans-serif;font-size:11px;fill:#aaa;stroke:none}" ++
        "line,path{stroke:#4a9;stroke-width:1.5;fill:none}" ++
        ".chip{fill:#16213e;stroke:#4a9eff;stroke-width:2}" ++
        ".symbol rect,.symbol path,.symbol line{fill:none;stroke:#8888cc;stroke-width:1.5}" ++
        ".component>text{font-size:9px;fill:#888}.component>text:first-of-type{font-size:9px}" ++
        ".component:has(.chip)>text{fill:#4a9eff;font-size:12px;font-weight:bold}" ++
        "[data-pin]>line{stroke:#666}[data-pin]>text{font-size:12px}" ++
        "[data-pin]>text:last-child{font-size:9px;fill:#666}" ++
        ".symbol-clear{fill:#0d1117;stroke:none}.ground line{stroke:#d6bb24}" ++
        ".dangling-marker line{stroke:#666}" ++
        ".net-label text{fill:#4a9eff;font-size:11px;font-weight:bold}[data-nc]{display:none}</style>");
    out.write("<rect width=\"100%\" height=\"100%\" fill=\"#0d1117\"/>");
    svg_routes(&out, ctx, segments.items, drawing.connections.items);
    var i: usize = 0;
    while (i < parts.len) : (i += 1) {
        if (parts[i].kind == 0) chip(&out, ctx, i, parts, pins, points.items, drawing.pinout.items);
    }
    var loop_b: usize = 0;
    while (loop_b < parts.len) : (loop_b += 1) {
        if (parts[loop_b].kind != 0) passive(&out, ctx, loop_b, parts, pins, points.items);
    }
    svg_ports(&out, ctx, drawing.connections.items);
    out.write("</svg>");
    return out.bytes;
}

// ── schematic.build and main ─────────────────────────────────────────

const Drawing = struct {
    nodes: std.ArrayList(Node),
    parts: std.ArrayList(Part),
    pins: std.ArrayList(Pin),
    pinout: std.ArrayList(Node),
    connections: std.ArrayList(Port),
};

fn build(
    ctx: *const Ctx,
    nodes: std.ArrayList(Node),
    pinout: std.ArrayList(Node),
    interface: std.ArrayList(Node),
) Fail!Drawing {
    const source_error = validate_source(ctx, nodes.items);
    if (source_error != 0) return fail(source_error);
    const parts = try collect_parts(ctx, nodes.items);
    const pinout_error = pinout_check(ctx, pinout.items);
    if (pinout_error != 0) return fail(pinout_error);
    const pins = try collect_pins(ctx, nodes.items, parts.items, pinout.items);
    const model_error = validate_model(ctx, nodes.items, parts.items, pins.items, pinout.items);
    if (model_error != 0) return fail(model_error);
    normalize(ctx, parts.items, pins.items);
    const connections = try ports_collect(ctx, nodes.items, interface.items);
    const ports_error = ports_validate(ctx, connections.items, pins.items);
    if (ports_error != 0) return fail(ports_error);
    return .{
        .nodes = nodes,
        .parts = parts,
        .pins = pins,
        .pinout = pinout,
        .connections = connections,
    };
}

/// Report the first located issue the way the mylang guest does: the code alone
/// on stdout, and the code as the process status.
fn issueExit(init: std.process.Init) noreturn {
    var buffer: [24]u8 = undefined;
    const message = std.fmt.bufPrint(&buffer, "{d}\n", .{issue_code}) catch "0\n";
    std.Io.File.stdout().writeStreamingAll(init.io, message) catch {};
    std.process.exit(@intCast(issue_code));
}

fn reportStderr(init: std.process.Init, message: []const u8) void {
    std.Io.File.stderr().writeStreamingAll(init.io, message) catch {};
}

pub fn main(init: std.process.Init) void {
    const args = init.minimal.args.toSlice(init.arena.allocator()) catch std.process.exit(2);
    if (args.len != 5) {
        var buffer: [512]u8 = undefined;
        const name: []const u8 = if (args.len > 0) args[0] else "schematic";
        const message = std.fmt.bufPrint(
            &buffer,
            "usage: {s} <module.sexp> <pinout.sexp> <interface.sexp> <output.svg>\n",
            .{name},
        ) catch "usage: schematic <module.sexp> <pinout.sexp> <interface.sexp> <output.svg>\n";
        reportStderr(init, message);
        std.process.exit(2);
    }
    global_alloc = init.gpa;
    var docs: [3][]const u8 = undefined;
    for (args[1..4], 0..) |path, index| {
        docs[index] = std.Io.Dir.cwd().readFileAlloc(init.io, path, init.gpa, .unlimited) catch {
            var buffer: [512]u8 = undefined;
            const message = std.fmt.bufPrint(&buffer, "schematic: {s}: read failed\n", .{path}) catch "schematic: read failed\n";
            reportStderr(init, message);
            std.process.exit(2);
        };
    }
    const ctx = Ctx{ .docs = docs };
    const nodes = parse(&ctx, 0) catch return issueExit(init);
    const pinout = parse(&ctx, 1) catch return issueExit(init);
    const interface = parse(&ctx, 2) catch return issueExit(init);
    const drawing = build(&ctx, nodes, pinout, interface) catch return issueExit(init);
    const svg = render(&ctx, &drawing);
    const file = std.Io.Dir.cwd().createFile(init.io, args[4], .{}) catch {
        var buffer: [512]u8 = undefined;
        const message = std.fmt.bufPrint(&buffer, "schematic: {s}: write failed\n", .{args[4]}) catch "schematic: write failed\n";
        reportStderr(init, message);
        std.process.exit(2);
    };
    defer file.close(init.io);
    file.writeStreamingAll(init.io, svg.items) catch {
        var buffer: [512]u8 = undefined;
        const message = std.fmt.bufPrint(&buffer, "schematic: {s}: write failed\n", .{args[4]}) catch "schematic: write failed\n";
        reportStderr(init, message);
        std.process.exit(2);
    };
}
