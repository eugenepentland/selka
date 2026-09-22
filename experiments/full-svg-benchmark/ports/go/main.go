// Command go-fast is the Go arm of the full-svg benchmark: a single-file,
// standard-library-only implementation of the mylang schematic-to-SVG pipeline.
//
// It is a faithful transcription of ports/rust/main.rs (itself a transcription
// of src/schematic/guest/*.my), performing the same parse, validation, model
// construction, net normalization, placement, routing and SVG serialization, in
// the same order, with the same integer arithmetic, so its output is
// byte-identical to the mylang arm. The only intended structural difference is
// that each host document is read whole into memory once instead of streamed
// through the io.byte/io.put host calls.
//
// Usage: go-fast <module.sexp> <pinout.sexp> <interface.sexp> <output.svg>
package main

import "os"

// ── spans and documents ──────────────────────────────────────────────

type Span struct {
	file  int
	start int
	end   int
}

var emptySpan = Span{file: 0, start: 0, end: 0}

func (s Span) length() int { return s.end - s.start }

func (s Span) isEmpty() bool { return s.end == s.start }

type Ctx struct {
	docs [][]byte
}

func (c *Ctx) byteAt(file int, position int) byte { return c.docs[file][position] }

// text.equal
func (c *Ctx) equal(a Span, b Span) bool {
	if a.length() != b.length() {
		return false
	}
	i := 0
	for i < a.length() {
		if c.byteAt(a.file, a.start+i) != c.byteAt(b.file, b.start+i) {
			return false
		}
		i++
	}
	return true
}

// text.matches
func (c *Ctx) matches(a Span, b string) bool {
	if a.length() != len(b) {
		return false
	}
	i := 0
	for i < a.length() {
		if int(c.byteAt(a.file, a.start+i)) != int(b[i]) {
			return false
		}
		i++
	}
	return true
}

// text.number
func (c *Ctx) number(a Span) int {
	value := 0
	i := a.start
	if i == a.end {
		return -1
	}
	for i < a.end {
		ch := int(c.byteAt(a.file, i))
		if ch < 48 || ch > 57 {
			return -1
		}
		if value > 1000000 {
			return -1
		}
		value = value*10 + ch - 48
		i++
	}
	return value
}

// text.identifier
func (c *Ctx) identifier(a Span) bool {
	if a.isEmpty() || a.length() > 64 {
		return false
	}
	i := a.start
	for i < a.end {
		ch := c.byteAt(a.file, i)
		if ch < 33 || ch == 92 {
			return false
		}
		i++
	}
	return true
}

// text.folded
func (c *Ctx) folded(a Span, b Span) bool {
	if a.length() != b.length() {
		return false
	}
	i := 0
	for i < a.length() {
		if lower(c.byteAt(a.file, a.start+i)) != lower(c.byteAt(b.file, b.start+i)) {
			return false
		}
		i++
	}
	return true
}

func lower(ch byte) byte {
	if ch >= 65 && ch <= 90 {
		return ch + 32
	}
	return ch
}

// ── output buffer ────────────────────────────────────────────────────

type Out struct {
	bytes []byte
}

func newOut(capacity int) *Out {
	return &Out{bytes: make([]byte, 0, capacity)}
}

func (o *Out) put(value byte) { o.bytes = append(o.bytes, value) }

func (o *Out) write(text string) { o.bytes = append(o.bytes, text...) }

// text.decimal
func (o *Out) decimal(value int) {
	var buffer [24]byte
	negative := value < 0
	var magnitude uint64
	if negative {
		magnitude = uint64(-(value + 1)) + 1
	} else {
		magnitude = uint64(value)
	}
	at := len(buffer)
	for {
		at--
		buffer[at] = byte('0' + magnitude%10)
		magnitude /= 10
		if magnitude == 0 {
			break
		}
	}
	if negative {
		at--
		buffer[at] = '-'
	}
	o.bytes = append(o.bytes, buffer[at:]...)
}

// text.escaped
func (o *Out) escaped(ctx *Ctx, a Span) {
	i := a.start
	for i < a.end {
		ch := ctx.byteAt(a.file, i)
		i++
		if ch == 92 && i < a.end {
			ch = ctx.byteAt(a.file, i)
			i++
			if ch == 110 {
				ch = 10
			} else if ch == 114 {
				ch = 13
			} else if ch == 116 {
				ch = 9
			}
		}
		switch ch {
		case 9:
			o.write("&#9;")
		case 10:
			o.write("&#10;")
		case 13:
			o.write("&#13;")
		case 38:
			o.write("&amp;")
		case 60:
			o.write("&lt;")
		case 62:
			o.write("&gt;")
		case 34:
			o.write("&quot;")
		default:
			o.put(ch)
		}
	}
}

// ── sexpr ────────────────────────────────────────────────────────────

type Kind int

const (
	kindList Kind = iota
	kindAtom
	kindStr
)

type Node struct {
	kind Kind
	span Span
	next int
}

// sexpr.at: an out-of-range index is an empty atom whose next ends the list.
func at(nodes []Node, index int) Node {
	if index < 0 || index >= len(nodes) {
		return Node{kind: kindAtom, span: emptySpan, next: len(nodes)}
	}
	return nodes[index]
}

// sexpr.form
func form(ctx *Ctx, nodes []Node, index int, name string) bool {
	item := at(nodes, index)
	if item.kind != kindList || item.next == index+1 {
		return false
	}
	return ctx.matches(at(nodes, index+1).span, name)
}

// sexpr.parse
func parse(ctx *Ctx, file int) ([]Node, int) {
	src := ctx.docs[file]
	size := len(src)
	nodes := make([]Node, 0, 1+size/8)
	stack := make([]int, 0, 16)
	depth := 0
	p := 0
	nodes = append(nodes, Node{kind: kindList, span: Span{file: file, start: 0, end: size}, next: 0})
	for p < size {
		c := src[p]
		if c == 32 || c == 9 || c == 10 || c == 13 {
			p++
		} else if c == 59 {
			for p < size && src[p] != 10 {
				p++
			}
		} else if c == 41 {
			if depth == 0 {
				return nil, 1
			}
			depth--
			open := stack[depth]
			nodes[open].next = len(nodes)
			p++
		} else {
			index := len(nodes)
			start := p
			if index == 16384 {
				return nil, 5
			}
			kind := kindAtom
			if c == 40 {
				if depth == 128 {
					return nil, 2
				}
				if depth == len(stack) {
					stack = append(stack, index)
				} else {
					stack[depth] = index
				}
				depth++
				kind = kindList
				p++
			} else if c == 34 {
				kind = kindStr
				p++
				closed := false
				for p < size && !closed {
					ch := src[p]
					p++
					if ch == 92 {
						if p == size {
							return nil, 3
						}
						escape := src[p]
						if escape != 92 && escape != 34 && escape != 110 && escape != 114 && escape != 116 {
							return nil, 6
						}
						p++
					} else if ch == 34 {
						closed = true
					}
				}
				if !closed {
					return nil, 3
				}
			} else {
				scanning := true
				for p < size && scanning {
					ch := src[p]
					if ch == 40 || ch == 41 || ch == 32 || ch == 9 || ch == 10 || ch == 13 || ch == 59 {
						scanning = false
					} else {
						p++
					}
				}
			}
			span := Span{file: file, start: start, end: p}
			if kind == kindStr {
				span.start = start + 1
				span.end = p - 1
			}
			nodes = append(nodes, Node{kind: kind, span: span, next: index + 1})
		}
	}
	if depth != 0 {
		return nil, 4
	}
	nodes[0].next = len(nodes)
	return nodes, 0
}

// ── circuit model ────────────────────────────────────────────────────

type Part struct {
	node      int
	reference Span
	family    Span
	value     Span
	kind      int
	pin1      int
	pin2      int
}

type Pin struct {
	part       int
	number     int
	net        Span
	nc         bool
	display    Span
	netID      int
	displayID  int
	rawRail    int
	rail       int
	decoupling bool
}

