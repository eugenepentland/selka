// Normal slices/maps and Go GC; nested snapshots explicitly copy every inner slice.
package main

import (
	"fmt"
	"os"
	"sort"
	"strconv"
	"time"
)

const modulus int64 = 1000000007

type value struct {
	boolean bool
	isBool  bool
	integer int64
}
type row struct{ key, ordinal, value int64 }
type instruction struct{ op, arg int }

var program = []instruction{{0, 0}, {4, 0}, {2, 0}, {4, 1}, {3, 1}, {1, 0}, {8, 0}, {10, 29}, {3, 1}, {2, 2}, {7, 0}, {2, 0}, {9, 0}, {10, 18}, {3, 0}, {12, 31}, {4, 0}, {11, 24}, {3, 0}, {3, 1}, {5, 0}, {2, 1000003}, {7, 0}, {4, 0}, {3, 1}, {2, 1}, {5, 0}, {4, 1}, {11, 4}, {3, 0}, {14, 0}, {2, 3}, {6, 0}, {2, 7}, {5, 0}, {2, 1000003}, {7, 0}, {13, 0}}

func integer(v value) int64 {
	if v.isBool {
		panic("expected integer")
	}
	return v.integer
}
func execute(code []instruction, size int, seed int64) int64 {
	stack := []value{}
	returns := []int{}
	vars := make([]int64, 2)
	pc := 0
	for {
		ins := code[pc]
		pc++
		switch ins.op {
		case 0:
			stack = append(stack, value{integer: seed})
		case 1:
			stack = append(stack, value{integer: int64(size)})
		case 2:
			stack = append(stack, value{integer: int64(ins.arg)})
		case 3:
			stack = append(stack, value{integer: vars[ins.arg]})
		case 4:
			vars[ins.arg] = integer(stack[len(stack)-1])
			stack = stack[:len(stack)-1]
		case 5, 6, 7, 8, 9:
			b := integer(stack[len(stack)-1])
			stack = stack[:len(stack)-1]
			a := integer(stack[len(stack)-1])
			stack = stack[:len(stack)-1]
			var next value
			switch ins.op {
			case 5:
				next.integer = a + b
			case 6:
				next.integer = a * b
			case 7:
				next.integer = a % b
			case 8:
				next = value{isBool: true, boolean: a < b}
			case 9:
				next = value{isBool: true, boolean: a == b}
			}
			stack = append(stack, next)
		case 10:
			v := stack[len(stack)-1]
			stack = stack[:len(stack)-1]
			if !v.isBool {
				panic("expected boolean")
			}
			if !v.boolean {
				pc = ins.arg
			}
		case 11:
			pc = ins.arg
		case 12:
			returns = append(returns, pc)
			pc = ins.arg
		case 13:
			pc = returns[len(returns)-1]
			returns = returns[:len(returns)-1]
		case 14:
			return integer(stack[len(stack)-1])
		default:
			panic("bad opcode")
		}
	}
}
func fold(xs []int64) int64 {
	var sum int64
	for j, v := range xs {
		sum += (int64(j) + 1) * v
	}
	return sum
}
func number(s string) int64 {
	n, e := strconv.ParseInt(s, 10, 64)
	if e != nil {
		panic(e)
	}
	return n
}
func main() {
	if len(os.Args) != 5 {
		panic("arguments")
	}
	kind := os.Args[1]
	size := int(number(os.Args[2]))
	iterations := number(os.Args[3])
	seed := number(os.Args[4])
	if size < 2 || iterations < 1 || seed < 1 || seed > 1000000 {
		panic("invalid arguments")
	}
	caseID := -1
	for id, name := range []string{"list_scan", "list_append", "list_filter", "dict_lookup", "dict_lookup_str", "dict_update", "dict_update_str", "set_dedup", "alloc_short", "alloc_retained", "mutate_nested", "sort_int", "sort_records", "lox_eval"} {
		if name == kind {
			caseID = id
		}
	}
	if caseID < 0 {
		panic("unknown case")
	}
	values := make([]int64, size)
	for j := range values {
		values[j] = (seed + int64(j)*13) % 1009
	}
	keyCount := 0
	if kind == "dict_lookup_str" || kind == "dict_update_str" {
		keyCount = size * 2
	}
	keys := make([]string, keyCount)
	for j := range keys {
		keys[j] = strconv.Itoa(j)
	}
	lookup := make(map[int]int64)
	lookupStr := make(map[string]int64)
	for j, v := range values {
		if kind == "dict_lookup" {
			lookup[j] = v
		}
		if kind == "dict_lookup_str" {
			lookupStr[keys[j]] = v
		}
	}
	nestedCount := 0
	if kind == "mutate_nested" {
		nestedCount = size
	}
	nested := make([][]int64, nestedCount)
	for j := range nested {
		nested[j] = make([]int64, 4)
		for k := range nested[j] {
			nested[j][k] = (seed + int64(j)*13 + int64(k)) % 1009
		}
	}
	var checksum int64
	start := time.Now()
	for batch := int64(0); batch < iterations; batch++ {
		var part int64
		switch caseID {
		case 0:
			for _, v := range values {
				part += (v + batch) % 1009
			}
		case 1:
			xs := []int64{}
			for j := 0; j < size; j++ {
				xs = append(xs, (seed+batch+int64(j)*13)%1009)
			}
			part = fold(xs)
		case 2:
			xs := make([]int64, size)
			for j := range xs {
				xs[j] = (seed + batch + int64(j)*13) % 1009
			}
			filtered := []int64{}
			for _, v := range xs {
				if v%3 == 0 {
					filtered = append(filtered, v)
				}
			}
			part = fold(filtered)
		case 3, 4:
			for j := 0; j < size; j++ {
				k := int((seed + int64(j)*17 + batch) % int64(size*2))
				var v int64
				var found bool
				if caseID == 3 {
					v, found = lookup[k]
				} else {
					v, found = lookupStr[keys[k]]
				}
				if !found {
					v = 17
				}
				part += v
			}
		case 5:
			m := make(map[int]int64)
			for j, v := range values {
				m[j] = v
			}
			for j := 0; j < size*2; j++ {
				k := int((seed + int64(j)*17 + batch) % int64(size*2))
				old, ok := m[k]
				if !ok {
					old = 17
				}
				m[k] = (old + int64(j) + batch + 1) % 1000003
			}
			for k, v := range m {
				part += int64(k) + v
			}
		case 6:
			m := make(map[string]int64)
			for j, v := range values {
				m[keys[j]] = v
			}
			for j := 0; j < size*2; j++ {
				k := int((seed + int64(j)*17 + batch) % int64(size*2))
				old, ok := m[keys[k]]
				if !ok {
					old = 17
				}
				m[keys[k]] = (old + int64(j) + batch + 1) % 1000003
			}
			for k, key := range keys {
				if v, ok := m[key]; ok {
					part += int64(k) + v
				}
			}
		case 7:
			m := make(map[int64]struct{})
			limit := size / 4
			if limit < 2 {
				limit = 2
			}
			for j := 0; j < size; j++ {
				m[(seed+batch+int64(j)*13)%int64(limit)] = struct{}{}
			}
			for k := range m {
				part += k
			}
		case 8:
			for j := 0; j < size; j++ {
				xs := make([]int64, 4)
				for k := range xs {
					xs[k] = seed + batch + int64(j) + int64(k)
				}
				for _, v := range xs {
					part += v
				}
			}
		case 9:
			lists := [][]int64{}
			for j := 0; j < size; j++ {
				xs := make([]int64, 4)
				for k := range xs {
					xs[k] = seed + batch + int64(j) + int64(k)
				}
				lists = append(lists, xs)
			}
			for _, xs := range lists {
				for _, v := range xs {
					part += v
				}
			}
		case 10:
			snapshot := make([][]int64, len(nested))
			for j, xs := range nested {
				snapshot[j] = make([]int64, len(xs))
				copy(snapshot[j], xs)
			}
			index := int((seed + batch*17) % int64(size))
			nested[index][1] = (nested[index][1] + batch + 1) % 1000003
			part = snapshot[index][1] + nested[index][1]
			snapshot = nil
		case 11:
			xs := make([]int64, size)
			for j := range xs {
				xs[j] = (seed + batch + int64(j)*13) % 1009
			}
			sort.Slice(xs, func(i, j int) bool { return xs[i] < xs[j] })
			part = fold(xs)
		case 12:
			rows := make([]row, size)
			for j := range rows {
				v := (seed + batch + int64(j)*13) % 1009
				rows[j] = row{v % 17, int64(j), v}
			}
			sort.SliceStable(rows, func(i, j int) bool { return rows[i].key < rows[j].key })
			for j, r := range rows {
				part += (int64(j) + 1) * (r.value*17 + r.ordinal)
			}
		case 13:
			part = execute(program, size, seed+batch)
		default:
			panic("unknown case")
		}
		checksum = (checksum + part) % modulus
	}
	elapsed := time.Since(start).Nanoseconds()
	if kind == "mutate_nested" {
		for _, xs := range nested {
			for _, v := range xs {
				checksum = (checksum + v) % modulus
			}
		}
	}
	fmt.Printf("%d %d\n", checksum, elapsed)
}
