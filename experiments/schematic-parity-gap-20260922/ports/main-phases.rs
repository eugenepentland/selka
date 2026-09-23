//! Native Rust implementation of the mylang schematic-to-SVG pipeline.
//!
//! This is a faithful port of `src/schematic/guest/*.my` (module `main` and the
//! modules it imports) with the host byte interface replaced by whole-document
//! reads. It performs the same parse, validation, model construction, net
//! normalization, placement, routing and SVG serialization, in the same order,
//! with the same integer arithmetic, so its output is byte-identical to the
//! mylang arm of `experiments/full-svg-benchmark`.
//!
//! Usage: `rust-o3 <module.sexp> <pinout.sexp> <interface.sexp> <output.svg>`

use std::env;
use std::fs;
use std::io::Write;
use std::process;

// ── spans and documents ──────────────────────────────────────────────

#[derive(Clone, Copy, PartialEq, Eq)]
struct Span {
    file: usize,
    start: usize,
    end: usize,
}

const EMPTY: Span = Span { file: 0, start: 0, end: 0 };

impl Span {
    #[inline]
    fn len(&self) -> usize {
        self.end - self.start
    }
    #[inline]
    fn is_empty(&self) -> bool {
        self.end == self.start
    }
}

struct Ctx {
    docs: Vec<Vec<u8>>,
}

impl Ctx {
    #[inline]
    fn byte(&self, file: usize, position: usize) -> u8 {
        self.docs[file][position]
    }

    /// `text.equal`
    fn equal(&self, a: Span, b: Span) -> bool {
        if a.len() != b.len() {
            return false;
        }
        let mut i = 0;
        while i < a.len() {
            if self.byte(a.file, a.start + i) != self.byte(b.file, b.start + i) {
                return false;
            }
            i += 1;
        }
        true
    }

    /// `text.matches`
    fn matches(&self, a: Span, b: &[u8]) -> bool {
        if a.len() != b.len() {
            return false;
        }
        let mut i = 0;
        while i < a.len() {
            if self.byte(a.file, a.start + i) as i64 != b[i] as i64 {
                return false;
            }
            i += 1;
        }
        true
    }

    /// `text.number`
    fn number(&self, a: Span) -> i64 {
        let mut value: i64 = 0;
        let mut i = a.start;
        if i == a.end {
            return -1;
        }
        while i < a.end {
            let c = self.byte(a.file, i) as i64;
            if c < 48 || c > 57 {
                return -1;
            }
            if value > 1000000 {
                return -1;
            }
            value = value * 10 + c - 48;
            i += 1;
        }
        value
    }

    /// `text.identifier`
    fn identifier(&self, a: Span) -> bool {
        if a.is_empty() || a.len() > 64 {
            return false;
        }
        let mut i = a.start;
        while i < a.end {
            let ch = self.byte(a.file, i);
            if ch < 33 || ch == 92 {
                return false;
            }
            i += 1;
        }
        true
    }

    /// `text.folded`
    fn folded(&self, a: Span, b: Span) -> bool {
        if a.len() != b.len() {
            return false;
        }
        let mut i = 0;
        while i < a.len() {
            if lower(self.byte(a.file, a.start + i)) != lower(self.byte(b.file, b.start + i)) {
                return false;
            }
            i += 1;
        }
        true
    }
}

#[inline]
fn lower(ch: u8) -> u8 {
    if (65..=90).contains(&ch) {
        ch + 32
    } else {
        ch
    }
}

// ── output buffer ────────────────────────────────────────────────────

struct Out {
    bytes: Vec<u8>,
}

impl Out {
    fn new(capacity: usize) -> Out {
        Out {
            bytes: Vec::with_capacity(capacity),
        }
    }
    #[inline]
    fn put(&mut self, value: u8) {
        self.bytes.push(value);
    }
    #[inline]
    fn write(&mut self, text: &[u8]) {
        self.bytes.extend_from_slice(text);
    }
    /// `text.decimal`
    fn decimal(&mut self, value: i64) {
        let mut buffer = [0u8; 24];
        let negative = value < 0;
        let mut magnitude = if negative {
            (value as i128).unsigned_abs() as u64
        } else {
            value as u64
        };
        let mut at = buffer.len();
        loop {
            at -= 1;
            buffer[at] = b'0' + (magnitude % 10) as u8;
            magnitude /= 10;
            if magnitude == 0 {
                break;
            }
        }
        if negative {
            at -= 1;
            buffer[at] = b'-';
        }
        self.bytes.extend_from_slice(&buffer[at..]);
    }
    /// `text.escaped`
    fn escaped(&mut self, ctx: &Ctx, a: Span) {
        let mut i = a.start;
        while i < a.end {
            let mut c = ctx.byte(a.file, i);
            i += 1;
            if c == 92 && i < a.end {
                c = ctx.byte(a.file, i);
                i += 1;
                if c == 110 {
                    c = 10;
                } else if c == 114 {
                    c = 13;
                } else if c == 116 {
                    c = 9;
                }
            }
            match c {
                9 => self.write(b"&#9;"),
                10 => self.write(b"&#10;"),
                13 => self.write(b"&#13;"),
                38 => self.write(b"&amp;"),
                60 => self.write(b"&lt;"),
                62 => self.write(b"&gt;"),
                34 => self.write(b"&quot;"),
                _ => self.put(c),
            }
        }
    }
}

// ── sexpr ────────────────────────────────────────────────────────────

#[derive(Clone, Copy, PartialEq, Eq)]
enum Kind {
    List,
    Atom,
    Str,
}

#[derive(Clone, Copy)]
struct Node {
    kind: Kind,
    span: Span,
    next: usize,
}

/// `sexpr.at`: an out-of-range index is an empty atom whose `next` ends the list.
#[inline]
fn at(nodes: &[Node], index: i64) -> Node {
    if index < 0 || index as usize >= nodes.len() {
        return Node {
            kind: Kind::Atom,
            span: EMPTY,
            next: nodes.len(),
        };
    }
    nodes[index as usize]
}

/// `sexpr.form`
fn form(ctx: &Ctx, nodes: &[Node], index: i64, name: &[u8]) -> bool {
    let item = at(nodes, index);
    if item.kind != Kind::List || item.next as i64 == index + 1 {
        return false;
    }
    ctx.matches(at(nodes, index + 1).span, name)
}

/// `sexpr.parse`
fn parse(ctx: &Ctx, file: usize) -> Result<Vec<Node>, i64> {
    let src = &ctx.docs[file];
    let size = src.len();
    let mut nodes: Vec<Node> = Vec::with_capacity(1 + size / 8);
    let mut stack: Vec<usize> = Vec::with_capacity(16);
    let mut depth: usize = 0;
    let mut p: usize = 0;
    nodes.push(Node {
        kind: Kind::List,
        span: Span {
            file,
            start: 0,
            end: size,
        },
        next: 0,
    });
    while p < size {
        let c = src[p];
        if c == 32 || c == 9 || c == 10 || c == 13 {
            p += 1;
        } else if c == 59 {
            while p < size && src[p] != 10 {
                p += 1;
            }
        } else if c == 41 {
            if depth == 0 {
                return Err(1);
            }
            depth -= 1;
            let open = stack[depth];
            nodes[open].next = nodes.len();
            p += 1;
        } else {
            let index = nodes.len();
            let start = p;
            if index == 16384 {
                return Err(5);
            }
            let mut kind = Kind::Atom;
            if c == 40 {
                if depth == 128 {
                    return Err(2);
                }
                if depth == stack.len() {
                    stack.push(index);
                } else {
                    stack[depth] = index;
                }
                depth += 1;
                kind = Kind::List;
                p += 1;
            } else if c == 34 {
                kind = Kind::Str;
                p += 1;
                let mut closed = false;
                while p < size && !closed {
                    let ch = src[p];
                    p += 1;
                    if ch == 92 {
                        if p == size {
                            return Err(3);
                        }
                        let escape = src[p];
                        if escape != 92 && escape != 34 && escape != 110 && escape != 114 && escape != 116
                        {
                            return Err(6);
                        }
                        p += 1;
                    } else if ch == 34 {
                        closed = true;
                    }
                }
                if !closed {
                    return Err(3);
                }
            } else {
                let mut scanning = true;
                while p < size && scanning {
                    let ch = src[p];
                    if ch == 40 || ch == 41 || ch == 32 || ch == 9 || ch == 10 || ch == 13 || ch == 59
                    {
                        scanning = false;
                    } else {
                        p += 1;
                    }
                }
            }
            let mut span = Span {
                file,
                start,
                end: p,
            };
            if kind == Kind::Str {
                span.start = start + 1;
                span.end = p - 1;
            }
            nodes.push(Node {
                kind,
                span,
                next: index + 1,
            });
        }
    }
    if depth != 0 {
        return Err(4);
    }
    nodes[0].next = nodes.len();
    Ok(nodes)
}

// ── circuit model ────────────────────────────────────────────────────

#[derive(Clone, Copy)]
struct Part {
    node: i64,
    reference: Span,
    family: Span,
    value: Span,
    kind: i64,
    pin1: i64,
    pin2: i64,
}

#[derive(Clone, Copy)]
struct Pin {
    part: usize,
    number: i64,
    net: Span,
    nc: bool,
    display: Span,
    net_id: i64,
    display_id: i64,
    raw_rail: i64,
    rail: i64,
    decoupling: bool,
}