// circuit.body
func body(ctx *Ctx, nodes []Node) int {
	i := 1
	for i < len(nodes) {
		if form(ctx, nodes, i, "design-block") {
			return i
		}
		if form(ctx, nodes, i, "defmodule") {
			i++
		} else {
			i = at(nodes, i).next
		}
	}
	return -1
}

// circuit.title
func title(ctx *Ctx, nodes []Node) Span {
	b := body(ctx, nodes)
	if b < 0 {
		return emptySpan
	}
	return at(nodes, b+2).span
}

// circuit.kind
func partKind(ctx *Ctx, family Span) int {
	if ctx.matches(family, "cap-0402") || ctx.matches(family, "cap-0603") {
		return 1
	}
	if ctx.matches(family, "res-0402") {
		return 2
	}
	if ctx.matches(family, "ind-0402") {
		return 3
	}
	return 0
}

// circuit.collectParts
func collectParts(ctx *Ctx, nodes []Node) ([]Part, int) {
	out := []Part{}
	b := body(ctx, nodes)
	if b < 0 {
		return nil, 10
	}
	i := b + 3
	for i < at(nodes, b).next {
		if form(ctx, nodes, i, "instance") {
			reference := at(nodes, i+2)
			spec := at(nodes, i+3)
			if i+3 >= at(nodes, i).next {
				return nil, 11
			}
			if !ctx.identifier(reference.span) || reference.kind != kindStr {
				return nil, 11
			}
			family := spec.span
			value := emptySpan
			if spec.kind == kindList {
				family = at(nodes, i+4).span
				value = at(nodes, i+5).span
			}
			if len(out) == 128 {
				return nil, 5
			}
			for j := 0; j < len(out); j++ {
				if ctx.equal(out[j].reference, reference.span) {
					return nil, 12
				}
			}
			out = append(out, Part{
				node:      i,
				reference: reference.span,
				family:    family,
				value:     value,
				kind:      partKind(ctx, family),
				pin1:      -1,
				pin2:      -1,
			})
		}
		i = at(nodes, i).next
	}
	return out, 0
}

// circuit.label
func pinoutLabel(ctx *Ctx, pinout []Node, number int) Span {
	i := 1
	for i < len(pinout) {
		if form(ctx, pinout, i, "pin") && ctx.number(at(pinout, i+2).span) == number {
			return at(pinout, i+3).span
		}
		i++
	}
	return emptySpan
}

// circuit.collectPins
func collectPins(ctx *Ctx, nodes []Node, parts []Part, pinout []Node) ([]Pin, int) {
	out := []Pin{}
	part := 0
	for part < len(parts) {
		item := parts[part]
		f := at(nodes, item.node+3).next
		for f < at(nodes, item.node).next {
			nc := form(ctx, nodes, f, "nc-ok")
			if form(ctx, nodes, f, "pin") || nc {
				netindex := f + 2
				for netindex < at(nodes, f).next && at(nodes, netindex).kind != kindStr {
					netindex = at(nodes, netindex).next
				}
				if netindex == at(nodes, f).next || netindex == f+2 {
					return nil, 13
				}
				net := at(nodes, netindex).span
				if (!nc && !ctx.identifier(net)) || net.isEmpty() {
					return nil, 13
				}
				for p := f + 2; p < netindex; p = at(nodes, p).next {
					number := ctx.number(at(nodes, p).span)
					valid := number == 1 || number == 2
					if item.kind == 0 {
						named := pinoutLabel(ctx, pinout, number)
						valid = named.end > named.start
					}
					if !valid {
						return nil, 14
					}
					for j := 0; j < len(out); j++ {
						previous := out[j]
						if previous.part == part && previous.number == number {
							return nil, 15
						}
					}
					if len(out) == 1024 {
						return nil, 5
					}
					out = append(out, Pin{
						part:      part,
						number:    number,
						net:       net,
						nc:        nc,
						display:   net,
						netID:     -1,
						displayID: -1,
						rawRail:   0,
						rail:      0,
					})
				}
			}
			f = at(nodes, f).next
		}
		part++
	}
	return out, 0
}

// circuit.displayNet
func displayNet(ctx *Ctx, net Span, parts []Part, pins []Pin) Span {
	last := -1
	previous := -1
	i := net.start
	for i < net.end {
		if ctx.byteAt(net.file, i) == 46 {
			previous = last
			last = i
		}
		i++
	}
	if previous <= net.start || last <= previous+1 || last+1 == net.end {
		return net
	}
	base := net
	base.end = previous
	reference := net
	reference.start = previous + 1
	reference.end = last
	numberSpan := net
	numberSpan.start = last + 1
	number := ctx.number(numberSpan)
	trunk := false
	namedHost := false
	i = 0
	for i < len(pins) {
		pin := pins[i]
		if !pin.nc {
			if ctx.equal(pin.net, base) {
				trunk = true
			}
			if pin.number == number && ctx.equal(pin.net, net) && ctx.equal(parts[pin.part].reference, reference) {
				namedHost = true
			}
		}
		i++
	}
	if trunk && namedHost {
		return base
	}
	return net
}

// circuit.railKind / layout_graph.rail
func railKind(ctx *Ctx, span Span) int {
	if ctx.matches(span, "GND") {
		return 1
	}
	if span.length() >= 2 && ctx.byteAt(span.file, span.start) == 86 && ctx.byteAt(span.file, span.start+1) == 95 {
		return 2
	}
	return 0
}

// circuit.normalize
func normalize(ctx *Ctx, parts []Part, pins []Pin) {
	for i := 0; i < len(pins); i++ {
		display := displayNet(ctx, pins[i].net, parts, pins)
		pins[i].display = display
		pins[i].rawRail = railKind(ctx, pins[i].net)
		pins[i].rail = railKind(ctx, pins[i].display)
		if pins[i].number == 1 {
			parts[pins[i].part].pin1 = i
		}
		if pins[i].number == 2 {
			parts[pins[i].part].pin2 = i
		}
		rawID := -1
		for j := 0; j < i; j++ {
			if rawID < 0 && ctx.equal(pins[j].net, pins[i].net) {
				rawID = pins[j].netID
			}
		}
		if rawID < 0 {
			rawID = i
		}
		pins[i].netID = rawID
	}
	for i := 0; i < len(pins); i++ {
		displayID := -1
		for j := 0; j < len(pins); j++ {
			if displayID < 0 && ctx.equal(pins[j].net, pins[i].display) {
				displayID = pins[j].netID
			}
		}
		for j := 0; j < i; j++ {
			if displayID < 0 && ctx.equal(pins[j].display, pins[i].display) {
				displayID = pins[j].displayID
			}
		}
		if displayID < 0 {
			displayID = len(pins) + i
		}
		pins[i].displayID = displayID
	}
	for i := 0; i < len(pins); i++ {
		pin := pins[i]
		if pin.rawRail == 1 && parts[pin.part].kind == 1 {
			otherIndex := parts[pin.part].pin1
			if otherIndex == i {
				otherIndex = parts[pin.part].pin2
			}
			if otherIndex >= 0 {
				other := pins[otherIndex]
				pins[i].decoupling = other.rail == 2 && other.rawRail != 1 && other.displayID != other.netID
			}
		}
	}
}

// ── validate ─────────────────────────────────────────────────────────

// validate.source
func validateSource(ctx *Ctx, nodes []Node) int {
	i := 1
	modules := 0
	blocks := 0
	for i < len(nodes) {
		if form(ctx, nodes, i, "defmodule") {
			modules++
			params := at(nodes, i+3)
			if modules != 1 || params.kind != kindList || params.next != i+4 {
				return 16
			}
			f := i + 4
			for f < at(nodes, i).next {
				if at(nodes, f).kind == kindStr || form(ctx, nodes, f, "implements") {
					// permitted
				} else if form(ctx, nodes, f, "design-block") {
					blocks++
					if blocks != 1 || at(nodes, f+2).kind != kindStr {
						return 16
					}
					child := f + 3
					for child < at(nodes, f).next {
						if !form(ctx, nodes, child, "instance") && !metadata(ctx, nodes, child) {
							return 17
						}
						child = at(nodes, child).next
					}
				} else {
					return 17
				}
				f = at(nodes, f).next
			}
		} else if !form(ctx, nodes, i, "import") {
			return 17
		}
		i = at(nodes, i).next
	}
	if modules != 1 || blocks != 1 {
		return 16
	}
	return 0
}

