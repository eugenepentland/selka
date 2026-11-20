#!/usr/bin/env python3
"""CPython oracle for the four K4 kernels (SUITE.md sections 12-15).

Writes `<name>.expected` for each kernel named on the command line (all four by
default) into `--out` (default: this directory). The ports must match these bytes.
The oracle follows the SUITE.md text, not any port: it builds the JSON tree in
the generator, walks and serializes that tree, and checks that the serialized
text equals the generated text. Hashing uses hashlib and zlib, which the main
ports do not, so the SHA-256 and CRC32 ports are checked against independent code.

Usage: python3 k4_oracle.py [--out DIR] [json_roundtrip netlist_union_find hash_bytes dict_churn]
"""
import argparse
import hashlib
import os
import zlib

MOD = 1000000007
MASK = (1 << 64) - 1
ALPHA = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
LOWER = "abcdefghijklmnopqrstuvwxyz"
SEED = 88172645463325252


class Gen:
    """The shared xorshift generator: `full()` is the state, `draw()` is state >> 33."""

    def __init__(self):
        self.x = SEED

    def full(self):
        x = self.x
        x ^= (x << 13) & MASK
        x ^= x >> 7
        x ^= (x << 17) & MASK
        self.x = x
        return x

    def draw(self):
        return self.full() >> 33

    def pick(self, n):
        return self.draw() % n


def mix(c, v):
    return (c * 31 + v) % MOD


# ---------------------------------------------------------------- 15 dict_churn


def dict_churn():
    lines = []
    g = Gen()

    def phases(tag, keys, miss, key_measure):
        m = {}
        K = len(keys)
        for i, k in enumerate(keys):
            m[k] = i
        lines.append(f"{tag} insert {K}")
        hits = sum(m[k] for k in keys)
        misses = sum(1 for k in miss if k not in m)
        lines.append(f"{tag} lookup hits_sum {hits} misses {misses}")
        removed = 0
        for i in range(0, K, 3):
            if keys[i] in m:
                del m[keys[i]]
                removed += 1
        lines.append(f"{tag} delete removed {removed} size {len(m)}")
        reinserted = 0
        for i in range(0, K, 6):
            m[keys[i]] = 2 * i
            reinserted += 1
        lines.append(f"{tag} reinsert reinserted {reinserted} size {len(m)}")
        value_sum = sum(m.values())
        measure = sum(key_measure(k) for k in m)
        if tag == "str":
            lines.append(f"str iterate size {len(m)} value_sum {value_sum} key_len_sum {measure}")
        else:
            lines.append(f"int iterate size {len(m)} value_sum {value_sum} key_sum {measure}")

    k_str = 800000
    keys = [f"n{g.draw()}_{i}" for i in range(k_str)]
    miss = [f"n{g.draw()}_{i}" for i in range(k_str)]
    phases("str", keys, miss, len)
    k_int = 2000000
    keys = [g.full() for _ in range(k_int)]
    miss = [g.full() for _ in range(k_int)]
    phases("int", keys, miss, lambda k: k >> 33)
    return "\n".join(lines) + "\n"


# ------------------------------------------------------- 14 hash_bytes


def hash_bytes():
    n = 67108864
    x = SEED
    data = bytearray(n)
    for i in range(n):
        x ^= (x << 13) & MASK
        x ^= x >> 7
        x ^= (x << 17) & MASK
        data[i] = (x >> 33) & 255
    abc = hashlib.sha256(b"abc").hexdigest()
    sha = hashlib.sha256(bytes(data)).hexdigest()
    crc = zlib.crc32(bytes(data)) & 0xFFFFFFFF
    return f"sha256 abc {abc}\nsha256 {sha}\ncrc32 {crc}\n"


# ------------------------------------------------------- 13 netlist_union_find


def netlist_union_find():
    g = Gen()
    pins = 1000000
    conns = 1000000
    ca = [0] * conns
    cb = [0] * conns
    for e in range(conns):
        ca[e] = g.pick(pins)
        cb[e] = g.pick(pins)
    parent = list(range(pins))
    size = [1] * pins

    def find(x):
        while parent[x] != x:
            parent[x] = parent[parent[x]]
            x = parent[x]
        return x

    for e in range(conns):
        ra = find(ca[e])
        rb = find(cb[e])
        if ra == rb:
            continue
        if size[ra] < size[rb]:
            ra, rb = rb, ra
        parent[rb] = ra
        size[ra] = size[ra] + size[rb]
    roots = [x for x in range(pins) if parent[x] == x]
    nets = len(roots)
    largest = max(size[x] for x in roots)
    roots_mix = 0
    for x in roots:
        roots_mix = mix(roots_mix, size[x])
    deg = [0] * pins
    for e in range(conns):
        deg[ca[e]] += 1
        deg[cb[e]] += 1
    offset = [0] * (pins + 1)
    for x in range(pins):
        offset[x + 1] = offset[x] + deg[x]
    cursor = offset[:pins]
    adj = [0] * (2 * conns)
    for e in range(conns):
        a = ca[e]
        b = cb[e]
        adj[cursor[a]] = b
        cursor[a] += 1
        adj[cursor[b]] = a
        cursor[b] += 1
    sources = [g.pick(pins) for _ in range(16)]
    lines = [f"pins {pins} connections {conns} nets {nets} largest {largest} roots_mix {roots_mix}"]
    dmix = 0
    queue = [0] * pins
    for s in sources:
        dist = [-1] * pins
        dist[s] = 0
        queue[0] = s
        head = 0
        tail = 1
        while head < tail:
            u = queue[head]
            head += 1
            du = dist[u] + 1
            for idx in range(offset[u], offset[u + 1]):
                v = adj[idx]
                if dist[v] < 0:
                    dist[v] = du
                    queue[tail] = v
                    tail += 1
        depth = max(dist)
        lines.append(f"source {s} reached {tail} depth {depth}")
        for x in range(pins):
            dmix = mix(dmix, dist[x] + 1)
    lines.append(f"distances_mix {dmix}")
    return "\n".join(lines) + "\n"


