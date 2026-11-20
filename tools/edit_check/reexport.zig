//! Which top-level items of a Zig file depend on an import of another file (EC2's re-export rule,
//! `--importers reexport`). A value of a file A reaches code outside A's functions in two ways: a
//! file that imports A has a container-level `const`, `var` or function that uses it (a value computed at
//! compile time, or a function the importer's importers call), and the file's own importers read that item.
//! The impact step follows the importers of a file only through the files for which `reexports` is true.
//!
//! The check is textual and over-approximates: an item is tainted when it names an identifier that a
//! tainted item defines (or the item imports the file), so a selection can widen, but an item that depends on
//! the file is not missed. An item starts at a column-0 line whose first word is an item keyword; the lines
//! after it up to the next such line belong to it.
const std = @import("std");

/// The words a column-0 line may start an item with.
const item_words = [_][]const u8{ "pub", "const", "var", "fn", "usingnamespace", "test", "export", "extern", "inline", "threadlocal", "comptime" };
/// Words that may precede the defining keyword of an item.
const modifier_words = [_][]const u8{ "pub", "export", "extern", "inline", "threadlocal", "comptime", "noinline" };

/// One top-level item of a file.
pub const Item = struct {
    /// The item's text, from its first line to the line before the next item.
    text: []const u8,
    /// The name a `const`, `var` or `fn` item defines (empty for the others).
    name: []const u8,
    /// Whether the item is `pub`, so an importer can reach it.
    is_pub: bool,
    /// Whether the item is a `usingnamespace`, which brings another file's items into this one.
    is_using: bool,
    /// Whether the item is a function (`fn`).
    is_function: bool,
    /// Whether the item is a `test` block: its body runs at run time, so it is never a compile-time use.
    is_test: bool,
    /// Whether the item is evaluated at compile time whatever it is: a `const`, `var`, `comptime` or `usingnamespace`
    /// item, or a function that returns a `type` (its body builds a type).
    compile_time: bool,
    /// Whether the item is a file-level item; a member of a container otherwise (`appendItem`).
    top_level: bool = true,
    /// What the item's tokens refer to.
    refs: Refs = .{},
    /// What the tokens of its `comptime` expressions and blocks refer to (`comptime f()`, `comptime { ... }`), which run
    /// at compile time inside a function or test body; empty when it has none.
    comptime_refs: Refs = .{},
};

/// The references an item's tokens make. Only tokens count: a string's or a comment's words name nothing, except a
/// whole string, which `@field` may read as a name.
pub const Refs = struct {
    /// Every identifier.
    words: std.StringHashMapUnmanaged(void) = .empty,
    /// The calls (a name directly followed by `(`), keyed as `fields` are, and a bare call by its name.
    calls: std.StringHashMapUnmanaged(void) = .empty,
    /// Each name after a dot, keyed twice: `R` NUL `name` (`R` the root of the dotted path, `a` of `a.b.name`, or the
    /// `@import("...")` an inline import spells) and NUL `name` (whatever comes before the dot).
    fields: std.StringHashMapUnmanaged(void) = .empty,
    /// The roots each name after a dot is reached from (`fields`), and those of the calls (`calls`).
    roots: Roots = .{},
    /// The contents of the string literals.
    strings: std.StringHashMapUnmanaged(void) = .empty,
    /// The identifiers a call is qualified by (`Q` of `Q.name(`): a call through a value of that name.
    call_qualifiers: std.StringHashMapUnmanaged(void) = .empty,
    /// Whether the item calls a member of an indexed or called value (`table[i].run(`, `get().run(`).
    indirect_calls: bool = false,
};

/// What a tainted name is to the items that refer to it: a function (it runs when called), a value that refers to tainted
/// functions without calling them (`pointers`: a table of them, which runs them when something calls through it), or a
/// value whose compile-time evaluation runs a tainted function (`evaluates`: naming it is a use).
pub const Kind = enum { function, pointers, evaluates };

/// The roots of the dotted paths that reach each name, for its references and for its calls.
pub const Roots = struct {
    fields: std.StringHashMapUnmanaged(std.ArrayList([]const u8)) = .empty,
    calls: std.StringHashMapUnmanaged(std.ArrayList([]const u8)) = .empty,
};

/// One name a compile-time search looks for: an item's name, whether it is a file-level item (another file reaches it
/// only through an import of its file) or a container member (reached through any value of its type), and its kind.
pub const Name = struct { text: []const u8, top_level: bool, kind: Kind };

/// How a searched file refers to the names: as its own (a bare name, or any member access), or through an import
/// (`imported`). A file-level name of the imported file is reached through a path rooted at one of `allowed` (the
/// importer's bindings of that file, their renames, or the `@import("...")` it spells), or at a root the importer does
/// not otherwise define (a `comptime` parameter, a local value: it may hold the file); a root in `excluded` (another
/// import's binding, `std`, a name the importer defines) is something else. A file that brings the names in with
/// `usingnamespace` is searched as its own.
pub const Scope = union(enum) { own, imported: Imported };

/// The roots an importer reaches an imported file through, and those that are something else (`Scope`).
pub const Imported = struct { allowed: []const []const u8, excluded: *const Set };

/// Whether `word` starts a column-0 item.
fn startsItem(line: []const u8) bool {
    if (line.len == 0 or !(std.ascii.isAlphabetic(line[0]) or line[0] == '_' or line[0] == '@')) return false;
    const word = firstWord(line);
    for (item_words) |item_word| if (std.mem.eql(u8, word, item_word)) return true;
    return false;
}

/// The identifier-like run at the start of `line`.
fn firstWord(line: []const u8) []const u8 {
    var end: usize = 0;
    while (end < line.len and isIdentifierByte(line[end])) end += 1;
    return line[0..end];
}

/// Whether `byte` may be part of an identifier.
fn isIdentifierByte(byte: u8) bool {
    return std.ascii.isAlphanumeric(byte) or byte == '_' or byte == '@';
}

/// The name a `const`, `var` or `fn` item defines, from its first line; empty for the other items.
fn nameOf(line: []const u8) []const u8 {
    var rest = line;
    while (true) {
        const word = firstWord(rest);
        if (word.len == 0) return "";
        var modifier = false;
        for (modifier_words) |candidate| modifier = modifier or std.mem.eql(u8, word, candidate);
        if (!modifier) {
            if (!std.mem.eql(u8, word, "const") and !std.mem.eql(u8, word, "var") and !std.mem.eql(u8, word, "fn")) return "";
            var after = rest[word.len..];
            while (after.len > 0 and after[0] == ' ') after = after[1..];
            return firstWord(after);
        }
        rest = rest[word.len..];
        while (rest.len > 0 and rest[0] == ' ') rest = rest[1..];
    }
}

/// The items of `source`, in order. Text before the first item is an item with no name and no `pub`. A constant that
/// opens a container type (`const S = struct {`) is split into its members (`appendItem`).
pub fn items(arena: std.mem.Allocator, source: []const u8) ![]Item {
    var list: std.ArrayList(Item) = .empty;
    var start: usize = 0;
    var first_line = true;
    var offset: usize = 0;
    while (offset <= source.len) {
        const end = std.mem.indexOfScalarPos(u8, source, offset, '\n') orelse source.len;
        const line = source[offset..end];
        if (!first_line and startsItem(line)) {
            try appendItem(arena, &list, source[start..offset], member_indent);
            start = offset;
        }
        first_line = false;
        if (end == source.len) break;
        offset = end + 1;
    }
    try appendItem(arena, &list, source[start..], member_indent);
    return list.toOwnedSlice(arena);
}

/// The indentation of a container's members, per nesting level (`zig fmt`'s four spaces).
const member_indent = 4;

/// Append the item of `text` (its first line unindented), splitting a container constant into its members: a function or
/// test member becomes an item of its own, described as a top-level function is (run time, unless it returns a `type`),
/// and a member constant that opens a container is split the same way. The container's other lines (fields and their
/// defaults, member constants, `comptime` blocks, the closing line) stay in the container's own item, which is evaluated at
/// compile time; comment lines are dropped from it. So a run-time call in a method is not a compile-time use of the
/// container, while a compile-time caller of the method is still found through the method's name.
fn appendItem(arena: std.mem.Allocator, list: *std.ArrayList(Item), text: []const u8, indent: usize) error{OutOfMemory}!void {
    const line_end = std.mem.indexOfScalar(u8, text, '\n') orelse text.len;
    if (line_end == text.len or !opensContainer(text[0..line_end])) {
        var item = try describe(arena, text);
        item.top_level = indent == member_indent;
        return list.append(arena, item);
    }
    var own: std.ArrayList(u8) = .empty;
    try own.appendSlice(arena, text[0 .. line_end + 1]);
    var member: ?[2]usize = null;
    var offset = line_end + 1;
    while (offset < text.len) {
        const end = std.mem.indexOfScalarPos(u8, text, offset, '\n') orelse text.len;
        const next = @min(end + 1, text.len);
        const line = text[offset..end];
        const at_member = line.len > indent and std.mem.allEqual(u8, line[0..indent], ' ') and line[indent] != ' ';
        // A member's own lines at the member indentation: the end of a signature split over lines, and the closing brace.
        const continues = at_member and member != null and (line[indent] == ')' or line[indent] == '}');
        if (continues) {
            member.?[1] = next;
            if (line[indent] == '}') {
                try appendMember(arena, list, text[member.?[0]..member.?[1]], indent);
                member = null;
            }
        } else if (at_member or line.len > 0 and line[0] != ' ') {
            if (member) |span| try appendMember(arena, list, text[span[0]..span[1]], indent);
            member = null;
            const dedented = if (at_member) line[indent..] else line;
            if (at_member and startsItem(dedented) and isMember(dedented)) {
                member = .{ offset, next };
            } else if (!std.mem.startsWith(u8, std.mem.trimStart(u8, line, " "), "//")) {
                try own.appendSlice(arena, text[offset..next]);
            }
        } else if (member) |*span| {
            span[1] = next;
        } else if (!std.mem.startsWith(u8, std.mem.trimStart(u8, line, " "), "//")) {
            try own.appendSlice(arena, text[offset..next]);
        }
        offset = next;
    }
    if (member) |span| try appendMember(arena, list, text[span[0]..span[1]], indent);
    var container = try describe(arena, own.items);
    // The copy lives in the caller's scratch arena; the name must point into the source, as every item's does.
    container.name = nameOf(text[0..line_end]);
    container.top_level = indent == member_indent;
    try list.append(arena, container);
}

/// Append one member of a container (`text` starts at the member's indentation `indent`) as an item of its own.
fn appendMember(arena: std.mem.Allocator, list: *std.ArrayList(Item), text: []const u8, indent: usize) error{OutOfMemory}!void {
    try appendItem(arena, list, text[indent..], indent + member_indent);
}

/// Whether a member line (unindented) starts a member that is an item of its own: a function, a test, or a constant
/// that opens a container (its own members are split in turn).
fn isMember(line: []const u8) bool {
    const keyword = keywordOf(line);
    return keyword == .@"fn" or keyword == .@"test" or opensContainer(line);
}

/// Whether an item's first line binds a container type whose body opens on that line: `const S = struct {`,
/// `pub const U = union(enum) {`, `const E = enum(u8) {`, `extern struct`, `packed struct(u32)`, `opaque`.
fn opensContainer(first: []const u8) bool {
    const keyword = keywordOf(first);
    if (keyword != .@"const" and keyword != .@"var") return false;
    const equals = std.mem.indexOfScalar(u8, first, '=') orelse return false;
    if (!std.mem.endsWith(u8, std.mem.trimEnd(u8, first, " \t\r"), "{")) return false;
    var value = std.mem.trimStart(u8, first[equals + 1 ..], " ");
    for ([_][]const u8{ "extern ", "packed " }) |layout| {
        if (std.mem.startsWith(u8, value, layout)) value = value[layout.len..];
    }
    for ([_][]const u8{ "struct", "union", "enum", "opaque" }) |container| {
        if (std.mem.startsWith(u8, value, container) and (value.len == container.len or !isIdentifierByte(value[container.len]))) return true;
    }
    return false;
}

