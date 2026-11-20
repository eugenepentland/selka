//! Conservative C ABI surface identity for the embedded, single runtime unit.
//! Keep declarations, aggregate layouts, initializers and every preprocessor
//! directive. Omit only balanced top-level function bodies following `)`;
//! comments, literals and directives are lexed before interpreting braces.
//! Unsupported/unbalanced input falls back to complete-source identity.
const std = @import("std");
const fast_blake3 = @import("fast_blake3.zig");

/// The number of distinct macro names `source` defines, as the surface scanner counts them; past the scanner's
/// table (`macro_capacity`) the surface falls back to the whole text, so every body edit would change the ABI.
pub fn macroNames(source: []const u8) usize {
    var scanner: Scanner = .{ .source = source, .hash = fast_blake3.Blake3.init(.{}) };
    scanner.run();
    return scanner.macros.count;
}

/// How many distinct macro names the surface scanner tracks before it binds the whole source.
pub const macro_capacity = @typeInfo(@FieldType(Macros, "names")).array.len;

/// Hash C declarations/layout independently of implementation-only function edits.
pub fn digest(source: []const u8) [32]u8 {
    var scanner: Scanner = .{ .source = source, .hash = fast_blake3.Blake3.init(.{}) };
    scanner.hash.update("core-runtime-c-surface-v1\x00");
    // Alternate C tokens can introduce directives or braces before lexing.
    // This runtime uses ordinary spellings; unsupported forms bind all bytes.
    for ([_][]const u8{ "??", "%:", "<:", ":>", "<%", "%>" }) |alternate| {
        if (std.mem.indexOf(u8, source, alternate) != null) {
            scanner.hash.update(source);
            break;
        }
    }
    scanner.run();
    if (scanner.shape.depth != 0 or scanner.shape.body != 0 or scanner.shape.parens != 0) scanner.hash.update(source);
    var result: [32]u8 = undefined;
    scanner.hash.final(&result);
    return result;
}

const Shape = struct {
    depth: usize = 0,
    body: usize = 0,
    parens: usize = 0,
    prefix: Prefix = .{},
    initializer: bool = false,
    aggregate: bool = false,
    typedef: bool = false,

    fn startsBody(self: Shape, token: []const u8) bool {
        if (self.depth != 0 or self.initializer or self.aggregate or self.typedef) return false;
        return std.mem.eql(u8, token, "{") and std.mem.eql(u8, self.prefix.previous, ")");
    }
};

const Prefix = struct { previous: []const u8 = "", words: usize = 0, macro_call: bool = false };

const Macros = struct {
    names: [512][]const u8 = undefined,
    count: usize = 0,

    fn contains(self: *const Macros, name: []const u8) bool {
        for (self.names[0..self.count]) |known| if (std.mem.eql(u8, known, name)) return true;
        return false;
    }

    fn observe(self: *Macros, directive: []const u8) bool {
        var header: Scanner = .{ .source = directive[1..], .hash = fast_blake3.Blake3.init(.{}) };
        if (!std.mem.eql(u8, header.next() orelse return true, "define")) return true;
        const name = header.next() orelse return false;
        if (!std.ascii.isAlphabetic(name[0]) and name[0] != '_') return false;
        if (header.at < header.source.len and header.source[header.at] == '\\') return false;
        if (self.contains(name)) return true;
        if (self.count == self.names.len) return false;
        self.names[self.count] = name;
        self.count += 1;
        return true;
    }
};

