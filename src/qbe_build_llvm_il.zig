//! QBE IL as the LLVM translator reads it (LLVM-ZIG-1): one emitted unit's
//! aggregate types, its function, and the type of every temporary.
//!
//! The parser accepts exactly the subset the frontend emits and refuses
//! anything else with a diagnostic naming the unit, the line and the text.
//! Nothing falls back and nothing is silently replaced. Temporaries are
//! mutable cells here, as they are in the IL: the emitter gives each one a
//! slot and lets LLVM's own promotion recover SSA.
const std = @import("std");

/// Translation failures: allocation, or a construct the translator refuses.
pub const Error = error{ OutOfMemory, TranslationFailed };

/// The runtime's failure helpers, each of which records a trap and calls
/// `fail`, share this prefix.
pub const fail_prefix = "myl_qbe_fail_";

/// Where a refusal is recorded: the unit being translated and the message.
pub const Diagnostic = struct {
    unit: []const u8 = "unit",
    message: []const u8 = "",

    /// Record a refusal at `line` of the unit and return `TranslationFailed`.
    pub fn fail(self: *Diagnostic, arena: std.mem.Allocator, line: usize, message: []const u8) Error {
        self.message = try std.fmt.allocPrint(arena, "{s}:{d}: {s}", .{ self.unit, line, message });
        return error.TranslationFailed;
    }
};

/// Every opcode the translator knows. The spellings are QBE's own
/// (`vendor/qbe/ops.h`); anything else is refused by name.
pub const Opcode = enum {
    add,
    sub,
    mul,
    umulh,
    @"and",
    @"or",
    xor,
    shl,
    sar,
    shr,
    div,
    rem,
    udiv,
    urem,
    neg,
    not,
    copy,
    loadsb,
    loadub,
    loadsh,
    loaduh,
    loadsw,
    loaduw,
    loadl,
    loads,
    loadd,
    storeb,
    storeh,
    storew,
    storel,
    stores,
    stored,
    extsw,
    extuw,
    extsh,
    extuh,
    extsb,
    extub,
    exts,
    truncd,
    stosi,
    dtosi,
    stoui,
    dtoui,
    swtof,
    uwtof,
    sltof,
    ultof,
    cast,
    ceqw,
    cnew,
    csltw,
    cultw,
    cslew,
    culew,
    csgtw,
    cugtw,
    csgew,
    cugew,
    ceql,
    cnel,
    csltl,
    cultl,
    cslel,
    culel,
    csgtl,
    cugtl,
    csgel,
    cugel,
    ceqs,
    cnes,
    clts,
    cles,
    cgts,
    cges,
    cos,
    cuos,
    ceqd,
    cned,
    cltd,
    cled,
    cgtd,
    cged,
    cod,
    cuod,
    call,
    ret,
    jmp,
    jnz,
    blit,
    alloc4,
    alloc8,
    alloc16,
    phi,
    hlt,
    dbgloc,

    /// Whether the opcode is one of the integer (or float) arithmetic operations.
    pub fn arithmetic(self: Opcode) bool {
        return @backingInt(self) <= @backingInt(Opcode.urem);
    }
    /// Whether the opcode is a load of any width.
    pub fn isLoad(self: Opcode) bool {
        return @backingInt(self) >= @backingInt(Opcode.loadsb) and @backingInt(self) <= @backingInt(Opcode.loadd);
    }
    /// Whether the opcode is a store of any width.
    pub fn isStore(self: Opcode) bool {
        return @backingInt(self) >= @backingInt(Opcode.storeb) and @backingInt(self) <= @backingInt(Opcode.stored);
    }
    /// Whether the opcode converts between widths or bit patterns.
    pub fn isConversion(self: Opcode) bool {
        return @backingInt(self) >= @backingInt(Opcode.extsw) and @backingInt(self) <= @backingInt(Opcode.cast);
    }
    /// Whether the opcode is a comparison.
    pub fn isComparison(self: Opcode) bool {
        return @backingInt(self) >= @backingInt(Opcode.ceqw) and @backingInt(self) <= @backingInt(Opcode.cuod);
    }
    /// Whether the opcode is a stack allocation.
    pub fn isAlloc(self: Opcode) bool {
        return self == .alloc4 or self == .alloc8 or self == .alloc16;
    }
    /// Whether the opcode is one of the integer widenings.
    pub fn isExtension(self: Opcode) bool {
        return @backingInt(self) >= @backingInt(Opcode.extsw) and @backingInt(self) <= @backingInt(Opcode.extub);
    }
};

/// A load's width in bits and whether it sign-extends.
pub fn loadShape(opcode: Opcode) struct { bits: u16, signed: bool } {
    return switch (opcode) {
        .loadsb => .{ .bits = 8, .signed = true },
        .loadub => .{ .bits = 8, .signed = false },
        .loadsh => .{ .bits = 16, .signed = true },
        .loaduh => .{ .bits = 16, .signed = false },
        .loadsw => .{ .bits = 32, .signed = true },
        .loaduw => .{ .bits = 32, .signed = false },
        .loads => .{ .bits = 32, .signed = true },
        else => .{ .bits = 64, .signed = true },
    };
}

/// A store's width in bits.
pub fn storeBits(opcode: Opcode) u16 {
    return switch (opcode) {
        .storeb => 8,
        .storeh => 16,
        .storew, .stores => 32,
        else => 64,
    };
}

/// An integer arithmetic opcode's LLVM instruction.
pub fn integerInstruction(opcode: Opcode) []const u8 {
    return switch (opcode) {
        .sar => "ashr",
        .shr => "lshr",
        .div => "sdiv",
        .rem => "srem",
        else => @tagName(opcode),
    };
}

/// What a comparison computes: its LLVM predicate, whether its operands are
/// floats, and the LLVM type of its operands.
pub const Comparison = struct { predicate: []const u8, float: bool, operand: []const u8 };