/// The item of `text` with its name, visibility and identifiers.
fn describe(arena: std.mem.Allocator, text: []const u8) !Item {
    const line_end = std.mem.indexOfScalar(u8, text, '\n') orelse text.len;
    const first = text[0..line_end];
    const keyword = keywordOf(first);
    var item: Item = .{ .text = text, .name = nameOf(first), .is_pub = std.mem.startsWith(u8, first, "pub "), .is_using = false, .is_function = keyword == .@"fn", .is_test = keyword == .@"test", .compile_time = false };
    const collected = try collect(arena, text);
    item.refs = collected.all;
    item.comptime_refs = collected.compile_time;
    item.is_using = std.mem.eql(u8, firstWord(first), "usingnamespace") or std.mem.indexOf(u8, first, " usingnamespace ") != null;
    // A `const`, `var`, `comptime` or `usingnamespace` item is evaluated at compile time; a function only when it
    // returns a type. Comments and other text before the first item are not evaluated at all.
    const returns_type = item.is_function and (std.mem.indexOf(u8, first, ") type") != null);
    const declares_value = keyword == .@"const" or keyword == .@"var" or std.mem.startsWith(u8, first, "comptime");
    item.compile_time = declares_value or item.is_using or returns_type;
    return item;
}

/// The keyword an item's first line defines, after its modifiers (`pub`, `export`, ...); `.none` for other lines.
fn keywordOf(first: []const u8) enum { @"const", @"var", @"fn", @"test", other, none } {
    var rest = first;
    while (true) {
        const word = firstWord(rest);
        if (word.len == 0) return .none;
        if (std.mem.eql(u8, word, "const")) return .@"const";
        if (std.mem.eql(u8, word, "var")) return .@"var";
        if (std.mem.eql(u8, word, "fn")) return .@"fn";
        if (std.mem.eql(u8, word, "test")) return .@"test";
        var modifier = false;
        for (modifier_words) |candidate| modifier = modifier or std.mem.eql(u8, word, candidate);
        if (!modifier) return .other;
        rest = rest[word.len..];
        while (rest.len > 0 and rest[0] == ' ') rest = rest[1..];
    }
}

/// What a compile-time use of the names `seeds` reaches in one file: `names` are the names of the items that refer to a
/// seed, closed over the items that refer to those (functions included), and `compile_time` is true when one of the
/// file's compile-time items (see `Item.compile_time`) uses one of them: calls a function, or names a value.
pub const Reach = struct {
    names: []const Name,
    compile_time: bool,
};

/// The references of `text`'s tokens (`Refs`): all of them, and those of its `comptime` expressions and blocks.
fn collect(arena: std.mem.Allocator, text: []const u8) error{OutOfMemory}!struct { all: Refs, compile_time: Refs } {
    const terminated = try arena.dupeSentinel(u8, text, 0);
    var tokenizer = std.zig.Tokenizer.init(terminated);
    var tokens: std.ArrayList(std.zig.Token) = .empty;
    while (true) {
        const token = tokenizer.next();
        if (token.tag == .eof) break;
        try tokens.append(arena, token);
    }
    const all = tokens.items;
    const everything = try arena.alloc(bool, all.len);
    @memset(everything, true);
    const regions = try comptimeRegions(arena, all);
    var compile_time: Refs = .{};
    if (std.mem.indexOfScalar(bool, regions, true) != null) compile_time = try gather(arena, terminated, all, regions);
    return .{ .all = try gather(arena, terminated, all, everything), .compile_time = compile_time };
}

/// Which tokens are inside a `comptime` expression or block: from the token after `comptime` through its matching
/// brace (a block), or up to the end of its expression (a `;` or `,` at its depth, or the bracket that closes the
/// enclosing one). A `comptime` parameter or field (`comptime T: type`) is no region.
fn comptimeRegions(arena: std.mem.Allocator, all: []const std.zig.Token) error{OutOfMemory}![]bool {
    const inside = try arena.alloc(bool, all.len);
    @memset(inside, false);
    for (all, 0..) |token, index| {
        if (token.tag != .keyword_comptime or index + 1 >= all.len) continue;
        const first = index + 1;
        if (all[first].tag == .identifier and first + 1 < all.len and all[first + 1].tag == .colon) continue;
        var depth: isize = 0;
        var at = first;
        while (at < all.len) : (at += 1) {
            switch (all[at].tag) {
                .l_paren, .l_bracket, .l_brace => depth += 1,
                .r_paren, .r_bracket, .r_brace => depth -= 1,
                else => {},
            }
            if (depth < 0) break;
            inside[at] = true;
            if (depth == 0 and all[first].tag == .l_brace and all[at].tag == .r_brace) break;
            if (depth == 0 and (all[at].tag == .semicolon or all[at].tag == .comma)) break;
        }
    }
    return inside;
}

/// The references of the tokens `selected` marks (`Refs`).
fn gather(arena: std.mem.Allocator, terminated: [:0]const u8, all: []const std.zig.Token, selected: []const bool) error{OutOfMemory}!Refs {
    var refs: Refs = .{};
    var reflects = false;
    for (all, 0..) |token, index| {
        if (!selected[index]) continue;
        const spelled = terminated[token.loc.start..token.loc.end];
        if (token.tag == .string_literal and spelled.len >= 2) try refs.strings.put(arena, spelled[1 .. spelled.len - 1], {});
        if (token.tag == .builtin) {
            for ([_][]const u8{ "@field", "@hasDecl", "@call" }) |reflection| reflects = reflects or std.mem.eql(u8, spelled, reflection);
        }
        if (token.tag != .identifier) continue;
        try refs.words.put(arena, spelled, {});
        // `fn name(` declares the name; it is no call.
        const called = index + 1 < all.len and all[index + 1].tag == .l_paren and (index == 0 or all[index - 1].tag != .keyword_fn);
        if (index == 0 or all[index - 1].tag != .period) {
            if (called) try refs.calls.put(arena, spelled, {});
            continue;
        }
        // A decl literal of a standard-library field type (`next: std.atomic.Value(usize) = .init(0)`) names a member of
        // that type, which no repository change touches.
        if (index >= 2 and all[index - 2].tag == .equal and standardFieldType(terminated, all, index - 2)) continue;
        const any = try std.mem.concat(arena, u8, &.{ "\x00", spelled });
        try refs.fields.put(arena, any, {});
        if (called) try refs.calls.put(arena, any, {});
        if (called and index >= 2 and (all[index - 2].tag == .r_bracket or all[index - 2].tag == .r_paren)) refs.indirect_calls = true;
        if (called) {
            if (qualifierBefore(terminated, all, index - 1)) |qualifier| try refs.call_qualifiers.put(arena, qualifier, {});
        }
        const root = rootBefore(terminated, all, index - 1) orelse continue;
        const key = try std.mem.concat(arena, u8, &.{ root, "\x00", spelled });
        try refs.fields.put(arena, key, {});
        try addRoot(arena, &refs.roots.fields, spelled, root);
        if (called) {
            try refs.calls.put(arena, key, {});
            try addRoot(arena, &refs.roots.calls, spelled, root);
        }
    }
    // A string names a member only where reflection reads it (`@field(value, "name")`).
    if (!reflects) refs.strings.clearRetainingCapacity();
    return refs;
}

