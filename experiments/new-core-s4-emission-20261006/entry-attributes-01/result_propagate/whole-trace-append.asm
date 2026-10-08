
.mylang-cache/s4-emission/paired-entry-import-01-whole/row_result_propagate:     file format elf64-x86-64


Disassembly of section .text:

000000000103274a <myl_core_err_trace_append_preserve_most>:
 103274a:	55                   	push   %rbp
 103274b:	48 89 e5             	mov    %rsp,%rbp
 103274e:	51                   	push   %rcx
 103274f:	50                   	push   %rax
 1032750:	4c 8d 1d 81 5e 02 00 	lea    0x25e81(%rip),%r11        # 10585d8 <error_trace>
 1032757:	48 8b 05 82 5e 02 00 	mov    0x25e82(%rip),%rax        # 10585e0 <error_trace+0x8>
 103275e:	48 8d 48 01          	lea    0x1(%rax),%rcx
 1032762:	83 e0 1f             	and    $0x1f,%eax
 1032765:	49 89 7c c3 10       	mov    %rdi,0x10(%r11,%rax,8)
 103276a:	48 89 0d 6f 5e 02 00 	mov    %rcx,0x25e6f(%rip)        # 10585e0 <error_trace+0x8>
 1032771:	58                   	pop    %rax
 1032772:	59                   	pop    %rcx
 1032773:	5d                   	pop    %rbp
 1032774:	c3                   	ret

Disassembly of section .init:

Disassembly of section .fini:

Disassembly of section .plt:
