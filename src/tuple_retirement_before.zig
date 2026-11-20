//! Immutable original diagnostic inputs; migration tools must not rewrite them.

pub const original_record_lambda =
    \\record Entry:
    \\    rank: int
    \\    id: int
    \\
    \\
    \\func main() -> int:
    \\    mut xs = [Entry(rank=1, id=0)]
    \\    xs.sort(key=lambda e: e)
    \\    return 0
    \\
;

pub const original_record_named =
    \\record Entry:
    \\    rank: int
    \\    id: int
    \\
    \\
    \\func whole(e: Entry) -> Entry:
    \\    return e
    \\
    \\
    \\func main() -> int:
    \\    mut xs = [Entry(rank=1, id=0)]
    \\    xs.sort(key=whole)
    \\    return 0
    \\
;