/// Whether the `=` at token `equal` gives a field a default and the field's type starts with `std` (`name: std.X = ...`):
/// the tokens before it on its line are an identifier, a colon, then `std`.
fn standardFieldType(text: [:0]const u8, tokens: []const std.zig.Token, equal: usize) bool {
    var at = equal;
    while (at > 0) {
        at -= 1;
        if (std.mem.indexOfScalar(u8, text[tokens[at].loc.end..tokens[equal].loc.start], '\n') != null) return false;
        if (tokens[at].tag != .colon) continue;
        if (at + 1 >= equal or tokens[at + 1].tag != .identifier) return false;
        return std.mem.eql(u8, text[tokens[at + 1].loc.start..tokens[at + 1].loc.end], "std");
    }
    return false;
}

/// Record `root` as a root of `name` in `map`, once.
fn addRoot(arena: std.mem.Allocator, map: *std.StringHashMapUnmanaged(std.ArrayList([]const u8)), name: []const u8, root: []const u8) error{OutOfMemory}!void {
    const slot = try map.getOrPut(arena, name);
    if (!slot.found_existing) slot.value_ptr.* = .empty;
    for (slot.value_ptr.items) |seen| if (std.mem.eql(u8, seen, root)) return;
    try slot.value_ptr.append(arena, root);
}

/// The root of the dotted path whose last dot is token `dot`: `a` of `a.b.name`, or the `@import("...")` of an inline
/// import (`@import("a.zig").b.name`); null for a path that starts at anything else (a call's result, an index).
fn rootBefore(text: [:0]const u8, tokens: []const std.zig.Token, dot: usize) ?[]const u8 {
    var at = dot;
    while (at >= 2 and tokens[at - 1].tag == .identifier and tokens[at - 2].tag == .period) at -= 2;
    return qualifierBefore(text, tokens, at);
}

/// What qualifies the field access whose dot is token `dot`: the identifier before it, or the `@import("...")` that an
/// inline import spells (`@import("a.zig").f`); null for anything else (a call's result, an enum literal).
fn qualifierBefore(text: [:0]const u8, tokens: []const std.zig.Token, dot: usize) ?[]const u8 {
    if (dot == 0) return null;
    const before = tokens[dot - 1];
    if (before.tag == .identifier) return text[before.loc.start..before.loc.end];
    if (before.tag != .r_paren or dot < 4) return null;
    const builtin = tokens[dot - 4];
    if (builtin.tag != .builtin or tokens[dot - 3].tag != .l_paren or tokens[dot - 2].tag != .string_literal) return null;
    if (!std.mem.eql(u8, text[builtin.loc.start..builtin.loc.end], "@import")) return null;
    return text[builtin.loc.start..before.loc.end];
}

/// Whether `item` names `name` in `scope`: any reference (a call, a field access, a bare word, or a whole string in an
/// item that reflects, as `@field` reads it).
fn mentions(refs: *const Refs, name: Name, scope: Scope) bool {
    return matches(refs, name, scope, .{ .keyed = &refs.fields, .bare = &refs.words, .roots = &refs.roots.fields });
}

/// Whether `item` calls `name` in `scope`.
fn calls(refs: *const Refs, name: Name, scope: Scope) bool {
    return matches(refs, name, scope, .{ .keyed = &refs.calls, .bare = &refs.calls, .roots = &refs.roots.calls });
}

/// The sets one kind of reference is looked up in: the keys (`Refs.fields` or `Refs.calls`), the bare names and the
/// roots of each name.
const Lookup = struct {
    keyed: *const Set,
    bare: *const Set,
    roots: *const std.StringHashMapUnmanaged(std.ArrayList([]const u8)),
};

/// Whether `keyed` (field keys) or, in the item's own file, `bare` (bare names) holds `name` as `scope` reaches it.
fn matches(refs: *const Refs, name: Name, scope: Scope, lookup: Lookup) bool {
    if (refs.strings.contains(name.text)) return true;
    var any_buffer: [256]u8 = undefined;
    const any = std.fmt.bufPrint(&any_buffer, "\x00{s}", .{name.text}) catch return true;
    switch (scope) {
        .own => return lookup.keyed.contains(any) or lookup.bare.contains(name.text),
        .imported => |imported| {
            if (!name.top_level) return lookup.keyed.contains(any);
            const roots = lookup.roots.get(name.text) orelse return false;
            for (roots.items) |root| {
                for (imported.allowed) |allowed| if (std.mem.eql(u8, root, allowed)) return true;
                if (!imported.excluded.contains(root)) return true;
            }
            return false;
        },
    }
}

/// A set of names or keys.
pub const Set = std.StringHashMapUnmanaged(void);

/// A name the search knows to be tainted: a seed (in the searched scope) or a tainted item of the file (`own`, with the
/// item's index, so that an item's own name is no reference to itself).
const Known = struct { name: Name, scope: Scope, item: ?usize };

/// How `item` refers to the tainted names `known`.
const Uses = struct {
    /// It refers to one of them.
    refers: bool = false,
    /// It calls a tainted function.
    calls_function: bool = false,
    /// It names a tainted function without calling it, or a `pointers` value.
    holds_pointers: bool = false,
    /// It calls through one of those names (`rules[0].run(`, `table.run(`).
    calls_through: bool = false,
    /// It names an `evaluates` value.
    names_evaluated: bool = false,

    /// Whether evaluating the item runs a tainted function: it calls one, names a value that does, or calls through
    /// tainted functions it holds (a call through a table of them, or through an indexed or called value).
    fn evaluates(uses: Uses, refs: *const Refs) bool {
        return uses.calls_function or uses.names_evaluated or (uses.holds_pointers and (uses.calls_through or refs.indirect_calls));
    }
};