// validate.metadata
func metadata(ctx *Ctx, nodes []Node, i int) bool {
	names := [...]string{
		"net-envelope",
		"port",
		"port-group",
		"net-class",
		"pcb-plan",
		"rough",
		"note",
	}
	for _, name := range names {
		if form(ctx, nodes, i, name) {
			return true
		}
	}
	return false
}

// validate.pinoutCheck
func pinoutCheck(ctx *Ctx, nodes []Node) int {
	if !form(ctx, nodes, 1, "pinout") || at(nodes, 1).next != len(nodes) || at(nodes, 3).kind != kindStr {
		return 18
	}
	count := 0
	i := 4
	for i < at(nodes, 1).next {
		number := ctx.number(at(nodes, i+2).span)
		if !form(ctx, nodes, i, "pin") ||
			at(nodes, i).next != i+4 ||
			number < 1 ||
			number > 41 ||
			at(nodes, i+3).kind != kindStr ||
			!ctx.identifier(at(nodes, i+3).span) {
			return 18
		}
		j := 4
		for j < i {
			if ctx.number(at(nodes, j+2).span) == number {
				return 18
			}
			j = at(nodes, j).next
		}
		count++
		i = at(nodes, i).next
	}
	if count != 41 {
		return 18
	}
	return 0
}

// validate.fields
func fields(ctx *Ctx, nodes []Node, item Part) int {
	spec := at(nodes, item.node+3)
	if item.kind != 0 &&
		(spec.kind != kindList ||
			spec.next < item.node+6 ||
			at(nodes, item.node+5).kind != kindStr) {
		return 19
	}
	if item.kind == 0 && spec.kind != kindAtom {
		return 19
	}
	f := spec.next
	for f < at(nodes, item.node).next {
		if !form(ctx, nodes, f, "pin") &&
			!form(ctx, nodes, f, "nc-ok") &&
			!form(ctx, nodes, f, "id") &&
			!form(ctx, nodes, f, "decouples") {
			return 17
		}
		if form(ctx, nodes, f, "nc-ok") && item.kind != 0 {
			return 13
		}
		if form(ctx, nodes, f, "pin") || form(ctx, nodes, f, "nc-ok") {
			j := f + 2
			for j < at(nodes, f).next && at(nodes, j).kind == kindAtom {
				j++
			}
			if j == f+2 || at(nodes, j).kind != kindStr {
				return 13
			}
			if form(ctx, nodes, f, "nc-ok") && (j != f+3 || at(nodes, f).next != j+1) {
				return 13
			}
			j++
			for j < at(nodes, f).next {
				if !form(ctx, nodes, j, "i-typ") && !form(ctx, nodes, j, "i-max") {
					return 17
				}
				j = at(nodes, j).next
			}
		}
		f = at(nodes, f).next
	}
	return 0
}

// validate.model
func validateModel(ctx *Ctx, nodes []Node, parts []Part, pins []Pin, pinout []Node) int {
	schema := pinoutCheck(ctx, pinout)
	if schema != 0 {
		return schema
	}
	chips := 0
	p := 0
	for p < len(parts) {
		item := parts[p]
		fieldError := fields(ctx, nodes, item)
		if fieldError != 0 {
			return fieldError
		}
		if item.kind == 0 {
			chips++
			if !ctx.folded(item.family, at(pinout, 3).span) {
				return 19
			}
		}
		count := 0
		for j := 0; j < len(pins); j++ {
			if pins[j].part == p {
				count++
			}
		}
		if (item.kind == 0 && count != 41) || (item.kind != 0 && count != 2) {
			return 20
		}
		p++
	}
	if chips != 1 {
		return 19
	}
	return 0
}

// ── ports ────────────────────────────────────────────────────────────

type Port struct {
	prefix    Span
	name      Span
	direction Span
}

// ports.collect
func portsCollect(ctx *Ctx, nodes []Node, lanes []Node) ([]Port, int) {
	out := []Port{}
	if !form(ctx, lanes, 1, "interface") || at(lanes, 1).next != len(lanes) {
		return nil, 21
	}
	b := body(ctx, nodes)
	i := b + 3
	for i < at(nodes, b).next {
		if form(ctx, nodes, i, "port") {
			name := at(nodes, i+2)
			direction := at(nodes, i+3)
			if i+3 >= at(nodes, i).next ||
				name.kind != kindStr ||
				!ctx.identifier(name.span) ||
				!directionOk(ctx, direction.span) {
				return nil, 21
			}
			if len(out) == 32 {
				return nil, 21
			}
			out = append(out, Port{prefix: emptySpan, name: name.span, direction: direction.span})
		} else if form(ctx, nodes, i, "port-group") {
			prefix := at(nodes, i+2).span
			if !ctx.identifier(prefix) || !ctx.equal(at(nodes, i+3).span, at(lanes, 3).span) {
				return nil, 21
			}
			for rename := i + 4; rename < at(nodes, i).next; rename = at(nodes, rename).next {
				if !form(ctx, nodes, rename, "rename") ||
					at(nodes, rename).next != rename+4 ||
					at(nodes, rename+3).kind != kindStr {
					return nil, 21
				}
				found := false
				for lane := 5; lane < at(lanes, 1).next; lane = at(lanes, lane).next {
					if ctx.equal(at(nodes, rename+2).span, at(lanes, lane+2).span) {
						found = true
					}
				}
				if !found {
					return nil, 21
				}
			}
			for lane := 5; lane < at(lanes, 1).next; lane = at(lanes, lane).next {
				if !form(ctx, lanes, lane, "signal") ||
					at(lanes, lane).next < lane+4 ||
					!directionOk(ctx, at(lanes, lane+3).span) {
					return nil, 21
				}
				label := at(lanes, lane+2).span
				original := label
				pre := prefix
				renamed := false
				for rename := i + 4; rename < at(nodes, i).next; rename = at(nodes, rename).next {
					if ctx.equal(at(nodes, rename+2).span, original) {
						if renamed {
							return nil, 21
						}
						renamed = true
						label = at(nodes, rename+3).span
						pre = emptySpan
					}
				}
				if !ctx.identifier(label) || len(out) == 32 {
					return nil, 21
				}
				out = append(out, Port{prefix: pre, name: label, direction: at(lanes, lane+3).span})
			}
		}
		i = at(nodes, i).next
	}
	return out, 0
}

// ports.direction
func directionOk(ctx *Ctx, span Span) bool {
	return ctx.matches(span, "in") || ctx.matches(span, "out") || ctx.matches(span, "bidi")
}

// ports.size
func portSize(item Port) int {
	n := item.name.end - item.name.start
	if item.prefix.start != item.prefix.end {
		n += item.prefix.end - item.prefix.start + 1
	}
	return n
}

// ports.byteAt
func portByte(ctx *Ctx, item Port, index int) byte {
	n := item.prefix.end - item.prefix.start
	if n == 0 {
		return ctx.byteAt(item.name.file, item.name.start+index)
	}
	if index < n {
		return ctx.byteAt(item.prefix.file, item.prefix.start+index)
	}
	if index == n {
		return 95
	}
	return ctx.byteAt(item.name.file, item.name.start+index-n-1)
}

// ports.equal
func portEqual(ctx *Ctx, a Port, b Port) bool {
	if portSize(a) != portSize(b) {
		return false
	}
	i := 0
	for i < portSize(a) {
		if portByte(ctx, a, i) != portByte(ctx, b, i) {
			return false
		}
		i++
	}
	return true
}

// ports.validate
func portsValidate(ctx *Ctx, connections []Port, pins []Pin) int {
	i := 0
	for i < len(connections) {
		item := connections[i]
		j := 0
		for j < i {
			if portEqual(ctx, item, connections[j]) {
				return 22
			}
			j++
		}
		found := false
		j = 0
		for j < len(pins) {
			pin := pins[j]
			candidate := Port{prefix: emptySpan, name: pin.net, direction: emptySpan}
			if !pin.nc && portEqual(ctx, item, candidate) {
				found = true
			}
			j++
		}
		if !found {
			return 23
		}
		i++
	}
	return 0
}

