"""Independent Python oracle for float_format: Python's repr(float) is the expected text."""
from functools import lru_cache

MOD = 1000000007


@lru_cache(maxsize=None)
def text_score(k, m):
    """(h + len(text)) for x = k + 0.125 * m, where h folds the bytes of repr(x)."""
    x = k + 0.125 * m
    text = repr(x)
    assert "e" not in text and "." in text, text
    h = 0
    for c in text.encode("ascii"):
        h = (h * 131 + c) % MOD
    return h + len(text)


def checksum(size, iterations, seed):
    total = 0
    for batch in range(iterations):
        part = 0
        for j in range(size):
            k = (seed + batch + 13 * j) % 100003
            part = (part + text_score(k, 1 + j % 7)) % MOD
        total = (total + part) % MOD
    return total
