#!/usr/bin/env python3
"""Group a prof.sh instructions report's symbols into cost classes (shares in %).
usage: symgroups.py REPORT.txt..."""
import re, sys
GROUPS = [
    ("allocation/free", re.compile(r"block_alloc|free_block|block_free|reference_at|small_alloc|myl_core_free|list_new_slow|list_grow|aligned_alloc|malloc|^free$|realloc|core_dict_free")),
    ("text materialize/copy", re.compile(r"str_slice|str_from|bytes_slice|bytes_concat|str_concat|bytes_from_list|str_from_view|text_publish|memcpy|memmove|str_join|join_short|append_bytes")),
    ("search/split", re.compile(r"memmem|memchr|find_bytes|str_split|str_ends|str_starts|str_count|text_replace|str_chars|utf8_count")),
    ("hash/compare", re.compile(r"str_hash|span_hash|str_eq|bcmp|memcmp|dict_")),
    ("number text", re.compile(r"str_from_i64|parse_float|parseFloat|number")),
    ("sort", re.compile(r"sort")),
]
for path in sys.argv[1:]:
    shares = {g: 0.0 for g, _ in GROUPS}
    shares["compiled code / other"] = 0.0
    for line in open(path):
        m = re.match(r"\s+([0-9.]+)%\s+(\S+)\s+\[\.\]\s+(.*)", line)
        if not m: continue
        pct, dso, sym = float(m.group(1)), m.group(2), m.group(3).strip()
        if dso.startswith("libc") and sym.startswith("0x"): sym = "memcpy"  # unresolved libc: memcpy/memset family
        for g, rx in GROUPS:
            if rx.search(sym):
                shares[g] += pct; break
        else:
            shares["compiled code / other"] += pct
    print(path.split("/")[-1], "  ".join(f"{k}={v:.1f}" for k, v in shares.items() if v >= 0.05))
