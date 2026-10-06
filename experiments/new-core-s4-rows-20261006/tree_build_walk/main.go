// Row `tree_build_walk` (S4 CONTRACT.md): pointer nodes with nil for Leaf; the garbage collector
// releases each batch's tree (GOMAXPROCS=1).
package main

import (
	"fmt"
	"os"
	"strconv"
	"time"
)

const modulus int64 = 1000000007

type node struct {
	left  *node
	value int64
	right *node
}

func build(lo, hi, base int64) *node {
	if lo >= hi {
		return nil
	}
	mid := (lo + hi) / 2
	return &node{build(lo, mid, base), (base + 13*mid) % 1009, build(mid+1, hi, base)}
}

func walk(t *node, depth int64) int64 {
	if t == nil {
		return 0
	}
	return (depth+1)*t.value + walk(t.left, depth+1) + walk(t.right, depth+1)
}

func number(s string) int64 {
	n, err := strconv.ParseInt(s, 10, 64)
	if err != nil {
		os.Exit(2)
	}
	return n
}

func main() {
	if len(os.Args) != 5 || os.Args[1] != "tree_build_walk" {
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
		part := walk(build(0, size, seed+batch), 0) % modulus
		checksum = (checksum + part) % modulus
	}
	elapsed := time.Since(start).Nanoseconds()
	fmt.Printf("%d %d\n", checksum, elapsed)
}
