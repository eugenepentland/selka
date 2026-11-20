package main

import (
	"encoding/json"
	"fmt"
	"os"
	"strconv"
	"strings"
	"time"
	"unicode/utf8"
)

const modulus int64 = 1000000007

// Inputs are prepared before timing; all result construction stays in operation.
type inputs struct {
	raw          []byte
	texts, other []string
	numbers      []int64
	fragments    []string
}

func score(text string) int64 {
	result := int64(len(text))
	for j := 0; j < len(text); j++ {
		result += int64(text[j])
	}
	return result
}
func name(j int) string {
	prefix := "naïve,item"
	if j%2 == 0 {
		prefix = "café,\"item\""
	}
	return prefix + strconv.Itoa(j)
}
func fixtures(kind string, size int, seed int64) inputs {
	d := inputs{}
	switch kind {
	case "bytes_scan":
		d.raw = make([]byte, size)
		for j := range d.raw {
			d.raw[j] = byte((seed + int64(j)*37) % 256)
		}
	case "string_equal":
		d.texts = []string{strings.Repeat("a", size), strings.Repeat("é", size), strings.Repeat("a", size), "café" + strconv.FormatInt(seed, 10)}
		d.other = []string{strings.Repeat("a", size), strings.Repeat("é", size-1) + "ê", "b" + strings.Repeat("a", size-1), "café" + strconv.FormatInt(seed, 10)}
	case "string_search":
		d.texts = []string{strings.Repeat("a", size) + ";café;needle;" + strconv.FormatInt(seed, 10)}
		d.other = []string{"a", "needle", "absentΩ", "é"}
	case "string_split", "string_join":
		options := []string{"", "alpha", "café", "x", "naïve"}
		d.fragments = make([]string, size)
		for j := range d.fragments {
			d.fragments[j] = options[(int(seed)+j)%5]
		}
		d.texts = []string{strings.Join(d.fragments, "|"), strings.Join(d.fragments, "::")}
	case "int_parse":
		d.texts = make([]string, size)
		for j := range d.texts {
			n := (seed + int64(j)*137) % 1000003
			text := strconv.FormatInt(n, 10)
			switch j % 6 {
			case 1:
				text = "-" + text
			case 2:
				text = "00" + text
			case 3:
				text += "x"
			case 4:
				text = "oops"
			case 5:
				text = ""
			}
			d.texts[j] = text
		}
	case "int_format":
		d.numbers = make([]int64, size)
		for j := range d.numbers {
			n := (seed + int64(j)*137) % 1000003
			if j%3 == 0 {
				n = -n
			}
			d.numbers[j] = n
		}
	case "word_count":
		vocabulary := []string{"red", "blue", "café", "red", "green", "blue", "naïve", "red"}
		separators := []string{" ", "\t", "\n", "  "}
		chunks := make([]string, size)
		for j := range chunks {
			chunks[j] = vocabulary[(int(seed)+j)%8] + separators[j%4]
		}
		document := strings.Join(chunks, "")
		d.texts = []string{document + "red", document + "blue"}
	case "csv_aggregate":
		regions := []string{"east", "west", "north"}
		chunks := make([]string, size)
		for j := range chunks {
			amount := "oops"
			if j%11 != 0 {
				amount = strconv.FormatInt((seed+int64(j)*19)%100003, 10)
			}
			active := "0"
			if (int(seed)+j)%3 != 0 {
				active = "1"
			}
			chunks[j] = strconv.FormatInt(seed+int64(j), 10) + ",\"" + strings.ReplaceAll(name(j), "\"", "\"\"") + "\"," + regions[(int(seed)+j)%3] + "," + amount + "," + active + "\n"
		}
		d.texts = []string{strings.Join(chunks, "")}
	case "json_transform":
		rows := make([]map[string]any, size)
		for j := range rows {
			rows[j] = map[string]any{"id": seed + int64(j), "name": name(j), "amount": (seed + int64(j)*19) % 100003, "active": (int(seed)+j)%3 != 0}
		}
		encoded, err := json.Marshal(rows)
		if err != nil {
			panic(err)
		}
		d.texts = []string{string(encoded)}
	default:
		panic("unknown case")
	}
	return d
}

// Equivalent documented quote-aware CSV subset, with UTF-8 bytes preserved.
func csvRows(text string) [][]string {
	rows := [][]string{}
	fields := []string{}
	var field strings.Builder
	quoted := false
	for index := 0; index < len(text); index++ {
		ch := text[index]
		if quoted {
			if ch == '"' {
				if index+1 < len(text) && text[index+1] == '"' {
					field.WriteByte('"')
					index++
				} else {
					quoted = false
				}
			} else {
				field.WriteByte(ch)
			}
		} else {
			switch ch {
			case '"':
				quoted = true
			case ',':
				fields = append(fields, field.String())
				field.Reset()
			case '\n':
				fields = append(fields, field.String())
				rows = append(rows, fields)
				fields = []string{}
				field.Reset()
			default:
				field.WriteByte(ch)
			}
		}
	}
	if quoted || field.Len() != 0 || len(fields) != 0 {
		panic("malformed CSV fixture")
	}
	return rows
}
func wordJob(text string) int64 {
	counts := map[string]int64{}
	for _, word := range strings.Fields(text) {
		counts[word]++
	}
	result := int64(0)
	for word, count := range counts {
		result += score(word) * count * count
	}
	return result
}
func csvJob(text string) int64 {
	groups := map[string]int64{"east": 0, "west": 0, "north": 0}
	accepted, rejected, names := int64(0), int64(0), int64(0)
	for _, row := range csvRows(text) {
		amount, err := strconv.ParseInt(row[3], 10, 64)
		if err != nil {
			rejected++
			continue
		}
		if row[4] == "1" {
			groups[row[2]] += amount
			accepted++
			names += score(row[1])
		}
	}
	return groups["east"] + groups["west"]*2 + groups["north"]*3 + accepted*17 + rejected*101 + names
}
func jsonJob(text string, bump int64) int64 {
	var rows []map[string]any
	if err := json.Unmarshal([]byte(text), &rows); err != nil {
		panic(err)
	}
	output := []map[string]any{}
	for _, row := range rows {
		if row["active"].(bool) {
			output = append(output, map[string]any{"id": int64(row["id"].(float64)), "name": row["name"], "amount": int64(row["amount"].(float64)) + bump})
		}
	}
	encoded, err := json.Marshal(output)
	if err != nil {
		panic(err)
	}
	return score(string(encoded))
}