// ── net graph ────────────────────────────────────────────────────────

type Net struct {
	span     Span
	identity int
	group    int
	owner    int
	distance int
}

type Edge struct {
	a int
	b int
}

// layout_graph.findId
func findID(nets []Net, identity int) int {
	i := 0
	for i < len(nets) {
		if nets[i].identity == identity {
			return i
		}
		i++
	}
	return -1
}

// layout_graph.build
func graphBuild(parts []Part, pins []Pin) []Net {
	nets := []Net{}
	edges := []Edge{}
	i := 0
	for i < len(pins) {
		pin := pins[i]
		if !pin.nc {
			present := false
			n := 0
			for n < len(nets) {
				if nets[n].identity == pin.displayID {
					present = true
				}
				n++
			}
			if !present {
				nets = append(nets, Net{
					span:     pin.display,
					identity: pin.displayID,
					group:    len(nets),
					owner:    -1,
					distance: 4096,
				})
			}
		}
		i++
	}
	part := 0
	for part < len(parts) {
		if parts[part].kind != 0 {
			ai := parts[part].pin1
			bi := parts[part].pin2
			if ai >= 0 &&
				bi >= 0 &&
				!pins[ai].nc &&
				!pins[bi].nc &&
				pins[ai].rail == 0 &&
				pins[bi].rail == 0 {
				na := -1
				nb := -1
				ga := -1
				gb := -1
				i := 0
				for i < len(nets) {
					item := nets[i]
					if item.identity == pins[ai].displayID {
						ga = item.group
						na = i
					}
					if item.identity == pins[bi].displayID {
						gb = item.group
						nb = i
					}
					i++
				}
				if na >= 0 && nb >= 0 {
					edges = append(edges, Edge{a: na, b: nb})
				}
				if ga >= 0 && gb >= 0 && ga != gb {
					i := 0
					for i < len(nets) {
						if nets[i].group == gb {
							nets[i].group = ga
						}
						i++
					}
				}
			}
		}
		part++
	}
	i = 0
	for i < len(pins) {
		pin := pins[i]
		if !pin.nc && parts[pin.part].kind == 0 {
			n := 0
			for n < len(nets) {
				if nets[n].owner < 0 && nets[n].identity == pin.displayID {
					nets[n].owner = i
					nets[n].distance = 0
				}
				n++
			}
		}
		i++
	}
	changed := true
	passes := 0
	for changed && passes < 128 {
		changed = false
		i := 0
		for i < len(edges) {
			edge := edges[i]
			// Records are values: these are snapshots taken before any update.
			head := nets[edge.a]
			tail := nets[edge.b]
			if head.distance+1 < tail.distance ||
				(head.owner >= 0 &&
					tail.owner >= 0 &&
					head.distance+1 == tail.distance &&
					pins[head.owner].number < pins[tail.owner].number) {
				nets[edge.b].owner = head.owner
				nets[edge.b].distance = head.distance + 1
				changed = true
			}
			if tail.distance+1 < head.distance ||
				(head.owner >= 0 &&
					tail.owner >= 0 &&
					tail.distance+1 == head.distance &&
					pins[tail.owner].number < pins[head.owner].number) {
				nets[edge.a].owner = tail.owner
				nets[edge.a].distance = tail.distance + 1
				changed = true
			}
			i++
		}
		passes++
	}
	return nets
}

// ── layout ───────────────────────────────────────────────────────────

type Point struct {
	x int
	y int
}

type Row struct {
	index  int
	group  int
	height int
	rail   int
	side   int
	y      int
}

// floorDiv is floor division, matching mylang's `//` on integers.
func floorDiv(a int, b int) int {
	q := a / b
	if a%b != 0 && ((a < 0) != (b < 0)) {
		return q - 1
	}
	return q
}

// layout.pinGroup
func pinGroup(pin Pin, nets []Net) int {
	id := findID(nets, pin.displayID)
	if id < 0 {
		return -1
	}
	return nets[id].group
}

// layout.rowHeight
func rowHeight(pin Pin, passiveCounts []int, bridgeNets []bool) int {
	if pin.rail != 0 {
		return 40
	}
	count := passiveCounts[pin.netID]
	if count > 1 {
		if !bridgeNets[pin.netID] {
			return count * 40
		}
		return 56 + (count-1)*40
	}
	return 56
}

// layout.collectRows
func collectRows(parts []Part, pins []Pin, nets []Net) []Row {
	out := []Row{}
	var counts [130]int
	var offsets [130]int
	var cursor [130]int
	ordered := make([]int, len(pins))
	for i := range ordered {
		ordered[i] = -1
	}
	passiveCounts := make([]int, len(pins))
	bridgeNets := make([]bool, len(pins))
	hubNets := make([]bool, len(pins))
	hubCount := 0
	i := 0
	for i < len(pins) {
		pin := pins[i]
		if parts[pin.part].kind == 0 {
			if !pin.nc && pin.number >= 1 && pin.number <= 128 {
				counts[pin.number]++
				hubCount++
			}
			if pin.netID >= 0 {
				hubNets[pin.netID] = true
			}
		} else if !pin.nc && pin.netID >= 0 {
			passiveCounts[pin.netID]++
		}
		i++
	}
	number := 1
	for number <= 129 {
		offsets[number] = offsets[number-1] + counts[number-1]
		cursor[number] = offsets[number]
		number++
	}
	i = 0
	for i < len(pins) {
		pin := pins[i]
		if parts[pin.part].kind == 0 && !pin.nc && pin.number >= 1 && pin.number <= 128 {
			slot := cursor[pin.number]
			ordered[slot] = i
			cursor[pin.number] = slot + 1
		}
		i++
	}
	i = 0
	for i < len(pins) {
		pin := pins[i]
		if parts[pin.part].kind != 0 && !pin.nc {
			far := parts[pin.part].pin1
			if far == i {
				far = parts[pin.part].pin2
			}
			if far >= 0 &&
				pins[far].rawRail == 0 &&
				pins[far].netID >= 0 &&
				hubNets[pins[far].netID] {
				bridgeNets[pin.netID] = true
			}
		}
		i++
	}
	seenGroups := []int{}
	position := 0
	for position < hubCount {
		index := ordered[position]
		pin := pins[index]
		group := pinGroup(pin, nets)
		present := false
		n := 0
		for n < len(seenGroups) {
			if seenGroups[n] == group {
				present = true
			}
			n++
		}
		if !present {
			seenGroups = append(seenGroups, group)
			member := 0
			for member < hubCount {
				otherIndex := ordered[member]
				other := pins[otherIndex]
				if other.part == pin.part && pinGroup(other, nets) == group {
					out = append(out, Row{
						index:  otherIndex,
						group:  group,
						height: rowHeight(other, passiveCounts, bridgeNets),
						rail:   other.rail,
						side:   0,
						y:      0,
					})
				}
				member++
			}
		}
		position++
	}
	return out
}

// layout.height
func layoutHeight(points []Point) int {
	bottom := 160
	i := 0
	for i < len(points) {
		if points[i].y+40 > bottom {
			bottom = points[i].y + 40
		}
		i++
	}
	return bottom
}

