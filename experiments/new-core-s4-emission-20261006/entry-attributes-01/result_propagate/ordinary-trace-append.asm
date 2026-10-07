
experiments/new-core-s4-emission-20261006/entry-attributes-01/result_propagate/ordinary_dependencies/program:     file format elf64-x86-64


Disassembly of section .text:

0000000001032bca <myl_core_err_trace_append_preserve_most>:
 1032bca:	55                   	push   %rbp
 1032bcb:	48 89 e5             	mov    %rsp,%rbp
 1032bce:	51                   	push   %rcx
 1032bcf:	50                   	push   %rax
 1032bd0:	4c 8d 1d 81 66 02 00 	lea    0x26681(%rip),%r11        # 1059258 <error_trace>
 1032bd7:	48 8b 05 82 66 02 00 	mov    0x26682(%rip),%rax        # 1059260 <error_trace+0x8>
 1032bde:	48 8d 48 01          	lea    0x1(%rax),%rcx
 1032be2:	83 e0 1f             	and    $0x1f,%eax
 1032be5:	49 89 7c c3 10       	mov    %rdi,0x10(%r11,%rax,8)
 1032bea:	48 89 0d 6f 66 02 00 	mov    %rcx,0x2666f(%rip)        # 1059260 <error_trace+0x8>
 1032bf1:	58                   	pop    %rax
 1032bf2:	59                   	pop    %rcx
 1032bf3:	5d                   	pop    %rbp
 1032bf4:	c3                   	ret

Disassembly of section .init:

Disassembly of section .fini:

Disassembly of section .plt:
