//! The event loop's runtime and checker contracts, run natively with explicit grants and no client:
//! the `Poller` resource, the port-0 listen grant, the operation outcomes and the ownership rules.
//! The end-to-end scenarios with real loopback clients live in `test/network_poller_cli_test.zig`.
const std = @import("std");
const t = std.testing;
const fixture = @import("stdlib_fixture.zig");
const transition = @import("ownership_transition_test_support.zig");

/// A program that opens a poller on `endpoint` and returns 1 when it reports a nonzero bound port,
/// else 100 plus the code the open failed with (2 is a denied endpoint).
fn opener(comptime endpoint: []const u8, comptime opens: []const u8) []const u8 {
    return "import network\n\n\n" ++
        "func bound(own poller: network.Poller) -> int:\n" ++
        "    mut live = own poller\n" ++
        "    mut outcome = network.new_outcome()\n" ++
        "    live = network.port(own live, network.LISTENER, mut outcome)\n" ++
        "    if outcome.value > 0:\n" ++
        "        return 1\n" ++
        "    return 0\n\n\n" ++
        "func main(net: Network) -> int:\n" ++
        "    with net.host(\"" ++ endpoint ++ "\") as scoped:\n" ++
        "        match " ++ opens ++ ":\n" ++
        "            case ok(poller):\n" ++
        "                return bound(own poller)\n" ++
        "            case err(code):\n" ++
        "                return 100 + code\n";
}

const open_poller = "network.open_poller(scoped)";

fn granted(options: []const []const u8, wanted: i64, text: []const u8) !void {
    try fixture.expect(t.allocator, text, .{ .arguments = options }, wanted);
}

// spec: NETWORK-POLL-1
test "a poller binds the kernel's port under a port-0 listen grant and the grant is matched verbatim" {
    const zero = [_][]const u8{ "--restrict", "--allow-listen=127.0.0.1:0" };
    // The :0 grant permits the :0 endpoint, and the poller reports the port the kernel chose.
    try granted(&zero, 1, comptime opener("127.0.0.1:0", open_poller));
    // It does not permit a named port: the match is verbatim.
    try granted(&zero, 102, comptime opener("127.0.0.1:18461", open_poller));
    // A named-port grant does not permit port 0.
    const named = [_][]const u8{ "--restrict", "--allow-listen=127.0.0.1:18462" };
    try granted(&named, 102, comptime opener("127.0.0.1:0", open_poller));
    // An outbound endpoint grant never permits a listener or a poller.
    const outbound = [_][]const u8{ "--restrict", "--allow-endpoint=127.0.0.1:18463", "--allow-listen=127.0.0.1:18464" };
    try granted(&outbound, 102, comptime opener("127.0.0.1:18463", open_poller));
    // A blocking listener cannot report its port, so it refuses a port-0 narrowing.
    try granted(&zero, 102, comptime "import network\n\n\n" ++
        "func main(net: Network) -> int:\n" ++
        "    with net.host(\"127.0.0.1:0\") as scoped:\n" ++
        "        match network.listen(scoped):\n" ++
        "            case ok(listener):\n" ++
        "                _ = own listener\n" ++
        "                return 1\n" ++
        "            case err(code):\n" ++
        "                return 100 + code\n");
}

// spec-case: NETWORK-POLL-1
test "a denied stand-in Network refuses a poller" {
    try fixture.run(t.allocator,
        \\import network
        \\
        \\
        \\func main() -> int:
        \\    mut net = network.denied()
        \\    with net.host("127.0.0.1:0") as scoped:
        \\        match network.open_poller(scoped):
        \\            case ok(poller):
        \\                _ = own poller
        \\                return 1
        \\            case err(code):
        \\                return code
    , network_denied);
}

/// The code a stand-in Network answers every acquisition with (`network.denied_here()`).
const network_denied = 6;