/// How the references `refs` of item `index` refer to `known`.
fn usesOf(refs: *const Refs, index: usize, known: []const Known) Uses {
    var uses: Uses = .{};
    for (known) |entry| {
        if (entry.item == index or !mentions(refs, entry.name, entry.scope)) continue;
        uses.refers = true;
        switch (entry.name.kind) {
            .function => if (calls(refs, entry.name, entry.scope)) {
                uses.calls_function = true;
            } else {
                uses.holds_pointers = true;
            },
            .pointers => {
                uses.holds_pointers = true;
                uses.calls_through = uses.calls_through or refs.call_qualifiers.contains(entry.name.text);
            },
            .evaluates => uses.names_evaluated = true,
        }
    }
    return uses;
}

/// The kind a tainted item's name has (`Kind`): a function's is `function`, a bare alias takes the kind of what it
/// renames, and any other value `evaluates` or holds `pointers`.
fn kindOf(item: *const Item, uses: Uses) Kind {
    if (item.is_function) return .function;
    if (isAlias(item.text)) {
        if (uses.names_evaluated) return .evaluates;
        return if (uses.calls_function or uses.holds_pointers) .function else .pointers;
    }
    return if (uses.evaluates(&item.refs)) .evaluates else .pointers;
}

/// Whether an item is a bare alias: one `const` or `var` line whose value is a path (`const f = a.f;`, `pub const g = f;`),
/// with only comment lines after it. An alias is a rename: a compile-time use of the name is a call or an evaluation, and
/// it is the alias's own uses (carried in `Reach.names`) that count.
fn isAlias(text: []const u8) bool {
    const line_end = std.mem.indexOfScalar(u8, text, '\n') orelse text.len;
    var lines = std.mem.splitScalar(u8, text[line_end..], '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len > 0 and !std.mem.startsWith(u8, trimmed, "//")) return false;
    }
    const first = text[0..line_end];
    const keyword = keywordOf(first);
    if (keyword != .@"const" and keyword != .@"var") return false;
    const equals = std.mem.indexOfScalar(u8, first, '=') orelse return false;
    const semicolon = std.mem.indexOfScalarPos(u8, first, equals, ';') orelse return false;
    const value = std.mem.trim(u8, first[equals + 1 .. semicolon], " \t");
    if (value.len == 0) return false;
    for (value) |byte| if (!isIdentifierByte(byte) and byte != '.') return false;
    return true;
}

/// The items of `source` that refer to one of `seeds` in `scope`, and what they reach (`Reach`). Token-based, so it
/// over-approximates: an item is tainted by any reference to a tainted name, and the taint is closed over the file's
/// items by their names (each referring to it as its own), each tainted name with its `Kind`. A compile-time item
/// counts only when its evaluation runs a tainted function (`Uses.evaluates`): naming a type or listing a function is
/// no call. A bare alias (`const f = a.f;`) is a rename: its own uses count instead.
pub fn reach(outer: std.mem.Allocator, source: []const u8, seeds: []const Name, scope: Scope) !Reach {
    // The items and their references are scratch, in an arena of their own: one inside OUTER (an arena) would give
    // nothing back until the whole run ends. The names returned point into `source`; only the list is in OUTER.
    var scratch_state = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer scratch_state.deinit();
    const arena = scratch_state.allocator();
    const list = try items(arena, source);
    const kinds = try arena.alloc(?Kind, list.len);
    @memset(kinds, null);
    var known: std.ArrayList(Known) = .empty;
    // Kinds only grow (none, then `pointers`, then `evaluates`), so the passes reach a fixed point.
    var changed = true;
    while (changed) {
        changed = false;
        known.clearRetainingCapacity();
        for (seeds) |seed| try known.append(arena, .{ .name = seed, .scope = scope, .item = null });
        for (list, kinds, 0..) |item, kind, index| {
            const tainted = kind orelse continue;
            if (item.name.len == 0) continue;
            try known.append(arena, .{ .name = .{ .text = item.name, .top_level = item.top_level, .kind = tainted }, .scope = .own, .item = index });
        }
        for (list, kinds, 0..) |*item, *kind, index| {
            const uses = usesOf(&item.refs, index, known.items);
            if (!uses.refers) continue;
            const next = kindOf(item, uses);
            if (kind.* != null and @backingInt(kind.*.?) >= @backingInt(next)) continue;
            kind.* = next;
            changed = true;
        }
    }
    var names: std.ArrayList(Name) = .empty;
    var compile_time = false;
    for (list, kinds) |item, kind| {
        const tainted = kind orelse continue;
        if (item.name.len > 0) try names.append(outer, .{ .text = item.name, .top_level = item.top_level, .kind = tainted });
    }
    for (list, 0..) |*item, index| {
        if (compile_time) break;
        // A run-time function or test counts through its `comptime` expressions only.
        const refs = if (item.compile_time and !item.is_test) &item.refs else &item.comptime_refs;
        if (isAlias(item.text) or refs.words.count() == 0) continue;
        compile_time = usesOf(refs, index, known.items).evaluates(refs);
    }
    return .{ .names = try names.toOwnedSlice(outer), .compile_time = compile_time };
}

/// Every identifier `source`'s tokens spell, and every string's contents (which reflection may read as a name): a name
/// that is not among them is no reference anywhere in the file. The keys are allocated in OUTER.
pub fn vocabulary(outer: std.mem.Allocator, source: []const u8) error{OutOfMemory}!Set {
    var words: Set = .empty;
    const terminated = try outer.dupeSentinel(u8, source, 0);
    var tokenizer = std.zig.Tokenizer.init(terminated);
    while (true) {
        const token = tokenizer.next();
        if (token.tag == .eof) break;
        const spelled = terminated[token.loc.start..token.loc.end];
        if (token.tag == .identifier) try words.put(outer, spelled, {});
        if (token.tag == .string_literal and spelled.len >= 2) try words.put(outer, spelled[1 .. spelled.len - 1], {});
    }
    return words;
}

/// The functions `source` defines (every `fn`, public or not, members of containers included), in order.
pub fn functionNames(outer: std.mem.Allocator, source: []const u8) ![]const Name {
    var scratch_state = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer scratch_state.deinit();
    var names: std.ArrayList(Name) = .empty;
    for (try items(scratch_state.allocator(), source)) |item| {
        if (item.is_function and item.name.len > 0) try names.append(outer, .{ .text = item.name, .top_level = item.top_level, .kind = .function });
    }
    return names.toOwnedSlice(outer);
}

