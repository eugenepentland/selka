//! The self-contained HTML pages the review commands write. Each page is an embedded
//! template with one `__DATA__` placeholder, which the page's JSON replaces. The JSON is
//! escaped so that no closing script tag or comment opener in the data can end the
//! script element early. The templates name no network resource, so a page reads the
//! same from `file://` and from a web server.
const std = @import("std");

/// Failure to build a page: allocation is the only one.
pub const Error = std.mem.Allocator.Error;

/// The placeholder the page's data replaces, exactly once per template.
const placeholder = "__DATA__";
/// The change review page of one `review-v1` object.
const review_template = @embedFile("review_page.html");
/// The project page of one overview document.
const project_template = @embedFile("project_page.html");
/// The front page of a review site.
const index_template = @embedFile("review_index.html");

/// The change review page for one `review-v1` JSON object. The bytes belong to `a`.
pub fn review(a: std.mem.Allocator, json: []const u8) Error![]u8 {
    return fill(a, review_template, json);
}

/// The project page for one data object: the overview-v1 document, the release note titles
/// and the optional link back to the site. The bytes belong to `a`.
pub fn project(a: std.mem.Allocator, json: []const u8) Error![]u8 {
    return fill(a, project_template, json);
}

/// The front page of a review site for one data object: the gate mode, the projects and the
/// reviews. The bytes belong to `a`.
pub fn siteIndex(a: std.mem.Allocator, json: []const u8) Error![]u8 {
    return fill(a, index_template, json);
}

/// Replace the template's placeholder with `json`, escaped for a script element.
pub fn fill(a: std.mem.Allocator, template: []const u8, json: []const u8) Error![]u8 {
    const escaped = try escapeScript(a, json);
    const at = std.mem.indexOf(u8, template, placeholder) orelse return a.dupe(u8, template);
    var out: std.ArrayList(u8) = .empty;
    try out.appendSlice(a, template[0..at]);
    try out.appendSlice(a, escaped);
    try out.appendSlice(a, template[at + placeholder.len ..]);
    return out.items;
}

/// Escape JSON for a script element: every `</` becomes `<\/` (the same text in a JSON
/// string), and every `<!--` becomes `<!--`, so the data never closes the element.
pub fn escapeScript(a: std.mem.Allocator, json: []const u8) Error![]u8 {
    var out: std.ArrayList(u8) = .empty;
    var index: usize = 0;
    while (index < json.len) {
        const rest = json[index..];
        if (std.mem.startsWith(u8, rest, "</")) {
            try out.appendSlice(a, "<\\/");
            index += 2;
        } else if (std.mem.startsWith(u8, rest, "<!--")) {
            try out.appendSlice(a, "\\u003c!--");
            index += 4;
        } else {
            try out.append(a, rest[0]);
            index += 1;
        }
    }
    return out.items;
}

/// The URL schemes a template must never name, spelled apart so that no literal URL is in the source.
const network_schemes = [_][]const u8{ "http" ++ "://", "https" ++ "://" };

/// Assert that a template names no network resource: no `http://` and no `https://`.
fn expectNoNetwork(template: []const u8) !void {
    for (network_schemes) |scheme| try std.testing.expect(std.mem.indexOf(u8, template, scheme) == null);
}

test "review html escapes every closing script tag in the data" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const escaped = try escapeScript(arena.allocator(), "{\"s\":\"</script><b>\",\"c\":\"<!-- x\"}");
    try std.testing.expectEqualStrings("{\"s\":\"<\\/script><b>\",\"c\":\"\\u003c!-- x\"}", escaped);
    try std.testing.expect(std.mem.indexOf(u8, escaped, "</") == null);
}

test "review html fills the placeholder with the escaped data and nothing else" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const filled = try fill(arena.allocator(), "a__DATA__b", "{\"x\":\"</\"}");
    try std.testing.expectEqualStrings("a{\"x\":\"<\\/\"}b", filled);
}

test "review html templates name no network resource" {
    try expectNoNetwork(review_template);
    try expectNoNetwork(project_template);
    try expectNoNetwork(index_template);
    try std.testing.expect(std.mem.indexOf(u8, review_template, "fonts.googleapis") == null);
    try std.testing.expect(std.mem.indexOf(u8, project_template, "fonts.googleapis") == null);
}

test "review html each template holds exactly one data placeholder" {
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, review_template, placeholder));
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, project_template, placeholder));
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, index_template, placeholder));
}

test "review html writes the project page's data into the project template" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const page = try project(arena.allocator(), "{\"overview\":{\"title\":\"app\"},\"back\":null}");
    try std.testing.expect(std.mem.startsWith(u8, page, "<!doctype html>"));
    try std.testing.expect(std.mem.indexOf(u8, page, "{\"overview\":{\"title\":\"app\"},\"back\":null}") != null);
    try std.testing.expect(std.mem.indexOf(u8, page, placeholder) == null);
}

test "review html writes the review's data into its page" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const page = try review(arena.allocator(), "{\"version\":\"review-v1\",\"project\":\"app\"}\n");
    try std.testing.expect(std.mem.startsWith(u8, page, "<!doctype html>"));
    try std.testing.expect(std.mem.indexOf(u8, page, "{\"version\":\"review-v1\",\"project\":\"app\"}") != null);
    try std.testing.expect(std.mem.indexOf(u8, page, placeholder) == null);
}