/// A poller with no clients: every operation answers at once with the documented outcome.
const quiet_poller =
    \\import byte_builder
    \\import network
    \\
    \\
    \\func score(own poller: network.Poller) -> int:
    \\    mut live = own poller
    \\    mut outcome = network.new_outcome()
    \\    mut ready = network.new_ready()
    \\    mut raw = byte_builder.create()
    \\    mut total = 0
    \\    live = network.wait(own live, 0, mut ready)
    \\    total += ready.count
    \\    live = network.wait(own live, 20, mut ready)
    \\    total += ready.count
    \\    live = network.accept(own live, mut outcome)
    \\    if outcome.code == network.OUTCOME_WOULD_BLOCK:
    \\        total += 10
    \\    live = network.recv(own live, 1024, mut raw, mut outcome)
    \\    if outcome.code == network.OUTCOME_UNKNOWN:
    \\        total += 100
    \\    live = network.send(own live, 1024, b"x", 0, mut outcome)
    \\    if outcome.code == network.OUTCOME_UNKNOWN:
    \\        total += 1000
    \\    live = network.close_connection(own live, 7, mut outcome)
    \\    if outcome.code == network.OUTCOME_UNKNOWN:
    \\        total += 10000
    \\    live = network.close_connection(own live, network.LISTENER, mut outcome)
    \\    if outcome.code == network.OUTCOME_BAD:
    \\        total += 100000
    \\    live = network.peer(own live, network.LISTENER, mut outcome)
    \\    if outcome.code == network.OUTCOME_BAD:
    \\        total += 1000000
    \\    live = network.set_interest(own live, network.LISTENER, 4, mut outcome)
    \\    if outcome.code == network.OUTCOME_BAD:
    \\        total += 10000000
    \\    live = network.connection_limit(own live, mut outcome)
    \\    if outcome.value >= 512 and outcome.extra == 0:
    \\        total += 100000000
    \\    return total
    \\
    \\
    \\func main(net: Network) -> int:
    \\    with net.host("127.0.0.1:0") as scoped:
    \\        match network.open_poller(scoped):
    \\            case ok(poller):
    \\                return score(own poller)
    \\            case err(code):
    \\                return 0 - code
;

// spec-case: NETWORK-POLL-3
test "a poller with no clients answers every operation at once with its documented outcome" {
    const zero = [_][]const u8{ "--restrict", "--allow-listen=127.0.0.1:0" };
    try fixture.expect(t.allocator, quiet_poller, .{ .arguments = &zero }, 111111110);
}

/// A client's poller: it listens on nothing, so every operation answers at once as the module says, and a dial to an
/// endpoint no grant names is denied before any socket is made. Each answer adds one power of two to the result.
const client_quiet =
    \\import byte_builder
    \\import network
    \\
    \\
    \\func score(own poller: network.Poller, net: Network) -> int:
    \\    mut live = own poller
    \\    mut outcome = network.new_outcome()
    \\    mut ready = network.new_ready()
    \\    mut raw = byte_builder.create()
    \\    mut total = 0
    \\    live = network.wait(own live, 20, mut ready)
    \\    if ready.count == 0:
    \\        total += 1
    \\    live = network.accept(own live, mut outcome)
    \\    if outcome.code == network.OUTCOME_WOULD_BLOCK:
    \\        total += 2
    \\    live = network.port(own live, network.LISTENER, mut outcome)
    \\    if outcome.code == network.OUTCOME_BAD:
    \\        total += 4
    \\    live = network.set_interest(own live, network.LISTENER, network.EVENT_READABLE, mut outcome)
    \\    if outcome.code == network.OUTCOME_BAD:
    \\        total += 8
    \\    live = network.connection_limit(own live, mut outcome)
    \\    if outcome.value >= 512 and outcome.extra == 0:
    \\        total += 16
    \\    network.dial_to(mut live, net, "127.0.0.1:9", mut outcome)
    \\    if outcome.code == network.OUTCOME_DENIED and outcome.value == 2:
    \\        total += 32
    \\    live = network.recv(own live, 1024, mut raw, mut outcome)
    \\    if outcome.code == network.OUTCOME_UNKNOWN:
    \\        total += 64
    \\    return total
    \\
    \\
    \\func main(net: Network) -> int:
    \\    match network.open_client_poller(net):
    \\        case ok(poller):
    \\            return score(own poller, net)
    \\        case err(code):
    \\            return 0 - code
;

// spec: NETWORK-POLL-6
test "a client poller opens under a connect grant alone and answers every operation at once" {
    const outbound = [_][]const u8{ "--restrict", "--allow-endpoint=127.0.0.1:18471" };
    try fixture.expect(t.allocator, client_quiet, .{ .arguments = &outbound }, 127);
}

/// A program that opens a client poller through `net` as it is and answers 1 when it opened, else 100 plus the code the
/// open failed with.
const client_plain =
    \\import network
    \\
    \\
    \\func main(net: Network) -> int:
    \\    match network.open_client_poller(net):
    \\        case ok(poller):
    \\            _ = own poller
    \\            return 1
    \\        case err(code):
    \\            return 100 + code
;