/// `circuit.body`
fn body(ctx: &Ctx, nodes: &[Node]) -> i64 {
    let mut i: i64 = 1;
    while (i as usize) < nodes.len() {
        if form(ctx, nodes, i, b"design-block") {
            return i;
        }
        if form(ctx, nodes, i, b"defmodule") {
            i += 1;
        } else {
            i = at(nodes, i).next as i64;
        }
    }
    -1
}

/// `circuit.title`
fn title(ctx: &Ctx, nodes: &[Node]) -> Span {
    let b = body(ctx, nodes);
    if b < 0 {
        return EMPTY;
    }
    at(nodes, b + 2).span
}

/// `circuit.kind`
fn part_kind(ctx: &Ctx, family: Span) -> i64 {
    if ctx.matches(family, b"cap-0402") || ctx.matches(family, b"cap-0603") {
        return 1;
    }
    if ctx.matches(family, b"res-0402") {
        return 2;
    }
    if ctx.matches(family, b"ind-0402") {
        return 3;
    }
    0
}

/// `circuit.collectParts`
fn collect_parts(ctx: &Ctx, nodes: &[Node]) -> Result<Vec<Part>, i64> {
    let mut out: Vec<Part> = Vec::new();
    let b = body(ctx, nodes);
    if b < 0 {
        return Err(10);
    }
    let mut i = b + 3;
    while i < at(nodes, b).next as i64 {
        if form(ctx, nodes, i, b"instance") {
            let reference = at(nodes, i + 2);
            let spec = at(nodes, i + 3);
            if i + 3 >= at(nodes, i).next as i64 {
                return Err(11);
            }
            if !ctx.identifier(reference.span) || reference.kind != Kind::Str {
                return Err(11);
            }
            let mut family = spec.span;
            let mut value = EMPTY;
            if spec.kind == Kind::List {
                family = at(nodes, i + 4).span;
                value = at(nodes, i + 5).span;
            }
            if out.len() == 128 {
                return Err(5);
            }
            let mut j = 0;
            while j < out.len() {
                if ctx.equal(out[j].reference, reference.span) {
                    return Err(12);
                }
                j += 1;
            }
            out.push(Part {
                node: i,
                reference: reference.span,
                family,
                value,
                kind: part_kind(ctx, family),
                pin1: -1,
                pin2: -1,
            });
        }
        i = at(nodes, i).next as i64;
    }
    Ok(out)
}

/// `circuit.label`
fn pinout_label(ctx: &Ctx, pinout: &[Node], number: i64) -> Span {
    let mut i: i64 = 1;
    while (i as usize) < pinout.len() {
        if form(ctx, pinout, i, b"pin") && ctx.number(at(pinout, i + 2).span) == number {
            return at(pinout, i + 3).span;
        }
        i += 1;
    }
    EMPTY
}

/// `circuit.collectPins`
fn collect_pins(
    ctx: &Ctx,
    nodes: &[Node],
    parts: &[Part],
    pinout: &[Node],
) -> Result<Vec<Pin>, i64> {
    let mut out: Vec<Pin> = Vec::new();
    let mut part = 0;
    while part < parts.len() {
        let item = parts[part];
        let mut f = at(nodes, item.node + 3).next as i64;
        while f < at(nodes, item.node).next as i64 {
            let nc = form(ctx, nodes, f, b"nc-ok");
            if form(ctx, nodes, f, b"pin") || nc {
                let mut netindex = f + 2;
                while netindex < at(nodes, f).next as i64
                    && at(nodes, netindex).kind != Kind::Str
                {
                    netindex = at(nodes, netindex).next as i64;
                }
                if netindex == at(nodes, f).next as i64 || netindex == f + 2 {
                    return Err(13);
                }
                let net = at(nodes, netindex).span;
                if (!nc && !ctx.identifier(net)) || net.is_empty() {
                    return Err(13);
                }
                let mut p = f + 2;
                while p < netindex {
                    let number = ctx.number(at(nodes, p).span);
                    let mut valid = number == 1 || number == 2;
                    if item.kind == 0 {
                        let named = pinout_label(ctx, pinout, number);
                        valid = named.end > named.start;
                    }
                    if !valid {
                        return Err(14);
                    }
                    let mut j = 0;
                    while j < out.len() {
                        let previous = out[j];
                        if previous.part == part && previous.number == number {
                            return Err(15);
                        }
                        j += 1;
                    }
                    if out.len() == 1024 {
                        return Err(5);
                    }
                    out.push(Pin {
                        part,
                        number,
                        net,
                        nc,
                        display: net,
                        net_id: -1,
                        display_id: -1,
                        raw_rail: 0,
                        rail: 0,
                        decoupling: false,
                    });
                    p = at(nodes, p).next as i64;
                }
            }
            f = at(nodes, f).next as i64;
        }
        part += 1;
    }
    Ok(out)
}

/// `circuit.displayNet`
fn display_net(ctx: &Ctx, net: Span, parts: &[Part], pins: &[Pin]) -> Span {
    let mut last: i64 = -1;
    let mut previous: i64 = -1;
    let mut i = net.start;
    while i < net.end {
        if ctx.byte(net.file, i) == 46 {
            previous = last;
            last = i as i64;
        }
        i += 1;
    }
    if previous <= net.start as i64 || last <= previous + 1 || last + 1 == net.end as i64 {
        return net;
    }
    let mut base = net;
    base.end = previous as usize;
    let mut reference = net;
    reference.start = previous as usize + 1;
    reference.end = last as usize;
    let mut number_span = net;
    number_span.start = last as usize + 1;
    let number = ctx.number(number_span);
    let mut trunk = false;
    let mut named_host = false;
    let mut i = 0;
    while i < pins.len() {
        let pin = pins[i];
        if !pin.nc {
            if ctx.equal(pin.net, base) {
                trunk = true;
            }
            if pin.number == number
                && ctx.equal(pin.net, net)
                && ctx.equal(parts[pin.part].reference, reference)
            {
                named_host = true;
            }
        }
        i += 1;
    }
    if trunk && named_host {
        return base;
    }
    net
}

/// `circuit.railKind` / `layout_graph.rail`
fn rail_kind(ctx: &Ctx, span: Span) -> i64 {
    if ctx.matches(span, b"GND") {
        return 1;
    }
    if span.len() >= 2
        && ctx.byte(span.file, span.start) == 86
        && ctx.byte(span.file, span.start + 1) == 95
    {
        return 2;
    }
    0
}

/// `circuit.normalize`
fn normalize(ctx: &Ctx, parts: &mut [Part], pins: &mut [Pin]) {
    let mut i = 0;
    while i < pins.len() {
        pins[i].display = display_net(ctx, pins[i].net, parts, pins);
        pins[i].raw_rail = rail_kind(ctx, pins[i].net);
        pins[i].rail = rail_kind(ctx, pins[i].display);
        if pins[i].number == 1 {
            parts[pins[i].part].pin1 = i as i64;
        }
        if pins[i].number == 2 {
            parts[pins[i].part].pin2 = i as i64;
        }
        let mut raw_id: i64 = -1;
        let mut j = 0;
        while j < i {
            if raw_id < 0 && ctx.equal(pins[j].net, pins[i].net) {
                raw_id = pins[j].net_id;
            }
            j += 1;
        }
        if raw_id < 0 {
            raw_id = i as i64;
        }
        pins[i].net_id = raw_id;
        i += 1;
    }
    let mut i = 0;
    while i < pins.len() {
        let mut display_id: i64 = -1;
        let mut j = 0;
        while j < pins.len() {
            if display_id < 0 && ctx.equal(pins[j].net, pins[i].display) {
                display_id = pins[j].net_id;
            }
            j += 1;
        }
        let mut j = 0;
        while j < i {
            if display_id < 0 && ctx.equal(pins[j].display, pins[i].display) {
                display_id = pins[j].display_id;
            }
            j += 1;
        }
        if display_id < 0 {
            display_id = pins.len() as i64 + i as i64;
        }
        pins[i].display_id = display_id;
        i += 1;
    }
    let mut i = 0;
    while i < pins.len() {
        let pin = pins[i];
        if pin.raw_rail == 1 && parts[pin.part].kind == 1 {
            let mut other_index = parts[pin.part].pin1;
            if other_index == i as i64 {
                other_index = parts[pin.part].pin2;
            }
            if other_index >= 0 {
                let other = pins[other_index as usize];
                pins[i].decoupling = other.rail == 2
                    && other.raw_rail != 1
                    && other.display_id != other.net_id;
            }
        }
        i += 1;
    }
}

// ── validate ─────────────────────────────────────────────────────────

/// `validate.source`
fn validate_source(ctx: &Ctx, nodes: &[Node]) -> i64 {
    let mut i: i64 = 1;
    let mut modules = 0;
    let mut blocks = 0;
    while (i as usize) < nodes.len() {
        if form(ctx, nodes, i, b"defmodule") {
            modules += 1;
            let params = at(nodes, i + 3);
            if modules != 1 || params.kind != Kind::List || params.next as i64 != i + 4 {
                return 16;
            }
            let mut f = i + 4;
            while f < at(nodes, i).next as i64 {
                if at(nodes, f).kind == Kind::Str || form(ctx, nodes, f, b"implements") {
                    // permitted
                } else if form(ctx, nodes, f, b"design-block") {
                    blocks += 1;
                    if blocks != 1 || at(nodes, f + 2).kind != Kind::Str {
                        return 16;
                    }
                    let mut child = f + 3;
                    while child < at(nodes, f).next as i64 {
                        if !form(ctx, nodes, child, b"instance")
                            && !metadata(ctx, nodes, child)
                        {
                            return 17;
                        }
                        child = at(nodes, child).next as i64;
                    }
                } else {
                    return 17;
                }
                f = at(nodes, f).next as i64;
            }
        } else if !form(ctx, nodes, i, b"import") {
            return 17;
        }
        i = at(nodes, i).next as i64;
    }
    if modules != 1 || blocks != 1 {
        return 16;
    }
    0
}