// layout.placeRows
func placeRows(rows []Row) {
	total := 0
	i := 0
	for i < len(rows) {
		row := rows[i]
		total += row.height
		if i == 0 || rows[i-1].group != row.group {
			if row.rail == 1 {
				total += 16
			}
			if row.rail == 2 {
				total += 56
			}
		}
		i++
	}
	prefix := 0
	best := total * 100
	split := len(rows)
	i = 0
	for i+1 < len(rows) {
		row := rows[i]
		prefix += row.height
		if i == 0 || rows[i-1].group != row.group {
			if row.rail == 1 {
				prefix += 16
			}
			if row.rail == 2 {
				prefix += 56
			}
		}
		if rows[i].group != rows[i+1].group {
			delta := total*48 - 100*prefix
			if delta < 0 {
				delta = -delta
			}
			if delta < best {
				best = delta
				split = i + 1
			}
		}
		i++
	}
	y := 80
	i = 0
	for i < len(rows) {
		if i == split {
			y = 80
		}
		row := rows[i]
		if i > 0 && i != split && rows[i-1].group != row.group {
			if rows[i-1].rail == 1 {
				y += 16
			}
			if rows[i-1].rail == 2 {
				y += 36
			}
			if rows[i-1].height == 80 {
				y += 16
			}
		}
		if row.rail == 2 && (i == 0 || i == split || rows[i-1].group != row.group) {
			y += 20
		}
		offset := 0
		if row.height > 56 {
			offset = floorDiv(row.height-56, 2)
		}
		if row.height == 80 {
			offset = 20
		}
		side := -1
		if i >= split {
			side = 1
		}
		rows[i].side = side
		rows[i].y = y + offset
		y += row.height
		i++
	}
}

// layout.nearest
func nearest(pin Pin, parts []Part, pins []Pin, rows []Row, nets []Net) int {
	group := pinGroup(pin, nets)
	id := findID(nets, pin.displayID)
	owner := -1
	if id >= 0 {
		owner = nets[id].owner
	}
	fallback := -1
	i := 0
	for i < len(rows) {
		row := rows[i]
		hub := pins[row.index]
		if pin.netID == hub.netID {
			return i
		}
		if row.index == owner {
			fallback = i
		}
		if row.group == group && fallback < 0 {
			fallback = i
		}
		i++
	}
	return fallback
}

// layout.partPin
func partPin(part int, number int, parts []Part, pins []Pin) Pin {
	index := -1
	if number == 1 {
		index = parts[part].pin1
	} else if number == 2 {
		index = parts[part].pin2
	}
	if index >= 0 &&
		index < len(pins) &&
		pins[index].part == part &&
		pins[index].number == number {
		return pins[index]
	}
	i := 0
	for i < len(pins) {
		pin := pins[i]
		if pin.part == part && pin.number == number {
			return pin
		}
		i++
	}
	return Pin{
		part:      part,
		number:    number,
		net:       emptySpan,
		nc:        true,
		display:   emptySpan,
		netID:     -1,
		displayID: -1,
		rawRail:   0,
		rail:      0,
	}
}

// layout.depth
func depth(pin Pin, nets []Net) int {
	id := findID(nets, pin.displayID)
	if id < 0 {
		return 4096
	}
	return nets[id].distance
}

// layout.innerPin
func innerPin(part int, parts []Part, pins []Pin, nets []Net) Pin {
	a := partPin(part, 1, parts, pins)
	b := partPin(part, 2, parts, pins)
	if a.rawRail != 0 && b.rawRail == 0 {
		return b
	}
	if b.rawRail == 0 && depth(b, nets) < depth(a, nets) {
		return b
	}
	return a
}

// layout.bridge
func bridge(part int, parts []Part, pins []Pin, rows []Row, nets []Net) bool {
	a := partPin(part, 1, parts, pins)
	b := partPin(part, 2, parts, pins)
	if a.rawRail != 0 || b.rawRail != 0 {
		return false
	}
	if depth(a, nets) != depth(b, nets) {
		return false
	}
	ai := nearest(a, parts, pins, rows, nets)
	bi := nearest(b, parts, pins, rows, nets)
	return ai >= 0 && bi >= 0 && ai != bi
}

// layout.groundBranch
func groundBranch(part int, parts []Part, pins []Pin, nets []Net) bool {
	inner := innerPin(part, parts, pins, nets)
	outer := partPin(part, 3-inner.number, parts, pins)
	if outer.rawRail == 1 {
		return true
	}
	if outer.rawRail == 2 {
		return false
	}
	found := false
	j := 0
	for j < len(parts) {
		if parts[j].kind != 0 && j != part {
			a := partPin(j, 1, parts, pins)
			b := partPin(j, 2, parts, pins)
			otherRail := 0
			if a.netID == outer.netID {
				otherRail = b.rawRail
			}
			if b.netID == outer.netID {
				otherRail = a.rawRail
			}
			if otherRail == 2 {
				return false
			}
			if otherRail == 1 {
				found = true
			}
		}
		j++
	}
	return found
}

// layout.branch
func branch(part int, parts []Part, pins []Pin, rows []Row, nets []Net, remaining int) int {
	if remaining == 0 {
		return 0
	}
	inner := innerPin(part, parts, pins, nets)
	level := depth(inner, nets)
	offset := 0
	if level > 0 {
		owner := nearest(inner, parts, pins, rows, nets)
		j := 0
		for j < len(parts) {
			if parts[j].kind != 0 && j != part {
				previous := innerPin(j, parts, pins, nets)
				if depth(previous, nets) < level && nearest(previous, parts, pins, rows, nets) == owner {
					outer := partPin(j, 3-previous.number, parts, pins)
					if outer.netID == inner.netID {
						offset = branch(j, parts, pins, rows, nets, remaining-1)
						break
					}
				}
			}
			j++
		}
	}
	count := 0
	rank := 0
	hasBridge := false
	grounded := groundBranch(part, parts, pins, nets)
	j := 0
	for j < len(parts) {
		if parts[j].kind != 0 {
			previous := innerPin(j, parts, pins, nets)
			a := partPin(j, 1, parts, pins)
			b := partPin(j, 2, parts, pins)
			if bridge(j, parts, pins, rows, nets) {
				if a.netID == inner.netID || b.netID == inner.netID {
					hasBridge = true
				}
			} else if previous.netID == inner.netID {
				count++
				otherGround := groundBranch(j, parts, pins, nets)
				if level > 0 {
					if j < part {
						rank++
					}
				} else if (otherGround && !grounded) || (otherGround == grounded && j < part) {
					rank++
				}
			}
		}
		j++
	}
	if level == 0 {
		spacing := 20
		if hasBridge {
			spacing = 40
		}
		offset -= (count - 1) * spacing
	}
	return offset + rank*40
}

// layout.endpoint
func endpoint(pin Pin, parts []Part, pins []Pin, rows []Row, nets []Net) Point {
	inner := innerPin(pin.part, parts, pins, nets)
	chosen := nearest(inner, parts, pins, rows, nets)
	if chosen < 0 {
		return Point{x: 100 + pin.number*60, y: 80 + pin.part*60}
	}
	row := rows[chosen]
	edge := 352
	if row.side == 1 {
		edge = 532
	}
	level := depth(inner, nets)
	if bridge(pin.part, parts, pins, rows, nets) {
		target := nearest(pin, parts, pins, rows, nets)
		other := rows[target]
		reach := 50
		if level > 0 {
			reach = 170
		}
		return Point{x: edge + row.side*reach, y: other.y}
	}
	hub := pins[row.index]
	count := 0
	j := 0
	for j < len(parts) {
		if parts[j].kind != 0 {
			attached := innerPin(j, parts, pins, nets)
			if attached.netID == hub.netID && !bridge(j, parts, pins, rows, nets) {
				count++
			}
		}
		j++
	}
	reach := 40
	if count > 1 {
		reach = 60
	}
	if pin.number != inner.number {
		reach = 120
	}
	localRail := inner.rawRail == 2 && inner.displayID != inner.netID
	y := row.y + branch(pin.part, parts, pins, rows, nets, 128)
	if localRail {
		reach = 70
		if pin.number != inner.number {
			reach = 110
		}
		y += 20
	}
	x := edge + row.side*(reach+level*60)
	return Point{x: x, y: y}
}

// layout.build
func layoutBuild(parts []Part, pins []Pin) []Point {
	nets := graphBuild(parts, pins)
	out := make([]Point, 0, len(pins))
	ordered := collectRows(parts, pins, nets)
	placeRows(ordered)
	i := 0
	for i < len(pins) {
		pin := pins[i]
		point := Point{x: -1, y: -1}
		if parts[pin.part].kind == 0 {
			j := 0
			for j < len(ordered) {
				row := ordered[j]
				if row.index == i {
					x := 352
					if row.side == 1 {
						x = 532
					}
					point = Point{x: x, y: row.y}
				}
				j++
			}
		} else {
			point = endpoint(pin, parts, pins, ordered, nets)
		}
		out = append(out, point)
		i++
	}
	return out
}

