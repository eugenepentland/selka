//! FR5a (F-4): `acquire_resource` on a Network belongs to the standard library's `network` module, whose requests are
//! its own encoding: outside it the builtin is `E_INTERNAL_NAME`, in every spelling that reaches it, with a repair only
//! where the operation sends the same request. The Filesystem's builtin keeps its old rule. The operations that take
//! an address at run time are tested by `tests/lang/network_addresses.selka` (the stand-ins) and
//! `test/network_address_cli_test.zig` (the grants).
const std = @import("std");
const t = std.testing;
const fixture = @import("stdlib_fixture.zig");

/// Check `text` and return its first diagnostic's code, message and repair text ("" for none).
fn firstRefusal(arena: std.mem.Allocator, text: []const u8) ![3][]const u8 {
    const checked = try fixture.check(arena, text);
    try t.expect(!checked.passed);
    const first = checked.diagnostics[0];
    const repair = if (first.provenance.fix) |fix| fix.edit.text else "";
    return .{ first.code, first.message, repair };
}

/// A program whose `main` acquires `result_type` on `receiver` with `request`, after the lines of `before`.
fn acquiring(comptime before: []const u8, comptime result_type: []const u8, comptime receiver: []const u8, comptime request: []const u8) []const u8 {
    return "import network\n\n" ++ before ++
        "func main(net: Network) -> int:\n" ++
        "    with net.host(\"127.0.0.1:8000\") as scoped:\n" ++
        "        match acquire_resource[" ++ result_type ++ "](" ++ receiver ++ ", " ++ request ++ "):\n" ++
        "            case ok(made):\n" ++
        "                _ = own made\n" ++
        "                return 0\n" ++
        "            case err(code):\n" ++
        "                return code\n";
}

const own_result = "resource Socket: network\n\nresult Open:\n    ok: Socket,\n    err: int\n\n";
const holder = "record Holder:\n    net: Network\n\n";

test "acquire_resource on a Network is refused outside the standard library in each spelling that reaches it" {
    var arena_state = std.heap.ArenaAllocator.init(t.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    // A resource and result the program declares, as the effects guide used to show.
    const declared = try firstRefusal(arena, comptime acquiring(own_result, "Open", "scoped", "FixedArray[u8, 1]([0u8])"));
    try t.expectEqualStrings("E_INTERNAL_NAME", declared[0]);
    try t.expect(std.mem.indexOf(u8, declared[1], "`network.connect_to`, `connect_within_to`, `listen_at`, `open_poller_at` or `dial_to`") != null);
    // The standard library's own result on main's un-narrowed Network, with a request built from a run-time address.
    const run_time = "import strings\n\n\nfunc request_of(address: str) -> FixedArray[u8, 15]:\n" ++
        "    mut request = FixedArray[u8, 15]([0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8])\n" ++
        "    mut at = 0\n" ++
        "    for octet in strings.encode(address):\n" ++
        "        if at < 15:\n" ++
        "            request[at] = u8(octet)\n" ++
        "        at += 1\n" ++
        "    return request\n\n";
    try fixture.rejectsWith(arena, comptime acquiring(run_time, "network.Polling", "net", "request_of(\"127.0.0.1:39851\")"), "E_INTERNAL_NAME");
    // Through a record that holds the Network.
    try fixture.rejectsWith(arena, "import network\n\n" ++ holder ++
        "func reach(held: Holder) -> int:\n" ++
        "    match acquire_resource[network.Connected](held.net, FixedArray[u8, 1]([0u8])):\n" ++
        "        case ok(made):\n" ++
        "            _ = network.close(own made)\n" ++
        "            return 0\n" ++
        "        case err(code):\n" ++
        "            return code\n\n" ++
        "func main(net: Network) -> int:\n" ++
        "    return reach(Holder(net=net))\n", "E_INTERNAL_NAME");
    // In a function that fails, and in a generic body nothing instantiates.
    try fixture.rejectsWith(arena, "import network\n\n" ++
        "func reach(net: Network) -> int fails int:\n" ++
        "    match acquire_resource[network.Connected](net, FixedArray[u8, 1]([0u8])):\n" ++
        "        case ok(made):\n" ++
        "            _ = network.close(own made)\n" ++
        "            return 0\n" ++
        "        case err(code):\n" ++
        "            fail code\n\n" ++
        "func main(net: Network) -> int:\n" ++
        "    match reach(net):\n" ++
        "        case Ok(value):\n" ++
        "            return value\n" ++
        "        case Err(code):\n" ++
        "            return code\n", "E_INTERNAL_NAME");
    try fixture.rejectsWith(arena, "import network\n\n" ++
        "func reach[T](net: Network, request: FixedArray[u8, 1]) -> network.Connected:\n" ++
        "    return acquire_resource[network.Connected](net, request)\n\n" ++
        "func main() -> int:\n" ++
        "    return 0\n", "E_INTERNAL_NAME");
}

test "the refusal repairs a one-octet request of the library's own result to the operation that sends the same octet" {
    var arena_state = std.heap.ArenaAllocator.init(t.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const connect = try firstRefusal(arena, comptime acquiring("", "network.Connected", "scoped", "FixedArray[u8, 1]([0u8])"));
    try t.expectEqualStrings("network.connect(scoped)", connect[2]);
    const listen = try firstRefusal(arena, comptime acquiring("", "network.Listening", "scoped", "FixedArray[u8, 1]([1u8])"));
    try t.expectEqualStrings("network.listen(scoped)", listen[2]);
    const poller = try firstRefusal(arena, comptime acquiring("", "network.Polling", "scoped", "FixedArray[u8, 1]([2u8])"));
    try t.expectEqualStrings("network.open_poller(scoped)", poller[2]);
    // No repair is certain for an octet that is not the result's own, a request with an address in it, or a result
    // the program declares: the operation would send other octets or answer another type.
    const mismatched = try firstRefusal(arena, comptime acquiring("", "network.Connected", "scoped", "FixedArray[u8, 1]([2u8])"));
    try t.expectEqualStrings("", mismatched[2]);
    const addressed = try firstRefusal(arena, comptime acquiring("", "network.Connected", "net", "FixedArray[u8, 3]([49u8, 58u8, 49u8])"));
    try t.expectEqualStrings("", addressed[2]);
    const declared = try firstRefusal(arena, comptime acquiring(own_result, "Open", "scoped", "FixedArray[u8, 1]([0u8])"));
    try t.expectEqualStrings("", declared[2]);
}

test "acquire_resource on a Filesystem keeps its rule outside the standard library" {
    var arena_state = std.heap.ArenaAllocator.init(t.allocator);
    defer arena_state.deinit();
    try fixture.accept(arena_state.allocator(), "resource File: filesystem\n\n" ++
        "result Open:\n    ok: File,\n    err: int\n\n" ++
        "func main(fs: Filesystem) -> int:\n" ++
        "    with fs.dir(\"data\") as scoped:\n" ++
        "        match acquire_resource[Open](scoped, FixedArray[u8, 3]([114u8, 58u8, 120u8])):\n" ++
        "            case ok(file):\n" ++
        "                _ = own file\n" ++
        "                return 0\n" ++
        "            case err(code):\n" ++
        "                return code\n");
}

test "net.host with a value that is not a literal names the operations that take an address at run time" {
    var arena_state = std.heap.ArenaAllocator.init(t.allocator);
    defer arena_state.deinit();
    const refused = try firstRefusal(arena_state.allocator(), "import network\n\n" ++
        "func reach(net: Network, address: str) -> int:\n" ++
        "    with net.host(address) as scoped:\n" ++
        "        match network.connect(scoped):\n" ++
        "            case ok(made):\n" ++
        "                _ = network.close(own made)\n" ++
        "                return 0\n" ++
        "            case err(code):\n" ++
        "                return code\n\n" ++
        "func main(net: Network) -> int:\n" ++
        "    return reach(net, \"127.0.0.1:9000\")\n");
    try t.expectEqualStrings("E_NETWORK_HOST", refused[0]);
    try t.expect(std.mem.startsWith(u8, refused[1], "host requires a string literal endpoint; "));
    try t.expect(std.mem.indexOf(u8, refused[1], "`network.connect_to`, `connect_within_to`, `listen_at`, `open_poller_at` or `dial_to`") != null);
}