/// `validate.metadata`
fn metadata(ctx: &Ctx, nodes: &[Node], i: i64) -> bool {
    for name in [
        b"net-envelope".as_slice(),
        b"port",
        b"port-group",
        b"net-class",
        b"pcb-plan",
        b"rough",
        b"note",
    ] {
        if form(ctx, nodes, i, name) {
            return true;
        }
    }
    false
}

/// `validate.pinoutCheck`
fn pinout_check(ctx: &Ctx, nodes: &[Node]) -> i64 {
    if !form(ctx, nodes, 1, b"pinout")
        || at(nodes, 1).next != nodes.len()
        || at(nodes, 3).kind != Kind::Str
    {
        return 18;
    }
    let mut count = 0;
    let mut i: i64 = 4;
    while i < at(nodes, 1).next as i64 {
        let number = ctx.number(at(nodes, i + 2).span);
        if !form(ctx, nodes, i, b"pin")
            || at(nodes, i).next as i64 != i + 4
            || number < 1
            || number > 41
            || at(nodes, i + 3).kind != Kind::Str
            || !ctx.identifier(at(nodes, i + 3).span)
        {
            return 18;
        }
        let mut j: i64 = 4;
        while j < i {
            if ctx.number(at(nodes, j + 2).span) == number {
                return 18;
            }
            j = at(nodes, j).next as i64;
        }
        count += 1;
        i = at(nodes, i).next as i64;
    }
    if count != 41 {
        return 18;
    }
    0
}

/// `validate.fields`
fn fields(ctx: &Ctx, nodes: &[Node], item: Part) -> i64 {
    let spec = at(nodes, item.node + 3);
    if item.kind != 0
        && (spec.kind != Kind::List
            || (spec.next as i64) < item.node + 6
            || at(nodes, item.node + 5).kind != Kind::Str)
    {
        return 19;
    }
    if item.kind == 0 && spec.kind != Kind::Atom {
        return 19;
    }
    let mut f = spec.next as i64;
    while f < at(nodes, item.node).next as i64 {
        if !form(ctx, nodes, f, b"pin")
            && !form(ctx, nodes, f, b"nc-ok")
            && !form(ctx, nodes, f, b"id")
            && !form(ctx, nodes, f, b"decouples")
        {
            return 17;
        }
        if form(ctx, nodes, f, b"nc-ok") && item.kind != 0 {
            return 13;
        }
        if form(ctx, nodes, f, b"pin") || form(ctx, nodes, f, b"nc-ok") {
            let mut j = f + 2;
            while j < at(nodes, f).next as i64 && at(nodes, j).kind == Kind::Atom {
                j += 1;
            }
            if j == f + 2 || at(nodes, j).kind != Kind::Str {
                return 13;
            }
            if form(ctx, nodes, f, b"nc-ok")
                && (j != f + 3 || at(nodes, f).next as i64 != j + 1)
            {
                return 13;
            }
            j += 1;
            while j < at(nodes, f).next as i64 {
                if !form(ctx, nodes, j, b"i-typ") && !form(ctx, nodes, j, b"i-max") {
                    return 17;
                }
                j = at(nodes, j).next as i64;
            }
        }
        f = at(nodes, f).next as i64;
    }
    0
}

/// `validate.model`
fn validate_model(
    ctx: &Ctx,
    nodes: &[Node],
    parts: &[Part],
    pins: &[Pin],
    pinout: &[Node],
) -> i64 {
    let schema = pinout_check(ctx, pinout);
    if schema != 0 {
        return schema;
    }
    let mut chips = 0;
    let mut p = 0;
    while p < parts.len() {
        let item = parts[p];
        let field_error = fields(ctx, nodes, item);
        if field_error != 0 {
            return field_error;
        }
        if item.kind == 0 {
            chips += 1;
            if !ctx.folded(item.family, at(pinout, 3).span) {
                return 19;
            }
        }
        let mut count = 0;
        let mut j = 0;
        while j < pins.len() {
            if pins[j].part == p {
                count += 1;
            }
            j += 1;
        }
        if (item.kind == 0 && count != 41) || (item.kind != 0 && count != 2) {
            return 20;
        }
        p += 1;
    }
    if chips != 1 {
        return 19;
    }
    0
}

// ── ports ────────────────────────────────────────────────────────────

#[derive(Clone, Copy)]
struct Port {
    prefix: Span,
    name: Span,
    direction: Span,
}

/// `ports.collect`
fn ports_collect(ctx: &Ctx, nodes: &[Node], lanes: &[Node]) -> Result<Vec<Port>, i64> {
    let mut out: Vec<Port> = Vec::new();
    if !form(ctx, lanes, 1, b"interface") || at(lanes, 1).next != lanes.len() {
        return Err(21);
    }
    let b = body(ctx, nodes);
    let mut i = b + 3;
    while i < at(nodes, b).next as i64 {
        if form(ctx, nodes, i, b"port") {
            let name = at(nodes, i + 2);
            let direction = at(nodes, i + 3);
            if i + 3 >= at(nodes, i).next as i64
                || name.kind != Kind::Str
                || !ctx.identifier(name.span)
                || !direction_ok(ctx, direction.span)
            {
                return Err(21);
            }
            if out.len() == 32 {
                return Err(21);
            }
            out.push(Port {
                prefix: EMPTY,
                name: name.span,
                direction: direction.span,
            });
        } else if form(ctx, nodes, i, b"port-group") {
            let prefix = at(nodes, i + 2).span;
            if !ctx.identifier(prefix) || !ctx.equal(at(nodes, i + 3).span, at(lanes, 3).span) {
                return Err(21);
            }
            let mut rename = i + 4;
            while rename < at(nodes, i).next as i64 {
                if !form(ctx, nodes, rename, b"rename")
                    || at(nodes, rename).next as i64 != rename + 4
                    || at(nodes, rename + 3).kind != Kind::Str
                {
                    return Err(21);
                }
                let mut found = false;
                let mut lane: i64 = 5;
                while lane < at(lanes, 1).next as i64 {
                    if ctx.equal(at(nodes, rename + 2).span, at(lanes, lane + 2).span) {
                        found = true;
                    }
                    lane = at(lanes, lane).next as i64;
                }
                if !found {
                    return Err(21);
                }
                rename = at(nodes, rename).next as i64;
            }
            let mut lane: i64 = 5;
            while lane < at(lanes, 1).next as i64 {
                if !form(ctx, lanes, lane, b"signal")
                    || (at(lanes, lane).next as i64) < lane + 4
                    || !direction_ok(ctx, at(lanes, lane + 3).span)
                {
                    return Err(21);
                }
                let mut label = at(lanes, lane + 2).span;
                let original = label;
                let mut pre = prefix;
                let mut renamed = false;
                let mut rename = i + 4;
                while rename < at(nodes, i).next as i64 {
                    if ctx.equal(at(nodes, rename + 2).span, original) {
                        if renamed {
                            return Err(21);
                        }
                        renamed = true;
                        label = at(nodes, rename + 3).span;
                        pre = EMPTY;
                    }
                    rename = at(nodes, rename).next as i64;
                }
                if !ctx.identifier(label) || out.len() == 32 {
                    return Err(21);
                }
                out.push(Port {
                    prefix: pre,
                    name: label,
                    direction: at(lanes, lane + 3).span,
                });
                lane = at(lanes, lane).next as i64;
            }
        }
        i = at(nodes, i).next as i64;
    }
    Ok(out)
}

/// `ports.direction`
fn direction_ok(ctx: &Ctx, span: Span) -> bool {
    ctx.matches(span, b"in") || ctx.matches(span, b"out") || ctx.matches(span, b"bidi")
}

/// `ports.size`
fn port_size(item: Port) -> i64 {
    let mut n = (item.name.end - item.name.start) as i64;
    if item.prefix.start != item.prefix.end {
        n += (item.prefix.end - item.prefix.start) as i64 + 1;
    }
    n
}

/// `ports.byteAt`
fn port_byte(ctx: &Ctx, item: Port, index: i64) -> u8 {
    let n = (item.prefix.end - item.prefix.start) as i64;
    if n == 0 {
        return ctx.byte(item.name.file, (item.name.start as i64 + index) as usize);
    }
    if index < n {
        return ctx.byte(item.prefix.file, (item.prefix.start as i64 + index) as usize);
    }
    if index == n {
        return 95;
    }
    ctx.byte(
        item.name.file,
        (item.name.start as i64 + index - n - 1) as usize,
    )
}

/// `ports.equal`
fn port_equal(ctx: &Ctx, a: Port, b: Port) -> bool {
    if port_size(a) != port_size(b) {
        return false;
    }
    let mut i: i64 = 0;
    while i < port_size(a) {
        if port_byte(ctx, a, i) != port_byte(ctx, b, i) {
            return false;
        }
        i += 1;
    }
    true
}

