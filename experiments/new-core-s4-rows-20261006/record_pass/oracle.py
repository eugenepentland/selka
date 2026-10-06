"""Independent Python spec of the record_pass row (CONTRACT.md): the state as a list of twelve ints.

part(batch) depends on the batch only through base = seed + batch mod 1009 (every initial field and
every x is `(base + c) % 1009`), so each residue is run once and reused: a cache over the literal
contract formula, not a different formula.
"""

MOD = 1_000_000_007


def mix(a, b):
    return (a * 31 + b) % 1009


def advance(s, x):
    t = mix(s[0] + s[5], x)
    f3 = mix(s[4], x) if x % 3 == 0 else s[4]
    return [s[1], s[2], s[3], f3, s[5], s[6], s[7], s[8], s[9], s[10], s[11], t]


def part(size, base):
    s = [(base + 7 * k) % 1009 for k in range(12)]
    for j in range(size):
        s = advance(s, (base + 13 * j) % 1009)
    return sum((k + 1) * s[k] for k in range(12))


def checksum(size, iterations, seed):
    part_by_residue = {}
    total = 0
    for batch in range(iterations):
        residue = (seed + batch) % 1009
        if residue not in part_by_residue:
            part_by_residue[residue] = part(size, residue)
        total = (total + part_by_residue[residue]) % MOD
    return total