const Scanner = struct {
    source: []const u8,
    at: usize = 0,
    shape: Shape = .{},
    hash: fast_blake3.Blake3,
    macros: Macros = .{},

    fn run(self: *Scanner) void {
        const shape = &self.shape;
        while (self.next()) |token| {
            if (token[0] == '#') {
                if (!self.macros.observe(token)) self.hash.update(self.source);
                self.field(token);
                continue;
            }
            if (shape.body != 0) {
                if (std.mem.eql(u8, token, "{")) shape.body += 1;
                if (std.mem.eql(u8, token, "}")) {
                    shape.body -= 1;
                    if (shape.body == 0) shape.prefix = .{};
                }
                continue;
            }
            if (shape.startsBody(token)) {
                // A bare NAME(...) may expand to an aggregate declaration.
                if (shape.prefix.words < 2 or shape.prefix.macro_call) self.hash.update(self.source);
                self.field("{function-body}");
                shape.body = 1;
                shape.prefix.previous = "";
                continue;
            }
            // A complete macro invocation may itself expand to declarations or
            // functions. If no explicit body follows it, start a fresh prefix.
            if (shape.parens == 0 and shape.depth == 0 and shape.prefix.macro_call and std.mem.eql(u8, shape.prefix.previous, ")")) shape.prefix = .{};
            self.declaration(token);
            if (std.mem.eql(u8, token, "{")) shape.depth += 1;
            if (std.mem.eql(u8, token, "}")) {
                if (shape.depth == 0) {
                    self.hash.update(self.source);
                    return;
                }
                shape.depth -= 1;
            }
            self.field(token);
            shape.prefix.previous = token;
        }
    }

    fn declaration(self: *Scanner, token: []const u8) void {
        const shape = &self.shape;
        if (shape.depth != 0) return;
        if (shape.parens == 0) {
            if (std.ascii.isAlphabetic(token[0]) or token[0] == '_') shape.prefix.words += 1;
            if (std.mem.eql(u8, token, "struct") or std.mem.eql(u8, token, "union") or std.mem.eql(u8, token, "enum")) shape.aggregate = true;
            if (std.mem.eql(u8, token, "typedef")) shape.typedef = true;
            if (std.mem.eql(u8, token, "=")) shape.initializer = true;
            if (std.mem.eql(u8, token, ";")) {
                shape.initializer = false;
                shape.aggregate = false;
                shape.typedef = false;
                shape.prefix = .{};
            }
        }
        if (std.mem.eql(u8, token, "(")) {
            // An opaque macro between an aggregate keyword and its body can
            // hide layout. Prefer complete-source identity to guessing whether
            // it denotes a function returning a struct or an ABI annotation.
            if (shape.parens == 0 and shape.aggregate and !std.mem.eql(u8, shape.prefix.previous, "__attribute__")) self.hash.update(self.source);
            if (shape.parens == 0 and self.macros.contains(shape.prefix.previous)) shape.prefix.macro_call = true;
            shape.parens += 1;
        }
        if (std.mem.eql(u8, token, ")")) {
            if (shape.parens == 0) self.hash.update(self.source) else shape.parens -= 1;
        }
    }

    fn field(self: *Scanner, token: []const u8) void {
        var length: [8]u8 = undefined;
        std.mem.writeInt(u64, &length, token.len, .little);
        self.hash.update(&length);
        self.hash.update(token);
    }

    fn next(self: *Scanner) ?[]const u8 {
        self.trivia();
        if (self.at == self.source.len) return null;
        const start = self.at;
        const first = self.source[self.at];
        self.at += 1;
        if (first == '\\') self.hash.update(self.source);
        if (first == '"' or first == '\'') {
            self.literal(first);
        } else if (first == '#') {
            while (self.at < self.source.len) : (self.at += 1) {
                if (self.source[self.at] == '\n' and self.source[self.at - 1] != '\\') break;
            }
        } else if (std.ascii.isAlphanumeric(first) or first == '_') {
            while (self.at < self.source.len and (std.ascii.isAlphanumeric(self.source[self.at]) or self.source[self.at] == '_')) self.at += 1;
        }
        return self.source[start..self.at];
    }

    fn literal(self: *Scanner, quote: u8) void {
        while (self.at < self.source.len) {
            const byte = self.source[self.at];
            self.at += 1;
            if (byte == quote) return;
            if (byte == '\\' and self.at < self.source.len) self.at += 1;
        }
        // A malformed literal is never an authority for excluding a body.
        self.hash.update(self.source);
    }

    fn trivia(self: *Scanner) void {
        while (self.at < self.source.len) {
            if (std.ascii.isWhitespace(self.source[self.at])) {
                self.at += 1;
                continue;
            }
            if (std.mem.startsWith(u8, self.source[self.at..], "//")) {
                const start = self.at;
                while (self.at < self.source.len and self.source[self.at] != '\n') self.at += 1;
                self.comment(self.source[start..@min(self.at + 1, self.source.len)]);
                continue;
            }
            if (std.mem.startsWith(u8, self.source[self.at..], "/*")) {
                const end = std.mem.indexOf(u8, self.source[self.at + 2 ..], "*/") orelse {
                    self.hash.update(self.source);
                    self.at = self.source.len;
                    return;
                };
                self.comment(self.source[self.at .. self.at + end + 4]);
                self.at += end + 4;
                continue;
            }
            return;
        }
    }

    fn comment(self: *Scanner, bytes: []const u8) void {
        // C removes escaped newlines before deciding where comments end.
        if (std.mem.indexOf(u8, bytes, "\\\n") != null or std.mem.indexOf(u8, bytes, "\\\r\n") != null) self.hash.update(self.source);
    }
};

