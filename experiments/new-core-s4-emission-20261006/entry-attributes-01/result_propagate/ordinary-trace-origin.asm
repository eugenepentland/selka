
experiments/new-core-s4-emission-20261006/entry-attributes-01/result_propagate/ordinary_dependencies/program:     file format elf64-x86-64


Disassembly of section .text:

0000000001032bb2 <myl_core_err_trace_origin_preserve_most>:
 1032bb2:	55                   	push   %rbp
 1032bb3:	48 89 e5             	mov    %rsp,%rbp
 1032bb6:	48 89 3d 9b 66 02 00 	mov    %rdi,0x2669b(%rip)        # 1059258 <error_trace>
 1032bbd:	48 c7 05 98 66 02 00 	movq   $0x0,0x26698(%rip)        # 1059260 <error_trace+0x8>
 1032bc4:	00 00 00 00 
 1032bc8:	5d                   	pop    %rbp
 1032bc9:	c3                   	ret

Disassembly of section .init:

Disassembly of section .fini:

Disassembly of section .plt:
