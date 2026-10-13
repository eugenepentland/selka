from pathlib import Path
scratch=Path('/home/epentland/ai/canopy/mylang/.tmp/lox-eda-parity/P3/c2-001')
p=scratch/'candidate-v2/eda/sexpr_tokenizer.my';base=(scratch/'baseline/eda/sexpr_tokenizer.my').read_text();s=base
num_a=base.index('func read_number(');num_b=base.find('\n\n\n',num_a)
num_tail=base[base.index('    mut num_end = t.pos',num_a):num_b]
names=['skip_whitespace_and_comments','read_string','read_number','read_atom']
for name in names:
 a=base.index('func '+name+'(');b=base.find('\n\n\n',a)
 old=base[a:b].replace('func '+name+'(', 'func '+name+'_slow(',1)
 s=s.replace(base[a:b],old+'\n\n\n'+({'skip_whitespace_and_comments':'''# Scan in scalar locals: newline semantics remain byte-oriented, including CRLF.
func skip_whitespace_and_comments(src: bytes, mut t: Cursor):
    if not scan_counters_fit(src, t):
        skip_whitespace_and_comments_slow(src, mut t)
        return
    mut pos = t.pos
    mut line = t.line
    mut col = t.col
    mut size = len(src)
    while pos < size:
        mut c = src[pos]
        if c == ord(" ") or c == ord("\\t") or c == ord("\\r"):
            col += 1
            pos += 1
        elif c == ord("\\n"):
            line += 1
            col = 1
            pos += 1
        elif c == ord(";"):
            while pos < size and src[pos] != ord("\\n"):
                col += 1
                pos += 1
        else:
            break
    t.pos = pos
    t.line = line
    t.col = col''',
'read_string':'''func read_string(src: bytes, mut t: Cursor, s: ast.Span) -> Result[OffsetToken, LexError]:
    if not scan_counters_fit(src, t):
        return read_string_slow(src, mut t, s)
    mut pos = t.pos + 1
    mut start = pos
    mut line = t.line
    mut col = t.col + 1
    mut size = len(src)
    while pos < size:
        mut ch = src[pos]
        if ch == ord("\\\\"):
            pos += 1
            col += 1
            if pos >= size:
                break
            ch = src[pos]
        elif ch == ord("\\\""):
            mut end = pos
            t.pos = pos + 1
            t.line = line
            t.col = col + 1
            return Ok(make_token(TokenTag.string, start, end, s))
        if ch == ord("\\n"):
            line += 1
            col = 1
        else:
            col += 1
        pos += 1
    t.pos = pos
    t.line = line
    t.col = col
    t.error_span = s
    return Err(LexError.unterminated_string)''',
'read_atom':'''# Atom bytes never contain a newline. Commit the cursor once per complete run.
func read_atom(src: bytes, mut t: Cursor, s: ast.Span) -> OffsetToken:
    if not scan_counters_fit(src, t):
        return read_atom_slow(src, mut t, s)
    mut start = t.pos
    mut pos = start
    mut size = len(src)
    while pos < size and is_atom_continue(src[pos]):
        pos += 1
    t.col += pos - start
    t.pos = pos
    return make_token(TokenTag.atom, start, pos, s)''',
'read_number':'''func read_number(src: bytes, mut t: Cursor, s: ast.Span) -> OffsetToken:
    if not scan_counters_fit(src, t):
        return read_number_slow(src, mut t, s)
    mut start = t.pos
    mut pos = start
    mut size = len(src)
    if pos < size and src[pos] == ord("-"):
        pos += 1
    while pos < size and is_digit(src[pos]):
        pos += 1
    mut is_float = False
    if pos + 1 < size and src[pos] == ord(".") and is_digit(src[pos + 1]):
        is_float = True
        pos += 1
        while pos < size and is_digit(src[pos]):
            pos += 1
    t.col += pos - start
    t.pos = pos
'''+num_tail.replace('''        while is_atom_continue(peek(src, t)):
            advance(src, mut t)''','''        mut tail_start = t.pos
        mut tail_end = tail_start
        while tail_end < size and is_atom_continue(src[tail_end]):
            tail_end += 1
        t.col += tail_end - tail_start
        t.pos = tail_end''')})[name])
helper = """# The fast loops never approach a checked counter limit. Unusual public cursors
# retain the original stepwise updates, including which field overflows first.
func scan_counters_fit(src: bytes, t: Cursor) -> bool noalloc:
    return t.pos >= 0 and t.line <= 9223372036854775807 - len(src) and t.col <= 9223372036854775807 - len(src)


"""
s=s.replace('func skip_whitespace_and_comments_slow(',helper+'func skip_whitespace_and_comments_slow(',1)
p.write_text(s)
