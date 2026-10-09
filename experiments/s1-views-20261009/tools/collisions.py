#!/usr/bin/env python3
"""Equal-length ASCII key pairs with the same runtime span hash (`myl_core_span_hash`),
differing only inside one 4-octet window (start, middle or end): every probe of one
after inserting the other reaches the key compare, in a small table and in an indexed
one. Prints `L window A B` lines; `--check` verifies them against the C hash."""
import random, sys

M64 = (1 << 64) - 1
WK, SK, ST = 0xA0761D6478BD642F, 0xE7037ED1A0B428DB, 0x243F6A8885A308D3


def fold(a, b):
    p = (a & M64) * (b & M64)
    return (p ^ (p >> 64)) & M64


def span_hash(bs: bytes) -> int:
    n = len(bs)
    state = ST ^ n
    if n <= 8:
        low = high = 0
        if n >= 4:
            low = int.from_bytes(bs[0:4], "little"); high = int.from_bytes(bs[n - 4:n], "little")
        elif n:
            low = bs[0] << 16 | bs[n >> 1] << 8 | bs[n - 1]
        h = fold(low ^ WK, high ^ state ^ SK)
    else:
        at = 0
        while at + 8 < n:
            w = int.from_bytes(bs[at:at + 8], "little"); state = fold(w ^ WK, state ^ SK); at += 8
        w = int.from_bytes(bs[n - 8:n], "little")
        h = fold(w ^ WK, state ^ SK)
    return (h ^ (h >> 32)) & 0xFFFFFFFF


ALPHA = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-"


def search(length: int, window: str, rng: random.Random):
    width = min(4, length)
    start = {"start": 0, "middle": (length - width) // 2, "end": length - width}[window]
    base = bytearray(b"k" * length)
    seen = {}
    for _ in range(1 << 20):
        cand = bytearray(base)
        for i in range(width):
            cand[start + i] = ALPHA[rng.randrange(64)]
        key = bytes(cand)
        h = span_hash(key)
        other = seen.get(h)
        if other is not None and other != key:
            return other.decode(), key.decode()
        seen[h] = key
        if len(seen) >= 64 ** width:
            break
    return None


def main():
    rng = random.Random(20261009)
    for length in list(range(2, 21)):
        for window in ("start", "middle", "end"):
            if length <= 4 and window != "start":
                continue
            pair = search(length, window, rng)
            if pair:
                print(length, window, pair[0], pair[1])


if __name__ == "__main__":
    main()
