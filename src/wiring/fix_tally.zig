//! Which of a command's printed diagnostics carry a structured fix, so that the command can end its report with how many of
//! them `selka fix` repairs.
//!
//! The text renderer (`diagnostic_output.render`) notes the first line of every text diagnostic whose fix has a place in the
//! source, `path:line:column: error[CODE]: message`; the display policy (`wiring/warning_display.zig`) asks `carries` for each
//! diagnostic it prints and counts the answers. The first line is the key because the report is text by the time it reaches the
//! display, and a cached or replayed report holds the same line as a fresh one. Nothing is noted unless a covered command switched
//! the tally on, so a command the policy does not cover (`lint`, `fix` itself) pays one lock and flag read per diagnostic.
const std = @import("std");

var enabled: bool = false;
var lock: std.atomic.Mutex = .unlocked;
var noted: std.AutoHashMapUnmanaged(u64, void) = .empty;

/// Switch the tally on or off for the command that is starting; either way the lines noted earlier are dropped.
pub fn enable(on: bool) void {
    acquire();
    defer lock.unlock();
    enabled = on;
    noted.clearAndFree(std.heap.page_allocator); // allocator-ok
}

/// The first line of `text`, a rendered diagnostic, without its newline.
pub fn firstLine(text: []const u8) []const u8 {
    return text[0 .. std.mem.indexOfScalar(u8, text, '\n') orelse text.len];
}

/// Note that the diagnostic rendered as `text` carries a structured fix. A failed allocation leaves it unnoted, which only makes the
/// closing count smaller.
pub fn note(text: []const u8) void {
    acquire();
    defer lock.unlock();
    if (!enabled) return;
    noted.put(std.heap.page_allocator, std.hash.Wyhash.hash(0, firstLine(text)), {}) catch return; // allocator-ok
}

/// Whether the diagnostic whose first printed line is `line` was noted as one that carries a fix.
pub fn carries(line: []const u8) bool {
    acquire();
    defer lock.unlock();
    return noted.contains(std.hash.Wyhash.hash(0, line));
}

/// The marker that ends a report's text in a store and starts the first lines of its diagnostics that carry a fix.
const trailer = "\x00selka-fix-lines\x00";

/// `text`, a report about to be stored, followed by a marker and the first lines of its diagnostics that carry a fix, one a line; `text`
/// itself when there are none. `detach` reads it back, so a replayed report closes with the same line as the run that stored it.
pub fn attach(a: std.mem.Allocator, text: []const u8) std.mem.Allocator.Error![]const u8 {
    acquire();
    defer lock.unlock();
    if (!enabled or noted.count() == 0) return text;
    var found: std.ArrayList(u8) = .empty;
    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |line| {
        if (line.len == 0 or !noted.contains(std.hash.Wyhash.hash(0, line))) continue;
        try found.appendSlice(a, line);
        try found.append(a, '\n');
    }
    return keep(a, text, found.items);
}

/// `text` followed by the marker and `fixed`, the first lines of its diagnostics that carry a fix, each ended by a newline; `text` itself
/// when `fixed` is empty. For a store written whatever the state of the tally (`attach` reads what the tally noted, so it needs the
/// command that stores to have switched the tally on): a replay by a command that covers the report reads the lines back with `detach`.
pub fn keep(a: std.mem.Allocator, text: []const u8, fixed: []const u8) std.mem.Allocator.Error![]const u8 {
    if (fixed.len == 0) return text;
    return std.mem.concat(a, u8, &.{ text, trailer, fixed });
}

/// The report `text` that `attach` produced, with its fix lines noted again for this run; `text` itself when it holds none.
pub fn detach(text: []const u8) []const u8 {
    const at = std.mem.lastIndexOf(u8, text, trailer) orelse return text;
    var lines = std.mem.splitScalar(u8, text[at + trailer.len ..], '\n');
    while (lines.next()) |line| if (line.len != 0) note(line);
    return text[0..at];
}

fn acquire() void {
    while (!lock.tryLock()) std.atomic.spinLoopHint();
}

test "a noted diagnostic is found by its first line only while the tally is on" {
    enable(true);
    defer enable(false);
    note("a.selka:3:5: error[E_X]: message\n  text\n  ^\n");
    try std.testing.expect(carries("a.selka:3:5: error[E_X]: message"));
    try std.testing.expect(!carries("a.selka:3:5: error[E_Y]: message"));
    enable(false);
    note("b.selka:1:1: error[E_X]: message\n");
    try std.testing.expect(!carries("b.selka:1:1: error[E_X]: message"));
    try std.testing.expect(!carries("a.selka:3:5: error[E_X]: message"));
}

test "a stored report keeps which of its diagnostics carry a fix, and a plain one comes back as it was" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    enable(true);
    defer enable(false);
    const report = "a.selka:3:5: warning[W_X]: one\n  line\n  ^\na.selka:9:1: warning[W_Y]: two\n  line\n  ^\n";
    try std.testing.expectEqualStrings(report, try attach(a, report));
    note("a.selka:9:1: warning[W_Y]: two");
    const stored = try attach(a, report);
    try std.testing.expect(stored.len > report.len);
    enable(true);
    try std.testing.expect(!carries("a.selka:9:1: warning[W_Y]: two"));
    try std.testing.expectEqualStrings(report, detach(stored));
    try std.testing.expect(carries("a.selka:9:1: warning[W_Y]: two"));
    try std.testing.expect(!carries("a.selka:3:5: warning[W_X]: one"));
    try std.testing.expectEqualStrings(report, detach(report));
}

test "a report kept with its fix lines while the tally is off comes back noted when a command that counts replays it" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const report = "a.selka:3:5: warning[W_X]: one\n  line\n  ^\na.selka:9:1: warning[W_Y]: two\n  line\n  ^\n";
    try std.testing.expectEqualStrings(report, try keep(a, report, ""));
    const stored = try keep(a, report, "a.selka:9:1: warning[W_Y]: two\n");
    try std.testing.expectEqualStrings(report, detach(stored));
    try std.testing.expect(!carries("a.selka:9:1: warning[W_Y]: two"));
    enable(true);
    defer enable(false);
    try std.testing.expectEqualStrings(report, detach(stored));
    try std.testing.expect(carries("a.selka:9:1: warning[W_Y]: two"));
    try std.testing.expect(!carries("a.selka:3:5: warning[W_X]: one"));
}
