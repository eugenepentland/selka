//! Named-constraint review repros kept as executable regressions.
//! Sources come from docs/audits/named-constraints-review-2026-09-15-probes.json.
const std = @import("std");

/// One embedded source file of a review probe.
pub const File = struct { name: []const u8, body: []const u8 };
/// One checking probe and the outcome a fixed compiler must produce.
pub const Probe = struct {
    name: []const u8,
    command: []const u8,
    expect_success: bool,
    /// Diagnostic code substring required when the probe must reject.
    diagnostic: []const u8 = "",
    files: []const File,
};
/// All 18 review probes: 13 repaired failures plus 5 controls.
pub const probes = [_]Probe{
    .{
        .name = "nominal_distinct_coalesce",
        .command = "check-project",
        .expect_success = false,
        .diagnostic = "E_GENERIC_REQUIREMENT",
        .files = &.{
            .{ .name = "a.my", .body =
            \\module a
            \\export ID
            \\export Has
            \\record ID:
            \\    value: int
            \\constraint Has[T] = copy + field(value: ID)
            \\
            },
            .{ .name = "b.my", .body =
            \\module b
            \\export ID
            \\export Has
            \\record ID:
            \\    value: int
            \\constraint Has[T] = copy + field(value: ID)
            \\
            },
            .{ .name = "main.my", .body =
            \\module main
            \\import a
            \\import b
            \\record Row:
            \\    value: a.ID
            \\def accept[T: a.Has + b.Has](row: T) -> int:
            \\    return 0
            \\def main() -> int:
            \\    return accept(Row(value=a.ID(value=7)))
            \\
            },
        },
    },
    .{
        .name = "nominal_distinct_reverse",
        .command = "check-project",
        .expect_success = false,
        .diagnostic = "E_GENERIC_REQUIREMENT",
        .files = &.{
            .{ .name = "a.my", .body =
            \\module a
            \\export ID
            \\export Has
            \\record ID:
            \\    value: int
            \\constraint Has[T] = copy + field(value: ID)
            \\
            },
            .{ .name = "b.my", .body =
            \\module b
            \\export ID
            \\export Has
            \\record ID:
            \\    value: int
            \\constraint Has[T] = copy + field(value: ID)
            \\
            },
            .{ .name = "main.my", .body =
            \\module main
            \\import a
            \\import b
            \\record Row:
            \\    value: a.ID
            \\def accept[T: b.Has + a.Has](row: T) -> int:
            \\    return 0
            \\def main() -> int:
            \\    return accept(Row(value=a.ID(value=7)))
            \\
            },
        },
    },
    .{
        .name = "capture_imported_nominal",
        .command = "check-project",
        .expect_success = false,
        .diagnostic = "E_GENERIC_TYPE",
        .files = &.{
            .{ .name = "contracts.my", .body =
            \\module contracts
            \\export Token
            \\export Use
            \\record Token:
            \\    value: int
            \\constraint Use[S] = copy + op(use(s: S, token: Token) -> int effects())
            \\
            },
            .{ .name = "main.my", .body =
            \\module main
            \\import contracts
            \\domain Provider: int:
            \\    def make() -> Provider:
            \\        return wrap[Provider](0)
            \\    def use(s: Provider, token: int) -> int effects():
            \\        return token
            \\def call[Token, P: contracts.Use](p: P, token: Token) -> int effects():
            \\    return P.use(p, token)
            \\def main() -> int:
            \\    return call(Provider.make(), 0)
            \\
            },
        },
    },
    .{
        .name = "capture_control_renamed",
        .command = "check-project",
        .expect_success = false,
        .diagnostic = "E_GENERIC_TYPE",
        .files = &.{
            .{ .name = "contracts.my", .body =
            \\module contracts
            \\export Token
            \\export Use
            \\record Token:
            \\    value: int
            \\constraint Use[S] = copy + op(use(s: S, token: Token) -> int effects())
            \\
            },
            .{ .name = "main.my", .body =
            \\module main
            \\import contracts
            \\domain Provider: int:
            \\    def make() -> Provider:
            \\        return wrap[Provider](0)
            \\    def use(s: Provider, token: int) -> int effects():
            \\        return token
            \\def call[U, P: contracts.Use](p: P, token: U) -> int effects():
            \\    return P.use(p, token)
            \\def main() -> int:
            \\    return call(Provider.make(), 0)
            \\
            },
        },
    },
    .{
        .name = "inline_subject_overlap",
        .command = "check",
        .expect_success = true,
        .diagnostic = "",
        .files = &.{
            .{ .name = "main.my", .body =
            \\constraint Id[P] = copy + op(identity(x: P) -> P effects())
            \\def forward[T: Id + op(identity(x: T) -> T effects())](x: T) -> T effects():
            \\    return T.identity(x)
            \\def main() -> int:
            \\    return 0
            \\
            },
        },
    },
    .{
        .name = "composite_subject_overlap",
        .command = "check",
        .expect_success = true,
        .diagnostic = "",
        .files = &.{
            .{ .name = "main.my", .body =
            \\constraint A[P] = copy + op(identity(x: list[P]) -> int effects())
            \\constraint B[Q] = copy + op(identity(x: list[Q]) -> int effects())
            \\def use[T: A + B](x: T) -> int:
            \\    return 0
            \\def main() -> int:
            \\    return 0
            \\
            },
        },
    },
    .{
        .name = "implied_copy_single",
        .command = "check",
        .expect_success = true,
        .diagnostic = "",
        .files = &.{
            .{ .name = "main.my", .body =
            \\def value[T: equality + field(value: int)](x: T) -> int:
            \\    return x.value
            \\def main() -> int:
            \\    return 0
            \\
            },
        },
    },
    .{
        .name = "implied_copy_module",
        .command = "check-project",
        .expect_success = true,
        .diagnostic = "",
        .files = &.{
            .{ .name = "main.my", .body =
            \\module main
            \\def value[T: equality + field(value: int)](x: T) -> int:
            \\    return x.value
            \\def main() -> int:
            \\    return 0
            \\
            },
        },
    },
    .{
        .name = "named_copy_plus_field",
        .command = "check-project",
        .expect_success = true,
        .diagnostic = "",
        .files = &.{
            .{ .name = "main.my", .body =
            \\module main
            \\constraint C[T] = copy
            \\def value[T: C + field(value: int)](x: T) -> int:
            \\    return x.value
            \\def main() -> int:
            \\    return 0
            \\
            },
        },
    },
    .{
        .name = "export_wrong_module_index",
        .command = "check-project",
        .expect_success = true,
        .diagnostic = "",
        .files = &.{
            .{ .name = "contracts.my", .body =
            \\module contracts
            \\export C
            \\record One:
            \\    a: int
            \\record Two:
            \\    a: int
            \\record Three:
            \\    a: int
            \\constraint C[T] = copy
            \\
            },
            .{ .name = "main.my", .body =
            \\module main
            \\import contracts
            \\export f
            \\def f[T: contracts.C](x: T) -> T:
            \\    return x
            \\def main() -> int:
            \\    return 0
            \\
            },
        },
    },
    .{
        .name = "export_false_private",
        .command = "check-project",
        .expect_success = true,
        .diagnostic = "",
        .files = &.{
            .{ .name = "contracts.my", .body =
            \\module contracts
            \\export C
            \\record One:
            \\    a: int
            \\constraint C[T] = copy
            \\
            },
            .{ .name = "main.my", .body =
            \\module main
            \\import contracts
            \\export f
            \\def f[T: contracts.C](x: T) -> T:
            \\    return x
            \\def main() -> int:
            \\    return 0
            \\
            },
        },
    },
    .{
        .name = "single_duplicate",
        .command = "check",
        .expect_success = false,
        .diagnostic = "E_DUPLICATE_SYMBOL",
        .files = &.{
            .{ .name = "main.my", .body =
            \\constraint C[T] = copy
            \\constraint C[T] = equality
            \\def main() -> int:
            \\    return 0
            \\
            },
        },
    },
    .{
        .name = "single_name_collision",
        .command = "check",
        .expect_success = false,
        .diagnostic = "E_DUPLICATE_SYMBOL",
        .files = &.{
            .{ .name = "main.my", .body =
            \\record C:
            \\    value: int
            \\constraint C[T] = copy
            \\def main() -> int:
            \\    return 0
            \\
            },
        },
    },
    .{
        .name = "overlap_limit_single",
        .command = "check",
        .expect_success = true,
        .diagnostic = "",
        .files = &.{
            .{ .name = "main.my", .body =
            \\constraint A[T] = copy + field(f0: int) + field(f1: int) + field(f2: int) + field(f3: int) + field(f4: int) + field(f5: int) + field(f6: int) + field(f7: int)
            \\constraint B[T] = copy + field(f0: int) + field(f1: int) + field(f2: int) + field(f3: int) + field(f4: int) + field(f5: int) + field(f6: int) + field(f7: int)
            \\def f[T: A + B](x: T) -> int:
            \\    return 0
            \\def main() -> int:
            \\    return 0
            \\
            },
        },
    },
    .{
        .name = "overlap_limit_module",
        .command = "check-project",
        .expect_success = true,
        .diagnostic = "",
        .files = &.{
            .{ .name = "main.my", .body =
            \\module main
            \\constraint A[T] = copy + field(f0: int) + field(f1: int) + field(f2: int) + field(f3: int) + field(f4: int) + field(f5: int) + field(f6: int) + field(f7: int)
            \\constraint B[T] = copy + field(f0: int) + field(f1: int) + field(f2: int) + field(f3: int) + field(f4: int) + field(f5: int) + field(f6: int) + field(f7: int)
            \\def f[T: A + B](x: T) -> int:
            \\    return 0
            \\def main() -> int:
            \\    return 0
            \\
            },
        },
    },
    .{
        .name = "unused_result_field",
        .command = "check",
        .expect_success = false,
        .diagnostic = "E_GENERIC_REQUIREMENT",
        .files = &.{
            .{ .name = "main.my", .body =
            \\constraint Bad[T] = copy + field(value: Result[int, int])
            \\def main() -> int:
            \\    return 0
            \\
            },
        },
    },
    .{
        .name = "used_result_field",
        .command = "check",
        .expect_success = false,
        .diagnostic = "E_GENERIC_REQUIREMENT",
        .files = &.{
            .{ .name = "main.my", .body =
            \\constraint Bad[T] = copy + field(value: Result[int, int])
            \\def bad[T: Bad](x: T) -> int:
            \\    return 0
            \\def main() -> int:
            \\    return 0
            \\
            },
        },
    },
    .{
        .name = "single_duplicate_used",
        .command = "check",
        .expect_success = false,
        .diagnostic = "E_DUPLICATE_SYMBOL",
        .files = &.{
            .{ .name = "main.my", .body =
            \\constraint C[T] = copy
            \\constraint C[T] = integer
            \\def identity[T: C](x: T) -> T:
            \\    return x
            \\def main() -> int:
            \\    assert identity(True)
            \\    return 0
            \\
            },
        },
    },
};
