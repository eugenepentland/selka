package main

import (
	"fmt"
	"os"
	"strconv"
	"time"
)

const mod int64 = 1_000_000_007

// batchResult appends the decimal digits of size values to a fresh byte slice, then folds it.
func batchResult(size, batch, seed int64) int64 {
	var buf []byte
	for j := int64(0); j < size; j++ {
		v := (seed + batch + 13*j) % 100003
		buf = strconv.AppendInt(buf, v, 10)
		buf = append(buf, ',')
		if j%16 == 15 {
			buf = append(buf, '\n')
		}
	}
	var h int64
	for _, c := range buf {
		h = (h*131 + int64(c)) % mod
	}
	return (int64(len(buf)) + h) % mod
}

func main() {
	args := os.Args[1:]
	if len(args) != 4 || args[0] != "buffer_write" {
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
