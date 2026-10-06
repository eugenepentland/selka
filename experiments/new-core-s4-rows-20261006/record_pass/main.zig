// Row `record_pass` (S4 CONTRACT.md): a twelve-field struct passed and returned by value.
const std = @import("std");
const MOD: i64 = 1_000_000_007;
const State = struct { f0: i64, f1: i64, f2: i64, f3: i64, f4: i64, f5: i64, f6: i64, f7: i64, f8: i64, f9: i64, f10: i64, f11: i64 };
const Timespec = extern struct { sec: c_long, nsec: c_long };
extern "c" fn clock_gettime(clock: c_int, time: *Timespec) c_int;
extern "c" fn printf(format: [*:0]const u8, ...) c_int;
fn now() i64 {
    var ts: Timespec = undefined;
    if (clock_gettime(1, &ts) != 0) @panic("clock failed");
    return ts.sec * 1_000_000_000 + ts.nsec;
}
fn mix(a: i64, b: i64) i64 {
    return @mod(a * 31 + b, 1009);
}
fn advance(s: State, x: i64) State {
    const t = mix(s.f0 + s.f5, x);
    const f3 = if (@mod(x, 3) == 0) mix(s.f4, x) else s.f4;
    return .{
        .f0 = s.f1,
        .f1 = s.f2,
        .f2 = s.f3,
        .f3 = f3,
        .f4 = s.f5,
        .f5 = s.f6,
        .f6 = s.f7,
        .f7 = s.f8,
        .f8 = s.f9,
        .f9 = s.f10,
        .f10 = s.f11,
        .f11 = t,
    };
}
fn batchResult(size: i64, batch: i64, seed: i64) i64 {
    const base = seed + batch;
    var s: State = .{
        .f0 = @mod(base, 1009),
        .f1 = @mod(base + 7, 1009),
        .f2 = @mod(base + 14, 1009),
        .f3 = @mod(base + 21, 1009),
        .f4 = @mod(base + 28, 1009),
        .f5 = @mod(base + 35, 1009),
        .f6 = @mod(base + 42, 1009),
        .f7 = @mod(base + 49, 1009),
        .f8 = @mod(base + 56, 1009),
        .f9 = @mod(base + 63, 1009),
        .f10 = @mod(base + 70, 1009),
        .f11 = @mod(base + 77, 1009),
    };
    var j: i64 = 0;
    while (j < size) : (j += 1) s = advance(s, @mod(base + 13 * j, 1009));
    return s.f0 + 2 * s.f1 + 3 * s.f2 + 4 * s.f3 + 5 * s.f4 + 6 * s.f5 + 7 * s.f6 + 8 * s.f7 + 9 * s.f8 +
        10 * s.f9 + 11 * s.f10 + 12 * s.f11;
}
fn run(argc: c_int, argv: [*][*:0]const u8) c_int {
    if (argc != 5 or !std.mem.eql(u8, std.mem.span(argv[1]), "record_pass")) return 2;
    const size = std.fmt.parseInt(i64, std.mem.span(argv[2]), 10) catch return 2;
    const iterations = std.fmt.parseInt(i64, std.mem.span(argv[3]), 10) catch return 2;
    const seed = std.fmt.parseInt(i64, std.mem.span(argv[4]), 10) catch return 2;
    if (size < 2 or iterations < 1 or seed < 1 or seed > 1000000) return 2;
    var checksum: i64 = 0;
    const start = now();
    var batch: i64 = 0;
    while (batch < iterations) : (batch += 1) checksum = @mod(checksum + batchResult(size, batch, seed), MOD);
    const elapsed = now() - start;
    _ = printf("%lld %lld\n", @as(c_longlong, checksum), @as(c_longlong, elapsed));
    return 0;
}
/// Runs the record_pass row selected by argv.
pub export fn main(argc: c_int, argv: [*][*:0]const u8) c_int {
    return run(argc, argv);
}
