// Row `union_find` (CONTRACT.md): union by linking roots, path halving that mutates `parent`.
// One `[]int` per batch left to the collector; `find` writes through the slice; std only.
package main

import (
	"fmt"
	"os"
	"runtime"
	"strconv"
	"time"
)

const modulus int64 = 1000000007

func find(parent []int, x int) int {
	for parent[x] != x {
		parent[x] = parent[parent[x]]
		x = parent[x]
	}
	return x
}

func batchResult(size int, batch, seed int64) int64 {
	n := int64(size)
	parent := make([]int, size)
	for j := range parent {
		parent[j] = j
	}
	for j := int64(0); j < n; j++ {
		a := int((seed + batch + 13*j) % n)
		b := int((seed + 7*batch + 17*j + 1) % n)
		ra := find(parent, a)
		rb := find(parent, b)
		if ra != rb {
			parent[ra] = rb
		}
	}
	var components, rootsum int64
	for j := 0; j < size; j++ {
		if find(parent, j) == j {
			components++
		}
	}
	for j := 0; j < size; j++ {
		rootsum += int64(find(parent, j))
	}
	return (components*1000003 + rootsum) % modulus
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
	if len(os.Args) != 5 || os.Args[1] != "union_find" {
		os.Exit(2)
	}
	size := number(os.Args[2])
	iterations := number(os.Args[3])
	seed := number(os.Args[4])
	if size < 2 || iterations < 1 || seed < 1 || seed > 1000000 {
		os.Exit(2)
	}
	var checksum int64
	start := time.Now()
	for batch := int64(0); batch < iterations; batch++ {
		checksum = (checksum + batchResult(int(size), batch, seed)) % modulus
	}
	elapsed := time.Since(start).Nanoseconds()
	fmt.Printf("%d %d\n", checksum, elapsed)
}
