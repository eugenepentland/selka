"""Exact C ABI signatures for runtime symbols used by the benchmark closure.

Types are LLVM source types, not QBE's pointer-sized spellings.  Keeping this
table checked in makes translation independent of compile order and prevents a
new runtime helper from silently receiving an integer-shaped declaration.
"""
import os
import re

P = "ptr"
I64 = "i64"
I32 = "i32"
V = "void"

SIGNATURES = {
    "myl_native_bytes_concat": ((P, P, P), P),
    "myl_native_bytes_encode": ((P, P), P),
    "myl_native_bytes_find": ((P, P), I64),
    "myl_native_bytes_join": ((P, P, P), P),
    "myl_native_bytes_slice": ((P, P, I64, I64), P),
    "myl_native_equal": ((P, P, P), I32),
    "myl_native_heap_alloc": ((P, P, I64), P),
    "myl_native_list_append": ((P, P, P), I32),
    "myl_native_list_clear": ((P,), I32),
    "myl_native_list_get": ((P, I64, P), I32),
    "myl_native_list_new": ((P, P, I64), P),
    "myl_native_number_parse": ((P, I64, I32, P), I32),
    "myl_native_text_at": ((P, P, I64), P),
    "myl_native_text_concat": ((P, P, P), P),
    "myl_native_text_edge": ((P, P, I32), I32),
    "myl_native_text_every": ((P, I32), I32),
    "myl_native_text_find": ((P, P), I64),
    "myl_native_text_join": ((P, P, P), P),
    "myl_native_text_scalar": ((P, P, I32), P),
    "myl_native_text_slice": ((P, P, I64, I64), P),
    "myl_qbe_bytes_decode_range": ((P, P, I64, I64, P), I32),
    "myl_qbe_bytes_decode": ((P, P, P), I32),
    "myl_qbe_bytes_from_list": ((P, P), P),
    "myl_qbe_fail_allocation": ((P,), V),
    "myl_qbe_fail_assert": ((P,), V),
    "myl_qbe_fail_cast": ((P, I64, I64), V),
    "myl_qbe_fail_empty_separator": ((P,), V),
    "myl_qbe_fail_division": ((P, I64, I64, I64), V),
    "myl_qbe_fail_equality": ((P, I32), V),
    "myl_qbe_fail_frame": ((P,), V),
    "myl_qbe_fail_index_bounds": ((P, I64, I64), V),
    "myl_qbe_fail_iteration": ((P,), V),
    "myl_qbe_fail_list_capacity": ((P,), V),
    "myl_qbe_fail_normalized_index_bounds": ((P, I64, I64), V),
    "myl_qbe_fail_overflow_op": ((P, I64, I64, I64, I64), V),
    "myl_qbe_fail_step": ((P,), V),
    "myl_qbe_fail_text_bounds_detail": ((P, I64, I64), V),
    "myl_qbe_file_access": ((P, I64, I32, P, P, P), I32),
    "myl_qbe_float_unary": ((P, I64, I64), I64),
    "myl_qbe_frame_allocate": ((P, I64), P),
    "myl_qbe_frame_release": ((P, P), V),
    "myl_qbe_heap": ((P,), P),
    "myl_qbe_int_neg": ((P, I64, I64, I64), I64),
    "myl_qbe_int_binary": ((P, I64, I64, I64, I64, I64), I64),
    "myl_qbe_print_byte": ((P, I32), V),
    "myl_qbe_require_frame_accounting": ((P,), V),
    "myl_qbe_require_step_accounting": ((P,), V),
    "myl_qbe_root_mark": ((P,), P),
    "myl_qbe_stream_begin": ((P, I64), P),
    "myl_qbe_stream_finish": ((P, P, I64), V),
    "myl_qbe_stream_write": ((P, I64, P), I64),
    "myl_qbe_stream_write_bytes": ((P, I64, P), I64),
}


def signature(name):
    if not isinstance(name, str):
        # A call whose target is computed at run time reaches here with the
        # parser's target object rather than a symbol; it has no C declaration to
        # look up, and asking for one must not raise.
        return None
    if name in SIGNATURES:
        return SIGNATURES[name]
    # Generated renderers have one stable C signature.
    if name.startswith("myl_r_"):
        return ((P, P, I32), V)
    return generated().get(name)


# ── Generated fallback ────────────────────────────────────────────────
# The table above is the frozen closure's curated manifest, and it stays the
# authority for everything it covers. Any runtime helper outside it — a new
# buffer or collection entry point, for example — is read from the header that
# declares it, so a helper cannot reach the backend with an invented signature
# and the table cannot silently fall out of date with `src/`.  A helper that
# exists only as a Zig `@export` has no header to read, so those declarations
# are read from the Zig source itself; otherwise every such entry point is
# invisible until someone hand-registers it, which is how the benchmark closure
# stopped building when the guest began calling `myl_native_bytes_buffer_append_float`.
_SRC = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))), "src")
_DECLARATION = re.compile(r"(?m)^[A-Za-z_][^\n;{}#]*?\b(\w+)\s*\(([^;{}]*?)\)\s*;")
_ZIG_EXPORT = re.compile(r"@export\(&(\w+)\s*,\s*\.\{\s*\.name\s*=\s*\"(\w+)\"")
_GENERATED = None
# Words that are part of a C type rather than a parameter's name, so an
# unnamed pointer parameter is not mistaken for a named one.
_TYPE_WORDS = frozenset("void char short int long float double signed unsigned const volatile size_t "
                        "int8_t int16_t int32_t int64_t uint8_t uint16_t uint32_t uint64_t".split())