/// The same through `net.host(endpoint)`.
fn client_narrowed(comptime endpoint: []const u8) []const u8 {
    return "import network\n\n\nfunc main(net: Network) -> int:\n" ++
        "    with net.host(\"" ++ endpoint ++ "\") as scoped:\n" ++
        "        match network.open_client_poller(scoped):\n" ++
        "            case ok(poller):\n" ++
        "                _ = own poller\n" ++
        "                return 1\n" ++
        "            case err(code):\n" ++
        "                return 100 + code\n";
}

// spec: NETWORK-POLL-6
test "a client poller needs a connect grant and no listen grant, and a narrowed Network's endpoint must be granted" {
    const outbound = [_][]const u8{ "--restrict", "--allow-endpoint=127.0.0.1:18471" };
    // The connect grant alone opens it, through the Network as it is and through a narrowing of a granted endpoint.
    try granted(&outbound, 1, client_plain);
    try granted(&outbound, 1, comptime client_narrowed("127.0.0.1:18471"));
    // A narrowing of an endpoint no grant names is refused, as a connect to it is (2).
    try granted(&outbound, 102, comptime client_narrowed("127.0.0.1:18472"));
    // A listen grant is not a connect grant: a launch that grants only listening refuses it as `connect` is refused (1).
    const listening = [_][]const u8{ "--restrict", "--allow-listen=127.0.0.1:0" };
    try granted(&listening, 101, client_plain);
    // Both grants together change nothing for the client.
    const both = [_][]const u8{ "--restrict", "--allow-endpoint=127.0.0.1:18471", "--allow-listen=127.0.0.1:0" };
    try granted(&both, 1, client_plain);
}

// spec-case: NETWORK-POLL-6
test "the stand-in Networks offer no client poller" {
    // `memory()` offers no poller of either kind (2, as `open_poller`), and `denied()` refuses every request (6).
    try fixture.run(t.allocator,
        \\import network
        \\
        \\
        \\func opened(net: Network) -> int:
        \\    match network.open_client_poller(net):
        \\        case ok(poller):
        \\            _ = own poller
        \\            return 0
        \\        case err(code):
        \\            return code
        \\
        \\
        \\func main() -> int:
        \\    mut memory = network.memory()
        \\    mut denied = network.denied()
        \\    return opened(memory) * 10 + opened(denied)
    , 26);
}

// spec: NETWORK-POLL-5
test "a poller is an ordinary network resource to the ownership checker" {
    // The wrappers return the poller, so a loop reassigns one local.
    const zero = [_][]const u8{ "--restrict", "--allow-listen=127.0.0.1:0" };
    try fixture.expect(t.allocator,
        \\import network
        \\
        \\
        \\func spin(own poller: network.Poller) -> int:
        \\    mut live = own poller
        \\    mut ready = network.new_ready()
        \\    mut turns = 0
        \\    while turns < 3:
        \\        live = network.wait(own live, 0, mut ready)
        \\        turns += 1
        \\    return turns
        \\
        \\
        \\func main(net: Network) -> int:
        \\    with net.host("127.0.0.1:0") as scoped:
        \\        match network.open_poller(scoped):
        \\            case ok(poller):
        \\                return spin(own poller)
        \\            case err(code):
        \\                return 0 - code
    , .{ .arguments = &zero }, 3);
    // It cannot be used after it was handed to a wrapper.
    const twice =
        \\import network
        \\
        \\
        \\func twice(own poller: network.Poller) -> int:
        \\    mut live = own poller
        \\    mut ready = network.new_ready()
        \\    const first = network.wait(own live, 0, mut ready)
        \\    const second = network.wait(own live, 0, mut ready)
        \\    _ = first
        \\    _ = second
        \\    return 0
        \\
        \\
        \\func main() -> int:
        \\    return 0
    ;
    {
        var arena = std.heap.ArenaAllocator.init(t.allocator);
        defer arena.deinit();
        try fixture.accept(arena.allocator(), twice);
    }
    try transition.refuses(t.allocator, twice, "E_SINGLE_OWNER_MOVED");
    // It cannot be kept in a list.
    try fixture.reject(t.allocator,
        \\import network
        \\
        \\
        \\func main() -> int:
        \\    mut pollers: network.Poller[] = []
        \\    return len(pollers)
    );
    // Events and outcomes are plain values that live in ordinary collections.
    try fixture.run(t.allocator,
        \\import network
        \\
        \\
        \\func main() -> int:
        \\    mut outcomes: dict[int, network.Outcome] = {}
        \\    outcomes[1024] = network.new_outcome()
        \\    return len(outcomes) + network.EVENT_IDLE
    , 17);
}