/// The roots that are something other than an imported file in `source` (`Imported.excluded`): the names its file-level
/// items define (its bindings of other files among them) and `std`, `builtin` and `root`. The keys point into `source`.
pub fn definedRoots(outer: std.mem.Allocator, source: []const u8) error{OutOfMemory}!Set {
    var scratch_state = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer scratch_state.deinit();
    var found: Set = .empty;
    for ([_][]const u8{ "std", "builtin", "root" }) |name| try found.put(outer, name, {});
    for (try items(scratch_state.allocator(), source)) |item| {
        if (item.top_level and item.name.len > 0) try found.put(outer, item.name, {});
    }
    return found;
}

/// The qualifiers through which `source` refers to the file its `literals` import (the exact `@import("...")`
/// spellings in it that resolve to that file): the literals themselves (an inline import) and the names of the
/// file-level constants that bind one of them, or that rename such a binding (`const out = output;`).
pub fn qualifiers(outer: std.mem.Allocator, source: []const u8, literals: []const []const u8) ![]const []const u8 {
    var scratch_state = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer scratch_state.deinit();
    const list = try items(scratch_state.allocator(), source);
    var found: std.ArrayList([]const u8) = .empty;
    try found.appendSlice(outer, literals);
    for (list) |item| {
        if (!item.top_level or item.name.len == 0 or item.is_function) continue;
        const line_end = std.mem.indexOfScalar(u8, item.text, '\n') orelse item.text.len;
        for (literals) |literal| {
            if (std.mem.indexOf(u8, item.text[0..line_end], literal) == null) continue;
            try found.append(outer, item.name);
            break;
        }
    }
    const bound = found.items.len;
    for (list) |item| {
        if (!item.top_level or item.name.len == 0 or !isAlias(item.text)) continue;
        for (found.items[literals.len..bound]) |binding| {
            if (!item.refs.words.contains(binding) or item.refs.words.count() > 3) continue;
            try found.append(outer, item.name);
            break;
        }
    }
    return found.toOwnedSlice(outer);
}

/// Whether the file `source` re-exports something from the file its `literals` import: `literals` are the exact
/// `@import("...")` spellings in it that resolve to that file. True when a `pub` item, or a `usingnamespace`, is
/// tainted: it imports the file, or it names an identifier a tainted item defines.
pub fn reexports(source: []const u8, literals: []const []const u8) !bool {
    if (literals.len == 0) return false;
    // The items and their word sets are scratch, in an arena of their own: a caller asks once per importer, and the
    // whole file's words would otherwise stay allocated for the rest of the run (6 GB on one replay sample).
    var scratch_state = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer scratch_state.deinit();
    const arena = scratch_state.allocator();
    const list = try items(arena, source);
    const tainted = try arena.alloc(bool, list.len);
    @memset(tainted, false);
    var queue: std.ArrayList(usize) = .empty;
    for (list, 0..) |item, index| {
        for (literals) |literal| {
            if (std.mem.indexOf(u8, item.text, literal) == null) continue;
            tainted[index] = true;
            try queue.append(arena, index);
            break;
        }
    }
    var next: usize = 0;
    while (next < queue.items.len) : (next += 1) {
        const defined = list[queue.items[next]].name;
        if (defined.len == 0) continue;
        for (list, 0..) |item, index| {
            if (tainted[index] or !item.refs.words.contains(defined)) continue;
            tainted[index] = true;
            try queue.append(arena, index);
        }
    }
    for (list, tainted) |item, flag| {
        // The re-export behaviour (lane F): a public value (`pub const`, `pub var`, a type alias) or a `usingnamespace`.
        // A public function is left out: rule 2 of the impact tool covers a compile-time call of one.
        if (flag and ((item.is_pub and !item.is_function) or item.is_using)) return true;
    }
    return false;
}

/// The scope of the tests' importer searches: a file that imports the searched-for file as `a` or `output`.
fn importedScope(arena: std.mem.Allocator) !Scope {
    return importedVia(arena, &.{ "a", "output" });
}

/// The scope of a test importer that reaches the searched-for file through `allowed` and defines `other` (another
/// import's binding) and `std`.
fn importedVia(arena: std.mem.Allocator, allowed: []const []const u8) !Scope {
    const excluded = try arena.create(Set);
    excluded.* = .empty;
    try excluded.put(arena, "other", {});
    try excluded.put(arena, "std", {});
    return .{ .imported = .{ .allowed = allowed, .excluded = excluded } };
}

test "a pub constant that uses an import of the file re-exports it" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const literal: []const []const u8 = &.{"@import(\"a.zig\")"};
    try std.testing.expect(try reexports("const a = @import(\"a.zig\");\npub const L = a.LIMIT * 2;\n", literal));
    try std.testing.expect(try reexports("const a = @import(\"a.zig\");\npub const S = struct {\n    x: u32 = a.LIMIT,\n};\n", literal));
    try std.testing.expect(try reexports("const a = @import(\"a.zig\");\nusingnamespace a;\n", literal));
    try std.testing.expect(!try reexports("const a = @import(\"a.zig\");\npub fn g() u32 {\n    return a.LIMIT;\n}\n", literal));
}

test "a constant reaches the pub items only through the names it defines" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const literal: []const []const u8 = &.{"@import(\"a.zig\")"};
    try std.testing.expect(try reexports("const a = @import(\"a.zig\");\nconst M = a.LIMIT;\npub const N = M + 1;\n", literal));
    try std.testing.expect(!try reexports("const a = @import(\"a.zig\");\nconst L = a.LIMIT;\nfn f() u32 {\n    return L;\n}\npub const K = 3;\n", literal));
    try std.testing.expect(!try reexports("const a = @import(\"a.zig\");\npub const K = 3;\n", literal));
    try std.testing.expect(!try reexports("const std = @import(\"std\");\npub const L = 2;\n", &.{"@import(\"a.zig\")"}));
}

test "the items of a file start at column-0 keywords and keep their continuation lines" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const split = try items(arena, "const x = 1;\n/// doc\npub fn f() void {\n    return;\n}\n\npub const T = struct {\n    y: u8 = 2,\n};\n");
    try std.testing.expectEqual(@as(usize, 3), split.len);
    try std.testing.expectEqualStrings("x", split[0].name);
    try std.testing.expectEqualStrings("f", split[1].name);
    try std.testing.expect(split[1].is_pub);
    try std.testing.expect(std.mem.indexOf(u8, split[1].text, "return;") != null);
    try std.testing.expect(std.mem.indexOf(u8, split[2].text, "y: u8") != null);
}

