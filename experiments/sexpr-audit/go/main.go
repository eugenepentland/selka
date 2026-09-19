// Benchmark driver for the Go S-expression reader.
//
// It mirrors `zig-bench` (experiments/sexpr-port/zig-bench/main.zig) exactly:
// the same six workloads, the same stdout lines, and the same tokenizer/parser/
// printer semantics as sexpr-core, so its output digests are directly
// comparable with the Zig, mylang and Python columns.
//
//	go-sexpr <input.sexp> [--loop|--scan|--tokens|--parse|--render]
//
// Float text follows Zig's `{d}`: shortest round-trip digits in positional
// notation, which Go calls strconv.FormatFloat(v, 'f', -1, 64).
package main

import (
	"bytes"
	"fmt"
	"math"
	"os"
	"strconv"
	"strings"
)

const (
	kLParen uint8 = iota
	kRParen
	kAtom
	kString
	kInt
	kFloat
	kUnit
	kSI
	kEOF
)

const (
	nForm uint8 = iota
	nAtom
	nString
	nInt
	nDec
	nMeasure
)

const (
	shortListMaxWidth  = 72
	fallbackIntWidth   = 12
	fallbackFloatWidth = 12
	fallbackUnitWidth  = 14
	maxParseDepth      = 10000
	milToMM            = 0.0254
)

type token struct {
	kind uint8
	text []byte
	off  int
}

type node struct {
	tag   uint8
	items []node
	text  string
	ival  int64
	fval  float64
	lit   string
}

var (
	isSpace     [256]bool
	isDigit     [256]bool
	isAtomStart [256]bool
	isAtomCont  [256]bool
	isOp        [256]bool
	isUnit      [256]bool
	isScale     [256]bool
)

func init() {
	for _, b := range []byte{' ', '\n', '\r', '\t'} {
		isSpace[b] = true
	}
	for b := byte('0'); b <= '9'; b++ {
		isDigit[b] = true
	}
	for b := byte('a'); b <= 'z'; b++ {
		isAtomStart[b] = true
	}
	for b := byte('A'); b <= 'Z'; b++ {
		isAtomStart[b] = true
	}
	for _, b := range []byte{'_', '~', '*'} {
		isAtomStart[b] = true
	}
	isAtomCont = isAtomStart
	for b := 0; b < 256; b++ {
		if isDigit[byte(b)] {
			isAtomCont[byte(b)] = true
		}
	}
	for _, b := range []byte{'-', '/', '.', '#', '@', ':', '+', ',', '$'} {
		isAtomCont[b] = true
	}
	for _, b := range []byte{'+', '-', '/', '%', '>', '<', '=', '!'} {
		isOp[b] = true
	}
	for _, b := range []byte{'V', 'A', 'F', 'H', 'R'} {
		isUnit[b] = true
	}
	for _, b := range []byte{'k', 'M', 'G', 'u', 'n', 'p'} {
		isScale[b] = true
	}
}

func fail(message string) {
	fmt.Fprintln(os.Stderr, message)
	os.Exit(1)
}

// siSuffixLen is the length (0/1/2) of an SI value suffix at p.
func siSuffixLen(src []byte, p int) int {
	n := len(src)
	if p >= n {
		return 0
	}
	c0 := src[p]
	if isScale[c0] {
		if p+1 >= n || !isAtomCont[src[p+1]] {
			return 1
		}
		if isUnit[src[p+1]] && (p+2 >= n || !isAtomCont[src[p+2]]) {
			return 2
		}
		return 0
	}
	if c0 == 'm' {
		if p+1 < n && isUnit[src[p+1]] && (p+2 >= n || !isAtomCont[src[p+2]]) {
			return 2
		}
		return 0
	}
	if isUnit[c0] && (p+1 >= n || !isAtomCont[src[p+1]]) {
		return 1
	}
	return 0
}