/// The predicate and operand type of one comparison opcode.
pub fn comparison(opcode: Opcode) Comparison {
    const name = @tagName(opcode);
    const last = name[name.len - 1];
    const operand: []const u8 = switch (last) {
        'w' => "i32",
        'l' => "i64",
        's' => "float",
        else => "double",
    };
    const stem = name[1 .. name.len - 1];
    if (last == 'w' or last == 'l') return .{ .predicate = integerPredicate(stem), .float = false, .operand = operand };
    return .{ .predicate = floatPredicate(stem), .float = true, .operand = operand };
}

fn integerPredicate(stem: []const u8) []const u8 {
    const table = [_][2][]const u8{
        .{ "eq", "eq" },   .{ "ne", "ne" },   .{ "slt", "slt" }, .{ "ult", "ult" }, .{ "sle", "sle" },
        .{ "ule", "ule" }, .{ "sgt", "sgt" }, .{ "ugt", "ugt" }, .{ "sge", "sge" }, .{ "uge", "uge" },
    };
    for (table) |row| if (std.mem.eql(u8, row[0], stem)) return row[1];
    unreachable;
}

fn floatPredicate(stem: []const u8) []const u8 {
    const table = [_][2][]const u8{
        .{ "eq", "oeq" }, .{ "ne", "une" }, .{ "lt", "olt" }, .{ "le", "ole" },
        .{ "gt", "ogt" }, .{ "ge", "oge" }, .{ "o", "ord" },  .{ "uo", "uno" },
    };
    for (table) |row| if (std.mem.eql(u8, row[0], stem)) return row[1];
    unreachable;
}

/// A widening's source width in bits.
pub fn extensionWidth(opcode: Opcode) u16 {
    return switch (opcode) {
        .extsw, .extuw => 32,
        .extsh, .extuh => 16,
        else => 8,
    };
}

/// A float conversion's source type letter, and the letter of its result.
pub fn conversionLetters(opcode: Opcode) struct { source: []const u8, result: []const u8 } {
    return switch (opcode) {
        .exts => .{ .source = "s", .result = "d" },
        .truncd => .{ .source = "d", .result = "s" },
        .stosi, .stoui => .{ .source = "s", .result = "w" },
        .dtosi, .dtoui => .{ .source = "d", .result = "w" },
        .swtof, .uwtof => .{ .source = "w", .result = "s" },
        .sltof, .ultof => .{ .source = "l", .result = "d" },
        else => .{ .source = "l", .result = "l" },
    };
}

/// A `%temporary` or `$global` operand, with the type its call site wrote.
pub const Ref = struct { name: []const u8, qbe_type: ?[]const u8 = null };
/// A literal operand: an integer, a float, or (`qbe_type` "extern") a symbol.
pub const Literal = struct { text: []const u8, qbe_type: ?[]const u8 = null };
/// A call's callee: a symbol, or a temporary holding a function address.
pub const Target = union(enum) { direct: []const u8, indirect: []const u8 };
/// A nested call used as an operand.
pub const CallOperand = struct { target: Target, args: []Operand, qbe_type: ?[]const u8 };
/// One operand of an instruction.
pub const Operand = union(enum) {
    temp: Ref,
    global: Ref,
    constant: Literal,
    call: *CallOperand,

    /// The name of a `%temporary`, or null for any other operand.
    pub fn tempName(self: Operand) ?[]const u8 {
        return switch (self) {
            .temp => |ref| ref.name,
            else => null,
        };
    }
    /// The name of a `%temporary` or `$global`, or null.
    pub fn refName(self: Operand) ?[]const u8 {
        return switch (self) {
            .temp, .global => |ref| ref.name,
            else => null,
        };
    }
};

/// One input of a phi: the predecessor label and the value it supplies.
pub const Phi = struct { label: []const u8, value: Operand };
/// Opcode-specific payload: branch labels, a call target, phi inputs or a position.
pub const Extra = union(enum) { none, label: []const u8, branch: [2][]const u8, target: Target, phi: []Phi, position: [2]u64 };

/// One parsed instruction.
pub const Instruction = struct {
    opcode: Opcode,
    qbe_type: ?[]const u8 = null,
    dest: ?[]const u8 = null,
    args: []Operand = &.{},
    extra: Extra = .none,
    line: usize = 0,
    text: []const u8 = "",

    /// The direct callee of a call, or null for any other instruction.
    pub fn directTarget(self: *const Instruction) ?[]const u8 {
        if (self.opcode != .call) return null;
        return switch (self.extra) {
            .target => |target| switch (target) {
                .direct => |name| name,
                .indirect => null,
            },
            else => null,
        };
    }
};

/// A basic block: a label and its instructions.
pub const Block = struct {
    label: []const u8,
    instructions: std.ArrayList(*Instruction) = .empty,

    /// The block's last instruction, whatever it is, or null when empty.
    pub fn terminator(self: *const Block) ?*Instruction {
        if (self.instructions.items.len == 0) return null;
        return self.instructions.items[self.instructions.items.len - 1];
    }
};

/// One declared parameter: its type letter or aggregate name, and its temporary.
pub const Parameter = struct { letter: []const u8, name: []const u8 };

/// What the frontend marked about addresses: `# myl-obj` temporaries,
/// `# myl-elem` storage words with their element kind, and `# myl-rc`
/// addresses of a counted prefix word (LLVM-RC-PREFIX-1).
pub const Hints = struct {
    objects: std.array_hash_map.String(void) = .empty,
    elements: std.StringHashMapUnmanaged([]const u8) = .empty,
    prefixes: std.array_hash_map.String(void) = .empty,
    /// Heap bookkeeping and journal words outside managed payload storage.
    rc_states: std.array_hash_map.String(void) = .empty,
    /// Preferred ordinary wrapped results; no alias or range authority.
    affine: std.array_hash_map.String(void) = .empty,
};

/// The unit's one function.
pub const Function = struct {
    name: []const u8,
    result: ?[]const u8,
    parameters: []Parameter,
    blocks: std.ArrayList(*Block) = .empty,
    exported: bool,
    hints: Hints = .{},
    line: usize,
};

