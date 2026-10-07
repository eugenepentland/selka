
experiments/new-core-s4-emission-20261006/entry-attributes-01/result_propagate/baseline/program:     file format elf64-x86-64


Disassembly of section .text:

00000000010326f2 <myl_core_err_trace_origin_preserve_most>:
 10326f2:	55                   	push   %rbp
 10326f3:	48 89 e5             	mov    %rsp,%rbp
 10326f6:	48 89 3d 6b 62 02 00 	mov    %rdi,0x2626b(%rip)        # 1058968 <error_trace>
 10326fd:	48 c7 05 68 62 02 00 	movq   $0x0,0x26268(%rip)        # 1058970 <error_trace+0x8>
 1032704:	00 00 00 00 
 1032708:	5d                   	pop    %rbp
 1032709:	c3                   	ret

Disassembly of section .init:

Disassembly of section .fini:

Disassembly of section .plt:
