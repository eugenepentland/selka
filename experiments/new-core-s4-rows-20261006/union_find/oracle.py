"""Independent Python oracle for the union_find row (CONTRACT.md, section union_find)."""

MOD = 1_000_000_007


def part(size, seed, batch):
    parent = list(range(size))

    def find(x):
        while parent[x] != x:
            parent[x] = parent[parent[x]]
            x = parent[x]
        return x

    for j in range(size):
        a = (seed + batch + 13 * j) % size
        b = (seed + 7 * batch + 17 * j + 1) % size
        ra = find(a)
        rb = find(b)
        if ra != rb:
            parent[ra] = rb
    components = sum(1 for j in range(size) if find(j) == j)
    rootsum = sum(find(j) for j in range(size))
    return (components * 1000003 + rootsum) % MOD


def checksum(size, iterations, seed):
    total = 0
    for batch in range(iterations):
        total = (total + part(size, seed, batch)) % MOD
    return total