/// A parsed unit: its aggregate definitions, its function and its `dbgfile`.
pub const Unit = struct {
    function: Function,
    sizes: std.StringHashMapUnmanaged(u64) = .empty,
    alignments: std.StringHashMapUnmanaged(u64) = .empty,
    debug_file: ?[]const u8 = null,
};

/// Whether a byte is a regular-expression word character (`\w`); bytes of a
/// multi-byte UTF-8 sequence count, as a Unicode letter would.
pub fn isWord(c: u8) bool {
    return std.ascii.isAlphanumeric(c) or c == '_' or c >= 0x80;
}
/// Whether a byte may appear in a QBE name (`[\w.$]`).
pub fn isNameChar(c: u8) bool {
    return isWord(c) or c == '.' or c == '$';
}
/// The bytes Python's `str.strip()`, `str.split()` and `\s` treat as whitespace.
pub const whitespace = " \t\n\r\x0b\x0c";
/// Whether a byte is whitespace as Python's `str.split()` and `\s` see it.
pub fn isSpace(c: u8) bool {
    return c == ' ' or (c >= 9 and c <= 13);
}
/// `text` without leading and trailing whitespace.
pub fn strip(text: []const u8) []const u8 {
    return std.mem.trim(u8, text, whitespace);
}
/// Whether `text` is an aggregate type name (`:name`).
pub fn isAggregateName(text: []const u8) bool {
    if (text.len < 2 or text[0] != ':') return false;
    for (text[1..]) |c| if (!isNameChar(c)) return false;
    return true;
}
/// Whether `text` is one of QBE's base type letters.
pub fn isBaseType(text: []const u8) bool {
    return text.len == 1 and std.mem.indexOfScalar(u8, "wlsd", text[0]) != null;
}
/// A base type letter's bit width.
pub fn baseBits(letter: []const u8) u16 {
    return if (letter[0] == 'w' or letter[0] == 's') 32 else 64;
}

/// Python's `int(text, 0)`, reduced modulo 2^64: a signed decimal without
/// leading zeros, or a `0x`/`0o`/`0b` literal, with single underscores
/// between digits. Null when Python would raise `ValueError`.
pub fn pythonInt(text: []const u8) ?u64 {
    var rest = strip(text);
    var negative = false;
    if (rest.len != 0 and (rest[0] == '-' or rest[0] == '+')) {
        negative = rest[0] == '-';
        rest = rest[1..];
    }
    var base: u8 = 10;
    if (rest.len >= 2 and rest[0] == '0' and std.ascii.isAlphabetic(rest[1])) {
        base = switch (std.ascii.toLower(rest[1])) {
            'x' => 16,
            'o' => 8,
            'b' => 2,
            else => return null,
        };
        rest = rest[2..];
        if (rest.len != 0 and rest[0] == '_') rest = rest[1..];
    } else if (rest.len > 1 and rest[0] == '0') {
        for (rest) |c| if (c != '0' and c != '_') return null;
    }
    const value = digitsValue(rest, base) orelse return null;
    return if (negative) 0 -% value else value;
}

fn digitsValue(digits: []const u8, base: u8) ?u64 {
    if (digits.len == 0 or digits[0] == '_' or digits[digits.len - 1] == '_') return null;
    var value: u64 = 0;
    var previous_underscore = false;
    for (digits) |c| {
        if (c == '_') {
            if (previous_underscore) return null;
            previous_underscore = true;
            continue;
        }
        previous_underscore = false;
        const digit = std.fmt.charToDigit(c, base) catch return null;
        value = value *% base +% digit;
    }
    return value;
}

/// Python's `float(text)`, or null when Python would raise `ValueError`.
pub fn pythonFloat(text: []const u8) ?f64 {
    const trimmed = strip(text);
    if (trimmed.len == 0) return null;
    for (trimmed) |c| if (c == 'x' or c == 'X' or c == 'p' or c == 'P') return null;
    return std.fmt.parseFloat(f64, trimmed) catch null;
}

/// Split a comma-separated operand list at the commas outside parentheses,
/// stripping each part. A trailing empty part is dropped, as the adapter did.
pub fn splitOperands(arena: std.mem.Allocator, text: []const u8) Error![]const []const u8 {
    var parts: std.ArrayList([]const u8) = .empty;
    var depth: i32 = 0;
    var start: usize = 0;
    for (text, 0..) |c, index| {
        if (c == '(') depth += 1;
        if (c == ')') depth -= 1;
        if (c == ',' and depth == 0) {
            try parts.append(arena, strip(text[start..index]));
            start = index + 1;
        }
    }
    const last = strip(text[start..]);
    if (last.len != 0) try parts.append(arena, last);
    return parts.items;
}

/// A line with any `# ...` comment outside string literals removed, stripped.
pub fn stripComment(line: []const u8) []const u8 {
    var in_string = false;
    for (line, 0..) |c, index| {
        if (c == '"') in_string = !in_string;
        if (c == '#' and !in_string) return strip(line[0..index]);
    }
    return strip(line);
}

/// The whitespace-separated words of `text`, as Python's `str.split()`.
pub fn words(arena: std.mem.Allocator, text: []const u8) Error![]const []const u8 {
    var out: std.ArrayList([]const u8) = .empty;
    var tokens = std.mem.tokenizeAny(u8, text, whitespace);
    while (tokens.next()) |token| try out.append(arena, token);
    return out.items;
}

/// `text.split(None, 1)`: the first word and the rest from the next word on.
fn splitFirst(text: []const u8) struct { first: []const u8, rest: []const u8 } {
    const trimmed = std.mem.trimStart(u8, text, whitespace);
    var end: usize = 0;
    while (end < trimmed.len and !isSpace(trimmed[end])) end += 1;
    const rest = std.mem.trimStart(u8, trimmed[end..], whitespace);
    return .{ .first = trimmed[0..end], .rest = rest };
}

/// The byte size of an emitted aggregate definition, or null when it is not one.
fn aggregateSize(definition: []const u8) ?u64 {
    var rest = definition;
    if (std.mem.startsWith(u8, rest, "align")) {
        const after = afterAlign(rest) orelse return null;
        rest = after.rest;
    }
    if (bytesRecord(rest)) |size| return size;
    if (definition.len == rest.len and pairRecord(rest)) return 16;
    return null;
}