test "a compile-time use of a seed reaches the constants that name it, through functions that name it" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const seeds: []const Name = &.{.{ .text = "f", .top_level = true, .kind = .function }};
    const constant = try reach(arena, "fn g() u32 {\n    return f(1);\n}\npub const K = g();\n", seeds, .own);
    try std.testing.expect(constant.compile_time);
    try std.testing.expectEqual(@as(usize, 2), constant.names.len);
    const type_builder = try reach(arena, "pub fn T() type {\n    return struct {\n        const L = f(1);\n    };\n}\n", seeds, .own);
    try std.testing.expect(type_builder.compile_time);
}

test "a use of a seed only in function bodies, or in a test, is not a compile-time use" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const seeds: []const Name = &.{.{ .text = "f", .top_level = true, .kind = .function }};
    const run_time = try reach(arena, "fn g() u32 {\n    return f(1);\n}\npub fn h() u32 {\n    return g();\n}\n", seeds, .own);
    try std.testing.expect(!run_time.compile_time);
    try std.testing.expectEqual(@as(usize, 2), run_time.names.len);
    const in_test = try reach(arena, "test \"t\" {\n    _ = f(1);\n}\n", seeds, .own);
    try std.testing.expect(!in_test.compile_time);
    try std.testing.expectEqual(@as(usize, 0), in_test.names.len);
}

test "an importer reaches a name through its field access, not through a bare word of its own" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const seeds: []const Name = &.{.{ .text = "init", .top_level = true, .kind = .function }};
    const qualified = try reach(arena, "pub const K = a.init(2);\n", seeds, try importedScope(arena));
    try std.testing.expect(qualified.compile_time);
    const bare = try reach(arena, "pub const K = init(2);\n", seeds, try importedScope(arena));
    try std.testing.expect(!bare.compile_time);
    const own_item = try reach(arena, "pub const K = 2;\npub fn init() u32 {\n    return K;\n}\n", seeds, try importedScope(arena));
    try std.testing.expect(!own_item.compile_time);
}

test "a bare alias is a rename, not a compile-time use: its own call counts" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const seeds: []const Name = &.{.{ .text = "f", .top_level = true, .kind = .function }};
    const rename = try reach(arena, "pub const g = f;\n", seeds, .own);
    try std.testing.expect(!rename.compile_time);
    try std.testing.expectEqual(@as(usize, 1), rename.names.len);
    const used = try reach(arena, "const g = f;\npub const K = g(2);\n", seeds, .own);
    try std.testing.expect(used.compile_time);
    try std.testing.expect(isAlias("pub const g = a.f;\n"));
    try std.testing.expect(!isAlias("pub const K = a.f(2);\n"));
}

test "a run-time call in a container's method is not a compile-time use of the container" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const seeds: []const Name = &.{.{ .text = "render", .top_level = true, .kind = .function }};
    const source = "const output = @import(\"output.zig\");\npub const Cache = struct {\n    format: u8 = 0,\n    /// Keep a render of the format.\n    pub fn remember(self: *Cache) void {\n        _ = output.render(self.format);\n    }\n};\n";
    const found = try reach(arena, source, seeds, try importedScope(arena));
    try std.testing.expect(!found.compile_time);
    try std.testing.expectEqual(@as(usize, 1), found.names.len);
    try std.testing.expectEqualStrings("remember", found.names[0].text);
    const split_signature = try reach(arena, "pub const S = struct {\n    pub fn g(\n        x: u32,\n    ) u32 {\n        return a.render(x);\n    }\n};\n", seeds, try importedScope(arena));
    try std.testing.expect(!split_signature.compile_time);
    const nested = try reach(arena, "pub const S = struct {\n    pub const Inner = struct {\n        pub fn g() u32 {\n            return a.render(2);\n        }\n    };\n};\n", seeds, try importedScope(arena));
    try std.testing.expect(!nested.compile_time);
    const in_test = try reach(arena, "const S = struct {\n    test \"t\" {\n        _ = a.render(2);\n    }\n};\n", seeds, try importedScope(arena));
    try std.testing.expect(!in_test.compile_time);
}

test "a container's field default, member constant, comptime block or type-returning method that calls a seed is a compile-time use" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const seeds: []const Name = &.{.{ .text = "f", .top_level = true, .kind = .function }};
    try std.testing.expect((try reach(arena, "pub const S = struct {\n    x: u32 = a.f(2),\n};\n", seeds, try importedScope(arena))).compile_time);
    try std.testing.expect((try reach(arena, "pub const S = struct {\n    const L = a.f(2);\n    pub fn g() u32 {\n        return L;\n    }\n};\n", seeds, try importedScope(arena))).compile_time);
    try std.testing.expect((try reach(arena, "const S = struct {\n    comptime {\n        _ = a.f(2);\n    }\n};\n", seeds, try importedScope(arena))).compile_time);
    try std.testing.expect((try reach(arena, "pub const S = struct {\n    pub fn T() type {\n        return [a.f(2)]u8;\n    }\n};\n", seeds, try importedScope(arena))).compile_time);
    try std.testing.expect((try reach(arena, "pub const U = union(enum) {\n    a: u32,\n    const L = a.f(2);\n};\n", seeds, try importedScope(arena))).compile_time);
}

test "a compile-time caller of a method that calls a seed is still a compile-time use" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const seeds: []const Name = &.{.{ .text = "f", .top_level = true, .kind = .function }};
    const caller = try reach(arena, "pub const S = struct {\n    pub fn g() u32 {\n        return a.f(2);\n    }\n};\npub const K = S.g();\n", seeds, try importedScope(arena));
    try std.testing.expect(caller.compile_time);
    const member_caller = try reach(arena, "pub const S = struct {\n    const L = g();\n    fn g() u32 {\n        return a.f(2);\n    }\n};\n", seeds, try importedScope(arena));
    try std.testing.expect(member_caller.compile_time);
}

test "a container's methods are items of their own, and its function names include them" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const source = "pub const S = struct {\n    y: u8 = 2,\n    pub fn g() void {}\n    const Inner = enum(u8) {\n        a,\n        fn h() void {}\n    };\n};\nfn k() void {}\n";
    const names = try functionNames(arena, source);
    try std.testing.expectEqual(@as(usize, 3), names.len);
    try std.testing.expectEqualStrings("g", names[0].text);
    try std.testing.expectEqualStrings("h", names[1].text);
    try std.testing.expectEqualStrings("k", names[2].text);
    const split = try items(arena, source);
    try std.testing.expectEqual(@as(usize, 5), split.len);
    try std.testing.expectEqualStrings("S", split[3].name);
    try std.testing.expect(split[3].compile_time);
    try std.testing.expect(std.mem.indexOf(u8, split[3].text, "y: u8") != null);
    try std.testing.expect(std.mem.indexOf(u8, split[3].text, "fn g") == null);
}