#: Zig scalar spellings an exported C-ABI function may use, in LLVM terms.  A
#: type outside this table makes the whole declaration unusable rather than
#: guessed, so an unknown helper still refuses translation loudly.  Widths below
#: 32 bits occupy a 32-bit C argument register, the same shape `_llvm_type`
#: gives a C `char` or `short`.
_ZIG_TYPES = {
    "u8": I32, "i8": I32, "u16": I32, "i16": I32, "u32": I32, "i32": I32,
    "c_uint": I32, "c_int": I32, "c_short": I32, "c_ushort": I32,
    "c_char": I32, "c_schar": I32, "c_uchar": I32,
    "u64": I64, "i64": I64, "usize": I64, "isize": I64,
    "c_ulong": I64, "c_long": I64, "c_ulonglong": I64, "c_longlong": I64,
    "f32": "float", "f64": "double", "void": V,
}


def _zig_type(text):
    """One Zig parameter or result type in the backend's own spelling."""
    piece = text.strip()
    if "*" in piece:
        return P
    return _ZIG_TYPES.get(piece)


def _zig_parameters(text):
    """The parameter list of an exported Zig function, split at top level."""
    if not text.strip():
        return ()
    converted = []
    for part in text.split(","):
        # `heap: ?*anyopaque` names its parameter; a bare type does not.
        piece = part.split(":", 1)[1] if ":" in part else part
        converted.append(_zig_type(piece))
    return tuple(converted)


def _zig_declaration(text, name):
    """The parameter list and result type of `fn name(...)` in one Zig file."""
    match = re.search(r"(?m)^(?:pub )?fn\s+" + re.escape(name) + r"\s*\(", text)
    if not match:
        return None
    start = match.end() - 1
    depth = 0
    for index in range(start, len(text)):
        if text[index] == "(":
            depth += 1
        elif text[index] == ")":
            depth -= 1
            if depth == 0:
                tail = text[index + 1:].lstrip()
                if tail.startswith("callconv"):
                    tail = tail[tail.index(")") + 1:].lstrip()
                return text[start + 1:index], tail.split("{")[0].strip()
    return None


def _generated_zig():
    """Every runtime helper exported from Zig, read from its own declaration."""
    table = {}
    for entry in sorted(os.listdir(_SRC)):
        if not entry.endswith(".zig"):
            continue
        with open(os.path.join(_SRC, entry)) as handle:
            text = handle.read()
        if "@export" not in text:
            continue
        for match in _ZIG_EXPORT.finditer(text):
            function, symbol = match.group(1), match.group(2)
            if not (symbol.startswith("myl_native_") or symbol.startswith("myl_qbe_")):
                continue
            found = _zig_declaration(text, function)
            if found is None:
                continue
            parameters, result = found
            converted = _zig_parameters(parameters)
            result_type = _zig_type(result)
            if result_type is None or any(item is None for item in converted):
                continue
            table.setdefault(symbol, (converted, result_type))
    return table


def _llvm_type(text, pointer=False):
    """One C parameter or result type in the backend's own type spelling."""
    normalized = re.sub(r"\s+", " ", text).strip()
    # A pointer is not a named parameter, so this test comes before any name is
    # dropped: `void *` is a type and `void *value` is a named one.
    if pointer or normalized.endswith("*"):
        return P
    if normalized in ("void",):
        return V
    if normalized in ("float",):
        return "float"
    if normalized in ("double",):
        return "double"
    if normalized in ("int", "unsigned", "unsigned int", "int32_t", "uint32_t"):
        return I32
    if normalized in ("size_t", "int64_t", "uint64_t", "long", "unsigned long", "long long", "unsigned long long"):
        return I64
    if normalized in ("char", "signed char", "unsigned char", "short", "unsigned short", "int16_t", "uint16_t"):
        return I32
    return None


def _parameters(text):
    normalized = re.sub(r"\s+", " ", text).strip()
    if normalized in ("", "void"):
        return ()
    parts, depth, current = [], 0, ""
    for character in normalized:
        if character == "(":
            depth += 1
        elif character == ")":
            depth -= 1
        if character == "," and depth == 0:
            parts.append(current)
            current = ""
        else:
            current += character
    parts.append(current)
    converted = []
    for part in parts:
        # A parameter may name itself (`const void *value`), write the name
        # against its `*` (`void *context`), or leave the name out (`void *`).
        # Trailing `[]` is array syntax on the type rather than a name.
        piece = part.strip()
        if piece.endswith("[]"):
            piece = piece[:-2].strip()
        words = piece.split()
        # Every word but the first `*`-free one is part of the type; the last
        # word of a spelled-out declaration is the parameter's own name.
        if len(words) > 1:
            words = words[:-1]
        converted.append(_llvm_type(" ".join(words), pointer="*" in piece))
    return tuple(converted)


def generated():
    """Every remaining runtime helper's signature, read from its declaration."""
    global _GENERATED
    if _GENERATED is not None:
        return _GENERATED
    table = {}
    for entry in sorted(os.listdir(_SRC)):
        if not entry.endswith(".h"):
            continue
        with open(os.path.join(_SRC, entry)) as handle:
            text = handle.read()
        text = re.sub(r"/\*.*?\*/", " ", text, flags=re.S)
        text = re.sub(r"(?m)//.*$", " ", text)
        for match in _DECLARATION.finditer(text):
            name, parameters = match.group(1), match.group(2)
            if not (name.startswith("myl_native_") or name.startswith("myl_qbe_")):
                continue
            result_text = text[match.start():match.start(1)]
            result = _llvm_type(result_text.split()[-1] if result_text.split() else "void")
            converted = _parameters(parameters)
            if result is None or any(item is None for item in converted):
                continue
            table.setdefault(name, (converted, result))
    for name, signature in _generated_zig().items():
        table.setdefault(name, signature)
    _GENERATED = table
    return _GENERATED