/// `align\s+\d+\s+` at the start: the alignment and what follows.
fn afterAlign(text: []const u8) ?struct { alignment: u64, rest: []const u8 } {
    var at: usize = "align".len;
    const spaces = at;
    while (at < text.len and isSpace(text[at])) at += 1;
    if (at == spaces) return null;
    const digits = at;
    while (at < text.len and std.ascii.isDigit(text[at])) at += 1;
    if (at == digits) return null;
    const value = std.fmt.parseUnsigned(u64, text[digits..at], 10) catch return null;
    const gap = at;
    while (at < text.len and isSpace(text[at])) at += 1;
    if (at == gap) return null;
    return .{ .alignment = value, .rest = text[at..] };
}

/// `{ b N }` with any spacing: N.
fn bytesRecord(text: []const u8) ?u64 {
    if (text.len < 2 or text[0] != '{' or text[text.len - 1] != '}') return null;
    const inner = strip(text[1 .. text.len - 1]);
    if (inner.len < 3 or inner[0] != 'b' or !isSpace(inner[1])) return null;
    const count = strip(inner[1..]);
    for (count) |c| if (!std.ascii.isDigit(c)) return null;
    return std.fmt.parseUnsigned(u64, count, 10) catch null;
}

/// `{ l, l }` with any spacing.
fn pairRecord(text: []const u8) bool {
    if (text.len < 2 or text[0] != '{' or text[text.len - 1] != '}') return false;
    const inner = text[1 .. text.len - 1];
    const comma = std.mem.indexOfScalar(u8, inner, ',') orelse return false;
    return std.mem.eql(u8, strip(inner[0..comma]), "l") and std.mem.eql(u8, strip(inner[comma + 1 ..]), "l");
}

/// The declared alignment of an aggregate definition (QBE's default otherwise).
fn aggregateAlignment(definition: []const u8) u64 {
    if (std.mem.startsWith(u8, definition, "align")) {
        if (afterAlign(definition)) |found| return found.alignment;
    }
    if (pairRecord(definition)) return 8;
    return 1;
}

/// Whether `line` starts with the directive `word` followed by whitespace.
fn directive(line: []const u8, word: []const u8) bool {
    return line.len > word.len and std.mem.startsWith(u8, line, word) and isSpace(line[word.len]);
}

/// A `type :name = definition` line: the name and the definition, or null.
fn typeLine(line: []const u8) ?struct { name: []const u8, definition: []const u8 } {
    if (!directive(line, "type")) return null;
    const rest = std.mem.trimStart(u8, line[4..], whitespace);
    if (rest.len == 0 or rest[0] != ':') return null;
    var end: usize = 0;
    while (end < rest.len and !isSpace(rest[end])) end += 1;
    var name = rest[0..end];
    var after = rest[end..];
    if (std.mem.lastIndexOfScalar(u8, name, '=')) |equals| {
        after = rest[equals..];
        name = rest[0..equals];
        if (name.len < 2) return null;
    }
    after = std.mem.trimStart(u8, after, whitespace);
    if (after.len == 0 or after[0] != '=') return null;
    const definition = strip(after[1..]);
    if (definition.len == 0) return null;
    return .{ .name = name, .definition = definition };
}

/// Whether a line is removed as a type definition (`^type\s+:\S+\s*=.*$`).
fn removedTypeLine(line: []const u8) bool {
    if (!directive(line, "type")) return false;
    const rest = std.mem.trimStart(u8, line[4..], whitespace);
    return rest.len > 1 and rest[0] == ':' and std.mem.indexOfScalar(u8, rest, '=') != null;
}

/// The quoted operand of a `dbgfile "NAME"` directive, quotes included, or null.
fn debugFileOperand(line: []const u8) ?[]const u8 {
    if (!directive(line, "dbgfile")) return null;
    const rest = strip(line[7..]);
    if (rest.len < 2 or rest[0] != '"') return null;
    return if (rest[rest.len - 1] == '"') rest else null;
}

/// A `dbgfile "NAME"` line's name, or null.
fn debugFileLine(line: []const u8) ?[]const u8 {
    const quoted = debugFileOperand(line) orelse return null;
    const name = quoted[1 .. quoted.len - 1];
    if (std.mem.indexOfScalar(u8, name, '"') != null) return null;
    return name;
}

/// Whether a line is removed as a `dbgfile` directive (`^dbgfile\s+".*"\s*$`).
fn removedDebugFileLine(line: []const u8) bool {
    return debugFileOperand(line) != null;
}

/// Parse one emitted QBE unit.
pub fn parse(arena: std.mem.Allocator, text: []const u8, diagnostic: *Diagnostic) Error!*Unit {
    const unit = try arena.create(Unit);
    unit.* = .{ .function = undefined };
    var reader = try prepare(arena, text, unit, diagnostic);
    unit.function = try reader.header();
    try reader.blocks(&unit.function);
    if (unit.function.blocks.items.len == 0) return diagnostic.fail(arena, unit.function.line, "function contains no blocks");
    return unit;
}

/// Parse only a unit's function header: its name, parameters and result.
pub fn parseHeader(arena: std.mem.Allocator, text: []const u8, diagnostic: *Diagnostic) Error!Function {
    var reader = try prepare(arena, text, null, diagnostic);
    return reader.header();
}