// ── routes ───────────────────────────────────────────────────────────

type Segment struct {
	x1       int
	y1       int
	x2       int
	y2       int
	net      Span
	junction bool
	terminal bool
}

func manhattan(a Point, b Point) int {
	x := a.x - b.x
	y := a.y - b.y
	if x < 0 {
		x = -x
	}
	if y < 0 {
		y = -y
	}
	return x + y
}

// layout_routes.external
func external(ctx *Ctx, net Span, connections []Port) bool {
	target := Port{prefix: emptySpan, name: net, direction: emptySpan}
	i := 0
	for i < len(connections) {
		if portEqual(ctx, target, connections[i]) {
			return true
		}
		i++
	}
	return false
}

// layout_routes.blocked
func blocked(a Point, b Point, netID int, pins []Pin, points []Point) bool {
	i := 0
	for i < len(pins) {
		pin := pins[i]
		q := points[i]
		intersects := false
		if a.x == b.x && q.x == a.x && ((q.y >= a.y && q.y <= b.y) || (q.y >= b.y && q.y <= a.y)) {
			intersects = true
		}
		if a.y == b.y && q.y == a.y && ((q.x >= a.x && q.x <= b.x) || (q.x >= b.x && q.x <= a.x)) {
			intersects = true
		}
		if intersects && !pin.nc && pin.displayID != netID {
			if a.x == b.x {
				return true
			}
			if a.y == b.y {
				return true
			}
		}
		i++
	}
	return false
}

// layout_routes.build
func routesBuild(ctx *Ctx, parts []Part, pins []Pin, points []Point, connections []Port) []Segment {
	out := []Segment{}
	i := 0
	for i < len(pins) {
		pin := pins[i]
		point := points[i]
		if !pin.nc {
			display := pin.display
			isGround := pin.rawRail == 1
			coupledGround := pin.decoupling
			localGround := isGround && parts[pin.part].kind != 0 && !coupledGround
			isRail := pin.rail != 0 && !isGround
			standaloneRail := isRail && parts[pin.part].kind != 0 && pin.netID == pin.displayID
			nearestIndex := -1
			shortest := 1000000
			count := 0
			j := 0
			for j < len(pins) {
				other := pins[j]
				otherPoint := points[j]
				otherStandalone := isRail && parts[other.part].kind != 0 && other.netID == pin.displayID
				allowed := (!isGround ||
					(coupledGround && other.decoupling) ||
					(!coupledGround && parts[other.part].kind == 0)) && !otherStandalone
				if !other.nc && allowed && pin.displayID == other.displayID {
					count++
					if j < i && manhattan(point, otherPoint) < shortest {
						nearestIndex = j
						shortest = manhattan(point, otherPoint)
					}
				}
				j++
			}
			if nearestIndex < 0 &&
				count > 1 &&
				(isGround || isRail) &&
				!localGround &&
				!standaloneRail {
				low := point.y
				high := point.y
				k := 0
				for k < len(pins) {
					other := pins[k]
					if !other.nc &&
						((coupledGround && other.decoupling) ||
							(!coupledGround && parts[other.part].kind == 0)) &&
						pin.displayID == other.displayID {
						q := points[k]
						if q.y < low {
							low = q.y
						}
						if q.y > high {
							high = q.y
						}
					}
					k++
				}
				side := -1
				if point.x > 442 {
					side = 1
				}
				y := floorDiv(low+high, 2)
				if isRail {
					y = low - 20
				}
				if coupledGround {
					y = high
				}
				bus := point.x + side*40
				if coupledGround {
					bus = point.x + side*20
				}
				out = append(out, Segment{
					x1:       bus,
					y1:       point.y,
					x2:       bus,
					y2:       y,
					net:      display,
					junction: false,
					terminal: false,
				})
				reach := 100
				if coupledGround {
					reach = 10
				}
				out = append(out, Segment{
					x1:       bus,
					y1:       y,
					x2:       bus + side*reach,
					y2:       y,
					net:      display,
					junction: false,
					terminal: true,
				})
			}
			if nearestIndex < 0 &&
				count > 1 &&
				!isGround &&
				!isRail &&
				external(ctx, display, connections) {
				dx := 24
				if point.x < 442 {
					dx = -24
				}
				out = append(out, Segment{
					x1:       point.x,
					y1:       point.y,
					x2:       point.x + dx,
					y2:       point.y,
					net:      display,
					junction: false,
					terminal: true,
				})
			}
			if localGround || standaloneRail || count == 1 {
				dx := 24
				if parts[pin.part].kind == 0 {
					dx = 140
					if !external(ctx, display, connections) && !isRail && !isGround {
						dx = 50
					}
				}
				if point.x < 442 {
					dx = -dx
				}
				out = append(out, Segment{
					x1:       point.x,
					y1:       point.y,
					x2:       point.x + dx,
					y2:       point.y,
					net:      display,
					junction: false,
					terminal: true,
				})
			} else if nearestIndex >= 0 {
				previous := points[nearestIndex]
				if isGround || (point.x == previous.x && (point.x == 352 || point.x == 532)) {
					bus := point.x - 40
					if point.x > 442 {
						bus = point.x + 40
					}
					if coupledGround {
						bus = point.x - 20
						if point.x > 442 {
							bus = point.x + 20
						}
					}
					out = append(out, Segment{
						x1:       point.x,
						y1:       point.y,
						x2:       bus,
						y2:       point.y,
						net:      display,
						junction: false,
						terminal: false,
					})
					out = append(out, Segment{
						x1:       bus,
						y1:       point.y,
						x2:       bus,
						y2:       previous.y,
						net:      display,
						junction: true,
						terminal: false,
					})
					out = append(out, Segment{
						x1:       bus,
						y1:       previous.y,
						x2:       previous.x,
						y2:       previous.y,
						net:      display,
						junction: false,
						terminal: false,
					})
				} else if isRail && parts[pin.part].kind != 0 {
					bus := 302
					if point.x > 442 {
						bus = 582
					}
					out = append(out, Segment{
						x1:       point.x,
						y1:       point.y,
						x2:       bus,
						y2:       point.y,
						net:      display,
						junction: false,
						terminal: false,
					})
					out = append(out, Segment{
						x1:       bus,
						y1:       point.y,
						x2:       bus,
						y2:       previous.y,
						net:      display,
						junction: false,
						terminal: false,
					})
					out = append(out, Segment{
						x1:       bus,
						y1:       previous.y,
						x2:       previous.x,
						y2:       previous.y,
						net:      display,
						junction: false,
						terminal: false,
					})
				} else if parts[pins[nearestIndex].part].kind == 0 && point.y != previous.y {
					side := 1
					if previous.x < 442 {
						side = -1
					}
					bus := previous.x + side*50
					out = append(out, Segment{
						x1:       point.x,
						y1:       point.y,
						x2:       bus,
						y2:       point.y,
						net:      display,
						junction: false,
						terminal: false,
					})
					out = append(out, Segment{
						x1:       bus,
						y1:       point.y,
						x2:       bus,
						y2:       previous.y,
						net:      display,
						junction: false,
						terminal: false,
					})
					out = append(out, Segment{
						x1:       bus,
						y1:       previous.y,
						x2:       previous.x,
						y2:       previous.y,
						net:      display,
						junction: false,
						terminal: false,
					})
				} else if point.x == previous.x && blocked(point, previous, pin.displayID, pins, points) {
					offset := 16
					lane := point.x + offset
					laneStart := Point{x: lane, y: point.y}
					laneEnd := Point{x: lane, y: previous.y}
					for blocked(laneStart, laneEnd, pin.displayID, pins, points) && offset < 160 {
						offset += 16
						lane = point.x + offset
						laneStart.x = lane
						laneEnd.x = lane
					}
					out = append(out, Segment{
						x1:       point.x,
						y1:       point.y,
						x2:       lane,
						y2:       point.y,
						net:      display,
						junction: false,
						terminal: false,
					})
					out = append(out, Segment{
						x1:       lane,
						y1:       point.y,
						x2:       lane,
						y2:       previous.y,
						net:      display,
						junction: false,
						terminal: false,
					})
					out = append(out, Segment{
						x1:       lane,
						y1:       previous.y,
						x2:       previous.x,
						y2:       previous.y,
						net:      display,
						junction: false,
						terminal: false,
					})
				} else {
					out = append(out, Segment{
						x1:       point.x,
						y1:       point.y,
						x2:       previous.x,
						y2:       point.y,
						net:      display,
						junction: count > 2,
						terminal: false,
					})
					if point.y != previous.y {
						out = append(out, Segment{
							x1:       previous.x,
							y1:       point.y,
							x2:       previous.x,
							y2:       previous.y,
							net:      display,
							junction: count > 2,
							terminal: false,
						})
					}
				}
			}
		}
		i++
	}
	return out
}

