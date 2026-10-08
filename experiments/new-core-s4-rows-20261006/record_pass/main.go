// Row `record_pass` (S4 CONTRACT.md): a twelve-field struct passed and returned by value.
package main

import (
	"fmt"
	"os"
	"strconv"
	"time"
)

const modulus int64 = 1000000007

type state struct {
	f0, f1, f2, f3, f4, f5, f6, f7, f8, f9, f10, f11 int64
}

func mix(a, b int64) int64 {
	return (a*31 + b) % 1009
}

func advance(s state, x int64) state {
	t := mix(s.f0+s.f5, x)
	f3 := s.f4
	if x%3 == 0 {
		f3 = mix(s.f4, x)
	}
	return state{s.f1, s.f2, s.f3, f3, s.f5, s.f6, s.f7, s.f8, s.f9, s.f10, s.f11, t}
}

func batchResult(size, batch, seed int64) int64 {
	base := seed + batch
	s := state{
		f0:  base % 1009,
		f1:  (base + 7) % 1009,
		f2:  (base + 14) % 1009,
		f3:  (base + 21) % 1009,
		f4:  (base + 28) % 1009,
		f5:  (base + 35) % 1009,
		f6:  (base + 42) % 1009,
		f7:  (base + 49) % 1009,
		f8:  (base + 56) % 1009,
		f9:  (base + 63) % 1009,
		f10: (base + 70) % 1009,
		f11: (base + 77) % 1009,
	}
	for j := int64(0); j < size; j++ {
		s = advance(s, (base+13*j)%1009)
	}
	return s.f0 + 2*s.f1 + 3*s.f2 + 4*s.f3 + 5*s.f4 + 6*s.f5 + 7*s.f6 + 8*s.f7 + 9*s.f8 +
		10*s.f9 + 11*s.f10 + 12*s.f11
}

func number(s string) int64 {
	n, err := strconv.ParseInt(s, 10, 64)
	if err != nil {
		os.Exit(2)
	}
	return n
}

func main() {
	if len(os.Args) != 5 || os.Args[1] != "record_pass" {
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
		checksum = (checksum + batchResult(size, batch, seed)) % modulus
	}
	elapsed := time.Since(start).Nanoseconds()
	fmt.Printf("%d %d\n", checksum, elapsed)
}