/// The unit's lines with its type definitions and `dbgfile` directive
/// blanked (recording them into `unit` when given), positioned at the
/// function header.
fn prepare(arena: std.mem.Allocator, text: []const u8, unit: ?*Unit, diagnostic: *Diagnostic) Error!Reader {
    var lines: std.ArrayList([]const u8) = .empty;
    var split = std.mem.splitScalar(u8, text, '\n');
    while (split.next()) |line| {
        if (unit) |into| if (typeLine(line)) |found| {
            const size = aggregateSize(found.definition) orelse
                return diagnostic.fail(arena, 0, try std.fmt.allocPrint(arena, "unsupported aggregate definition `{s} = {s}`", .{ found.name, found.definition }));
            try into.sizes.put(arena, found.name, size);
            try into.alignments.put(arena, found.name, aggregateAlignment(found.definition));
        };
        if (removedTypeLine(line)) {
            try lines.append(arena, "");
            continue;
        }
        if (unit) |into| if (debugFileLine(line)) |name| {
            into.debug_file = name;
        };
        if (removedDebugFileLine(line)) {
            try lines.append(arena, "");
            continue;
        }
        try lines.append(arena, line);
    }
    var index: usize = 0;
    while (index < lines.items.len and strip(lines.items[index]).len == 0) index += 1;
    if (index >= lines.items.len) return diagnostic.fail(arena, 0, "unit contains no function");
    return .{ .arena = arena, .lines = lines.items, .index = index, .diagnostic = diagnostic };
}

/// Marker line the frontend writes before an address it knows names memory
/// outside the running function's frame (`# myl-obj %temp`).
const object_marker = "# myl-obj ";
/// Marker line for a managed container's storage word (`# myl-elem %temp KIND`).
const element_marker = "# myl-elem ";
/// Marker line for the address of one word of the RC prefix below a managed
/// payload: its owner or hold count or its common-header mark (`# myl-rc %temp`).
const prefix_marker = "# myl-rc ";
/// RC-SCOPE-IL-1: addresses in runtime bookkeeping, apart from guest values.
const rc_state_marker = "# myl-rc-state ";
/// A counted-loop arithmetic result, a performance-only lowering preference.
const affine_marker = "# myl-affine ";

/// A cursor over one unit's lines.
const Reader = struct {
    arena: std.mem.Allocator,
    lines: []const []const u8,
    index: usize,
    diagnostic: *Diagnostic,

    fn header(self: *Reader) Error!Function {
        const line_number = self.index + 1;
        const text = strip(self.lines[self.index]);
        var rest = text;
        var exported = false;
        if (std.mem.startsWith(u8, rest, "export ")) {
            exported = true;
            rest = rest["export ".len..];
        }
        if (!std.mem.startsWith(u8, rest, "function ")) return self.diagnostic.fail(self.arena, line_number, "expected a function header");
        const signature = parseSignature(rest["function ".len..]) orelse return self.diagnostic.fail(self.arena, line_number, "cannot parse the function signature");
        var parameters: std.ArrayList(Parameter) = .empty;
        if (strip(signature.parameters).len != 0) {
            for (try splitOperands(self.arena, signature.parameters)) |item| {
                const parts = try words(self.arena, item);
                if (parts.len != 2 or parts[1][0] != '%') return self.diagnostic.fail(self.arena, line_number, "cannot parse a parameter");
                try parameters.append(self.arena, .{ .letter = parts[0], .name = parts[1][1..] });
            }
        }
        self.index += 1;
        if (std.mem.indexOfScalar(u8, text, '{') == null) {
            while (self.index < self.lines.len and std.mem.indexOfScalar(u8, self.lines[self.index], '{') == null) self.index += 1;
            self.index += 1;
        }
        return .{ .name = signature.name, .result = signature.result, .parameters = parameters.items, .exported = exported, .line = line_number };
    }

    fn blocks(self: *Reader, function: *Function) Error!void {
        var current: ?*Block = null;
        while (self.index < self.lines.len) {
            const raw = self.lines[self.index];
            self.index += 1;
            const stripped = strip(raw);
            if (std.mem.startsWith(u8, stripped, object_marker)) {
                const marked = strip(stripped[object_marker.len..]);
                if (marked.len != 0 and marked[0] == '%') try function.hints.objects.put(self.arena, marked[1..], {});
                continue;
            }
            if (std.mem.startsWith(u8, stripped, element_marker)) {
                try self.elementMarker(function, stripped[element_marker.len..]);
                continue;
            }
            if (std.mem.startsWith(u8, stripped, prefix_marker)) {
                const marked = strip(stripped[prefix_marker.len..]);
                if (marked.len != 0 and marked[0] == '%') try function.hints.prefixes.put(self.arena, marked[1..], {});
                continue;
            }
            if (std.mem.startsWith(u8, stripped, rc_state_marker)) {
                const marked = strip(stripped[rc_state_marker.len..]);
                if (marked.len != 0 and marked[0] == '%') try function.hints.rc_states.put(self.arena, marked[1..], {});
                continue;
            }
            if (std.mem.startsWith(u8, stripped, affine_marker)) {
                const marked = strip(stripped[affine_marker.len..]);
                if (marked.len != 0 and marked[0] == '%') try function.hints.affine.put(self.arena, marked[1..], {});
                continue;
            }
            const line = stripComment(raw);
            if (line.len == 0) continue;
            if (std.mem.eql(u8, line, "}")) break;
            if (line[0] == '@') {
                if (std.mem.indexOfScalar(u8, line, ' ') != null) return self.diagnostic.fail(self.arena, self.index, "unexpected text after a label");
                const block = try self.arena.create(Block);
                block.* = .{ .label = line };
                try function.blocks.append(self.arena, block);
                current = block;
                continue;
            }
            const block = current orelse return self.diagnostic.fail(self.arena, self.index, "instruction outside any block");
            try block.instructions.append(self.arena, try parseInstruction(self.arena, line, .{ .number = self.index, .raw = raw, .diagnostic = self.diagnostic }));
        }
    }

    fn elementMarker(self: *Reader, function: *Function, text: []const u8) Error!void {
        const parts = try words(self.arena, text);
        if (parts.len == 0 or parts[0][0] != '%') return;
        try function.hints.objects.put(self.arena, parts[0][1..], {});
        if (parts.len == 2 and elementKind(parts[1])) try function.hints.elements.put(self.arena, parts[0][1..], parts[1]);
    }
};

/// `\d+[rv]`: an element kind such as `8r` or `1v`.
fn elementKind(text: []const u8) bool {
    if (text.len < 2) return false;
    const last = text[text.len - 1];
    if (last != 'r' and last != 'v') return false;
    for (text[0 .. text.len - 1]) |c| if (!std.ascii.isDigit(c)) return false;
    return true;
}