# ------------------------------------------------------- 12 json_roundtrip


def gen_decimal(g, out):
    mag = g.pick(2000000)
    sign = g.pick(2)
    negative = sign == 1 and mag > 0
    text = ("-" if negative else "") + str(mag // 1000) + "." + ("%03d" % (mag % 1000))
    out.append(text)
    value = float(text)
    scaled = (-mag) if negative else mag
    return ("dec", scaled, value)


def gen_record(g, d, out):
    out.append('{"id":')
    ident = g.draw()
    out.append(str(ident))
    length = 4 + g.pick(12)
    out.append(',"name":"')
    chars = []
    for _ in range(length):
        r = g.pick(16)
        if r == 0:
            out.append('\\"')
            chars.append('"')
        elif r == 1:
            out.append("\\\\")
            chars.append("\\")
        elif r == 2:
            out.append("\\n")
            chars.append("\n")
        else:
            c = ALPHA[g.pick(62)]
            out.append(c)
            chars.append(c)
    name = "".join(chars)
    out.append('"')
    out.append(',"pos":[')
    first = gen_decimal(g, out)
    out.append(",")
    second = gen_decimal(g, out)
    out.append("]")
    out.append(',"tags":[')
    tag_count = g.pick(5)
    tags = []
    for t in range(tag_count):
        if t:
            out.append(",")
        letters = 1 + g.pick(4)
        out.append('"')
        word = []
        for _ in range(letters):
            c = LOWER[g.pick(26)]
            out.append(c)
            word.append(c)
        out.append('"')
        tags.append(("str", "".join(word)))
    out.append("]")
    out.append(',"child":')
    if d < 3:
        c = g.pick(3)
        if c != 0:
            child = gen_record(g, d + 1, out)
        else:
            out.append("null")
            child = ("null",)
    else:
        out.append("null")
        child = ("null",)
    out.append("}")
    members = [
        ("id", ("int", ident)),
        ("name", ("str", name)),
        ("pos", ("arr", [first, second])),
        ("tags", ("arr", tags)),
        ("child", child),
    ]
    return ("obj", members)


def walk(node, st):
    kind = node[0]
    if kind == "null":
        st[0] = mix(st[0], 1)
    elif kind == "int":
        st[0] = mix(st[0], 4)
        st[0] = mix(st[0], node[1])
    elif kind == "dec":
        st[0] = mix(st[0], 5)
        st[0] = mix(st[0], abs(int(node[2] * 1e9)))
    elif kind == "str":
        st[0] = mix(st[0], 6)
        st[0] = mix(st[0], len(node[1]))
    elif kind == "arr":
        st[0] = mix(st[0], 7)
        st[0] = mix(st[0], len(node[1]))
        for item in node[1]:
            walk(item, st)
    elif kind == "obj":
        st[0] = mix(st[0], 8)
        st[0] = mix(st[0], len(node[1]))
        for key, value in node[1]:
            st[0] = mix(st[0], len(key))
            walk(value, st)


def escape(text):
    return text.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n")


def serialize(node, out):
    kind = node[0]
    if kind == "null":
        out.append("null")
    elif kind == "int":
        out.append(str(node[1]))
    elif kind == "dec":
        scaled = node[1]
        mag = abs(scaled)
        out.append(("-" if scaled < 0 else "") + str(mag // 1000) + "." + ("%03d" % (mag % 1000)))
    elif kind == "str":
        out.append('"' + escape(node[1]) + '"')
    elif kind == "arr":
        out.append("[")
        for i, item in enumerate(node[1]):
            if i:
                out.append(",")
            serialize(item, out)
        out.append("]")
    elif kind == "obj":
        out.append("{")
        for i, (key, value) in enumerate(node[1]):
            if i:
                out.append(",")
            out.append('"' + key + '":')
            serialize(value, out)
        out.append("}")


def json_roundtrip():
    records = 120000
    g = Gen()
    out = ["["]
    tree = []
    for r in range(records):
        if r:
            out.append(",")
        tree.append(gen_record(g, 0, out))
    out.append("]")
    text = "".join(out)
    top = ("arr", tree)
    st = [0]
    walk(top, st)
    pieces = []
    serialize(top, pieces)
    serialized = "".join(pieces)
    mixed = 0
    for byte in serialized.encode("ascii"):
        mixed = mix(mixed, byte)
    status = "roundtrip ok" if serialized == text else "roundtrip mismatch"
    return (
        f"records {records} text {len(text)} walk {st[0]}\n"
        f"serialized {len(serialized)} mix {mixed}\n"
        f"{status}\n"
    )


KERNELS = {
    "json_roundtrip": json_roundtrip,
    "netlist_union_find": netlist_union_find,
    "hash_bytes": hash_bytes,
    "dict_churn": dict_churn,
}


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--out", default=here)
    parser.add_argument("kernels", nargs="*", default=list(KERNELS))
    args = parser.parse_args()
    for name in args.kernels:
        text = KERNELS[name]()
        path = os.path.join(args.out, name + ".expected")
        with open(path, "w", encoding="ascii", newline="\n") as handle:
            handle.write(text)
        print(f"{path}: {len(text)} bytes")


if __name__ == "__main__":
    main()