/// `ports.validate`
fn ports_validate(ctx: &Ctx, connections: &[Port], pins: &[Pin]) -> i64 {
    let mut i = 0;
    while i < connections.len() {
        let item = connections[i];
        let mut j = 0;
        while j < i {
            if port_equal(ctx, item, connections[j]) {
                return 22;
            }
            j += 1;
        }
        let mut found = false;
        let mut j = 0;
        while j < pins.len() {
            let pin = pins[j];
            let candidate = Port {
                prefix: EMPTY,
                name: pin.net,
                direction: EMPTY,
            };
            if !pin.nc && port_equal(ctx, item, candidate) {
                found = true;
            }
            j += 1;
        }
        if !found {
            if env::var_os("RUST_SCHEMATIC_DEBUG").is_some() {
                eprintln!(
                    "connection {} not matched by any pin; pins:",
                    debug_span(ctx, item.name)
                );
                let mut k = 0;
                while k < pins.len() {
                    eprintln!(
                        "  pin part={} number={} nc={} net={} display={}",
                        pins[k].part,
                        pins[k].number,
                        pins[k].nc,
                        debug_span(ctx, pins[k].net),
                        debug_span(ctx, pins[k].display)
                    );
                    k += 1;
                }
            }
            return 23;
        }
        i += 1;
    }
    0
}

fn debug_span(ctx: &Ctx, span: Span) -> String {
    String::from_utf8_lossy(&ctx.docs[span.file][span.start..span.end]).into_owned()
}

// ── net graph ────────────────────────────────────────────────────────

#[derive(Clone, Copy)]
struct Net {
    // `span` is carried exactly as the guest's Net carries it; nothing reads it
    // after the graph is built, and it is kept so the record stays comparable.
    #[allow(dead_code)]
    span: Span,
    identity: i64,
    group: i64,
    owner: i64,
    distance: i64,
}

#[derive(Clone, Copy)]
struct Edge {
    a: usize,
    b: usize,
}

/// `layout_graph.findId`
fn find_id(nets: &[Net], identity: i64) -> i64 {
    let mut i = 0;
    while i < nets.len() {
        if nets[i].identity == identity {
            return i as i64;
        }
        i += 1;
    }
    -1
}

/// `layout_graph.build`
fn graph_build(parts: &[Part], pins: &[Pin]) -> Vec<Net> {
    let mut nets: Vec<Net> = Vec::new();
    let mut edges: Vec<Edge> = Vec::new();
    let mut i = 0;
    while i < pins.len() {
        let pin = pins[i];
        if !pin.nc {
            let mut present = false;
            let mut n = 0;
            while n < nets.len() {
                if nets[n].identity == pin.display_id {
                    present = true;
                }
                n += 1;
            }
            if !present {
                nets.push(Net {
                    span: pin.display,
                    identity: pin.display_id,
                    group: nets.len() as i64,
                    owner: -1,
                    distance: 4096,
                });
            }
        }
        i += 1;
    }
    let mut part = 0;
    while part < parts.len() {
        if parts[part].kind != 0 {
            let ai = parts[part].pin1;
            let bi = parts[part].pin2;
            if ai >= 0
                && bi >= 0
                && !pins[ai as usize].nc
                && !pins[bi as usize].nc
                && pins[ai as usize].rail == 0
                && pins[bi as usize].rail == 0
            {
                let mut na: i64 = -1;
                let mut nb: i64 = -1;
                let mut ga: i64 = -1;
                let mut gb: i64 = -1;
                let mut i = 0;
                while i < nets.len() {
                    let item = nets[i];
                    if item.identity == pins[ai as usize].display_id {
                        ga = item.group;
                        na = i as i64;
                    }
                    if item.identity == pins[bi as usize].display_id {
                        gb = item.group;
                        nb = i as i64;
                    }
                    i += 1;
                }
                if na >= 0 && nb >= 0 {
                    edges.push(Edge {
                        a: na as usize,
                        b: nb as usize,
                    });
                }
                if ga >= 0 && gb >= 0 && ga != gb {
                    let mut i = 0;
                    while i < nets.len() {
                        if nets[i].group == gb {
                            nets[i].group = ga;
                        }
                        i += 1;
                    }
                }
            }
        }
        part += 1;
    }
    let mut i = 0;
    while i < pins.len() {
        let pin = pins[i];
        if !pin.nc && parts[pin.part].kind == 0 {
            let mut n = 0;
            while n < nets.len() {
                if nets[n].owner < 0 && nets[n].identity == pin.display_id {
                    nets[n].owner = i as i64;
                    nets[n].distance = 0;
                }
                n += 1;
            }
        }
        i += 1;
    }
    let mut changed = true;
    let mut passes = 0;
    while changed && passes < 128 {
        changed = false;
        let mut i = 0;
        while i < edges.len() {
            let edge = edges[i];
            // Records are values: these are snapshots taken before any update.
            let head = nets[edge.a];
            let tail = nets[edge.b];
            if head.distance + 1 < tail.distance
                || (head.owner >= 0
                    && tail.owner >= 0
                    && head.distance + 1 == tail.distance
                    && pins[head.owner as usize].number < pins[tail.owner as usize].number)
            {
                nets[edge.b].owner = head.owner;
                nets[edge.b].distance = head.distance + 1;
                changed = true;
            }
            if tail.distance + 1 < head.distance
                || (head.owner >= 0
                    && tail.owner >= 0
                    && tail.distance + 1 == head.distance
                    && pins[tail.owner as usize].number < pins[head.owner as usize].number)
            {
                nets[edge.a].owner = tail.owner;
                nets[edge.a].distance = tail.distance + 1;
                changed = true;
            }
            i += 1;
        }
        passes += 1;
    }
    nets
}

// ── layout ───────────────────────────────────────────────────────────

#[derive(Clone, Copy)]
struct Point {
    x: i64,
    y: i64,
}

#[derive(Clone, Copy)]
struct Row {
    index: usize,
    group: i64,
    height: i64,
    rail: i64,
    side: i64,
    y: i64,
}

/// Floor division, matching mylang's `//` on integers.
#[inline]
fn floor_div(a: i64, b: i64) -> i64 {
    let q = a / b;
    if (a % b != 0) && ((a < 0) != (b < 0)) {
        q - 1
    } else {
        q
    }
}

/// `layout.pinGroup`
fn pin_group(pin: Pin, nets: &[Net]) -> i64 {
    let id = find_id(nets, pin.display_id);
    if id < 0 {
        return -1;
    }
    nets[id as usize].group
}

/// `layout.rowHeight`
fn row_height(pin: Pin, passive_counts: &[i64], bridge_nets: &[bool]) -> i64 {
    if pin.rail != 0 {
        return 40;
    }
    let count = passive_counts[pin.net_id as usize];
    if count > 1 {
        if !bridge_nets[pin.net_id as usize] {
            return count * 40;
        }
        return 56 + (count - 1) * 40;
    }
    56
}

/// `layout.collectRows`
fn collect_rows(parts: &[Part], pins: &[Pin], nets: &[Net]) -> Vec<Row> {
    let mut out: Vec<Row> = Vec::new();
    let mut counts = [0i64; 130];
    let mut offsets = [0i64; 130];
    let mut cursor = [0i64; 130];
    let mut ordered = vec![-1i64; pins.len()];
    let mut passive_counts = vec![0i64; pins.len()];
    let mut bridge_nets = vec![false; pins.len()];
    let mut hub_nets = vec![false; pins.len()];
    let mut hub_count = 0;
    let mut i = 0;
    while i < pins.len() {
        let pin = pins[i];
        if parts[pin.part].kind == 0 {
            if !pin.nc && pin.number >= 1 && pin.number <= 128 {
                counts[pin.number as usize] += 1;
                hub_count += 1;
            }
            if pin.net_id >= 0 {
                hub_nets[pin.net_id as usize] = true;
            }
        } else if !pin.nc && pin.net_id >= 0 {
            passive_counts[pin.net_id as usize] += 1;
        }
        i += 1;
    }
    let mut number = 1;
    while number <= 129 {
        offsets[number] = offsets[number - 1] + counts[number - 1];
        cursor[number] = offsets[number];
        number += 1;
    }
    let mut i = 0;
    while i < pins.len() {
        let pin = pins[i];
        if parts[pin.part].kind == 0 && !pin.nc && pin.number >= 1 && pin.number <= 128 {
            let slot = cursor[pin.number as usize];
            ordered[slot as usize] = i as i64;
            cursor[pin.number as usize] = slot + 1;
        }
        i += 1;
    }
    let mut i = 0;
    while i < pins.len() {
        let pin = pins[i];
        if parts[pin.part].kind != 0 && !pin.nc {
            let mut far = parts[pin.part].pin1;
            if far == i as i64 {
                far = parts[pin.part].pin2;
            }
            if far >= 0
                && pins[far as usize].raw_rail == 0
                && pins[far as usize].net_id >= 0
                && hub_nets[pins[far as usize].net_id as usize]
            {
                bridge_nets[pin.net_id as usize] = true;
            }
        }
        i += 1;
    }
    let mut seen_groups: Vec<i64> = Vec::new();
    let mut position = 0;
    while position < hub_count {
        let index = ordered[position] as usize;
        let pin = pins[index];
        let group = pin_group(pin, nets);
        let mut present = false;
        let mut n = 0;
        while n < seen_groups.len() {
            if seen_groups[n] == group {
                present = true;
            }
            n += 1;
        }
        if !present {
            seen_groups.push(group);
            let mut member = 0;
            while member < hub_count {
                let other_index = ordered[member] as usize;
                let other = pins[other_index];
                if other.part == pin.part && pin_group(other, nets) == group {
                    out.push(Row {
                        index: other_index,
                        group,
                        height: row_height(other, &passive_counts, &bridge_nets),
                        rail: other.rail,
                        side: 0,
                        y: 0,
                    });
                }
                member += 1;
            }
        }
        position += 1;
    }
    out
}

