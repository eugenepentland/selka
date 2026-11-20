// Normal slices use the Go runtime allocator and normal garbage collection.
// Shared batches copy the entire slice and release its local reference in the kernel;
// physical reclamation follows the runtime's ordinary GC scheduling.
package main

import (
	"fmt"
	"os"
	"strconv"
	"time"
)

const modulus int64 = 1000000007

type record struct {
	code, bias int64
	payload    []int64
}

func readRecord(r *record) int64 { return r.code + r.bias + r.payload[0] }

type value struct {
	isBool  bool
	integer int64
	boolean bool
}

func number(s string) int64 {
	v, e := strconv.ParseInt(s, 10, 64)
	if e != nil {
		panic(e)
	}
	return v
}
func main() {
	if len(os.Args) != 5 {
		panic("expected CASE SIZE ITERATIONS SEED")
	}
	kind := os.Args[1]
	size := int(number(os.Args[2]))
	iterations := number(os.Args[3])
	seed := number(os.Args[4])
	if size < 2 || iterations < 1 || seed < 1 || seed > 1000000 {
		panic("invalid arguments")
	}
	var checksum int64
	var elapsed time.Duration
	switch kind {
	case "record_reads":
		records := make([]record, size)
		for j := range records {
			n := int64(j)
			records[j] = record{(seed + n*17) % 1009, (seed*3 + n*7) % 257, []int64{n + seed, n + seed + 1, n + seed + 2, n + seed + 3}}
		}
		index := int(seed % int64(size))
		start := time.Now()
		for i := int64(0); i < iterations; i++ {
			v := readRecord(&records[index])
			checksum = (checksum + v) % modulus
			index = (index + 2*int(seed) + 1) % size
		}
		elapsed = time.Since(start)
	case "tagged_stack":
		opcodes := make([]int64, size)
		for j := range opcodes {
			opcodes[j] = (int64(j) + seed) % 4
		}
		stack := []value{{integer: seed}, {isBool: true, boolean: false}}
		cursor := 0
		start := time.Now()
		for i := int64(0); i < iterations; i++ {
			popped := stack[len(stack)-1]
			stack = stack[:len(stack)-1]
			base := stack[0].integer
			op := opcodes[cursor]
			var delta int64
			if popped.isBool {
				switch op {
				case 0:
					delta = 1
					if popped.boolean {
						delta = 3
					}
				case 1:
					delta = 7
				case 2:
					delta = 11
				case 3:
					delta = 13
				}
			} else {
				switch op {
				case 0:
					delta = popped.integer % 5
				case 1:
					delta = popped.integer % 7
				case 2:
					delta = popped.integer % 11
				case 3:
					delta = popped.integer % 13
				}
			}
			next := (base + delta + op + 1) % 1000003
			stack[0] = value{integer: next}
			if op == 0 || op == 2 {
				stack = append(stack, value{isBool: true, boolean: next%2 == 0})
			} else {
				stack = append(stack, value{integer: next % 97})
			}
			cursor = (cursor + 1) % size
		}
		elapsed = time.Since(start)
		top := stack[1].integer
		if stack[1].isBool {
			top = 0
			if stack[1].boolean {
				top = 1
			}
		}
		checksum = stack[0].integer*101 + top
	case "mutate_unique", "mutate_shared":
		values := make([]int64, size)
		for j := range values {
			values[j] = (seed + int64(j)*13) % 1009
		}
		start := time.Now()
		for batch := int64(0); batch < iterations; batch++ {
			index := int((seed + batch*17) % int64(size))
			if kind == "mutate_shared" {
				snapshot := make([]int64, len(values))
				copy(snapshot, values)
				values[index] = (values[index] + batch + 1) % 1000003
				checksum = (checksum + snapshot[index] + values[index]) % modulus
				snapshot = nil
			} else {
				values[index] = (values[index] + batch + 1) % 1000003
				checksum = (checksum + values[index]) % modulus
			}
		}
		elapsed = time.Since(start)
		for _, v := range values {
			checksum = (checksum + v) % modulus
		}
	default:
		panic("unknown case")
	}
	fmt.Printf("%d %d\n", checksum, elapsed.Nanoseconds())
}
