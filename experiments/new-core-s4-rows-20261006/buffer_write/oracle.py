"""Independent Python oracle for buffer_write: build the bytes, then hash them."""

MOD = 1000000007


def checksum(size, iterations, seed):
    total = 0
    for batch in range(iterations):
        buffer = bytearray()
        for j in range(size):
            v = (seed + batch + 13 * j) % 100003
            buffer += str(v).encode("ascii")
            buffer += b","
            if j % 16 == 15:
                buffer += b"\n"
        h = 0
        for c in buffer:
            h = (h * 131 + c) % MOD
        total = (total + (len(buffer) + h) % MOD) % MOD
    return total
