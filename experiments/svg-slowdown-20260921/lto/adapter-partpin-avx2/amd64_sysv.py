"""AMD64 SysV shapes for the QBE aggregate subset emitted by mylang.

The frontend's aggregates are opaque, naturally aligned byte records.  QBE's
AMD64 ABI therefore classifies each complete eightbyte as INTEGER.  Values of at
most two eightbytes travel in registers; larger values use caller-owned memory.
"""

from dataclasses import dataclass


@dataclass(frozen=True)
class AggregateABI:
    size: int
    alignment: int
    storage: str
    value: str | None
    indirect: bool


def aggregate_abi(size, alignment=8, force_memory=False):
    """Return the LLVM storage and coerced SysV value shape for ``size`` bytes."""
    if size <= 0:
        raise ValueError("aggregate size must be positive")
    storage = f"[{size} x i8]"
    if size <= 8:
        value = f"i{size * 8}"
    elif size <= 16:
        tail = (size - 8) * 8
        value = "{ i64, i64 }" if tail == 64 else f"{{ i64, i{tail} }}"
    else:
        value = None
    return AggregateABI(size, alignment, storage, value,
                        force_memory or value is None)