/// `layout.height`
fn layout_height(points: &[Point]) -> i64 {
    let mut bottom = 160;
    let mut i = 0;
    while i < points.len() {
        if points[i].y + 40 > bottom {
            bottom = points[i].y + 40;
        }
        i += 1;
    }
    bottom
}

/// `layout.placeRows`
fn place_rows(rows: &mut [Row]) {
    let mut total = 0;
    let mut i = 0;
    while i < rows.len() {
        let row = rows[i];
        total += row.height;
        if i == 0 || rows[i - 1].group != row.group {
            if row.rail == 1 {
                total += 16;
            }
            if row.rail == 2 {
                total += 56;
            }
        }
        i += 1;
    }
    let mut prefix = 0;
    let mut best = total * 100;
    let mut split = rows.len();
    let mut i = 0;
    while i + 1 < rows.len() {
        let row = rows[i];
        prefix += row.height;
        if i == 0 || rows[i - 1].group != row.group {
            if row.rail == 1 {
                prefix += 16;
            }
            if row.rail == 2 {
                prefix += 56;
            }
        }
        if rows[i].group != rows[i + 1].group {
            let mut delta = total * 48 - 100 * prefix;
            if delta < 0 {
                delta = -delta;
            }
            if delta < best {
                best = delta;
                split = i + 1;
            }
        }
        i += 1;
    }
    let mut y = 80;
    let mut i = 0;
    while i < rows.len() {
        if i == split {
            y = 80;
        }
        let row = rows[i];
        if i > 0 && i != split && rows[i - 1].group != row.group {
            if rows[i - 1].rail == 1 {
                y += 16;
            }
            if rows[i - 1].rail == 2 {
                y += 36;
            }
            if rows[i - 1].height == 80 {
                y += 16;
            }
        }
        if row.rail == 2 && (i == 0 || i == split || rows[i - 1].group != row.group) {
            y += 20;
        }
        let mut offset = 0;
        if row.height > 56 {
            offset = floor_div(row.height - 56, 2);
        }
        if row.height == 80 {
            offset = 20;
        }
        let side = if i >= split { 1 } else { -1 };
        rows[i].side = side;
        rows[i].y = y + offset;
        y += row.height;
        i += 1;
    }
}

/// `layout.nearest`
fn nearest(pin: Pin, parts: &[Part], pins: &[Pin], rows: &[Row], nets: &[Net]) -> i64 {
    let group = pin_group(pin, nets);
    let id = find_id(nets, pin.display_id);
    let mut owner: i64 = -1;
    if id >= 0 {
        owner = nets[id as usize].owner;
    }
    let mut fallback: i64 = -1;
    let mut i = 0;
    while i < rows.len() {
        let row = rows[i];
        let hub = pins[row.index];
        if pin.net_id == hub.net_id {
            return i as i64;
        }
        if row.index as i64 == owner {
            fallback = i as i64;
        }
        if row.group == group && fallback < 0 {
            fallback = i as i64;
        }
        i += 1;
    }
    let _ = parts;
    fallback
}

/// `layout.partPin`
fn part_pin(part: usize, number: i64, parts: &[Part], pins: &[Pin]) -> Pin {
    let mut index: i64 = -1;
    if number == 1 {
        index = parts[part].pin1;
    } else if number == 2 {
        index = parts[part].pin2;
    }
    if index >= 0
        && (index as usize) < pins.len()
        && pins[index as usize].part == part
        && pins[index as usize].number == number
    {
        return pins[index as usize];
    }
    let mut i = 0;
    while i < pins.len() {
        let pin = pins[i];
        if pin.part == part && pin.number == number {
            return pin;
        }
        i += 1;
    }
    Pin {
        part,
        number,
        net: EMPTY,
        nc: true,
        display: EMPTY,
        net_id: -1,
        display_id: -1,
        raw_rail: 0,
        rail: 0,
        decoupling: false,
    }
}

/// `layout.depth`
fn depth(pin: Pin, nets: &[Net]) -> i64 {
    let id = find_id(nets, pin.display_id);
    if id < 0 {
        return 4096;
    }
    nets[id as usize].distance
}

/// `layout.innerPin`
fn inner_pin(part: usize, parts: &[Part], pins: &[Pin], nets: &[Net]) -> Pin {
    let a = part_pin(part, 1, parts, pins);
    let b = part_pin(part, 2, parts, pins);
    if a.raw_rail != 0 && b.raw_rail == 0 {
        return b;
    }
    if b.raw_rail == 0 && depth(b, nets) < depth(a, nets) {
        return b;
    }
    a
}

/// `layout.bridge`
fn bridge(part: usize, parts: &[Part], pins: &[Pin], rows: &[Row], nets: &[Net]) -> bool {
    let a = part_pin(part, 1, parts, pins);
    let b = part_pin(part, 2, parts, pins);
    if a.raw_rail != 0 || b.raw_rail != 0 {
        return false;
    }
    if depth(a, nets) != depth(b, nets) {
        return false;
    }
    let ai = nearest(a, parts, pins, rows, nets);
    let bi = nearest(b, parts, pins, rows, nets);
    ai >= 0 && bi >= 0 && ai != bi
}

/// `layout.groundBranch`
fn ground_branch(part: usize, parts: &[Part], pins: &[Pin], nets: &[Net]) -> bool {
    let inner = inner_pin(part, parts, pins, nets);
    let outer = part_pin(part, 3 - inner.number, parts, pins);
    if outer.raw_rail == 1 {
        return true;
    }
    if outer.raw_rail == 2 {
        return false;
    }
    let mut found = false;
    let mut j = 0;
    while j < parts.len() {
        if parts[j].kind != 0 && j != part {
            let a = part_pin(j, 1, parts, pins);
            let b = part_pin(j, 2, parts, pins);
            let mut other_rail = 0;
            if a.net_id == outer.net_id {
                other_rail = b.raw_rail;
            }
            if b.net_id == outer.net_id {
                other_rail = a.raw_rail;
            }
            if other_rail == 2 {
                return false;
            }
            if other_rail == 1 {
                found = true;
            }
        }
        j += 1;
    }
    found
}

/// `layout.branch`
fn branch(
    part: usize,
    parts: &[Part],
    pins: &[Pin],
    rows: &[Row],
    nets: &[Net],
    remaining: i64,
) -> i64 {
    if remaining == 0 {
        return 0;
    }
    let inner = inner_pin(part, parts, pins, nets);
    let level = depth(inner, nets);
    let mut offset = 0;
    if level > 0 {
        let owner = nearest(inner, parts, pins, rows, nets);
        let mut j = 0;
        while j < parts.len() {
            if parts[j].kind != 0 && j != part {
                let previous = inner_pin(j, parts, pins, nets);
                if depth(previous, nets) < level
                    && nearest(previous, parts, pins, rows, nets) == owner
                {
                    let outer = part_pin(j, 3 - previous.number, parts, pins);
                    if outer.net_id == inner.net_id {
                        offset = branch(j, parts, pins, rows, nets, remaining - 1);
                        break;
                    }
                }
            }
            j += 1;
        }
    }
    let mut count = 0;
    let mut rank = 0;
    let mut has_bridge = false;
    let grounded = ground_branch(part, parts, pins, nets);
    let mut j = 0;
    while j < parts.len() {
        if parts[j].kind != 0 {
            let previous = inner_pin(j, parts, pins, nets);
            let a = part_pin(j, 1, parts, pins);
            let b = part_pin(j, 2, parts, pins);
            if bridge(j, parts, pins, rows, nets) {
                if a.net_id == inner.net_id || b.net_id == inner.net_id {
                    has_bridge = true;
                }
            } else if previous.net_id == inner.net_id {
                count += 1;
                let other_ground = ground_branch(j, parts, pins, nets);
                if level > 0 {
                    if (j as i64) < part as i64 {
                        rank += 1;
                    }
                } else if (other_ground && !grounded)
                    || (other_ground == grounded && (j as i64) < part as i64)
                {
                    rank += 1;
                }
            }
        }
        j += 1;
    }
    if level == 0 {
        let mut spacing = 20;
        if has_bridge {
            spacing = 40;
        }
        offset -= (count - 1) * spacing;
    }
    offset + rank * 40
}

/// `layout.endpoint`
fn endpoint(pin: Pin, parts: &[Part], pins: &[Pin], rows: &[Row], nets: &[Net]) -> Point {
    let inner = inner_pin(pin.part, parts, pins, nets);
    let chosen = nearest(inner, parts, pins, rows, nets);
    if chosen < 0 {
        return Point {
            x: 100 + pin.number * 60,
            y: 80 + pin.part as i64 * 60,
        };
    }
    let row = rows[chosen as usize];
    let mut edge = 352;
    if row.side == 1 {
        edge = 532;
    }
    let level = depth(inner, nets);
    if bridge(pin.part, parts, pins, rows, nets) {
        let target = nearest(pin, parts, pins, rows, nets);
        let other = rows[target as usize];
        let mut reach = 50;
        if level > 0 {
            reach = 170;
        }
        return Point {
            x: edge + row.side * reach,
            y: other.y,
        };
    }
    let hub = pins[row.index];
    let mut count = 0;
    let mut j = 0;
    while j < parts.len() {
        if parts[j].kind != 0 {
            let attached = inner_pin(j, parts, pins, nets);
            if attached.net_id == hub.net_id && !bridge(j, parts, pins, rows, nets) {
                count += 1;
            }
        }
        j += 1;
    }
    let mut reach = 40;
    if count > 1 {
        reach = 60;
    }
    if pin.number != inner.number {
        reach = 120;
    }
    let local_rail = inner.raw_rail == 2 && inner.display_id != inner.net_id;
    let mut y = row.y + branch(pin.part, parts, pins, rows, nets, 128);
    if local_rail {
        reach = 70;
        if pin.number != inner.number {
            reach = 110;
        }
        y += 20;
    }
    let x = edge + row.side * (reach + level * 60);
    Point { x, y }
}

