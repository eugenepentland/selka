"""Independent Python oracle for the grid_dp row (CONTRACT.md, section grid_dp)."""
from math import isqrt

MOD = 1_000_000_007


def part(width, height, seed, batch):
    cost = [[(seed + batch + 13 * (i * width + j)) % 1009 for j in range(width)] for i in range(height)]
    dp = [[0] * width for _ in range(height)]
    for i in range(height):
        for j in range(width):
            if i == 0 and j == 0:
                dp[i][j] = cost[i][j]
            elif i == 0:
                dp[i][j] = dp[i][j - 1] + cost[i][j]
            elif j == 0:
                dp[i][j] = dp[i - 1][j] + cost[i][j]
            else:
                dp[i][j] = cost[i][j] + min(dp[i - 1][j], dp[i][j - 1])
    return dp[height - 1][width - 1] + sum(dp[height - 1])


def checksum(size, iterations, seed):
    width = isqrt(size)
    height = size // width
    total = 0
    for batch in range(iterations):
        total = (total + part(width, height, seed, batch)) % MOD
    return total