/// A function signature after `function `: result, name and parameter text.
const Signature = struct { result: ?[]const u8, name: []const u8, parameters: []const u8 };

fn parseSignature(text: []const u8) ?Signature {
    var at: usize = 0;
    while (at < text.len and isSpace(text[at])) at += 1;
    var result: ?[]const u8 = null;
    if (at < text.len and text[at] != '$') {
        const start = at;
        if (text[at] == ':') {
            at += 1;
            while (at < text.len and isNameChar(text[at])) at += 1;
            if (at == start + 1) return null;
        } else if (std.mem.indexOfScalar(u8, "lwsbd", text[at]) != null) {
            at += 1;
        } else return null;
        result = text[start..at];
        const gap = at;
        while (at < text.len and isSpace(text[at])) at += 1;
        if (at == gap) return null;
    }
    if (at >= text.len or text[at] != '$') return null;
    at += 1;
    const name_start = at;
    while (at < text.len and isNameChar(text[at])) at += 1;
    if (at == name_start) return null;
    const name = text[name_start..at];
    while (at < text.len and isSpace(text[at])) at += 1;
    if (at >= text.len or text[at] != '(') return null;
    at += 1;
    var close = at;
    while (std.mem.indexOfScalarPos(u8, text, close, ')')) |found| : (close = found + 1) {
        if (signatureEnd(text[found + 1 ..])) return .{ .result = result, .name = name, .parameters = text[at..found] };
    }
    return null;
}

/// `\s*\{?\s*$`.
fn signatureEnd(text: []const u8) bool {
    var rest = std.mem.trimStart(u8, text, whitespace);
    if (rest.len != 0 and rest[0] == '{') rest = rest[1..];
    return strip(rest).len == 0;
}

/// Where an instruction came from, for its diagnostics.
const Place = struct { number: usize, raw: []const u8, diagnostic: *Diagnostic };

/// Parse one instruction line (a comment already removed).
pub fn parseInstruction(arena: std.mem.Allocator, line: []const u8, place: anytype) Error!*Instruction {
    var dest: ?[]const u8 = null;
    var qbe_type: ?[]const u8 = null;
    var tail = line;
    if (assignment(line)) |found| {
        dest = found.dest;
        qbe_type = found.qbe_type;
        tail = strip(found.rest);
    }
    const tokens = splitFirst(tail);
    const instruction = try arena.create(Instruction);
    instruction.* = .{ .opcode = .copy, .qbe_type = qbe_type, .dest = dest, .line = place.number, .text = place.raw };
    var builder: Builder = .{ .arena = arena, .instruction = instruction, .diagnostic = place.diagnostic };
    try builder.build(tokens.first, tokens.rest);
    return instruction;
}

/// `%dest =[type] rest`: the destination, its optional type and the rest.
fn assignment(line: []const u8) ?struct { dest: []const u8, qbe_type: ?[]const u8, rest: []const u8 } {
    if (line.len == 0 or line[0] != '%') return null;
    var at: usize = 1;
    while (at < line.len and isNameChar(line[at])) at += 1;
    if (at == 1) return null;
    const dest = line[1..at];
    while (at < line.len and isSpace(line[at])) at += 1;
    if (at >= line.len or line[at] != '=') return null;
    at += 1;
    while (at < line.len and isSpace(line[at])) at += 1;
    const after = line[at..];
    if (typedRest(after)) |typed| return .{ .dest = dest, .qbe_type = typed.qbe_type, .rest = typed.rest };
    return .{ .dest = dest, .qbe_type = null, .rest = after };
}

/// `(?:([lwsbd]|:[\w.$]+)\s+)` at the start of `text`, when it matches.
fn typedRest(text: []const u8) ?struct { qbe_type: []const u8, rest: []const u8 } {
    if (text.len == 0) return null;
    var end: usize = 0;
    if (text[0] == ':') {
        end = 1;
        while (end < text.len and isNameChar(text[end])) end += 1;
        if (end == 1) return null;
    } else if (std.mem.indexOfScalar(u8, "lwsbd", text[0]) != null) {
        end = 1;
    } else return null;
    var at = end;
    while (at < text.len and isSpace(text[at])) at += 1;
    if (at == end) return null;
    return .{ .qbe_type = text[0..end], .rest = text[at..] };
}

