package main

import (
	"errors"
	"fmt"
	"os"
	"strconv"
	"time"
)

const modulus int64 = 1000000007

type triple struct{ a, b, c int64 }
type packet struct{ identifier, payloadSum, length int64 }
type option struct {
	present bool
	value   int64
}
type packetResult struct {
	ok    bool
	value packet
	err   int64
}

func affineA(x int64) int64 { return x*3 + 7 }
func affineB(x int64) int64 { return x*5 + 11 }
func score(r triple) int64  { return r.a + r.b*3 + r.c*5 }
func optional(x, p int64) option {
	if x%4 == 0 {
		return option{}
	}
	return option{true, x + p}
}

var invalid = errors.New("invalid scalar")

func checked(x, p int64) (int64, error) {
	if x%5 == 0 {
		return 0, invalid
	}
	return x + p, nil
}
func forwarded(x, p int64) (int64, error) {
	v, err := checked(x, p)
	if err != nil {
		return 0, err
	}
	return v*3 + 1, nil
}
func search(xs []int64, key int64) int64 {
	lo, hi := 0, len(xs)
	for lo < hi {
		mid := (lo + hi) / 2
		if xs[mid] < key {
			lo = mid + 1
		} else {
			hi = mid
		}
	}
	if lo < len(xs) && xs[lo] == key {
		return int64(lo) + 1
	}
	return 0
}
func frame(j, seed int64) []byte {
	id := (seed + j*17) % 65536
	raw := []byte{165, 1, byte(id / 256), byte(id % 256), 4}
	for k := int64(0); k < 4; k++ {
		raw = append(raw, byte((seed+j*13+k*7)%256))
	}
	var check int64
	for _, b := range raw {
		check += int64(b)
	}
	raw = append(raw, byte(check%256))
	switch j % 4 {
	case 1:
		raw[0] = 164
	case 2:
		raw[9]++
	case 3:
		raw[4] = 5
	}
	return raw
}
func decode(raw []byte) packetResult {
	if len(raw) < 6 {
		return packetResult{err: 3}
	}
	if raw[0] != 165 {
		return packetResult{err: 1}
	}
	if raw[1] != 1 {
		return packetResult{err: 2}
	}
	length := int(raw[4])
	if len(raw) != length+6 {
		return packetResult{err: 3}
	}
	var check int64
	for _, b := range raw[:len(raw)-1] {
		check += int64(b)
	}
	if check%256 != int64(raw[len(raw)-1]) {
		return packetResult{err: 4}
	}
	var total int64
	for _, b := range raw[5 : len(raw)-1] {
		total += int64(b)
	}
	return packetResult{ok: true, value: packet{int64(raw[2])*256 + int64(raw[3]), total, int64(length)}}
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
		panic("arguments")
	}
	names := []string{"integer_math", "float_math", "branch_predictable", "branch_mixed", "record_construct", "record_update", "call_direct", "call_indirect", "option_handle", "result_propagate", "binary_search", "packet_decode"}
	kind := -1
	for i, name := range names {
		if name == os.Args[1] {
			kind = i
		}
	}
	if kind < 0 {
		panic("case")
	}
	size := int(number(os.Args[2]))
	iterations := number(os.Args[3])
	seed := number(os.Args[4])
	if size < 2 || iterations < 1 || seed < 1 || seed > 1000000 {
		panic("arguments")
	}
	values := make([]int64, size)
	ordered := make([]int64, size)
	flags := make([]bool, size)
	records := make([]triple, size)
	frames := make([][]byte, size)
	for j := range values {
		x := (seed + int64(j)*37) % 1009
		values[j] = x
		ordered[j] = int64(j)*3 + seed%11
		if kind == 2 {
			flags[j] = j%16 != 0
		} else {
			flags[j] = (x*73+int64(j)*19+seed)%101 < 50
		}
		records[j] = triple{x, x % 17, x * 3 % 101}
		frames[j] = frame(int64(j), seed)
	}
	function := affineA
	if seed%2 != 0 {
		function = affineB
	}
	var checksum int64
	start := time.Now()
	for batch := int64(0); batch < iterations; batch++ {
		phase := batch % 17
		var passTotal int64
		for j, x := range values {
			var value int64
			switch kind {
			case 0:
				value = ((x+phase)*17 + 23) / 7 % 1009
			case 1:
				value = int64(((float64(x)/8+float64(phase)/4)*(float64(x)/16+1) + 0.5) * 128)
			case 2, 3:
				if flags[j] {
					value = (x+phase)*3 + 1
				} else {
					value = (x+phase)*5 + 7
				}
			case 4:
				value = score(triple{x + phase, x % 17, (x*3 + phase) % 101})
			case 5:
				r := records[j]
				r.a = x + phase
				r.b = x % 17
				r.c = (x*3 + phase) % 101
				value = score(r)
			case 6:
				value = affineA(x + phase)
			case 7:
				value = function(x + phase)
			case 8:
				r := optional(x, phase)
				if r.present {
					value = r.value*3 + 1
				} else {
					value = 19
				}
			case 9:
				v, err := forwarded(x, phase)
				if err == nil {
					value = v
				} else {
					value = 7
				}
			case 10:
				value = search(ordered, (x+phase)%(int64(size)*3+3)+seed%11)
			case 11:
				r := decode(frames[j])
				if r.ok {
					value = r.value.identifier + r.value.payloadSum*3 + r.value.length
				} else {
					value = r.err * 101
				}
			}
			passTotal += value
		}
		checksum = (checksum + passTotal) % modulus
	}
	elapsed := time.Since(start)
	fmt.Printf("%d %d\n", checksum, elapsed.Nanoseconds())
}