/// `layout.build`
fn layout_build(parts: &[Part], pins: &[Pin]) -> Vec<Point> {
    let nets = graph_build(parts, pins);
    let mut out: Vec<Point> = Vec::with_capacity(pins.len());
    let mut ordered = collect_rows(parts, pins, &nets);
    place_rows(&mut ordered);
    let mut i = 0;
    while i < pins.len() {
        let pin = pins[i];
        let mut point = Point { x: -1, y: -1 };
        if parts[pin.part].kind == 0 {
            let mut j = 0;
            while j < ordered.len() {
                let row = ordered[j];
                if row.index == i {
                    let mut x = 352;
                    if row.side == 1 {
                        x = 532;
                    }
                    point = Point { x, y: row.y };
                }
                j += 1;
            }
        } else {
            point = endpoint(pin, parts, pins, &ordered, &nets);
        }
        out.push(point);
        i += 1;
    }
    out
}

// ── routes ───────────────────────────────────────────────────────────

#[derive(Clone, Copy)]
struct Segment {
    x1: i64,
    y1: i64,
    x2: i64,
    y2: i64,
    net: Span,
    // Recorded by the router but never read by the SVG writer, exactly as in
    // the guest's Segment.
    #[allow(dead_code)]
    junction: bool,
    terminal: bool,
}

#[inline]
fn manhattan(a: Point, b: Point) -> i64 {
    let mut x = a.x - b.x;
    let mut y = a.y - b.y;
    if x < 0 {
        x = -x;
    }
    if y < 0 {
        y = -y;
    }
    x + y
}

/// `layout_routes.external`
fn external(ctx: &Ctx, net: Span, connections: &[Port]) -> bool {
    let target = Port {
        prefix: EMPTY,
        name: net,
        direction: EMPTY,
    };
    let mut i = 0;
    while i < connections.len() {
        if port_equal(ctx, target, connections[i]) {
            return true;
        }
        i += 1;
    }
    false
}

/// `layout_routes.blocked`
fn blocked(
    a: Point,
    b: Point,
    net_id: i64,
    pins: &[Pin],
    points: &[Point],
) -> bool {
    let mut i = 0;
    while i < pins.len() {
        let pin = pins[i];
        let q = points[i];
        let mut intersects = false;
        if a.x == b.x
            && q.x == a.x
            && ((q.y >= a.y && q.y <= b.y) || (q.y >= b.y && q.y <= a.y))
        {
            intersects = true;
        }
        if a.y == b.y
            && q.y == a.y
            && ((q.x >= a.x && q.x <= b.x) || (q.x >= b.x && q.x <= a.x))
        {
            intersects = true;
        }
        if intersects && !pin.nc && pin.display_id != net_id {
            if a.x == b.x {
                return true;
            }
            if a.y == b.y {
                return true;
            }
        }
        i += 1;
    }
    false
}

/// `layout_routes.build`
fn routes_build(
    ctx: &Ctx,
    parts: &[Part],
    pins: &[Pin],
    points: &[Point],
    connections: &[Port],
) -> Vec<Segment> {
    let mut out: Vec<Segment> = Vec::new();
    let mut i = 0;
    while i < pins.len() {
        let pin = pins[i];
        let point = points[i];
        if !pin.nc {
            let display = pin.display;
            let is_ground = pin.raw_rail == 1;
            let coupled_ground = pin.decoupling;
            let local_ground = is_ground && parts[pin.part].kind != 0 && !coupled_ground;
            let is_rail = pin.rail != 0 && !is_ground;
            let standalone_rail =
                is_rail && parts[pin.part].kind != 0 && pin.net_id == pin.display_id;
            let mut nearest_index: i64 = -1;
            let mut shortest = 1000000;
            let mut count = 0;
            let mut j = 0;
            while j < pins.len() {
                let other = pins[j];
                let other_point = points[j];
                let other_standalone =
                    is_rail && parts[other.part].kind != 0 && other.net_id == pin.display_id;
                let allowed = (!is_ground
                    || (coupled_ground && other.decoupling)
                    || (!coupled_ground && parts[other.part].kind == 0))
                    && !other_standalone;
                if !other.nc && allowed && pin.display_id == other.display_id {
                    count += 1;
                    if (j as i64) < i as i64 && manhattan(point, other_point) < shortest {
                        nearest_index = j as i64;
                        shortest = manhattan(point, other_point);
                    }
                }
                j += 1;
            }
            if nearest_index < 0
                && count > 1
                && (is_ground || is_rail)
                && !local_ground
                && !standalone_rail
            {
                let mut low = point.y;
                let mut high = point.y;
                let mut k = 0;
                while k < pins.len() {
                    let other = pins[k];
                    if !other.nc
                        && ((coupled_ground && other.decoupling)
                            || (!coupled_ground && parts[other.part].kind == 0))
                        && pin.display_id == other.display_id
                    {
                        let q = points[k];
                        if q.y < low {
                            low = q.y;
                        }
                        if q.y > high {
                            high = q.y;
                        }
                    }
                    k += 1;
                }
                let mut side = -1;
                if point.x > 442 {
                    side = 1;
                }
                let mut y = floor_div(low + high, 2);
                if is_rail {
                    y = low - 20;
                }
                if coupled_ground {
                    y = high;
                }
                let mut bus = point.x + side * 40;
                if coupled_ground {
                    bus = point.x + side * 20;
                }
                out.push(Segment {
                    x1: bus,
                    y1: point.y,
                    x2: bus,
                    y2: y,
                    net: display,
                    junction: false,
                    terminal: false,
                });
                let mut reach = 100;
                if coupled_ground {
                    reach = 10;
                }
                out.push(Segment {
                    x1: bus,
                    y1: y,
                    x2: bus + side * reach,
                    y2: y,
                    net: display,
                    junction: false,
                    terminal: true,
                });
            }
            if nearest_index < 0
                && count > 1
                && !is_ground
                && !is_rail
                && external(ctx, display, connections)
            {
                let mut dx = 24;
                if point.x < 442 {
                    dx = -24;
                }
                out.push(Segment {
                    x1: point.x,
                    y1: point.y,
                    x2: point.x + dx,
                    y2: point.y,
                    net: display,
                    junction: false,
                    terminal: true,
                });
            }
            if local_ground || standalone_rail || count == 1 {
                let mut dx = 24;
                if parts[pin.part].kind == 0 {
                    dx = 140;
                    if !external(ctx, display, connections) && !is_rail && !is_ground {
                        dx = 50;
                    }
                }
                if point.x < 442 {
                    dx = -dx;
                }
                out.push(Segment {
                    x1: point.x,
                    y1: point.y,
                    x2: point.x + dx,
                    y2: point.y,
                    net: display,
                    junction: false,
                    terminal: true,
                });
            } else if nearest_index >= 0 {
                let previous = points[nearest_index as usize];
                if is_ground
                    || (point.x == previous.x && (point.x == 352 || point.x == 532))
                {
                    let mut bus = point.x - 40;
                    if point.x > 442 {
                        bus = point.x + 40;
                    }
                    if coupled_ground {
                        bus = point.x - 20;
                        if point.x > 442 {
                            bus = point.x + 20;
                        }
                    }
                    out.push(Segment {
                        x1: point.x,
                        y1: point.y,
                        x2: bus,
                        y2: point.y,
                        net: display,
                        junction: false,
                        terminal: false,
                    });
                    out.push(Segment {
                        x1: bus,
                        y1: point.y,
                        x2: bus,
                        y2: previous.y,
                        net: display,
                        junction: true,
                        terminal: false,
                    });
                    out.push(Segment {
                        x1: bus,
                        y1: previous.y,
                        x2: previous.x,
                        y2: previous.y,
                        net: display,
                        junction: false,
                        terminal: false,
                    });
                } else if is_rail && parts[pin.part].kind != 0 {
                    let mut bus = 302;
                    if point.x > 442 {
                        bus = 582;
                    }
                    out.push(Segment {
                        x1: point.x,
                        y1: point.y,
                        x2: bus,
                        y2: point.y,
                        net: display,
                        junction: false,
                        terminal: false,
                    });
                    out.push(Segment {
                        x1: bus,
                        y1: point.y,
                        x2: bus,
                        y2: previous.y,
                        net: display,
                        junction: false,
                        terminal: false,
                    });
                    out.push(Segment {
                        x1: bus,
                        y1: previous.y,
                        x2: previous.x,
                        y2: previous.y,
                        net: display,
                        junction: false,
                        terminal: false,
                    });
                } else if parts[pins[nearest_index as usize].part].kind == 0
                    && point.y != previous.y
                {
                    let mut side = 1;
                    if previous.x < 442 {
                        side = -1;
                    }
                    let bus = previous.x + side * 50;
                    out.push(Segment {
                        x1: point.x,
                        y1: point.y,
                        x2: bus,
                        y2: point.y,
                        net: display,
                        junction: false,
                        terminal: false,
                    });
                    out.push(Segment {
                        x1: bus,
                        y1: point.y,
                        x2: bus,
                        y2: previous.y,
                        net: display,
                        junction: false,
                        terminal: false,
                    });
                    out.push(Segment {
                        x1: bus,
                        y1: previous.y,
                        x2: previous.x,
                        y2: previous.y,
                        net: display,
                        junction: false,
                        terminal: false,
                    });
                } else if point.x == previous.x
                    && blocked(point, previous, pin.display_id, pins, points)
                {
                    let mut offset = 16;
                    let mut lane = point.x + offset;
                    let mut lane_start = Point {
                        x: lane,
                        y: point.y,
                    };
                    let mut lane_end = Point {
                        x: lane,
                        y: previous.y,
                    };
                    while blocked(lane_start, lane_end, pin.display_id, pins, points) && offset < 160 {
                        offset += 16;
                        lane = point.x + offset;
                        lane_start.x = lane;
                        lane_end.x = lane;
                    }
                    out.push(Segment {
                        x1: point.x,
                        y1: point.y,
                        x2: lane,
                        y2: point.y,
                        net: display,
                        junction: false,
                        terminal: false,
                    });
                    out.push(Segment {
                        x1: lane,
                        y1: point.y,
                        x2: lane,
                        y2: previous.y,
                        net: display,
                        junction: false,
                        terminal: false,
                    });
                    out.push(Segment {
                        x1: lane,
                        y1: previous.y,
                        x2: previous.x,
                        y2: previous.y,
                        net: display,
                        junction: false,
                        terminal: false,
                    });
                } else {
                    out.push(Segment {
                        x1: point.x,
                        y1: point.y,
                        x2: previous.x,
                        y2: point.y,
                        net: display,
                        junction: count > 2,
                        terminal: false,
                    });
                    if point.y != previous.y {
                        out.push(Segment {
                            x1: previous.x,
                            y1: point.y,
                            x2: previous.x,
                            y2: previous.y,
                            net: display,
                            junction: count > 2,
                            terminal: false,
                        });
                    }
                }
            }
        }
        i += 1;
    }
    out
}

