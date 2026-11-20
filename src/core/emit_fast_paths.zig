//! The runtime helpers a unit defines from one prelude (`emit_llvm.zig`): the prelude's text before its first definition,
//! then each `define internal` function the unit's body or element layouts name, and every helper those name, in first-use
//! order. A prelude is parsed once for a program (`Prelude.parse`, kept by `emit_survey.Survey`), and a unit's text is read
//! once for the symbols it names (`Named`). Before, each unit scanned its whole text once for each helper's name.
const std = @import("std");
const Symbols = @import("emit_constants.zig").Symbols;
const Out = std.ArrayList(u8);

/// Allocation, or a prelude with no definition or an unnamed one.
pub const Error = error{ OutOfMemory, UnsupportedInstruction };

/// One prelude, split: its head (the text before the first definition), each definition with its name, and for each
/// definition the prelude's names it mentions, as indices into `names` in ascending order.
pub const Prelude = struct {
    text: []const u8,
    head: []const u8,
    definitions: []const []const u8,
    names: []const []const u8,
    uses: []const []const u32,

    /// Split `text`. Its definitions start at the first `define internal` and each ends at a line holding `}`.
    pub fn parse(a: std.mem.Allocator, text: []const u8) Error!Prelude {
        const first = std.mem.indexOf(u8, text, "define internal") orelse return error.UnsupportedInstruction;
        var definitions: std.ArrayList([]const u8) = .empty;
        var names: std.ArrayList([]const u8) = .empty;
        var start = first;
        while (start < text.len) {
            const close = std.mem.indexOfPos(u8, text, start, "\n}\n") orelse break;
            const definition = text[start .. close + 3];
            var refs: Symbols = .{ .text = definition };
            const name = refs.next() orelse return error.UnsupportedInstruction;
            try definitions.append(a, definition);
            try names.append(a, name);
            start = close + 3;
        }
        const uses = try a.alloc([]const u32, definitions.items.len);
        for (definitions.items, uses) |definition, *used| {
            var found: std.ArrayList(u32) = .empty;
            for (names.items, 0..) |name, index| if (mentions(definition, name)) try found.append(a, @intCast(index));
            used.* = found.items;
        }
        return .{ .text = text, .head = text[0..first], .definitions = definitions.items, .names = names.items, .uses = uses };
    }
};

/// The global symbols some texts name (`emit_constants.Symbols`: quoted data and metadata strings excluded).
pub const Named = struct {
    set: std.StringHashMapUnmanaged(void) = .empty,

    /// The symbols every text of `texts` names.
    pub fn of(a: std.mem.Allocator, texts: []const []const u8) std.mem.Allocator.Error!Named {
        var named: Named = .{};
        for (texts) |text| {
            var refs: Symbols = .{ .text = text };
            while (refs.next()) |name| try named.set.put(a, name, {});
        }
        return named;
    }

    /// Whether one of the texts names `name`.
    pub fn has(self: *const Named, name: []const u8) bool {
        return self.set.contains(name);
    }
};

/// Append `prelude`'s head, then each definition whose name `named` holds, then every definition an appended one mentions,
/// each once, in the order they are first reached.
pub fn append(a: std.mem.Allocator, out: *Out, prelude: *const Prelude, named: *const Named) std.mem.Allocator.Error!void {
    try out.appendSlice(a, prelude.head);
    var reached: std.ArrayList(u32) = .empty;
    for (prelude.names, 0..) |name, index| if (named.has(name)) try reached.append(a, @intCast(index));
    var at: usize = 0;
    while (at < reached.items.len) : (at += 1) {
        const index = reached.items[at];
        try out.appendSlice(a, prelude.definitions[index]);
        for (prelude.uses[index]) |dependency| {
            if (std.mem.indexOfScalar(u32, reached.items, dependency) != null) continue;
            try reached.append(a, dependency);
        }
    }
}

/// Whether `text` names the global symbol `name`.
pub fn mentions(text: []const u8, name: []const u8) bool {
    var refs: Symbols = .{ .text = text };
    while (refs.next()) |ref| if (std.mem.eql(u8, ref, name)) return true;
    return false;
}