// readNumber classifies the numeric token at start; it returns the kind, where
// scanning resumes, and where the token's text ends (a mm/mil measure's text
// stops before the suffix, exactly as tokenizer.my does).
func readNumber(src []byte, start int) (uint8, int, int) {
	n := len(src)
	p := start
	if src[p] == '-' {
		p++
	}
	for p < n && isDigit[src[p]] {
		p++
	}
	isFloat := false
	if p+1 < n && src[p] == '.' && isDigit[src[p+1]] {
		isFloat = true
		p++
		for p < n && isDigit[src[p]] {
			p++
		}
	}
	numEnd := p
	if p < n && src[p] == 'm' {
		if p+1 < n && src[p+1] == 'm' && (p+2 >= n || !isAtomCont[src[p+2]]) {
			return kUnit, p + 2, numEnd
		}
		if p+2 < n && src[p+1] == 'i' && src[p+2] == 'l' && (p+3 >= n || !isAtomCont[src[p+3]]) {
			return kUnit, p + 3, numEnd
		}
	}
	if suffix := siSuffixLen(src, p); suffix > 0 {
		return kSI, p + suffix, p + suffix
	}
	if p < n && src[p] == '%' && (p+1 >= n || !isAtomCont[src[p+1]]) {
		return kSI, p + 1, p + 1
	}
	if p < n && isAtomCont[src[p]] {
		for p < n && isAtomCont[src[p]] {
			p++
		}
		return kAtom, p, p
	}
	if isFloat {
		return kFloat, p, p
	}
	return kInt, p, p
}

// tokenize lexes src. With collect it returns the token list ending in kEOF and
// the count is unused; without it returns only the non-EOF token count, matching
// zig-bench's streaming --tokens phase. The count is the second result.
func tokenize(src []byte, collect bool) ([]token, int) {
	n := len(src)
	pos := 0
	var tokens []token
	count := 0
	for {
		for pos < n {
			b := src[pos]
			if isSpace[b] {
				pos++
				continue
			}
			if b == ';' {
				pos++
				for pos < n && src[pos] != '\n' {
					pos++
				}
				continue
			}
			break
		}
		if pos >= n {
			if collect {
				tokens = append(tokens, token{kind: kEOF, off: pos})
			}
			return tokens, count
		}
		start := pos
		b := src[pos]
		switch {
		case b == '(':
			pos++
			if collect {
				tokens = append(tokens, token{kind: kLParen, text: src[start:pos], off: start})
			}
			count++
		case b == ')':
			pos++
			if collect {
				tokens = append(tokens, token{kind: kRParen, text: src[start:pos], off: start})
			}
			count++
		case b == '"':
			pos++
			textStart := pos
			closed := false
			for pos < n {
				c := src[pos]
				if c == '\\' {
					pos += 2
				} else if c == '"' {
					closed = true
					break
				} else {
					pos++
				}
			}
			if !closed {
				fail("unterminated string")
			}
			if collect {
				tokens = append(tokens, token{kind: kString, text: src[textStart:pos], off: start})
			}
			count++
			pos++
		case isDigit[b] || (b == '-' && pos+1 < n && isDigit[src[pos+1]]):
			kind, end, textEnd := readNumber(src, start)
			if collect {
				tokens = append(tokens, token{kind: kind, text: src[start:textEnd], off: start})
			}
			count++
			pos = end
		case isAtomStart[b]:
			pos++
			for pos < n && isAtomCont[src[pos]] {
				pos++
			}
			if collect {
				tokens = append(tokens, token{kind: kAtom, text: src[start:pos], off: start})
			}
			count++
		case isOp[b]:
			pos++
			if pos < n && src[pos] == '=' {
				pos++
			}
			if collect {
				tokens = append(tokens, token{kind: kAtom, text: src[start:pos], off: start})
			}
			count++
		default:
			fail("unexpected character")
		}
	}
}

// ── parser ────────────────────────────────────────────────────────────

type parser struct {
	src    []byte
	tokens []token
	pos    int
}

func (p *parser) parseAll() []node {
	var nodes []node
	for p.tokens[p.pos].kind != kEOF {
		nodes = append(nodes, p.parseNode(0))
	}
	return nodes
}

func (p *parser) parseNode(depth int) node {
	t := p.tokens[p.pos]
	p.pos++
	switch t.kind {
	case kAtom:
		return node{tag: nAtom, text: string(t.text)}
	case kString:
		return node{tag: nString, text: string(t.text)}
	case kInt:
		value, err := strconv.ParseInt(string(t.text), 10, 64)
		if err != nil {
			fail("invalid number literal")
		}
		return node{tag: nInt, ival: value}
	case kFloat:
		value, err := strconv.ParseFloat(string(t.text), 64)
		if err != nil {
			fail("invalid number literal")
		}
		return node{tag: nDec, fval: value}
	case kUnit:
		return parseUnit(p.src, t)
	case kSI:
		return parseSI(t)
	case kLParen:
		return p.parseList(depth)
	default:
		fail("unexpected ')' — no matching '(' is open here")
	}
	return node{}
}