// ── SVG ──────────────────────────────────────────────────────────────

/// `draw.rect`
fn draw_rect(out: &mut Out, x: i64, y: i64, w: i64, h: i64) {
    out.write(b"<rect class=\"chip\" x=\"");
    out.decimal(x);
    out.write(b"\" y=\"");
    out.decimal(y);
    out.write(b"\" width=\"");
    out.decimal(w);
    out.write(b"\" height=\"");
    out.decimal(h);
    out.write(b"\" rx=\"6\"/>");
}

/// `draw.line`
fn draw_line(out: &mut Out, x1: i64, y1: i64, x2: i64, y2: i64) {
    out.write(b"<line x1=\"");
    out.decimal(x1);
    out.write(b"\" y1=\"");
    out.decimal(y1);
    out.write(b"\" x2=\"");
    out.decimal(x2);
    out.write(b"\" y2=\"");
    out.decimal(y2);
    out.write(b"\"/>");
}

/// `draw.labelStart`
fn draw_label_start(out: &mut Out, x: i64, y: i64, anchor: i64) {
    out.write(b"<text x=\"");
    out.decimal(x);
    out.write(b"\" y=\"");
    out.decimal(y);
    out.write(b"\" text-anchor=\"");
    if anchor == 0 {
        out.write(b"start");
    } else if anchor == 1 {
        out.write(b"middle");
    } else {
        out.write(b"end");
    }
    out.write(b"\">");
}

/// `draw.labelEnd`
fn draw_label_end(out: &mut Out) {
    out.write(b"</text>");
}

/// `draw.label`
fn draw_label(out: &mut Out, ctx: &Ctx, x: i64, y: i64, anchor: i64, value: Span) {
    draw_label_start(out, x, y, anchor);
    out.escaped(ctx, value);
    draw_label_end(out);
}

/// `draw.symbol`
fn draw_symbol(out: &mut Out, kind: i64) {
    out.write(b"<g class=\"symbol\">");
    draw_line(out, -20, 0, -12, 0);
    draw_line(out, 12, 0, 20, 0);
    if kind == 1 {
        draw_line(out, -3, -6, -3, 6);
        draw_line(out, 3, -6, 3, 6);
        draw_line(out, -12, 0, -3, 0);
        draw_line(out, 3, 0, 12, 0);
    } else if kind == 2 {
        out.write(b"<rect x=\"-12\" y=\"-5\" width=\"24\" height=\"10\"/>");
    } else {
        out.write(
            b"<path d=\"M -12 0 c 0,-7 6,-7 6,0 c 0,-7 6,-7 6,0 c 0,-7 6,-7 6,0 c 0,-7 6,-7 6,0\"/>",
        );
    }
    out.write(b"</g>");
}

/// `svg.instanceStart`
fn instance_start(out: &mut Out, ctx: &Ctx, item: Part) {
    out.write(b"<g class=\"component\" data-ref=\"");
    out.escaped(ctx, item.reference);
    out.write(b"\" data-family=\"");
    out.escaped(ctx, item.family);
    out.write(b"\" data-value=\"");
    out.escaped(ctx, item.value);
    out.write(b"\"><title>");
    out.escaped(ctx, item.reference);
    out.write(" — ".as_bytes());
    out.escaped(ctx, item.family);
    out.write(b" ");
    out.escaped(ctx, item.value);
    out.write(b"</title>");
}

/// `svg.pinStart`
fn pin_start(out: &mut Out, ctx: &Ctx, pin: Pin, display: Span, point: Point) {
    out.write(b"<g data-pin=\"");
    out.decimal(pin.number);
    out.write(b"\" data-x=\"");
    out.decimal(point.x);
    out.write(b"\" data-y=\"");
    out.decimal(point.y);
    if pin.nc {
        out.write(b"\" data-nc=\"true\"><title>");
        out.escaped(ctx, pin.net);
        out.write(b"</title>");
    } else {
        out.write(b"\" data-net=\"");
        out.escaped(ctx, pin.net);
        out.write(b"\" data-electrical-net=\"");
        out.escaped(ctx, display);
        out.write(b"\">");
    }
}

/// `svg.finishGroup`
fn finish_group(out: &mut Out) {
    out.write(b"</g>");
}

/// `svg.displayRef`
fn display_ref(out: &mut Out, parts: &[Part], index: usize) {
    let item = parts[index];
    let mut n = 0;
    let mut i = 0;
    while i <= index {
        if parts[i].kind == item.kind {
            n += 1;
        }
        i += 1;
    }
    if item.kind == 0 {
        out.write(b"U");
    } else if item.kind == 1 {
        out.write(b"C");
    } else if item.kind == 2 {
        out.write(b"R");
    } else {
        out.write(b"L");
    }
    out.decimal(n);
}

/// `svg.passive`
fn passive(out: &mut Out, ctx: &Ctx, index: usize, parts: &[Part], pins: &[Pin], points: &[Point]) {
    let item = parts[index];
    let mut a = Point { x: 0, y: 0 };
    let mut b = a;
    let mut i = 0;
    while i < pins.len() {
        let pin = pins[i];
        if pin.part == index {
            if pin.number == 1 {
                a = points[i];
            } else {
                b = points[i];
            }
        }
        i += 1;
    }
    let x = floor_div(a.x + b.x, 2);
    let y = floor_div(a.y + b.y, 2);
    instance_start(out, ctx, item);
    out.write(b"<g transform=\"translate(");
    out.decimal(x);
    out.write(b" ");
    out.decimal(y);
    out.write(b")");
    if a.x == b.x {
        out.write(b" rotate(90)");
    }
    out.write(b"\"><rect class=\"symbol-clear\" x=\"-20\" y=\"-9\" width=\"40\" height=\"18\"/>");
    draw_symbol(out, item.kind);
    finish_group(out);
    if a.x == b.x {
        let mut top = a.y;
        let mut bottom = b.y;
        if top > bottom {
            top = b.y;
            bottom = a.y;
        }
        draw_line(out, x, top, x, y - 20);
        draw_line(out, x, y + 20, x, bottom);
        draw_label_start(out, x + 10, y + 3, 0);
    } else {
        let mut left = a.x;
        let mut right = b.x;
        if left > right {
            left = b.x;
            right = a.x;
        }
        draw_line(out, left, y, x - 20, y);
        draw_line(out, x + 20, y, right, y);
        draw_label_start(out, x, y - 14, 1);
    }
    display_ref(out, parts, index);
    out.write(b" ");
    out.escaped(ctx, item.value);
    draw_label_end(out);
    let mut i = 0;
    while i < pins.len() {
        let pin = pins[i];
        if pin.part == index {
            pin_start(out, ctx, pin, pin.display, points[i]);
            finish_group(out);
        }
        i += 1;
    }
    finish_group(out);
}