// spec-case: NEW-CORE-S4-CACHE-1
test "runtime C surface binds declarations layouts and directives but omits bodies" {
    const first = digest("typedef struct { int value; } S; int f(S x) { return x.value; }");
    try std.testing.expectEqual(first, digest("typedef struct { int value; } S; int f(S x) { if (x.value) { return 2; } return 3; }"));
    try std.testing.expect(!std.mem.eql(u8, &first, &digest("typedef struct { long value; } S; int f(S x) { return x.value; }")));
    try std.testing.expect(!std.mem.eql(u8, &first, &digest("typedef struct { int value; } S; long f(S x) { return x.value; }")));
    try std.testing.expect(!std.mem.eql(u8, &digest("#define ABI 1\nint f(void) { return 1; }"), &digest("#define ABI 2\nint f(void) { return 1; }")));
    try std.testing.expectEqual(digest("int f(void) { return 1; }"), digest("int f(void) { const char *s=\"}\\\"{\"; /* } */ return 2; }"));
    try std.testing.expect(!std.mem.eql(u8, &digest("typedef int T; T g;"), &digest("typedef long T; T g;")));
    try std.testing.expect(!std.mem.eql(u8, &digest("extern int g;"), &digest("extern long g;")));
    try std.testing.expect(!std.mem.eql(u8, &digest("S x=(S){1};"), &digest("S x=(S){2};")));
    try std.testing.expect(!std.mem.eql(u8, &digest("typedef struct __attribute__((packed)) { int x; } S;"), &digest("typedef struct __attribute__((packed)) { long x; } S;")));
    try std.testing.expect(!std.mem.eql(u8, &digest("int f(void) { return 1;"), &digest("int f(void) { return 2;")));
    try std.testing.expect(!std.mem.eql(u8, &digest("int f(void) {\n#define ABI 1\\\n + 2\nreturn 1; }"), &digest("int f(void) {\n#define ABI 1\\\n + 3\nreturn 1; }")));
}

// spec-case: NEW-CORE-S4-CACHE-1
test "runtime C surface binds unsupported preprocessing and macro aggregates" {
    try std.testing.expect(!std.mem.eql(u8, &digest("int f(void) { // ignored \\\n#define ABI 1\nreturn 1; }\nABI x;"), &digest("int f(void) { // ignored\n#define ABI 1\nreturn 1; }\nABI x;")));
    try std.testing.expect(!std.mem.eql(u8, &digest("int f(void) { %:define ABI 1\nreturn 1; }\nABI x;"), &digest("int f(void) { %:define ABI 2\nreturn 1; }\nABI x;")));
    try std.testing.expect(!std.mem.eql(u8, &digest("int f(void) { ??=define ABI 1\nreturn 1; }\nABI x;"), &digest("int f(void) { ??=define ABI 2\nreturn 1; }\nABI x;")));
    try std.testing.expect(!std.mem.eql(u8, &digest("int f(void) { /* ignored \\\ncomment */ return 1; }"), &digest("int f(void) { /* ignored \\\ncomment */ return 2; }")));
    try std.testing.expect(!std.mem.eql(u8, &digest("#define AGG(name) typedef struct name\nAGG(S) { int x; } S;"), &digest("#define AGG(name) typedef struct name\nAGG(S) { long x; } S;")));
    try std.testing.expect(!std.mem.eql(u8, &digest("#define STORAGE typedef\n#define AGG(name) struct name\nSTORAGE AGG(S) { int x; } S;"), &digest("#define STORAGE typedef\n#define AGG(name) struct name\nSTORAGE AGG(S) { long x; } S;")));
    try std.testing.expect(!std.mem.eql(u8, &digest("OPAQUE(S) { int x; } S;"), &digest("OPAQUE(S) { long x; } S;")));
}

// spec-case: NEW-CORE-S4-CACHE-1
test "runtime ABI observes actual file edits independently of unchanged guest declarations" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    try dir.dir.writeFile(std.testing.io, .{ .sub_path = "runtime.c", .data = "typedef struct { int field; } S; int helper(S x) { return x.field; }" });
    const original = digest(try dir.dir.readFileAlloc(std.testing.io, "runtime.c", a, .limited(4096)));
    try dir.dir.writeFile(std.testing.io, .{ .sub_path = "runtime.c", .data = "typedef struct { int field; } S; int helper(S x) { return x.field + 1; }" });
    try std.testing.expectEqual(original, digest(try dir.dir.readFileAlloc(std.testing.io, "runtime.c", a, .limited(4096))));
    try dir.dir.writeFile(std.testing.io, .{ .sub_path = "runtime.c", .data = "typedef struct { int field; } S; long helper(S x) { return x.field; }" });
    try std.testing.expect(!std.mem.eql(u8, &original, &digest(try dir.dir.readFileAlloc(std.testing.io, "runtime.c", a, .limited(4096)))));
    try dir.dir.writeFile(std.testing.io, .{ .sub_path = "runtime.c", .data = "typedef struct { long field; } S; int helper(S x) { return x.field; }" });
    try std.testing.expect(!std.mem.eql(u8, &original, &digest(try dir.dir.readFileAlloc(std.testing.io, "runtime.c", a, .limited(4096)))));
}

// spec-case: NEW-CORE-S4-CACHE-1
test "embedded runtime body edit preserves its C ABI surface" {
    const source = @embedFile("runtime/core_rt.c");
    const edited = try std.mem.replaceOwned(u8, std.testing.allocator, source, "return atomic_load_explicit(&core_pool_started, memory_order_acquire);", "return !atomic_load_explicit(&core_pool_started, memory_order_acquire);");
    defer std.testing.allocator.free(edited);
    try std.testing.expect(!std.mem.eql(u8, source, edited));
    try std.testing.expectEqual(digest(source), digest(edited));
}
