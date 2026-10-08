"""Independent Python spec of the tree_build_walk row (CONTRACT.md): nested tuples as the tree.

part(batch) depends on the batch only through base = seed + batch, and base enters build() only as
`base % 1009` (every node value is `(base + 13*mid) % 1009`), so each distinct residue is built and
walked once and reused. That is a cache over the literal contract formula, not a different formula.
"""
import sys

MOD = 1_000_000_007


def build(lo, hi, base):
    if lo >= hi:
        return None
    mid = (lo + hi) // 2
    return (build(lo, mid, base), (base + 13 * mid) % 1009, build(mid + 1, hi, base))


def walk(tree, depth):
    if tree is None:
        return 0
    left, value, right = tree
    return (depth + 1) * value + walk(left, depth + 1) + walk(right, depth + 1)


def checksum(size, iterations, seed):
    sys.setrecursionlimit(10000)
    part_by_residue = {}
    total = 0
    for batch in range(iterations):
        residue = (seed + batch) % 1009
        if residue not in part_by_residue:
            part_by_residue[residue] = walk(build(0, size, residue), 0) % MOD
        total = (total + part_by_residue[residue]) % MOD
    return total