/// `svg.chip`
fn chip(
    out: &mut Out,
    ctx: &Ctx,
    index: usize,
    parts: &[Part],
    pins: &[Pin],
    points: &[Point],
    pinout: &[Node],
) {
    instance_start(out, ctx, parts[index]);
    draw_rect(out, 352, 20, 180, layout_height(points) - 40);
    draw_label_start(out, 442, 38, 1);
    display_ref(out, parts, index);
    out.write(b" ");
    out.escaped(ctx, parts[index].family);
    draw_label_end(out);
    let mut i = 0;
    while i < pins.len() {
        let pin = pins[i];
        if pin.part == index {
            let point = points[i];
            pin_start(out, ctx, pin, pin.display, points[i]);
            if !pin.nc {
                let mut side = -1;
                let mut anchor = 0;
                if point.x > 442 {
                    side = 1;
                    anchor = 2;
                }
                draw_line(out, point.x, point.y, point.x + side * 40, point.y);
                draw_label(
                    out,
                    ctx,
                    point.x - side * 8,
                    point.y + 4,
                    anchor,
                    pinout_label(ctx, pinout, pin.number),
                );
                draw_label_start(out, point.x + side * 3, point.y - 3, 1);
                out.decimal(pin.number);
                draw_label_end(out);
            }
            finish_group(out);
        }
        i += 1;
    }
    finish_group(out);
}

/// `svg.portName`
fn port_name(out: &mut Out, ctx: &Ctx, item: Port) {
    if item.prefix.start != item.prefix.end {
        out.escaped(ctx, item.prefix);
        out.write(b"_");
    }
    out.escaped(ctx, item.name);
}

/// `svg.ports`
fn svg_ports(out: &mut Out, ctx: &Ctx, connections: &[Port]) {
    let mut i = 0;
    while i < connections.len() {
        let item = connections[i];
        out.write(b"<g class=\"port\" data-port=\"");
        port_name(out, ctx, item);
        out.write(b"\" data-direction=\"");
        out.escaped(ctx, item.direction);
        out.write(b"\"><title>");
        port_name(out, ctx, item);
        out.write(b"</title></g>");
        i += 1;
    }
}

/// `svg.ground`
fn svg_ground(ctx: &Ctx, net: Span) -> bool {
    ctx.matches(net, b"GND")
}

/// `svg.routes`
fn svg_routes(out: &mut Out, ctx: &Ctx, segments: &[Segment], connections: &[Port]) {
    let mut i = 0;
    while i < segments.len() {
        let item = segments[i];
        out.write(b"<g class=\"wire\" data-net=\"");
        out.escaped(ctx, item.net);
        out.write(b"\">");
        draw_line(out, item.x1, item.y1, item.x2, item.y2);
        if item.terminal {
            if svg_ground(ctx, item.net) {
                out.write(b"<g class=\"ground\">");
                draw_line(out, item.x2, item.y2, item.x2, item.y2 + 6);
                draw_line(out, item.x2 - 7, item.y2 + 6, item.x2 + 7, item.y2 + 6);
                draw_line(out, item.x2 - 4, item.y2 + 9, item.x2 + 4, item.y2 + 9);
                draw_line(out, item.x2 - 1, item.y2 + 12, item.x2 + 1, item.y2 + 12);
                finish_group(out);
            } else if !external(ctx, item.net, connections) && rail_kind(ctx, item.net) == 0 {
                out.write(b"<g class=\"dangling-marker\">");
                draw_line(out, item.x2 - 4, item.y2 - 4, item.x2 + 4, item.y2 + 4);
                draw_line(out, item.x2 - 4, item.y2 + 4, item.x2 + 4, item.y2 - 4);
                finish_group(out);
            } else {
                let mut side = 1;
                let mut anchor = 0;
                if item.x2 < 442 {
                    side = -1;
                    anchor = 2;
                }
                out.write(b"<g class=\"net-label\">");
                draw_label(out, ctx, item.x2 + side * 12, item.y2 + 4, anchor, item.net);
                finish_group(out);
            }
        }
        finish_group(out);
        i += 1;
    }
}

/// `svg.render`
fn render(ctx: &Ctx, drawing: &Drawing) -> Vec<u8> {
    let parts = &drawing.parts;
    let pins = &drawing.pins;
    let tl = std::time::Instant::now();
    let points = layout_build(parts, pins);
    let tr = std::time::Instant::now();
    let segments = routes_build(ctx, parts, pins, &points, &drawing.connections);
    eprintln!("PHASE layout ns={}", (tr-tl).as_nanos());
    eprintln!("PHASE routes ns={}", tr.elapsed().as_nanos());
    let mut out = Out::new(64 * 1024);
    out.write(b"<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 884 ");
    out.decimal(layout_height(&points));
    out.write(b"\" width=\"884\" height=\"");
    out.decimal(layout_height(&points));
    out.write(b"\" role=\"img\"><title>");
    out.escaped(ctx, title(ctx, &drawing.nodes));
    out.write(b"</title><style>svg{background:#0d1117}text{font-family:Arial,sans-serif;font-size:11px;fill:#aaa;stroke:none}line,path{stroke:#4a9;stroke-width:1.5;fill:none}.chip{fill:#16213e;stroke:#4a9eff;stroke-width:2}.symbol rect,.symbol path,.symbol line{fill:none;stroke:#8888cc;stroke-width:1.5}.component>text{font-size:9px;fill:#888}.component>text:first-of-type{font-size:9px}.component:has(.chip)>text{fill:#4a9eff;font-size:12px;font-weight:bold}[data-pin]>line{stroke:#666}[data-pin]>text{font-size:12px}[data-pin]>text:last-child{font-size:9px;fill:#666}.symbol-clear{fill:#0d1117;stroke:none}.ground line{stroke:#d6bb24}.dangling-marker line{stroke:#666}.net-label text{fill:#4a9eff;font-size:11px;font-weight:bold}[data-nc]{display:none}</style><rect width=\"100%\" height=\"100%\" fill=\"#0d1117\"/>");
    svg_routes(&mut out, ctx, &segments, &drawing.connections);
    let mut i = 0;
    while i < parts.len() {
        if parts[i].kind == 0 {
            chip(&mut out, ctx, i, parts, pins, &points, &drawing.pinout);
        }
        i += 1;
    }
    let mut i = 0;
    while i < parts.len() {
        if parts[i].kind != 0 {
            passive(&mut out, ctx, i, parts, pins, &points);
        }
        i += 1;
    }
    svg_ports(&mut out, ctx, &drawing.connections);
    out.write(b"</svg>");
    out.bytes
}

// ── schematic.build and main ─────────────────────────────────────────

struct Drawing {
    nodes: Vec<Node>,
    parts: Vec<Part>,
    pins: Vec<Pin>,
    pinout: Vec<Node>,
    connections: Vec<Port>,
}

fn build(
    ctx: &Ctx,
    nodes: Vec<Node>,
    pinout: Vec<Node>,
    interface: Vec<Node>,
) -> Result<Drawing, i64> {
    let source_error = validate_source(ctx, &nodes);
    if source_error != 0 {
        return Err(source_error);
    }
    let mut parts = collect_parts(ctx, &nodes)?;
    let pinout_error = pinout_check(ctx, &pinout);
    if pinout_error != 0 {
        return Err(pinout_error);
    }
    let mut pins = collect_pins(ctx, &nodes, &parts, &pinout)?;
    let model_error = validate_model(ctx, &nodes, &parts, &pins, &pinout);
    if model_error != 0 {
        return Err(model_error);
    }
    normalize(ctx, &mut parts, &mut pins);
    let connections = ports_collect(ctx, &nodes, &interface)?;
    let ports_error = ports_validate(ctx, &connections, &pins);
    if ports_error != 0 {
        return Err(ports_error);
    }
    Ok(Drawing {
        nodes,
        parts,
        pins,
        pinout,
        connections,
    })
}

fn main() {
    let args: Vec<String> = env::args().collect();
    if args.len() != 5 {
        let mut stderr = std::io::stderr();
        let _ = writeln!(
            stderr,
            "usage: {} <module.sexp> <pinout.sexp> <interface.sexp> <output.svg>",
            args.first().map(String::as_str).unwrap_or("schematic")
        );
        process::exit(2);
    }
    let tr0 = std::time::Instant::now();
    let mut docs: Vec<Vec<u8>> = Vec::with_capacity(3);
    for path in &args[1..4] {
        match fs::read(path) {
            Ok(bytes) => docs.push(bytes),
            Err(error) => {
                eprintln!("schematic: {path}: {error}");
                process::exit(2);
            }
        }
    }
    eprintln!("PHASE read ns={}", tr0.elapsed().as_nanos());
    let ctx = Ctx { docs };
    let outcome = (|| -> Result<Vec<u8>, i64> {
        let t0 = std::time::Instant::now();
        let nodes = parse(&ctx, 0)?;
        let pinout = parse(&ctx, 1)?;
        let interface = parse(&ctx, 2)?;
        let t1 = std::time::Instant::now();
        let drawing = build(&ctx, nodes, pinout, interface)?;
        let t2 = std::time::Instant::now();
        let svg = render(&ctx, &drawing);
        let t3 = std::time::Instant::now();
        eprintln!("PHASE parse ns={}", (t1-t0).as_nanos());
        eprintln!("PHASE model ns={}", (t2-t1).as_nanos());
        eprintln!("PHASE render ns={}", (t3-t2).as_nanos());
        Ok(svg)
    })();
    match outcome {
        Ok(svg) => {
            let tw = std::time::Instant::now();
            if let Err(error) = fs::write(&args[4], &svg) {
                eprintln!("schematic: {}: {error}", args[4]);
                process::exit(2);
            }
            eprintln!("PHASE write ns={}", tw.elapsed().as_nanos());
        }
        Err(code) => {
            // The mylang guest reports its first located issue as the printed
            // result and as the process status; mirror that exactly so the
            // malformed-input differential can compare the two implementations.
            println!("{code}");
            process::exit(code as i32);
        }
    }
}