func (p *parser) parseList(depth int) node {
	if depth >= maxParseDepth {
		fail("s-expression nesting is too deep")
	}
	var items []node
	for {
		kind := p.tokens[p.pos].kind
		if kind == kEOF {
			fail("unexpected end of input — a '(' was never closed")
		}
		if kind == kRParen {
			p.pos++
			break
		}
		items = append(items, p.parseNode(depth+1))
	}
	return node{tag: nForm, items: items}
}

func parseUnit(src []byte, t token) node {
	text := t.text
	numberText := text
	isMil := false
	if bytes.HasSuffix(text, []byte("mil")) {
		numberText = text[:len(text)-3]
		isMil = true
	} else if bytes.HasSuffix(text, []byte("mm")) {
		numberText = text[:len(text)-2]
	} else {
		after := t.off + len(text)
		if after+3 <= len(src) && src[after] == 'm' && src[after+1] == 'i' && src[after+2] == 'l' {
			isMil = true
		}
	}
	value, err := strconv.ParseFloat(string(numberText), 64)
	if err != nil {
		fail("invalid number literal")
	}
	if isMil {
		value *= milToMM
	}
	return node{tag: nMeasure, fval: value}
}

func parseSI(t token) node {
	text := t.text
	end := 0
	for end < len(text) {
		c := text[end]
		if (c >= '0' && c <= '9') || c == '.' || (c == '-' && end == 0) {
			end++
		} else {
			break
		}
	}
	if end == 0 || end == len(text) {
		fail("invalid number literal")
	}
	value, err := strconv.ParseFloat(string(text[:end]), 64)
	if err != nil {
		fail("invalid number literal")
	}
	switch text[end] {
	case 'k':
		value *= 1e3
	case 'M':
		value *= 1e6
	case 'G':
		value *= 1e9
	case 'm':
		value *= 1e-3
	case 'u':
		value *= 1e-6
	case 'n':
		value *= 1e-9
	case 'p':
		value *= 1e-12
	}
	return node{tag: nDec, fval: value, lit: string(text)}
}

// ── float text (Zig `{d}`) ────────────────────────────────────────────

// zigDecimal is Zig's `{d}` for f64: shortest round-trip digits, positional.
func zigDecimal(value float64) string {
	if math.IsNaN(value) {
		return "nan"
	}
	if math.IsInf(value, 1) {
		return "inf"
	}
	if math.IsInf(value, -1) {
		return "-inf"
	}
	return strconv.FormatFloat(value, 'f', -1, 64)
}

// strFloat is mylang's str(float): the Zig spelling with ".0" forced on a whole
// value. nan/inf are returned bare, as native_format.zig does before appending.
func strFloat(value float64) string {
	text := zigDecimal(value)
	if math.IsNaN(value) || math.IsInf(value, 0) {
		return text
	}
	if !strings.ContainsAny(text, ".eE") {
		return text + ".0"
	}
	return text
}

// ── census ────────────────────────────────────────────────────────────

type censusCounts struct {
	forms    int
	nodes    int
	atoms    int
	strings  int
	ints     int
	floats   int
	measures int
	depth    int
	values   float64
}

func tally(c *censusCounts, n node, depth int) {
	c.nodes++
	if depth > c.depth {
		c.depth = depth
	}
	switch n.tag {
	case nForm:
		c.forms++
		for i := range n.items {
			tally(c, n.items[i], depth+1)
		}
	case nAtom:
		c.atoms++
	case nString:
		c.strings++
	case nInt:
		c.ints++
		c.values += float64(n.ival)
	case nDec:
		c.floats++
		c.values += n.fval
	default:
		c.measures++
		c.values += n.fval
	}
}

func censusLine(nodes []node) string {
	var counts censusCounts
	for i := range nodes {
		tally(&counts, nodes[i], 0)
	}
	return fmt.Sprintf("forms=%d nodes=%d atoms=%d strings=%d ints=%d floats=%d measures=%d max_depth=%d value_sum=%s",
		counts.forms, counts.nodes, counts.atoms, counts.strings, counts.ints,
		counts.floats, counts.measures, counts.depth, zigDecimal(counts.values))
}

// ── printer ───────────────────────────────────────────────────────────