// ── SVG ──────────────────────────────────────────────────────────────

// draw.rect
func drawRect(out *Out, x int, y int, w int, h int) {
	out.write("<rect class=\"chip\" x=\"")
	out.decimal(x)
	out.write("\" y=\"")
	out.decimal(y)
	out.write("\" width=\"")
	out.decimal(w)
	out.write("\" height=\"")
	out.decimal(h)
	out.write("\" rx=\"6\"/>")
}

// draw.line
func drawLine(out *Out, x1 int, y1 int, x2 int, y2 int) {
	out.write("<line x1=\"")
	out.decimal(x1)
	out.write("\" y1=\"")
	out.decimal(y1)
	out.write("\" x2=\"")
	out.decimal(x2)
	out.write("\" y2=\"")
	out.decimal(y2)
	out.write("\"/>")
}

// draw.labelStart
func drawLabelStart(out *Out, x int, y int, anchor int) {
	out.write("<text x=\"")
	out.decimal(x)
	out.write("\" y=\"")
	out.decimal(y)
	out.write("\" text-anchor=\"")
	if anchor == 0 {
		out.write("start")
	} else if anchor == 1 {
		out.write("middle")
	} else {
		out.write("end")
	}
	out.write("\">")
}

// draw.labelEnd
func drawLabelEnd(out *Out) {
	out.write("</text>")
}

// draw.label
func drawLabel(out *Out, ctx *Ctx, x int, y int, anchor int, value Span) {
	drawLabelStart(out, x, y, anchor)
	out.escaped(ctx, value)
	drawLabelEnd(out)
}

// draw.symbol
func drawSymbol(out *Out, kind int) {
	out.write("<g class=\"symbol\">")
	drawLine(out, -20, 0, -12, 0)
	drawLine(out, 12, 0, 20, 0)
	if kind == 1 {
		drawLine(out, -3, -6, -3, 6)
		drawLine(out, 3, -6, 3, 6)
		drawLine(out, -12, 0, -3, 0)
		drawLine(out, 3, 0, 12, 0)
	} else if kind == 2 {
		out.write("<rect x=\"-12\" y=\"-5\" width=\"24\" height=\"10\"/>")
	} else {
		out.write("<path d=\"M -12 0 c 0,-7 6,-7 6,0 c 0,-7 6,-7 6,0 c 0,-7 6,-7 6,0 c 0,-7 6,-7 6,0\"/>")
	}
	out.write("</g>")
}

// svg.instanceStart
func instanceStart(out *Out, ctx *Ctx, item Part) {
	out.write("<g class=\"component\" data-ref=\"")
	out.escaped(ctx, item.reference)
	out.write("\" data-family=\"")
	out.escaped(ctx, item.family)
	out.write("\" data-value=\"")
	out.escaped(ctx, item.value)
	out.write("\"><title>")
	out.escaped(ctx, item.reference)
	out.write(" — ")
	out.escaped(ctx, item.family)
	out.write(" ")
	out.escaped(ctx, item.value)
	out.write("</title>")
}

// svg.pinStart
func pinStart(out *Out, ctx *Ctx, pin Pin, display Span, point Point) {
	out.write("<g data-pin=\"")
	out.decimal(pin.number)
	out.write("\" data-x=\"")
	out.decimal(point.x)
	out.write("\" data-y=\"")
	out.decimal(point.y)
	if pin.nc {
		out.write("\" data-nc=\"true\"><title>")
		out.escaped(ctx, pin.net)
		out.write("</title>")
	} else {
		out.write("\" data-net=\"")
		out.escaped(ctx, pin.net)
		out.write("\" data-electrical-net=\"")
		out.escaped(ctx, display)
		out.write("\">")
	}
}

// svg.finishGroup
func finishGroup(out *Out) {
	out.write("</g>")
}

// svg.displayRef
func displayRef(out *Out, parts []Part, index int) {
	item := parts[index]
	n := 0
	i := 0
	for i <= index {
		if parts[i].kind == item.kind {
			n++
		}
		i++
	}
	if item.kind == 0 {
		out.write("U")
	} else if item.kind == 1 {
		out.write("C")
	} else if item.kind == 2 {
		out.write("R")
	} else {
		out.write("L")
	}
	out.decimal(n)
}

// svg.passive
func passive(out *Out, ctx *Ctx, index int, parts []Part, pins []Pin, points []Point) {
	item := parts[index]
	a := Point{x: 0, y: 0}
	b := a
	i := 0
	for i < len(pins) {
		pin := pins[i]
		if pin.part == index {
			if pin.number == 1 {
				a = points[i]
			} else {
				b = points[i]
			}
		}
		i++
	}
	x := floorDiv(a.x+b.x, 2)
	y := floorDiv(a.y+b.y, 2)
	instanceStart(out, ctx, item)
	out.write("<g transform=\"translate(")
	out.decimal(x)
	out.write(" ")
	out.decimal(y)
	out.write(")")
	if a.x == b.x {
		out.write(" rotate(90)")
	}
	out.write("\"><rect class=\"symbol-clear\" x=\"-20\" y=\"-9\" width=\"40\" height=\"18\"/>")
	drawSymbol(out, item.kind)
	finishGroup(out)
	if a.x == b.x {
		top := a.y
		bottom := b.y
		if top > bottom {
			top = b.y
			bottom = a.y
		}
		drawLine(out, x, top, x, y-20)
		drawLine(out, x, y+20, x, bottom)
		drawLabelStart(out, x+10, y+3, 0)
	} else {
		left := a.x
		right := b.x
		if left > right {
			left = b.x
			right = a.x
		}
		drawLine(out, left, y, x-20, y)
		drawLine(out, x+20, y, right, y)
		drawLabelStart(out, x, y-14, 1)
	}
	displayRef(out, parts, index)
	out.write(" ")
	out.escaped(ctx, item.value)
	drawLabelEnd(out)
	i = 0
	for i < len(pins) {
		pin := pins[i]
		if pin.part == index {
			pinStart(out, ctx, pin, pin.display, points[i])
			finishGroup(out)
		}
		i++
	}
	finishGroup(out)
}

// svg.chip
func chip(out *Out, ctx *Ctx, index int, parts []Part, pins []Pin, points []Point, pinout []Node) {
	instanceStart(out, ctx, parts[index])
	drawRect(out, 352, 20, 180, layoutHeight(points)-40)
	drawLabelStart(out, 442, 38, 1)
	displayRef(out, parts, index)
	out.write(" ")
	out.escaped(ctx, parts[index].family)
	drawLabelEnd(out)
	i := 0
	for i < len(pins) {
		pin := pins[i]
		if pin.part == index {
			point := points[i]
			pinStart(out, ctx, pin, pin.display, points[i])
			if !pin.nc {
				side := -1
				anchor := 0
				if point.x > 442 {
					side = 1
					anchor = 2
				}
				drawLine(out, point.x, point.y, point.x+side*40, point.y)
				drawLabel(out, ctx, point.x-side*8, point.y+4, anchor, pinoutLabel(ctx, pinout, pin.number))
				drawLabelStart(out, point.x+side*3, point.y-3, 1)
				out.decimal(pin.number)
				drawLabelEnd(out)
			}
			finishGroup(out)
		}
		i++
	}
	finishGroup(out)
}