/// Fills one instruction from its opcode and operand text.
const Builder = struct {
    arena: std.mem.Allocator,
    instruction: *Instruction,
    diagnostic: *Diagnostic,

    fn fail(self: *Builder, message: []const u8) Error {
        return self.diagnostic.fail(self.arena, self.instruction.line, try std.fmt.allocPrint(self.arena, "{s}\n    {s}", .{ message, self.instruction.text }));
    }

    fn one(self: *Builder, text: []const u8, expected: ?[]const u8) Error!Operand {
        return parseOperand(self.arena, text, expected, self.diagnostic);
    }

    fn many(self: *Builder, parts: []const []const u8, expected: []const ?[]const u8) Error![]Operand {
        const out = try self.arena.alloc(Operand, parts.len);
        for (parts, out, 0..) |part, *slot, index| slot.* = try self.one(part, if (index < expected.len) expected[index] else null);
        return out;
    }

    fn build(self: *Builder, name: []const u8, operands: []const u8) Error!void {
        const opcode = std.meta.stringToEnum(Opcode, name) orelse {
            if (std.mem.eql(u8, name, "vastart") or std.mem.eql(u8, name, "vaarg")) return self.fail("unsupported opcode");
            return self.fail("unknown opcode");
        };
        const ins = self.instruction;
        ins.opcode = opcode;
        switch (opcode) {
            .ret => if (strip(operands).len != 0) {
                ins.args = try self.many(&.{operands}, &.{});
            },
            .jmp => {
                const target = strip(operands);
                if (target.len == 0 or target[0] != '@') return self.fail("jmp target is not a label");
                ins.extra = .{ .label = target };
            },
            .jnz => {
                const parts = try splitOperands(self.arena, operands);
                if (parts.len != 3) return self.fail("jnz expects a value and two labels");
                ins.args = try self.many(parts[0..1], &.{});
                ins.extra = .{ .branch = .{ strip(parts[1]), strip(parts[2]) } };
            },
            .call => try self.call(operands),
            .phi => try self.phi(operands),
            .alloc4, .alloc8, .alloc16 => ins.args = try self.many(&.{operands}, &.{"l"}),
            .blit => {
                const parts = try splitOperands(self.arena, operands);
                if (parts.len != 3) return self.fail("blit expects source, destination and size");
                ins.args = try self.many(parts, &.{ "l", "l", "l" });
            },
            .dbgloc => try self.position(operands),
            .hlt => if (strip(operands).len != 0 or ins.dest != null) return self.fail("hlt takes no operands and defines nothing"),
            .copy, .neg, .not => ins.args = try self.many(&.{operands}, &.{}),
            else => try self.plain(opcode, operands),
        }
    }

    fn plain(self: *Builder, opcode: Opcode, operands: []const u8) Error!void {
        const ins = self.instruction;
        if (opcode.isStore()) {
            const parts = try splitOperands(self.arena, operands);
            if (parts.len != 2) return self.fail("a store expects a value and an address");
            ins.args = try self.many(parts, &.{ null, "l" });
        } else if (opcode.isLoad()) {
            ins.args = try self.many(&.{operands}, &.{"l"});
        } else {
            ins.args = try self.many(try splitOperands(self.arena, operands), &.{});
        }
    }

    fn call(self: *Builder, operands: []const u8) Error!void {
        const found = callShape(operands, false) orelse return self.fail("cannot parse a call");
        self.instruction.extra = .{ .target = callTarget(found.target) };
        self.instruction.args = try callArguments(self.arena, found.arguments, self.diagnostic);
    }

    fn phi(self: *Builder, operands: []const u8) Error!void {
        const parts = try splitOperands(self.arena, operands);
        const inputs = try self.arena.alloc(Phi, parts.len);
        for (parts, inputs) |part, *input| {
            const pieces = try words(self.arena, part);
            if (pieces.len != 2) return self.fail("cannot parse a phi input");
            input.* = .{ .label = pieces[0], .value = try self.one(pieces[1], null) };
        }
        self.instruction.extra = .{ .phi = inputs };
    }

    fn position(self: *Builder, operands: []const u8) Error!void {
        const malformed = "dbgloc takes a line and an optional column";
        const parts = try splitOperands(self.arena, operands);
        if (self.instruction.dest != null or parts.len < 1 or parts.len > 2) return self.fail(malformed);
        var values: [2]u64 = .{ 0, 0 };
        for (parts, 0..) |part, index| {
            const trimmed = strip(part);
            if (trimmed.len == 0) return self.fail(malformed);
            for (trimmed) |c| if (!std.ascii.isDigit(c)) return self.fail(malformed);
            values[index] = std.fmt.parseUnsigned(u64, trimmed, 10) catch return self.fail("dbgloc position out of range");
        }
        self.instruction.extra = .{ .position = values };
    }
};

/// `TARGET(ARGS)` of a call: the target token and the argument text.
fn callShape(text: []const u8, nested: bool) ?struct { target: []const u8, arguments: []const u8 } {
    var at: usize = 0;
    if (at < text.len and (text[at] == '%' or text[at] == '$')) at += 1;
    const name_start = at;
    while (at < text.len and isNameChar(text[at])) at += 1;
    if (at == name_start) return null;
    const target = text[0..at];
    while (at < text.len and isSpace(text[at])) at += 1;
    if (at >= text.len or text[at] != '(') return null;
    const close = std.mem.lastIndexOfScalar(u8, text, ')') orelse return null;
    if (close < at) return null;
    const tail = text[close + 1 ..];
    if (nested and tail.len != 0) return null;
    if (strip(tail).len != 0) return null;
    return .{ .target = target, .arguments = text[at + 1 .. close] };
}

/// A call's callee from its token: `%temp` computes it, `$f` names it.
fn callTarget(token: []const u8) Target {
    if (token[0] == '%') return .{ .indirect = token[1..] };
    return .{ .direct = std.mem.trimStart(u8, token, "$") };
}

fn callArguments(arena: std.mem.Allocator, text: []const u8, diagnostic: *Diagnostic) Error![]Operand {
    if (strip(text).len == 0) return &.{};
    const parts = try splitOperands(arena, text);
    const out = try arena.alloc(Operand, parts.len);
    for (parts, out) |part, *slot| slot.* = try parseOperand(arena, part, innerParameterType(part), diagnostic);
    return out;
}

/// The declared type of one call argument (`l %v` → `l`), when it has one.
fn innerParameterType(text: []const u8) ?[]const u8 {
    const first = splitFirst(text).first;
    if (first.len != 0 and (isBaseType(first) or isAggregateName(first))) return first;
    return null;
}

/// Parse one operand: a temporary, a global, an `extern` symbol, a typed
/// operand, a nested call, or a literal.
pub fn parseOperand(arena: std.mem.Allocator, raw: []const u8, qbe_type: ?[]const u8, diagnostic: *Diagnostic) Error!Operand {
    const text = strip(raw);
    if (text.len == 0) return diagnostic.fail(arena, 0, "empty operand");
    if (text[0] == '%') return .{ .temp = .{ .name = text[1..], .qbe_type = qbe_type } };
    if (text[0] == '$') return .{ .global = .{ .name = text[1..], .qbe_type = qbe_type } };
    if (std.mem.startsWith(u8, text, "extern ")) return .{ .constant = .{ .text = std.mem.trimStart(u8, text["extern ".len..], "$"), .qbe_type = "extern" } };
    const parts = splitFirst(text);
    if (parts.rest.len != 0 and (isBaseType(parts.first) or isAggregateName(parts.first))) return parseOperand(arena, parts.rest, parts.first, diagnostic);
    if (std.mem.startsWith(u8, text, "call ")) {
        const inner = strip(text["call ".len..]);
        const found = callShape(inner, true) orelse return diagnostic.fail(arena, 0, "cannot parse a nested call");
        const call = try arena.create(CallOperand);
        call.* = .{ .target = callTarget(found.target), .args = try callArguments(arena, found.arguments, diagnostic), .qbe_type = qbe_type };
        return .{ .call = call };
    }
    return .{ .constant = .{ .text = text, .qbe_type = qbe_type } };
}

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