// estimateWidth returns the one-line width and whether it is known; past four
// levels of nesting the measure is unknown (Zig's estimateWidth).
func estimateWidth(n node, depth int) (int, bool) {
	if depth > 3 {
		return 0, false
	}
	switch n.tag {
	case nForm:
		total := 2
		for i := range n.items {
			if i > 0 {
				total++
			}
			width, known := estimateWidth(n.items[i], depth+1)
			if !known {
				return 0, false
			}
			total += width
		}
		return total, true
	case nAtom:
		return len(n.text), true
	case nString:
		return len(n.text) + 2, true
	case nInt:
		text := strconv.FormatInt(n.ival, 10)
		if text == "" {
			return fallbackIntWidth, true
		}
		return len(text), true
	case nDec:
		if n.lit != "" {
			return len(n.lit), true
		}
		text := strFloat(n.fval)
		text = strings.TrimSuffix(text, ".0")
		if text == "" {
			return fallbackFloatWidth, true
		}
		return len(text), true
	default:
		text := strFloat(n.fval)
		text = strings.TrimSuffix(text, ".0")
		if text == "" {
			return fallbackUnitWidth + 2, true
		}
		return len(text) + 2, true
	}
}

func isShortList(items []node) bool {
	total := 2
	for i := range items {
		if i > 0 {
			total++
		}
		width, known := estimateWidth(items[i], 0)
		if !known {
			return false
		}
		total += width
		if total > shortListMaxWidth {
			return false
		}
	}
	return true
}

func pushNode(dst []byte, n node, indent int) []byte {
	switch n.tag {
	case nForm:
		if len(n.items) == 0 {
			return append(dst, '(', ')')
		}
		if isShortList(n.items) {
			dst = append(dst, '(')
			for i := range n.items {
				if i > 0 {
					dst = append(dst, ' ')
				}
				dst = pushNode(dst, n.items[i], indent+2)
			}
			return append(dst, ')')
		}
		dst = append(dst, '(')
		dst = pushNode(dst, n.items[0], indent+2)
		for i := 1; i < len(n.items); i++ {
			dst = append(dst, '\n')
			for k := 0; k < indent+2; k++ {
				dst = append(dst, ' ')
			}
			dst = pushNode(dst, n.items[i], indent+2)
		}
		return append(dst, ')')
	case nAtom:
		return append(dst, n.text...)
	case nString:
		dst = append(dst, '"')
		dst = append(dst, n.text...)
		return append(dst, '"')
	case nInt:
		return strconv.AppendInt(dst, n.ival, 10)
	case nDec:
		if n.lit != "" {
			return append(dst, n.lit...)
		}
		return append(dst, strFloat(n.fval)...)
	default:
		dst = append(dst, strFloat(n.fval)...)
		return append(dst, 'm', 'm')
	}
}

func render(nodes []node) []byte {
	var dst []byte
	for i := range nodes {
		if i > 0 {
			dst = append(dst, '\n')
		}
		dst = pushNode(dst, nodes[i], 0)
	}
	return dst
}

// ── driver ────────────────────────────────────────────────────────────

func main() {
	args := os.Args[1:]
	if len(args) < 1 {
		fmt.Fprintln(os.Stderr, "usage: go-sexpr <input.sexp> [--loop|--scan|--tokens|--parse|--render]")
		os.Exit(2)
	}
	mode := ""
	if len(args) > 1 {
		mode = args[1]
	}
	src, err := os.ReadFile(args[0])
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(2)
	}

	switch mode {
	case "--loop":
		index := 0
		for index < len(src) {
			index++
		}
		fmt.Printf("bytes=%d index=%d\n", len(src), index)
		return
	case "--scan":
		count := 0
		for _, b := range src {
			if b == '(' || b == ')' {
				count++
			}
		}
		fmt.Printf("bytes=%d delims=%d\n", len(src), count)
		return
	case "--tokens":
		_, count := tokenize(src, false)
		fmt.Printf("tokens=%d\n", count)
		return
	}

	tokens, _ := tokenize(src, true)
	p := &parser{src: src, tokens: tokens}
	nodes := p.parseAll()
	switch mode {
	case "--parse":
		fmt.Printf("roots=%d\n", len(nodes))
	case "--render":
		out := render(nodes)
		out = append(out, '\n')
		os.Stdout.Write(out)
	default:
		fmt.Println(censusLine(nodes))
	}
}
