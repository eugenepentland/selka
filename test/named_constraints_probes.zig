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
            .{ .name = "a.selka", .body =
            \\public record ID:
            \\    value: int
            \\public constraint Has[T] = copy + field(value: ID)
            \\
            },
            .{ .name = "b.selka", .body =
            \\public record ID:
            \\    value: int
            \\public constraint Has[T] = copy + field(value: ID)
            \\
            },
            .{ .name = "main.selka", .body =
            \\import a
            \\import b
            \\record Row:
            \\    value: a.ID
            \\func accept[T: a.Has + b.Has](row: T) -> int:
            \\    return 0
            \\func main() -> int:
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
            .{ .name = "a.selka", .body =
            \\public record ID:
            \\    value: int
            \\public constraint Has[T] = copy + field(value: ID)
            \\
            },
            .{ .name = "b.selka", .body =
            \\public record ID:
            \\    value: int
            \\public constraint Has[T] = copy + field(value: ID)
            \\
            },
            .{ .name = "main.selka", .body =
            \\import a
            \\import b
            \\record Row:
            \\    value: a.ID
            \\func accept[T: b.Has + a.Has](row: T) -> int:
            \\    return 0
            \\func main() -> int:
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
            .{ .name = "contracts.selka", .body =
            \\public record Token:
            \\    value: int
            \\public constraint Use[S] = copy + op(use(s: S, token: Token) -> int effects())
            \\
            },
            .{ .name = "main.selka", .body =
            \\import contracts
            \\domain Provider: int:
            \\    func make() -> Provider:
            \\        return wrap[Provider](0)
            \\    func use(s: Provider, token: int) -> int effects():
            \\        return token
            \\func call[Token, P: contracts.Use](p: P, token: Token) -> int effects():
            \\    return P.use(p, token)
            \\func main() -> int:
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
            .{ .name = "contracts.selka", .body =
            \\public record Token:
            \\    value: int
            \\public constraint Use[S] = copy + op(use(s: S, token: Token) -> int effects())
            \\
            },
            .{ .name = "main.selka", .body =
            \\import contracts
            \\domain Provider: int:
            \\    func make() -> Provider:
            \\        return wrap[Provider](0)
            \\    func use(s: Provider, token: int) -> int effects():
            \\        return token
            \\func call[U, P: contracts.Use](p: P, token: U) -> int effects():
            \\    return P.use(p, token)
            \\func main() -> int:
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
            .{ .name = "main.selka", .body =
            \\constraint Id[P] = copy + op(identity(x: P) -> P effects())
            \\func forward[T: Id + op(identity(x: T) -> T effects())](x: T) -> T effects():
            \\    return T.identity(x)
            \\func main() -> int:
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
            .{ .name = "main.selka", .body =
            \\constraint A[P] = copy + op(identity(x: P[]) -> int effects())
            \\constraint B[Q] = copy + op(identity(x: Q[]) -> int effects())
            \\func use[T: A + B](x: T) -> int:
            \\    return 0
            \\func main() -> int:
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
            .{ .name = "main.selka", .body =
            \\func value[T: equality + field(value: int)](x: T) -> int:
            \\    return x.value
            \\func main() -> int:
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
            .{ .name = "main.selka", .body =
            \\func value[T: equality + field(value: int)](x: T) -> int:
            \\    return x.value
            \\func main() -> int:
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
            .{ .name = "main.selka", .body =
            \\constraint C[T] = copy
            \\func value[T: C + field(value: int)](x: T) -> int:
            \\    return x.value
            \\func main() -> int:
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
            .{ .name = "contracts.selka", .body =
            \\record One:
            \\    a: int
            \\record Two:
            \\    a: int
            \\record Three:
            \\    a: int
            \\public constraint C[T] = copy
            \\
            },
            .{ .name = "main.selka", .body =
            \\import contracts
            \\public func f[T: contracts.C](x: T) -> T effects():
            \\    return x
            \\func main() -> int:
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
            .{ .name = "contracts.selka", .body =
            \\record One:
            \\    a: int
            \\public constraint C[T] = copy
            \\
            },
            .{ .name = "main.selka", .body =
            \\import contracts
            \\public func f[T: contracts.C](x: T) -> T effects():
            \\    return x
            \\func main() -> int:
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
            .{ .name = "main.selka", .body =
            \\constraint C[T] = copy
            \\constraint C[T] = equality
            \\func main() -> int:
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
            .{ .name = "main.selka", .body =
            \\record C:
            \\    value: int
            \\constraint C[T] = copy
            \\func main() -> int:
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
            .{ .name = "main.selka", .body =
            \\constraint A[T] = copy + field(f0: int) + field(f1: int) + field(f2: int) + field(f3: int) + field(f4: int) + field(f5: int) + field(f6: int) + field(f7: int)
            \\constraint B[T] = copy + field(f0: int) + field(f1: int) + field(f2: int) + field(f3: int) + field(f4: int) + field(f5: int) + field(f6: int) + field(f7: int)
            \\func f[T: A + B](x: T) -> int:
            \\    return 0
            \\func main() -> int:
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
            .{ .name = "main.selka", .body =
            \\constraint A[T] = copy + field(f0: int) + field(f1: int) + field(f2: int) + field(f3: int) + field(f4: int) + field(f5: int) + field(f6: int) + field(f7: int)
            \\constraint B[T] = copy + field(f0: int) + field(f1: int) + field(f2: int) + field(f3: int) + field(f4: int) + field(f5: int) + field(f6: int) + field(f7: int)
            \\func f[T: A + B](x: T) -> int:
            \\    return 0
            \\func main() -> int:
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
            .{ .name = "main.selka", .body =
            \\constraint Bad[T] = copy + field(value: Result[int, int])
            \\func main() -> int:
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
            .{ .name = "main.selka", .body =
            \\constraint Bad[T] = copy + field(value: Result[int, int])
            \\func bad[T: Bad](x: T) -> int:
            \\    return 0
            \\func main() -> int:
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
            .{ .name = "main.selka", .body =
            \\constraint C[T] = copy
            \\constraint C[T] = integer
            \\func identity[T: C](x: T) -> T:
            \\    return x
            \\func main() -> int:
            \\    assert identity(True)
            \\    return 0
            \\
            },
        },
    },
};
