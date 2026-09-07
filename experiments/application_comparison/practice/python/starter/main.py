"""Execute the byte-oriented preparation utility."""

import sys

from helper import multiply_by_six

NINE = 9
INPUT_LIMIT = 256


def parse_digit(data: bytes) -> int:
    if len(data) != 1 or not ord("0") <= data[0] <= ord("9"):
        raise ValueError("expected exactly one ASCII digit")
    return data[0] - ord("0")


def evaluate(data: bytes) -> int:
    if len(data) > INPUT_LIMIT:
        return -1
    if data == b"m":
        return multiply_by_six(6)
    if data.startswith(b"f"):
        try:
            return parse_digit(data[1:])
        except ValueError:
            return 0
    if data == b"d":
        return NINE_VALUE
    return -1


def main() -> None:
    data = sys.stdin.buffer.read(INPUT_LIMIT + 1)
    sys.stdout.write(f"{evaluate(data)}\n")


if __name__ == "__main__":
    main()