// svg.portName
func portName(out *Out, ctx *Ctx, item Port) {
	if item.prefix.start != item.prefix.end {
		out.escaped(ctx, item.prefix)
		out.write("_")
	}
	out.escaped(ctx, item.name)
}

// svg.ports
func svgPorts(out *Out, ctx *Ctx, connections []Port) {
	i := 0
	for i < len(connections) {
		item := connections[i]
		out.write("<g class=\"port\" data-port=\"")
		portName(out, ctx, item)
		out.write("\" data-direction=\"")
		out.escaped(ctx, item.direction)
		out.write("\"><title>")
		portName(out, ctx, item)
		out.write("</title></g>")
		i++
	}
}

// svg.ground
func svgGround(ctx *Ctx, net Span) bool {
	return ctx.matches(net, "GND")
}

// svg.routes
func svgRoutes(out *Out, ctx *Ctx, segments []Segment, connections []Port) {
	i := 0
	for i < len(segments) {
		item := segments[i]
		out.write("<g class=\"wire\" data-net=\"")
		out.escaped(ctx, item.net)
		out.write("\">")
		drawLine(out, item.x1, item.y1, item.x2, item.y2)
		if item.terminal {
			if svgGround(ctx, item.net) {
				out.write("<g class=\"ground\">")
				drawLine(out, item.x2, item.y2, item.x2, item.y2+6)
				drawLine(out, item.x2-7, item.y2+6, item.x2+7, item.y2+6)
				drawLine(out, item.x2-4, item.y2+9, item.x2+4, item.y2+9)
				drawLine(out, item.x2-1, item.y2+12, item.x2+1, item.y2+12)
				finishGroup(out)
			} else if !external(ctx, item.net, connections) && railKind(ctx, item.net) == 0 {
				out.write("<g class=\"dangling-marker\">")
				drawLine(out, item.x2-4, item.y2-4, item.x2+4, item.y2+4)
				drawLine(out, item.x2-4, item.y2+4, item.x2+4, item.y2-4)
				finishGroup(out)
			} else {
				side := 1
				anchor := 0
				if item.x2 < 442 {
					side = -1
					anchor = 2
				}
				out.write("<g class=\"net-label\">")
				drawLabel(out, ctx, item.x2+side*12, item.y2+4, anchor, item.net)
				finishGroup(out)
			}
		}
		finishGroup(out)
		i++
	}
}

// svg.render
func render(ctx *Ctx, drawing *Drawing) []byte {
	parts := drawing.parts
	pins := drawing.pins
	points := layoutBuild(parts, pins)
	segments := routesBuild(ctx, parts, pins, points, drawing.connections)
	out := newOut(64 * 1024)
	out.write("<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 884 ")
	out.decimal(layoutHeight(points))
	out.write("\" width=\"884\" height=\"")
	out.decimal(layoutHeight(points))
	out.write("\" role=\"img\"><title>")
	out.escaped(ctx, title(ctx, drawing.nodes))
	out.write("</title><style>svg{background:#0d1117}text{font-family:Arial,sans-serif;font-size:11px;fill:#aaa;stroke:none}line,path{stroke:#4a9;stroke-width:1.5;fill:none}.chip{fill:#16213e;stroke:#4a9eff;stroke-width:2}.symbol rect,.symbol path,.symbol line{fill:none;stroke:#8888cc;stroke-width:1.5}.component>text{font-size:9px;fill:#888}.component>text:first-of-type{font-size:9px}.component:has(.chip)>text{fill:#4a9eff;font-size:12px;font-weight:bold}[data-pin]>line{stroke:#666}[data-pin]>text{font-size:12px}[data-pin]>text:last-child{font-size:9px;fill:#666}.symbol-clear{fill:#0d1117;stroke:none}.ground line{stroke:#d6bb24}.dangling-marker line{stroke:#666}.net-label text{fill:#4a9eff;font-size:11px;font-weight:bold}[data-nc]{display:none}</style><rect width=\"100%\" height=\"100%\" fill=\"#0d1117\"/>")
	svgRoutes(out, ctx, segments, drawing.connections)
	i := 0
	for i < len(parts) {
		if parts[i].kind == 0 {
			chip(out, ctx, i, parts, pins, points, drawing.pinout)
		}
		i++
	}
	i = 0
	for i < len(parts) {
		if parts[i].kind != 0 {
			passive(out, ctx, i, parts, pins, points)
		}
		i++
	}
	svgPorts(out, ctx, drawing.connections)
	out.write("</svg>")
	return out.bytes
}

// ── schematic.build and main ─────────────────────────────────────────

type Drawing struct {
	nodes       []Node
	parts       []Part
	pins        []Pin
	pinout      []Node
	connections []Port
}

func build(ctx *Ctx, nodes []Node, pinout []Node, iface []Node) (*Drawing, int) {
	sourceError := validateSource(ctx, nodes)
	if sourceError != 0 {
		return nil, sourceError
	}
	parts, code := collectParts(ctx, nodes)
	if code != 0 {
		return nil, code
	}
	pinoutError := pinoutCheck(ctx, pinout)
	if pinoutError != 0 {
		return nil, pinoutError
	}
	pins, code := collectPins(ctx, nodes, parts, pinout)
	if code != 0 {
		return nil, code
	}
	modelError := validateModel(ctx, nodes, parts, pins, pinout)
	if modelError != 0 {
		return nil, modelError
	}
	normalize(ctx, parts, pins)
	connections, code := portsCollect(ctx, nodes, iface)
	if code != 0 {
		return nil, code
	}
	portsError := portsValidate(ctx, connections, pins)
	if portsError != 0 {
		return nil, portsError
	}
	return &Drawing{
		nodes:       nodes,
		parts:       parts,
		pins:        pins,
		pinout:      pinout,
		connections: connections,
	}, 0
}

// itoa renders an int for diagnostics only; the SVG uses Out.decimal.
func itoa(value int) string {
	var buffer [24]byte
	negative := value < 0
	var magnitude uint64
	if negative {
		magnitude = uint64(-(value + 1)) + 1
	} else {
		magnitude = uint64(value)
	}
	at := len(buffer)
	for {
		at--
		buffer[at] = byte('0' + magnitude%10)
		magnitude /= 10
		if magnitude == 0 {
			break
		}
	}
	if negative {
		at--
		buffer[at] = '-'
	}
	return string(buffer[at:])
}

func run(ctx *Ctx) ([]byte, int) {
	nodes, code := parse(ctx, 0)
	if code != 0 {
		return nil, code
	}
	pinout, code := parse(ctx, 1)
	if code != 0 {
		return nil, code
	}
	iface, code := parse(ctx, 2)
	if code != 0 {
		return nil, code
	}
	drawing, code := build(ctx, nodes, pinout, iface)
	if code != 0 {
		return nil, code
	}
	return render(ctx, drawing), 0
}

func main() {
	args := os.Args
	if len(args) != 5 {
		name := "schematic"
		if len(args) > 0 {
			name = args[0]
		}
		os.Stderr.WriteString("usage: " + name + " <module.sexp> <pinout.sexp> <interface.sexp> <output.svg>\n")
		os.Exit(2)
	}
	docs := make([][]byte, 0, 3)
	for _, path := range args[1:4] {
		bytes, err := os.ReadFile(path)
		if err != nil {
			os.Stderr.WriteString("schematic: " + path + ": " + err.Error() + "\n")
			os.Exit(2)
		}
		docs = append(docs, bytes)
	}
	ctx := &Ctx{docs: docs}
	svg, code := run(ctx)
	if code != 0 {
		// The mylang guest reports its first located issue as the printed
		// result and as the process status; mirror that exactly so the
		// malformed-input differential can compare the two implementations.
		// Nothing goes to stderr and no output file is written.
		os.Stdout.WriteString(itoa(code) + "\n")
		os.Exit(code)
	}
	if err := os.WriteFile(args[4], svg, 0666); err != nil {
		os.Stderr.WriteString("schematic: " + args[4] + ": " + err.Error() + "\n")
		os.Exit(2)
	}
}
