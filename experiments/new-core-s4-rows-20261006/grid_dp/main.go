// Row `grid_dp` (CONTRACT.md): a minimum-cost path DP over two nested dynamic grids.
// `[][]int64` for both grids, built row by row and left to the collector inside every batch; std only.
package main

import (
	"fmt"
	"os"
	"runtime"
	"strconv"
	"time"
)

const modulus int64 = 1000000007

// isqrt returns the largest w with w*w <= n, the same integer loop in every language.
func isqrt(n int) int {
	w := 0
	for (w+1)*(w+1) <= n {
		w++
	}
	return w
}

func batchResult(w, h int, batch, seed int64) int64 {
	cost := make([][]int64, h)
	for i := range cost {
		row := make([]int64, w)
		for j := range row {
			row[j] = (seed + batch + 13*int64(i*w+j)) % 1009
		}
		cost[i] = row
	}
	dp := make([][]int64, h)
	for i := range dp {
		dp[i] = make([]int64, w)
	}
	dp[0][0] = cost[0][0]
	for j := 1; j < w; j++ {
		dp[0][j] = dp[0][j-1] + cost[0][j]
	}
	for i := 1; i < h; i++ {
		dp[i][0] = dp[i-1][0] + cost[i][0]
		for j := 1; j < w; j++ {
			dp[i][j] = cost[i][j] + min(dp[i-1][j], dp[i][j-1])
		}
	}
	part := dp[h-1][w-1]
	for _, v := range dp[h-1] {
		part += v
	}
	return part
}

func number(text string) int64 {
	n, err := strconv.ParseInt(text, 10, 64)
	if err != nil {
		os.Exit(2)
	}
	return n
}

func main() {
	runtime.GOMAXPROCS(1)
	if len(os.Args) != 5 || os.Args[1] != "grid_dp" {
		os.Exit(2)
	}
	size := number(os.Args[2])
	iterations := number(os.Args[3])
	seed := number(os.Args[4])
	if size < 2 || iterations < 1 || seed < 1 || seed > 1000000 {
		os.Exit(2)
	}
	w := isqrt(int(size))
	h := int(size) / w
	var checksum int64
	start := time.Now()
	for batch := int64(0); batch < iterations; batch++ {
		checksum = (checksum + batchResult(w, h, batch, seed)) % modulus
	}
	elapsed := time.Since(start).Nanoseconds()
	fmt.Printf("%d %d\n", checksum, elapsed)
}
