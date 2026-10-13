# Read-only scalar native observations

Exact measured scalar binary/LLVM is pinned by ../scalar-ip-001/structural.json. heap.push and heap.pop have emitted LLVM definitions but no native nm symbols: native run has inlined them. heap.pop nominal sret[208] definition actually stores only 16 bytes of Value into the return buffer; Runtime updates use the incoming pointer. Thus the nominal mutation return size does not establish a whole Runtime copy.

Native scalar run.asm has no memcpy, memmove, rep-move or packed movups/movaps record copy instructions. This is not proof that all stores are necessary, but it rejects the proposed whole-record copying explanation based solely on source/LLVM signature appearances. The dispatch path intentionally retains four CallFrame publication stores at 105b167 through 105b17b, after read_byte returns byte and IP in rax/rdx. IP-only publication previously regressed and remains rejected.

No further source experiment is proposed from these appearances. The next pinned CPU profile is needed to attribute remaining checked stack access, reader, call or other costs. profile.py is syntax checked, and awaits coordinator timing authorization.