/// What kind of value a temporary holds.
pub const Kind = enum { int, float, aggregate };
/// A temporary's type: an integer or float width, or an aggregate name.
pub const Type = struct {
    kind: Kind,
    bits: u16 = 64,
    aggregate: []const u8 = "",

    /// Whether two types are the same kind and width (or aggregate).
    pub fn eql(self: Type, other: Type) bool {
        if (self.kind != other.kind) return false;
        if (self.kind == .aggregate) return std.mem.eql(u8, self.aggregate, other.aggregate);
        return self.bits == other.bits;
    }
    /// The LLVM type a slot of this type holds.
    pub fn llvm(self: Type) []const u8 {
        return switch (self.kind) {
            .aggregate => "i64",
            .float => if (self.bits == 64) "double" else "float",
            .int => intName(self.bits),
        };
    }
    /// The QBE letter of an integer or float type (an aggregate answers its name).
    pub fn letter(self: Type) []const u8 {
        return switch (self.kind) {
            .aggregate => self.aggregate,
            .float => if (self.bits == 32) "s" else "d",
            .int => if (self.bits == 32) "w" else "l",
        };
    }
};

/// The spelling of an LLVM integer type of `bits` bits.
pub fn intName(bits: u16) []const u8 {
    return switch (bits) {
        1 => "i1",
        8 => "i8",
        16 => "i16",
        32 => "i32",
        else => "i64",
    };
}

/// The type of every temporary a unit defines.
pub const Types = struct {
    map: std.StringHashMapUnmanaged(Type) = .empty,

    /// The recorded type of one temporary, or null.
    pub fn get(self: *const Types, name: []const u8) ?Type {
        return self.map.get(name);
    }

    fn record(self: *Types, context: Inference, name: []const u8, value: Type) Error!bool {
        if (self.map.get(name)) |existing| {
            if (existing.eql(value)) return false;
            return context.diagnostic.fail(context.arena, context.line, try std.fmt.allocPrint(context.arena, "temporary %{s} has conflicting types", .{name}));
        }
        try self.map.put(context.arena, name, value);
        return true;
    }

    fn recordLetter(self: *Types, context: Inference, name: []const u8, letter: []const u8) Error!bool {
        if (isAggregateName(letter)) {
            if (!context.sizes.contains(letter)) return context.diagnostic.fail(context.arena, context.line, "undefined aggregate type");
            return self.record(context, name, .{ .kind = .aggregate, .aggregate = letter });
        }
        if (!isBaseType(letter)) return context.diagnostic.fail(context.arena, context.line, "unsupported value type");
        const kind: Kind = if (letter[0] == 's' or letter[0] == 'd') .float else .int;
        return self.record(context, name, .{ .kind = kind, .bits = baseBits(letter) });
    }
};

/// What type inference needs besides the map it fills.
const Inference = struct { arena: std.mem.Allocator, sizes: *const std.StringHashMapUnmanaged(u64), diagnostic: *Diagnostic, line: usize };

/// Resolve the type of every temporary the unit defines: parameters, then up
/// to four passes over the definitions, which also follow `copy` and `cast`.
pub fn inferTypes(arena: std.mem.Allocator, unit: *const Unit, diagnostic: *Diagnostic) Error!Types {
    var types: Types = .{};
    const function = &unit.function;
    var context: Inference = .{ .arena = arena, .sizes = &unit.sizes, .diagnostic = diagnostic, .line = function.line };
    for (function.parameters) |parameter| _ = try types.recordLetter(context, parameter.name, parameter.letter);
    for (0..4) |_| {
        var changed = false;
        for (function.blocks.items) |block| for (block.instructions.items) |instruction| {
            context.line = instruction.line;
            changed = (try recordDefinition(&types, context, instruction)) or changed;
        };
        if (!changed) break;
    }
    return types;
}

fn recordDefinition(types: *Types, context: Inference, instruction: *const Instruction) Error!bool {
    const dest = instruction.dest orelse return false;
    if (types.map.contains(dest)) return false;
    const opcode = instruction.opcode;
    if (instruction.qbe_type) |letter| return types.recordLetter(context, dest, letter);
    if (opcode.isExtension()) return types.record(context, dest, .{ .kind = .int, .bits = 64 });
    if (opcode == .cast or opcode == .copy) {
        const source = instruction.args[0].refName() orelse return false;
        const known = types.get(source) orelse return false;
        return types.record(context, dest, known);
    }
    if (opcode.isConversion()) return types.recordLetter(context, dest, conversionLetters(opcode).result);
    if (opcode.isComparison()) {
        const shape = comparison(opcode);
        if (shape.float) return types.record(context, dest, .{ .kind = .float, .bits = if (std.mem.eql(u8, shape.operand, "double")) 64 else 32 });
        return types.record(context, dest, .{ .kind = .int, .bits = if (std.mem.eql(u8, shape.operand, "i64")) 64 else 32 });
    }
    if (opcode.arithmetic() or opcode == .neg or opcode == .not) {
        const bits = operandWidth(types, instruction.args[0]) orelse return false;
        return types.record(context, dest, .{ .kind = .int, .bits = bits });
    }
    return false;
}

/// The integer width of an operand, or null when it is not known yet.
fn operandWidth(types: *const Types, argument: Operand) ?u16 {
    return switch (argument) {
        .global => 64,
        .temp => |ref| if (types.get(ref.name)) |known| (if (known.kind == .int) known.bits else null) else null,
        .constant => |literal| if (literal.qbe_type) |letter| (if (isBaseType(letter)) baseBits(letter) else 64) else 64,
        .call => null,
    };
}
