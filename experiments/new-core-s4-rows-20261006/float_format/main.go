package main

import (
	"fmt"
	"os"
	"strconv"
	"time"
)

const mod int64 = 1_000_000_007

// batchResult converts each value to a fresh shortest round-trip decimal text and folds its bytes.
func batchResult(size, batch, seed int64) int64 {
	var part int64
	for j := int64(0); j < size; j++ {
		k := (seed + batch + 13*j) % 100003
		x := float64(k) + 0.125*float64(1+j%7)
		text := strconv.FormatFloat(x, 'f', -1, 64)
		var h int64
		for i := 0; i < len(text); i++ {
			h = (h*131 + int64(text[i])) % mod
		}
		part = (part + h + int64(len(text))) % mod
	}
	return part
}

func main() {
	args := os.Args[1:]
	if len(args) != 4 || args[0] != "float_format" {
		os.Exit(2)
	}
	size, err1 := strconv.ParseInt(args[1], 10, 64)
	iterations, err2 := strconv.ParseInt(args[2], 10, 64)
	seed, err3 := strconv.ParseInt(args[3], 10, 64)
	if err1 != nil || err2 != nil || err3 != nil || size < 2 || iterations < 1 || seed < 1 || seed > 1000000 {
		os.Exit(2)
	}
	start := time.Now()
	var checksum int64
	for batch := int64(0); batch < iterations; batch++ {
		checksum = (checksum + batchResult(size, batch, seed)) % mod
	}
	elapsed := time.Since(start).Nanoseconds()
	fmt.Printf("%d %d\n", checksum, elapsed)
}