test "an importer's call of a same-named function of another file is no use of the seed" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const seeds: []const Name = &.{.{ .text = "render", .top_level = true, .kind = .function }};
    try std.testing.expect(!(try reach(arena, "pub const K = other.render(2);\n", seeds, try importedScope(arena))).compile_time);
    try std.testing.expect((try reach(arena, "pub const K = output.render(2);\n", seeds, try importedScope(arena))).compile_time);
    const inline_import = try importedVia(arena, &.{"@import(\"output.zig\")"});
    try std.testing.expect((try reach(arena, "pub const K = @import(\"output.zig\").render(2);\n", seeds, inline_import)).compile_time);
    const member: []const Name = &.{.{ .text = "remember", .top_level = false, .kind = .function }};
    try std.testing.expect((try reach(arena, "pub const K = cache.remember();\n", member, try importedScope(arena))).compile_time);
}

test "a function named in a compile-time table is no compile-time call, but a use of the table is" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const seeds: []const Name = &.{.{ .text = "f", .top_level = true, .kind = .function }};
    const table = "pub const rules = [_]Rule{.{ .run = check }};\nfn check() void {\n    _ = a.f(2);\n}\n";
    const listed = try reach(arena, table, seeds, try importedScope(arena));
    try std.testing.expect(!listed.compile_time);
    try std.testing.expectEqual(@as(usize, 2), listed.names.len);
    const counted = try reach(arena, "pub const rules = [_]Rule{.{ .run = check }};\nfn check() void {\n    _ = a.f(2);\n}\nconst n = rules[0].run();\n", seeds, try importedScope(arena));
    try std.testing.expect(counted.compile_time);
}

test "strings and comments name nothing, except a string that reflection reads" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const seeds: []const Name = &.{.{ .text = "f", .top_level = true, .kind = .function }};
    try std.testing.expect(!(try reach(arena, "/// Computed like a.f(2).\npub const K = \"a.f(2)\";\n", seeds, try importedScope(arena))).compile_time);
    try std.testing.expect(!(try reach(arena, "pub const K =\n    \\\\a.f(2)\n;\n", seeds, try importedScope(arena))).compile_time);
    try std.testing.expect((try reach(arena, "pub const K = @field(a, \"f\")(2);\n", seeds, try importedScope(arena))).compile_time);
}

test "an import's qualifiers are its literal, the constants that bind it and their renames" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const found = try qualifiers(arena, "const a = @import(\"a.zig\");\nconst b = a;\nconst c = @import(\"c.zig\");\nfn d() void {}\n", &.{"@import(\"a.zig\")"});
    try std.testing.expectEqual(@as(usize, 3), found.len);
    try std.testing.expectEqualStrings("@import(\"a.zig\")", found[0]);
    try std.testing.expectEqualStrings("a", found[1]);
    try std.testing.expectEqualStrings("b", found[2]);
}

test "a decl literal of a standard-library field type, or an unrelated call, is no call through a tainted table" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const member: []const Name = &.{.{ .text = "init", .top_level = false, .kind = .function }};
    try std.testing.expect(!(try reach(arena, "const Queue = struct {\n    next: std.atomic.Value(usize) = .init(0),\n};\n", member, try importedScope(arena))).compile_time);
    try std.testing.expect((try reach(arena, "const Queue = struct {\n    next: Local = .init(0),\n};\n", member, try importedScope(arena))).compile_time);
    const seeds: []const Name = &.{.{ .text = "f", .top_level = true, .kind = .function }};
    const unrelated = try reach(arena, "pub const rules = [_]Rule{.{ .run = check }};\nfn check() void {\n    _ = a.f(2);\n}\nconst Set = struct {\n    list: std.ArrayList(u8) = .empty,\n    first: Rule = rules[0],\n};\n", seeds, try importedScope(arena));
    try std.testing.expect(!unrelated.compile_time);
    const through = try reach(arena, "pub const rules = [_]Rule{.{ .run = check }};\nfn check() void {\n    _ = a.f(2);\n}\nconst first = rules.first();\n", seeds, try importedScope(arena));
    try std.testing.expect(through.compile_time);
}

test "a comptime expression or block inside a function or test body is a compile-time use; a comptime parameter is not" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const seeds: []const Name = &.{.{ .text = "f", .top_level = true, .kind = .function }};
    try std.testing.expect((try reach(arena, "fn g() u32 {\n    const t = comptime a.f(2);\n    return t;\n}\n", seeds, try importedScope(arena))).compile_time);
    try std.testing.expect((try reach(arena, "pub const S = struct {\n    fn g() void {\n        if (comptime a.f(2)) {}\n    }\n};\n", seeds, try importedScope(arena))).compile_time);
    try std.testing.expect((try reach(arena, "test \"t\" {\n    comptime {\n        _ = a.f(2);\n    }\n}\n", seeds, try importedScope(arena))).compile_time);
    try std.testing.expect(!(try reach(arena, "fn g(comptime T: type) T {\n    return a.f(2);\n}\n", seeds, try importedScope(arena))).compile_time);
    try std.testing.expect(!(try reach(arena, "fn g() u32 {\n    const n = comptime b.size();\n    return a.f(n);\n}\n", seeds, try importedScope(arena))).compile_time);
}

test "a file-level name is reached through a root the importer does not define, not through another import or std" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const seeds: []const Name = &.{.{ .text = "render", .top_level = true, .kind = .function }};
    const scope = try importedScope(arena);
    try std.testing.expect((try reach(arena, "fn W(comptime M: type) type {\n    return [M.render(2)]u8;\n}\n", seeds, scope)).compile_time);
    try std.testing.expect((try reach(arena, "pub const K = output.inner.render(2);\n", seeds, scope)).compile_time);
    try std.testing.expect(!(try reach(arena, "pub const K = std.fmt.render(2);\n", seeds, scope)).compile_time);
    try std.testing.expect(!(try reach(arena, "pub const K = other.render(2);\n", seeds, scope)).compile_time);
}