func bytesJob(raw []byte, mask byte) int64 {
	total := int64(0)
	for _, value := range raw {
		total += int64(value ^ mask)
	}
	return total
}
func searchJob(text, needle string) int64 {
	pos := strings.Index(text, needle)
	if pos < 0 {
		return 0
	}
	return int64(utf8.RuneCountInString(text[:pos]) + 1)
}
func splitJob(text, separator string) int64 {
	parts := strings.Split(text, separator)
	result := int64(len(parts) * 7)
	for _, part := range parts {
		result += score(part)
	}
	return result
}
func separator(cursor int) string {
	if cursor%2 == 0 {
		return "|"
	}
	return "::"
}
func parseJob(text string) int64 {
	n, err := strconv.ParseInt(text, 10, 64)
	if err != nil {
		return 97
	}
	return n
}
func kernel(kind string, d *inputs, iterations, seed int) int64 {
	checksum := int64(0)
	switch kind {
	case "bytes_scan":
		for step := 0; step < iterations; step++ {
			cursor := seed + step
			value := bytesJob(d.raw, byte(cursor%256))
			checksum = (checksum + value) % modulus
			if checksum < 0 {
				checksum += modulus
			}
		}
	case "string_equal":
		for step := 0; step < iterations; step++ {
			cursor := seed + step
			value := int64(0)
			if d.texts[cursor%4] == d.other[cursor%4] {
				value = 1
			}
			checksum = (checksum + value) % modulus
			if checksum < 0 {
				checksum += modulus
			}
		}
	case "string_search":
		for step := 0; step < iterations; step++ {
			cursor := seed + step
			value := searchJob(d.texts[0], d.other[cursor%4])
			checksum = (checksum + value) % modulus
			if checksum < 0 {
				checksum += modulus
			}
		}
	case "string_split":
		for step := 0; step < iterations; step++ {
			cursor := seed + step
			value := splitJob(d.texts[cursor%2], separator(cursor))
			checksum = (checksum + value) % modulus
			if checksum < 0 {
				checksum += modulus
			}
		}
	case "string_join":
		for step := 0; step < iterations; step++ {
			cursor := seed + step
			value := score(strings.Join(d.fragments, separator(cursor)))
			checksum = (checksum + value) % modulus
			if checksum < 0 {
				checksum += modulus
			}
		}
	case "int_parse":
		for step := 0; step < iterations; step++ {
			cursor := seed + step
			value := parseJob(d.texts[cursor%len(d.texts)])
			checksum = (checksum + value) % modulus
			if checksum < 0 {
				checksum += modulus
			}
		}
	case "int_format":
		for step := 0; step < iterations; step++ {
			cursor := seed + step
			value := score(strconv.FormatInt(d.numbers[cursor%len(d.numbers)], 10))
			checksum = (checksum + value) % modulus
			if checksum < 0 {
				checksum += modulus
			}
		}
	case "word_count":
		for step := 0; step < iterations; step++ {
			cursor := seed + step
			value := wordJob(d.texts[cursor%2])
			checksum = (checksum + value) % modulus
			if checksum < 0 {
				checksum += modulus
			}
		}
	case "csv_aggregate":
		for step := 0; step < iterations; step++ {
			value := csvJob(d.texts[0])
			checksum = (checksum + value) % modulus
			if checksum < 0 {
				checksum += modulus
			}
		}
	case "json_transform":
		for step := 0; step < iterations; step++ {
			cursor := seed + step
			value := jsonJob(d.texts[0], int64(cursor%17))
			checksum = (checksum + value) % modulus
			if checksum < 0 {
				checksum += modulus
			}
		}
	default:
		panic("unknown case")
	}
	return checksum
}

func main() {
	args := os.Args[1:]
	if len(args) != 4 {
		os.Exit(2)
	}
	valid := false
	for _, kind := range []string{"bytes_scan", "string_equal", "string_search", "string_split", "string_join", "int_parse", "int_format", "word_count", "csv_aggregate", "json_transform"} {
		if args[0] == kind {
			valid = true
		}
	}
	if !valid {
		os.Exit(2)
	}
	size, e1 := strconv.Atoi(args[1])
	iterations, e2 := strconv.Atoi(args[2])
	seed, e3 := strconv.ParseInt(args[3], 10, 64)
	if e1 != nil || e2 != nil || e3 != nil || size < 2 || iterations < 1 || seed < 1 || seed > 1000000 {
		os.Exit(2)
	}
	d := fixtures(args[0], size, seed)
	checksum := int64(0)
	start := time.Now()
	checksum = kernel(args[0], &d, iterations, int(seed))
	elapsed := time.Since(start).Nanoseconds()
	fmt.Printf("%d %d\n", checksum, elapsed)
}
